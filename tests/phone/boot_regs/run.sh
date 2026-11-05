#!/bin/sh
set -eu
mkdir -p build/sim/unit-boot-regs
iverilog -g2012 -s tb -o build/sim/unit-boot-regs/test rtl/ngage_boot_regs.v tests/phone/boot_regs/tb.sv
vvp build/sim/unit-boot-regs/test
