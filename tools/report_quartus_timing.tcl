# Quartus 17 TimeQuest post-fit diagnostics. Run after the normal compile:
# quartus_sta -t tools/report_quartus_timing.tcl Template 1000
# No clocks, exceptions, operating limits or fit settings are changed.
# API reference: resources.altera.com/quartushelp/17.0/tafs/tafs/
# tcl_pkg_sta_ver_1.0_cmd_report_timing.htm
package require ::quartus::project
package require ::quartus::sta

set project Template
set count 1000
if {[llength $argv] > 0} {set project [lindex $argv 0]}
if {[llength $argv] > 1} {set count [lindex $argv 1]}
if {![string is integer -strict $count] || $count < 1 || $count > 10000} {
    error "Path count must be an integer from 1 to 10000"
}
set output output_files/timing
file mkdir $output

proc csv_cell {value} {
    return "\"[string map [list \" \"\"] $value]\""
}
proc clock_name {path option} {
    set id [get_path_info $option $path]
    if {$id eq ""} {return ""}
    return [get_clock_info -name $id]
}
proc export_paths {path_file count} {
    set paths [get_timing_paths -setup -npaths $count -nworst 1 -detail full_path]
    set f [open $path_file w]
    puts $f "rank,slack_ns,data_delay_ns,logic_levels,from_clock,to_clock,from_node,to_node"
    set rank 0
    foreach_in_collection path $paths {
        incr rank
        set fields [list $rank [get_path_info -slack $path] \
            [get_path_info -data_delay $path] [get_path_info -num_logic_levels $path] \
            [clock_name $path -from_clock] [clock_name $path -to_clock] \
            [get_node_info -name [get_path_info -from $path]] \
            [get_node_info -name [get_path_info -to $path]]]
        set cells {}
        foreach field $fields {lappend cells [csv_cell $field]}
        puts $f [join $cells ,]
    }
    close $f
    if {$rank == 0} {error "No constrained setup paths found; refusing an empty timing export"}
    puts "EXPORTED $rank worst setup paths to $path_file"
}

