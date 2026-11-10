#!/bin/sh
set -eu
mkdir -p build/sim/unit-line-refill
iverilog -g2012 -s tb -o build/sim/unit-line-refill/test rtl/arm920/cache_transfer.sv tests/phone/line_refill/tb.sv
vvp build/sim/unit-line-refill/test
iverilog -g2012 -Irtl/arm -s tb -o build/sim/unit-line-refill/owner rtl/arm/zap_top.sv tests/phone/line_refill/owner_tb.sv
vvp build/sim/unit-line-refill/owner
iverilog -g2012 -s tb -o build/sim/unit-line-refill/ddr rtl/ngage_ddr_adapter.v rtl/ngage_ddr_rom_cache.v rtl/jtframe/ngage_jtframe_romrq_lcache.v rtl/ngage_ddr_lanes.sv rtl/ngage_bram.v tests/phone/line_refill/ddr_tb.sv
vvp build/sim/unit-line-refill/ddr
for rate in 78000000 104000000; do
    iverilog -g2012 -Ptb.LINE_REFILL=1 -Ptb.INVERTED_CLOCK=1 -Ptb.CAPTURE_NEGEDGE=1 -Ptb.SYS_CLK_HZ="$rate" -s tb -o "build/sim/unit-line-refill/sdram-$rate" rtl/ngage_sdram_clock.v tests/phone/sdram/ddio_model.v rtl/ngage_sdram_adapter.v rtl/ngage_sdram_arbiter.v rtl/sdram/jtframe_sdram64*.v scratch/sdram-reference/mt48lc16m16a2.v tests/phone/sdram/tb.sv
    vvp "build/sim/unit-line-refill/sdram-$rate" > "build/sim/unit-line-refill/sdram-$rate.log"
    if grep -E 'ERROR:|FATAL:' "build/sim/unit-line-refill/sdram-$rate.log"; then exit 1; fi
    grep '^PASS SDRAM' "build/sim/unit-line-refill/sdram-$rate.log"
done
