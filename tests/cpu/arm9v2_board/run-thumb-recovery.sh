#!/bin/sh
set -eu

name=${1:?provide a fresh run name}
case "$name" in *[!A-Za-z0-9_.-]*) exit 2 ;; esac
out="build/sim/$name"
netlist=${ARM9V2_NETLIST:-rtl/arm9v2/arm925t_phone.v}
mkdir -p build/sim
mkdir "$out"

simulate() {
    entrypoint=$1
    shift
    docker run --rm --pull=never --network none --platform linux/arm64 -v "$PWD:/work" \
        -w /work --entrypoint "$entrypoint" jotego/simulator:arm64 "$@"
}

simulate verilator --binary --timing --assert -j 2 -Wno-fatal -Wno-lint \
    --top-module recovery_tb --Mdir "$out/obj" "$netlist" \
    tests/cpu/arm9v2_board/thumb_recovery_tb.sv > "$out/build.log" 2>&1
simulate "/work/$out/obj/Vrecovery_tb" > "$out/run.log" 2>&1
rg '^PASS Thumb recovery' "$out/run.log"
