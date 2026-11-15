# Current full profile after absent-line stores — 2026-11-15

Reprofiled all six accepted E0 kernels at both 0:0 and 2:9 profiles. All 12
groups/84 windows per repeat pass with two identical repeats; every original
per-window/whole-run timing, traffic and payload/helper counter is unchanged.
All 128 current CPU source hashes match that accepted snapshot; nine parser
controls pass. Production HDL and guest inputs are unchanged by profiling.

| Workload | I:D | Data hold | Read share of all clocks | Write share of all clocks | Load dependency | Empty queue |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| matrix4 | 0:0 | 28.84% | 24.07% | 4.77% | 0.28% | 32.67% |
| transpose4 | 0:0 | 54.10% | 24.77% | 29.33% | 16.80% | 14.80% |
| triangle_edges | 0:0 | 28.37% | 11.74% | 16.63% | 6.53% | 30.49% |
| fill16_frame | 0:0 | 59.35% | 0.00% | 59.34% | 0.01% | 16.95% |
| fill16_frame | 2:9 | 72.67% | 0.00% | 72.67% | 0.00% | 11.40% |
| fill16_tail | 0:0 | 68.97% | 0.11% | 68.86% | 0.19% | 13.16% |
| fill8_tail | 0:0 | 60.74% | 0.10% | 60.64% | 0.15% | 23.10% |

Read/write columns partition the data-hold bucket. Other displayed buckets use
the fixed priority accounting; raw translation/fetch/backend counters below
overlap buckets and must not be added as independent recoverable losses.

**Next priority: resident-way reuse through an owned indexed bank interface,
including stores.** Transpose and both tails are dominated by resident data
completion despite zero modeled external waits. Hot resident stores still hold
7 clocks; the tag-owner/read/compare states occupy 26.2% of transpose clocks,
29.5% of fill16 tail and 26.0% of fill8 tail. These boundaries are targets for
lookup reuse, not all automatically removable stages. Keep synchronous RAM
and dirty-half timing boundaries for the 104 MHz objective.

Build the common indexed owner path, qualify fresh resident reads first, then
measure resident stores independently. Store support must preserve byte masks,
both dirty halves, commit ordering, maintenance and same-slot hazards. Retain
current P2 privilege/translation checks; do not restore large dirty mirrors or
copy full lines into FFs. Carry selectors/results with request owners so later
P1 probes and F credits reuse the bank interface. The CPU single-completion/
global-hold redesign stays a separate step. Coverage evidence and tests are in
[selected-way investigation](selected-way-pipeline-investigation.md).

Full-frame zero-wait data holds fall from 70.00% to 59.35%. Actual hot repeated
stores at 10002AE8/10002AEC now hold 4 clocks versus 7 before E0. At 2:9 the
write hold remains 72.67%, BUFFER_STORE occupies 41.88% of all clocks and raw
backend-wait activity is 81.79%. That confirms the modeled backing-write limit;
more cache-only shortening cannot remove it. This does not qualify or identify
a physical MiSTer memory-controller defect.

Matrix's empty queue is 32.67%, read hold 24.07%, translation-related hold 9.92%.
Triangle's empty queue is 30.49%, data hold 28.37%, multiply 0.86%. C's second
mapping slot remains an independent matrix-locality experiment. Raw fetch waits
are 24.99% matrix/18.84% triangle, but their overlap with empty-queue time is not
measured by this observer: do not claim those queues are entirely fetch/branch
loss or jump directly to a predictor change. The older donor plan's RAS,
correctness, forwarding and pipeline phases stay active. Matrix multiply holds
8.64% and does not displace the broader data-path work as the next priority.

A smaller source-audited follow-up is to test whether a posted absent store can
respond immediately after durable buffer reservation rather than retaining the
extra STORE_COMMIT response step. At 0:0 that state occupies 13.53% of full-
frame clocks. This is **unimplemented/unqualified**, and its clock benefit must
be measured separately with queue/commit/reset/order tests; do not shorten
resident-store commit, which also owns data/dirty RAM writes. Keep it as a
small later experiment rather than attributing it to resident-way reuse.

[Full evidence](evidence/spmark-payload-cycle-profile-store-absence-20261115.json),
[complete state/owner report](../build/sim/spmark-profile/store-absence-full-20261115/report.md),
[benchmark results](spmark-payload-results.md), [CPU donor plan](cpu-donor-import-plan.md).

```sh
python3 tests/cpu/spmark_payload/profile.py \
  --base build/sim/spmark-payload/store-absence-20261115 \
  --name UNIQUE --profile 0:0 --profile 2:9
```

# Permission-reuse transpose profile — 2026-11-15

The full B benchmark passes all six kernels at both memory profiles, two exact
repeats and six wrong-output controls. A focused transpose observer also passes
two exact repeats, all seven windows and every original counter against that
accepted candidate. Actual hot STR owners at `1000264C`/`1000265C` now hold
**7 clocks rather than 10**. Translation-related holds fall from 12.19% to
**2.07%**, and data-completion holds from 58.85% to **54.10%**.
Load-dependency occupancy is 16.80%, empty queue 14.80%; those percentages use
the shorter 9,164-cycle window and do not by themselves imply a regression.

