# Early store address, late owned data — Step 4F, 16 November 2026

**Retain this isolated candidate.** Original transpose improves **4,550 → 4,041
cycles (−509, −11.1868%)**, at both I:D 0:0 and2:9. Matrix remains **52,125**;
the unchanged drained store stream remains **71**. One bounded CPU mechanism
uses existing store pipeline owners plus **five logical pending-data bits**.
Production, physical timing and the phone are not changed or qualified here.

| Identical original guest work | Corrected 4E | 4F | Saved |
| --- | ---: | ---: | ---: |
| Transpose, 0:0 | 4,550 | **4,041** | 509 |
| Transpose, 2:9 | 4,550 | **4,041** | 509 |
| Matrix, 0:0 | 52,125 | **52,125** | 0 |
| Matrix, 2:9 | 52,125 | **52,125** | 0 |
| Drained64-store stream, 0:0 | 71 | **71** | 0 |
| Drained64-store stream, 2:9 | 71 | **71** | 0 |

All five scored samples, two complete repeats, original mathematical/Unicorn
output oracles, original instruction bytes and wrong-output controls pass.
Transpose retains 800 payload instructions / 1,025 ordinary retirement events;
matrix retains 14,176 / 14,353. Warm external scalar/line traffic is zero.
Transpose's checked 2,048-byte output SHA256 remains
`ebfe239b2a964064eb2556d23d86a1e69b04f0ae63503374d1e696af2c7dc2bd`.
These are offline cycle measurements, not a phone/SPMark or frequency claim.

[Hashes, all192 pairs, actual writes and qualification](evidence/cpu-store-late-20261116.json).

## Actual opportunity and its wall-clock limit

The representative sequence is `LDR r2,[r0,#4]`, `LDR r3,[r0,#16]`,
`STR r3,[r0,#4]`, `STR r2,[r0,#16]`. The first store's base R0 and immediate
are already ready while only R3 data is missing. In 4E that store remains in
issue until R3's registered completion. The address then takes the ordinary
pipeline path, and admission follows **five clocks after that completion**.

Across all **192 first stores** in the scored transpose window, the baseline
schedule is identical relative to the R3 completion `c`:

| Event | 4E edge relative to `c` | 4F |
| --- | ---: | ---: |
| First store issues | 0 | Before `c`, while its data is pending |
| First store address registered in ALU | +3 | Before `c` |
| First store accepted after its own checks | +5 | **0** |
| First actual RAM mutation | +7 | **+2** |
| Second store accepted | +6 | **+4** |
| Second actual RAM mutation | +8 | **+6** |
| Next instruction issues | +2 | **0** |

The older loads occupy the LSU until success. An early real store request would
not be useful or safe; the exploitable operation is **private CPU address
calculation**, held in the existing ALU/P1 store owner. It performs no early tag
lookup, TLB walk, refill, cache write, device access or completion. Once the
producer succeeds, the cache is free and the first store can use that edge,
subject to its own normal translation, permission and attribute checks.

The original **768 load-lock observations are not 768 recoverable clocks**.
A first optimistic estimate was three clocks per pair, or576; it assumed a
four-clock issue-to-demand route for the following ordinary store. The complete
edge ledger shows that unchanged route takes **five** clocks. The second store
issues when R2 becomes available, one clock before `c`, so it is admitted at
`c+4`. The pair's final write therefore improves **c+8→c+6**: a practical local
saving of **two clocks ×192 =384**, even though the first store is five clocks
earlier. The occupied LSU and following-store pipeline consume the apparent
larger gain. The initial estimate is preserved in the evidence.

## Representative edges, including real data and writes

Use the first scored pair. Control opportunity/head-ready edge is **149623**;
candidate is **148624**. Compare relative edges; preceding work also speeds up.

```text
4E: head/base ready(0) --wait for R3--> return+issue(12)
                                      → address(15) → accept(17) → RAM write(19)
4F: head+early issue(0) → address(3) --held privately--> return+checked accept(12)
                                                       → RAM write(14)
Second store's RAM write: 20 → 18.  Next instruction issues: 14 → 12.
```

| Event | 4E absolute edge | 4F absolute edge |
| --- | ---: | ---: |
| Ready store head / early eligibility | 149623 | 148624 |
| First actual ALU store address | 149638 | **148627** |
| R3 registered completion | 149635 | 148636 |
| Store acceptance, VA80001004, data1b1ee3ff | 149640 | **148636** |
| Actual RAM write of that word | 149642 | **148638** |
| Following STR acceptance, VA80001010, dataa846e198 | 149641 | 148640 |
| Actual RAM write of following word | 149643 | 148642 |
| Following LDR10002654 issues | 149637 | **148636** |

At 148627 the store address exists while older load10002644 owns the LSU;
no store has been admitted. At 148636, the exact producer10002648 completes R3
with **0x1b1ee3ff**; the store's own checks pass and it is accepted. The write
occurs two clocks later. The preceding R2 read retained **0xa846e198**, which the
second store writes to80001010. Original output oracles verify every matrix.

