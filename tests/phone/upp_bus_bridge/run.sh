#!/bin/sh
set -eu
mkdir -p build/sim/unit-upp-bus-bridge
for mode in 0 1; do
    iverilog -g2005 -s tb -Ptb.REGISTERED_MASTER="$mode" -o build/sim/unit-upp-bus-bridge/test rtl/ngage_mmc_host.v rtl/ngage_mmc_card.v rtl/ngage_mmc_dpram.v rtl/ngage_upp.v tests/phone/upp_bus_bridge/tb.v
    vvp build/sim/unit-upp-bus-bridge/test
done
