# Step 5E — call/return delivery, 17 November 2026

**Reject the single registered-BTB handoff prototype and retain accepted 5D
`258eed3abffac2017462d57005ef4da0e8443357`.** The prototype is functionally
correct in the recorded checks, but accelerates stale return predictions enough
to delay their corrections. Matrix gets slower despite earlier useful call
fetches. Production RTL and the patch series through 0077 remain unchanged.

| Identical original work; median cycles | Exact 5D | Prototype | Change |
| --- | ---: | ---: | ---: |
| ARM matrix, 16 products | 45,736 | 46,932 | +1,196 (+2.6150%) |
| ARM transpose, 32 transposes | 3,591 | 3,537 | −54 (−1.5038%) |
| Original Thumb JPEG, 64 pixels | 84,353 | 84,014 | −339 (−0.4019%) |
| Drained 64-store stream | 71 | 71 | 0 |

Both established I:D profiles, 0:0 and 2:9, give these medians. Original bytes,
mathematical/Unicorn outputs, guards, saved registers/SP, seven windows, two
repeats and wrong-output controls pass. The JPEG scored windows are
84,399/84,353/84,353/84,353/84,353 versus
84,060/84,014/84,014/84,014/84,014 at 0:0; at 2:9 the first window is
84,417 versus 84,078 and the later four are unchanged. The first scored window
has one instruction line/eight scalar reads; subsequent scored windows have
zero external traffic. Matrix and transpose have zero scored external traffic.
These are offline fixed-work results, not a phone score or physical timing.

[Complete dynamic stage schedules, identities, checks and edge witnesses](evidence/cpu-target-delivery-20261117.json).

## What was traced

The [donor comparison](ngage2-vs-5c-benchmark.md) uses exact 5C and retirement
intervals. It is not an experiment on 5D and does not identify an isolated
frontend savings budget. Exact 5D was recompiled and measured here. Its helper
BL→first SUB retirement median is still six clocks and BX→caller is seven,
the same medians reported for 5C. The donor's one-clock medians therefore
remain a reason to investigate delivery, rather than proof that five/six
clocks per transfer can be removed by one change.

The passive observer samples before the active edge. It distinguishes:

- Registered BTB prediction, its source packet and target metadata.
- Accepted predecode call/return target and registered correction.
- First offered request belonging to the **surviving** target fetch, its ACK,
  accepted F packet, predecode head, decode and first actual operand dequeue.
- Both source and target ordinary retirement events.
- Exclusive data, multiply, load/shift dependency, empty and other occupancy;
  separately overlapping wrong-target fetch holds, translation-pipeline busy
  and external-bus activity.

Repeated PCs are aligned by dynamic retirement order and source occurrence.
The fetch must survive the last frontend flush before its target head. An
earlier killed request to the same return PC is excluded. A held value is not
an issue; reset/older kills, data/multiply holds and operand locks exclude
advancement. An LDM/STM can start issuing before predecode releases its final
micro-op, so target availability uses its first valid head, not that release.

ARM/Thumb stage PCs are observed directly. Thumb BL's internal packet names its
suffix halfword; the report maps that to the original prefix PC. The resulting
22,500 JPEG instruction histogram exactly matches the independent original-code
oracle. All 22,508 ordinary retirement PCs, including wrapper work, match
between versions in each profile. Matrix retains all 14,353 PCs and transpose
all 1,025. Complete passive traces also repeat exactly.

## Frequency and bounded opportunity

Matrix has 1,024 original helper BLs and 1,024 helper BX returns. The BTB gets
633 calls right; predecode corrects the other 391 calls and every helper return.
There are also 16 outer matrix returns, whose RAS hints are wrong because their
wrapper entry is not a recognized BL. Those are recorded separately from the
helper comparison.

JPEG has 905 original BLs at 19 sites and 905 mapped return packets at 11 sites.
Predecode corrects 513 calls and 778 returns. All calls and 779 return hints
identify the actual successor; 126 return hints need later execution correction.
Its recognized BL nesting reaches three levels, with 904 directly matched LR
returns; indirect/tail-return ownership is also present. All native outputs and
the full retirement sequence are checked, rather than treating speculative RAS
activity as committed calls. There are 130 additional accepted RAS updates that
do not map to a separately retired transfer: 128 at `505adef6`, two at
`505aec1a`. They are excluded from the dynamic transfer count.

Across the 633 surviving correctly predicted matrix transfers, the registered
BTB target precedes its offered target request by **four clocks**. The same is
true for 463 JPEG transfers; another 56 have a ten-clock gap including holds.
There are 519 surviving correct JPEG predictions in total. Reusing the existing
registered CPU handoff can remove exactly one local PC stage: a direct target
of 633 clocks (1.3840% of matrix) or 519 (0.6153% of JPEG) if every one were
exposed. Those are counts for this mechanism, not promised wall-cycle savings.
Other predictions can launch wrong-path work, and backend slack can hide gains.

