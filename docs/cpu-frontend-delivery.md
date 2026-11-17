# Registered target delivery — Step 5A, 17 November 2026

Subsequent [hardware build and source promotion](cpu-frontend-delivery-fit.md):
verified78MHz RBF collected; timing remains red. Owner authorized mainline
consolidation of these exact payloads without deployment.

**Retain corrected isolated5A source1ddc7653.** The same original matrix work
improves **52,125→50,033 cycles (−2,092,−4.0134%)** against retained4G.
Transpose improves **3,625→3,591 (−34,−0.9379%)**; the existing original Thumb
JPEG block improves **86,428→84,353 (−2,075,−2.4008%)**. The drained64-store
reference remains **71**. Both synthetic I:D delay profiles0:0 and2:9 agree.
There is **zero new state**, one changed writeback file and no predictor change.

| Identical work, median cycles | Exact4G | First attempt | Corrected5A |
| --- | ---: | ---: | ---: |
| Original matrix ×16 | 52,125 | 52,285 | **50,033** |
| Original transpose ×32 | 3,625 | 3,591 | **3,591** |
| Original Thumb JPEG, diffuse_m10_8x8_jpeg | 86,428 | 86,076 | **84,353** |
| Drained64-store stream | 71 | 71 | **71** |

Every scored sample/two complete repeats, original bytes/math and Unicorn
outputs, callee registers/SP, retirement counts and negative-output controls
pass. Matrix retains14,176 payload/14,353 ordinary retirement events;
transpose retains800/1,025. Their warm external scalar/line traffic is zero. JPEG
uses the established native firmware block and unchanged mathematical/Unicorn
oracle and guard checks, not a replacement routine or full application score.
JPEG scored cycles are86473/86428/86428/86428/86428→84399/84353/84353/84353/84353
at0:0, and86491/86428/86428/86428/86428→84417/84353/84353/84353/84353 at2:9.
The first scored window retains one line/eight reads in each design; later four
have zero external traffic. All windows retain22,508 ordinary retirement events
for22,500 original native instructions plus wrapper work. Report the median,
not an identical count for every JPEG sample.

No game payload, fit, production integration, deployment or phone work was done.

[Audited identities, all1,024 dynamic BL/BX pairs, both-profile schedules and qualification](evidence/cpu-frontend-delivery-20261117.json).

## Existing frontend schedule and the actual opportunity

The control is exact retained4G source7b9a7dd2. A read-only full matrix trace
reproduces52,125 cycles, including all14,353 ordinary retirement events. Each
of the1,024 repeated original SMULL-helper calls is aligned with its original
BL source PC/occurrence, helper entry100011c4, BX LR100011e4 and correct caller
PC=BL+4. Both profiles' complete warm schedules agree up to an absolute time
offset. Correct architectural retirement order is matched independently.

The existing BTB already predicts633 of1,024 direct calls correctly. Predecode
computes the correct immediate target for the remaining391. The shared helper's
BTB return target reflects another call site; its existing RAS supplies the
correct caller target at predecode for all1,024 returns. There are1,431 decode
correction events:391 helper calls,1,024 returns and16 other branches. **A new
predictor is not needed to discover these already-known predecode targets.**

The old path records the redirect target in the PC source, then moves it into
the first of three fetch stages. Existing4E accelerated a previously shelved
target when a held wrong-path fetch drained. It did not accelerate the first
registered CPU redirect when that fetch was already complete. At1,030 correction
edges the frontend is ready;401 have a held fetch or another frontend stop.
Neither1,431 nor the earlier433 pending-owner handoffs is a savings forecast.

The representative second call in the first measured matrix is:
`10002194: BL100011c4`, then the original helper ending
`100011e4: BX LR`, returning to10002198. Everything here is ARM state. The
incoming BTB prediction for the BL is absent/SNT; the return prediction is
10002188/ST, while the RAS correctly resolves10002198. ALU still validates the
actual result; BL's two existing uops and link-write semantics are unchanged.

| Second call / return event | 4G absolute | Corrected5A absolute |
| --- | ---: | ---: |
| BL target known/accepted at predecode | 239649 | 233990 |
| Registered BL correction | 239650 | 233991 |
| Correct helper target requested | 239654 | 233994 |
| Correct helper fetch enters F | 239663 | 233998 |
| Helper instruction usable in decode | 239668 | 234003 |
| Helper operand head / first actual issue | 239669 | 234004 |
| BX target known at predecode | 239682 | 234017 |
| Registered return correction | 239683 | 234018 |
| Correct caller target requested | 239688 | 234022 |
| Correct caller fetch enters F | 239689 | 234023 |
| Caller instruction usable in decode | 239694 | 234028 |
| Caller operand head / first actual issue | 239695 | 234029 |

Compare relative gaps, since earlier work also changes. For that call,
registered correction→request is **4→3**, correction→F **13→7**,
correction→decode **18→12**, and correction→actual issue **19→13**. Public
request→issue is **15→10**. For its return, correction→request **5→4**,
correction→F **6→5**, correction→decode **11→10**, and correction→issue
**12→11**; request→issue remains7. These are witnesses, not every-call constants.

