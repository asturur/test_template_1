# Ordinary write-back store completion

The current full SPMark payload profile identifies data completion as the largest
remaining wait in the fills:76.06–87.44% of measured clocks. Transpose spends
44.69% in data holds; matrix20.82%, with10.88% multiplier busy. These occupancies
are not additive recoverable loss. The previous branch/return improvement makes
old pre-branch percentages obsolete. All12current baseline groups repeat exactly
and retain every accepted timing/traffic/retirement counter. All46compiled CPU
sources match the checkout; only Template's unrelated clock/debugger wiring
differs from the133-file accepted source snapshot.

This change shortens ordinary cached write-back store completion while retaining
physical commit and ordered reservations. Full-suite throughput improves
**10.2203% /6.7791%** over branch-return at synthetic I:D waits0:0/2:9. Original
baseline indices advance **186.9337/167.8711 →206.0389/179.2512**. No extra state,
RAM, DSP, pipeline stage or PLL change;78MHz stays active,104MHz the timing goal.
Physical resource/timing and native phone speed are unverified.

## Commit contract

A write-back miss is nonallocating and mutates no cache bank. At a successful
posted-buffer reservation the existing buffer captures payload, capacity and
line hazards. Its local data commit proceeds independently of the CPU owner.
The response remains registered, but can be asserted at reservation instead of
waiting in STORE_COMMIT. A full queue still holds the request; accepting a store
does not mean its external memory write has completed. Read misses, drain and
maintenance continue to observe the existing buffer hazards/empty state.

A resident hit still captures data and dirty metadata in STORE_HIT and commits
both on the following edge. Its response is offered in STORE_COMMIT so the CPU
captures completion on that same commit edge. Suppressing the later copied
pulse prevents double acknowledgement. A maintenance offer cannot steal the
accepted store; actual reset/invalidate/lock retains its cancellation boundary.
Byte masks, both dirty halves, selected way and physical address remain owned
by the existing registers. Zero-byte stores can complete without a RAM write.

Eligibility uses the existing captured ordinary-owner/cacheability/bufferability
flags. SWP, write-through and unsupported/noncached clients keep their previous
completion. There is no new late ACK-to-issue or wide RAM-data-to-control cone:
resident completion uses narrow registered metadata/state, and posted completion
uses the existing ready decision into a response FF. Routed104MHz closure is
still a separate gate. This does not implement multiple outstanding requests,
F2 credits or speculative device operations. A future pipeline must retain the
same reservation, commit, collision and oldest-fault ownership contract.

## Results and tests

| Workload | Before | After,0:0 /2:9 |
| --- | ---: | ---: |
| Matrix ×16 |56489 |56009 /56009 |
| Transpose ×32 |6102 |5784 /5784 |
| Triangle edges ×16 |28331 |27744 /27744 |
| Full16-bit frame |105589 /201321 |87288 /201316 |
|16-bit tail |3527 |3015 /3015 |
|8-bit tail |3587 |3076 /3076 |

The delayed frame is still limited by backing writes: this is not a claim that
cache-only work removes that limit. The full zero-wait frame gains20.97% in
throughput. All12groups/84windows per repeat, two exact repeats and six wrong-
output controls pass; mathematical/original-code output and helper retirement
checks remain unchanged. All133candidate snapshot hashes match the checkout.

78CPU runs pass across cached/posted/write-through/drain behavior, privilege,
MMU/FCSE/TLB ordering, faults, block transfers, FIQ, SWP and instruction-buffer
ordering.44IRQ/FIQ boundary sweeps pass. Ten related unit groups pass, including
packed-dirty differential, buffer retries/hazards and336F1 probe transactions
with155fast reads,8independent A/B overlap clocks and122blocked collisions.
Resident/posted fixtures check all masks, fresh reads/dirty writeback, PMM-like
partial writes, full capacity, changing live inputs, maintenance and reset.
The direct fixture's indexed store drops3→2clocks; known-absent posted store2→1.
The SWP-class direct fixture retains5clocks. These are fixture intervals, not
independent CPU initiation intervals. Five controls reject old posted/resident
latency, ignored capacity, wrong-class delivery and a repeated response.

The initial CPU list mistakenly named generated ARMv4T assembly as a static
program; it failed before CPU execution. The recovered78-run list omits that
unrelated generated profile and retains the actual memory/exception checks.
No RTL fault or missing instruction-profile coverage is inferred from that
fixture setup failure. Nine profiler parser controls also pass.

Full post-change profiling is running under
`build/sim/spmark-profile/store-commit-full-20261115`; its focused math groups
already reconcile without changing accepted counters. Do not call that a full
post-change profile until all12groups and repeats finish. Raw scripts and run
identity live under `scratch/cpu-next-bottleneck-20261115/`.

[Qualification](evidence/cache-store-completion-20261115.json),
[full benchmark](evidence/spmark-payload-store-commit-20261115.json),
[baseline profile](evidence/spmark-payload-branch-final-profile-20261115.json).

Next: quantify remaining CPU/cache handoff waits and initiation intervals for F2
credits/ordered completion using the completed profile; retain the older donor
plan's multiply, block-transfer and frontend attribution work. Do not sum raw
empty-queue, fetch and redirect counts into a claimed speedup. User's debugger-on
build and MMC hardware session remain separate; no new CI/deployment was done.
