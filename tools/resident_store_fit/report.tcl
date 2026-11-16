# Fit-only diagnostics. Does not change QSF, PLL HDL or the fitted database.
package require ::quartus::project
package require ::quartus::sta
project_open -revision Template Template
set root output_files/timing/resident-store
file mkdir $root
set errors [open $root/errors.txt w]
proc checked {script} {
    global errors
    if {[catch {uplevel 1 $script} result]} {puts $errors "$script => $result";flush $errors;puts "DIAGNOSTIC_ERROR $script => $result";return "ERROR:$result"}
    return $result
}
proc clock_snapshot {} {
    set d [dict create]
    foreach_in_collection c [get_clocks *] {
        set master "";catch {set master [get_clock_info -master_clock $c]}
        dict set d [get_clock_info -name $c] [list [get_clock_info -period $c] [get_clock_info -waveform $c] $master [get_clock_info -nreg_pos $c] [get_clock_info -nreg_neg $c]]
    }
    return $d
}
proc retarget_core {} {
    # Preserve the derived clock names/targets, their original reference source,
    # relative phase/duty, all unrelated clocks, exceptions and I/O constraints.
    # Actual VCO=780 MHz -> analysis-only VCO=1040, unchanged /10 -> 104 MHz.
    set original [clock_snapshot]
    set vcos {};set outputs {}
    foreach_in_collection c [get_clocks *] {
        set n [get_clock_info -name $c]
        if {[string first "emu|pll|" $n] != 0} {continue}
        if {[string match {*~FRACTIONAL_PLL|vcoph*} $n]} {lappend vcos $c}
        if {[string match {*~PLL_OUTPUT_COUNTER*|divclk} $n]} {lappend outputs $c}
    }
    if {[llength $vcos]!=1 || [llength $outputs]!=1} {error "Expected one live core VCO/output, got $vcos / $outputs"}
    set vco [lindex $vcos 0]
    set n [get_clock_info -name $vco]
    set period [get_clock_info -period $vco]
    if {abs($period - 20.0*5/78)>0.002} {error "Unexpected control VCO period $period"}
    set src [get_clock_info -master_clock_pin $vco]
    set master [get_clock_info -master_clock $vco]
    set targets [get_clock_info -targets $vco]
    # Overwrite by same name/target; keep existing clock-group names meaningful.
    create_generated_clock -name $n -source $src -master_clock $master -multiply_by 104 -divide_by 5 -duty_cycle 50 $targets
    foreach c $outputs {
        set n [get_clock_info -name $c]
        set row [dict get $original $n]
        set old_period [lindex $row 0]
        set wave [lindex $row 1]
        if {abs($old_period - 1000.0/78)>0.002} {error "Unexpected core output period $old_period"}
        set phase [expr {360.0*[lindex $wave 0]/$old_period}]
        set duty [expr {100.0*([lindex $wave 1]-[lindex $wave 0])/$old_period}]
        create_generated_clock -name $n -source [get_clock_info -master_clock_pin $c] -master_clock [get_clock_info -master_clock $c] -multiply_by 1 -divide_by 10 -phase $phase -duty_cycle $duty [get_clock_info -targets $c]
    }
    derive_clock_uncertainty
    update_timing_netlist
    set changed [clock_snapshot]
    foreach n [dict keys $original] {
        if {![dict exists $changed $n]} {error "Clock disappeared: $n"}
        if {[string first "emu|pll|" $n] != 0 && [dict get $original $n] ne [dict get $changed $n]} {error "Unrelated clock changed: $n"}
        if {[lrange [dict get $original $n] 2 end] ne [lrange [dict get $changed $n] 2 end]} {error "Master/clock fanout changed: $n"}
    }
    foreach c $outputs {
        set n [get_clock_info -name $c]
        set p [lindex [dict get $changed $n] 0]
        if {abs($p-1000.0/104)>0.002} {error "104 MHz clock validation failed: $p"}
    }
    puts "PASS clock relationship/fanout preservation and 104 MHz period validation"
}
proc endpoint_csv {filename} {
    set f [open $filename w]
    puts $f "rank,slack_ns,data_delay_ns,logic_levels,from,to"
    set rank 0
    foreach_in_collection p [get_timing_paths -setup -npaths 1000 -nworst 1 -detail full_path] {
        incr rank
        set cells {}
        foreach v [list $rank [get_path_info -slack $p] [get_path_info -data_delay $p] [get_path_info -num_logic_levels $p] [get_node_info -name [get_path_info -from $p]] [get_node_info -name [get_path_info -to $p]]] {
            lappend cells "\"[string map [list \" \"\"] $v]\""
        }
        puts $f [join $cells ,]
    }
    close $f
}
proc emit {d} {
    file mkdir $d
    checked [list report_clocks -file $d/clocks.rpt]
    checked [list report_sdc -file $d/constraints.rpt]
    checked [list report_sdc -ignored -file $d/ignored-constraints.rpt]
    checked [list report_ucp -file $d/unconstrained.rpt]
    checked [list check_timing -include {no_clock multiple_clock generated_clock uncertainty loops latches no_input_delay no_output_delay partial_input_delay partial_output_delay pll_cross_check} -file $d/check-timing.rpt]
    checked [list report_clock_fmax_summary -file $d/fmax.rpt]
    foreach kind {setup hold recovery removal} {
        checked [list report_timing -$kind -npaths 100 -nworst 1 -detail full_path -show_routing -file $d/$kind.rpt]
        checked [list report_timing -$kind -npaths 1 -nworst 1 -file $d/$kind-summary.rpt]
    }
    checked [list report_min_pulse_width -nworst 100 -detail full_path -file $d/min-pulse.rpt]
    checked [list endpoint_csv $d/setup.csv]
    set groups [list \
        [list any_to_p1_tags {*} {*u_data_cache*probe_p1_tag_q*}] \
        [list any_to_p2_tags {*} {*u_data_cache*probe_p2_tag_q*}] \
        [list any_to_hint_valid {*} {*u_data_cache*probe_p1_valid_q* *u_data_cache*probe_p2_valid_q*}] \
        [list hints_to_ram_b {*u_data_cache*probe_p*_q*} {*u_data_cache*lines*portb*}] \
        [list certificate_to_ram_b {*u_data_cache*line_result*} {*u_data_cache*lines*portb*}] \
        [list any_to_ram_b {*} {*u_data_cache*lines*portb*}] \
        [list hints_to_result {*u_data_cache*probe_p*_q*} {*u_data_cache*probe_result*}] \
        [list certificate_to_result {*u_data_cache*line_result*} {*u_data_cache*probe_result*}] \
        [list any_to_result {*} {*u_data_cache*probe_result*}] \
        [list reset_to_downstream {*reset_drain*} {*u_data_cache*lines*portb* *u_data_cache*probe_result*}] \
        [list pipeline_to_downstream {*u_data_cache*pipe_owner* *u_data_cache*pipe_commit*} {*u_data_cache*lines*portb* *u_data_cache*probe_result*}] \
        [list completion_to_downstream {*u_data_completion*} {*u_data_cache*lines*portb* *u_data_cache*probe_result*}] \
        [list any_to_pipeline {*} {*cache*pipe_owner* *cache*pipe_commit* *cache*pipe_way* *cache*pipe_mask* *cache*pipe_data* *cache*pipe_mva*}] \
        [list certificate_to_owner {*cache*line_result*} {*cache*pipe_way* *cache*pipe_owner*}] \
        [list reset_to_store_payload {*reset_drain*} {*u_data_cache*pipe_mva* *u_data_cache*pipe_data* *u_data_cache*pipe_way* *u_data_cache*pipe_mask*}] \
        [list dirty_forwarding {*tags*commit_dirty* *tags*recent* *tags*commit_selected* *tags*commit_mva*} {*tags*commit_dirty* *tags*recent*}] \
        [list pipeline_to_any {*cache*pipe_owner* *cache*pipe_commit*} {*}] \
        [list result_to_any {*u_data_cache*probe_result*} {*}]]
    set summary [open $d/groups.txt w]
    foreach g $groups {
        lassign $g name from to
        set inventory [open $d/$name-keepers.txt w]
        foreach side {from to} patterns [list $from $to] {
            set count 0
            foreach_in_collection k [get_keepers -nowarn $patterns] {
                incr count
                # Avoid repeating the entire chip for unrestricted sides.
                if {$patterns ne "*"} {puts $inventory "$side [get_node_info -name $k]"}
            }
            puts $inventory "$side matched_keepers=$count"
        }
        close $inventory
        set result [checked [list report_timing -setup -from $from -to $to -npaths 10 -nworst 1 -detail full_path -show_routing -file $d/$name.rpt]]
        puts $summary "$name: $result"
    }
    close $summary
    set clocks [open $d/clock-inventory.tcl w];puts $clocks [clock_snapshot];close $clocks
}
# Analyze each available required operating condition. All scenarios use the
# same routed database. No settings are written or fit/synthesis rerun.
foreach scenario {78 104} {
    create_timing_netlist -model slow
    read_sdc
    update_timing_netlist
    set d $root/$scenario
    file mkdir $d
    if {$scenario==104} {
        if {[catch {retarget_core} why]} {
            puts $errors "104 clock coverage FAILED: $why";flush $errors
            set f [open $d/clock-coverage-FAILED.txt w];puts $f $why;close $f
            checked [list report_clocks -file $d/clocks-on-failure.rpt]
            delete_timing_netlist
            continue
        }
        set f [open $d/clock-coverage-PASS.txt w];puts $f "104 MHz internal clocks validated; see UCP for preexisting missing I/O constraints";close $f
    }
    set index 0
    foreach_in_collection op [get_available_operating_conditions] {
        incr index
        set od $d/corner-$index
        file mkdir $od
        set f [open $od/operating-condition.txt w]
        foreach option {name display_name model temperature voltage} {puts $f "$option: [get_operating_conditions_info -$option $op]"}
        close $f
        set_operating_conditions $op
        update_timing_netlist
        emit $od
    }
    delete_timing_netlist
}
close $errors
project_close
puts "DONE isolated resident-store post-fit scenarios; inspect errors/coverage explicitly"
