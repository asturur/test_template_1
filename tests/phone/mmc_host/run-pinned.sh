#!/bin/sh
set -eu
docker run --rm --pull=never --network none --platform linux/arm64 \
    -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 -c '
set -eu
sh tests/phone/mmc_host/run.sh
python3 tools/format_phone_rtl.py --formatter scratch/ngage2-integration/tools/verible-verilog-format --check rtl/ngage_mmc_host.v
verilator --lint-only --language 1364-2001 --top-module ngage_mmc_host -Wall -Wno-fatal rtl/ngage_mmc_host.v > build/sim/unit-mmc-host/verilator-lint.log 2>&1
'
