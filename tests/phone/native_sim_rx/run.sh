#!/bin/sh
set -eu
out=build/sim/unit-native-sim-rx
mkdir -p "$out"
arm-none-eabi-gcc -c -mcpu=arm920t -marm tests/phone/native_sim_rx/program.S -o "$out/program.o"
arm-none-eabi-ld -T sim/programs/link.ld "$out/program.o" -o "$out/program.elf"
arm-none-eabi-objcopy -O binary "$out/program.elf" "$out/program.bin"
python3 tests/phone/native_sim_rx/prepare.py
docker run --rm --pull=never --network none -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 -c '
set -eu
out=build/sim/unit-native-sim-rx
verilator --binary --timing --assert -j 2 -Wno-fatal -Wno-lint -Irtl/arm --top-module tb --Mdir "$out/obj" rtl/ngage_bram.v rtl/ngage_cpu.sv rtl/ngage_simif.v rtl/ngage_test_sim.v rtl/arm/*.sv rtl/arm920/*.sv rtl/ngage_mmc_host.v rtl/ngage_mmc_card.v rtl/ngage_mmc_dpram.v rtl/ngage_board.v rtl/ngage_upp.v rtl/ngage_upp_peripherals.v rtl/ngage_upp_euart.v rtl/ngage_uem.v rtl/ngage_adsp.v rtl/ngage_adsp_bootstrap_tx.v rtl/ngage_adsp_diagnostic.v rtl/ngage_aic23.v rtl/ngage_lrb2.v rtl/ngage_mjoelner.v rtl/ngage_bram_be.v rtl/ngage_sparse_regs.v rtl/ngage_icu.v rtl/ngage_icu_extra.v rtl/ngage_timers.v rtl/ngage_nos_io.v rtl/ngage_mdi_stub.v rtl/ngage_upp_dsp_peer.v rtl/ngage_upp_mdi.v rtl/ngage_cbus_uem.v rtl/ngage_gpio_loopback.v rtl/ngage_boot_regs.v rtl/ngage_trace_sink.v tests/phone/native_sim_rx/tb.v > "$out/build.log" 2>&1
for card in 0 1; do
for cache in 0 1; do
 for wait in 0 3; do
  "$out/obj/Vtb" +card="$card" +cached="$cache" +wait="$wait" > "$out/run-$card-$cache-$wait.log" 2>&1
  grep "^PASS" "$out/run-$card-$cache-$wait.log"
 done
done
done'
