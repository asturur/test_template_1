#!/bin/sh
set -eu
out=build/sim/unit-board-shadow-fault
mkdir -p "$out"
for mode in missing dma; do
 value=0
 if [ "$mode" = missing ]; then value=1; fi
 arm-none-eabi-as -mcpu=arm920t --defsym MISSING=$value tests/phone/board_shadow/fault.S -o "$out/$mode.o"
 arm-none-eabi-ld -T sim/programs/link.ld "$out/$mode.o" -o "$out/$mode.elf"
 arm-none-eabi-objcopy -O binary "$out/$mode.elf" "$out/$mode.bin"
 python3 - "$out/$mode.bin" <<'PYROM'
import struct,sys
p=sys.argv[1]; b=bytearray(open(p,'rb').read()); b.extend(bytes(4096-len(b)))
struct.pack_into('<I',b,0x830,2)
struct.pack_into('<IIII',b,0x838,0,4096,1,0)
struct.pack_into('<IIII',b,0x848,0x0a000000,0x10000,2,0)
open(p,'wb').write(b)
PYROM
 docker run --rm --network none --platform linux/arm64 -v "$PWD:/work" -w /work --entrypoint /work/build/sim/obj-current-hdl-board/Vngage_cpu_sim jotego/simulator:arm64 /work/"$out/$mode.bin" 10000 3 /work/"$out/$mode-trace.tsv" /work/"$out/$mode-bus.tsv" /work/"$out/$mode-cp15.tsv" /work/"$out/$mode-result.json" amd16 hdl-exclusive > "$out/$mode-run.log" 2>&1 || true
 python3 - "$out/$mode-result.json" "$mode" <<'PYTEST'
import json,sys
r=json.load(open(sys.argv[1])); mode=sys.argv[2]
assert r['status']==('hdl_missing_device' if mode=='missing' else 'unmapped_access'),r['status']
assert r['blocked_address']==(0x0c160000 if mode=='missing' else 0x0c120348),hex(r['blocked_address'])
print('PASS exclusive HDL '+mode+' refusal')
PYTEST
done
