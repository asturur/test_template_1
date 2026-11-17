# CPU redirect handoff and recovered issue cycles — Step 4E, 16 November 2026

**Retain the corrected isolated candidate.** Against fixed final 4D, original
transpose improves **4,613 → 4,550 cycles (−63, −1.3657%)** and original matrix
improves **52,714 → 52,125 (−589, −1.1174%)**. Both synthetic memory profiles,
all five scored windows and two complete repeats agree exactly. The unchanged
64-store stream remains **71 cycles**. One CPU writeback source file changes;
there is no new cache fast path or queue, and no new state bit.

| Original guest work | Final 4D | Corrected 4E | Saved cycles |
| --- | ---: | ---: | ---: |
| Transpose, I:D 0:0 | 4,613 | **4,550** | 63 |
| Transpose, I:D 2:9 | 4,613 | **4,550** | 63 |
| Matrix, I:D 0:0 | 52,714 | **52,125** | 589 |
| Matrix, I:D 2:9 | 52,714 | **52,125** | 589 |
| Drained 64-store stream | 71 | **71** | 0 |

The original payload/input hashes, mathematical and Unicorn output oracles,
800 transpose / 14,176 matrix payload instructions, normal helper execution,
1,025 / 14,353 ordinary retirement observations per window, two warm-ups and
wrong-output rejection are unchanged. Every scored window has zero external
scalar reads/writes or line transfers. These are checked offline CPU/cache
cycles, not a whole-phone score or physical timing qualification.

[Audited evidence, exact owners and edge records](evidence/cpu-issue-recovery-20261116.json).

## Why 65 saved load-wait clocks became 31 saved total clocks

The 4C and 4D full stage traces were aligned by **architectural PC and
occurrence**, not absolute timestamps. Their 1,025 ordinary retirement PCs match
in order. All **65 changed load owners** match by PC, occurrence and address:
32 at 10002648, 32 at 10002698, one at 10002658.

At each earlier registered completion, the next STR is **already held in the
operand queue**. Its address base R0 and immediate offset are independent; its
store data depends on the newly loaded R3. It issues **on that very completion
edge in both designs**: head valid=1, load lock=0, pop=1. No extra issue enable
clock follows these completions, and there is no missing queue packet to
recover immediately at any of the 65 returns. Before completion the load lock
is a real store-data dependency, not a queue-empty condition.

The **34 additional empty clocks occur later**, after `100026a4: BX LR`, before
the caller's 000000cc instruction retires. Thirty return intervals add one empty
clock, one adds four, and one adds none. That exactly explains +34 empty clocks;
all other architectural intervals have equal empty counts. The earlier load
service changes where return redirection meets an already owned wrong-path
instruction fetch. Fetch drains that old request, then the saved redirect
restarts the PC pipeline. Decode and register acquisition have no usable target
instruction until fetch supplies one. There are no warm external refills.

This distinguishes the relevant classes:

| Observed class in final 4D transpose | Count | Interpretation |
| --- | ---: | --- |
| Changed load completes; dependent STR already usable | **65** | Immediate useful issue, no extra enable bubble |
| Empty operand queue with valid decoded input during data stall | **0** | Early acquisition of a held decode packet would not address this loss |
| Empty operand queue with valid decoded input, no data stall | **97** | Every one pushes normally that edge; ordinary registered R acquisition |
| Later return intervals with additional empty clocks vs 4C | **31** | 30×1 + 1×4 = 34 clocks, fetch/redirect restart |
| Non-data-stalled store-data load-lock clocks | **768** | 192 first STRs × four true dependency clocks |
| Other load-lock clocks | 95 | Caller BX using its loaded target |

Raw empty-stage occupancy is not treated as recoverable work. Of 4D's 1,670
empty clocks, 97 have decoded input, 97 have only predecode as the first raw valid
stage, 128 mode decode, 128 FIFO, 350 fetch and 870 none. A raw valid stage on a
clear edge can be wrong-path and unusable. The return-aligned causal trace,
normal push checks and real dependency controls determine the interpretation;
these occupancies do not constitute a savings budget.

## One bounded CPU scheduling change

