#!/bin/sh
# Run from the repository root. Never pull a simulator or touch boot checkpoints.
set -eu
docker run --rm --pull=never --network none --platform linux/arm64 \
    -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 -c '
set -eu
sh tests/phone/sdram/run-ownership.sh
sh tests/phone/sdram/run.sh
sh tests/phone/sdram/run-ddio.sh
sh tests/phone/sdram/run-short-reads.sh
sh tests/phone/sdram/run-scrub.sh
sh tests/phone/dma_ram_mux/run.sh
sh tests/phone/lcd_stream/run-comparison.sh
'
