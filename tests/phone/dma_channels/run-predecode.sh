#!/bin/sh
# Run in the simulator image from the project root with the old channels RTL.
set -eu
baseline=${1:?pass the reference ngage_dma_channels.v file}
out=build/sim/dma-program-predecode
mkdir -p "$out"
sed 's/module ngage_dma_channels /module ngage_dma_channels_reference /' \
    "$baseline" > "$out/reference.v"
iverilog -g2012 -s program_predecode_tb -o "$out/test" \
    "$out/reference.v" rtl/ngage_dma_channels.v rtl/ngage_upp.v rtl/ngage_bram.v \
    rtl/ngage_lcd_stream.v rtl/ngage_dma_engine.v tests/phone/dma_channels/program_predecode_tb.sv
vvp "$out/test"
