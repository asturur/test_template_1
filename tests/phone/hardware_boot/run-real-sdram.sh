#!/bin/sh
set -eu
mkdir -p build/sim/unit-hardware-boot-real-sdram
# Verilator is two-state: the vendor model's == X diagnostic treats X as 0.
# Keep the memory protocol intact and disable only this invalid X check.
python3 - <<'PYMODEL'
from pathlib import Path
p=Path('scratch/sdram-reference/mt48lc16m16a2.v')
s=p.read_text(encoding="latin-1")
old="if (Dqm[0] === 1'bx || Dqm[1]== 1'bx) begin"
assert s.count(old)==1
s=s.replace(old,"if (1'b0) begin")
# Verilator is two-state: Z on this temporary makes its procedural writes
# resolve as separate drivers and returns stale data. Masked read lanes have
# no valid value; choose zero only inside this test-only reference copy.
s=s.replace("Dq_dqm [ 7 : 0] = 8'bz;", "Dq_dqm [ 7 : 0] = 8'b0;")
s=s.replace("Dq_dqm [15 : 8] = 8'bz;", "Dq_dqm [15 : 8] = 8'b0;")
s=s.replace('downloading, VS, frame_cnt );','downloading, VS, frame_cnt, Dq_write );',1)
s=s.replace('inout     [data_bits - 1 : 0] Dq;','inout [data_bits - 1 : 0] Dq; input [data_bits - 1 : 0] Dq_write;',1)
s=s.replace('= Dq [ 7 : 0];','= Dq_write [ 7 : 0];').replace('= Dq [15 : 8];','= Dq_write [15 : 8];')
Path('build/sim/unit-hardware-boot-real-sdram/mt48lc16m16a2-verilator.v').write_text(s)
PYMODEL
docker run --rm --pull=never --network none --platform linux/arm64 -e PHONE_SYS_CLK_HZ="${PHONE_SYS_CLK_HZ:-104000000}" -e PHONE_ROM_CACHE="${PHONE_ROM_CACHE:-0}" -e PHONE_LINE_REFILL="${PHONE_LINE_REFILL:-0}" -e PHONE_SHORT_READS="${PHONE_SHORT_READS:-0}" -e PHONE_CYCLES="${PHONE_CYCLES:-5000000}" -e PHONE_CORE="${PHONE_CORE:-build/firmware/nem4-factory/core.bin}" -e PHONE_EXTENSION="${PHONE_EXTENSION:-build/firmware/nem4-factory/extension.bin}" -e PHONE_CDRIVE="${PHONE_CDRIVE:-scratch/overnight/cdrive-11b.img}" -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 -c 'verilator --binary --timing -j 4 -GLINE_REFILL="$PHONE_LINE_REFILL" -GSHORT_READS="$PHONE_SHORT_READS" -GBOUNDED_CYCLES="$PHONE_CYCLES" --assert -GSYS_CLK_HZ="$PHONE_SYS_CLK_HZ" -GROM_CACHE="$PHONE_ROM_CACHE" -DNGAGE_REAL_SDRAM -DNGAGE_RUNTIME_TRACE -Wno-fatal -Wno-lint -Irtl/arm --top-module tb --Mdir build/sim/unit-hardware-boot-real-sdram/obj rtl/ngage_cpu.sv rtl/arm/*.sv rtl/ngage_bram.v rtl/arm920/*.sv rtl/ngage_debug_font.v rtl/ngage_debug_monitor.v rtl/ngage_debug_video.v rtl/ngage_mister.v rtl/ngage_lcd_display.v rtl/ngage_lcd_dma.v rtl/ngage_dma_channels.v rtl/ngage_dma_engine.v rtl/ngage_dma_route.v rtl/ngage_lcd_stream.v rtl/ngage_dma_ram_mux.v rtl/ngage_keypad.v rtl/ngage_diagnostics.v rtl/ngage_sdram_arbiter.v rtl/ngage_sdram_adapter.v rtl/ngage_sdram_clock.v tests/phone/sdram/ddio_model.v rtl/sdram/jtframe_sdram64*.v build/sim/unit-hardware-boot-real-sdram/mt48lc16m16a2-verilator.v rtl/ngage_ddr_arbiter.v rtl/ngage_ddr_adapter.v rtl/ngage_ddr_stream.v rtl/ngage_ddr_stream_legacy.v rtl/ngage_ddr_rom_cache.v rtl/jtframe/ngage_jtframe_romrq_lcache.v rtl/ngage_ddr_lanes.sv rtl/ngage_simif.v rtl/ngage_test_sim.v rtl/ngage_mmc_host.v rtl/ngage_mmc_card.v rtl/ngage_mmc_dpram.v rtl/ngage_board.v rtl/ngage_upp.v rtl/ngage_upp_peripherals.v rtl/ngage_upp_euart.v rtl/ngage_uem.v rtl/ngage_adsp.v rtl/ngage_lrb2.v rtl/ngage_mjoelner.v rtl/ngage_bram_be.v rtl/ngage_sparse_regs.v rtl/ngage_icu.v rtl/ngage_icu_extra.v rtl/ngage_timers.v rtl/ngage_nos_io.v rtl/ngage_mdi_stub.v rtl/ngage_upp_dsp_peer.v rtl/ngage_upp_mdi.v rtl/ngage_cbus_uem.v rtl/ngage_gpio_loopback.v rtl/ngage_boot_regs.v rtl/ngage_trace_sink.v rtl/ngage_rom_map.sv rtl/ngage_am29n643_state.v rtl/ngage_codeflash.sv rtl/ngage_cflash.sv rtl/ngage_flash_read_decode.v rtl/ngage_descramble.v tests/phone/hardware_boot/tb.v > build/sim/unit-hardware-boot-real-sdram/build.log 2>&1 && build/sim/unit-hardware-boot-real-sdram/obj/Vtb +ngage-compact-trace +no-board-log +core="$PHONE_CORE" +extension="$PHONE_EXTENSION" +cdrive="$PHONE_CDRIVE" > build/sim/unit-hardware-boot-real-sdram/run.log 2>&1 && grep "^PASS bounded hardware-bound boot" build/sim/unit-hardware-boot-real-sdram/run.log'
