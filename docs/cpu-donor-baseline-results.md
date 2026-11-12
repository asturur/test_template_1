# First measured CPU baseline batch

2026-11-12. Partial phase00/01 of the [ordered CPU import plan](cpu-donor-import-plan.md).
The original15 ARM kernels have now executed on H0, H1, frozen current work and
its matched old-SDRAM control. No CPU RTL import or production-source edit was
made. The branch remains `codex/ngage2-integration`; donor sources are read-only.

## Sources, controls and execution

The mandatory order was H0 `ce8d2c902724a59e7537b845bc841dbd82d5bbf7`,
its direct child H1 `3f5e8aeae3260562a814eacdd8d8aa505c044af8`, then B0/current.
“Current” here is the existing frozen B0, source ID `3d96bd00dcf9…`, not the
concurrently changing live checkout. Its matched old-SDRAM control changes only
six saved predecessor files inside its own isolated snapshot. Full source IDs,
compiled executable hashes, binary hashes and image identity are retained in the
[maintained evidence](evidence/cpu-donor-import/baseline-runtime-2026-11-12.json).

Experiment `cpu-donor-baselines-20261112-b`, attempt0002, passes the original
H0/H1 dependent-ADD smoke. Attempt0003 passes480 observations: four variants,
15 kernels, scalar/line modes, I:D waits0:0 and2:9, seeds1/17, jitter0.
Two warm-ups precede three scored windows. All240 deterministic pairs match
**every raw window and whole-run counter**, including warm-ups. The seeds do not
change the memory schedule when jitter is zero; they provide separate identical
executions, not randomized stress coverage.

All120 B0/old-SDRAM comparisons likewise match every raw counter. This is the
required negative control: the synthetic backing model does not instantiate
SDRAM RTL. H1→B0 includes already-imported RF and cache/TLB changes; it is not a
controller-only comparison. All120 H1→B0 measured body-cycle comparisons are
identical in this batch. The donor MLAB RF is already present and receives no new
speed-gain attribution.

All variants use the same10ns harness clock period and memory convention.
The board remains at78MHz;104MHz remains the target. Harness cycle counts do
not establish routed timing, resources, board operation or FPS.

## Measured tradeoff

The scalar comparison and14 hot line-mode kernels show identical H0/H1 body
cycles. The cold65-line stride exposes the refill-interface tradeoff below.
B0 and its old-controller control have the same measured body cycles as H1.

| Mode / I:D waits | H0 | H1 | B0 | H1 cycle change | H1 throughput change |
| --- | ---: | ---: | ---: | ---: | ---: |
| Scalar /0:0 |2897 |2897 |2897 |0% |0% |
| Scalar /2:9 |7577 |7577 |7577 |0% |0% |
| Line /0:0 |2897 |3157 |3157 |8.97% more |8.24% lower |
| Line /2:9 |7577 |3742 |3742 |50.61% fewer |102.49% higher |

H0 retains scalar refills in the line-mode comparison because it lacks the line
port. Each measured cold window contains520 scalar32-bit reads on H0, or65
line requests and1040 halfwords on H1/B0, with zero writes. All32 cold-stride
observations satisfy that contract. At zero wait the modeled line transport adds
260 clocks across65 fills. Changing the D wait to9 adds4680 clocks to the
scalar body and585 to the line body, reconciling the observed520 versus65 wait
payments. The I side is warm in these windows. These results characterize the
specified synthetic transport, not the physical controller's timing.

Every case, transport, profile and repeat is in the generated
[body-cycle tables](../build/sim/cpu-donor-import/cpu-donor-baselines-20261112-b/attempts/0003/report.md),
[CSV](../build/sim/cpu-donor-import/cpu-donor-baselines-20261112-b/attempts/0003/report.csv)
and [JSON](../build/sim/cpu-donor-import/cpu-donor-baselines-20261112-b/attempts/0003/report.json).
The maintained evidence also preserves all60 case/transport/profile rows, with
separate cycle-savings and throughput fields. No overall score is assigned to
this incomplete suite.

## Qualification and limits

All32 host harness/reporting checks pass. Across the eight CPU/transport builds,
all120 deliberately wrong guest expectations reach the original failure mailbox;
all8 ADD replays match their original complete counters; all24 missing/equal
marker controls fail as required. These152 HDL qualification checks pass. The
separate smoke attempt also passes10 qualification checks.

All480 observations satisfy expected ordinary-retirement counts in all2400
windows, derived from the explicit kernel instruction/control-flow streams.
The ADD window contains128 ADDs plus the closing NOP, and its warmed schedule is
129 clocks. Block copy produces33 ordinary last-uop events; the branch loop194;
CP15 reads only1 because its64 MRCs are excluded by this observer. This explicitly
qualifies `retire_proxy` as a proxy, not architectural instructions or CPI.
Useful-operation units are listed in the exported tables/CSV; a load-plus-ADD,
store/reload iteration, copied word or call is not one architectural instruction.

Qualification logs, mutated program copies, commands and executable hashes are
append-only under attempt0003's `qualification-*` folders. `qualify.py` and
`report.py` add these checks without altering the frozen harness, source trees
or normal program binaries. Frozen integrity is checked before runs/reports.
The original first-batch Docker blockage is superseded; the old blocked attempts
remain intact. Optional software-oracle validation remains BLOCKED: the previously
recorded host Unicorn native initialization SIGILL is unresolved, and the existing
simulator image has no installed Unicorn. No oracle dependency was downloaded.

The existing physical-controller runtime evidence applies to B0: all9 native
source hashes and all6 saved predecessor hashes match the frozen snapshots;
[source correspondence](evidence/cpu-donor-import/sdram-source-correspondence-2026-11-12.json).
See [native SDRAM validation](sdram-native-validation.md) for its separate
measured results and remaining board/fit gates. No physical tests were repeated
or attributed to the synthetic CPU matrix here.

A local Call of Duty v3.6a card container was found in the preserved consolidated
scratch files. Its hash matches the prior format inspection (`a611fdf97810…`);
[read-only input inventory](evidence/cpu-donor-import/gameplay-input-2026-11-12.json).
There is no verified runnable scene, guest-level start state, input script or
validated game-produced-frame marker in this benchmark suite. Gameplay is
BLOCKED; no game was launched and no hardware session was accessed.

## Resume before CPU imports

Phase00/01 remains incomplete. Next qualify instrumented/uninstrumented effects,
random holds/reset and further waits/seeds, then add and run the planned
Thumb/BL/IRQ, ISA/fault, multiply/flag corner, compiled ARM/Thumb C and production
memory/contention families. Record architectural outcomes using an independent
applicable oracle; passing these guest assertions is not complete ARM920
certification. Freeze complete group membership/weights before a cumulative score
or import. Resource and routed timing measurements are NOT_RUN. Preserve78MHz
operation and the104MHz target; continue the original import order only after
its relevant baseline and acceptance gates are satisfied.
