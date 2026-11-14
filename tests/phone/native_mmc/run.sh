#!/bin/sh
set -eu
out=build/sim/unit-native-mmc
mkdir -p "$out"
arm-none-eabi-gcc -c -mcpu=arm920t -marm tests/phone/native_mmc/program.S -o "$out/program.o"
arm-none-eabi-ld -T sim/programs/link.ld "$out/program.o" -o "$out/program.elf"
arm-none-eabi-objcopy -O binary "$out/program.elf" "$out/program.bin"
python3 tests/phone/native_mmc/prepare.py
docker run --rm --pull=never --network none --platform linux/arm64 -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 -c '
set -eu
out=build/sim/unit-native-mmc
verilator -DNGAGE_RUNTIME_TRACE --binary --timing --assert -j 2 -Wno-fatal -Wno-lint -Irtl/arm --top-module tb --Mdir "$out/obj" rtl/ngage_cpu.sv rtl/arm/*.sv rtl/ngage_bram.v rtl/arm920/*.sv rtl/ngage_mmc_host.v rtl/ngage_icu.v tests/phone/native_mmc/tb.v > "$out/build.log" 2>&1
for wait in 0 3; do "$out/obj/Vtb" +wait="$wait" +ngage-compact-trace > "$out/run-$wait.log" 2>&1; grep "^PASS" "$out/run-$wait.log"; done'