The first scored matrix contains 13,619 empty-operand clocks in the helper
call/return intervals. Including outer returns gives 13,939 in their nonoverlap
union, versus 14,678 whole-window empty clocks. JPEG's transfer-interval union
contains 11,322 empty clocks; its intervals overlap by 126 clocks, counted once.
That union also contains 9,023 data-hold clocks and 3,806 load/shift-lock clocks.
None of these empty counts is a removable budget. In the whole first scored
JPEG window, data holds and load locks alone occupy 39,845 of 84,399 clocks.

Warm matrix request→F medians are six clocks for calls and one for helper
returns; F→decode is six/five and decode→first dequeue is one. JPEG request→F
is six clocks for both classes, F→decode five and decode→dequeue one. Its
call-target issue→retirement median is another 13 clocks, reflecting real
backend work; returns have six. `tlb_busy`/translation wait often denotes the
registered translation pipeline, not a page-table miss. Warm zero-external
windows cannot be credited with eliminating external walks/refills.

## Comparison with 5A and one selected architecture

[5A](cpu-frontend-delivery.md) already put registered CPU corrections into the
first PC stage when the old fetch was ready. It also preserved the target in
invalid PC payloads for resident cache lookahead. The second original helper
call still has known-target→request/F/decode/issue offsets **4/8/13/14** on 5D;
the second helper return still has **5/6/11/12**, exactly the corrected 5A
witnesses. Another claim of removing that same CPU-source stage would double
count an accepted optimization.

The one prototype changes only `zap_writeback.sv`: at the existing ready,
valid-source BTB branch, replace `zap_pc_shelve(pc_from_btb)` with
`resume_registered_redirect(pc_from_btb)`. Its registered target enters the
first PC stage and remains in invalid later payloads for lookahead. Outgoing
prediction metadata, source-fetch acceptance, predictor/RAS contents and
ALU validation are unchanged. Existing older CPU/fault/interrupt/load-PC,
pending-owner and I-cache replay priorities remain above this branch.

It adds **zero state**, no predictor capacity, queue, payload copy, DSP work or
response bypass. It preserves the fetch packet while held. This was chosen as
one bounded test of a remaining registered target handoff; no donor RTL, cache
resizing or broad predictor redesign was attempted.

## Earlier requests and the measured regression

For the first correctly predicted matrix call, `1000224c → 100011c4`, offsets
from its registered BTB prediction are:

| Event | 5D | Prototype |
| --- | ---: | ---: |
| BTB target registered | 0 | 0 |
| Target known at predecode | 5 | 5 |
| Surviving target request | 4 | 3 |
| Target ACK | 9 | 8 |
| Target accepted in F | 10 | 9 |
| Target decode | 16 | 15 |
| First useful operand dequeue | 17 | 16 |
| First target retirement | 23 | 22 |

All 633 correct matrix predictions save that one local request stage. The 519
JPEG predictions likewise change 4→3 or 10→9. But in the first correctly
predicted JPEG example, original BL `505a9ea4 → 505adef4`, an earlier request/F
(4→3 and 10→9) is hidden by older work: decode is 44→45, first dequeue 55→56
and retirement 61→62 from the predictor event. Source retirement also moves
58→59, so its source→target retirement interval is unchanged. Earlier F alone
does not establish useful elapsed acceleration.

The first helper return exposes the failure, with offsets from its RAS-known
target (`100011e4 → 10002188`):

| Event | 5D | Prototype |
| --- | ---: | ---: |
| RAS target known | 0 | 0 |
| Registered decode correction | 1 | 1 |
| Correct target request | 5 | 8 |
| Correct target ACK | 8 | 11 |
| Correct F / decode | 9 / 14 | 12 / 17 |
| First useful dequeue / retirement | 15 / 21 | 18 / 24 |

In 5D the unrelated BTB prediction to wrapper `000000f8` occurs at offset 0;
the RAS correction kills it before it becomes a request. In the prototype its
prediction has already occurred at −6 and its request starts at −3. The old
`000000f8` packet stays held through offset +5 while internal translation and
resident lookup finish. The correction is saved, and the correct request must
wait until +8. There is zero external traffic in this matrix window: this is
an owned internal wrong-path demand, not an SDRAM miss or backend multiply
failure. Full before/after edge rows are in the evidence.

Matrix's disjoint accounting is exact: **empty +1,164, read hold +32 = +1,196**;
all other buckets, including 3,072 multiply-busy clocks and 3,088 shift locks,
are unchanged. Helper-call source→first-target retirement intervals improve
by 383 clocks in total, but all mapped return intervals worsen by 1,137 and
other retirement intervals by 442. These are disjoint observed interval deltas,
not independent design budgets. JPEG's 339-clock gain is entirely fewer empty
clocks; other exclusive buckets remain unchanged.

