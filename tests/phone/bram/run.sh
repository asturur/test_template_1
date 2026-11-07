#!/bin/sh
# Run inside jotego/simulator:arm64. No vendor library is copied into the repo.
set -eu
out=build/sim/unit-bram
mkdir -p "$out"
# Check branch selection using Quartus's native macro, without SYNTHESIS.
iverilog -g2012 -E -DALTERA_RESERVED_QIS -o "$out/quartus-path.v" rtl/ngage_bram.v
python3 - "$out/quartus-path.v" <<'PY_CHECK'
import sys
from pathlib import Path
source = Path(sys.argv[1]).read_text()
assert 'altsyncram #' in source, 'Quartus must instantiate the primitive'
assert 'reg [DW-1:0] memory' not in source, 'simulation array leaked into Quartus'
print('PASS Quartus native-macro primitive selection')
PY_CHECK
iverilog -g2012 -s tb -o "$out/behavioral" rtl/ngage_bram.v tests/phone/bram/tb.v
vvp "$out/behavioral"
if [ -n "${ALTERA_MF:-}" ]; then
  iverilog -g2012 -DSYNTHESIS -s tb -o "$out/primitive" rtl/ngage_bram.v tests/phone/bram/tb.v "$ALTERA_MF" > "$out/vendor-build.log" 2>&1
  vvp "$out/primitive"
fi
