# CPU resident-store overlap — Step 4A, 16 November 2026

**A working measured intermediate speedup:** the same 64 ARM stores take
**197 → 102 clocks** from first issue through the final physical cache write
(−48.22%, **3.0781 → 1.5938 clocks/architectural store**, including fill/drain).
Original transpose takes **5,130 → 4,676 clocks** (−8.85%, 1.0971× throughput),
in both synthetic I:D wait profiles 0:0 and 2:9. Outputs, ordering, repeats and
negative controls pass. CPU acceptance is not yet one store every clock.

This user-directed offline experiment proceeds independently of Stop 3D.
There is no Quartus run, routed-timing claim, production adoption or phone work.

## Candidate and ownership

The comparison is exact production `9c948da8da413a882e0fe8e559c380ea0cadabf4`
plus the four hash-qualified Stop 3C cache files and **production BRAM**.
The new explicit overlay is `tests/cpu/cpu_store_overlap/rtl/`; the runner
freezes that base and then selects this overlay. Source IDs and every overlay
hash are in [the evidence](evidence/cpu-store-overlap-20261116.json).
The loop and original-workload runs have identical complete source manifests
within each variant. Their matched guest bytes, memory profiles, harnesses and
independent output oracles are checked.

Before, the adapter's single `launched` owner waits for the physical cache
response. CPU `data_stall` holds upstream issue until the registered completion
returns, then its existing completion-next path can offer P1. Warm architectural
stores consequently enter every **three** clocks here; this is the real CPU
Stop 3C baseline, distinct from the direct-cache fixture's one-clock capacity.

The prototype carries one classification bit with existing instruction owners,
including the operand queue and post-ALU stages. It identifies the **original**
ARM instruction before macro-op expansion: unconditional, immediate-offset,
pre-index word STR, no writeback, no PC base/data register. The selected original
address must be aligned. Fault/interrupt/redirect state and older memory/PC
effects suppress the credit. Thumb, predicated, narrow, writeback, register-offset
and macro stores retain the serialized route.

Only the existing cache's actual **certified resident ordinary write-back
pipe_accept**, after translation/permission/cache qualification, can allocate
a credit. No predicted hit or hint authorizes a store. The existing data/way/
mask owner captures the store; no second payload queue is introduced. A two-bit
registered count permits **at most two** such admitted stores awaiting physical
response. CPU completion still crosses its existing register; live ACK is not
added to the global advance tree. The next actual instruction can then advance
while its predecessor's physical write remains in flight.

The adapter counts the physical responses separately. They cannot acknowledge a
younger CPU request. A following load, fault or other ineligible operation waits
for the accepted stores to drain. Admission is irrevocable only for this
already-certified no-fault local mutation. Bank/tags/dirty forwarding and probe
scheduling are unchanged from Stop 3C; cache_access only exposes the admission
credit, and the adapter/CPU boundary consumes it.

## First overlapping pair

The first pair in the run is PC **0x18c / 0x190**:
`STR r1,[r10,#0]`, `STR r2,[r10,#4]`, VA **0x80001000 / 0x80001004**,
PA **0x0a001000 / 0x0a001004**, data **0x11111111 / 0x22222222**.
They are accepted at edges **95174 / 95175**; the first physical write is
edge **95176**. The younger instruction is accepted before that write.

Full first-pair trace in scored window 2, relative to each variant's first
actual operand-queue issue (absolute 95821 control / 95726 candidate):

| Event | 3C store A | 3C store B | Candidate A | Candidate B |
| --- | ---: | ---: | ---: | ---: |
| CPU issue | 0 | 1 | 0 | 1 |
| Adapter/cache acceptance | 5 | 8 | 5 | **6** |
| Registered CPU completion | 8 | 11 | 6 | 7 |
| Actual RAM write | 7 | 10 | 7 | 8 |
| Architectural WB retirement | 9 | 12 | 7 | 8 |

The physical-write checker compares the actual RAM index, word lane, byte mask
and data to an acceptance-ordered independent instruction oracle. Retirement and
registered completion must each name the same 448 distinct dynamic stores in
order, exactly once. Speculative operand pops are observed separately; each
accepted store is tied to its most recent actual issue edge. A wrong-path issue
is not counted as architectural progress.

## Matched measurements

Seven identical windows: two warm-ups, five scored. All five scored samples
match exactly, as do two complete repeats.

| Measurement | Stop 3C | Candidate |
| --- | ---: | ---: |
| 64 stores, first issue through final physical write, inclusive | 197 | 102 |
| Clocks per architectural store over that interval | 3.078125 | 1.593750 |
| First acceptance through final physical write, inclusive | 192 | 97 |
| Entire marked window including following load/byte checks | 218 | 123 |
| Distinct architectural stores / physical writes per window | 64 / 64 | 64 / 64 |
| Scored acceptance interval histogram | 3:63 | 1:32, 2:31 |
| Scored external reads/writes/line transfers | 0 / 0 / 0 | 0 / 0 / 0 |