The first call overlaps substantially more older load work: its correction→
issue is23→22 despite fetch delivery13→8. The first return actually worsens
15→21 because its newly timed wrong-path demand is still held at correction.
All occurrences, including worse intervals, remain in the evidence. Earlier
fetch delivery does not authorize advancing a held backend packet or a load-use.

## Count actual empty clocks, separate backend holds

For each call and return, mark the interval from accepted known predecode target
to first real issue of that target. The2,048 intervals do **not overlap**, so
clocks are counted once. Apply exclusive priority: data hold, shifter busy,
load lock, shift lock, operand empty, other/advance.

| Control clocks in those intervals | Call delivery | Return delivery |
| --- | ---: | ---: |
| Data read hold | 4,591 | 0 |
| Data write hold | 1,872 | 0 |
| Shift lock | 0 | 2,048 |
| Operand empty | **5,919** | **9,234** |
| Other/advance | 3,902 | 4,096 |
| Total | 16,284 | 15,378 |

Thus15,153 of17,995 control operand-empty clocks lie in call/return delivery
intervals;2,842 lie outside. All6,144 multiplier/shifter busy clocks are outside
these intervals. These are observed ownership/occupancy classifications,
**not15,153 removable clocks**. Some target delivery overlaps unavoidable data
holds, pipeline transit or an already-correct predicted path.

In the corrected run, interval-empty counts become5,440/9,074; outside empty
becomes1,357. Accepted target information also arrives earlier relative to older
memory work: data holds inside the call intervals rise while outside holds fall.
Consequently the sum of known-target→issue interval lengths can increase even
as the fixed workload gets faster. That sum is not elapsed performance.
The complete disjoint matrix profile is the final accounting:

| Priority occupancy | 4G | Corrected5A | Change |
| --- | ---: | ---: | ---: |
| Read stall | 5,503 | 5,567 | +64 |
| Write stall | 2,550 | 2,550 | 0 |
| Load lock | 146 | 114 | −32 |
| Other lock | 3,088 | 3,088 | 0 |
| Empty operand queue | 17,995 | 15,871 | **−2,124** |
| Other/advance, including multiplier busy | 22,843 | 22,843 | 0 |
| **Total** | **52,125** | **50,033** | **−2,092** |

The read/empty/lock redistribution reconciles exactly:2,124+32−64=2,092.
No external service reduction, multiply change or retirement-count reduction is
credited to the frontend. All6,144 multiplier busy clocks remain.

## One mechanism, and the measured failed first attempt

The isolated overlay changes only `zap_writeback.sv`:

1. Registered CPU ALU/predecode redirect targets enter the first PC stage
   directly when the existing code-ready condition says the old fetch is done.
   A held fetch retains its full packet and saves the target through the existing
   pending owner. Older writeback events retain priority.
2. The now-inactive second/third PC stages retain the canonical **target address**
   with valid bits clear. That lets existing resident-only I-cache lookahead
   prepare the target during fetch-pipeline transit. It launches no fetch,
   page walk, refill, architectural completion or external effect by itself.

The first attempt made only change1 and kept the old task's zero payload in
inactive stages. It was functionally correct but **matrix regressed160 clocks**:
empty+144 and read+16. A separate read-only I-cache trace reproduced that result
and exposed the exact failure. On the first return:

- Control correction239633 leaves inactive addresses useful to lookahead. The
  target appears while RD=0 at239637; target+16 lookup starts239638. At239641,
  translation and the private resident token are ready together: fast ACK.
- First attempt correction239534 produces inactive address0 for three clocks;
  private lookahead follows00000010. Target request239538 arrives before the
  target token. At239541 translation is ready but the token is not, so an owned
  demand is accepted and cancels the arriving speculative token. ACK waits
  until239546. Request was earlier, but correct-target delivery became later.
- The correction retains the target in invalid PC payloads instead of zero.
  The final I-cache attribution run reproduces50,033 with the same full work.
  No cache RTL, predictor, queue, cache capacity or lookup depth was changed.

This is one registered-target handoff experiment corrected to preserve its
private preparation information. The rejected and corrected frozen sources,
original workload results and diagnostic traces are retained separately.

Fixed4G source:
`7b9a7dd28baccdfedfe75baaac91358c7751ed56d977fe348101738946e40244`.
Rejected first attempt:
`1b4eadbd9d100b51330b5fc2a87d5d6750b810325973bb74e5dd733075434470`.
Corrected5A:
`1ddc7653903458d33e765e26bad69e1c8d817b2cab0920320b48d251ab2cb643`.

## Qualification and104MHz implications

All23 focused real-writeback cases pass twice: first-ready ALU/decode target,
held old/new fetches, ended/repeated redirects, changed targets, ARM/Thumb
canonical addresses and successors, FCSE/PID boundary carry, reset, pending IRQ,
and DABT/FIQ/IRQ/PABT/SWI/UND/load-PC priority. Changed targets use the actual
current target; older events cannot take the new CPU handoff route.

