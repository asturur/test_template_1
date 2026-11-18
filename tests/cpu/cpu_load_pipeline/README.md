# Step 5J: P1 ordinary-load start

One isolated CPU-interface prototype on exact production 5F
`8e70b1ebc16486443d09f008384b4c0bc41c071c`. Production RTL stays untouched.
`rtl/arm/zap_core.sv` is the only overlay. Cache geometry, address arithmetic,
RAM ports, translation, data formatting and the issue scoreboard are unchanged.

The existing P1 register can offer an original unconditional aligned ARM word
LDR without writeback while older P2 has no memory operation, exception or PC
effect and Memory has no older exception/redirect. P1 advances to P2 on that
edge, independently of ACK. An immediate response enters the existing completion
register beside that P2 owner; a waited demand remains identical in P2 until
completion. All address, privilege, width and destination metadata select the
same P1 packet. No speculative demand or second completion slot is created.

Run serially, using only the installed offline simulator and one compiler job:

```sh
python3 tests/cpu/cpu_load_pipeline/bench.py --control --name NEW_CONTROL
python3 tests/cpu/cpu_load_pipeline/bench.py --name NEW_CANDIDATE
python3 tests/cpu/cpu_load_pipeline/safety.py \
  --build build/sim/cpu-load-pipeline/NEW_CONTROL
python3 tests/cpu/cpu_load_pipeline/safety.py \
  --build build/sim/cpu-load-pipeline/NEW_CANDIDATE
python3 tests/cpu/cpu_load_pipeline/diagnostics.py NEW_DIAGNOSTICS \
  --build build/sim/cpu-load-pipeline/NEW_CANDIDATE
```

`--only span|transpose|stream|dependency` narrows a run. `--reuse-build PATH`
requires equal frozen sources, variant, fixture and image hashes plus a verified
executable. Run names must be new. `--legacy-transpose-layout` reproduces the
earlier canonical wrapper without added guard copies/checks. Compare identical
layouts; extra checks change wrapper addresses and warm state.

The runner reuses the original private span extraction, mathematical reference,
Unicorn oracle and passive RAM/retirement checker under `super_monkey_ball/`.
It also executes original transpose from the existing ignored `3DTEST.DLL`
fixture. Both original span patterns produce 512 pixels. Transpose does 32
original functions and checks all 2,048 output bytes plus 32 nonuniform guard
bytes on each side. Every scored window verifies 512 halfword RAM mutations
for a span or 384 word mutations for transpose, including byte counts and
actual acknowledged stores. Guards, outputs and the original instruction counts
must match. Wrong-output controls execute at every pattern/profile.

The straight-line stream has 128 independent aligned loads, each followed by
an independent ALU increment, over eight words in one resident cache line.
Its prologue/epilogue preserve r4–r9. The exact measured architectural region
is 256 instructions at payload offsets 8 through 0x404 inclusive. The fixed
steady region excludes its first and last 16 instructions. Trace analysis
requires all 256 ordered starts and retirements and verifies all 128 owned
completion values independently against the initialized source words. STM/LDM
micro-ops, wrapper work, private probes and killed instructions do not count as
these architectural starts. A separate 32-load dependent checksum stream
checks load-use distance and output.

Each case runs at 0:0 and 2:9 with five scored windows and two exact repeats.
Span/transpose/independent stream have two warm-ups; the small dependent stream
has three because its third window still has an instruction refill. No scored
external traffic is accepted. Classic wrapper timing uses the existing retired
NOP markers; span timing keeps its exact first-dequeue/final-original-branch
boundaries, including last-store completion. Throughput uses actual issue and
retirement journals inside the synthetic region, not wrapper cycle totals.

`observe.vh` checks stable demand PC/address across backpressure and records
P0/ALU, P1, P2, translation/permissions, BRAM reads, ACK and completion edges.
The existing D-cache assertions also check full pending translation context,
destination, width, byte enables and payload continuity. The safety guest
checks a cold waited load, a load/add, IRQ entry/return, exact abort FAR/FSR,
unchanged fault destination, and exclusion of younger fault-path and flushed
noncacheable device loads. Those device reads are forbidden by the harness;
any external read fails immediately. The focused diagnostic runner reuses the
existing real CPU ARM/Thumb, FCSE, prefetch-fault and return checks.

Qualified runs are `step5j-control-04` and `step5j-candidate-02`. Original-layout
comparison receipts are `step5j-control-03` / `step5j-candidate-01`; diagnostics
are `step5j-diagnostics-01` with byte-identical candidate CPU sources.
`analyze.py` audits these receipts and generates the durable report evidence.
It also runs after generated compiler/source/binary trees have been removed,
using retained compiler input manifests and compressed logs.

[Measured decision and schedules](../../../docs/cpu-load-pipeline.md).
