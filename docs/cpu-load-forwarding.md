# CPU load-result availability and forwarding

Patch0062 implements a declared joint phase08 change: early aligned-word P2
load forwarding and late formatted Memory-commit availability, including correct
paired base/load producer priority. It is a CPU instruction scheduling change;
the cache/MMU/bus RTL is unchanged.

The complete original-payload suite improves **1.3900% / 1.3899%** over C at
waits0:0/2:9. Original-baseline indices are **151.2480 / 141.5576**, previously
149.1744/139.6171. Transpose improves **6.37%**, triangle **1.84%**, matrix
**0.11%**. These are simulated fixed-work kernels, not official SPMark scores
or whole-phone speed. Fit, routed timing and hardware boot remain unverified.

## Availability contract

A completed aligned word already resides in the existing CPU completion
register. When its actual P2 owner is valid, fault-free, full-width, aligned and
non-SWP, issue can use that register while Memory captures the same word. The
normal younger-writer priority still applies. The load result wins its own
paired ALU/base write; all earlier unresolved load stages remain locked. The
consumer can issue two edges earlier than waiting through P2 and Memory.

Byte/halfword, signed, unaligned, SWP and fault/retry paths retain their existing
formatting/ownership boundary. Once a valid Memory load is actually writing the
effective B port, its correctly formatted value is already available through
current-write forwarding. That load need not lock issue for another edge.
Missing/redirected B commits keep the lock. Current C/B/A priority is preserved,
including load-versus-base aliasing. Clear, global holds and background locks
retain their existing priority and operand-journal refresh rules.

No ACK-to-issue path is introduced: early data comes from the completion
register, and late data from registered Memory/writeback. No extra state bits,
RAM, completion slot, port or pipeline edge is added. The forwarding reduction
has one additional source and narrow availability/selection logic. Actual ALMs
and routed timing still need the build; a register-to-issue path is not itself
proof of104MHz closure. The PLL remains78MHz, with104MHz the design objective.

This allows an in-order dependent instruction to overlap its producer's later
stages. It does not create dual issue, multiple outstanding cache requests or
speculative MMIO accesses. Only the explicit supported class bypasses the two
late dependency holds; there is no raw cache-data formatter bypass for other
widths.

## Measurements and verification

All six payloads/both profiles pass12groups and84windows per repeat, two exact
repetitions, original output/helper/retirement checks and six wrong-output
controls. Final run421.588s. Medians: matrix60784, transpose7060, triangle36686,
frame135314/201317, fill16tail4324, fill8tail5048.
[Full table](spmark-payload-results.md).

The final source passes98CPU regression runs plus44IRQ/FIQ edge sweeps, five
related unit suites and four deliberately broken controls. The independent
operand oracle checks80,580clocks,40physical registers and all four operand
ports, including2,880early and2,720commit-edge issues. It covers younger writers,
all producer-valid combinations, no/misdirected commits, paired destinations,
immediates/special registers, and a completion disappearing during a hold while
the queue refreshes from the real commit.

The new CPU program checks load→ALU, shift source/count, store data, address,
multiple loads to one register, failed conditional writers/loads, signed/narrow
loads and unaligned rotation. Test-only monitoring verifies the early word and
physical destination against the next registered Memory formatter output, and
rejects unowned, faulted, narrow/unaligned or SWP early offers. Both wait settings
exercise early and late issue. Existing abort/permission/retry, FIQ banks,
Thumb/block transfer, SWP and page-walk ordering tests also pass with monitoring.

Four controls reject the predecessor, releasing without the actual B commit,
a P2 base write overriding its own load, and a Memory base write overriding its
own load. The proof uses an independent oldest-to-youngest producer oracle,
rather than the DUT's lock decision.

Qualified post-change profiles cover matrix/transpose/triangle at both profiles,
with two exact repetitions and every accepted original counter unchanged. Load
lock clocks per scored window fall matrix196→131, transpose1540→1091 and
triangle2676→1907. Transpose data holds remain3368clocks while its window shrinks:
44.85%→47.71% is a denominator change, not slower memory. This is a focused
profile, not a six-case post-change stall profile. Remaining matrix/triangle
empty queues33.88%/31.75% still require causal attribution.

The late-only exploratory run passed its guest cases but its comparison was
rejected because the selected group membership differed from the full baseline.
It is not an accepted performance row. The next probe used an explicitly
selected subset of existing qualified C rows; the accepted result above reruns
the complete final-source suite. Formatting of the extended operand fixture is
lexically equivalent and recorded; production imported-source styles are kept.

## Build checkpoint and next parallelism step

**Build this measured commit next.** Check fit,78MHz closure,104MHz path margins,
stock boot and actual phone/game behavior before adding another pipeline change.
The new readiness path and forwarding selector are specific timing endpoints
to inspect alongside the prior mapping/selected-way changes.

After that gate, prioritize F1: overlap independent RAM requests using the
existing ports. `cache_lines` already maps A to byte-enabled writes and B to
synchronous reads. Packed tag/dirty RAM also has separate commit/read ports.
The single-owner controller and CPU hold serialize their use; port availability
alone does not provide another accepted request.

Start by separating owned data-read addressing from dirty/commit addressing,
allowing a next-stage probe/read while an older independent write commits.
Give each stage a valid owner and registered capacity. Same-slot/word collisions
must interlock or forward byte masks and fresh dirty halves; do not depend on
unspecified mixed-port read-during-write values. Revoke probes on mapping/cache
mutations and retain precise permission/fault/destination capture at P2. Prove
independent initiation interval separately from dependent load latency before
relaxing the global completion hold.

**Modest additional BRAM is allowed** if buffers, banking or replication buy
useful ports/bandwidth or replace ALM storage. The previous changes adding no
RAM were measured implementation choices, not a prohibition. Prefer exploiting
the existing dual ports before increasing capacity without measured need. Do
not resurrect wide ALM dirty mirrors. More general phase08 producer availability,
phase03 RAS correctness, arithmetic scheduling and frontend attribution remain
on the older CPU plan; this patch does not close those larger phases.

## Reproduction and provenance

```sh
CPU_PROGRAM=load_forward CPU_LOAD_FORWARD_CHECK=1 \
  CPU_RUN_ARGS=+load_forward_check sh tests/cpu/core/sim.sh
python3 tests/cpu/spmark_payload/run.py --name UNIQUE \
  --baseline build/sim/spmark-payload/two-mapping-final-20261115/result.json
```

These normal commands use their standard output directories. This investigation
used isolated outputs instead: `build/sim/load-forward-cpu-20261115/`,
`build/sim/load-forward-units-20261115/`,
`build/sim/load-forward-controls-20261115/`,
`build/sim/spmark-payload/load-forward-20261115/` and
`build/sim/spmark-profile/load-forward-after-20261115/`.
Scripts, qualified subset derivation and patch reconstruction remain under
`scratch/load-commit-issue-20261115/`.

The new ordered upstream-relative patch is registered in `UPSTREAM.json`.
All83pristine upstream hashes and37SV/SVH reconstructed lexical streams pass.
A fresh pinned archive was fetched through gh into this experiment because the
shared cached reference failed its pristine hashes; that cache was untouched.
The new patch applies to reconstructed0061; strict byte equality still has
preexisting formatting/comment drift. No claim that the stock verify.sh passed.

[Qualification](evidence/cpu-load-forwarding-20261115.json),
[benchmark](evidence/spmark-payload-load-forward-20261115.json),
[profile](evidence/spmark-payload-load-forward-profile-20261115.json).
All work remains on the original integration branch/checkout; other simulations
and permanent checkpoints are untouched. No card, firmware or PLL changes.
