#!/bin/sh
set -eu
mkdir -p build/sim/unit
iverilog -g2012 -s tb -o build/sim/unit/mister_transport rtl/ngage_ddr_lanes.sv rtl/ngage_ddr_adapter.v tests/phone/mister_transport/tb.sv
vvp build/sim/unit/mister_transport
iverilog -g2012 -s tb -o build/sim/unit/mister_loader rtl/ngage_loader.sv tests/phone/mister_transport/loader_tb.sv
vvp build/sim/unit/mister_loader
iverilog -g2012 -s tb -o build/sim/unit/mister_map rtl/ngage_rom_map.sv tests/phone/mister_map/tb.sv
vvp build/sim/unit/mister_map
iverilog -g2012 -s tb -o build/sim/unit/mister_integrated rtl/ngage_ddr_lanes.sv rtl/ngage_ddr_adapter.v rtl/ngage_ddr_arbiter.v rtl/ngage_loader.sv tests/phone/mister_transport/integrated_tb.sv
vvp build/sim/unit/mister_integrated
iverilog -g2012 -s tb -o build/sim/unit/mister_arbiter rtl/ngage_ddr_arbiter.v tests/phone/mister_transport/arbiter_tb.sv
vvp build/sim/unit/mister_arbiter
iverilog -g2012 -s tb -o build/sim/unit/mister_tail rtl/ngage_loader.sv tests/phone/mister_transport/tail_tb.sv
vvp build/sim/unit/mister_tail
