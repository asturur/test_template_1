# Diagnostic TimeQuest export for an already fitted Template revision.
# One fitted PLL, four operating corners, unchanged timing constraints.
package require ::quartus::project
package require ::quartus::sta

set variant [lindex $argv 0]
if {$variant ni {cpu-only board-only}} {error "Expected cpu-only or board-only"}
set output output_files/timing
file mkdir $output
set diagnostics [open $output/export-errors.txt w]

proc attempt {label script} {
    global diagnostics
    if {[catch {uplevel 1 $script} result]} {
        puts $diagnostics "$label: $result"
        flush $diagnostics
        puts stderr "Timing export $label failed: $result"
        return ""
    }
    return $result
}

proc quote_csv {value} {
    return "\"[string map [list \" \"\"] $value]\""
}

proc path_clock_name {path option} {
    set clock [get_path_info $option $path]
    if {$clock eq ""} {return ""}
    return [get_clock_info -name $clock]
}

proc path_csv {destination options} {
    set file [open $destination w]
    puts $file "rank,slack_ns,data_delay_ns,logic_levels,from_clock,to_clock,from_node,to_node"
    set rank 0
    foreach_in_collection path [get_timing_paths -setup -npaths 1000 -nworst 1 -detail full_path {*}$options] {
        incr rank
        set fields [list $rank [get_path_info -slack $path] [get_path_info -data_delay $path] \
            [get_path_info -num_logic_levels $path] \
            [path_clock_name $path -from_clock] \
            [path_clock_name $path -to_clock] \
            [get_node_info -name [get_path_info -from $path]] \
            [get_node_info -name [get_path_info -to $path]]]
        set row {}
        foreach field $fields {lappend row [quote_csv $field]}
        puts $file [join $row ,]
    }
    close $file
    if {$rank != 1000} {error "Expected 1000 paths; exported $rank"}
}

proc core_clock {} {
    set matched {}
    foreach_in_collection clock [get_clocks *] {
        set name [get_clock_info -name $clock]
        if {[string match {*emu|pll|*~PLL_OUTPUT_COUNTER*|divclk} $name]} {
            lappend matched [list $clock $name]
        }
    }
    if {[llength $matched] != 1} {error "Expected one running emu PLL output: $matched"}
    lassign [lindex $matched 0] clock name
    set period [get_clock_info -period $clock]
    if {abs($period - 1000.0/104) > 0.002} {error "Fitted PLL does not run at 104 MHz: $period ns"}
    return [list $clock $name $period]
}

proc endpoint_groups {directory variant clock_options} {
    set all [get_keepers *]
    if {$variant eq "cpu-only"} {
        set dut [get_keepers -nowarn {emu|cpu|* *|emu|cpu|*}]
        set harness [remove_from_collection $all $dut]
    } else {
        set harness [get_keepers -nowarn {*|cpu_inside.cpu|*}]
        set dut [remove_from_collection $all $harness]
    }
    set file [open $directory/groups.tsv w]
    puts $file "group\tsource_keepers\tdestination_keepers\treported_paths\tworst_slack_ns"
    foreach {group from to} [list dut-to-dut $dut $dut dut-to-harness $dut $harness \
                              harness-to-dut $harness $dut harness-to-harness $harness $harness] {
        set source_count [get_collection_size $from]
        set destination_count [get_collection_size $to]
        set result {}
        if {$source_count && $destination_count} {
            set result [attempt $group [list report_timing -setup -npaths 25 -nworst 1 -detail full_path \
                -show_routing -file $directory/$group.rpt {*}$clock_options -from $from -to $to]]
        }
        puts $file [join [list $group $source_count $destination_count [lindex $result 0] [lindex $result 1]] "\t"]
    }
    close $file
}

project_open -revision Template Template
create_timing_netlist -model slow
read_sdc
update_timing_netlist

set index 0
foreach_in_collection condition [get_available_operating_conditions] {
    incr index
    set directory $output/corner-$index
    file mkdir $directory
    set_operating_conditions $condition
    update_timing_netlist
    set file [open $directory/operating-condition.txt w]
    foreach field {name display_name model temperature voltage} {
        puts $file "$field: [get_operating_conditions_info -$field $condition]"
    }
    close $file
    attempt clocks [list report_clocks -file $directory/clocks.rpt]
    attempt fmax [list report_clock_fmax_summary -file $directory/fmax.rpt]
    attempt constraints [list report_sdc -file $directory/constraints.rpt]
    attempt ignored [list report_sdc -ignored -file $directory/ignored-constraints.rpt]
    attempt coverage [list report_ucp -file $directory/unconstrained.rpt]
    attempt checks [list check_timing -include {no_clock multiple_clock generated_clock uncertainty loops latches no_input_delay no_output_delay partial_input_delay partial_output_delay pll_cross_check} \
        -file $directory/check-timing.rpt]
    attempt setup [list path_csv $directory/worst-setup.csv {}]
    foreach kind {hold recovery removal} {
        attempt $kind [list report_timing -$kind -npaths 25 -nworst 1 -detail full_path -file $directory/$kind.rpt]
    }
    attempt pulse [list report_min_pulse_width -nworst 25 -detail full_path -file $directory/min-pulse.rpt]

    set clock [attempt physical-clock core_clock]
    if {$clock ne ""} {
        lassign $clock collection name period
        set file [open $directory/physical-clock.txt w]
        puts $file "clock=$name\nphysical_mhz=104\nperiod_ns=$period"
        close $file
        set options [list -from_clock $collection -to_clock $collection]
        attempt core-setup [list path_csv $directory/core-setup.csv $options]
        attempt core-full [list report_timing -setup -npaths 100 -nworst 1 -detail full_path -show_routing \
            -file $directory/core-setup-full.rpt {*}$options]
        attempt groups [list endpoint_groups $directory $variant $options]
    }
}
if {$index != 4} {puts $diagnostics "Expected four fitted operating corners, found $index"}
close $diagnostics
delete_timing_netlist
project_close
puts "Completed $variant timing export. See export-errors.txt and coverage checks."
