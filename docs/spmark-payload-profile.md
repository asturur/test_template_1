# SPMark payload cycle profile — 2026-11-15

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
