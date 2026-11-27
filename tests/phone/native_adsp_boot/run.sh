#!/bin/sh
set -eu
out=build/sim/unit-native-adsp-boot
mkdir -p "$out"
docker run --rm --pull=never --network none --platform linux/arm64 -v "$PWD:/work" -w /work --entrypoint sh -e PYTHONPATH=/work/scratch/profile-records-20261113/linux-unicorn/site jotego/simulator:arm64 -c 'python3 tests/tools/test_native_adsp_boot_protocol.py --emit build/sim/unit-native-adsp-boot'

arm-none-eabi-gcc -c -mcpu=arm920t -marm tests/phone/native_adsp_boot/program.S -o "$out/program.o"
arm-none-eabi-ld -T sim/programs/link.ld "$out/program.o" -o "$out/program.elf"
arm-none-eabi-objcopy -O binary "$out/program.elf" "$out/program.bin"
python3 -B tests/phone/native_adsp_boot/prepare.py
docker run --rm --pull=never --network none --platform linux/arm64 -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 -c '
set -eu
out=build/sim/unit-native-adsp-boot
verilator --binary --timing --assert -j 2 -Wno-fatal -Wno-lint -Irtl/arm --top-module tb --Mdir "$out/obj" rtl/ngage_cpu.sv rtl/arm/*.sv rtl/ngage_bram.v rtl/arm920/*.sv rtl/ngage_mmc_host.v rtl/ngage_mmc_card.v rtl/ngage_mmc_dpram.v rtl/ngage_board.v rtl/ngage_upp.v rtl/ngage_upp_peripherals.v rtl/ngage_upp_euart.v rtl/ngage_uem.v rtl/ngage_adsp.v rtl/ngage_adsp_bootstrap_tx.v rtl/ngage_adsp_diagnostic.v rtl/ngage_aic23.v rtl/ngage_lrb2.v rtl/ngage_mjoelner.v rtl/ngage_bram.v rtl/ngage_bram_be.v rtl/ngage_sparse_regs.v rtl/ngage_icu.v rtl/ngage_icu_extra.v rtl/ngage_timers.v rtl/ngage_nos_io.v rtl/ngage_mdi_stub.v rtl/ngage_upp_dsp_peer.v rtl/ngage_upp_mdi.v rtl/ngage_cbus_uem.v rtl/ngage_gpio_loopback.v rtl/ngage_boot_regs.v rtl/ngage_trace_sink.v tests/phone/native_adsp_boot/tb.v > "$out/build.log" 2>&1
for rate in 78 104; do
 case "$rate" in
  78) half=6.410256 ;;
  104) half=4.807692 ;;
 esac
 for wait in 0 3; do
  "$out/obj/Vtb" +wait="$wait" +half_period="$half" > "$out/run-$rate-$wait.log" 2>&1
  grep "^PASS" "$out/run-$rate-$wait.log"
 done
done'
docker run --rm --pull=never --network none --platform linux/arm64 -v "$PWD:/work" -w /work --entrypoint sh -e PYTHONPATH=/work/scratch/profile-records-20261113/linux-unicorn/site jotego/simulator:arm64 -c 'python3 tests/tools/test_native_adsp_boot_protocol.py --capture build/sim/unit-native-adsp-boot/run-78-0.log'

