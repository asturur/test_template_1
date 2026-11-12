#!/bin/sh
set -eu
out=build/sim/unit-diag-ddr
mkdir -p "$out"
for bits in 10 3; do
 iverilog -g2001 -s tb -Ptb.RING_BITS=$bits -o "$out/test-$bits" rtl/ngage_bram.v rtl/ngage_diag_ddr.v rtl/ngage_diag_text_ddr.v rtl/ngage_ddr*.v rtl/ngage_ddr_lanes.sv rtl/ngage_diagnostics.v tests/phone/diag_ddr/tb.v > "$out/build-$bits.log" 2>&1
 vvp "$out/test-$bits" > "$out/run-$bits.log" 2>&1
 cat "$out/run-$bits.log"
done

iverilog -g2001 -s tb -Ptb.PHYSICAL=1 -o "$out/physical" rtl/ngage_bram.v rtl/ngage_diag_ddr.v rtl/ngage_diag_text_ddr.v rtl/ngage_ddr*.v rtl/ngage_ddr_lanes.sv rtl/ngage_diagnostics.v tests/phone/diag_ddr/tb.v > "$out/build-physical.log" 2>&1
vvp "$out/physical" > "$out/run-physical.log" 2>&1
cat "$out/run-physical.log"

for mode in poison vendor; do
 if [ "$mode" = poison ]; then
  ram=tests/cpu/cache_dirty_packed/poison_bram.v
 else
  [ -n "${ALTERA_MF:-}" ] || continue
  ram="-DALTERA_RESERVED_QIS rtl/ngage_bram.v $ALTERA_MF"
 fi
 iverilog -g2001 -s tb -o "$out/$mode" $ram rtl/ngage_diag_ddr.v rtl/ngage_diag_text_ddr.v rtl/ngage_ddr*.v rtl/ngage_ddr_lanes.sv rtl/ngage_diagnostics.v tests/phone/diag_ddr/tb.v > "$out/build-$mode.log" 2>&1
 vvp "$out/$mode" > "$out/run-$mode.log" 2>&1
 cat "$out/run-$mode.log"
done
python3 tests/phone/diag_ddr/test_reader.py
