# Owned resident-way cache access — 2026-11-15

The next resident-cache bottleneck is implemented in two separately frozen and
measured stages on the original integration branch. The ordinary CPU remains
single-request; no PLL, cache geometry, guest/firmware image or OSD changes.

## E1: small directory and indexed reads

E1 is an explicitly declared joint directory/read candidate. It replaces E0's
one 28-bit absent record with two fully associative line-result records: valid,
27 MVA line bits, presence and 6-bit way, plus one replacement bit (71 bits).
A known absence retains the nonallocating-store route. A known resident line
can select the existing data RAM; no line payload is cached in FFs.

Current P2 checks still precede admission. The upstream ordinary-data class
excludes instruction fetches, SWP and unsupported clients. The chosen way and
indexed class are captured with the actual request; RAM selection uses the
registered MVA/way owner, not the live directory comparator. LOOKUP_CAPTURE
reads existing RAM then advances directly to READ_LINE. A tag miss/unknown
record keeps the normal lookup. Reset, cache disable, refill, maintenance,
invalidation and lock revoke facts, while accepted owners finish precisely.

The shared read port is explicit in cache_bank: indexed segment/way/read owner
versus maintenance, victim or CAM lookup. Instruction-cache classification
constant-disables the path. Legacy test clients explicitly withhold reuse,
retaining the original response/dirty-packing equivalence contracts. This
request-class input is not a build/user setting.

E1 adds 50 declared data-controller state bits over E0: 43 for the larger
71-bit directory and 7 for the indexed owner/way. The ordinary-owner flag is
repurposed, not duplicated. No new RAM, full-line copy or dirty-flag mirror.
Actual fitted ALMs/register pruning remain unmeasured.

## E2: indexed resident stores with fresh dirty RAM

E2 changes only the owned indexed-store route relative to frozen E1. It adds
no declared state. Eligible ordinary write-back stores advance from the capture
stage to STORE_HIT, retaining the real STORE_COMMIT edge and registered CPU
completion. Write-through, uncached, SWP and unknown cases keep their fallback.

The preceding edge reads the selected owner's tag/dirty M10K segment. At store
capture, cache_bank takes the indexed segment/way/data/byte mask while tags takes
the current MVA and **fresh raw dirty halves for that same selected way**.
The normal CAM dirty snapshot is too old for this shorter route. Existing data
and metadata write ports commit together on the next edge. Dirty OR, physical
writeback tags, no-write-allocation and exact-once semantics remain intact.
The chosen way is decoded directly per metadata way; it does not traverse the
64-way hit encoder and then decode that late result back into every write flag.

Dirty/selector boundaries stay registered for the 104 MHz target. There is one
additional combinational 2-bit dirty selection across existing RAM outputs,
not another dirty array. Current 78 MHz PLL is unchanged. Routed timing/fit
must be checked independently; cycle savings do not establish 104 MHz closure.

Assertions require a fresh valid tag at indexed-store capture, matching data/
metadata segments, no refill/scan/victim conflict and no uncommitted same-slot
write. The current blocking controller satisfies that contract. Later overlap
must provide an interlock or qualified forwarding for data **and** dirty bits;
this change does not silently permit unsafe concurrent mutations.

## Results (original baseline index 100)

| Stage | Index 0:0 | Index 2:9 | Gain versus immediate predecessor |
| --- | ---: | ---: | --- |
| E0 absent stores | 130.5092 | 122.1483 | Starting point for this change |
| E1 directory + resident reads | 134.0546 | 125.4664 | +2.7165% / +2.7165% |
| E2 resident stores | 145.1635 | 135.8637 | +8.2869% / +8.2869% |

Combined E1/E2 improves throughput 11.2285% over E0 in both synthetic memory
profiles. Against the original baseline, current throughput is +45.16% at
0:0 and +35.86% at 2:9. These are the six-kernel geometric simulation indices,
not official phone SPMark points, board FPS or whole-game measurements.

