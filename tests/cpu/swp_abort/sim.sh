#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
CPU_PROGRAM=swp_read_abort CPU_FAULT_ADDR=80001000 CPU_SWP_ABORT=1 tests/cpu/core/sim.sh
