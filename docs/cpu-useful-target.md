# Step 5H — useful target delivery, 17 November 2026

**Retain 5F; do not fund this path as the proposed roughly 5% RTL experiment.**
One registered delivery mechanism has identifiable opportunities in matrix and
JPEG, but the conservative event model exposes **1,555 / 970 clocks
(3.40% / 1.15%)**. These are counterfactual counts, **not measured wall savings**.
The small byte control offers only six certified clocks. No production RTL,
donor checkout, payload, fit, CI or phone was changed.

## Measured control and successor knowledge

New passive runs freeze all **60 CPU RTL inputs** at accepted 5F
`8e70b1ebc16486443d09f008384b4c0bc41c071c`. Original matrix and byte-tail
medians reproduce **45,736 / 1,647 at 0:0**; original Thumb JPEG reproduces
**84,353 at both 0:0 and 2:9**. Seven timing windows, two repeats, original
mathematical/Unicorn outputs and wrong-output rejection pass. Matrix/JPEG's
entire **14,353 / 22,508 retirement-PC sequences** equal the checked 5E
controls; JPEG's normalized histogram equals its original-code oracle.

The extended journal observes the first scored window, before each active
edge: permitted response, held F register, FIFO array read/write and head,
ARM/Thumb assembly, predecode, decode, operand arrival/dequeue, clears,
translation and cache owner. Every reported target dequeue is matched to the
**next dynamic retirement**, including repeated PCs. Matrix has all **1,024
helper calls and 1,024 helper returns**, 16 outer returns and 30 other taken
transfers. One initial wrapper transfer's source predecode precedes the
journal; it receives no credit. JPEG has **905 calls, 905 returns and 516
other taken transfers**. Byte has 68, including 63 main-loop backedges.

The receipt separates source encoding complete in F, first existing target
signal, accepted predecode, prediction and later execution correction. A
matching prediction is a speculative value, not architectural knowledge.
No hypothetical zero-clock displacement calculation or future return value
enters the model. For example, the common Thumb call `505a9e42` has its full
encoding at clock **288609**, its correct predecode target at **288612**, but
cannot accept that predecode until **288622** because of older work. Labeling
only acceptance as “target known” would hide ten clocks of overlap.

Matrix has 633 correct mature call predictions; the other 391 calls and all
helper returns use predecode correction. JPEG has 392 mature call predictions
and 127 mature return predictions. Of its 779 correct RAS hints, 652 therefore
belong to the separate predecode/RAS class. **126 RAS hints are wrong**:
their authoritative ALU corrections occur 7 clocks later in 62 cases,
14 later in 63, and 12 later once. The early matching BTB value is sometimes
discarded by that intervening wrong RAS correction; it is not reusable code
without an owned context and cancellation contract.

## Which delivery clocks are occupied

The unobstructed F-acceptance→decode path is **five clocks**: array enqueue,
registered FIFO head, assembly register, predecode register and decode register.
Actual operand dequeue follows one clock later. These are registered edges,
not five empty slots that can all be removed by storage.

Matrix's call F→decode histogram is **325×5, 301×6, 142×8, 67×9, 15×13,
174×14**. All 1,040 returns take five clocks after accepted F; 32 of those
already had the word in F five clocks earlier, inhibited by the *successor's*
held instruction demand. Of 633 mature calls, the conservative model exposes
only **16 clocks**; the other calls encounter older work or lack an earlier
operand certificate. The 391 corrected calls expose 309; helper returns expose
1,184, outer returns 16 and other taken branches 30.

JPEG calls have 645 five-clock and 131 six-clock cases; the remaining 129 are
longer. Correct-RAS return targets occupy both halfword phases; calls enter at
phase zero. Later-corrected returns split **63/63 between phases zero and two**,
and all have five accepted-F→decode clocks. The target instruction classes
include Thumb PUSH, loads/stores, BX veneers and ALU operations; “Thumb” is not
one uniform timing class. Across the F-present→decode **nonoverlap union**,
JPEG has **5,583 useful older dequeue clocks**, **8,199 data/dependency clocks**,
and **6,249 registered FIFO/assembly/predecode/decode clocks**. Fourteen more
are F held by another demand. The receipt gives each occurrence's exclusive
first blocker and the union, rather than adding intersecting intervals.

A mature JPEG call `505a9ea4→505adef4` illustrates useful overlap: relative to
BTB availability, request/F are **4/10**, head/assembly **18/31**, decode/issue
**44/55**, source retirement **58**. Earlier F cannot bypass that older work.
The first correct-RAS return `505a99d8→505a9e46` similarly has F/decode/issue
**10/18/19** from RAS acceptance, with source retirement at19; it receives no
certified saving. These are distinct from a late return correction.

## One modeled change and its schedule

**One-shot F-to-empty-head delivery:** when the FIFO array and registered head
are empty, capture the already permitted F packet directly into the existing
head register. Permit this capture while the *next* instruction demand is held.
Retain it under ordinary downstream holds. A consumed bit prevents the held F
packet from subsequently being enqueued a second time. Ordinary nonempty FIFO
ordering remains the fallback. No prediction or request launches earlier.

For `505aec1a→505a9ebe`, offsets below use the **authoritative ALU correction**
at clock290720. The earlier BTB prediction at−18 matched the successor, but
RAS redirected to505aec18 at−13. That wrong demand remains stable through+2.
The correct surviving response is genuinely late; the model does not invent a
saved copy of its earlier discarded response.

