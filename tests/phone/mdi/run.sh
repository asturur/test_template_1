#!/bin/sh
set -eu
mkdir -p build/sim/unit-mdi
iverilog -g2005 -s tb -o build/sim/unit-mdi/test rtl/ngage_mdi_stub.v tests/phone/mdi/tb.v
vvp build/sim/unit-mdi/test
