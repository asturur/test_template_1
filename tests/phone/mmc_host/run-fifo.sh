#!/bin/sh
set -eu
cd "$(dirname "$0")/../../.."
out=${MMC_FIFO_OUT:-build/sim/mmc-host-fifo}
mkdir -p "$out"
git show 739d3bd:rtl/ngage_mmc_host.v > "$out/register-host.v"
sed 's/^module ngage_mmc_host #(/module mmc_host_fifo_reference #(/' \
    "$out/register-host.v" > "$out/reference.v"
python3 - "$out" <<'PY'
from pathlib import Path
import sys

source = Path("rtl/ngage_bram.v").read_text()
old = "b_q[lane*BYTE_WIDTH+:BYTE_WIDTH] <= we_b[lane] ?"
new = ("b_q[lane*BYTE_WIDTH+:BYTE_WIDTH] <= "
       "(we_a[lane] && addr_a == addr_b) ? {BYTE_WIDTH{1'bx}} : we_b[lane] ?")
assert source.count(old) == 1
Path(sys.argv[1], "poison_bram.v").write_text(source.replace(old, new))

# Add the comparator to a local copy of the ordinary data bench.
source = Path("tests/phone/mmc_host/data_tb.v").read_text()
anchor = "    always @(posedge clk)begin cycles<=cycles+1;"
assert source.count(anchor) == 1
monitor = '''    `include "fifo_reference.vh"
    // Let the register model sample a mask transition before leaving reset.
    initial begin #1; be = 0; #1; be = 15; end
'''
Path(sys.argv[1], "data_fifo_tb.v").write_text(source.replace(anchor, monitor + anchor))

PY
for config in '2 16' '3 16' '4 16' '12 8'; do
    set -- $config
    exe="$out/data-$1-$2"
    iverilog -g2012 -Itests/phone/mmc_host -s tb \
        -Ptb.DIV="$1" -Ptb.FIFO_DEPTH="$2" -o "$exe" \
        rtl/ngage_mmc_host.v "$out/reference.v" "$out/poison_bram.v" "$out/data_fifo_tb.v"
    vvp "$exe" > "$exe.log"
    grep '^PASS MMC host data ' "$exe.log"
done
iverilog -g2012 -Itests/phone/mmc_host -s fifo_banks_tb -o "$out/banks" \
    rtl/ngage_mmc_host.v "$out/reference.v" "$out/poison_bram.v" tests/phone/mmc_host/fifo_banks_tb.sv
vvp "$out/banks" > "$out/banks.log"
grep '^PASS MMC FIFO ' "$out/banks.log"
