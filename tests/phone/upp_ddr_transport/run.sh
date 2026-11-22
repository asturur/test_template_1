#!/bin/sh
set -eu
cd "$(dirname "$0")/../../.."
out=build/sim/upp-ddr-transport
mkdir -p "$out"

# Test the production bind points, including which side owns the SWP lock.
sed -n -e '/^    localparam .*UPP_RAM_BASE/p' \
    -e '/^    wire .*core_ddr_addr;/,/^    \/\/ Raw media has no embedded firmware identity\./p' Template.sv > "$out/route.vh"
iverilog -g2012 -I"$out" -s tb -o "$out/bench" \
    rtl/ngage_bram.v rtl/ngage_ddr_lanes.sv rtl/ngage_ddr_stream.v \
    rtl/ngage_ddr_stream_legacy.v rtl/ngage_ddr_adapter.v rtl/ngage_ddr_flash_cache.v \
    rtl/ngage_ddr_flash_adapter.v rtl/ngage_ddr_arbiter.v rtl/ngage_upp_ddr_port.v \
    tests/phone/upp_ddr_transport/tb.sv
vvp "$out/bench"
