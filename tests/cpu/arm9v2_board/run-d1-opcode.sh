#!/bin/sh
# Run inside the installed jotego/simulator:arm64 image.
set -eu
reference=${1:?provide the c492853 reference netlist}
candidate=rtl/arm9v2/arm925t_phone.v
out=build/sim/unit-d1-opcode
python3 -B tests/cpu/arm9v2_board/prepare_d1_opcode_test.py "$reference" "$candidate" "$out"
verilator --binary --timing --assert -j 2 -Wno-fatal --top-module d1_opcode_tb \
    -I"$out" --Mdir "$out/obj" "$candidate" "$out/reference.v" \
    tests/cpu/arm9v2_board/d1_opcode_tb.sv > "$out/build.log" 2>&1
"$out/obj/Vd1_opcode_tb" > "$out/run.log"
cat "$out/run.log"
test "$(grep -c '^PASS D1 opcode .*lists=65536 thumb=131072 ' "$out/run.log")" = 4