Eight real-CPU diagnostics pass on the exact corrected source: ARM/Thumb/link
smoke, FCSE, discarded plus actual prefetch faults, and trained return-alias guard,
each at latency0/3. Actual bus faults are exercised and the guard stops only at
its expected0x0bad0000. Matrix/transpose retirement PC order matches controls;
JPEG retains original Thumb code, ROM, outputs, state return, guards and saved
register checks. The standard store fixture retains71 cycles at both profiles,
448 ordered accepts/actual mutations/completions/retirements,16 independent dirty
backing words and63 one-clock warm gaps. Its actual older IRQ/abort boundaries,
held offers, following load and byte transition pass. Wrong expected physical
bytes still fail at the first actual write.

Added state is **zero bits**. Existing source/stage/pending registers are reused;
no predictor/RAS/tag payload or queue is added. Likely104MHz risks are the
registered target→FCSE/canonicalization→PC-stage data selection and target fanout
into the two previously invalidated payload fields, plus the existing selected
successor increment. The I-cache pipeline remains registered and actual demand
permission checks remain in place. This expands use of an existing code-ready
boundary; it does not bypass a held fetch or change the global data-stall tree.
ALMs, duplication and routed9.615ns timing are unmeasured. Physical PLL stays78MHz.

## Decision and one next mainline action

Keep the qualified5A overlay for the next offline CPU experiment, with passing4G
intact as control. No fit or production adoption is implied.

The next mainline action is **one bounded SMULL start/result handoff experiment
on original matrix**, using this exact5A as fixed control and retaining JPEG
non-regression. The same1,024 original helper invocations still incur6,144 busy
clocks and3,088 shift-lock clocks; neither bucket improves here. Trace one full
SMULL owner and dependent result before changing its existing full-product
pipeline/control. Those observations justify investigating a concrete recurrence,
not deleting6,144 clocks on paper or adding a general queue. No further RTL
change is implemented in5A.

## Replay and preserved artifacts

```sh
python3 tests/cpu/cpu_frontend_delivery/bench.py --control --name UNIQUE_CONTROL \
  --case matrix4 --case transpose4
python3 tests/cpu/cpu_frontend_delivery/bench.py --name UNIQUE_CANDIDATE \
  --case matrix4 --case transpose4 \
  --baseline build/sim/spmark-payload/UNIQUE_CONTROL/result.json
python3 tests/cpu/cpu_frontend_delivery/jpeg.py --control --name UNIQUE_JPEG_CONTROL
python3 tests/cpu/cpu_frontend_delivery/jpeg.py --name UNIQUE_JPEG_CANDIDATE
python3 tests/cpu/cpu_frontend_delivery/cache_bench.py --name UNIQUE_CACHE_TRACE \
  --case matrix4 --profile 0:0
python3 tests/cpu/cpu_frontend_delivery/redirect.py UNIQUE_REDIRECT
python3 tests/cpu/cpu_frontend_delivery/run.py UNIQUE_STREAM \
  --arg +i_wait=2 --arg +d_wait=9
python3 tests/cpu/cpu_frontend_delivery/run.py UNIQUE_ZERO \
  --reuse build/sim/cpu-frontend-delivery/UNIQUE_STREAM
python3 tests/cpu/cpu_frontend_delivery/diagnostics.py UNIQUE_DIAGNOSTICS \
  --build build/sim/spmark-payload/UNIQUE_CANDIDATE
python3 tests/cpu/cpu_store_overlap/negative.py build/sim/cpu-frontend-delivery/UNIQUE_STREAM
```

The JPEG wrapper selects only the existing first8×8 JPEG case and its permanent
workload definition; it uses the established runner/fixture and original oracle.
No scratch-only helper is required. Simulator is installed
`jotego/simulator:arm64`, no pull/network. All run names refuse overwrite.

Primary runs: `build/sim/spmark-payload/frontend-{control-01,candidate-01,candidate-02}/`.
Read-only cache attribution: `frontend-cache-{control-01,candidate-01,candidate-02}/`
under the same parent. JPEG: `build/sim/jpeg-payload/frontend-jpeg-{control-01,candidate-01,candidate-02}/`.
Qualification: `build/sim/cpu-frontend-delivery/{redirect-candidate-02,diagnostics-candidate-02,stream-candidate-02,stream-candidate-02-zero}/`.
Full frontend traces are compressed losslessly; the audit helper reads either
plain or compressed logs. Profile2:9 schedules are stored as verified time-offset
copies of0:0 schedules to avoid duplicate evidence. Every dynamic call/return
and full retirement sequence is audited before durable summaries are written.

Original integration branch/checkout/HEAD/index, production/project/workflows,
physical78MHz PLL, phone, other simulations and permanent checkpoints remain
untouched. Solo/offline. No CI, fit or deployment. Stop after5A.
