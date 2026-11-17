# Second store preparation with its own producer — Step 4G, 16 November 2026

**Retain the qualified isolated 4G candidate.** Original transpose improves
**4,041 → 3,625 cycles (−416, −10.2945%)** against exact passing 4F. Matrix
remains **52,125**, and the drained 64-store stream remains **71**, at both
synthetic I:D delay profiles 0:0 and 2:9. Every scored sample, two repeats,
original instruction/output/retirement oracles and negative controls pass.
This is an offline CPU measurement; no fit, production integration or deployment.

| Identical work | Fixed 4F, 0:0 / 2:9 | 4G, 0:0 / 2:9 |
| --- | ---: | ---: |
| Original transpose, 32 matrices | 4,041 / 4,041 | **3,625 / 3,625** |
| Original matrix, 16 products | 52,125 / 52,125 | **52,125 / 52,125** |
| 64 original stores, first issue through final physical write | 71 / 71 | **71 / 71** |

All five scored workload windows have those exact cycle counts. Original
mathematical and Unicorn outputs, callee-saved registers/SP, original payload
bytes, 800 transpose / 14,176 matrix payload instructions and 1,025 / 14,353
ordinary retirement events pass. Warm external scalar/line traffic is zero.
Transpose's original checked 2,048-byte output SHA256 remains
`ebfe239b2a964064eb2556d23d86a1e69b04f0ae63503374d1e696af2c7dc2bd`.

[Source identities, all192 second-store transfers, physical writes and qualification](evidence/cpu-store-second-20261116.json).

## Schedule and capacity, checked before the prototype

The existing passing 4F trace has `LDR R2`, `LDR R3`, `STR R3`, `STR R2`.
R0 and the store offsets are already ready. At edge148625, the second store is
at the operand head, the first store is in Issue, the R3 load is in Shifter and
the exact R2 producer is in ALU. 4F locks the second store's data and bubbles
Issue. At148627, R2 occupies P2, R3 occupies P1 and the first store holds its
private address in ALU. **Shifter is available to hold the second store.**
No second ALU/address slot or general queue is required.

Had that second store issued at148625, it could reach Shifter at148627 and wait
there. At the registered R2 completion148635 it can consume its exact data and
advance to ALU; its address is then registered148636. The first store advances
from ALU to P1 at148635 and consumes its own R3 completion148636. Existing P1
and P2 owners can carry the two stores in order, admitting the second148637.
Backpressure continues to hold these existing owners; no payload moves into an
unowned location and no physical effect precedes its normal checks.

The preflight is preserved in the evidence. Its initial next-instruction
prediction was too optimistic: following `LDR R2` has an independent **base**
but still writes the older load's R2. The existing WAW/load scoreboard must hold
it until R2 is ready. Actual measurement moves that issue **c→c−1**, not to the
early head edge. The two former store-lock clocks and four-clock admission gap
were opportunities, not guaranteed elapsed savings.

## Actual representative pair, both stores and next instruction

Let `c` be the R3 registered completion. The representative first scored pair
has `c=148636` in fixed4F and `c=147777` in4G. Prior work also speeds up, so use
relative edges for the local comparison.

| Event | 4F relative to c | 4G relative to c | 4G absolute |
| --- | ---: | ---: | ---: |
| First STR R3 issues | −12 | −12 | 147765 |
| Second STR R2 issues | −1 | **−11** | 147766 |
| Second store held in Shifter | No valid owner before R2 returns | **−9 through −1** | 147768–147776 |
| R2 registered completion / exact data available | −1 | −1 | 147776 |
| Second address registered in ALU | +2 | **0** | 147777 |
| R3 completion and first checked store admission | 0 | 0 | 147777 |
| Second checked store admission | +4 | **+1** | 147778 |
| First actual RAM write | +2 | +2 | 147779 |
| Second actual RAM write | +6 | **+3** | 147780 |
| Following LDR10002654 actual issue | 0 | **−1** | 147776 |

The first store at1000264c writes **0x1b1ee3ff** to VA80001004. The second at
10002650 consumes the distinct producer10002644, physical Rd2, and writes
**0xa846e198** to VA80001010. Both target resident way6 in this example. The
second Shifter's data lane holds its producer PC+8 until the exact registered
R2 value replaces it; it never borrows R3 or stale RF data.

Across all192 measured second stores, allocation→exact data→actual address→
admission is audited. All192 pairs admit one clock apart and physically write
one clock apart. Every admission has its matching physical write two clocks
later. **384 accepts match384 actual RAM mutations**, with correct PC/address/
word/mask/data and no duplicates or reordering. The unchanged 4F observer also
checks the192 first-store R3 owners. The1,025 retirement PC/occurrence sequence
matches fixed4F exactly. Following issue varies with genuine dependencies:
129 cases c−1,31 cases c−5, and32 final return instructions c−4. Earlier issue
is not counted as retirement and cannot override an older fault.

## One bounded mechanism, no new payload bank

