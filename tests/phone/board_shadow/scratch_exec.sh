#!/bin/sh
set -eu
out=build/sim/unit-board-scratch-exec
mkdir -p "$out"
for region in scratch upload asic; do
 value=0;asic=0;target=0x0c004748
 if [ "$region" = upload ];then value=1;target=0x0c030220;fi
 if [ "$region" = asic ];then asic=1;target=0x0c000000;fi
 arm-none-eabi-as -mcpu=arm920t --defsym UPLOAD=$value --defsym ASIC=$asic tests/phone/board_shadow/scratch_exec.S -o "$out/program.o"
arm-none-eabi-ld -T sim/programs/link.ld "$out/program.o" -o "$out/program.elf"
arm-none-eabi-objcopy -O binary "$out/program.elf" "$out/program.bin"
python3 - "$out/program.bin" <<'PY'
import struct,sys
p=sys.argv[1];b=bytearray(open(p,'rb').read());b.extend(bytes(4096-len(b)))
struct.pack_into('<I',b,0x830,2)
struct.pack_into('<IIII',b,0x838,0,4096,1,0)
struct.pack_into('<IIII',b,0x848,0x0a000000,0x10000,2,0)
open(p,'wb').write(b)
PY
good=$(arm-none-eabi-nm "$out/program.elf" | awk '$3 == "good" {print $1}')
for mode in shadow exclusive; do
 opt="";if [ "$mode" = exclusive ];then opt=hdl-exclusive;fi
 docker run --rm --network none --platform linux/arm64 -v "$PWD:/work" -w /work --entrypoint /work/build/sim/obj-current-hdl-board/Vngage_cpu_sim jotego/simulator:arm64 /work/"$out"/program.bin 10000 3 /work/"$out"/"$mode"-trace.tsv /work/"$out"/"$mode"-bus.tsv /work/"$out"/"$mode"-cp15.tsv /work/"$out"/"$mode"-result.json amd16 ideal-clocks boot-io-probe keypad-gpio nos-periph-4000 $opt > "$out/$mode.log" 2>&1 || true
 python3 - "$out/$mode-result.json" "$out/$mode-bus.tsv" "$good" "$mode" "$region" "$target" <<'PY'
import json,sys
r=json.load(open(sys.argv[1])); assert r['status']=='firmware_loop',r['status']
assert r['blocked_address']==int(sys.argv[3],16),hex(r['blocked_address'])
bus=open(sys.argv[2]).read().lower();assert ('\t'+sys.argv[6].lower()+'\t') in bus and '\tcode\t' in bus
print('PASS ARM execution from '+sys.argv[5]+' in '+sys.argv[4]+' mode')
PY
done
done