All192 early stores have independently recorded issue, actual private address,
matching `(producer PC, physical Rd)` data and admission. Private addresses lead
data availability by3 clocks in97 cases,4 in33,6 in29,8 in31 and9 in2. All384
accepted transpose stores match **384 actual RAM writes**, in order, with exact
address, word, mask and data; an unowned/duplicate transpose mutation is fatal.
The 1,025 ordinary retirement PCs match the control in order and occurrence.

## One implementation, existing owners

The explicit overlay is `tests/cpu/cpu_store_late/rtl/arm/`, changing only
issue, shifter, ALU, post-ALU and core wiring. Eligibility is deliberately narrow:

- Original unconditional ARM immediate word STR, pre-indexed, no writeback or PC.
- Its immediately preceding original unconditional word LDR is still the owned
  issue output, writes that store's physical data register, and has PC=storePC−4.
- Address/shift dependency checks remain intact; exceptions, kills and background
  register locks exclude allocation. A dependent base stays serialized.

Only the store-data load-lock term is deferred for that class. One bit follows
its existing issue, shifter, ALU, P1 and P2 owners; post-ALU0 is an alias. Store PC
and physical Rd already identify the exact producer, so there is no new PC/tag
payload, general queue or copied address/data bank. The real address calculation
and held payload remain in the existing pipeline.

At P1, an aligned, full-word **registered** P2 completion may supply data only
when full producer PC/Rd, success and older-exception checks match. The value is
captured into the existing store data register as its owner advances. A load
whose value needs formatting takes the existing formatted B-commit path instead:
the store waits in P2, then captures that exact producer's committed value even
while held. The actual request stays disabled while its data is pending.
A valid offered request keeps stable address/data through backpressure.

Store translation, alignment, AP permission, cacheability, bufferability,
maintenance/IRQ/abort priority and real admission are unchanged. Private address
work does not assert that the VA is RAM. Cacheable RAM uses the existing store
path after its checks; device/uncached demand uses its normal serialized backend.
No new external transaction is generated before producer success and the store's
own checks. Unsupported or ambiguous instruction/data-source cases retain the
normal issue path. A faulting older load clears the younger store; stale data
cannot be substituted for an unmatched producer.

Fixed corrected4E source ID:
`9c2f022a85f3dad30026752e4537debca035b26a832821bcef950caf6edfab1c`.
Candidate source ID:
`0bf6550b3c7d9035f3d7c548c4731076b88ed024ed8590f1ebef0df320f1f081`.
The first prototype and final qualified RTL have this same candidate identity.
All cache/MMU/bank/tag/dirty, geometry, DSP/NOS/BT, writeback4E and other RTL
hashes remain identical to the fixed control.

## Measured accounting and regressions

| Priority occupancy, transpose | 4E | 4F |
| --- | ---: | ---: |
| Read stall | 737 | 737 |
| Write stall | 192 | 192 |
| Load lock | 863 | **479** |
| Other lock | 64 | 64 |
| Empty operand queue | 1607 | **1482** |
| Other / advance | 1087 | 1087 |
| **Total** | **4550** | **4041** |

The first stores lose their768 load-lock clocks, but the newly exposed second
stores acquire384 (two per occurrence). The caller's loaded branch target keeps
its95 clocks. Thus the net issue-dependency improvement is **384 clocks**.
An additional **125 empty clocks** disappear in caller-return intervals:31
returns save four and the first saves one. Other last-pair empty occupancies
redistribute with zero net change. This reconciles exactly to **384+125=509**.

The return trace confirms the extra saving rather than treating queue occupancy
as a budget. In4E,31 returns arrive while a wrong-path fetch at00000020 still
needs draining: clear→target fetch8 clocks, clear→actual caller issue20. In4F,
the old fetch is already ACKed on the clear edge: clear→target4, clear→issue16.
The first return improves17→16. No fetch/cache RTL or warm external traffic
changes. Data-read latency and fast/admitted/fallback counts remain identical.

Matrix allocates **zero** early stores, retains all profile counters and cycles,
and passes its original outputs. The drained store guest has identical raw
ordered events and cycles in both designs. No measured workload regresses.
Transpose store acceptance overlap falls192→0 because the first store now
finishes before the second arrives; the four-clock acceptance gap is a remaining
CPU limitation, not a cache-throughput regression.

## Focused qualification

The same focused guest passes on both exact4E and4F sources, with identical guest
bytes and two repeats at I:D2:9. Candidate coverage:

| Case | Early store | Data source | Accepted | Actual effect |
| --- | ---: | --- | ---: | --- |
| Cold older RAM load; resident target; long stalls | 1 | Registered P2 | 1 | One RAM write89abcdef |
| Unaligned word source, A=0 | 1 | Formatted B commit | 1 | One RAM writeef89abcd |
| Store base depends on loaded register | **0** | Normal serialized path | 1 | One correct RAM write |
| Device destination | 1 private preparation | Registered P2 | 1 | Exactly one external device write |
| Uncacheable source | 1 | Actual older demand's P2 result | 1 | One correct RAM write |
| Older unmapped load faults | 1 private preparation | No success/data capture | **0** | No write; source/destination sentinels unchanged |
| Older load succeeds; store AP permission fails | 1 | Registered P2 | **0** | No write; alias sentinel unchanged |

