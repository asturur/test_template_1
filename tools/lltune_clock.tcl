# TimeQuest clock model for the stock MiSTer HDMI low-latency tuner.
namespace eval ::lltune_clock {
    variable core_pattern {emu|pll|pll_inst|altera_pll_i|*[0].*|divclk}
    variable tuner_pattern {*pll_hdmi_adj:pll_hdmi_adj|*}
}

proc ::lltune_clock::one {collection description} {
    if {[get_collection_size $collection] != 1} {
        error "Expected one $description, found [get_collection_size $collection]"
    }
    foreach_in_collection node $collection {return $node}
}

proc ::lltune_clock::names {collection} {
    set result {}
    foreach_in_collection node $collection {
        lappend result [get_node_info -name $node]
    }
    return [lsort -unique $result]
}

proc ::lltune_clock::delay_registers {} {
    variable tuner_pattern
    set expected {i_de2 i_vss2 i_vss_delay}
    foreach {name width} {i_linecpt 12 i_line 12 i_delay 14} {
        for {set bit 0} {$bit < $width} {incr bit} {
            lappend expected [format {%s[%d]} $name $bit]
        }
    }
    set originals {}
    set registers {}
    foreach_in_collection reg [get_registers -nowarn $tuner_pattern] {
        set leaf [lindex [split [get_node_info -name $reg] |] end]
        set original [lindex [split $leaf ~] 0]
        if {$original in $expected} {
            lappend originals $original
            lappend registers $reg
        }
    }
    if {[lsort -unique $originals] ne [lsort $expected]} {
        error "Incomplete HDMI tuner Delay register set: [lsort -unique $originals]"
    }
    return $registers
}

proc ::lltune_clock::clock_pin {node} {
    # Follow the immediate clock arc. A TimeQuest netlist can name its
    # source as the comb output or as the owning top-level LUT.
    for {set hop 0} {$hop < 8} {incr hop} {
        set name [get_node_info -name $node]
        if {[regexp {^(?:(?:sys_top(?::sys_top)?)\|)?([^|]+)(\|combout)?$} $name -> cell suffix] &&
            ($suffix ne "" || [get_node_info -type $node] eq "comb")} {
            return "$cell|combout"
        }
        set edges [get_node_info -clock_edges $node]
        if {![llength $edges] && [get_node_info -type $node] in {pin net}} {
            set edges [get_node_info -synch_edges $node]
        }
        if {[llength $edges] != 1} {break}
        set node [get_edge_info -src [lindex $edges 0]]
    }
    error "Could not identify a unique upstream LUT output for $name"
}

proc ::lltune_clock::resolve {} {
    set assigned {}
    set candidates {}
    foreach reg [delay_registers] {
        lappend assigned [get_node_info -name $reg]
        lappend candidates [clock_pin $reg]
    }
    set candidates [lsort -unique $candidates]
    if {[llength $candidates] != 1} {
        error "HDMI Delay registers do not share a single LUT clock driver"
    }
    set gate [get_pins -compatibility_mode -nowarn $candidates]
    one $gate "top-level tuner gate output"

    # The physical clock load must be exactly the Delay registers.
    set sinks {}
    foreach_in_collection sink [get_fanouts -no_logic $gate] {
        if {[get_node_info -type $sink] eq "reg"} {
            lappend sinks [get_node_info -name $sink]
        }
    }
    set assigned [lsort -unique $assigned]
    if {[lsort -unique $sinks] ne $assigned} {
        error "Gate $candidates fanout is not exactly the HDMI Delay registers"
    }
    return [list $gate $assigned]
}

proc ::lltune_clock::core {} {
    variable core_pattern
    return [one [get_clocks -nowarn $core_pattern] "core PLL output clock"]
}

