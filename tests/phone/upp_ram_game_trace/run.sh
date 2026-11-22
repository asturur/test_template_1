#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "usage: $0 calibration OUTPUT_DIR" >&2
    echo "       $0 sega|sonic OUTPUT_DIR PROFILE_DIR CARD_IMAGE" >&2
    exit 2
}

[[ $# -ge 2 ]] || usage
case "$1" in
    calibration) [[ $# == 2 ]] || usage ;;
    sega|sonic) [[ $# == 4 ]] || usage ;;
    *) usage ;;
esac

mode=$1
test_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mame_bin=${NGAGE_MAME:-"$HOME/develop/mame/ngagetest"}
rompath=${NGAGE_MAME_ROMPATH:-"$(dirname "$mame_bin")/roms"}
mame_bin=$(realpath "$mame_bin")
rompath=$(realpath "$rompath")
[[ -x "$mame_bin" && -d "$rompath" ]]

if [[ "$mode" != calibration ]]; then
    [[ -d "$3/cfg" && -d "$3/nvram" && -f "$4" ]] || usage
fi
mkdir "$2"
out=$(cd "$2" && pwd)
common=(-noreadconfig -rompath "$rompath" -nothrottle -skip_gameinfo -video none -nodrc -autoboot_delay 0)
export SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy

if [[ "$mode" == calibration ]]; then
    arm-none-eabi-gcc -c -mcpu=arm920t -marm "$test_dir/calibration.S" -o "$out/calibration.o"
    arm-none-eabi-objcopy -O binary "$out/calibration.o" "$out/calibration.bin"
    cd "$out"
    TRACE_PROGRAM="$out/calibration.bin" "$mame_bin" ngage "${common[@]}" \
        -sound none -seconds_to_run 2 -autoboot_script "$test_dir/calibration.lua" > trace.log 2>&1
    grep '^PASS calibrated both physical windows' trace.log
    exit
fi

cp -R "$3/cfg" "$3/nvram" "$out/"
cp "$4" "$out/card.mmc"
chmod a-w "$out/card.mmc"
machine=ngage
qd=0
if [[ "$mode" == sonic ]]; then
    machine=ngageqd
    qd=1
fi
cd "$out"
TRACE_OUTPUT="$out" TRACE_QD="$qd" "$mame_bin" "$machine" "${common[@]}" \
    -mmc "$out/card.mmc" -sound sdl -seconds_to_run 152 \
    -autoboot_script "$test_dir/trace.lua" > trace.log 2>&1
grep -E '^END [0-9.]+ completed=true .*nonzero=[1-9][0-9]*$' trace.log