# Read-only stage diagnostics remain useful even after a family leaves the
# global worst1000. These are worst-path samples, not whole-family TNS/sign-off.
# Quartus17 report_timing accepts Tcl lists of wildcard node names for -from/-to:
# resources.altera.com/quartushelp/17.0/tafs/tafs/tcl_pkg_sta_ver_1.0_cmd_report_timing.htm
proc report_operand_stages {output} {
    set directory [file join $output operand-stages]
    file mkdir $directory
    set summary [open [file join $directory summary.csv] w]
    puts $summary "group,status,reported_paths,worst_slack_ns,from_patterns,to_patterns,message"
    set rdata {*u_operand_read*slot0_data* *u_operand_read*slot1_data*}
    set groups [list \
        [list cache_request_to_owner {*u_zap_core* *u_code_cache* *u_data_cache*} {*cache*lookup_owner*}] \
        [list cache_owner_to_tags {*cache*lookup_owner*} {*tags*read_mva* *tags*read_valid_bits* *tags*read_dirty_bits* *tags*match_bits*}] \
        [list cache_lookup_pipeline {*cache*lookup_owner* *cache*fast_read* *cache*fast_compare* *tags*} {*cache*fast_read* *cache*fast_compare* *cache*fast_result*}] \
        [list cache_to_response {*cache* *bank*} {*cache*response_valid* *cache*response_data*}] \
        [list decode_to_r_data {*u_zap_decode_main*} $rdata] \
        [list decode_to_r_context {*u_zap_decode_main*} {*u_operand_read*slot0_control* *u_operand_read*slot1_control* *u_operand_read*slot0_index* *u_operand_read*slot1_index*}] \
        [list rf_to_r {*u_zap_register_file*} $rdata] \
        [list commit_sources_to_r {*u_zap_memory_main* *u_zap_postalu2_main* *u_zap_alu_main*} $rdata] \
        [list commit_to_journal {*u_zap_memory_main* *u_zap_postalu2_main* *u_zap_alu_main*} {*u_operand_read*commit_a* *u_operand_read*commit_b* *u_operand_read*commit_c*}] \
        [list journal_to_queue {*u_operand_read*commit_a* *u_operand_read*commit_b* *u_operand_read*commit_c* *u_operand_read*slot0_pending* *u_operand_read*slot1_pending*} $rdata] \
        [list backend_to_completion {*u_data_cache* *u_zap_postalu2_main*} {*u_data_completion*}] \
        [list completion_to_r {*u_data_completion*o_valid*} {*u_operand_read*}] \
        [list completion_format_to_m {*u_data_completion* *u_zap_postalu2_main*} {*u_zap_memory_main*o_mem_rd_data*}] \
        [list formatted_m_to_issue {*u_zap_memory_main*o_mem_rd_data*} {*u_zap_issue_main*o_*_value_ff*}] \
        [list memory_to_issue {*u_zap_memory_main*} {*u_zap_issue_main*o_*_value_ff*}] \
        [list execute_to_issue {*u_zap_shifter_main* *u_zap_alu_main* *u_zap_postalu*} {*u_zap_issue_main*o_*_value_ff*}] \
        [list cp15_select_to_r {*u_zap_predecode* *u_zap_cp15*} $rdata] \
        [list r_pointer_to_issue {*u_operand_read*read_slot*} {*u_zap_issue_main*o_*_value_ff*}] \
        [list r_pointer_to_queue {*u_operand_read*read_slot* *u_operand_read*write_slot*} {*u_operand_read*}] \
        [list cp15_read_response {*u_zap_register_file* *u_zap_cp15* *u_zap_predecode*} {*u_zap_writeback*o_copro_reg_rd_data_ff*}] \
        [list r_to_alu {*u_operand_read*} {*u_zap_issue_main*o_alu_source_value_ff*}] \
        [list r_to_shift_source {*u_operand_read*} {*u_zap_issue_main*o_shift_source_value_ff*}] \
        [list r_to_shift_length {*u_operand_read*} {*u_zap_issue_main*o_shift_length_value_ff*}] \
        [list r_to_memory_operand {*u_operand_read*} {*u_zap_issue_main*o_mem_srcdest_value_ff*}] \
        [list r_queue_feedback {*u_operand_read*} {*u_operand_read*}] \
        [list issue_to_shifter {*u_zap_issue_main*o_*_ff*} {*u_zap_shifter_main*}] \
        [list shifter_recurrence {*u_zap_shifter_main* *u_zap_alu_main*} {*u_zap_shifter_main*}] \
        [list r_stop_to_frontend {*u_operand_read*head_valid* *u_operand_read*tail_valid*} {*u_zap_decode_main* *u_zap_predecode* *u_zap_fetch*}]]
    foreach group $groups {
        lassign $group name sources destinations
        set status ok
        set count ""
        set slack ""
        set message ""
        # Instrumentation must not invalidate an otherwise complete global
        # export if a group was pruned/renamed. Record every missing/error group
        # explicitly; it cannot be treated as a passing measured path.
        if {[catch {
            report_timing -setup -from $sources -to $destinations \
                -npaths 10 -nworst 1 -detail full_path -show_routing \
                -file [file join $directory "$name.rpt"]
        } result]} {
            set status error
            set message $result
        } else {
            set count [lindex $result 0]
            set slack [lindex $result 1]
            if {![string is integer -strict $count] || $count < 0} {
                set status unparsed
                set message $result
                set count ""
                set slack ""
            } elseif {$count == 0} {
                set status no_paths
                set slack ""
            } elseif {![string is double -strict $slack]} {
                set status unparsed
                set message $result
                set slack ""
            }
        }
        set cells {}
        foreach value [list $name $status $count $slack $sources $destinations $message] {
            lappend cells [csv_cell $value]
        }
        puts $summary [join $cells ,]
        puts "OPERAND_STAGE $name: $status paths=$count slack=$slack"
    }
    close $summary
}

project_open -revision $project $project
# Match the normal slow post-fit model. One worst path per endpoint spreads
# the requested 1000 paths across bottlenecks, rather than duplicating one sink.
create_timing_netlist -model slow
read_sdc
update_timing_netlist
report_clocks -file $output/clocks.rpt
report_clock_fmax_summary -file $output/fmax-slow.rpt
report_ucp -file $output/unconstrained-slow.rpt
report_timing -setup -npaths $count -nworst 1 -detail full_path -show_routing \
    -file $output/worst-setup-full.rpt
export_paths $output/worst-setup.csv $count
report_operand_stages $output
report_timing -hold -npaths 100 -nworst 1 -detail full_path -show_routing \
    -file $output/hold-slow-full.rpt
report_timing -recovery -npaths 25 -nworst 1 -detail full_path \
    -file $output/recovery-slow.rpt
report_timing -removal -npaths 25 -nworst 1 -detail full_path \
    -file $output/removal-slow.rpt
delete_timing_netlist

# Fast-model hold paths are separate from setup ranking. Normal multicorner
# compile reports remain the sign-off input; this script adds diagnostic detail.
create_timing_netlist -model fast
read_sdc
update_timing_netlist
report_timing -hold -npaths 100 -nworst 1 -detail full_path -show_routing \
    -file $output/hold-fast-full.rpt
delete_timing_netlist
project_close
puts "PASS detailed post-fit timing export (timing closure is checked separately)"
