#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
out=build/sim/unit-icache-read-only
mkdir -p "$out"
# Compare metadata specializations under the same instruction-request class.
# The generic data adapter's ordinary-load early reply intentionally differs
# from the instruction path; it is not a valid cycle-equivalence reference.
python3 - "$out" <<'PYREF'
from pathlib import Path
import sys
out = Path(sys.argv[1])
s = Path('rtl/arm920/cache_adapter.sv').read_text()
needle = 'module arm920_cache_adapter #('
assert s.count(needle) == 1
s = s.replace(needle, 'module reference_icache_adapter #(', 1)
for port in ['req_early_read', 'req_ordinary_store', 'req_resident_access']:
    needle = '.' + port + '(!READ_ONLY && swp_tag == 2\'d0),'
    assert s.count(needle) == 1, port
    s = s.replace(needle, '.' + port + '(1\'b0),', 1)
(out/'reference_adapter.sv').write_text(s)
PYREF
docker run --rm --pull=never --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint verilator jotego/simulator:arm64 \
 --binary --timing --assert -Wno-fatal -Wno-lint --top-module test --Mdir "$out" \
 rtl/ngage_bram.v rtl/arm920/*.sv "$out/reference_adapter.sv" tests/cpu/icache_read_only/test.v > "$out/build.log" 2>&1
docker run --rm --pull=never --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint "/work/$out/Vtest" jotego/simulator:arm64 > "$out/run-wide.log" 2>&1
cat "$out/run-wide.log"
docker run --rm --pull=never --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint "/work/$out/Vtest" jotego/simulator:arm64 +halfword > "$out/run-halfword.log" 2>&1
cat "$out/run-halfword.log"
