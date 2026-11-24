#!/bin/sh
# Run inside the installed jotego/simulator:arm64 image.
set -eu
reference=${1:?provide the c492853 reference netlist}
candidate=rtl/arm9v2/arm925t_phone.v
out=build/sim/unit-cp15-ap0
mkdir -p "$out"
sed -n -e '/^module ngage2_zap_cp15_cb (/,/^endmodule/p' \
    -e '/^module ngage2_zap_tlb_check (/,/^endmodule/p' "$reference" |
    sed -e 's/^module ngage2_zap_tlb_check (/module old_tlb_check (/' \
        -e 's/^module ngage2_zap_cp15_cb (/module old_cp15 (/' > "$out/reference.v"
verilator --binary --timing -j 2 -Wno-fatal --top-module cp15_ap0_tb \
    --Mdir "$out/obj" "$candidate" "$out/reference.v" \
    tests/cpu/arm9v2_board/cp15_ap0_tb.sv > "$out/build.log" 2>&1
"$out/obj/Vcp15_ap0_tb" > "$out/run.log"
cat "$out/run.log"
grep -q '^PASS CP15 AP0 instruction=0 ' "$out/run.log"
grep -q '^PASS CP15 AP0 instruction=1 ' "$out/run.log"
