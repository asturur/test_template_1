#!/bin/sh
set -eu
mkdir -p build/sim/unit-lcd-dma
iverilog -g2005 -s tb -o build/sim/unit-lcd-dma/test rtl/ngage_lcd_dma.v tests/phone/lcd_dma/tb.v
vvp build/sim/unit-lcd-dma/test > build/sim/unit-lcd-dma/run.log
cat build/sim/unit-lcd-dma/run.log
grep -q '^PASS LCD DMA' build/sim/unit-lcd-dma/run.log
iverilog -g2005 -s tb -o build/sim/unit-lcd-dma/arbiter rtl/ngage_lcd_dma.v rtl/ngage_bram.v rtl/ngage_lcd_display.v rtl/ngage_sdram_arbiter.v rtl/ngage_dma_route.v tests/phone/lcd_dma/arbiter_tb.v
vvp build/sim/unit-lcd-dma/arbiter > build/sim/unit-lcd-dma/arbiter.log
cat build/sim/unit-lcd-dma/arbiter.log
grep -q '^PASS LCD full DMA' build/sim/unit-lcd-dma/arbiter.log
# Replay the preserved firmware frame when its local trace is available.
if [ -f build/sim/runs/boot-v15-simif-noatr-faulttrace/lcd-dma.tsv ]; then
 python3 - <<'PY'
from pathlib import Path
p=Path('build/sim/runs/boot-v15-simif-noatr-faulttrace/lcd-dma.tsv')
words=[int(f[4],16) for line in p.read_text().splitlines()[2:] if len(f:=line.split('\t'))>4 and f[2]=='0x0c121208']
assert len(words)==18304 and sum(words)&0xffffffff==0x6de5f326
Path('build/sim/unit-lcd-dma/firmware-frame.hex').write_text(''.join(f'{v:08x}\n' for v in words))
PY
 iverilog -g2005 -DRETAINED_FRAME -s tb -o build/sim/unit-lcd-dma/firmware rtl/ngage_lcd_dma.v rtl/ngage_bram.v rtl/ngage_lcd_display.v rtl/ngage_sdram_arbiter.v rtl/ngage_dma_route.v tests/phone/lcd_dma/arbiter_tb.v
 vvp build/sim/unit-lcd-dma/firmware > build/sim/unit-lcd-dma/firmware.log
 cat build/sim/unit-lcd-dma/firmware.log
 grep -q '^PASS LCD full DMA' build/sim/unit-lcd-dma/firmware.log
else
 echo 'SKIP retained firmware LCD trace unavailable'
fi
