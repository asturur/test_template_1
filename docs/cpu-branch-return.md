# Owned branch feedback and return prediction

Patches0065/0066 implement the two requested CPU steps. The complete original
SPMark payload suite passes after each step. Combined throughput improves
**21.0121% /16.1110%** over771be07 at synthetic I:D waits0:0/2:9. Original
baseline indices advance **154.4752/144.5781→186.9337/167.8711**. These are
offline kernel indices; the last measured native MiSTer score remains119 on
a745119. Physical fit, routed timing and native performance require a new build.

## Step1: instruction-owned feedback

The old BTB assigns a validity bit every clock, even when its source address
belongs to a bubble or held ALU output.0065 adds one registered decoded-owner
bit alongside the ALU metadata. A valid condition code establishes ownership
even when the condition fails; IRQ/FIQ/prefetch-abort tags do not. Reset,
writeback clear, older data fault/sleep and ALU flush revoke it under the same
priorities as the existing ALU outputs. Data hold retains the registered owner.

Feedback is accepted only when that owner advances, without writeback clear or
an older data fault. BTB read/fetch hold is independent: valid ALU feedback can
still train while fetch is held. Unowned cycles neither erase a valid bit nor
write predictor RAM. A real nonbranch still invalidates its aliased entry;
failed conditional branches still update prediction state. BTB reset/clear
remains dominant. No cache geometry, predictor capacity or CPU issue contract
changes. Added declared state: **one bit**, no added RAM or pipeline stage.

This step alone improves the full-suite geometric index by11.9640%/7.8126%,
to172.9566/155.8735. Matrix initially regresses60094→63972clocks; several other
kernels improve enough to give the overall gain. This is measured explicitly,
not an assertion that every workload benefits.

## Step2: correct returns and retain confirmed targets

The raw ARM return matcher used Rm15, recognizing `MOV pc,pc` instead of
`MOV pc,lr`.0066 selects Rm14; BX/LDM/stack-load recognition and the existing
circular RAS remain unchanged. Matcher-only payload counters equal step1,
but the32-call microbenchmark initially regresses1092→1185clocks.

A bounded scored-window trace shows the RAS supplies the correct caller
address and ALU confirms it, yet later BTB predictions contain target zero.
The ALU's PC output was a don't-care when no redirect was required; the BTB
also uses that output to train a confirmed branch. Thus success wrote an
undefined target.0066 supplies the existing registered computed target in that
case. Actual redirect cases, including failed-condition fallthrough and mode
resynchronization, retain their prior selection. PC redirection remains gated
by its original clear signal. No new target register, arithmetic or RAM is added.

The combined second step gains8.0813%/7.6970% over step1. Both wait profiles
repeat the following warmed microbenchmarks exactly:

| Variant | 64-iteration direct branch | 32 calls/returns |
| --- | ---: | ---: |
|771be07 predecessor |1392 |1133 |
|Owned feedback only |1271 |1092 |
|Matcher only, without target repair |1271 |1185 |
|Target repair with old matcher, explicit control |412 |812 |
|Final matcher + target repair |**412** |**740** |

These include loop/frontend overhead and are not pure branch latency or native
SPMark points. The old-matcher control proves that fixing recognition is useful
after target repair. Full speculative RAS checkpoint/rollback is still later
phase10b work; circular overflow/underflow preservation is not a new recovery
implementation. Exception-return MOVS remains excluded from this matcher.

## Verification and continuity

Final qualification passes66CPU runs,44IRQ/FIQ edge sweeps, three focused units
and three broken controls. The units cover bubble/stale-strobe retention,
aliases, failed conditions, independent fetch hold, clear/reset priority,
confirmed targets, ALU holds/faults/exception tags, nested returns, circular
overflow/underflow, Thumb, MOV pc,pc and squashed/held calls. A directed guest
checks nested ARM/Thumb calls, recursion beyond RAS capacity and false-positive
return classification. Temporal assertions check decoded ownership, accepted
BTB mutations and the confirmed target on every CPU clock.

Both accepted full payload runs pass12groups/84windows per repeat, two exact
repeats and six wrong-output controls. Every compiled final source hash still
matches the working tree. All20matched branch/call groups repeat every raw
window and total exactly. All83pristine upstream hashes and37ZAP token streams
reconstruct through0066; preexisting formatting/comment drift remains.

Focused tests: `sh tests/cpu/branch_feedback/run.sh OUTPUT`,
`sh tests/cpu/branch_feedback/alu.sh OUTPUT`, and
`sh tests/cpu/return_predict/run.sh OUTPUT`, with distinct build directories.
CPU_BRANCH_OWNER_CHECK=1 enables the temporal observer in the core runner.
Recorded qualification used isolated branch-owned/branch-return-target/hook
directories; other threads' simulations/checkpoints remain untouched. Fixture
path/instance-name mistakes are preserved separately in evidence and corrected;
they are not reported as RTL failures.

[Qualification](evidence/cpu-branch-return-20261115.json),
[step1 payload](evidence/spmark-payload-branch-owned-20261115.json),
[final payload](evidence/spmark-payload-branch-return-20261115.json),
[microbenchmarks](evidence/branch-return-microbench-20261115.json).
Scripts/raw traces remain in scratch/branch-return-20261115. PLL stays78MHz,
104MHz remains the timing target. Reprofile this final CPU before choosing F2
credits/ordered completion versus further frontend/arithmetic work; old F1
empty-queue percentages are not measurements of this revision.
