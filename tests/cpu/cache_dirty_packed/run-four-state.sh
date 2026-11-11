#!/bin/sh
# Actual Intel primitive and X-poisoned mixed-port collision equivalence.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
model=${1:?Pass the existing Intel altera_mf.v model path}
out=build/sim/unit-cache-dirty-packed-four-state
mkdir -p "$out/src"
python3 - <<'PREPARE'
from pathlib import Path
import re
out = Path('build/sim/unit-cache-dirty-packed-four-state/src')
# Icarus requires explicit enum state branches in these ternary assignments.
for source in [*Path('rtl/arm920').glob('*.sv'), *Path('tests/cpu/cache_dirty_packed').glob('reference_*.sv')]:
    text = re.sub(r'state\s*<=\s*([^;?]+)\?\s*(\w+)\s*:\s*(\w+)\s*;',
                  r'if (\1) state <= \2; else state <= \3;', source.read_text())
    if source.name.endswith('cache_tags.sv'):
        text = text.replace('    wire [63:0] selected_ways;\n', '')
        text = text.replace('    reg [63:0] commit_selected;', '    reg [63:0] commit_selected;\n    wire [63:0] selected_ways;')
    (out / source.name).write_text(text)
PREPARE
docker run --rm --pull=never --network none --platform linux/arm64 \
 --mount "type=bind,src=$root,dst=/src,readonly" \
 --mount "type=bind,src=$root/$out,dst=/out" \
 --mount "type=bind,src=$model,dst=/vendor/altera_mf.v,readonly" \
 --workdir /src --entrypoint sh jotego/simulator:arm64 -c '
set -eu
for mode in poison vendor; do
 if [ "$mode" = poison ]; then ram="tests/cpu/cache_dirty_packed/poison_bram.v"; else ram="-DALTERA_RESERVED_QIS rtl/ngage_bram.v /vendor/altera_mf.v"; fi
 iverilog -g2012 -s test -o /out/$mode $ram /out/src/*.sv tests/cpu/cache_dirty_packed/access_equivalence.sv > /out/build-$mode.log 2>&1
 vvp /out/$mode > /out/run-$mode.log 2>&1
 grep -E "EQUIVALENCE|PASS" /out/run-$mode.log
done'