The overlay is `tests/cpu/cpu_store_second/rtl/arm/`, changing only Issue,
Shifter and core wiring from fixed4F. It adds **two logical pending bits**,
one in Issue and one in Shifter, and **zero new address/data/PC payload flops**.
Together with4F's five pending bits, the cumulative mechanism has seven logical
control bits. No cache, MMU, bank/tag/dirty, geometry, DSP, store-credit,
writeback4E or other RTL changes are made.

Eligibility uses actual architectural classes and in-flight ownership:

- Original unconditional ARM immediate word-store class, no writeback,
  PC or macro-op, with all address/shift checks unchanged.
- Its data register has an actual owned original unconditional ordinary aligned
  word load in ALU. The producer must have no base writeback or exception.
- Any younger Issue/Shifter writer to the **same physical register**, including
  a load's B destination, excludes this producer. Background locks and normal
  reset/clear rules still apply. There are no guest-PC, R2/R3, offset or
  transpose-pattern tests in the DUT.

Only this store's data lock is deferred. Its existing Issue/Shifter data lane
holds the producer's full PC+8 while the bit says pending. No operand can use
that lane as store data until a matching successful producer replaces it.
Already-committed or unsupported producers use the existing operand/forwarding
path. The bounded new class does not search arbitrary old history.

The common resolver matches full producer PC and six-bit banked Rd against a
registered fault-free aligned P2 result, or an actual matching formatted B
commit. It blocks an older matching result while a younger matching load still
occupies ALU/P1, and blocks M while P2 owns a younger matching load. This
preserves youngest-older-writer priority, including repeated PC identities.
An advancing consumer captures data into the existing next-stage register.
A **held** Issue/Shifter consumer refreshes its own existing data register and
clears pending, so a later disappearance of the producer cannot lose its value.
A runtime invariant rejects unresolved valid transfers into ALU.

First-store address/data ownership is unchanged from4F. The second address
uses the ordinary ALU; all actual store translation, permission, attributes,
credits, ordering, IRQ/abort/redirect and serialized device behavior remain on
the existing path. There is no early TLB walk, probe, refill, external write or
RAM effect from the pending tag.

Fixed4F source:
`0bf6550b3c7d9035f3d7c548c4731076b88ed024ed8590f1ebef0df320f1f081`.
Qualified4G source:
`7b9a7dd28baccdfedfe75baaac91358c7751ed56d977fe348101738946e40244`.
The DUT has this identity from the first measured prototype through qualification.

## Elapsed-cycle accounting and remaining limitation

| Priority occupancy, transpose | 4F | 4G | Change |
| --- | ---: | ---: | ---: |
| Read stall | 737 | 673 | −64 |
| Write stall | 192 | 0 | −192 |
| Load lock | 479 | 255 | −224 |
| Other lock | 64 | 64 | 0 |
| Empty operand queue | 1,482 | 1,546 | +64 |
| Other / advance | 1,087 | 1,087 | 0 |
| **Total** | **4,041** | **3,625** | **−416** |

The192 second stores lose their384 load-lock observations. Five following
LDR PCs now expose32 WAW/load-lock clocks each (160 total); the caller's loaded
branch target retains95. Thus total load locks are255, not zero. Read-stall
occupancy falls64 while empty occupancy rises64; the observed write/load/empty
accounting reconciles exactly to416. It does **not** justify a192×3=576
wall-clock forecast from the local final-write movement. Cached read-service
and private-probe timing redistribute even though cache RTL and external traffic
do not change. Matrix allocates zero new second owners and every matrix profile
counter remains identical to4F. The identical independent store loop still
accepts/writes every clock in its warm stream,71 cycles including fill/drain.
No measured workload regresses.

## Focused qualification and failed fixture expectations

The identical focused guest passes fixed4F and4G, twice at2:9. Candidate checks:

| New case | Allocation / effect |
| --- | --- |
| Distinct R6/R7 load values and independent base | Second allocates; first writes55667788, second11223344 |
| Younger ALU writer replaces older load | Old producer excluded; stored value55 |
| Younger load overwrites same Rd | Actual younger load is selected when it reaches ALU; stored55667788 |
| Source already committed | No new allocation; existing operand path stores11223344 |
| FIQ-bank R8/R9 | Physical Rd18 producer selected; SVC R8/R9 preserved |
| Intervening older load faults | Second privately allocates/resolves; neither younger store accepted or written |
| First store's own AP fault | Prepared second is killed; neither store accepted or written |
| Actual redirect | Both wrong-path store PCs have zero acceptance/effects |

The guest verifies exact FAR/FSR for both new faults and checks independent
sentinel bytes at both destinations, including the AP-fault backing alias.
Five monitored ordinary target stores have five ordered actual RAM mutations;
banked store bytes are checked by the guest too. It exercises71 held Shifter
owner clocks. Existing4F rotated-data, cold-source, base-dependency, uncached,
exactly-once device, older-fault and own-permission checks pass; existing load-pair
exclusions, an IRQ and five data aborts are exercised. Existing held valid
requests retain their address/data/mask. Standard stream oracles retain448
ordered accepts, actual writes, completions and retirements, sixteen independent
dirty backing words,63 one-clock warm gaps and deliberate wrong-byte rejection.