## Qualification, risks and retained choice

The exact measured prototype passes 38 real-writeback checks twice: ready BTB
handoff, prediction metadata, ARM/Thumb canonicalization, FCSE/PID boundary
carry, stalled source and target packets, successors, CPU correction/cache
replay priority, older DABT/FIQ/IRQ/PABT/SWI/UND/load-PC, pending IRQ and reset.
Eight existing real-CPU diagnostics pass at 0/3 waits: ARM/Thumb/link smoke,
FCSE, discarded and actual prefetch faults, and the trained return-alias guard.
The guard stops only at its expected `0x0bad0000`.

The unchanged memory guest passes at both profiles: 448 ordered accepted
stores, actual writes, completions and retirements, 16 independent dirty backing
words, 71-cycle warm drained streams, older IRQ/abort and wrong-path effects,
held owners, dependent loads, permissions, device exactly-once and late/second
store cases. Wrong expected physical bytes still fail on the first mutation.
The full native JPEG exercises nested calls and Thumb BL links, in addition to
the directed ARM/Thumb/link and alias controls. No functional DUT failure was
found; rejection is based on the measured matrix regression.

The candidate also increases use of registered BTB target selection, FCSE
mapping and inactive-address fanout. Their physical packing/timing impact is
unmeasured. The physical PLL remains 78 MHz and the registered design target
104 MHz. There was no Quartus fit, CI dispatch, branch/worktree, deployment or
hardware input. There is no new timing-closure gate for this offline decision.

Retain production 5D and its existing patch provenance. Preserve the rejected
overlay under the test directory as replayable evidence; do not append it to
`UPSTREAM.json`. The next bounded research question is **useful corrected-target
preparation versus disposable predicted-demand ownership**: can a known
correction prepare its resident target without accelerating a stale demand or
violating the held packet? Trace that registered boundary and its cancellation
rules before changing it. Skipping another fetch stage or importing a donor
predictor is not justified by this experiment. Stop after this outcome.

## Identities and replay

Exact control source bundle:
`a70e107c983794856fb6091433866f9809263d0f307e356991c2e7a3d60f7f68`.
Rejected prototype:
`70865ee70bbfe39722f751c8c913788e802c2e98dd83ff779ac4db959ff55889`.
All 60 compiled control CPU RTL inputs equal accepted 5D; the candidate differs
only in the frozen writeback file. Fixed snapshots include observer inputs.
The installed simulator image is unchanged, networking/pulls disabled, all
builds serial with one compiler job. Only this step's rebuildable objects were
removed; traces are losslessly compressed with raw hashes, executables retained.
Other working files, donor work, runs, checkpoints and private assets remain.

Maintained helpers are in `tests/cpu/cpu_target_delivery/`. Use unique names:

```sh
python3 tests/cpu/cpu_target_delivery/bench.py --control --name CONTROL \
  --case matrix4 --case transpose4 --jobs 1
python3 tests/cpu/cpu_target_delivery/bench.py --name PROTOTYPE \
  --case matrix4 --case transpose4 --jobs 1
python3 tests/cpu/cpu_target_delivery/jpeg.py --control --name JPEG_CONTROL
python3 tests/cpu/cpu_target_delivery/jpeg.py --name JPEG_PROTOTYPE
python3 tests/cpu/cpu_target_delivery/redirect.py REDIRECT
python3 tests/cpu/cpu_target_delivery/diagnostics.py DIAGNOSTICS \
  --build build/sim/spmark-payload/PROTOTYPE
python3 tests/cpu/cpu_target_delivery/run.py MEMORY --safety \
  --arg +i_wait=2 --arg +d_wait=9
python3 tests/cpu/cpu_target_delivery/run.py MEMORY_ZERO --safety \
  --reuse build/sim/cpu-target-delivery/MEMORY
python3 tests/cpu/cpu_store_overlap/negative.py build/sim/cpu-target-delivery/MEMORY
```

Final named runs: `target-{control-02,candidate-01}` under
`build/sim/spmark-payload/`; `target-jpeg-{control-01,candidate-01}` under
`build/sim/jpeg-payload/`; `redirect-01`, `diagnostics-01`, `memory-01` and
`memory-zero-01` under `build/sim/cpu-target-delivery/`. The ARM-only initial
`target-control-01` calibration also reproduced 45,736; final `control-02`
uses direct stage PCs consistently for ARM and Thumb.

`timeline.py LOG OUTPUT` reconstructs a schedule from any recorded trace;
`analyze.py` audits the named final runs and writes the durable evidence.
`storage.py RUN_DIRECTORY` compacts only a completed Step5E run. No scratch-only
helper is needed to reproduce the experiment or its rejection.
