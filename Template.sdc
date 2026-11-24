derive_pll_clocks
derive_clock_uncertainty

# core specific constraints
#
# The production UPP request stage holds one immutable packet. Peripherals
# wait for its maturity token before sampling the protected data bank. The
# earliest destination edge is E2 after launch E0. Keep all packet-to-control,
# live-to-data, fast RAM, and response-to-bridge paths at their ordinary timing.
namespace eval upp_mmio {
    variable upp {emu:emu|ngage_mister:core|ngage_board:board|ngage_upp:upp}
    variable packet $upp|ngage_upp_request_stage:cpu_inside.request_stage
    variable peripheral $upp|ngage_upp_peripherals:peripherals
}

proc upp_mmio::endpoints {} {
    variable packet
    variable peripheral
    # Match the exact owning instances first, then verify the physical names
    # returned by TimeQuest. Replicas of these held/sample regs are permitted.
    set launch [get_registers -nowarn [list $packet|held_address* $packet|held_sel* $packet|held_we*]]
    set sample [get_registers -nowarn $peripheral|registered_response.local_results*.two_edge_payload.data*]
    set launches 0
    set samples 0
    set lanes {}
    foreach_in_collection reg $launch {
        set name [get_node_info -name $reg]
        set prefix "$packet|"
        set tail [string range $name [string length $prefix] end]
        if {[string first $prefix $name] != 0 ||
            ![regexp {^(held_address\[(?:[0-9]|[12][0-9]|3[01])\]|held_sel\[[0-3]\]|held_we)(~DUPLICATE[0-9]*)?$} $tail]} {
            error "Unexpected UPP packet launch register $name"
        }
        incr launches
    }
    foreach_in_collection reg $sample {
        set name [get_node_info -name $reg]
        set prefix "$peripheral|registered_response.local_results"
        set tail [string range $name [string length $prefix] end]
        if {[string first $prefix $name] != 0 ||
            ![regexp {^\[([0-9]|1[1-5])\]\.two_edge_payload\.data\[(?:[0-9]|[12][0-9]|3[01])\](~DUPLICATE[0-9]*)?$} $tail -> lane]} {
            error "Unexpected UPP response sample register $name"
        }
        dict set lanes $lane 1
        incr samples
    }
    return [list $launch $sample $launches $samples [lsort -integer [dict keys $lanes]]]
}

lassign [upp_mmio::endpoints] upp_launch upp_sample upp_launches upp_samples upp_lanes
if {$upp_launches && $upp_samples} {
    set_multicycle_path -end -setup -from $upp_launch -to $upp_sample 2
    set_multicycle_path -end -hold -from $upp_launch -to $upp_sample 1
} else {
    # No exception on a partially elaborated netlist or a diagnostic
    # configuration without these registers. Production postfit requires
    # connected, nonempty collections and checks the effective relationships.
    post_message -type warning "UPP two-edge endpoints not both present ($upp_launches launches, $upp_samples samples)"
}
