#!/bin/sh
# Host launcher; creates only this experiment's files and uses the cached image.
set -eu
out=scratch/rf-timeout-20261113
python3 "$out/build_probe.py" > "$out/prepared-report.json"
docker run --rm --pull=never --network none --platform linux/arm64 -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 -c '
set -eu
out=scratch/rf-timeout-20261113
verilator --binary --timing --assert -j 2 -Wno-fatal -Wno-lint -Irtl/arm --top-module tb --Mdir "$out/obj" rtl/ngage_cpu.sv rtl/arm/*.sv rtl/ngage_bram.v rtl/arm920/*.sv "$out/tb.v" > "$out/build.log" 2>&1
for tag in 1 2 3 4 5 6 7 8; do
 for wait in 0 3; do
  "$out/obj/Vtb" +tag=$tag +wait=$wait > "$out/run-$tag-$wait.log" 2>&1
  grep "^PASS" "$out/run-$tag-$wait.log"
 done
done'
