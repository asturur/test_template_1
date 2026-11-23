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
    --top-module probe_tb --Mdir "$out/obj" rtl/ngage_upp.v rtl/ngage_icu_extra.v \
    rtl/ngage_bram.v tests/phone/register_ram/probe_tb.sv > "$out/build.log" 2>&1
simulate "/work/$out/obj/Vprobe_tb" > "$out/run.log" 2>&1
rg '^PASS ICU probe prefetch' "$out/run.log"
