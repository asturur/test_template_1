#!/bin/sh
set -eu
cd "$(dirname "$0")/../../.."
out=build/sim/arm9v2-store-queue
mkdir -p "$out"
module=ngage2_zap_store_queue
git show 341a45421019398c2a44bf6f9ce79d312e0cdbac:rtl/arm9v2/arm925t_phone.v |
    awk -v name="$module" '
        $1 == "module" && $2 == name { active = 1; sub(name, "queue_reference") }
        active { print }
        active && /^endmodule/ { exit }
    ' > "$out/reference.v"
grep -q '^module queue_reference' "$out/reference.v"
awk -v name="$module" '
    $1 == "module" && $2 == name { active = 1 }
    active { print }
    active && /^endmodule/ { exit }
' rtl/arm9v2/arm925t_phone.v > "$out/candidate.v"
grep -q '^module ngage2_zap_store_queue' "$out/candidate.v"

python3 - "$out" <<'PY'
from pathlib import Path
import sys

out = Path(sys.argv[1])
source = (out / 'candidate.v').read_text()
for bank in ('even', 'odd'):
    expression = f'{bank}_payload <= entries_{bank}[{bank}_row];'
    assert source.count(expression) == 1
    source = source.replace(expression, f'{bank}_payload <= push_{bank} && write_row == {bank}_row'
                            f" ? 68'bx : entries_{bank}[{bank}_row];")
(out / 'collision.v').write_text(source)
PY

docker run --rm --pull=never --network none --platform linux/arm64 \
    -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 -ec '
        out=build/sim/arm9v2-store-queue
        for model in candidate collision; do
            iverilog -g2005 -s queue_tb -o "$out/$model" \
                "$out/reference.v" "$out/$model.v" tests/cpu/arm9v2_store_queue/tb.v
            vvp "$out/$model" > "$out/$model.log"
            grep "^PASS AW=" "$out/$model.log"
        done
    '
