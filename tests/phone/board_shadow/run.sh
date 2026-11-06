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
# Test both comparison mode and exclusive HDL peripheral ownership.
good=$(arm-none-eabi-nm "$out/program.elf" | awk '$3 == "good" {print $1}')
for mode in shadow exclusive; do
 option=""
 if [ "$mode" = exclusive ]; then option=hdl-exclusive; fi
 docker run --rm --network none --platform linux/arm64 -v "$PWD:/work" -w /work --entrypoint /work/build/sim/obj-current-hdl-board/Vngage_cpu_sim jotego/simulator:arm64 /work/"$out"/program.bin 10000 3 /work/"$out"/"$mode"-trace.tsv /work/"$out"/"$mode"-bus.tsv /work/"$out"/"$mode"-cp15.tsv /work/"$out"/"$mode"-result.json amd16 ideal-clocks boot-io-probe keypad-gpio epbus-clkblk icu-banks timer-irq-delay=1 timer-compare-probe icu1c8-probe timer-periodic block14d-probe debug59-sink nos-periph-4000 $option > "$out/$mode-run.log" 2>&1 || true
 python3 - "$out/$mode-result.json" "$good" "$mode" <<'PYTEST'
import json,sys
r=json.load(open(sys.argv[1])); mode=sys.argv[3]
assert r['status'] == 'firmware_loop',r['status']
assert r['hdl_board_claims'] == 24,r['hdl_board_claims']
assert r['blocked_address'] == int(sys.argv[2],16),hex(r['blocked_address'])
assert r['hdl_exclusive'] == (mode=='exclusive')
if mode=='exclusive':
 assert r['hdl_memory_fallbacks']>0
 assert r['boot_profile']['ideal_boot_cbus_transactions']==0
 assert r['boot_profile']['keypad_registers']==0
print('PASS CPU board '+mode+' ownership and stalled transactions')
PYTEST
done
