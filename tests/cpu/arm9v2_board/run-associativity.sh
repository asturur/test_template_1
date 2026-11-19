#!/bin/sh
set -eu

mode=${1:?pass line, packed, or half}
case "$mode" in line|packed|half) ;; *) exit 2 ;; esac
shift
scope=all
if [ "${1:-}" = '--qualify-only' ]; then scope=qualify; shift; fi
if [ "$#" -eq 0 ]; then set -- 2 4 8 16 32 64; fi
fixture=${NGAGE_FIXTURES:-/Users/andreabogazzi/develop/NGage_MiSTer/tests/cpu}
status=0

run_leg() {
    leg="v5-assoc-$mode-$ways"
    out="build/arm9v2-assoc/$mode-$ways"
    if [ "$scope" = qualify ]; then
        leg="$leg-directed"
        out="$out-directed"
    fi
    netlist="$out/arm925t_phone.v"
    python3 -B tools/gen_arm9v2_cache_experiment.py --iways "$ways" --dways "$ways" \
        --dirty "$mode" --output "$netlist" || return
    ctype=$(sed -n "s/.*\.CP15_CTYPE(32'h\([0-9a-f]*\)).*/0x\1/p" "$netlist")
    half_writeback=0
    if [ "$mode" = half ]; then half_writeback=1; fi
    ARM9V2_CTYPE="$ctype" ARM9V2_NETLIST="$netlist" ARM9V2_ASSOC_WAYS="$ways" \
        ARM9V2_HALF_WRITEBACK="$half_writeback" sh tests/cpu/arm9v2_board/run-contract.sh "$leg" \
        > "$out/contract.log" 2>&1 &
    contract_job=$!
    if [ "$scope" = qualify ]; then wait "$contract_job"; return; fi
    python3 -B tests/cpu/ngage2_compare/run.py --cpu arm9v2 --name "$leg" \
        --arm9v2-netlist "$netlist" --payload-dir "$fixture/spmark_payload/local" \
        > "$out/spmark.log" 2>&1 &
    spmark_job=$!
    checked=0
    wait "$contract_job" || checked=1
    wait "$spmark_job" || return
    python3 -B tests/cpu/arm9v2_board/games.py --name "$leg-games" --fixtures "$fixture" \
        --leg "arm9v2=$leg" --workers 3 > "$out/games.log" 2>&1 &
    games_job=$!
    python3 -B tests/cpu/arm9v2_board/games.py --name "$leg-sega" --fixtures "$fixture" \
        --leg "arm9v2=$leg" --sega-scan-only --workers 6 > "$out/sega.log" 2>&1 &
    sega_job=$!
    python3 -B tests/cpu/ngage2_compare/jpeg.py --cpu arm9v2 --name "$leg-jpeg" \
        --arm9v2-netlist "$netlist" --jpeg "$fixture/spmark_payload/local/TEST.JPG" \
        > "$out/jpeg.log" 2>&1 &
    jpeg_job=$!
    wait "$games_job" || checked=1
    wait "$sega_job" || checked=1
    wait "$jpeg_job" || checked=1
    return "$checked"
}

for ways do
    case "$ways" in 2|4|8|16|32|64) ;; *) exit 2 ;; esac
    printf '%s\n' "Starting $mode-dirty $ways-way build"
    if run_leg; then
        printf '%s\n' "PASS $mode-dirty $ways-way build"
    else
        printf '%s\n' "FAIL $mode-dirty $ways-way build. See $out." >&2
        status=1
    fi
done
exit "$status"
