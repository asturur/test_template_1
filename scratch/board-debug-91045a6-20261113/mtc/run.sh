#!/bin/sh
set -eu
out=scratch/board-debug-91045a6-20261113/mtc
for name in program trace; do
 arm-none-eabi-gcc -c -march=armv4t "$out/$name.S" -o "$out/$name.o"
 script=test.ld
 if [ "$name" = trace ]; then script=link.ld; fi
 arm-none-eabi-ld -T "$out/$script" "$out/$name.o" -o "$out/$name.elf"
 arm-none-eabi-objcopy -O binary "$out/$name.elf" "$out/$name.bin"
done
python3 - <<'BUILD'
from pathlib import Path
import subprocess
p=Path('scratch/board-debug-91045a6-20261113/mtc')
symbols={x[2]:int(x[0],16) for line in subprocess.check_output(['arm-none-eabi-nm',str(p/'program.elf')],text=True).splitlines() if len(x:=line.split())==3}
assert symbols['original']==0xb8 and symbols['returned']==0x44,'fixture mock addresses changed'
for name,size in [('program',2048),('trace',4096)]:
 b=(p/(name+'.bin')).read_bytes();assert len(b)<=size;b=b.ljust(size,b'\0')
 (p/(name+'.hex')).write_text(''.join(f'{int.from_bytes(b[i:i+4],"little"):08x}\n' for i in range(0,len(b),4)))
s='M MTC msg/action/lr/0958/095c/df48/sim 00000064 00000006 00000044 00000000 00000000 00000000 00000000\nM TESTS '+''.join(f'{int.from_bytes(bytes(range(i,i+4)),"little"):08x} ' for i in range(0,24,4))+'\n'
assert len(s)==165
(p/'expected.hex').write_text(''.join(f'{v:02x}\n' for v in s.encode()))
BUILD
docker run --rm --pull=never --network none --platform linux/arm64 -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 -c '
 for waits in 0 3; do
  out=scratch/board-debug-91045a6-20261113/mtc
  verilator --binary --timing --assert -j 2 -GWAIT_CYCLES=$waits -Wno-fatal -Wno-lint -Irtl/arm --top-module tb --Mdir "$out/obj-$waits" rtl/ngage_cpu.sv rtl/arm/*.sv rtl/ngage_bram.v rtl/arm920/*.sv "$out/tb.v" > "$out/build-results-$waits.log" 2>&1
  "$out/obj-$waits/Vtb" > "$out/run-results-$waits.log" 2>&1
  grep "^PASS" "$out/run-results-$waits.log"
 done'
