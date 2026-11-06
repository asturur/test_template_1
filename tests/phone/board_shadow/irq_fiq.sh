#!/bin/sh
set -eu
out=build/sim/unit-board-shadow-irq
mkdir -p "$out"
arm-none-eabi-gcc -c -mcpu=arm920t -marm tests/phone/board_shadow/irq_fiq.S -o "$out/program.o"
arm-none-eabi-ld -T sim/programs/link.ld "$out/program.o" -o "$out/program.elf"
arm-none-eabi-objcopy -O binary "$out/program.elf" "$out/program.bin"
python3 - "$out/program.bin" <<'PYROM'
import struct,sys
p=sys.argv[1]; b=bytearray(open(p,'rb').read()); b.extend(bytes(4096-len(b)))
struct.pack_into('<I',b,0x830,2)
struct.pack_into('<IIII',b,0x838,0,4096,1,0)
struct.pack_into('<IIII',b,0x848,0x0a000000,0x10000,2,0)
open(p,'wb').write(b)
PYROM
set +e
docker run --rm --network none --platform linux/arm64 -v "$PWD:/work" -w /work --entrypoint /work/build/sim/obj-current-hdl-board/Vngage_cpu_sim jotego/simulator:arm64 /work/"$out"/program.bin 100000 3 /work/"$out"/trace.tsv /work/"$out"/bus.tsv /work/"$out"/cp15.tsv /work/"$out"/result.json amd16 ideal-clocks boot-io-probe hdl-exclusive > "$out/run.log" 2>&1
set -e
good=$(arm-none-eabi-nm "$out/program.elf" | awk '$3 == "good" {print $1}')
python3 - "$out/result.json" "$good" <<'PYTEST'
import json,sys
r=json.load(open(sys.argv[1])); assert r['status']=='firmware_loop',r['status']
assert r['blocked_address']==int(sys.argv[2],16),hex(r['blocked_address'])
assert r['hdl_board_claims']>=8,r['hdl_board_claims']
assert r['hdl_exclusive']
assert r['hdl_trace_events']==1 and r['hdl_trace_dropped']==0
trace=open(sys.argv[1].replace('result.json','hdl-board-trace.tsv')).read()
assert '0xde00000\t0x41414141\t0x1' in trace,trace
print('PASS exclusive HDL IRQ/FIQ delivery and acknowledgement')
PYTEST