A separate **test-only capacity perturbation**, disabled for performance and
normal qualification, holds the actual Issue store and inserts Shifter bubbles
across its producer's return. Hold begins166019; data11223344 is saved166078;
release166147 follows **70 checked clocks with the saved data and pending clear**.
The guest then completes with all the same output/order/fault checks, twice.
This verifies a returned value survives a held consumer; it is not a performance
measurement or a change in architectural admission rules.

Eight reused real-CPU diagnostics pass: ARM/Thumb smoke, FCSE, actual/discarded
prefetch abort and BTB-alias return guard, each at latency0/3. They retain their
previous counts and expected stop addresses. Original transpose/matrix bad-output
controls remain active, and wrong expected physical bytes fail at the first
actual mutation.

No DUT failure or RTL correction was needed. Failed fixtures remain explicit:
`safety-candidate-01` incorrectly required zero allocation for the same-Rd load
case, although by the later actual allocation the **younger** load owned ALU.
The corrected observer verifies that exact younger producer PC and final value.
`safety-held-01/02` used a32-clock hold that ended before the cold load returned;
the accepted128-clock hold spans the return and70 saved-data clocks. The first
hold driver also needed its upstream stop and downstream bubbles driven
consistently. These failed runs remain INCOMPLETE and are not accepted results.
All final stream fixtures/includes are frozen and hash-pinned for reuse.

## 104MHz risk and one broader next target

The two new bits do not establish physical cost or timing. The new paths are
ALU producer class plus younger-writer comparisons→Issue data-lock release;
PC/Rd/younger-load comparisons→registered-result selection→existing Issue/
Shifter refresh and ALU data mux. The ALU source remains registered completion
or actual B commit; no live cache ACK is added to global stall. Comparator
fanout and the32-bit data mux before ALU need later physical qualification at
9.615ns. Fitted duplication/ALMs and routed timing are unmeasured. The physical
PLL remains78MHz; no CI, fit or deployment was submitted.

**Leave the transpose sequence now.** The single broader next target is
**matrix call/return target delivery and operand refill around its original
SMULL helper calls**. This exact4F/4G matrix still spends **17,995 of52,125 clocks
with an empty operand queue**; the accepted4E evidence records433 registered
redirect handoffs in matrix. Earlier architecture traces show helper BL→target
and BX→caller delivery gaps. Profile those intervals under this retained source
and remove one concrete frontend/target-delivery recurrence before proposing
more completion capacity. Empty occupancy and433 events are evidence to select
a target, not an additive savings budget. No further change is implemented here.

## Replay and preserved outputs

```sh
python3 tests/cpu/cpu_store_second/bench.py --control --name UNIQUE_CONTROL \
  --case transpose4 --case matrix4
python3 tests/cpu/cpu_store_second/bench.py --name UNIQUE_CANDIDATE \
  --case transpose4 --case matrix4 \
  --baseline build/sim/spmark-payload/UNIQUE_CONTROL/result.json
python3 tests/cpu/cpu_store_second/run.py UNIQUE_STREAM --arg +i_wait=2 --arg +d_wait=9
python3 tests/cpu/cpu_store_second/run.py UNIQUE_ZERO \
  --reuse build/sim/cpu-store-second/UNIQUE_STREAM
python3 tests/cpu/cpu_store_second/run.py UNIQUE_SAFETY --stress --safety \
  --reuse build/sim/cpu-store-second/UNIQUE_STREAM --arg +i_wait=2 --arg +d_wait=9
python3 tests/cpu/cpu_store_second/run.py UNIQUE_HELD --stress --safety \
  --reuse build/sim/cpu-store-second/UNIQUE_STREAM \
  --arg +i_wait=2 --arg +d_wait=9 --arg +second_hold=1
python3 tests/cpu/cpu_store_overlap/negative.py build/sim/cpu-store-second/UNIQUE_STREAM
python3 tests/cpu/cpu_store_second/diagnostics.py UNIQUE_DIAGNOSTICS \
  --build build/sim/spmark-payload/UNIQUE_CANDIDATE
```

Add `--control` to stream/safety commands for the fixed4F comparison and reuse
only its matching control build. The installed `jotego/simulator:arm64` runs
with no network or pull. New names refuse overwrite.

Final original workloads: `build/sim/spmark-payload/store-second-control-01/`
and `store-second-candidate-02/`. Final other outputs under
`build/sim/cpu-store-second/`: `stream-{control,candidate}-retention/`,
`stream-{control,candidate}-retention-0-0/`, `safety-{control,candidate}-final/`,
`safety-held-03/`, `diagnostics-candidate-01/` and `preflight.json`.
`tests/cpu/cpu_store_second/analyze.py` verifies source/oracle identities,
all192 owned transfers,384 ordered actual writes, retirement, counter sums,
stream profiles, frozen fixtures, focused repeats and negative controls before
saving the durable evidence linked above.

Solo/offline, original integration checkout and branch/HEAD/index preserved.
Fixed4F, production RTL/project/workflows, physical78MHz PLL, phone, other runs
and permanent checkpoints remain untouched. Stop at this measured4G result.
