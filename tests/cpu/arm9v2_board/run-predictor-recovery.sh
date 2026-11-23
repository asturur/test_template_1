#!/bin/sh
set -eu

name=${1:?provide a fresh run name}
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

git show 27bd8bff3f3a1a898ae628ecdfaf80bfaac5668a:rtl/arm9v2/arm925t_phone.v | python3 -c '
import sys
text = sys.stdin.read()
header = "module ngage2_arm9v2_predict ("
start = text.index(header)
end = text.index("\nendmodule", start) + len("\nendmodule")
print(text[start:end].replace(header, "module reference_predict (", 1))
' > "$out/reference.v"

simulate verilator --binary --timing --assert -j 2 -Wno-fatal -Wno-lint \
    --top-module predictor_recovery_tb --Mdir "$out/obj" \
    rtl/arm9v2/arm925t_phone.v "$out/reference.v" \
    tests/cpu/arm9v2_board/predictor_recovery_tb.sv > "$out/build.log" 2>&1
simulate "/work/$out/obj/Vpredictor_recovery_tb" > "$out/run.log" 2>&1
rg '^PASS parallel predictor' "$out/run.log"
