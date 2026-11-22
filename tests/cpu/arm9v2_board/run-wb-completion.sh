#!/bin/sh
set -eu
name="${1:?provide a fresh run name}"
case "$name" in *[!A-Za-z0-9_.-]*) exit 2 ;; esac
out="build/sim/$name"
mkdir "$out"

simulate() {
    entrypoint=$1
    shift
    docker run --rm --pull=never --network none --platform linux/arm64 -v "$PWD:/work" \
        -w /work --entrypoint "$entrypoint" jotego/simulator:arm64 "$@"
}

simulate verilator --binary --timing --assert -j 2 -Wno-fatal -Wno-lint \
    --top-module wb_completion_tb --Mdir "$out/obj" rtl/ngage_cpu.sv rtl/ngage_upp.v \
    tests/cpu/arm9v2_board/wb_completion_tb.sv > "$out/build.log" 2>&1
simulate "/work/$out/obj/Vwb_completion_tb" > "$out/run.log" 2>&1
rg '^PASS owned Wishbone completion' "$out/run.log"