Only `tests/cpu/cpu_issue_recovery/rtl/arm/zap_writeback.sv` differs from fixed
4D. The existing `pc_shelve_ff` and `shelve_ff` already retain a redirect target
while the current fetch drains. Previously, the release edge loaded that target
back into the PC source register; it entered the first PC pipeline stage a clock
later. The new handoff places the **already registered target directly into the
first PC stage on release**, clears later valid stages, and places its successor
in the source register. No instruction is completed, issued or architecturally
written merely by this transfer.

The same transfer handles a repeated, identical ALU/decode redirect when the
old fetch finishes on that edge. A changed target uses the existing redirect
path. All higher-priority data/prefetch abort, interrupt, SWI/UND and load-PC
choices retain their original priority. An outstanding fetch packet remains
unchanged while stalled. FCSE mapping, bit-zero masking and ARM/Thumb increments
are retained, including the corrected mapped-address carry described below.

No cache, TLB, certificate, data/probe, issue/operand queue, multiplier/DSP,
NOS/BT or production interface changes. The 31 uncertified second lines were
not pursued. No new payload, state bit or live cache-ACK bypass is added.

Fixed final 4D source ID:
`76d176e29ae091962ebe66efe2cf0060f0d551f844fce29c014a5fd64fe6b4bb`.
Corrected 4E source ID:
`9c2f022a85f3dad30026752e4537debca035b26a832821bcef950caf6edfab1c`.
All other frozen RTL file hashes match exactly.

## Real CPU before/after edge

Use the second original function return, aligned by its PC occurrence. Control
release is edge **149952**; corrected candidate release **149850**. Both have
the same old fetch at 00000020 with ACK=1, saved target 000000cc, shelve=1,
no remaining ALU/decode strobe, and no fault or data stall. Absolute origins
differ because preceding work also becomes faster.

| Event relative to old-fetch drain / saved-target release | 4D | 4E |
| --- | ---: | ---: |
| Saved target enters first PC stage | 2 | **1** |
| Actual target fetch strobe, address 000000cc | 4 | **3** |
| Target instruction ACK | 9 | **8** |
| Target is valid in decoded input | 15 | **14** |
| Target issues from the real operand queue | 16 | **15** |

The target's own cache service remains five clocks. The earlier issue follows
from its earlier owned fetch, not from a changed RAM responder or an unowned
instruction bypass. Target and successors remain unique and in order; the
focused test stalls both the old and new fetch packets to verify this contract.

Per scored transpose window, the corrected design observes **64 pending-target
handoffs**: 31 to the next function entry, 31 to caller 000000cc, one speculative
zero target and one final caller exit 000000d8. Architectural retirement interval
alignment attributes the **63 saved clocks exactly** to 31 function-entry
intervals, 31 caller-return intervals and the final exit. The speculative handoff
is not counted as an architectural gain. Read stalls=737, write stalls=192,
load locks=863, other locks=64 and other/advance=1087 are identical; **empty
clocks fall 1670→1607**.

The matrix kernel exercises the same pending-owner handoff beyond transpose:
**433 handoffs** in the candidate scored window, compared with 467 opportunities
in 4D; phase and subsequent pending events change with earlier execution. Its
read stalls fall 5599→5503, empty clocks 18520→17995 and load locks rise 114→146;
write stalls=2550, other locks=3088 and other/advance=22843 are unchanged. These
reconcile to **−96 −525 +32 = −589 cycles**. Handoff counts are coverage, not an
assumption that each event translates into one net workload clock.

## Corrections and hazard qualification

The first conservative implementation handled only a redirect strobe that was
still repeated when the old fetch finished. It measured transpose **4612** and
matrix **52510**, with correct outputs, but missed the ordinary release after
that strobe ended. The detailed owner trace showed 31 such return releases.
Extending the **same registered handoff** to that existing pending-owner branch
produced 4550 / 52125. This was one mechanism refined from its causal trace,
not a parallel scheduling or cache-design sweep.

A focused FCSE edge then caught a real candidate error. For raw target
**01fffffc**, PID5 maps the first fetch to **0bfffffc**. Advancing the raw address
incorrectly produced next fetch **02000000**, while the fixed control's mapped-PC
sequence requires **0c000000**. The correction advances the **mapped, aligned
PC** before applying the existing PC logic. Observed failing and corrected traces:

```text
Before: raw=01fffffc mapped=0bfffffc next=02000000 expected_next=0c000000
After:  raw=01fffffc mapped=0bfffffc next=0c000000 expected_next=0c000000
```

