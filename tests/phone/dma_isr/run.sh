#!/bin/sh
# Run original private NEM-4 ISR instructions on the actual ZAP CPU.
set -eu
out=${PHONE_TEST_OUT:-scratch/ngage2-integration/lcd-handover/isr}
mkdir -p "$out"
arm-none-eabi-gcc -c -mcpu=arm920t -marm tests/phone/dma_isr/program.S -o "$out/program.o"
arm-none-eabi-ld -T sim/programs/link.ld "$out/program.o" -o "$out/program.elf"
arm-none-eabi-objcopy -O binary "$out/program.elf" "$out/program.bin"
python3 -B tests/phone/dma_isr/prepare.py "$1" "$out"
python3 -B tests/phone/dma_isr/results.py --snapshot
docker image inspect --format '{{.Id}}' jotego/simulator:arm64 > "$out/image-id.txt"
docker run --rm --pull=never --network none --platform linux/arm64 -e PHONE_TEST_OUT="$out" -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 -c '
set -eu
out=$PHONE_TEST_OUT
verilator --binary --timing --assert -j 2 -DNGAGE_RUNTIME_TRACE -Wno-fatal -Wno-lint -Irtl/arm --top-module tb --Mdir "$out/obj" rtl/ngage_cpu.sv rtl/arm/*.sv rtl/ngage_bram.v rtl/arm920/*.sv rtl/ngage_dma_engine.v rtl/ngage_dma_channels.v rtl/ngage_dma_route.v tests/phone/dma_isr/tb.v > "$out/build.log" 2>&1
for wait in 0 3; do
 "$out/obj/Vtb" +ngage-compact-trace +wait="$wait" +program="$out/program.hex" +app="$out/app.hex" > "$out/run-$wait.log" 2>&1
 grep "^PASS" "$out/run-$wait.log"
done'

python3 -B tests/phone/dma_isr/results.py
