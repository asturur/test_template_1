#!/bin/sh
# Exercise the production UPP bridge between the actual CPU and memory bench.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
export CPU_BUS_BRIDGE=1
for program in cpu_timing swp_basic swp_cached swp_irq swp_fiq swp_bufferable cache_irq_refill cache_irq_writeback alignment_cases; do
    CPU_PROGRAM="$program" sh tests/cpu/core/sim.sh
done
CPU_PROGRAM=swp_basic CPU_SDRAM_PATH=1 sh tests/cpu/core/sim.sh
CPU_PROGRAM=cache_external_abort CPU_FAULT_ADDR=80030100 sh tests/cpu/core/sim.sh
CPU_PROGRAM=swp_read_abort CPU_FAULT_ADDR=80001000 CPU_SWP_BOTH_ABORT=1 sh tests/cpu/core/sim.sh
CPU_PROGRAM=swp_write_abort CPU_FAULT_ADDR=80001000 CPU_FAULT_WRITE_ONLY=1 sh tests/cpu/core/sim.sh
CPU_PROGRAM=swp_abort_irq CPU_FAULT_ADDR=80001000 CPU_SWP_ABORT=1 sh tests/cpu/core/sim.sh
