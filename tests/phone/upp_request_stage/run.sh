#!/bin/sh
set -eu
out=${UPP_STAGE_OUT:-build/sim/unit-upp-request-stage}
mkdir -p "$out"
for mode in 0 1; do
    iverilog -g2001 -s tb -Ptb.EXPLICIT_LIVE="$mode" -o "$out/test-$mode" \
        rtl/ngage_upp.v tests/phone/upp_request_stage/tb.v
    vvp "$out/test-$mode"
done
