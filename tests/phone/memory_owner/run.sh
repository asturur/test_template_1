#!/bin/sh
set -eu
# flash_reset also verifies outstanding read/program/erase cancellation and
# builds common.f from the maintained Quartus manifest.
sh tests/phone/flash_reset/run.sh
iverilog -g2012 -s memory_owner_tb -o build/sim/unit-flash-reset/owner -f build/sim/unit-flash-reset/common.f tests/phone/flash_reset/tb.v tests/phone/memory_owner/tb.v
vvp build/sim/unit-flash-reset/owner > build/sim/unit-flash-reset/owner.log
cat build/sim/unit-flash-reset/owner.log
grep -q '^PASS captured memory ownership' build/sim/unit-flash-reset/owner.log
