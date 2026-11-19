#!/bin/sh
set -eu

name=${1:?specify a fresh run name}
case "$name" in
    *[!A-Za-z0-9_.-]*) echo "Invalid run name: $name" >&2; exit 2 ;;
esac
out=build/sim/arm9v2/contract-"$name"
mkdir -p build/sim/arm9v2
mkdir "$out"
fixture=tests/cpu/arm9v2_board
netlist=${ARM9V2_NETLIST:-rtl/arm9v2/arm925t_phone.v}
section_reads=
case "${ARM9V2_SECTION_INDEX:-}" in
    direct) section_reads=8 ;;
    xor) section_reads=2 ;;
    '') ;;
    *) echo 'ARM9V2_SECTION_INDEX must be direct or xor' >&2; exit 2 ;;
esac
set --
if [ -n "${ARM9V2_ASSOC_WAYS:-}" ]; then set -- "$@" "-DASSOC_WAYS=$ARM9V2_ASSOC_WAYS"; fi
if [ -n "$section_reads" ]; then set -- "$@" -DSECTION_INDEX_TEST; fi
arm-none-eabi-gcc -c -mcpu=arm920t -marm "-DEXPECTED_CTYPE=${ARM9V2_CTYPE:-0x0514a14a}" "$@" "$fixture/contract.S" -o "$out/guest.o"
arm-none-eabi-ld -T sim/programs/link.ld "$out/guest.o" -o "$out/guest.elf"
arm-none-eabi-objcopy -O binary "$out/guest.elf" "$out/guest.bin"
python3 - "$out" <<'PY'
from pathlib import Path
import struct
import sys

out = Path(sys.argv[1])
words = struct.iter_unpack('<I', (out / 'guest.bin').read_bytes())
(out / 'guest.hex').write_text(''.join(f'{word:08x}\n' for (word,) in words))
PY
image=jotego/simulator:arm64
simulation() {
    docker run --rm --pull=never --network none --platform linux/arm64 \
        -v "$PWD:/work" -w /work --entrypoint "$@"
}
simulation verilator "$image" --binary --timing --assert -j 2 \
    -Wno-fatal -Wno-lint -DNGAGE_ARM9V2 --top-module contract --Mdir "$out/obj" \
    rtl/ngage_cpu.sv rtl/ngage_upp.v "$netlist" \
    rtl/arm9v2/upstream/sim/stubs/*.sv "$fixture/contract.v" > "$out/build.log" 2>&1
for burst in 0 1; do
    for wait in 0 5; do
        log="$out/burst-$burst-wait-$wait.log"
        set --
        if [ "${ARM9V2_HALF_WRITEBACK:-0}" = 1 ]; then set -- +half-writeback; fi
        if [ -n "$section_reads" ]; then set -- "$@" "+section-reads=$section_reads"; fi
        simulation "/work/$out/obj/Vcontract" "$image" "+program=$out/guest.hex" "+wait=$wait" "+burst=$burst" "$@" > "$log" 2>&1
        grep -E '^(PASS|LINES|ASSOC|SECTION) ' "$log"
    done
done
