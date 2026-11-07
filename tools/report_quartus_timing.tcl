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
