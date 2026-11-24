#!/bin/sh
# Run in the simulator image with a saved 3363c87 reference CPU netlist.
set -eu
reference=${1:?provide the retained CPU netlist}
candidate=rtl/arm9v2/arm925t_phone.v
fixture=tests/cpu/arm9v2_board
out=build/sim/unit-wb-rs
python3 "$fixture/prepare_wb_rs_test.py" "$reference" "$candidate" "$out"
verilator --binary --timing --assert -j 2 -Wno-fatal \
    -I"$out" --top-module wb_rs_tb --Mdir "$out/obj" \
    "$candidate" "$out/reference.v" "$fixture/wb_rs_tb.sv" > "$out/build.log" 2>&1
ulimit -c 0
"$out/obj/Vwb_rs_tb" > "$out/run.log" 2>&1 || {
    cat "$out/run.log"
    exit 1
}
cat "$out/run.log"
grep -q '^PASS W auxiliary Rs preparation' "$out/run.log"
