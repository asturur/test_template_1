#!/bin/sh
# Verilator-only structural check: use explicit HPS/PLL stubs, not vendor timing.
set -eu
mkdir -p build/sim/unit
python3 - <<'PY'
import re
from pathlib import Path
s='\n'.join(line for line in Path('files.qip').read_text().splitlines() if not line.lstrip().startswith('#'))
p=[m.group(1) for m in re.finditer(r'-name (?:SYSTEMVERILOG_FILE|VERILOG_FILE) (\S+)',s)]
p += ['tests/phone/sdram/ddio_model.v','tests/phone/mister_transport/hps_stub.sv','tests/phone/mister_transport/pll_stub.sv']
Path('build/sim/unit/mister-lint.f').write_text('\n'.join(p)+'\n')
PY
verilator --lint-only --top-module emu -I. -Irtl/arm --bbox-unsup --bbox-sys -Wno-fatal -f build/sim/unit/mister-lint.f > build/sim/unit/mister-lint-stubs.log 2>&1
printf '%s\n' 'PASS top-level structural elaboration (HPS and PLL stubbed)'
