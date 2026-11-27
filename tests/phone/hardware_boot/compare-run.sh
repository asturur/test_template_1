#!/bin/sh
# Bounded staged C++/HDL shadow run followed by the actual RTL board run.
# Local firmware and C image are read-only. Writes are in dedicated directories.
set -eu
sh scratch/milestone5/build.sh
out=build/sim/runs/milestone7-reference-present
mkdir -p "$out"
: > "$out/result.json"
set +e
docker run --rm --network none --platform linux/arm64 -v "$PWD:/work" -w /work --entrypoint /work/build/sim/obj-milestone5/Vngage_cpu_sim jotego/simulator:arm64 \
 /work/build/firmware/nem4-factory/core.bin 5000000 0 \
 "/work/$out/instructions.tsv" "/work/$out/bus.tsv" "/work/$out/cp15.tsv" "/work/$out/result.json" \
 amd16 ideal-clocks lcd-probe boot-io-probe +ngage-compact-trace \
 rom-extension=/work/build/firmware/nem4-factory/extension.bin timer-irq-delay=18200000 \
 keypad-gpio icu-banks timer-units cdrive-flash cdrive-image=/work/scratch/overnight/cdrive-11b.img \
 timer-unit60-irq3 nos-periph-4000 uem-irq-source1 epbus-clkblk descramble-window > "$out/run.log" 2>&1
status=$?
set -e
# A bounded timeout reports a nonzero exit; compare.py validates the result.
if [ "$status" -ne 0 ] && [ ! -s "$out/result.json" ]; then exit "$status"; fi
sh tests/phone/hardware_boot/run-real-sdram.sh
python3 tests/phone/hardware_boot/compare.py
