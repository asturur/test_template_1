# Step 5G — resident line crossing, 17 November 2026

**Reject the sole isolated prototype and retain production 5F.** The halfword
tail improves by68 clocks (5.105%); the byte tail improves by only1 (0.061%).
It fails the agreed two-tail retention gate. No production RTL or upstream patch
was changed, and no second design, fit, donor run, deployment or phone access
was attempted. The separately dispatched5F fit remains pinned and untouched.

| Original workload; both0:0/2:9 | Pinned5F | Prototype | Required maximum | Decision |
| --- | ---: | ---: | ---: | --- |
| fill16_tail,1,023pixels |1,332 |**1,264** |1,278 |passes this performance gate |
| fill8_tail,2,051bytes |1,647 |**1,646** |1,581 |fails; reject candidate |

Scored halfword samples:1332/1341/1332/1341/1332→1264/1273/1264/1273/1264.
Byte:1647/1645/1647/1645/1647→1646/1644/1646/1644/1646. Both profiles reproduce
every sample twice. Original bytes, mathematical/Unicorn outputs, both guard
regions, every checked output byte, saved registers/SP and bad-output rejection
pass. Warm scored windows have zero external reads/writes/refills.

## Control and all-scored crossing gate

Control is exact`8e70b1ebc16486443d09f008384b4c0bc41c071c`, the accepted5F CPU
with the same five multiplier numeric encodings written at explicit six-bit
width. Its tail cycles reproduce5F exactly. All60 compiled CPU RTL inputs are
checked against that Git object. The candidate changes only
`rtl/arm920/cache_access.sv` in a test overlay; production source is never copied
back. Source IDs and executable/input/observer hashes are in the
[machine receipt](evidence/cpu-store-crossing-20261117.json).

The passive journal covers **all five scored windows, both profiles, both exact
repeats**. Each halfword window has504 main word stores and63 physical-line
crossings; each byte window has512 and64. Each accepted VA, translated PA,
physical tag/way/segment, word mask/data, actual RAM write, architectural base
write and retirement is independently reconciled. Across both versions this
checks20,320 main word mutations and2,540 crossings. Extra speculative operand
dequeues are separated from the accepted/retired prefix; they do not count as
completed work.

At every crossing the next line is physically resident, but absent from the
eight recent-line certificates. Neither version has a registered RAM probe
result for it. Retaining the existing RAM-probe token would not certify that
line; the ordinary registered tag lookup must still validate it. In the control,
every halfword crossing spends two ready-blocked clocks draining older stores:
**126 clocks/window**. Byte has62 such crossings plus two late arrivals with no
drain wait: **124 clocks/window**, correcting the earlier conditional128 estimate.
The54/66-clock wall-gain gate was plausible but not guaranteed, so one prototype
was justified.

The last old-line store remains the `pipe_mva` owner; the preceding store is in
commit. At the first new-line offer, old pending counts are2 then1. In the
control the serial lookup owner captures only after both drain. A valid tag RAM
scan, independent of the recent-directory way selector, supplies each expected
physical slot and backing PA. No fallback `result_way` is treated as certified.

## The one registered overlap

For an already permitted, ordinary cacheable/bufferable eligible store with no
recent-line certificate, allow the **existing registered serial lookup owner**
to capture while older certified writes drain, only when its segment differs
from the last pipeline store. Different segments exclude all old physical slots
without guessing the unknown new way. Normal L0/read/compare/STORE_HIT stages
then validate the resident line. There is **no early store credit or CPU ACK**
for that new owner; data/dirty mutation and its response remain serialized after
tag validation. Every original permission/alignment/request qualifier and the
serial fallback remain. Loads, device requests, maintenance, same-segment
aliases and known-line pipelined acceptance are not widened.

Source-level cost: **zero added state bits, payload registers, RAM ports/blocks,
DSPs or cache-tag comparators**. One three-bit segment inequality plus existing
qualified-store/result-known predicates joins the ready expression. The request
still captures a registered owner; there is no new unregistered tag→issue ACK.
Actual ALM packing and routed timing are unmeasured. This is a resource estimate,
not a claim about the running matched fit. Cache geometry and78MHz PLL stay fixed.