| Kernel | E0 cycles | E1 cycles | E2 cycles |
| --- | ---: | ---: | ---: |
| Matrix | 71,119 | 66,253 | 66,031 |
| Transpose | 9,164 | 8,522 | 7,786 |
| Triangle | 40,991 | 40,317 | 39,005 |
| Full frame,0:0 /2:9 | 135,329 /201,332 | 135,327 /201,330 | 135,327 /201,330 |
| Fill16 tail | 5,228 | 5,226 | 4,334 |
| Fill8 tail | 5,960 | 5,958 | 5,058 |

The two-clock full-frame/tail E1 delta also includes its directory/read change;
do not assign that joint gain exclusively to a gate. The buffered full frame
has no resident stores and therefore receives no E2 store-path gain. All math
and small-fill medians shown match across the two backing profiles.

Real-cache admission-to-response latency is normal read3→indexed1 and normal
store5→indexed3 clocks. A CPU-owner profile confirms repeated LDRs at10002648/
10002654 hold3clocks and STRs at1000264C/10002650 hold5, versus matching-token
5/7 before this change. Transpose data holds fall54.10%→45.57%; fill16 tail
68.97%→62.48%. Both focused profiles repeat exactly and preserve every accepted
benchmark counter. Only these two cases were reprofiled after E2.

## Qualification

Both E1 and E2 pass all six original kernels, both profiles, two exact repeats,
84windows per repeat and six wrong-output controls. E1 passes92CPU runs and
19related unit suites; E2 passes94CPU runs and the same19suites, with added data
associativity coverage. Source snapshots and fixture copies are independent,
so the E1 tests/benchmarks could not accidentally compile E2 changes.

The extended real-cache test passes92owned requests: all word lanes/masks,
partial-store freshness, two-slot aliases/capacity, high MVA tags, refill,
unsupported classes, cache toggle/reset and pending maintenance revocation.
It verifies both dirty halves by cleaning all8words of a modified line, and
exercises all8segments with alternating dirty halves, checking32writeback words
and the exact physical contents. Permission programs verify read-only User
mappings cannot be written through either warmed absence or resident facts.

Two isolated negative controls pass: the port-only E0 predecessor fails the
expected indexed-read latency check; a broken E2 prototype that sets old dirty
bits to zero instead of reading RAM fails the both-halves writeback check.
Controls mutate only frozen scratch copies. Normal dirty-packing cycle
comparison, CP15/fault/SWP/IRQ/FIQ, write-buffer retry/order and instruction
read-only equivalence remain passing.

Relevant focused commands:

```sh
sh tests/cpu/cache_resident/sim.sh build/sim/UNIQUE
python3 tests/cpu/spmark_payload/run.py --name UNIQUE \
  --baseline build/sim/spmark-payload/resident-read-20261115/result.json
python3 tests/cpu/spmark_payload/profile.py \
  --base build/sim/spmark-payload/resident-store-20261115 --name UNIQUE \
  --case transpose4 --case fill16_tail --profile 0:0
```

Run only new output names. Benchmarks/frozen sources live in
`build/sim/spmark-payload/resident-{read,store}-20261115/`; isolated CPU/unit
results use `build/sim/resident-*`. Local controls/orchestration are under
`scratch/resident-way-20261115/`. Only this step's rebuildable compiler headers
were removed afterward; every executable, frozen source, log and checkpoint is
retained. Existing other-thread simulations were untouched.

## Next boundaries

C's second translation slot and load-dependency/fetch/branch attribution remain
open. P1 probes and F multi-request CPU overlap remain separate. The indexed
bank request is already owned and contains the selectors needed by that next
pipeline; directory facts never authorize permissions or substitute for an
ordered completion. No out-of-order register/store commit was introduced.
FPGA ALM/LAB/timing and original-firmware boot/game/save/MMC verification remain
unperformed. No image changes, hardware deployment or CI build/monitoring.

[Qualification](evidence/cache-resident-way-20261115.json),
[E1 payload evidence](evidence/spmark-payload-resident-read-20261115.json),
[E2 payload evidence](evidence/spmark-payload-resident-store-20261115.json),
[CPU owner profile](evidence/spmark-payload-resident-hot-profile-20261115.json).
