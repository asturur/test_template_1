#!/bin/sh
# Host ARM binutils and the existing simulator image. Private fixtures required.
set -eu
out=build/sim/unit-nos-abi
mkdir -p "$out"
arm-none-eabi-gcc -c -mcpu=arm920t -marm tests/phone/nos_abi/program.S -o "$out/program.o"
arm-none-eabi-ld -T sim/programs/link.ld "$out/program.o" -o "$out/program.elf"
arm-none-eabi-objcopy -O binary "$out/program.elf" "$out/program.bin"
python3 -B tests/phone/nos_abi/prepare.py "$1" "$2" "$3" "$out"
docker run --rm --pull=never --network none --platform linux/arm64 -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 -c '
set -eu
out=build/sim/unit-nos-abi
verilator --binary --timing --assert -j 2 -DNGAGE_RUNTIME_TRACE -Wno-fatal -Wno-lint -Irtl/arm --top-module tb --Mdir "$out/obj" rtl/ngage_cpu.sv rtl/arm/*.sv rtl/ngage_bram.v rtl/arm920/*.sv tests/phone/nos_abi/tb.v > "$out/build.log" 2>&1
for wait in 0 3; do
 "$out/obj/Vtb" +ngage-compact-trace +wait="$wait" > "$out/run-$wait.log" 2>&1
 grep "^PASS" "$out/run-$wait.log"
done'
