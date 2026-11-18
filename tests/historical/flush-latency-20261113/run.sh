#!/bin/sh
# Frozen scoped probes; separate outputs, no board operations or full phone run.
set -eu
out=scratch/flush-latency-20261113
for payload in io_trace profile_trace; do
 arm-none-eabi-gcc -c -march=armv4t -marm "$out/$payload.S" -o "$out/$payload.o"
 arm-none-eabi-ld -T "$out/$payload.ld" "$out/$payload.o" -o "$out/$payload.elf"
 arm-none-eabi-objcopy -O binary "$out/$payload.elf" "$out/$payload.bin"
done
for program in program profile-program; do
 payload=io_trace
 [ "$program" != profile-program ] || payload=profile_trace
 arm-none-eabi-gcc -c -march=armv4t -marm "$out/$program.S" -o "$out/$program.o"
 arm-none-eabi-ld -R "$out/$payload.elf" -T "$out/test.ld" "$out/$program.o" -o "$out/$program.elf"
 arm-none-eabi-objcopy -O binary "$out/$program.elf" "$out/$program.bin"
done
python3 - <<'PY'
from pathlib import Path
p=Path('scratch/flush-latency-20261113')
for name in ['program','io_trace','profile-program','profile_trace']:
 d=(p/(name+'.bin')).read_bytes();size=2048 if name in ['program','profile-program'] else 4096
 assert len(d)<=size
 d=d.ljust(size,b'\0');(p/(name+'.hex')).write_text(''.join('%08x\n'%int.from_bytes(d[i:i+4],'little') for i in range(0,len(d),4)))
PY
docker run --rm --pull=never --network none --platform linux/arm64 -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 -c '
 for kind in io profile; do
  fixture=tb.v
  [ "$kind" != profile ] || fixture=profile-tb.v
  for waits in 0 3; do
   out=scratch/flush-latency-20261113
   verilator --binary --timing --assert -j 2 -GWAIT_CYCLES=$waits -Wno-fatal -Wno-lint -Irtl/arm --top-module tb --Mdir "$out/obj-check-$kind-$waits" rtl/ngage_cpu.sv rtl/arm/*.sv rtl/ngage_bram.v rtl/arm920/*.sv "$out/$fixture" > "$out/build-check-$kind-$waits.log" 2>&1 && "$out/obj-check-$kind-$waits/Vtb" > "$out/run-check-$kind-$waits.log" 2>&1 || exit $?
   grep "^PASS" "$out/run-check-$kind-$waits.log"
  done
 done'