Failure: `build/sim/cpu-issue-recovery/redirect-fcse-carry-trace/run-0.log`.
Correction: `build/sim/cpu-issue-recovery/redirect-corrected-final/run-0.log`.
Both source/log hashes are retained. All final performance and CPU tests were
rerun on the byte-identical corrected source; the 4550 / 52125 results persist.

Final qualification:

- **17 focused handoff cases, twice:** ended ALU/decode strobes, repeated owners,
  held old/new fetches, unique target and successors, changed target, ARM/Thumb,
  FCSE and its carry boundary, DABT/FIQ/IRQ/PABT/SWI/UND/load-PC priority, pending
  IRQ replacing a saved CPU target, and reset cancellation.
- **Eight existing real-CPU diagnostic runs:** ARM/Thumb smoke, FCSE, discarded
  wrong-path fetch fault plus actual prefetch-abort entry/return, and a trained
  BTB alias/cached-return guard, each at latency0 and3. The guard reaches only
  its expected 0x0bad0000 completion stop; prefetch tests exercise actual bus
  faults. These run in a fresh frozen CPU build and isolated output tree.
- Original transpose/matrix inputs, original output and retirement oracles,
  both profiles, two repeats and wrong-output controls all pass. Warm external
  traffic remains zero. The observer explicitly records a checker read that
  crosses a matrix end marker; it does not discard timed cycles, change the
  marker, or weaken any guest/oracle check. The earlier strict profiling-only
  boundary assertion was an observer failure, not accepted DUT evidence.
- **Store stream remains71:** 448 ordered instruction acceptances, actual RAM
  writes, completions and retirements; sixteen independently checked dirty
  backing words; all 63 warm accept/write gaps one clock; deliberately wrong
  physical byte rejected. The separate CPU stress guest also passes older
  unmapped load and IRQ at live store credits, forbidden younger load/store
  effects, same-Rd/address-dependent/same-address/LDM/writeback/failed-condition
  cases and dirty backing checks. Its larger prologue is not used for the
  unchanged stream's 71-cycle measurement.

## One next dependency

The next measured CPU issue dependency is **store-data pickup**. Each of the
192 first dependent STRs has an independent R0+immediate address but waits for
R3 data; they account for 768 of the unchanged 863 load-lock clocks outside
data stalls. The completed load already releases issue immediately, so another
completion-enable tweak would not help. A future late store-data mechanism
would need to let the address start earlier while keeping the exact older load
owner, ordering, fault and kill guarantees. Those 768 observations are not a
claim of 768 recoverable cycles. No such mechanism was added in this slice.

## Replay and outputs

```sh
python3 tests/cpu/cpu_issue_recovery/bench.py --control --name UNIQUE_CONTROL \
  --case transpose4 --case matrix4
python3 tests/cpu/cpu_issue_recovery/bench.py --name UNIQUE_CANDIDATE \
  --case transpose4 --case matrix4 \
  --baseline build/sim/spmark-payload/UNIQUE_CONTROL/result.json
python3 tests/cpu/cpu_issue_recovery/redirect.py UNIQUE_REDIRECT
python3 tests/cpu/cpu_issue_recovery/run.py UNIQUE_STORE
python3 tests/cpu/cpu_issue_recovery/run.py UNIQUE_SAFETY --stress --safety
python3 tests/cpu/cpu_issue_recovery/diagnostics.py UNIQUE_DIAGNOSTICS \
  --build build/sim/spmark-payload/UNIQUE_CANDIDATE
```

Final payload outputs:
`build/sim/spmark-payload/issue-recovery-{control-final,candidate-qualified}/`.
4C causal replay: `build/sim/spmark-payload/issue-recovery-trace-4c-01/`.
Focused outputs under `build/sim/cpu-issue-recovery/`:
`redirect-corrected-final/`, `store-corrected-final/`, `safety-corrected-final/`
and `diagnostics-corrected-final/`. Earlier partial and failing runs remain
separate. `tests/cpu/cpu_issue_recovery/analyze.py` audits exact source identities,
65 changed owners, PC/occurrence alignments, cycles, traces and correctness
before writing the compact evidence linked above.

Work stayed solo, offline, in the original integration checkout. Fixed 4D,
production RTL/project/workflow, branch/HEAD/index, 78 MHz PLL, phone, other
simulations and permanent checkpoints were preserved. No CI, fit or deployment.
Stop at this corrected measured CPU improvement.
