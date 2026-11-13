#!/bin/sh
# Stock private original instructions, bounded CPU/board fixture; no patches.
set -eu
out=${2:-scratch/ngage2-integration/keypad-flow-2026-11-11}
mkdir -p "$out"
arm-none-eabi-gcc -c -mcpu=arm920t -marm tests/phone/keypad/original/program.S -o "$out/program.o"
arm-none-eabi-ld -T sim/programs/link.ld "$out/program.o" -o "$out/program.elf"
arm-none-eabi-objcopy -O binary "$out/program.elf" "$out/program.bin"
python3 -B tests/phone/keypad/original/prepare.py "$1" "$out"
docker run --rm --pull=never --network none --platform linux/arm64 \
 -v "$PWD:/src:ro" -v "$PWD/$out:/out" -w /src --entrypoint sh jotego/simulator:arm64 -c '
set -eu
sources="rtl/ngage_cpu.sv rtl/arm/*.sv rtl/ngage_bram.v rtl/arm920/*.sv rtl/ngage_keypad.v rtl/ngage_mmc_host.v rtl/ngage_mmc_card.v rtl/ngage_mmc_dpram.v rtl/ngage_board.v rtl/ngage_upp.v rtl/ngage_upp_peripherals.v rtl/ngage_upp_euart.v rtl/ngage_uem.v rtl/ngage_adsp.v rtl/ngage_lrb2.v rtl/ngage_mjoelner.v rtl/ngage_bram_be.v rtl/ngage_sparse_regs.v rtl/ngage_icu.v rtl/ngage_icu_extra.v rtl/ngage_timers.v rtl/ngage_nos_io.v rtl/ngage_mdi_stub.v rtl/ngage_upp_dsp_peer.v rtl/ngage_upp_mdi.v rtl/ngage_cbus_uem.v rtl/ngage_gpio_loopback.v rtl/ngage_boot_regs.v rtl/ngage_trace_sink.v"
for hz in 104000000 78000000; do
 verilator --binary --timing --assert -j 2 -GSYS_CLK_HZ="$hz" -DNGAGE_RUNTIME_TRACE -Wno-fatal -Wno-lint -Irtl/arm --top-module tb --Mdir "/out/obj-$hz" $sources tests/phone/keypad/original/tb.v > "/out/original-build-$hz.log" 2>&1
 for waits in 0 3; do
  "/out/obj-$hz/Vtb" +ngage-compact-trace +program=/out/program.hex +app=/out/app.hex +wait="$waits" > "/out/original-$hz-wait$waits.log" 2>&1
  grep "^PASS" "/out/original-$hz-wait$waits.log"
 done
done'