| Event | Measured 5F | Modeled path |
| --- | ---: | ---: |
| Correct surviving demand offered / permitted response |5 /10 |5 /10 |
| Correct word first present in F |11 |11 |
| F permitted to enter the ordinary FIFO |16 |head captures at12 |
| Registered FIFO head |18 |12 |
| Thumb assembly / predecode output (registered-edge derivation) |19 /20 |13 /14 |
| Decode / actual operand dequeue |21 /22 |15 /16 |

The six-clock estimate removes five clocks waiting on the successor demand
plus the empty-array edge. It preserves the held demand and the registered
decode path. A plain ARM return instead advances head/decode/dequeue
**11/14/15→10/13/14** from its accepted RAS event: one clock.

The byte backedge is a negative phase control. Its first target STR is in F
at145258 but normal FIFO insertion waits until145263; the model holds its
earlier head across the older store wait and moves issue145269→145265.
The next steady backedge has F145281, insertion145286 and issue145292.
Older stores hold predecode through145288: an earlier head reaches the same
decode/dequeue schedule. Only the first main backedge receives four clocks;
the other 62 receive zero. Two non-loop transfers add two clocks. This explains
why the 5G cache improvement mostly reappeared as frontend empty occupancy.

## Counterfactual screen, cost and stopping point

The model retains the packet at each existing register until the **measured
normal readiness** allows advance. It requires a free actual-dequeue slot and
conservatively waits for source retirement to certify older register/flag
producers. It preserves extra observed assembly latency and rejects intervening
clears. Candidate saving intervals are unioned once. Removing the retirement
certificate provides a separate free-slot screen, not an operand-ready claim.

| Original workload | Conservative exposed clocks | Median fraction | Free-slot screen without operand certificate | Local delivery clocks before overlap/holds |
| --- | ---: | ---: | ---: | ---: |
| Matrix |**1,555** |**3.40%** |1,856 |2,254 |
| JPEG |**970** |**1.15%** |1,360 |1,916 |
| Byte tail |**6** |**0.36%** |9 |383 |

JPEG's conservative total is504 from corrected direct calls, seven from mature
BTB transfers, 73 from predecode correct-RAS returns, 131 from late-corrected
returns and255 from ordinary taken branches. The same mechanism has exposed
slots in both main workloads. Neither estimate supplies convincing evidence for
the proposed **2,287 /4,218-clock** funding screen. The local column is not a
global upper bound: sequential packets and changed future phasing are outside
this transfer-only model. No column is a measured elapsed-cycle improvement.
JPEG's journal is the84,399-clock first scored sample; percentages use its
84,353 median for the planning comparison. Four later scored windows are not
silently relabeled as stage-journaled measurements.

Source-level budget: **one consumed bit**, the existing **100-bit** head tuple
(PC+8:32, word:32, abort:1, direction:2, prediction:33), one100-bit mux and
empty/valid/consume control. **Zero extra word/context storage, address/tag
comparators, RAM ports, predictor entries or DSPs.** F→head remains a registered
edge; no cache/tag→decode/issue path is added. Packing and routed timing at the
**104MHz design target /78MHz physical PLL** are unmeasured.

An RTL proposal must give existing reset/older CPU/ALU/decode corrections priority
over capture, retain the F owner while held, suppress duplicate array writes,
and invalidate the head under the original frontend context/maintenance rules.
The tuple transports freshly permitted code in its original ARM/Thumb and
translation context; it is not a PC-keyed instruction cache. A live abort rides
the existing abort sideband exactly once, using F's existing sleep behavior and
the consumed bit; killed speculative aborts disappear on clear. No new request,
device read or architectural effect is authorized by capture. These are design
requirements, **not newly qualified fault/maintenance results**.

The evidence supports separating valid-word consumption from subsequent-demand
readiness. Reaching a larger gain would require a deeper registered frontend
or a context-owned corrected-target response mechanism, with a separate
schedule and cancellation proof. No second mechanism is modeled or implemented.
End Step5H with production5F retained.

## Receipts and replay

[Machine-readable dynamic schedules, first blockers, model and hashes](evidence/cpu-useful-target-20261117.json).
[Compressed complete occurrence journal](evidence/cpu-useful-target-20261117.events.json.gz).
Maintained passive observers and analyzer: `tests/cpu/cpu_useful_target/`.
New runs: `build/sim/spmark-payload/useful-target-5f-arm-02/` and
`build/sim/jpeg-payload/useful-target-5f-jpeg-01/`. The excluded `arm-01` run
reproduced matrix but its legacy5E late-store observer rejected5F's byte path;
the maintained5F observer fixed that fixture, with unchanged CPU RTL.

```sh
python3 tests/cpu/cpu_useful_target/bench.py --name NEW_ARM \
  --case matrix4 --case fill8_tail --profile 0:0 --jobs 1
python3 tests/cpu/cpu_useful_target/jpeg.py --name NEW_JPEG
python3 tests/cpu/cpu_useful_target/analyze.py
```

Builds/runs are serial, installed `jotego/simulator:arm64`, pulls/network disabled.
Completed build trees, frozen sources and generated binary/hex inputs are
retired after qualification; losslessly compressed logs, executable hashes,
source/observer manifests, original guest assembly and results remain.
No other chat's run, fit, generated output or working change was removed.