This is a focused post-change profile; the six-kernel table below is the
preserved e188110 A/D attribution. Matrix and fill cycle counts are unchanged
by B, and no new full-profile measurements are claimed for them. C's second
mapping slot remains a measured-locality experiment; E/F overlap requires
per-request ownership and ordering as documented in the cache plan.

[Focused profile evidence](evidence/spmark-payload-permission-reuse-profile-20261115.json),
[implementation/tests](evidence/permission-token-reuse-20261115.json),
[full benchmark results](spmark-payload-results.md).

# Integration A/D profile before B — 2026-11-15

Reprofiled commit `e188110` on the original integration checkout.
All128 production CPU source files match the accepted early-hit-response
snapshot. All six kernels pass both0:0 and2:9 memory profiles, two identical
repeats and84windows per repeat. Every original timing, traffic and
payload/helper-retirement counter matches that accepted benchmark. The nine
profiler parser tests also pass. This is new attribution of the existing
performance result; no new RTL optimization or higher throughput is claimed.

| Workload,0:0 waits | Data holds before A/D | Current data holds | Current translation-related holds | Current empty queue |
| --- | ---: | ---: | ---: | ---: |
| matrix4 | 35.70% | 28.84% | 9.92% | 32.67% |
| transpose4 | 66.84% | 58.85% | 12.19% | 13.27% |
| triangle_edges | 37.50% | 29.26% | 4.17% | 30.00% |
| fill16_frame | 76.91% | 70.00% | 0.12% | 12.51% |
| fill16_tail | 76.04% | 68.97% | 0.19% | 13.16% |
| fill8_tail | 68.82% | 60.74% | 0.17% | 23.10% |

The old column is the ARMv4T snapshot before owned-admission A and response-copy
D. The translation counter overlaps data holds and includes owner settling;
these columns must not be summed. Percentages can increase when total cycles
fall. Full-frame data holds at2:9 are72.67%; other kernels have the same hot
medians at both wait profiles. Current cumulative throughput indices remain
121.6327/119.7529 against original baseline100.

Transpose's hot STR owners at1000264C/1000265C and neighboring stores still
hold10clocks per execution, compared with the matching-token store witness
of7clocks. Matrix push/pop holds are52/38clocks per invocation. Matrix and
triangle empty-queue occupancy is32.67%/30.00%; this needs fetch/redirect/
dispatch attribution before choosing a branch change. Multiply occupancy is
8.64% matrix and0.85% triangle, below the broad data-path pressure.

**Next recommendation: B, one local mapping with separately checked read/write
permissions**, then measure C's second mapping slot independently. B addresses
avoidable direction-change lookups without another full translation/context
record. Preserve denied-write faults, AP/S/R/domain/privilege checks, force-user
access, FCSE/TTBR changes, invalidation, lockdown and walk-error ownership.
Keep the cache BRAM/read/compare register boundaries and78MHz PLL;104MHz
remains the timing objective. FPGA area/timing and phone boot are unverified.

Translation is only0.12–0.19% of clocks in the zero-wait fills, so B/C are not
expected to solve their remaining60.74–70.00% data holds. Selected-way/store
scheduling and later bounded request overlap remain in the cache plan. The
older donor plan's correctness, forwarding, branch attribution and integration
qualification work stays active; do not replace it with this kernel suite.

[Recorded evidence](evidence/spmark-payload-cycle-profile-integration-20261115.json),
[full current report](../build/sim/spmark-profile/integration-e188110-20261115/report.md),
[staged cache plan](cache-load-optimization-plan.md),
[full CPU donor plan](cpu-donor-import-plan.md).

Reproduce with:

```sh
python3 tests/cpu/spmark_payload/profile.py \
  --base build/sim/spmark-payload/early-hit-response-20261115 \
  --name UNIQUE --profile 0:0 --profile 2:9
```

# Earlier ARMv4T profile before A/D — 2026-11-15

The largest measured blocking category is the data-demand completion path,
including resident cache accesses and translation readiness. This moves that
path ahead of small ALU/multiply changes in the performance work. Production
HDL is unchanged by this investigation; the observer exists only in Verilator.

| Workload | Data completion hold | Multiply busy | Load dependency | Empty operand queue |
| --- | ---: | ---: | ---: | ---: |
| matrix4 | 35.70% | 7.84% | 0.25% | 29.35% |
| transpose4 | 66.84% | 0.00% | 12.23% | 10.52% |
| triangle_edges | 37.50% | 0.76% | 5.74% | 26.31% |
| fill16_frame | 76.91% | 0.00% | 0.00% | 9.63% |
| fill16_tail | 76.04% | 0.00% | 0.15% | 10.16% |
| fill8_tail | 68.82% | 0.00% | 0.12% | 18.36% |

