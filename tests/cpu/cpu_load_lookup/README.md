# Step 5K: earlier registered ALU lookup

This isolated experiment adds an earlier private resident-line probe to the
[Step 5J P1-load prototype](../cpu_load_pipeline/README.md). Production stays
at exact 5F `8e70b1ebc16486443d09f008384b4c0bc41c071c`.

Only `rtl/arm/zap_core.sv` is overlaid. For an eligible original ARM word load,
its existing registered ALU effective address may drive the private cache hint
one clock before P1. A current P1 memory operation keeps priority. Reset,
writeback/ALU clear and data stall suppress the new hint. No new demand,
translation, response slot, arithmetic unit, cache entry or RAM port is added.
The adapter retains its registered tag/way ownership, collision/revoke checks
and current-demand permission checks. The actual instruction still follows 5J's
P1→P2 demand/completion handoff.

Use unique names and run serially with the installed offline image:

```sh
python3 tests/cpu/cpu_load_lookup/bench.py --variant 5f --name NEW_5F
python3 tests/cpu/cpu_load_lookup/bench.py --variant p1 --name NEW_P1
python3 tests/cpu/cpu_load_lookup/bench.py --variant lookup --name NEW_LOOKUP
python3 tests/cpu/cpu_load_lookup/safety.py \
  --build build/sim/cpu-load-lookup/NEW_LOOKUP
python3 tests/cpu/cpu_load_lookup/pressure.py NEW_PRESSURE
python3 tests/cpu/cpu_load_lookup/diagnostics.py NEW_DIAGNOSTICS \
  --build build/sim/cpu-load-lookup/NEW_LOOKUP
```

`bench.py` reuses the maintained 5J driver and checked 5I original-span fixture;
it does not edit either. `--only span|transpose|stream|dependency|multiline`
narrows a run. `--reuse-build PATH` verifies CPU, harness, image and executable
hashes before reuse. `--legacy-transpose-layout` is inherited for reproducing
the earlier wrapper layout; the default includes both nonuniform guard regions.
One compiler job, no image pulls/network, no hardware or Quartus is used.

The first five cases are unchanged from 5J. The additional `multiline` stream
alternates 128 independent loads with 128 ALU increments, selecting offsets
0,32,...,224 from a 256-byte initialized source. It preserves r4–r9 and uses
the same 256-instruction measurement region at offsets 8–0x404 as the single-line
stream. Every owned load result is independently checked from its PC against
the selected source word. This tests eight resident lines rather than one.
The fixed steady region excludes the first/last 16 instructions. Its trace
is window 2, the last declared warm-up; the analyzer requires its cycle and
traffic metrics to equal the first scored window. The span and single-line
stream traces are from their first scored window. No dependent-stream warm-up
with instruction refills is scored.

All cases run 0:0/2:9, five scored windows and two equal repetitions. Scored
external reads/writes/line requests must be zero. Original-byte independent
oracles, mathematical outputs, destination guards, source/stack integrity,
retirement counts/order and actual cache RAM mutation/byte counts are retained.
Every case/profile executes its wrong-output control. The original app and
derived machine code remain ignored and private.

`observe.vh` adds `LOOKUP_EDGE` and full-window hint counts to the 5J observer.
`analyze.py` verifies all 512 dynamic load/consumer pairs for each of three
targeted stack loads, in both original span patterns, against both controls.
It also checks every stream start/retirement and all 128 completion values,
the saved compiler input closure and source/fixture hashes.

The CPU safety guest adds same-line stores followed by loads, both immediately
and with independent work between them. It retains cold stalls, IRQ,
exact fault FAR/FSR, unchanged fault destination and exclusion of younger or
flushed device loads. The unchanged production cache is separately exercised
with the existing collision-poison pressure fixture, including active credits,
stale probes, competing addresses, permission/translation, alias stores and
reset. The focused actual-CPU diagnostics also run on the candidate.

Qualified runs are `step5k-5f-01`, `step5k-p1-01` and `step5k-lookup-02`.
`step5k-lookup-01` is the same verified executable's initial five-case run.
Safety receipts are in each qualified run; guard and diagnostic receipts are
`step5k-pressure-01` and `step5k-diagnostics-01`. The default analyzer audits
these names and can be rerun after build cleanup using compressed logs and
retained compiler-input receipts.

[Results and decision](../../../docs/cpu-load-lookup.md).
