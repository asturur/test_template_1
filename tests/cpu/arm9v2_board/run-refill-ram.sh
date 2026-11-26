#!/bin/sh
set -eu

name="${1:?provide a fresh run name}"
case "$name" in *[!A-Za-z0-9_.-]*) exit 2 ;; esac
out="build/sim/$name"
mkdir "$out"

simulate() {
    entrypoint=$1
    shift
    docker run --rm --pull=never --network none --platform linux/arm64 -v "$PWD:/work" \
        -w /work --entrypoint "$entrypoint" jotego/simulator:arm64 "$@"
}

# Quartus permits any mixed-port collision value. Repeat with bad collision
# data forced in the RAM model so a missing bypass cannot pass by accident.
python3 - "$out" <<'PY'
from pathlib import Path
import re
import sys

source = Path('rtl/ngage_cpu.sv').read_text()
source, count = re.subn(
    r'ram_word +<= words\[read_row\];',
    'ram_word <= write_word && write_row == read_row ? ~write_data : words[read_row];',
    source,
)
assert count == 1, 'Update the mixed-port RAM collision injection'
(Path(sys.argv[1]) / 'poison.sv').write_text(source)
PY

for mode in ordinary poison; do
    wrapper=rtl/ngage_cpu.sv
    if [ "$mode" = poison ]; then wrapper="$out/poison.sv"; fi
    simulate verilator --binary --timing --assert -j 2 -Wno-fatal -Wno-lint \
        --top-module refill_ram_tb --Mdir "$out/obj-$mode" "$wrapper" \
        tests/cpu/arm9v2_board/refill_ram_tb.sv > "$out/build-$mode.log" 2>&1
    simulate "/work/$out/obj-$mode/Vrefill_ram_tb" > "$out/run-$mode.log" 2>&1
    rg '^PASS refill RAM' "$out/run-$mode.log"
done