These percentages use all five scored windows of each workload, with two
warm-ups excluded, on the synthetic0:0 memory profile. Buckets use an explicit
priority: data hold, multiply busy, load dependency, shift dependency, redirect
event, decode sequencing, empty operand queue, advance/other. They sum to100%.
They measure blocking-signal occupancy, not additive recoverable cycle loss:
older pipeline work can retire during an initial hold. Raw memory/fetch/redirect
counters overlap the priority buckets and must not be summed as lost time.

## Why the data path is first

Hot matrix, transpose, triangle and tail windows have no external memory
transactions. The full-frame fill posts18,305 scalar writes per window, but at
0:0 the external responder has zero wait clocks; the core still holds for data
completion during76.91% of that window. The preceding accepted benchmark also
has identical hot medians at0:0 and2:9. This points to internal request latency,
not the modeled external memory wait, for these workloads. It does not measure
physical SDRAM, LCD/MMC contention or a complete game.

Transpose spends25.67% of all clocks with a blocking demand waiting for
translation readiness. That counter also includes owner/recovery settling; it
is not a count of TLB misses or page walks. Its cache-state occupancy is38.37%
IDLE,6.35% each in LOOKUP_CAPTURE/LOOKUP_WAIT/LOOKUP,3.30% READ_LINE and3.05%
each STORE_HIT/STORE_COMMIT. IDLE includes translation and response handshakes;
it is not automatically removable idle time.

Actual held instruction owners confirm the cost: transpose STR at1000264C
(and its neighboring stores) waits12clocks per execution. Fill STRs at10002AE8
and10002AEC wait10clocks each. Matrix function entry/exit block transfers wait
72/65 clocks per invocation. This is a broad load/store and stack cost, not
just an odd benchmark instruction.

Code inspection matches the measurements:

- `rtl/arm/zap_dcache.sv` waits for owned translation/pending-request readiness
  before admitting the demand and ties the D-side lookahead fast path off.
- `rtl/arm920/cache_access.sv` sequences normal cacheable hits through
  LOOKUP_CAPTURE → LOOKUP_WAIT → LOOKUP, then READ_LINE or store commit.
- `rtl/arm/zap_core.sv` holds on the P2 demand until the registered
  `zap_data_completion` response is owned and valid.

These boundaries were introduced for real timing/permission/response-ownership
bugs. Their presence is not proof each edge is redundant. The next change must
retain registered ownership, precise faults, byte/sign formatting and exactly-once
stores while avoiding repeated hit validation/handshakes where it is safe.

## Priority and acceptance

1. Trace a resident LDR/STR across checked translation, cache acceptance and
   completion; make the narrow phase07 D-hit latency improvement first. Audit
   phase12b translation reuse separately if it is the necessary first cut.
2. Attribute the remaining empty-queue time (matrix29.35%, triangle26.31%)
   between internal fetch, redirects and dispatch. Current redirect counters
   count event edges only; they do not measure the complete branch penalty.
   Load-use forwarding is another measured target (transpose12.23%).
3. Multiply scheduling is smaller in these samples:7.84% matrix,0.76% triangle,
   zero in the other four. Keep it after the broad data path work.

Keep78MHz PLL unchanged and design toward104MHz. Do not remove BRAM/register
stages merely to lower simulated latency. Each candidate must pass the existing
IRQ/FIQ, privilege, fault, SWP, cache and Thumb regressions, then remeasure the
same original payloads and these pressure counters. ALM/routed timing and full
phone/game behavior require a separate build/hardware qualification.

## Reproduce and qualification

```sh
python3 tests/cpu/spmark_payload/profile.py \
  --base build/sim/spmark-payload/armv4t-profile-20261115 \
  --name UNIQUE
python3 -m unittest discover -s tests/cpu/spmark_payload -p test_profile.py -v
```

The companion runner copies the accepted frozen CPU sources and injects its
observer into a copy of the accepted testbench. It leaves the normal timing
harness, guest bodies and production HDL unchanged. It refuses changed source,
guest/payload hashes, image or cache-state labels. Default is all six cases,
profile0:0 and two exact repeats; `--case`/`--profile` select accepted members.

All six workloads pass,42windows (30scored), two identical repetitions. Every
original per-window and whole-run counter, including payload/helper execution,
matches the uninstrumented accepted run. Per-window bucket/state/direction sums
and scored owner-PC histograms reconcile. Nine parser controls pass (one valid
fixture and eight rejection cases). The finalized runner also passes a separate
transpose smoke with identical original counters and profile. Current RTL hashes equal the accepted
snapshot; no other thread simulation/checkpoint, hardware or CI was touched.

An initial observer used a nonexistent postalu_pc_ff signal; the demand owner
is obtained from postalu_pc_plus_8_ff−8. This profiler currently targets the
qualified ARM payloads; adapt PC/state/retirement semantics for another CPU or
Thumb workloads instead of assuming this observer applies.

[Preserved machine-readable evidence](evidence/spmark-payload-cycle-profile-20261115.json),
[complete bucket/state/top-PC report](../build/sim/spmark-profile/qualified-20261115/report.md).
