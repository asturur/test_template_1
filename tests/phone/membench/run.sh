#!/bin/sh
# membench and memtest on the whole board: the phone CPU, the SDRAM service
# with the chip model, the production DDR flash adapter and cache. No
# firmware is needed: the guest is the flash image. Run from the repository
# root with Verilator 5 and the ARM GNU binutils on the path (or inside the
# simulator image).
#   MHZ=78|104 (default 78)   FLASH_CACHE=bytes (default: Template.sv's)
#   PHONE_SDRAM_MODEL=mt48lc16m16a2.v of the other SDRAM tests
set -eu
MHZ=${MHZ:-78}
cache=${FLASH_CACHE:-$(sed -n 's/.*localparam D2_FLASH_CACHE_BYTES = \([0-9]*\);.*/\1/p' Template.sv)}
out=build/sim/membench-$MHZ
dir=tests/phone/membench
mkdir -p "$out"
for guest in membench memtest; do
    arm-none-eabi-as -mcpu=arm9tdmi -mfloat-abi=soft -o "$out/$guest.o" "$dir/$guest.S"
    if [ "$guest" = membench ]; then arm-none-eabi-ld -T "$dir/membench.ld" -o "$out/$guest.elf" "$out/$guest.o"
    else arm-none-eabi-ld -Ttext=0 -o "$out/$guest.elf" "$out/$guest.o"; fi
    arm-none-eabi-objcopy -O binary "$out/$guest.elf" "$out/$guest.bin"
    python3 "$dir/bench_tb.py" "$out/$guest.bin" "${PHONE_SDRAM_MODEL:-scratch/sdram-reference/mt48lc16m16a2.v}" "$out/$guest"
done
# the DDR3 port's first read beat: about 144 ns on a DE10-Nano
verilator --binary --timing -j 4 -O3 --x-assign fast --x-initial fast -CFLAGS -O2 \
    -GLINE_REFILL=1 -GSHORT_READS=1 -GBOUNDED_CYCLES=400000000 -GSYS_CLK_HZ=${MHZ}000000 -GROM_CACHE=0 \
    -GTIMER_CLK_DIV=$((MHZ / 26)) -GNOS_TICK_HZ=64 -GDDR_LAT=$((MHZ * 144 / 1000)) -GFLASH_CACHE=$cache \
    -DNGAGE_ARM9V2 -DNGAGE_REAL_SDRAM -DNGAGE_PRODUCTION_DDR -DNGAGE_RUNTIME_TRACE \
    -Wno-fatal -Wno-lint --top-module tb --Mdir "$out/obj" \
    rtl/ngage_cpu.sv rtl/arm9v2/arm925t_phone.v rtl/arm9v2/upstream/sim/stubs/*.sv \
    rtl/ngage_bram.v rtl/ngage_debug_font.v rtl/ngage_debug_monitor.v rtl/ngage_debug_video.v rtl/ngage_mister.v \
    rtl/ngage_lcd_display.v rtl/ngage_lcd_dma.v rtl/ngage_dma_channels.v rtl/ngage_dma_engine.v rtl/ngage_dma_route.v \
    rtl/ngage_lcd_stream.v rtl/ngage_dma_ram_mux.v rtl/ngage_keypad.v rtl/ngage_diagnostics.v rtl/ngage_sdram_arbiter.v \
    rtl/ngage_sdram_fast.v rtl/sdram/ngage2_sdram.sv rtl/ngage_sdram_clock.v tests/phone/sdram/ddio_model.v \
    "$out/membench/mt48lc16m16a2-verilator.v" rtl/ngage_ddr_arbiter.v rtl/ngage_ddr_adapter.v rtl/ngage_ddr_stream.v \
    rtl/ngage_ddr_stream_legacy.v rtl/ngage_ddr_rom_cache.v rtl/jtframe/ngage_jtframe_romrq_lcache.v rtl/ngage_ddr_lanes.sv \
    rtl/ngage_ddr_flash_adapter.v rtl/ngage_ddr_flash_cache.v \
    rtl/ngage_simif.v rtl/ngage_test_sim.v rtl/ngage_mmc_host.v rtl/ngage_mmc_card.v rtl/ngage_mmc_dpram.v rtl/ngage_board.v \
    rtl/ngage_upp.v rtl/ngage_upp_peripherals.v rtl/ngage_upp_euart.v rtl/ngage_uem.v rtl/ngage_adsp.v \
    rtl/ngage_adsp_bootstrap_tx.v rtl/ngage_adsp_diagnostic.v rtl/ngage_aic23.v rtl/ngage_lrb2.v rtl/ngage_mjoelner.v \
    rtl/ngage_bram_be.v rtl/ngage_sparse_regs.v rtl/ngage_icu.v rtl/ngage_icu_extra.v rtl/ngage_timers.v rtl/ngage_nos_io.v \
    rtl/ngage_mdi_stub.v rtl/ngage_upp_dsp_peer.v rtl/ngage_upp_mdi.v rtl/ngage_cbus_uem.v rtl/ngage_gpio_loopback.v \
    rtl/ngage_boot_regs.v rtl/ngage_trace_sink.v rtl/ngage_rom_map.sv rtl/ngage_am29n643_state.v rtl/ngage_codeflash.sv \
    rtl/ngage_cflash.sv rtl/ngage_flash_read_decode.v rtl/ngage_descramble.v "$out/membench/tb_bench.v" > "$out/build.log" 2>&1 \
    || { tail -30 "$out/build.log"; exit 1; }
for guest in memtest membench; do
    "$out/obj/Vtb" +ngage-compact-trace +no-board-log +core="$out/$guest/core.bin" \
        +extension="$out/$guest/extension.bin" +cdrive="$out/$guest/cdrive.img" > "$out/$guest.log" 2>&1 \
        || { tail -20 "$out/$guest.log"; exit 1; }
    grep -q '^BENCH_END .* errors=0 data_errors=0' "$out/$guest.log"
    if grep -q -e FAIL -e exception "$out/$guest.log"; then grep -e FAIL -e exception "$out/$guest.log"; exit 1; fi
    python3 "$dir/table.py" "$out/$guest.log" "$MHZ"
done
