#!/bin/sh
set -eu
python3 tests/phone/save_hps/gen.py
# hps_io's legacy PS/2 generate-block references need explicit scope in
# Verilator. This test-only copy leaves its SD and block protocol unchanged.
python3 - <<'PY'
from pathlib import Path
import re
s=Path('sys/hps_io.sv').read_text()
a,b=s.split('///////////////////////////////   PS2   ///////////////////////////////',1)
for name in 'kbd_rd kbd_we kbd_data kbd_data_host mouse_rd mouse_we mouse_data mouse_data_host'.split():
 a=re.sub(r'(?<![\w.])'+name+r'\b','ps2_model.'+name,a)
b=b.replace('if(PS2DIV) begin','if(PS2DIV) begin: ps2_model',1)
Path('build/sim/unit-save-hps/hps-compat.sv').write_text(a+'///////////////////////////////   PS2   ///////////////////////////////'+b)
PY
verilator --binary --timing -Wno-fatal -Wno-lint --top-module tb --Mdir build/sim/unit-save-hps/obj build/sim/unit-save-hps/hps-compat.sv rtl/ngage_bram.v rtl/ngage_sd_sector.sv rtl/ngage_save_sector_bridge.v rtl/ngage_save_header.sv rtl/ngage_dirty_tracker.sv rtl/ngage_save_manager.sv rtl/ngage_diag_export.v tests/phone/save_hps/tb.sv > build/sim/unit-save-hps/build.log 2>&1
build/sim/unit-save-hps/obj/Vtb > build/sim/unit-save-hps/run.log 2>&1
cat build/sim/unit-save-hps/run.log
grep -q '^PASS actual hps_io C/PMM' build/sim/unit-save-hps/run.log
verilator --binary --timing -Wno-fatal -Wno-lint --top-module tb --Mdir build/sim/unit-save-hps/nor-obj build/sim/unit-save-hps/hps-compat.sv rtl/ngage_bram.v rtl/ngage_sd_sector.sv rtl/ngage_save_sector_bridge.v rtl/ngage_save_header.sv rtl/ngage_dirty_tracker.sv rtl/ngage_save_manager.sv rtl/ngage_diag_export.v rtl/ngage_cflash.sv rtl/ngage_am29n643_state.v rtl/ngage_codeflash.sv rtl/ngage_rom_map.sv rtl/ngage_descramble.v rtl/ngage_flash_read_decode.v rtl/ngage_ddr_arbiter.v rtl/ngage_ddr_adapter.v rtl/ngage_ddr_lanes.sv tests/phone/save_hps/nor_tb.sv > build/sim/unit-save-hps/nor-build.log 2>&1
build/sim/unit-save-hps/nor-obj/Vtb > build/sim/unit-save-hps/nor.log 2>&1
cat build/sim/unit-save-hps/nor.log
grep -q '^PASS actual NOR, DDR and hps_io' build/sim/unit-save-hps/nor.log
