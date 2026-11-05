#!/bin/sh
# Known legacy-cache geometry gap: this records an expected failure, not a pass.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
mkdir -p build/sim/unit-cache-associativity
if CPU_ASSOC_EXPERIMENT=0 CPU_PROGRAM=cache_associativity tests/cpu/core/sim.sh > build/sim/unit-cache-associativity/run.log 2>&1; then
 echo 'XPASS: cache-conflict test now passes; remove the known-failure expectation and audit the implementation.'
 exit 1
fi
if rg -q 'EVICTION: dirty first line written to memory' build/sim/unit-cache-associativity/run.log && \
   rg -q 'CPU diagnostic failed: 00000064' build/sim/unit-cache-associativity/run.log; then
 echo 'XFAIL: direct-mapped cache evicts a line that ARM920T round-robin 64-way cache retains'
else
 cat build/sim/unit-cache-associativity/run.log
 exit 1
fi
