#!/bin/sh
set -eu
out=build/sim/unit-upp-request-stage
mkdir -p "$out"
iverilog -g2001 -s tb -o "$out/test" rtl/ngage_upp.v tests/phone/upp_request_stage/tb.v
vvp "$out/test"
