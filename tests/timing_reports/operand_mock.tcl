# Host-only control-flow/serialization test, not a TimeQuest timing model.
# Run from repo root: tclsh tests/timing_reports/operand_mock.tcl
set f [open tools/report_quartus_timing.tcl]
set script [read $f]
close $f
if {![info complete $script]} {error "Incomplete timing-export Tcl"}
set start [string first "proc csv_cell" $script]
set end [string first "\nproject_open -revision" $script]
if {$start < 0 || $end <= $start} {error "Missing report procedure region"}
eval [string range $script $start [expr {$end-1}]]
set calls 0
proc report_timing {args} {
    global calls
    incr calls
    foreach flag {-setup -from -to -npaths -nworst -detail -show_routing -file} {
        if {[lsearch -exact $args $flag] < 0} {error "Missing $flag"}
    }
    foreach {flag expected} {-npaths 10 -nworst 1 -detail full_path} {
        set i [lsearch -exact $args $flag]
        if {[lindex $args [expr {$i+1}]] ne $expected} {error "Wrong $flag"}
    }
    set i [lsearch -exact $args -file]
    set path [lindex $args [expr {$i+1}]]
    set name [file rootname [file tail $path]]
    if {$name eq "r_queue_feedback"} {error {mock missing "node, renamed"}}
    set f [open $path w]
    puts $f "mock report: $name"
    close $f
    if {$name eq "r_to_memory_operand"} {return {0 0.0}}
    if {$name eq "shifter_recurrence"} {return {unexpected return}}
    return {10 0.375}
}
set directory build/sim/unit-timing-reports
file mkdir $directory
set f [open [file join $directory worst-setup.csv] w]
puts $f "global canary"
close $f
report_operand_stages $directory
if {$calls != 33} {error "Expected33 group queries, got$calls"}
set f [open [file join $directory worst-setup.csv]]
set canary [read $f]
close $f
if {$canary ne "global canary\n"} {error "Stage reports modified global export"}
puts "PASS targeted timing mock:33 bounded queries, status handling; global export unchanged"
