#!/bin/sh
# Run inside jotego/simulator:arm64 (same toolchain as the phone simulation).
set -eu
out=build/sim/unit-sdram-short
mkdir -p "$out"
for config in baseline short78 short104 short104delay; do
    case "$config" in
        baseline) settings='-Ptb.LINE_REFILL=1 -Ptb.SHORT_READS=0 -Ptb.SYS_CLK_HZ=104000000' ;;
        short78) settings='-Ptb.LINE_REFILL=1 -Ptb.SHORT_READS=1 -Ptb.SYS_CLK_HZ=78000000' ;;
        short104) settings='-Ptb.LINE_REFILL=1 -Ptb.SHORT_READS=1 -Ptb.SYS_CLK_HZ=104000000' ;;
        short104delay) settings='-Ptb.LINE_REFILL=1 -Ptb.SHORT_READS=1 -Ptb.SYS_CLK_HZ=104000000 -Ptb.CLOCK_PIN_DELAY=0.6' ;;
    esac
    iverilog -g2012 -s tb -Ptb.INVERTED_CLOCK=1 -Ptb.CAPTURE_NEGEDGE=1 $settings \
        -o "$out/$config" rtl/ngage_sdram_clock.v tests/phone/sdram/ddio_model.v \
        rtl/ngage_sdram_adapter.v rtl/ngage_sdram_arbiter.v rtl/sdram/jtframe_sdram64*.v \
        scratch/sdram-reference/mt48lc16m16a2.v tests/phone/sdram/tb.sv
    vvp "$out/$config" > "$out/$config.log"
    if grep -E 'ERROR:|FATAL:' "$out/$config.log"; then exit 1; fi
    grep '^PASS' "$out/$config.log"
done
for hz in 78000000 104000000; do
for short in 0 1; do
    iverilog -g2012 -s tb -Ptb.SYS_CLK_HZ="$hz" -Ptb.SHORT_READS="$short" -o "$out/concurrent-$hz-$short" \
        rtl/ngage_sdram_clock.v tests/phone/sdram/ddio_model.v rtl/sdram/jtframe_sdram64*.v \
        scratch/sdram-reference/mt48lc16m16a2.v tests/phone/sdram/short_concurrent_tb.sv
    vvp "$out/concurrent-$hz-$short" > "$out/concurrent-$hz-$short.log"
    if grep -E 'ERROR:|FATAL:' "$out/concurrent-$hz-$short.log"; then exit 1; fi
    grep '^PASS' "$out/concurrent-$hz-$short.log"
done
done