proc ::lltune_clock::create {} {
    variable tuner_pattern
    if {![get_collection_size [get_registers -nowarn $tuner_pattern]]} {
        # The framework debug build can omit the entire HDMI tuner.
        return {}
    }
    set master [core]
    set period [get_clock_info -period $master]
    if {abs($period - 1000.0 / 78) < 0.002} {
        # Leave the original 78 MHz model and its retarget diagnostics intact.
        return {}
    }
    if {abs($period - 1000.0 / 104) > 0.002} {
        error "Unsupported core PLL period for HDMI tuner clock: $period ns"
    }
    lassign [resolve] gate sinks
    set source [get_clock_info -targets $master]
    one $source "core PLL output pin"
    if {![get_collection_size [get_fanins -through $source $gate]]} {
        error "HDMI tuner gate does not have the fitted core PLL output in its fanin"
    }
    set enable [lsearch -regexp [names [get_fanins $gate]] {(^|\|)cfg_done(~[^|]+)?$}]
    if {$enable < 0} {error "HDMI tuner gate does not have cfg_done in its fanin"}
    create_generated_clock -name lltune_clk -source $source \
        -master_clock [get_clock_info -name $master] -divide_by 1 $gate
    set target_name [get_node_info -name [one $gate "HDMI tuner gate output"]]
    post_message -type info "HDMI tuner clock target $target_name, [llength $sinks] Delay registers"
    return lltune_clk
}

proc ::lltune_clock::check_uncertainty_table {table check from_name to_name expected} {
    set from_query [format {[get_clocks {%s}]} $from_name]
    set to_query [format {[get_clocks {%s}]} $to_name]
    set edges {}
    foreach row [split $table "\n"] {
        if {[string first set_clock_uncertainty $row] == -1} {continue}
        set fields {}
        foreach field [split $row {;}] {lappend fields [string trim $field]}
        lassign $fields empty command kind from_edge from to_edge to value
        if {$command ne "set_clock_uncertainty" || $kind ne "-$check" ||
            $from ne $from_query || $to ne $to_query} {continue}
        if {abs($value - $expected) > 0.002} {
            error "Derived $check uncertainty on $from_name to $to_name is $value ns, expected $expected ns"
        }
        lappend edges [list $from_edge $to_edge]
    }
    if {{-rise_from -rise_to} ni $edges} {
        error "Incomplete derived $check uncertainty from $from_name to $to_name"
    }
}

proc ::lltune_clock::check_pair {log check from_name to_name expected required} {
    set paths [get_timing_paths -$check -npaths 1 -from_clock [list $from_name] \
        -to_clock [list $to_name] -detail full_path]
    if {![get_collection_size $paths]} {
        puts $log "$check\t$from_name\t$to_name\tno active paths"
        if {$required} {error "Missing $check path from $from_name to $to_name"}
        return
    }
    foreach_in_collection path $paths {
        set uncertainty {}
        foreach_in_collection point [get_path_info -required_points $path] {
            if {[get_point_info -type $point] eq "unc"} {
                lappend uncertainty [expr {abs([get_point_info -incr $point])}]
            }
        }
        if {[llength $uncertainty] != 1} {error "Unreported uncertainty on $from_name to $to_name $check"}
        set actual [lindex $uncertainty 0]
        set from_reg [get_node_info -name [get_path_info -from $path]]
        set to_reg [get_node_info -name [get_path_info -to $path]]
        puts $log "$check\t$from_name\t$to_name\t$actual\t[get_path_info -slack $path]\t$from_reg\t$to_reg"
        # TimeQuest can cancel uncertainty on a hold path on a common
        # physical edge. The derived margin is checked separately.
        if {$expected ne "" && abs($actual - $expected) > 0.002 &&
            !($check eq "hold" && $actual < 0.002)} {
            error "$check uncertainty on $from_name to $to_name is $actual ns, expected $expected ns"
        }
    }
}

