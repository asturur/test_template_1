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
arm-none-eabi-gcc -c -mcpu=arm920t -marm "$fixture/contract.S" -o "$out/guest.o"
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
    rtl/ngage_cpu.sv rtl/ngage_upp.v rtl/arm9v2/arm925t_phone.v \
    rtl/arm9v2/upstream/sim/stubs/*.sv "$fixture/contract.v" > "$out/build.log" 2>&1
for burst in 0 1; do
    for wait in 0 5; do
        log="$out/burst-$burst-wait-$wait.log"
        simulation "/work/$out/obj/Vcontract" "$image" "+program=$out/guest.hex" "+wait=$wait" "+burst=$burst" > "$log" 2>&1
        grep -E '^(PASS|LINES) ' "$log"
    done
done
