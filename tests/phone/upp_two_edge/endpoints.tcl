# Check the SDC selector against Quartus-style register and replica names.
# Timing path connectivity and clock relationships are audited post-fit.
set prefix {emu:emu|ngage_mister:core|ngage_board:board|ngage_upp:upp}
set stage $prefix|ngage_upp_request_stage:cpu_inside.request_stage
set response $prefix|ngage_upp_peripherals:peripherals
set held [list "$stage|held_address\[17\]" "$stage|held_sel\[3\]~DUPLICATE263" "$stage|held_we"]
set late [list "$response|registered_response.local_results\[13\].two_edge_payload.data\[14\]" \
               "$response|registered_response.local_results\[15\].two_edge_payload.data\[31\]"]
set excluded [list "$response|registered_response.local_results\[10\].ordinary_payload.data\[14\]" \
                   "$response|registered_response.local_results\[13\].owner" \
                   "$response|registered_response.valid" "$stage|mature" \
                   "other|ngage_upp_request_stage:cpu_inside.request_stage|held_address\[17\]"]
set registers [concat $held $late $excluded]
set constraints {}
proc derive_pll_clocks {} {}
proc derive_clock_uncertainty {} {}
proc foreach_in_collection {var collection body} {uplevel 1 [list foreach $var $collection $body]}
proc get_node_info {option name} {return $name}
proc get_registers {option patterns} {
    global registers
    set result {}
    foreach reg $registers {
        foreach pattern $patterns {
            if {[string match $pattern $reg]} {lappend result $reg; break}
        }
    }
    return $result
}
proc set_multicycle_path {args} {
    global constraints
    lappend constraints $args
}
proc post_message {args} {}
source Template.sdc
if {$constraints ne [list [list -end -setup -from $held -to $late 2] \
                         [list -end -hold -from $held -to $late 1]]} {
    error "Wrong UPP exception scope $constraints"
}
lappend registers "$response|registered_response.local_results\[10\].two_edge_payload.data\[2\]"
if {![catch {upp_mmio::endpoints} message] || ![string match {Unexpected UPP response sample register *} $message]} {
    error "Wrong-lane named result was not rejected"
}
set registers $excluded
set constraints {}
source Template.sdc
if {$constraints ne {}} {error "Empty selector emitted an exception"}
puts "PASS exact held-packet SDC collection scope, fast-path exclusion and empty guard"
