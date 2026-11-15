#!/bin/sh
# Run on host; build and execute in the existing offline ARM64 image.
set -eu
out="${OUT_DIR:-build/sim/unit-uem-clock-native}"
mkdir -p "$out"
arm-none-eabi-gcc -c -mcpu=arm920t -marm tests/phone/uem_clock/native.S -o "$out/program.o"
arm-none-eabi-ld -T sim/programs/link.ld "$out/program.o" -o "$out/program.elf"
arm-none-eabi-objcopy -O binary "$out/program.elf" "$out/program.bin"
python3 tests/phone/uem_clock/prepare_native.py "$out"
docker run --rm --pull=never --network none --platform linux/arm64 -v "$PWD:/work" -w /work -e OUT_DIR="$out" --entrypoint sh jotego/simulator:arm64 -c '
set -eu
verilator --binary --timing --assert -j 2 -Wno-fatal -Wno-lint -Irtl/arm --top-module tb --Mdir "$OUT_DIR/obj" rtl/ngage_cpu.sv rtl/arm/*.sv rtl/ngage_bram.v rtl/arm920/*.sv rtl/ngage_cbus_uem.v "$OUT_DIR/tb.v" > "$OUT_DIR/build.log" 2>&1
for valid in 0 1; do
 for wait in 0 3; do
  "$OUT_DIR/obj/Vtb" +clock_valid="$valid" +wait="$wait" > "$OUT_DIR/run-$valid-$wait.log" 2>&1
  grep "^PASS" "$OUT_DIR/run-$valid-$wait.log"
 done
done'
