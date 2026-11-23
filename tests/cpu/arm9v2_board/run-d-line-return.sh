#!/bin/sh
set -eu

name="${1:?provide a fresh run name}"
case "$name" in *[!A-Za-z0-9_.-]*) exit 2 ;; esac
mode="${2:-capture}"
wrapper="${3:-rtl/ngage_cpu.sv}"
fixture="${4:-tests/cpu/arm9v2_board/d_return_tb.sv}"
out="build/sim/$name"
mkdir -p build/sim
mkdir "$out"

simulate() {
    entrypoint=$1
    shift
    docker run --rm --pull=never --network none --platform linux/arm64 -v "$PWD:/work" \
        -w /work --entrypoint "$entrypoint" jotego/simulator:arm64 "$@"
}

set --
case "$mode" in
    capture) set -- +same_edge ;;
    buffered) ;;
    *) exit 2 ;;
esac
simulate verilator --binary --timing --assert -j 2 -Wno-fatal -Wno-lint \
    --top-module return_tb --Mdir "$out/obj" "$wrapper" "$fixture" > "$out/build.log" 2>&1
simulate "/work/$out/obj/Vreturn_tb" "$@" > "$out/run.log" 2>&1
rg '^PASS D line return' "$out/run.log"
