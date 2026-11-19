#!/bin/sh
set -eu

name="${1:?provide a fresh run name}"
case "$name" in *[!A-Za-z0-9_.-]*) exit 2 ;; esac
out="build/sim/$name"
model="${PHONE_SDRAM_MODEL:-build/sim/unit-hardware-boot-real-sdram/mt48lc16m16a2-verilator.v}"
mkdir "$out"
cp "$model" "$out/mt48lc16m16a2.v"
awk '/^set_global_assignment -name (SYSTEMVERILOG_FILE|VERILOG_FILE)/ && $4 != "Template.sv" {print $4}' \
    files.qip > "$out/rtl.f"

simulate() {
    docker run --rm --pull=never --network none --platform linux/arm64 -v "$PWD:/work" \
        -w /work --entrypoint "$@"
}
run() {
    burst=$1
    image=jotego/simulator:arm64
    simulate verilator "$image" --binary --timing --assert -j 2 -Wno-fatal -Wno-lint \
        --top-module physical_lcd_stream_tb "-GLCD_LINE_BYTES=$burst" --Mdir "$out/obj-$burst" \
        -DNGAGE_ARM9V2 -Irtl/arm -f "$out/rtl.f" tests/phone/sdram/ddio_model.v \
        tests/phone/lcd_stream/physical_tb.sv "$out/mt48lc16m16a2.v" > "$out/build-$burst.log" 2>&1
    exe="/work/$out/obj-$burst/Vphysical_lcd_stream_tb"
    for config in aligned contend moderate unaligned cancel refills; do
        log="$out/$burst-$config.log"
        simulate "$exe" "$image" "+$config" > "$log" 2>&1
        rg '^LCD_RESULT|^PASS' "$log"
    done
}

run 0 &
control=$!
run 16 &
half=$!
run 32 &
full=$!
status=0
wait "$control" || status=1
wait "$half" || status=1
wait "$full" || status=1
exit "$status"
