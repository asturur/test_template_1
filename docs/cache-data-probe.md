# F1: owned reads on the cache data RAM's second port

F1 is simulation-qualified on the integration branch. It pre-reads a certified
P1/current-read address while the older owner is completing, allowing independent
RAM A writes and B reads. A validated actual P2 read can use the existing BRAM
output directly through the CPU's registered completion boundary.

The full six-kernel suite gains **2.1338%** over load-forward, with original
baseline indices **154.4752 / 144.5781** at waits0:0/2:9. Transpose gains9.97%,
triangle1.96%, matrix1.15%; full-frame stores are unchanged. These are offline
kernel results, not hardware SPMark scores. The hardware build currently under
test is **a745119/run43719932412**, which precedes F1 and cannot verify it.

## Ownership, ports and cost

Two34-bit records hold a full27-bit virtual line tag,6-bit selected way and
valid bit: one captured probe owner, one result aligned with the actual read
edge. Total **68additional declared state bits**, no new RAM, cache-line copy,
dirty mirror or permission copy. Existing data-RAM output supplies the line.
Selector capture precedes its RAM address use; live P1 comparisons do not drive
BRAM addresses. The D role selects DATA_PROBE=1 automatically; I/legacy clients
retain their existing role. There is no OSD/user/build opt-in.

The bank has separate owned data read-B addressing and exposes actual write-A
commit validity/index. Tag/dirty metadata retains the P2 owner and existing
atomic data/dirty commit ports. Independent slots may read/write concurrently.
Any same physical slot/segment write blocks the probe, invalidates its result,
and requires a fresh legal read. Neither old/new/zero data from a mixed-port
collision is assumed. Full-byte masks and both dirty halves remain unchanged.

P1 probes are read-only internal RAM activity: they never walk, refill, issue
external traffic, consume a fault, enqueue a store or authorize a completion.
Before admission, a current read may also hide RAM access behind translation;
once launched/satisfied, its probe slot can prepare P1 instead. Actual P2
permissions, alignment, C/B, cache state and non-SWP class still gate the fast
response. Narrow/unaligned results remain raw words for the existing formatter.
Wrong-path probes cannot publish data architecturally.

Fill/replacement, maintenance, invalidate, lockdown, cache-disable and reset
revoke both records. Loss of the data read port revokes the result token. A
registered write to the result's physical slot suppresses it before completion.
Private directory replacement alone need not discard a still-correct owner;
actual cache mutations revoke it, so a retained selector cannot outlive its line.
The D role disables the old instruction-style stream-line copies; they are not
silently synthesized into a new writable L0 cache.

The CPU still has **one outstanding memory request** and a global hold. This is
P1/P2 RAM preparation and independent A/B overlap, not dual issue or the full F2
request pipeline. The78MHz PLL is unchanged;104MHz remains the design target.
All added selectors/readiness use registered metadata and existing RAM outputs,
but routed timing, fitted ALMs and hardware boot remain unverified for F1.

## Verification and measurements

The final suite passes12groups/84windows per repeat, two exact repeats and six
wrong-output controls in 419.197s. Medians: matrix60094, transpose6420,
triangle35982, frame135314/201317, fill16tail4322, fill8tail5046.
[Comparison table](spmark-payload-results.md).

Acceptance also passes98CPU regression runs plus44IRQ/FIQ/SWP edge sweeps,
20related unit suites, five broken controls and an adversarial RAM model. The
final dedicated fixture checks336transactions plus explicit faults/walk waits,
155fast reads, all8segments/words/byte masks and both dirty halves. It observes
8independent A-write/B-read clocks and122blocked same-slot collisions. It also
checks changing P1 targets, high virtual aliases, SWP pairs, uncached/disabled
paths, permission/alignment faults, translation delay and primed invalidation,
lock/reset. Probes alone issue no external reads. Forcing actual data-RAM
mixed-port collisions to return zero still passes; an output-token assertion
rejects publishing those unspecified results.

Controls reject a disabled owned read, ignored collision guard, truncated high
tag, ignored P2 permission and ignored SWP class. The initial high-alias control
survived because maintenance had cleared the fixture's certificate; preparation
now asserts that the probe is genuinely primed. A stale backing-memory oracle
for dirty A and new ports accidentally added to a frozen reference fixture were
also corrected. These were test fixes; RTL did not change during qualification.
The recovered packed-dirty/reference and write-buffer suites pass, with the
initial failed fixture attempt retained explicitly in local evidence.

Existing CPU microbenchmarks compare the exact committed predecessor against
F1 using identical binaries/harness/image/model and two exact repeated runs:

| Work | a745119 | F1 | Scope |
| --- | ---: | ---: | --- |
|32dependent LDR+ADD iterations |321 |259 |10.031→8.094clocks/iteration |
|128word loads in a four-register stream |579 |325 |4.523→2.539clocks/word |

The latter includes frontend/WAW/loop costs and is not a pure cache initiation
interval. All15guest kernels/checks pass their independent Unicorn/wrong-result
controls; only the two listed kernels were timed here. Operand timing's warmed
load→consumer issue gap drops9→7clocks; warmed dependent ADD stays one clock.
This does not show one accepted CPU memory request per clock.

The focused math profiler at both profiles repeats exactly and matches every
original accepted counter. Data-hold occupancies are matrix19.62%, transpose
42.49%, triangle22.90%; raw counters overlap. No new full six-case stall profile
is claimed. The older RAS/forwarding/arithmetic plan stays active.

## Next boundary and hardware identity

Keep the scheduled a745119 deployment/native SPMark run separate from this
candidate. After physical feedback, F2 should introduce explicit stage credits
and ordered completion ownership before relaxing the global hold. Measure
independent initiation interval and dependent latency separately. Preserve
same-slot forwarding/interlocks, precise oldest faults, SWP/MMIO/CP15 barriers
and mutation drain/generation rules. Modest extra BRAM remains allowed for
useful buffering/banking; the old two-stage RAM ports should be used deliberately.

Build manifest: `scratch/load-forward-build-20261115/build.json`.
Next-candidate sources/logs: `build/sim/spmark-payload/f1-data-probe-20261115/`.
CPU: `build/sim/f1-data-probe-cpu-20261115/`.
Initial/recovered units: `build/sim/resident-f1-data-probe-units-20261115/` and
`build/sim/resident-f1-recovered-units-20261115/`.
Controls/poison: `build/sim/f1-probe-controls-final-20261115/` and
`build/sim/f1-probe-poison-final-20261115/`.
Microbench: `build/sim/cpu-donor-import/f1-port-cpu-20261115/`.
Scripts/provenance: `scratch/f1-dual-port-20261115/`.

Patch0063 wires the always-active D role and existing P1 address/read signals.
All37reconstructed ZAP token streams match through0063; strict bytes retain
preexisting formatting drift. No branch/worktree, card-image or firmware patch.
Other simulations and permanent checkpoints are preserved.

[Qualification](evidence/cache-data-probe-20261115.json),
[full benchmark](evidence/spmark-payload-data-probe-20261115.json),
[microbench](evidence/data-probe-load-microbench-20261115.json),
[profile](evidence/spmark-payload-data-probe-profile-20261115.json).