The marked window is **43.58% shorter**, including its unchanged transition
and readback checks (73 ordinary retirements in both variants). Cold window 0
is 389 clocks in both: instruction line fills hide most of the store gain.
Do not report the warmed result as a cold-fetch gain. The complete run has the
same backing reads/writes and line beats in both variants.

Original transpose, 32 matrices per window, unchanged original instructions:

| I:D waits | 3C median | Candidate median | Delta | Cycle reduction |
| --- | ---: | ---: | ---: | ---: |
| 0:0 | 5,130 | 4,676 | −454 | 8.8499% |
| 2:9 | 5,130 | 4,676 | −454 | 8.8499% |

Each scored window has **384 stores**. All 384 use the certified resident path
and receive the admission credit; **192** acceptances overlap an older live
store, versus zero in 3C. Cold window 0 qualifies 352/384; the remaining stores
use the ordinary route. Actual payload/helper retirement records and independent
mathematical/Unicorn output oracles match; the intentionally wrong original
workload output is rejected. This is simulated fixed-work CPU performance,
not an SPMark score or a phone-speed measurement.

## Correctness and stopping point

- **Memory/order:** all 448 target stores in each run issue, accept, physically
  write, complete and retire with correct identity/order. All sixteen cleaned
  backing words are independently checked. Both lines' dirty halves write back
  correctly. The following byte store changes word 0 to **0x44441144**;
  all other final words match the independently generated register-value pattern.
- **Backpressure:** held CPU packets retain PC/address/data/mask/class until
  completion or a legitimate older kill. Candidate target stores exercise 209
  full-owner hold clocks across the run. No request or physical write duplicates.
- **Following access:** immediately after the store sequence, an ineligible
  STRB and same-address LDR observe the drained bytes; another load verifies the
  final word. These transitions cannot consume older stores' physical replies.
- **Older exceptions:** an actual unmapped load raises one data abort and a
  real IRQ raises one interrupt. Handlers skip the following eligible STR.
  The forbidden PCs never reach cache acceptance, and their target words remain
  unchanged before the measured sequence starts.
- **Negative control:** deliberately flipping the first expected physical byte
  fails at the first RAM mutation, rather than reaching PASS.
- **Reused paths:** the corrected lifecycle suite passes 35 event/stage cases,
  eight probe consumers and four transfer/replacement cases with exact repeat.
  The final actual-adapter probe suite, credits explicitly disabled, passes
  402 requests, 164 fast reads, eight A/B overlap clocks and 123 collisions,
  including permission/alignment/translation/SWP/uncached/reset controls.

The next measured dependency is the **two-credit return**, not the cache write
port: after two consecutive acceptances the registered count is full. It does
not reuse a same-edge returned credit, causing one bubble every pair. This
also pauses upstream issue. A bounded spare-credit/return experiment is the
next small performance step; no eight-entry completion structure is justified
by this result. It has not been implemented here. Broader exception/Thumb/native
and integrated physical qualification remain later milestones.

Fixture failures worth avoiding: VA 0x0a001000 was unmapped in this page-table
setup (the valid VA is 0x80001000); filling a second line revokes earlier
certificates, so both lines must be re-read after fills; speculative issue pops
cannot be asserted to equal architectural stores; IRQ deassertion must observe
the exception flag even when ordinary DAV is zero; cold instruction-fill gaps
must not be bounded by a warm-store interval assertion. These failures reproduced
on the control and were fixed in the fixture, without weakening acceptance,
mutation, retirement or memory oracles. Large superseded IRQ-driver logs are
compressed with original hashes; only superseded build objects were discarded.

## Replay and evidence

From the existing checkout, using the installed offline simulator image:

```sh
python3 tests/cpu/cpu_store_overlap/run.py NEW_CONTROL --control
python3 tests/cpu/cpu_store_overlap/run.py NEW_CANDIDATE
python3 tests/cpu/cpu_store_overlap/negative.py build/sim/cpu-store-overlap/NEW_CANDIDATE
python3 tests/cpu/cpu_store_overlap/bench.py --control --name NEW_TRANSPOSE_CONTROL --case transpose4
python3 tests/cpu/cpu_store_overlap/bench.py --name NEW_TRANSPOSE_CANDIDATE --case transpose4 \
  --baseline build/sim/spmark-payload/NEW_TRANSPOSE_CONTROL/result.json
```

Final loop outputs: `build/sim/cpu-store-overlap/{control-final-02,candidate-final-02}/`.
Final workload outputs: `build/sim/spmark-payload/store-overlap-{control-01,candidate-final}/`.
[Compact results, source hashes and edge samples](evidence/cpu-store-overlap-20261116.json).
The loop manifest pins program/harness/observer/executable/container hashes;
compiled source and harness copies are frozen under each final run.

Production RTL/project/workflow, integration branch/HEAD/index, physical 78 MHz
PLL, running simulations/checkpoints and phone remain untouched. The 104 MHz
design target and Stop 3D evidence are retained independently; no fit or
deployment was submitted for Step 4A. Stop at this measured intermediate.
