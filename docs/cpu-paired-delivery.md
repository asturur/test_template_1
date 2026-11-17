# Step5D — paired registered-product handoff,17 November2026

One bounded general owner state improves the original matrix from **47887 to
45736 clocks (−2151,−4.4918%)**. Original transpose3591, ThumbJPEG84353 and
drained64-store stream71 remain unchanged, at both0:0/2:9 synthetic memory
profiles. Same original bytes, independent mathematical/Unicorn outputs,
all scored windows, two repeats and negative controls pass. This is offline
fixed-work performance, not a board score.

## Trace first: actual elapsed opportunity

Control is exact accepted5C master`78d53d4c129e761d979794c38398aa72ecf87f87`.
All1024 original SMULL helper invocations have the same local schedule. Sample
before the active edge and require real shifter advancement: issued valid CC,
no data hold, no multiply busy and no older ALU/WB kill. A visible operand or
held value alone is not progress. Both physical destination writes and every
measured ordinary-retirement PC are separately observed.

Offsets from first low-owner start (first control231081,candidate226949):

| Event | Accepted5C | Candidate5D |
| --- | ---: | ---: |
| Exact registered DSP product ready / S1 |2 |2 |
| Low owner actually advances |3 |3 |
| High restart busy edges |4,5 |none |
| High owner actually advances |6 |4 |
| First advancing dependent100011cc, high half |7 |5 |
| Following advancing dependent100011d0, low half |8 |6 |
| Actual low write R2 |8 |8 |
| Actual high write R3 |11 |9 |
| Later valid shift-head holds |8,10,12 |6,8,10 |

There is **zero clock overlap** between the two high-restart busy clocks and
three later qualified shift locks. Their five-clock union is5120 clocks
(10.6918% of47887), but it is not this mechanism's savings budget: the holds
belong to later shift consumers, the first consumer has already advanced, and
one hold occurs after both paired writes. The product-ready→both-writes
interval spans9clocks before and7after. The low write remains fixed while
high completion and the first real consumer move two clocks earlier.
The realistically targeted direct work was **2048clocks,4.2767%** of the
workload; frontend/cache phasing can expose or hide additional elapsed clocks.

The earlier5C table mixed the first high-half consumer's issue position with
the following instruction's low-word operand sample. Step5D names the PCs
and actual advancing edges explicitly; the old performance measurements do
not change. Examplefffd412f×fffcf9dc gives000000084d4ebb64: the first consumer
receives00000008, then the following consumer receives4d4ebb64, each on its
actual advance edge. [All1024 paired schedules and audit](evidence/cpu-paired-delivery-20261117.json).

## Small general mechanism

After a low S3 result advances, a local PAIRED_READY state retains ownership of
the existing registered64-bit x result and low-half zero information. The
immediately following signed/unsigned high micro-op consumes x[63:32] directly
through the existing multiplier output. It does not restart IDLE/POST_IDLE.
An unrelated instruction or bubble expires this fast owner; a delayed high
request retains the old serialized fallback. A following low operation has
the same start controls as old IDLE. Existing reset/WB-kill priority and
held/deferred ALU-kill semantics remain. Nonzero accumulation still completes
its existing S2 sum before either half is delivered. Predication, original
register-write stages and flags stay in their original owners.

This adds **one local FSM state** (one declared logical state bit), no payload flops, DSP operation, queue or new
CPU bypass network. Signed33-bit factors and the registered66-bit DSP product
block remain byte-identical to5C. Low/high results still write one architectural
instruction in order; the existing ALU forwarding lets consumers execute
before the later register write. Area/timing are unmeasured: the last5B fit
still has only three empty LABs and misses78/104 timing. No physical closure
gate or new fit was used for this offline experiment.

## Checked result and cycle accounting

| Disjoint matrix bucket | 5C | 5D | Delta |
| --- | ---: | ---: | ---: |
| Read stalls |5551 |5535 |−16 |
| Write stalls |2550 |2550 |0 |
| Load locks |114 |114 |0 |
| Other locks |3088 |3088 |0 |
| Empty |14765 |14678 |−87 |
| Other |21819 |19771 |−2048 |

The buckets sum exactly−2151. Actual multiply busy falls5120→3072; all2048
high-restart clocks disappear. The remaining103 clocks are observed read/
frontend phase changes, not extra removed DSP stages. The3072 valid helper
shift holds remain and move earlier. Full **14353 retirement-PC sequences**
match, with exactly one correctly ordered low and high write for each of1024
products; all advancing dependent values match independent integer products.

Focused checks pass:2048 signed/unsigned zero/random-addend vectors,4096
ordered outputs and paired flags;1536 immediate and512 expired high owners;
random holds,16 held WB kills and18 state/reset/WB/deferred-ALU-clear cases;
exact repeats and deliberately wrong-product rejection. The first unit fixture
stored state in five bits, truncating new state32 and falsely reporting a hold
failure. Widening only the observer to six bits fixes it; candidate RTL did not
change. The existing5C IRQ guest is reused byte-for-byte to interrupt S1 and
PAIRED_READY at0/3 waits; whole destination pairs, flags, failed predicates and
signed/unsigned/accumulating fallback pass. Eight ARM/Thumb/FCSE/prefetch
checks, held/fault/IRQ/abort/device/dirty-memory oracles and wrong physical-byte
rejection pass; the store stream still drains in71 clocks.

The existing ARMv4T profile, including scalar MUL/MLA and long-multiply
controls, passes at0/3 waits:4567 ARM opcode/condition cases,480 user-CP15
cases and four Thumb undefined cases. Its first run was interrupted by disk
exhaustion while printing expected undefined-op traps. The user restarted
Docker; the identical compiled executable and program hashes then passed
without a rebuild. No global restart or unrelated-container stop was performed
by this experiment. Only its superseded raw traces/precompiled headers were
removed; final traces, hashes, sources and executables remain.

## Decision and next question

Retain and adopt this bounded change on sole master: all60 compiled CPU RTL
paths equal the qualified frozen candidate, and pristine upstream replay with
patch0077 passes. Qualified source bundle
`14dd1033839d68dabf090d9b26e89ef626aaba4976675d5b5e8f408ff8bfb344`. The required controls, focused
write/flag/IRQ/kill/hold checks and existing instruction profile pass. No new benchmark payload, branch,
parallel build, CI or hardware access was used. Runs used the installed offline
simulator image and one compiler job at a time.

Next research question: can the existing general ALU→shift-operand handoff
remove the three valid helper consumer holds at100011d4/100011d8/100011dc
without a wider bypass network or worse timing? They account for3072 local
hold observations (6.7168% of45736), not guaranteed elapsed savings. Establish
producer/operand readiness and JPEG coverage before another implementation.
The physical private-probe selection/coverage path from5B remains a separate
outstanding timing boundary. Stop after this5D result.

Replay: `bench.py --control` or default with `--case matrix4 --case transpose4
--jobs 1`; `unit.py UNIQUE`; `jpeg.py --name UNIQUE`; `run.py UNIQUE --safety`;
`irq.py UNIQUE --build BUILD`; `diagnostics.py UNIQUE --build BUILD` under
`tests/cpu/cpu_paired_delivery/`. `profile.py` reuses the existing ARMv4T profile.
`analyze.py` checks the named final runs, full retirement order and all1024
actual paired handoffs. Generated outputs live underbuild/sim.
