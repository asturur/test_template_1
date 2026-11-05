#!/bin/sh
set -eu
out=build/sim/unit-board-shadow
mkdir -p "$out"
arm-none-eabi-gcc -c -mcpu=arm920t -marm tests/phone/board_shadow/program.S -o "$out/program.o"
arm-none-eabi-ld -T sim/programs/link.ld "$out/program.o" -o "$out/program.elf"
arm-none-eabi-objcopy -O binary "$out/program.elf" "$out/program.bin"
# Supply the minimal boot-bank table expected by the software board model.
python3 - "$out/program.bin" <<'PYROM'
import struct,sys
p=sys.argv[1]; b=bytearray(open(p,'rb').read()); b.extend(bytes(4096-len(b)))
struct.pack_into('<I',b,0x830,2)
struct.pack_into('<IIII',b,0x838,0,4096,1,0)
struct.pack_into('<IIII',b,0x848,0x0a000000,0x10000,2,0)
open(p,'wb').write(b)
PYROM
# The CPU intentionally ends in a self-loop; timeout is not test success by itself.
docker run --rm --network none --platform linux/arm64 -v "$PWD:/work" -w /work --entrypoint /work/build/sim/obj-current-hdl-board/Vngage_cpu_sim jotego/simulator:arm64 /work/"$out"/program.bin 10000 3 /work/"$out"/trace.tsv /work/"$out"/bus.tsv /work/"$out"/cp15.tsv /work/"$out"/result.json amd16 ideal-clocks boot-io-probe keypad-gpio > "$out/run.log" 2>&1 || true
good=$(arm-none-eabi-nm "$out/program.elf" | awk '$3 == "good" {print $1}')
python3 - "$out/result.json" "$good" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
assert r['status'] == 'firmware_loop',r
assert r['hdl_board_claims'] == 14,r
assert r['blocked_address'] == int(sys.argv[2],16),r
print('PASS CPU/C++/HDL shadow bus transactions and stalled accesses')
PY
