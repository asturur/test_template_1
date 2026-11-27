#!/bin/sh
# Compare the three selected tag hits and public pins against the FF baseline.
set -eu
cd "$(dirname "$0")/../../.."
out=${MMC_TAG_OUT:-build/sim/mmc-stream-tags}
mkdir -p "$out"

git show 29479fe:rtl/ngage_mmc_card.v |
    sed 's/^module ngage_mmc_card #(/module mmc_card #(/' > "$out/reference.v"
python3 - "$out" <<'PY'
import sys
from pathlib import Path

# The hardware ignores read data on a mixed-port read/write collision. A
# coincident hit must use the pending logical tag, even against an X payload.
source = Path("rtl/ngage_bram.v").read_text()
old = "b_q[lane*BYTE_WIDTH+:BYTE_WIDTH] <= we_b[lane] ?"
new = (
    "b_q[lane*BYTE_WIDTH+:BYTE_WIDTH] <= "
    "(we_a[lane] && addr_a == addr_b) ? {BYTE_WIDTH{1'bx}} : we_b[lane] ?"
)
assert source.count(old) == 1
Path(sys.argv[1], "poison_bram.v").write_text(source.replace(old, new))
PY

for test in eof version; do
    sed 's/ngage_mmc_card dut(/mmc_card_equivalence dut(/' \
        "tests/phone/mmc_card/${test}_tb.v" > "$out/${test}_tb.v"
    iverilog -g2012 -DNGAGE_TEST_MMC_STREAM_TAGS -s "${test}_tb" -o "$out/$test" \
        "$out/reference.v" "$out/poison_bram.v" rtl/ngage_mmc_dpram.v \
        rtl/ngage_mmc_card.v tests/phone/mmc_card/equivalence.v "$out/${test}_tb.v"
    vvp "$out/$test" > "$out/$test.log"
    cat "$out/$test.log"
    grep -q '^PASS MMC ' "$out/$test.log"
done
iverilog -g2012 -DNGAGE_TEST_MMC_STREAM_TAGS -s stream_lookup_tb -o "$out/ports" \
    "$out/reference.v" "$out/poison_bram.v" rtl/ngage_mmc_dpram.v \
    rtl/ngage_mmc_card.v tests/phone/mmc_card/equivalence.v tests/phone/mmc_card/stream_lookup_tb.sv
vvp "$out/ports" > "$out/ports.log"
cat "$out/ports.log"
grep -q '^PASS MMC all 12 stream slots' "$out/ports.log"
