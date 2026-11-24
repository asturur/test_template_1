#!/bin/sh
# Run from the source root in the simulator image with the fe145b0 netlist.
set -eu
reference=${1:?provide the retained fe145b0 arm925t_phone.v}
candidate=rtl/arm9v2/arm925t_phone.v
fixture=tests/cpu/arm9v2_board
out=build/sim/unit-early-shift
python3 "$fixture/prepare_early_shift_test.py" "$reference" "$candidate" "$out"
verilator --binary --timing --assert -j 2 -Wno-fatal \
    -I"$out" --top-module early_shift_tb --Mdir "$out/obj" \
    "$candidate" "$out/reference.v" "$fixture/early_shift_tb.sv" > "$out/build.log" 2>&1
"$out/obj/Vearly_shift_tb" > "$out/run.log" 2>&1 || {
    cat "$out/run.log"
    exit 1
}
cat "$out/run.log"
grep -q '^PASS early shift' "$out/run.log"