## Before/after first-crossing schedule

Same local schedule in both tails/profiles; offsets from the crossing store's
actual operand dequeue. The address row names the registered ALU/P0 address,
not its earlier combinational availability.

| Event | Pinned5F | Prototype |
| --- | ---: | ---: |
| Actual operand dequeue |0 |0 |
| Registered address |3 |3 |
| First qualified offer |4 |4 |
| Serial owner accepts |6 |**4** |
| Registered tag decision for the new line |9 |**7** |
| Actual RAM write |11 |**9** |
| Architectural base write / retirement |13 |**11** |
| Next committed loop's first useful issue, halfword |15 |15 |
| Next committed loop's first useful issue, byte |20 |20 |

The first new store is atVA`80004020`, physical line`0a004020`; the last old
store is`8000401c`. Candidate acceptance overlaps its old owner/commit, but the
new actual mutation follows them in order. All63 halfword crossing issue→accept
latencies move6→4 and issue→RAM11→9. For byte,62 move likewise; the other two
remain7/12. Issue→retire changes13→11 for the moved stores. The per-window
histograms, physical owners, first/last witnesses and complete schedule hashes
are retained. Earlier response is not assumed to mean earlier useful issue.

## Wall-cycle accounting and the exposed empty clocks

Every scored window gives the same disjoint delta in each profile:

| Exclusive bucket | Halfword | Byte |
| --- | ---: | ---: |
| Write waits |−96 |−124 |
| Empty operand queue |+29 |+123 |
| Other |−1 |0 |
| Read waits / load locks / other locks |0 |0 |
| **Wall clocks** |**−68** |**−1** |

The local126/124 acceptance targets are not additive wall savings. Changed issue
phasing means halfword write holds fall96, not126, and29 empty clocks absorb
part of that gain. Its first-scored committed loop-spacing histogram changes
from58 intervals of19 clocks plus startup exceptions to29 of19 and28 of17 plus
exceptions. Inter-loop empty clocks increase8→41.

Byte remains dominated by replenishment:61 steady intervals of23 clocks become
60 of23 plus one22-clock interval. Inter-loop empty clocks rise257→380; the
usual four empty clocks per interval become six. Thus the124 shorter write
waits almost exactly reappear as123 empty clocks. The first crossing witness
shows the following useful issue unchanged despite earlier retirement.

The historical5D→5F byte result already reconciled **−772 write +250 empty −3
other =−525 wall clocks** (2172→1647). Current first-scored5F empty time is360
clocks:257 between committed loop starts and103 outside those intervals.
The250 is a measured increase relative to5D's110, not an independent removable
budget. This experiment removes the remaining drain wait yet raises that empty
time to483; simply shortening cache acceptance does not repair frontend supply.
The original5F receipt is preserved unchanged.

## Qualification boundary and stop

Passing evidence here covers original tail correctness/repeats/negatives and
all-scored independent physical slot/mask/data/base/retirement ordering.
An initial observer used the physical-tag RAM's way/segment address order
instead of segment/way. That run is explicitly excluded; the observer was
corrected before the final control and sole prototype. No DUT failure or second
RTL design is hidden by that fixture repair.

**This is not a fully qualified replacement CPU.** The byte performance gate
fails, so no candidate warm64, other-kernel/JPEG, IRQ/fault, alias/dirty or rejected
permission campaign was started, and no production adoption/patch was made.
Production5F retains its established71-cycle stream and prior safety results;
those are not relabeled as results for this prototype. Respecting the bounded
stop avoids broad qualification of an already rejected change.

Remaining bottleneck: useful frontend/operand replenishment following a line
crossing and loop transfer, especially byte-tail phasing. No follow-on design
is selected or executed here. Retain5F and end Step5G.

Replay helpers: `tests/cpu/cpu_store_crossing/`. Correct final runs are
`build/sim/spmark-payload/crossing-{control-02,candidate-01}/`.
`analyze.py` audits all scored journals and receipts, including archived `.log.gz`.
Only these runs' and the excluded observer attempt's compiler/frozen-source
and generated binary outputs were retired after verification. Manifests,
results, original guest assembly, observer inputs and compact logs remain.
