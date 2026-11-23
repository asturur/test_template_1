#!/bin/sh
set -eu

name="${1:?provide a fresh run name}"
case "$name" in *[!A-Za-z0-9_.-]*) exit 2 ;; esac
out="build/sim/$name"
mkdir -p build/sim
mkdir "$out"

simulate() {
    entrypoint=$1
    shift
    docker run --rm --pull=never --network none --platform linux/arm64 -v "$PWD:/work" \
        -w /work --entrypoint "$entrypoint" jotego/simulator:arm64 "$@"
}

# Freeze only the prior TLB controller. Both legs use the same current
# translation checks, page walker and synchronous memory models.
git show 739d3bdb6a10ad975df500576bbde39f7676ff47:rtl/arm9v2/arm925t_phone.v | python3 -c '
import sys
text = sys.stdin.read()
header = "module ngage2_zap_tlb ("
start = text.index(header)
end = text.index("\nendmodule", start) + len("\nendmodule")
print(text[start:end].replace(header, "module reference_zap_tlb (", 1))
' > "$out/reference_zap_tlb.v"

simulate verilator --binary --timing --assert -j 2 -Wno-fatal -Wno-lint \
    --top-module walker_tb --Mdir "$out/obj" rtl/arm9v2/arm925t_phone.v \
    rtl/arm9v2/upstream/sim/stubs/*.sv "$out/reference_zap_tlb.v" \
    tests/cpu/arm9v2_board/tlb_victim_tb.sv > "$out/build.log" 2>&1
simulate "/work/$out/obj/Vwalker_tb" > "$out/run.log" 2>&1
rg '^PASS walker' "$out/run.log"
