#!/bin/sh
set -eu
cd "$(dirname "$0")/../../.."
out=build/sim/upp-ddr-top/source
mkdir -p "$out"
for path in rtl sys tests Template.sv files.qip; do
    ln -sfn "../../../../$path" "$out/$path"
done
printf '`define BUILD_DATE "sim-upp-ddr"\n' > "$out/build_id.v"

docker run --rm --pull=never --network none --platform linux/arm64 \
    -v "$PWD:/work" -w "/work/$out" --entrypoint sh jotego/simulator:arm64 -ec '
        sh tests/phone/mister_transport/lint-top.sh
        verilator --binary --timing -j 2 --assert --top-module cold_top -I. -Irtl/arm \
            --bbox-unsup --bbox-sys -Wno-fatal -f build/sim/unit/mister-lint.f \
            --Mdir ../obj tests/phone/upp_ddr_top/tb.sv > ../build.log 2>&1
        ../obj/Vcold_top > ../run.log 2>&1
        grep "^PASS" ../run.log
    '
