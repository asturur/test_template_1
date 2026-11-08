#!/bin/sh
# Optional latency-insensitive whole-core differential and cycle measurements.
# Each simulator has one CPU. The baseline is never in the synthesis source graph.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
evidence=scratch/timing-closure/slice1-operand
sh tests/cpu/operands/reference.sh
for version in reference candidate; do
 directory="$evidence/$version"
 mkdir -p "$directory"
 reference=""
 if [ "$version" = reference ]; then reference="$evidence/reference"; fi
 CPU_REFERENCE_DIR="$reference" CPU_BUS_BRIDGE=1 CPU_PROGRAM=operand_timing CPU_RUN_ARGS=+effect_trace CPU_DELAYS='0 3 7 15 31' CPU_MAX_CYCLES=2000000 sh tests/cpu/core/sim.sh > "$directory/operand-timing.log" 2>&1
 for wait in 0 3 7 15 31; do
  rg '^EFFECT' "build/sim/unit-core/run-$wait.log" > "$directory/effects-$wait.txt"
 done
 for program in cpu_timing ldm_base_coldcache cache_drain swp_basic; do
  CPU_REFERENCE_DIR="$reference" CPU_BUS_BRIDGE=1 CPU_PROGRAM="$program" sh tests/cpu/core/sim.sh > "$directory/$program.log" 2>&1
 done
done
for wait in 0 3 7 15 31; do
 diff "$evidence/reference/effects-$wait.txt" "$evidence/candidate/effects-$wait.txt"
done
printf '%s\n' 'PASS exact ordered RF writes and architectural retirement/CPSR effects at waits 0/3/7/15/31'
