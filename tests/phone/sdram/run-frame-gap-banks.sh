#!/bin/sh
set -eu

name=${1:?provide a fresh run name}
case "$name" in *[!A-Za-z0-9_.-]*) exit 2 ;; esac
out="build/sim/$name"
mkdir "$out"
donor=${NGAGE2_ROOT:-/Users/andreabogazzi/develop/ngage2}
revision=${NGAGE2_REVISION:-ff6dcff}
model=${PHONE_SDRAM_MODEL:-build/sim/unit-hardware-boot-real-sdram/mt48lc16m16a2-verilator.v}
git -C "$donor" rev-parse "$revision^{commit}" > "$out/donor-revision.txt"
for source in rtl/mem/sdram.sv rtl/mem/bram32.sv rtl/upp/upp_bus.sv rtl/board/sdp_ram.sv; do
    git -C "$donor" show "$revision:$source" > "$out/${source##*/}"
done
cp "$model" "$out/mt48lc16m16a2.v"
PYTHONPATH=tests/cpu/arm9v2_board python3 - "$out" <<'PYTHON'
import os
from pathlib import Path
import sys
from frame_gap_interleave import generate

generate(Path(sys.argv[1]))
if os.environ.get('FRAME_GAP_HANDOFF'):
    from frame_gap_handoff import generate as handoff
    for name, admit in [('completion', False), ('admit', True)]:
        destination = Path(sys.argv[1]) / name
        destination.mkdir()
        handoff(destination, admit)
PYTHON

simulate() {
    docker run --rm --pull=never --network none --platform linux/arm64 -v "$PWD:/work" \
        -w /work --entrypoint "$@"
}

run() {
    variant=$1
    set -- rtl/ngage_sdram_adapter.v rtl/sdram/jtframe_sdram64.v -GDONOR="$variant"
    if [ "$variant" -eq 2 ]; then
        set -- "$out/ngage_sdram_adapter.v" "$out/jtframe_sdram64.v" -GDONOR=0 -DFRAME_INTERLEAVE
    elif [ "$variant" -eq 3 ]; then
        set -- "$out/completion/ngage_sdram_adapter.v" rtl/sdram/jtframe_sdram64.v -GDONOR=0
    elif [ "$variant" -eq 4 ]; then
        set -- "$out/admit/ngage_sdram_adapter.v" rtl/sdram/jtframe_sdram64.v -GDONOR=0
    fi
    image=jotego/simulator:arm64
    simulate verilator "$image" --binary --timing --assert -j 2 -Wno-fatal -Wno-lint \
        --top-module frame_gap_banks --Mdir "$out/obj-$variant" "$@" \
        "$out/sdram.sv" "$out/bram32.sv" "$out/sdp_ram.sv" "$out/upp_bus.sv" "$out/mt48lc16m16a2.v" \
        rtl/ngage_sdram_clock.v tests/phone/sdram/ddio_model.v \
        rtl/sdram/jtframe_sdram64_*.v tests/phone/sdram/frame_gap_banks.sv > "$out/build-$variant.log" 2>&1
    executable="/work/$out/obj-$variant/Vframe_gap_banks"
    simulate "$executable" "$image" > "$out/run-$variant.log" 2>&1
    rg '^BANK_RESULT|^SCAN_RESULT|^PASS' "$out/run-$variant.log"
    if [ -n "${FRAME_GAP_TRACES:-}" ]; then
        for trace in "$FRAME_GAP_TRACES"/*-requests.txt; do
            case_name=${trace##*/}
            log="$out/trace-$variant-${case_name%-requests.txt}.log"
            set -- "+trace=/work/$trace"
            if [ -n "${FRAME_GAP_HANDOFF:-}" ]; then set -- "$@" "+timeline=/work/${log%.log}-timeline.txt"; fi
            simulate "$executable" "$image" "$@" > "$log" 2>&1
            rg '^TRACE_RESULT|^PASS' "$log"
        done
    fi
}

run 0 &
v5=$!
run 1 &
ngage2=$!
run 2 &
interleave=$!
status=0
wait "$v5" || status=1
wait "$ngage2" || status=1
wait "$interleave" || status=1
if [ -n "${FRAME_GAP_HANDOFF:-}" ]; then
    run 3 &
    completion=$!
    run 4 &
    admission=$!
    wait "$completion" || status=1
    wait "$admission" || status=1
fi
exit "$status"
