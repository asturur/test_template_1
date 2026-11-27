#!/bin/sh
set -eu

name="${1:?provide a fresh run name}"
case "$name" in *[!A-Za-z0-9_.-]*) exit 2 ;; esac
out="build/sim/$name"
hz="${PHONE_SDRAM_SYS_HZ:-78000000}"
model="${PHONE_SDRAM_MODEL:-build/sim/unit-hardware-boot-real-sdram/mt48lc16m16a2-verilator.v}"
mkdir "$out"
cp "$model" "$out/mt48lc16m16a2.v"

docker run --rm --pull=never --network none --platform linux/arm64 -v "$PWD:/work" \
    -w /work --entrypoint verilator jotego/simulator:arm64 --binary --timing --assert -j 2 \
    -Wno-fatal -Wno-lint --top-module stream_tb "-GSYS_HZ=$hz" --Mdir "$out/obj" \
    rtl/ngage_sdram_stream.v rtl/sdram/ngage_sdram_scheduler.v rtl/ngage_sdram_arbiter.v \
    rtl/ngage_sdram_clock.v tests/phone/sdram/ddio_model.v tests/phone/sdram/stream_tb.sv \
    "$out/mt48lc16m16a2.v" > "$out/build.log" 2>&1
docker run --rm --pull=never --network none --platform linux/arm64 -v "$PWD:/work" \
    -w /work --entrypoint "/work/$out/obj/Vstream_tb" jotego/simulator:arm64 > "$out/run.log" 2>&1
if rg '^(ERROR:|FATAL:)' "$out/run.log"; then exit 1; fi
rg '^SCRUB PASS|^REFRESH PASS|^PASS stream' "$out/run.log"
