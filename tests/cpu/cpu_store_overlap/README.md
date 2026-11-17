# Real ARM store-overlap experiment

See [the Step 4A report](../../../docs/cpu-store-overlap.md) for scope, measured
cycles, first pair and correctness limits. This is an isolated selectable
overlay, not production integration.

`run.py UNIQUE_NAME [--control]` freezes exact 9c948da8 + qualified Stop 3C,
then adds `rtl/` for the candidate. Both use production BRAM. It runs the same
64-STR program through the real CPU, includes older abort/IRQ and following
load/byte-store checks, verifies actual physical writes/ordered completion/
retirement and independent dirty backing bytes, and requires exact repeats.
`--reuse RUN_DIRECTORY` requires matching source/harness/observer and executable
hashes; choose a retained final build rather than a superseded trial.

`negative.py RUN_DIRECTORY` reuses that verified executable and deliberately
corrupts an expected physical byte; success means the intended checker fails.
`bench.py [--control]` selects the same RTL for the maintained original payload
runner and adds acceptance/credit/overlap counters. Use `--case transpose4` and
matched `--baseline` inputs. All output/oracle/repeat/negative gates remain.
`compat.py OUTPUT [--fixture cache_probe]` reuses Stop 3C directed cache tests,
explicitly disables new credits and never modifies their maintained fixtures.
`analyze.py` validates the recorded final run names and saves compact evidence;
it never builds, dispatches CI or changes production RTL.

All Docker calls use the existing `jotego/simulator:arm64`, `--pull=never` and
`--network none`. Generated outputs live in `build/sim/`. The running phone,
other simulations and billion-cycle checkpoints are outside these commands.
