#!/bin/sh
# Run inside jotego/simulator:arm64. The control is b6d8981's arm925t_phone.v.
set -eu
reference=${1:?provide the b6d8981 reference netlist}
candidate=rtl/arm9v2/arm925t_phone.v
out=build/sim/unit-execute-ready
python3 tests/cpu/arm9v2_board/prepare_execute_ready_test.py "$reference" "$candidate" "$out"
# Arbitrary inputs stress the execute interface. Board and workload benches
# run with the RTL assertions enabled and real producer/retire relationships.
verilator --binary --timing -DSYNTHESIS -j 2 -Wno-fatal --top-module execute_ready_tb \
    --Mdir "$out/obj" "$candidate" "$out/reference.v" "$out/tb.sv" > "$out/build.log" 2>&1
"$out/obj/Vexecute_ready_tb" > "$out/run.log"
cat "$out/run.log"
grep -q '^PASS execute readiness 20000 cycles ' "$out/run.log"
