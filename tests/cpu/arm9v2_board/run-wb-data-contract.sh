#!/bin/sh
# Run from the project root with ARM GNU binutils and the installed Jotego image.
set -eu
reference=${1:?provide the retained a846b87 arm925t_phone.v}
out=${2:-build/sim/wb-data-contract}
fixture=tests/cpu/arm9v2_board
mkdir -p "$(dirname "$out")"
mkdir "$out"
python3 -B "$fixture/prepare_wb_data_contract.py" "$out"
cp "$reference" "$out/reference.v"
arm-none-eabi-gcc -c -mcpu=arm920t -marm -DASSOC_WAYS=2 -DSECTION_INDEX_TEST \
    -I"$fixture" "$out/contract.S" -o "$out/guest.o"
arm-none-eabi-ld -T sim/programs/link.ld "$out/guest.o" -o "$out/guest.elf"
arm-none-eabi-objcopy -O binary "$out/guest.elf" "$out/guest.bin"
python3 - "$out" <<'PY'
from pathlib import Path
from struct import iter_unpack
import sys
out = Path(sys.argv[1])
words = iter_unpack('<I', (out/'guest.bin').read_bytes())
(out/'guest.hex').write_text(''.join(f'{word:08x}\n' for (word,) in words))
PY

docker run --rm --pull=never --network none --platform linux/arm64 \
    -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 -euc '
out=$1
fixture=$2
ulimit -c 0
for mode in word block; do
    block=
    if [ "$mode" = block ]; then block=-DNGAGE_BLOCK_WRITEBACK; fi
    for leg in reference candidate; do
        source=$out/reference.v
        if [ "$leg" = candidate ]; then source=rtl/arm9v2/arm925t_phone.v; fi
        stem="$out/$mode-$leg"
        verilator --binary --timing --assert -j 2 -Wno-fatal -Wno-lint \
            -DNGAGE_ARM9V2 $block --top-module contract --Mdir "$stem-obj" \
            -I"$fixture" rtl/ngage_cpu.sv rtl/ngage_upp.v "$source" \
            rtl/arm9v2/upstream/sim/stubs/*.sv "$out/contract.v" > "$stem-build.log" 2>&1
        for burst in 0 1; do
            for wait in 0 5; do
                name="$stem-burst$burst-wait$wait"
                "$stem-obj/Vcontract" "+program=$out/guest.hex" "+burst=$burst" "+wait=$wait" +section-reads=2 +half-writeback > "$name.log" 2>&1 || {
                    tail -20 "$name.log"
                    exit 1
                }
                grep -E "^(WB_DATA|PASS|LINES|ASSOC|SECTION|DATA_FAULT|REFILL_FAULT) " "$name.log" > "$name.trace"
            done
        done
        reset_log="$stem-reset"
        "$stem-obj/Vcontract" "+program=$out/guest.hex" +burst=1 +wait=5 \
            +section-reads=2 +half-writeback +reset-in-write > "$reset_log.log" 2>&1 || {
                tail -20 "$reset_log.log"
                exit 1
            }
        grep -E "^(WB_DATA|PASS|LINES|ASSOC|SECTION|DATA_FAULT|REFILL_FAULT) " \
            "$reset_log.log" > "$reset_log.trace"
    done
    cmp "$out/$mode-reference-reset.trace" "$out/$mode-candidate-reset.trace"
    printf "%s reset " "$mode"
    grep "^WB_DATA " "$out/$mode-candidate-reset.trace"
    for burst in 0 1; do
        for wait in 0 5; do
            profile="burst$burst-wait$wait"
            cmp "$out/$mode-reference-$profile.trace" "$out/$mode-candidate-$profile.trace"
            printf "%s %s " "$mode" "$profile"
            grep "^WB_DATA " "$out/$mode-candidate-$profile.trace"
        done
    done
done
' sh "$out" "$fixture"
