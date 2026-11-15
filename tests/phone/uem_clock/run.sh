#!/bin/sh
set -eu
out="${OUT_DIR:-build/sim/unit-uem-clock}"
mkdir -p "$out"
python3 - "$out/vectors.txt" <<'PY'
import random,sys
from pathlib import Path
r=random.Random(0x190)
values=[0,1,59,60,3599,3600,86399,86400,951782399,951782400,1794744000,0xffffffff]
values += [r.randrange(1<<32) for _ in range(150)]
base=values[0]//86400
Path(sys.argv[1]).write_text(''.join(f'{v:08x} {v//3600%24} {v//60%60} {v%60} {(v//86400-base)%256}\n' for v in values))
PY
iverilog -g2005 -s tb -o "$out/test" rtl/ngage_bram.v rtl/ngage_cbus_uem.v tests/phone/uem_clock/tb.v
vvp "$out/test" +vectors="$out/vectors.txt"
# Both production parameter values elaborate without touching the PLL.
for hz in 78000000 104000000; do
 verilator --lint-only -Wno-fatal --top-module ngage_uem_clock -GCLK_HZ="$hz" rtl/ngage_cbus_uem.v > "$out/lint-$hz.log" 2>&1
done