There are **199 held-private-address clocks**. The existing valid-request packet
checker enforces stable address/data while stalled. Fault handlers verify exact
FAR and FSR (older translation fault at70000000, younger section-permission fault
at81010000). IRQ at active store credits, precise older abort/flush, forbidden
younger accesses, same-Rd/address-dependent/LDM/writeback/failed-condition cases
and dirty writeback checks also pass. New target successes have exactly one
acceptance and one corresponding physical RAM/device effect.

The unchanged64-store performance guest retains **448 ordered accepts, actual
writes, CPU completions and retirements**, sixteen independent backing words,
all63 one-clock warm acceptance/write gaps and the **71-cycle** drain at both
0:0 and2:9, with identical raw control/candidate events in each profile. Deliberately
wrong expected physical bytes are rejected. Original transpose and matrix
wrong-output controls also remain active.

Eight existing real-CPU diagnostics pass on a separate frozen candidate build:
ARM/Thumb smoke, FCSE, discarded/actual prefetch abort, and a trained BTB-alias
cached-return guard, each at response latency0 and3. Actual bus faults are
exercised; the return guard reaches only its expected0x0bad0000 stop.

Two fixture corrections were needed, without changing candidate RTL or waiving
an output failure. The new cache-disrupting prelude required the standard
resident-line preparation restored before its existing physical-way oracle.
The permission test's base was still load-dependent; a dependency-consuming MOV
prepares it before the LDR/STR so early allocation is genuinely exercised.
Failed logs remain in `safety-candidate-01/` and `safety-candidate-02/`; accepted
coverage is `safety-candidate-03/`.

## State and likely104MHz path risks

Estimated added state is **five one-bit pending controls**, one each in issue,
shifter, ALU, P1 and P2. Existing payload registers are reused; there are no new
address/data flops, RAMs, geometry changes or intended DSP operations. Fitted
register duplication, ALMs and routed timing are unmeasured.

At104MHz the period is9.615ns. New path candidates inferred from the RTL are:

- Producer PC/Rd/class comparison → store-data lock suppression → issue controls.
- Registered completion/producer identity → P1-ready → next-owner admission and
  the32-bit store-data mux. This joins the existing completion/admission cone.
- Formatted B-commit identity/priority → held P2 data refresh and its first offer.

No live cache ACK is added to global stall; completion remains registered.
Nevertheless, narrow identity decisions now control data muxes and owner
selection, so104MHz closure cannot be inferred from the cycle gain or small
state count. Physical timing remains a later matched checkpoint; the actual
78MHz PLL was not changed and no fit was submitted.

## Single recommended next architectural step

Extend this **same producer-owned address/data separation to the second STR**,
with its distinct older R2 producer identity. The new trace exposes two data-lock
clocks per second store and a four-clock admission gap while the cache can accept
one store per clock. That class currently falls back because its producer is not
the immediately preceding instruction. A bounded extension must preserve the
older result through the existing held owner, including formatting, fault and
kill cases. No general queue or gain forecast is justified by these counts.
This extension was not implemented in4F.

## Replay and preserved outputs

```sh
python3 tests/cpu/cpu_store_late/bench.py --control --name UNIQUE_CONTROL \
  --case transpose4 --case matrix4
python3 tests/cpu/cpu_store_late/bench.py --name UNIQUE_CANDIDATE \
  --case transpose4 --case matrix4 \
  --baseline build/sim/spmark-payload/UNIQUE_CONTROL/result.json
python3 tests/cpu/cpu_store_late/run.py UNIQUE_STORE
python3 tests/cpu/cpu_store_late/run.py UNIQUE_STORE_DELAYED \
  --arg +i_wait=2 --arg +d_wait=9
python3 tests/cpu/cpu_store_late/run.py UNIQUE_SAFETY --stress --safety \
  --arg +i_wait=2 --arg +d_wait=9
python3 tests/cpu/cpu_store_late/diagnostics.py UNIQUE_DIAGNOSTICS \
  --build build/sim/spmark-payload/UNIQUE_CANDIDATE
```

Final payload runs: `build/sim/spmark-payload/store-late-{control,candidate}-final/`.
Other outputs under `build/sim/cpu-store-late/`: `store-{control,candidate}-01/`,
`store-{control,candidate}-2-9/`, `safety-control-01/`, `safety-candidate-03/`,
`diagnostics-candidate-01/`.
`tests/cpu/cpu_store_late/analyze.py` audits frozen identities, original oracles,
all192 edge sequences,384 physical writes, retirement order, counter conservation,
focused cases, repeated events and negative controls before saving evidence.

Solo/offline in the original integration checkout. Corrected4E, production RTL,
project/workflow, branch/HEAD/index, actual78MHz PLL, phone, other simulations and
permanent checkpoints remain untouched. No CI, fit, deployment or hardware access.
Stop after this measured4F result.
