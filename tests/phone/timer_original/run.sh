#!/bin/sh
set -eu
out=scratch/ngage2-integration/timer-flow-2026-11-11/original
mkdir -p "$out"
arm-none-eabi-gcc -c -mcpu=arm920t -marm tests/phone/timer_original/program.S -o "$out/program.o"
arm-none-eabi-ld -T sim/programs/link.ld "$out/program.o" -o "$out/program.elf"
arm-none-eabi-objcopy -O binary "$out/program.elf" "$out/program.bin"
python3 -B tests/phone/timer_original/prepare.py "${1:?pass the original NEM-4 ROM dump path}" "$out"
docker run --rm --pull=never --network none --platform linux/arm64 -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 -c '
set -eu
out=scratch/ngage2-integration/timer-flow-2026-11-11/original
for div in 3 4; do
 verilator --binary --timing --assert -j 2 -GDIV="$div" -DNGAGE_RUNTIME_TRACE -Wno-fatal -Wno-lint -Irtl/arm --top-module tb --Mdir "$out/obj-$div" rtl/ngage_cpu.sv rtl/arm/*.sv rtl/ngage_bram.v rtl/arm920/*.sv rtl/ngage_timers.v tests/phone/timer_original/tb.v > "$out/build-$div.log" 2>&1
 for wait in 0 3; do
  "$out/obj-$div/Vtb" +ngage-compact-trace +wait="$wait" > "$out/run-$div-$wait.log" 2>&1
  grep "^PASS" "$out/run-$div-$wait.log"
 done
done'
