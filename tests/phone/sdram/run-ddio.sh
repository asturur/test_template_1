#!/bin/sh
# Run inside jotego/simulator:arm64. Keep the unmodified four-state Micron
# model and its original tAC=5.4ns/tOH=3ns parameters for every case.
set -eu
out=build/sim/unit-sdram-ddio
mkdir -p "$out"
sources="rtl/ngage_sdram_clock.v ${DDIO_MODEL:-tests/phone/sdram/ddio_model.v} rtl/ngage_sdram_adapter.v rtl/ngage_sdram_arbiter.v rtl/sdram/jtframe_sdram64.v rtl/sdram/jtframe_sdram64_bank.v rtl/sdram/jtframe_sdram64_init.v rtl/sdram/jtframe_sdram64_latch.v rtl/sdram/jtframe_sdram64_rfsh.v scratch/sdram-reference/mt48lc16m16a2.v tests/phone/sdram/tb.sv"
# A deliberately mismatched capture edge must still expose the original Z
# failure. Two-state Verilator cannot substitute for this negative control.
iverilog -g2012 -s tb -Ptb.INVERTED_CLOCK=1 -Ptb.CAPTURE_NEGEDGE=0 -o "$out/wrong-edge" $sources
if vvp "$out/wrong-edge" > "$out/wrong-edge.log" 2>&1; then
    echo 'FAIL wrong-edge negative control unexpectedly passed'; exit 1
fi
grep -Eq 'got [0-9a-f]*z[0-9a-fz]* expected' "$out/wrong-edge.log"
echo 'PASS negative control: inverted clock with rising-only capture fails'
for hz in 104000000 78000000; do
for delay in 0 0.25 0.5 1.0; do
    iverilog -g2012 -s tb -Ptb.INVERTED_CLOCK=1 -Ptb.CAPTURE_NEGEDGE=1 \
        -Ptb.SYS_CLK_HZ="$hz" -Ptb.CLOCK_PIN_DELAY="$delay" -o "$out/test" $sources
    vvp "$out/test" > "$out/delay-$hz-$delay.log" 2>&1
    if grep -E 'ERROR:|FATAL:' "$out/delay-$hz-$delay.log"; then exit 1; fi
    grep '^PASS SDRAM real controller' "$out/delay-$hz-$delay.log"
    echo "PASS ${hz} Hz DDIO/falling capture, modeled clock-pin delay ${delay}ns"
done
done
