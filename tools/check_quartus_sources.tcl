# Source-graph preflight for the Quartus 17 GitHub build. Run from repo root:
#   tclsh tools/check_quartus_sources.tcl
# or quartus_sh -t tools/check_quartus_sources.tcl
# This evaluates QSF/QIP Tcl; it does not elaborate HDL or validate timing.
set project_root [pwd]
set quartus(version) 17.0.2
set quartus(qip_path) $project_root
set required [dict create]
set qips [dict create]
set optional_missing {}
set failures {}
set search_paths [list $project_root]
proc require_file {kind path} {
    global project_root required failures
    set path [file normalize [file join $project_root $path]]
    if {![file isfile $path]} {lappend failures "Missing $kind: $path"; return 0}
    dict set required $path $kind
    return 1
}
proc include_qip {path} {
    global quartus project_root qips failures
    set path [file normalize [file join $project_root $path]]
    if {[dict exists $qips $path]} {lappend failures "Duplicate QIP inclusion: $path";return}
    dict set qips $path 1
    if {![require_file QIP_FILE $path]} {return}
    set saved $quartus(qip_path)
    set quartus(qip_path) "[file dirname $path]/"
    source $path
    set quartus(qip_path) $saved
}
proc set_global_assignment {args} {
    global optional_missing search_paths project_root
    set n [lsearch -exact $args -name]
    if {$n<0} {error "Assignment has no -name: $args"}
    set kind [lindex $args [expr {$n+1}]]
    set value [lindex $args [expr {$n+2}]]
    switch -- $kind {
        QIP_FILE {include_qip $value}
        VERILOG_FILE - SYSTEMVERILOG_FILE - VHDL_FILE - SOURCE_FILE - SDC_FILE - MIF_FILE - HEX_FILE {require_file $kind $value}
        SEARCH_PATH {lappend search_paths [file normalize [file join $project_root $value]]}
        MISC_FILE {if {![file isfile $value]} {lappend optional_missing $value}}
        PRE_FLOW_SCRIPT_FILE {require_file PRE_FLOW_SCRIPT_FILE [lindex [split $value :] end]}
        default {}
    }
}
proc set_instance_assignment {args} {}
proc set_location_assignment {args} {}
# Stock MiSTer QSF uses unquoted pin indices such as USER_IO[6]. Quartus's
# assignment parser preserves them; emulate just that spelling for this check.
proc unknown {name args} {
    if {[regexp {^[0-9*]+$} $name] && [llength $args]==0} {return "\[$name\]"}
    error "Unsupported project command: $name $args"
}
rename source source_actual
proc source {path} {
    if {![require_file TCL_SOURCE $path]} {return}
    uplevel 1 [list source_actual $path]
}
source Template.qsf
# Resolve quoted HDL includes using source-local, project and SEARCH_PATH
# directories. build_id.v is produced by the verified pre-flow script.
set queue [dict keys $required]
set examined [dict create]
while {[llength $queue]} {
    set path [lindex $queue 0];set queue [lrange $queue 1 end]
    if {[dict exists $examined $path]} {continue}
    dict set examined $path 1
    if {[file extension $path] ni {.v .sv .vh .svh}} {continue}
    set f [open $path];set text [read $f];close $f
    # Quartus17 rejects inline generate-loop variable declarations even in
    # SYSTEMVERILOG_FILE inputs. Catch this known parser failure before compile;
    # this targeted guard does not replace HDL elaboration or synthesis.
    regsub -all {//[^\n]*|/\*.*?\*/} $text "" code
    if {[regexp {for\s*\(\s*genvar\M} $code]} {
        lappend failures "Quartus17 inline genvar: $path (declare genvar before generate)"
    }
    foreach {whole include} [regexp -all -inline {`include[ \t]+"([^"\n]+)"} $text] {
        if {$include eq "build_id.v"} {continue}
        set found 0
        foreach directory [concat [list [file dirname $path]] $search_paths] {
            set candidate [file normalize [file join $directory $include]]
            if {[file isfile $candidate]} {
                require_file HDL_INCLUDE $candidate;lappend queue $candidate;set found 1;break
            }
        }
        if {!$found} {lappend failures "Missing HDL include $include from $path"}
    }
}
# The production cache/TLB must be present; no legacy cache selector exists.
set f [open files.qip];set manifest [read $f];close $f
foreach required_source {rtl/arm920/cache_adapter.sv rtl/arm920/tlb.sv rtl/arm920/tlb_bank.sv} {
    if {![string match "*$required_source*" $manifest]} {lappend failures "Missing production cache/MMU source $required_source"}
}
# GUI metadata must not contradict the maintained two-output PLL HDL.
set f [open rtl/pll.qip];set pll_qip [read $f];close $f
if {[string match {*IP_COMPONENT_PARAMETER*} $pll_qip]} {lappend failures "Stale generated core PLL metadata reintroduced"}
if {[llength $failures]} {foreach failure $failures {puts stderr "ERROR: $failure"};exit 1}
puts "PASS Quartus 17 source graph: [dict size $required] required files, [dict size $qips] unique QIPs"
if {[llength $optional_missing]} {puts "INFO: [llength $optional_missing] absent optional component-symbol files are not synthesis inputs"}

if {[lsearch -exact $argv --list]>=0} {
    foreach path [lsort [dict keys $required]] {puts "SOURCE $path"}
}
