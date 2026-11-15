# Absent-line store shortcut — 2026-11-15

E0 is implemented on the original integration checkout after permission reuse B.
A single absent-line record removes repeated tag searches for ordinary cacheable,
bufferable stores to a line previously observed missing. Write misses still do
not allocate; permissions, byte enables and posted-write ordering are retained.
No firmware/image changes, new OSD or build option, extra RAM or PLL changes.

## Implementation and ownership

The directory holds valid + all 27 MVA line bits (28 state bits). Two request
flags capture ordinary-store eligibility and the selected absent-store class,
for 30 added declared data-cache bits total. `READ_ONLY` and the upstream
instruction request class disable the path for I-cache; physical pruning/ALM
cost is unmeasured. The adapter supplies an explicit ordinary-store class,
excluding both SWP phases. Standalone legacy clients explicitly withhold it.

A normal registered tag decision records an absent cacheable/bufferable store
line. An eligible later request with the same MVA line captures its own PA,
data, byte enables and absent class, then enters BUFFER_STORE directly rather
than LOOKUP_CAPTURE → LOOKUP_WAIT → LOOKUP. It completes through the existing
posted buffer reservation, STORE_COMMIT and owned CPU completion. Full queues
still hold the owner; bus errors retain/retry the queued packet as before.
The presence comparator never generates a combinational CPU ACK.

Only absence-valid depends on the late global 64-way hit reduction. The 27-bit
tag captures under the registered state/request owner, avoiding a global-hit
enable across its payload registers. A checked resident store conservatively
revokes/replaces the old absence instead of preserving an unrelated record.
This does not affect the measured all-miss stream coverage.

Reset, cache disable, refill/wait-for-fill, maintenance requests/scan operations,
invalidation and lockdown revoke the reusable fact. Revocation does **not**
change an already accepted request's class or drop its queued write. Reads,
uncached requests, write-through requests, SWP and unsupported classes use their
existing paths. A read of the absent line therefore performs the ordinary
ordered refill; subsequent stores update the resident cache and dirty metadata.
An absent owner cannot issue any cache mutation, even while delayed tag outputs
still correspond to a different address. Simulation assertions check this and
compare the settled tag result against the certificate before completion.

This is a cache-tag fact, not a physical mapping or permission token. Current
P2 translation, privilege, alignment and attributes still gate admission. A
changed mapping uses the current request's checked PA; the record stores no PA.
The CPU regression explicitly warms absence with privileged stores, attempts a
denied force-user store, checks FSR/FAR, reads the original data through refill,
and verifies a later resident update. It covers eight different lines at
memory delays 0/3.

## Measured result

All six original kernels pass both synthetic memory profiles, two exact repeats,
84 windows per repeat and six wrong-output controls. Only cache_access and
cache_adapter differ from accepted B's 128-file CPU closure.

| Full-frame fill | B cycles | E0 cycles | Throughput improvement |
| --- | ---: | ---: | ---: |
| I:D 0:0 | 183,380 | 135,329 | 35.51% |
| I:D 2:9 | 201,344 | 201,332 | 0.00596% |

Matrix, transpose, triangle and both small-fill medians are unchanged. The
six-kernel geometric index improves **5.1946% / 0.000993%** over B at 0:0/2:9.
The delayed full-frame stream is limited by backing-write service rather than
lookup latency; this shortcut does not make its backend faster. Neither result
is a whole-phone speedup, official SPMark score or physical SDRAM measurement.

The standalone real-cache test measures admission-to-response latency **5→2
clocks** for repeated absent stores. It checks 44 owned requests/39 exact ordered
posted packets, all byte masks/word lanes, independent physical address capture,
no write allocation, read/refill revocation, resident partial-store freshness,
both dirty halves through clean, MVA aliases, unsupported classes, cache toggle,
invalidation, lock, full-buffer backpressure, pending maintenance revocation,
bus retry and reset before reservation. The port-only predecessor fails the
expected second-store shortcut check. Total benchmark wall time is 521.394 s.

## Qualification and corrected test fixture

92 CPU runs pass, including faults, force-user/FIQ, IRQ/SWP, cache policy,
instruction prefetch/lockdown, buffered-walk ordering and the two new permission
programs. Thirteen related unit suites also pass, including demand/idle ACK
separation, dirty-packing cycle equivalence and an independent write-buffer
hazard/FIFO scoreboard. Exact commands/results are in the evidence below.

The preexisting read-only cache equivalence fixture failed at cycle 1470 on
both accepted B and E0: it compared a generic data adapter's intentionally early
ordinary-load response against the instruction response class. Its generated
reference now retains writable metadata while using the same instruction
request class. Both word/wide and halfword transports pass 9,416/9,440 compared
clocks, preserving every external value/timing comparison. Production response
classification is unchanged. Formatting preserves all fixture lexical tokens.

The temporary unit orchestrator also rejected a valid `PASS` without a colon
and collided output paths for the write-buffer hazard build. Replaying the
already-built basic and hazard executables into separate logs passes both; no
RTL change was needed. A test expectation after pending maintenance was also
corrected to require normal lookup, since that offer correctly revoked absence.
These failed approaches and source identities are retained in local evidence.

## Pipeline continuity and remaining gates

The reusable lookup result and current request's captured absent class are
separate. A later hit pipeline can carry that class alongside its owned PA/data/
mask rather than consulting a newer live record. Pending maintenance revocation
while an accepted store waits is already tested. The surrounding single-owner
controller, adapter and CPU completion/global hold remain unchanged; multi-
request execution still needs stages/credits, hazards and ordered commit.

Resident selected-way reads/stores remain separate experiments under the
[indexed-bank plan](selected-way-pipeline-investigation.md). E0 needs no direct
indexed data/dirty mutation because an absent store must never touch that bank.
C's second translation slot remains open. Keep the 78 MHz PLL and 104 MHz
design objective. FPGA ALM/LAB/timing and full boot/game/save/MMC acceptance
require a later build and board qualification.

[Detailed qualification](evidence/cache-store-absence-20261115.json),
[complete payload evidence](evidence/spmark-payload-store-absence-20261115.json),
[comparison table](spmark-payload-results.md).

Reproduce the dedicated test:

```sh
sh tests/cpu/cache_store_absence/sim.sh build/sim/NEW_NAME
CPU_PROGRAM=cache_store_absence tests/cpu/core/sim.sh
python3 tests/cpu/spmark_payload/run.py --name NEW_NAME \
  --baseline build/sim/spmark-payload/permission-reuse-20261115/result.json
```

The recorded CPU regression scripts use isolated outputs under
`build/sim/store-absence-*`; local orchestration and failed controls are under
`scratch/absent-line-store-20261115/`. Only this step's rebuildable compiler
headers were removed after verification; executables, source, logs and all
checkpoints remain. No branch/worktree, commit, push, CI or hardware action.
