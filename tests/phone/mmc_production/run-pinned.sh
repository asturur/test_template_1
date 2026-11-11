#!/bin/sh
set -eu
docker run --rm --pull=never --network none --platform linux/arm64 \
    -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 -c '
set -eu
sh tests/phone/mmc_production/run.sh
python3 tools/format_phone_rtl.py --formatter scratch/ngage2-integration/tools/verible-verilog-format --check rtl/ngage_upp.v rtl/ngage_upp_peripherals.v rtl/ngage_dma_channels.v rtl/ngage_dma_route.v rtl/ngage_board.v tests/phone/mmc_production/bus_tb.v tests/phone/mmc_production/dma_tb.v tests/phone/mmc_production/cpu_peer.v
'