proc ::lltune_clock::audit {directory} {
    variable tuner_pattern
    if {![get_collection_size [get_registers -nowarn $tuner_pattern]]} {return}
    lassign [resolve] gate sinks
    set gate_pin [one $gate "HDMI tuner gate output"]
    set master [core]
    set master_name [get_clock_info -name $master]
    set gated [one [get_clocks -nowarn lltune_clk] "HDMI tuner generated clock"]
    set target [one [get_clock_info -targets $gated] "HDMI tuner clock target"]
    set source [one [get_clock_info -targets $master] "core PLL output pin"]
    set gate_name [get_node_info -name $gate_pin]
    set source_name [get_node_info -name $source]
    if {[get_node_info -name $target] ne $gate_name ||
        [get_clock_info -master_clock $gated] ne $master_name ||
        [get_clock_info -master_clock_pin $gated] ni [list $source $source_name] ||
        [get_clock_info -nreg_pos $gated] != [llength $sinks] ||
        [get_clock_info -nreg_neg $gated] != 0} {
        error "HDMI generated clock does not own exactly the expected Delay registers"
    }
    set period [get_clock_info -period $master]
    lassign [get_clock_info -waveform $master] master_rise master_fall
    lassign [get_clock_info -waveform $gated] gated_rise gated_fall
    if {abs($period - 1000.0 / 104) > 0.002 ||
        abs([get_clock_info -period $gated] - $period) > 0.002 ||
        abs($gated_rise - $master_rise) > 0.002 || abs($gated_fall - $master_fall) > 0.002} {
        error "The 104 MHz native PLL and its gated copy do not have the expected waveform"
    }

    set constraints [open $directory/constraints.rpt r]
    set table [read $constraints]
    close $constraints
    set log [open $directory/lltune-clock.tsv w]
    puts $log "master\t$master_name\t$period ns"
    puts $log "gate\t$gate_name\t[llength $sinks] rising edge registers"
    foreach sink $sinks {puts $log "sink\t$sink"}
    puts $log "check\tfrom_clock\tto_clock\tuncertainty_ns\tslack_ns\tfrom\tto"
    foreach {check core_unc gate_unc inbound_unc} {setup 0.140 0.300 0.220 hold 0.080 0.280 0.180} {
        foreach {from to margin} [list $master_name $master_name $core_unc                                       lltune_clk lltune_clk $gate_unc                                       $master_name lltune_clk $inbound_unc] {
            check_uncertainty_table $table $check $from $to $margin
            puts $log "derived-$check\t$from\t$to\t$margin"
            check_pair $log $check $from $to $margin 1
        }
        check_pair $log $check lltune_clk $master_name {} 0
    }
    # Same original external groups, with the generated clock on the core
    # side. Record an uninstantiated SPI clock separately from a cut crossing.
    foreach pattern {spi_sck hdmi_sck *|h2f_user0_clk FPGA_CLK1_50 FPGA_CLK2_50 FPGA_CLK3_50
                     {pll_hdmi|pll_hdmi_inst|altera_pll_i|*[0].*|divclk}
                     {pll_audio|pll_audio_inst|altera_pll_i|*[0].*|divclk}} {
        set external [get_clocks -nowarn $pattern]
        if {![get_collection_size $external]} {puts $log "absent\t$pattern"}
        foreach_in_collection clock $external {
            set name [get_clock_info -name $clock]
            foreach check {setup hold recovery removal} {
                foreach local [list $master_name lltune_clk] {
                    foreach {from to} [list $local $name $name $local] {
                        if {[get_collection_size [get_timing_paths -$check -npaths 1 \
                                -from_clock [list $from] -to_clock [list $to]]]} {
                            error "Unexpected active $check crossing from $from to $to"
                        }
                    }
                }
            }
            puts $log "exclusive\t$name"
        }
    }
    set pulse_domains [dict create]
    foreach scope [get_clock_domain_info -mpw] {
        lassign $scope clock slack
        dict set pulse_domains $clock $slack
    }
    foreach clock [list $master_name lltune_clk] {
        if {![dict exists $pulse_domains $clock]} {
            error "Missing minimum pulse-width analysis on $clock"
        }
        puts $log "min-pulse\t$clock\t[dict get $pulse_domains $clock]"
    }
    close $log
    report_clock_transfers -file $directory/lltune-clock-transfers.rpt
    puts "PASS HDMI tuner clock topology and derived uncertainty"
}
