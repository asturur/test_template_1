# Used from the existing production post-fit report after read_sdc.
proc upp_mmio::audit_paths {directory tag type options expected steps period {maximum 0}} {
    set paths [get_timing_paths -$type {*}$options -pairs_only -npaths $maximum -less_than_slack 100]
    set f [open [file join $directory $tag.tsv] w]
    puts $f "slack_ns	relationship_ns	setup_end	hold_end	from	to"
    set count 0
    set endpoints {}
    set code [catch {
        foreach_in_collection path $paths {
            set from [get_node_info -name [get_path_info -from $path]]
            set to [get_node_info -name [get_path_info -to $path]]
            set srcclk [get_path_info -from_clock $path]
            set dstclk [get_path_info -to_clock $path]
            set slack [get_path_info -slack $path]
            set relationship [get_path_info -clock_relationship $path]
            set setup [get_path_info -setup_end_multicycle $path]
            set hold [get_path_info -hold_end_multicycle $path]
            puts $f "$slack	$relationship	$setup	$hold	$from	$to"
            incr count
            dict set endpoints $to 1
            if {$srcclk ne $dstclk || abs([get_clock_info -period $dstclk]-$period) > 0.002 ||
                abs($relationship-$expected) > 0.005 ||
                ($type eq "setup" && $steps == 2 && $setup != 2) ||
                ($type eq "setup" && $steps == 1 && $setup > 1) ||
                ($type eq "hold" && $hold != $steps)} {
                error "$tag unexpected relationship $relationship, setup $setup, hold $hold ($from -> $to)"
            }
        }
    } reason failure]
    close $f
    if {$code} {return -options $failure $reason}
    if {$count == 0} {error "$tag has no connected paths"}
    report_timing -$type {*}$options -npaths 20 -nworst 1 -less_than_slack 100 \
        -detail full_path -show_routing -file [file join $directory $tag.rpt]
    return [list $tag $count [dict size $endpoints]]
}

proc upp_mmio::audit {directory period} {
    variable packet
    variable peripheral
    variable upp
    lassign [endpoints] launch sample launches samples lanes
    file mkdir $directory
    if {$launches < 20 || $samples < 100 || 13 ni $lanes || 15 ni $lanes} {
        error "Incomplete UPP two-edge registers ($launches launches, $samples samples, lanes $lanes)"
    }
    set f [open [file join $directory inventory.txt] w]
    puts $f "launches=$launches samples=$samples lanes=$lanes period_ns=$period"
    foreach group {launch sample} {
        foreach_in_collection reg [set $group] {
            puts $f "$group [get_node_info -name $reg]"
        }
    }
    close $f
    set pair [list -from $launch -to $sample]
    set control [get_registers -nowarn [list \
        $peripheral|registered_response.valid* \
        $peripheral|registered_response.local_results*.owner* \
        $peripheral|registered_response.local_results*.error*]]
    set fast [get_registers -nowarn $peripheral|registered_response.local_results*.ordinary_payload.data*]
    set returned [get_registers -nowarn $upp|ngage_upp_bus_bridge:cpu_inside.bridge|master_read_data*]
    set result [open [file join $directory coverage.txt] w]
    set code [catch {
        puts $result [audit_paths $directory held_setup setup $pair [expr {2*$period}] 2 $period]
        puts $result [audit_paths $directory held_hold hold $pair 0 1 $period]
        puts $result [audit_paths $directory held_to_controls setup [list -from $launch -to $control] $period 1 $period 32]
        puts $result [audit_paths $directory held_to_fast setup [list -from $launch -to $fast] $period 1 $period 32]
        puts $result [audit_paths $directory response_to_bridge setup [list -from $sample -to $returned] $period 1 $period 32]
        foreach {tag pattern} {
            uart {*|ngage_upp_euart:euart1|*}
            keypad {*|ngage_keypad:keypad_enabled.keypad|*}
            timer {*|ngage_timers:timers|*}
            mmc {*|ngage_mmc_host:mmc_enabled.host|*}
        } {
            set live [get_registers -nowarn $peripheral$pattern]
            puts $result [audit_paths $directory live_$tag setup [list -from $live -to $sample] $period 1 $period 32]
        }
        puts $result "PASS protected setup/hold and single-cycle witnesses"
    } reason failure]
    close $result
    if {$code} {return -options $failure $reason}
}
