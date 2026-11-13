#!/bin/sh
set -eu
mkdir -p build/sim/unit-flash-reset
# Rebuild the source list from the maintained Quartus manifest. Old local .f
# files are ignored build products and must not be prerequisites of this test.
python3 - <<'PYSOURCES'
import re
from pathlib import Path
sources=re.findall(r'-name (?:SYSTEMVERILOG_FILE|VERILOG_FILE) (rtl/ngage_\S+)',Path('files.qip').read_text())
sources=[p for p in sources if p!='rtl/ngage_cpu.sv']
assert 'rtl/ngage_bram.v' in sources and 'rtl/ngage_mister.v' in sources
Path('build/sim/unit-flash-reset/common.f').write_text('\n'.join(sources)+'\n')
PYSOURCES
iverilog -g2012 -s tb -o build/sim/unit-flash-reset/test -f build/sim/unit-flash-reset/common.f tests/phone/flash_reset/tb.v
vvp build/sim/unit-flash-reset/test > build/sim/unit-flash-reset/run.log
cat build/sim/unit-flash-reset/run.log
grep -q '^PASS reset drains' build/sim/unit-flash-reset/run.log
iverilog -g2012 -s tb -o build/sim/unit-flash-reset/cold -f build/sim/unit-flash-reset/common.f tests/phone/flash_reset/cold_tb.v
vvp build/sim/unit-flash-reset/cold > build/sim/unit-flash-reset/cold.log
cat build/sim/unit-flash-reset/cold.log
grep -q '^PASS cold reset drains' build/sim/unit-flash-reset/cold.log
iverilog -g2012 -s tb -o build/sim/unit-flash-reset/writes -f build/sim/unit-flash-reset/common.f tests/phone/flash_reset/write_tb.v
vvp build/sim/unit-flash-reset/writes > build/sim/unit-flash-reset/writes.log
cat build/sim/unit-flash-reset/writes.log
grep -q '^PASS integrated C/PMM program and erase reset' build/sim/unit-flash-reset/writes.log
