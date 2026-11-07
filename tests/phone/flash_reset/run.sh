#!/bin/sh
set -eu
mkdir -p build/sim/unit-flash-reset
iverilog -g2012 -s tb -o build/sim/unit-flash-reset/test -f tests/phone/flash_reset/files.f
vvp build/sim/unit-flash-reset/test > build/sim/unit-flash-reset/run.log
cat build/sim/unit-flash-reset/run.log
grep -q '^PASS reset drains' build/sim/unit-flash-reset/run.log
iverilog -g2012 -s tb -o build/sim/unit-flash-reset/cold -f tests/phone/flash_reset/cold.f
vvp build/sim/unit-flash-reset/cold > build/sim/unit-flash-reset/cold.log
cat build/sim/unit-flash-reset/cold.log
grep -q '^PASS cold reset drains' build/sim/unit-flash-reset/cold.log
iverilog -g2012 -s tb -o build/sim/unit-flash-reset/writes -f tests/phone/flash_reset/write.f
vvp build/sim/unit-flash-reset/writes > build/sim/unit-flash-reset/writes.log
cat build/sim/unit-flash-reset/writes.log
grep -q '^PASS integrated C, PMM and erase reset writes' build/sim/unit-flash-reset/writes.log
