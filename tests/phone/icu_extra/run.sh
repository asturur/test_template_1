#!/bin/sh
set -eu
mkdir -p build/sim/unit-icu-extra
iverilog -g2005 -s tb -o build/sim/unit-icu-extra/test rtl/ngage_icu_extra.v tests/phone/icu_extra/tb.v
vvp build/sim/unit-icu-extra/test
