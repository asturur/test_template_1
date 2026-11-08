#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
# Handler accepts the whole before-SWP or whole after-SWP state, never a torn pair.
CPU_PROGRAM=operand_swp_irq CPU_RUN_ARGS='+swp_edge=0' CPU_DELAYS='0 3' sh tests/cpu/core/sim.sh
for kind in irq fiq; do
 for edge in 0 1 2 3 4 5 6 7 8 9 10; do
  if [ "$kind" = irq ] && [ "$edge" = 0 ]; then continue; fi
  extra=""
  if [ "$kind" = fiq ]; then extra="+sweep_fiq"; fi
  for delay in 0 3; do
   log="build/sim/unit-core/sweep-$kind-$edge-$delay.log"
   if ! docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint /work/build/sim/unit-core/Vtest jotego/simulator:arm64 +ngage-compact-trace +latency="$delay" +swp_edge="$edge" $extra > "$log" 2>&1; then
    tail -30 "$log"
    exit 1
   fi
   grep '^PASS:' "$log"
  done
 done
done
