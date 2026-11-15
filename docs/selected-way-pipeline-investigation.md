# Selected-way reuse and later execution overlap

Current checkpoint: [resident indexed reads/stores](cache-resident-way.md) now
implement E1/E2 after E0 and independently measure the gain. The directory and
indexed owner interface are present; P1/CPU execution overlap is not. The
investigation below is historical planning evidence, with tests now addressed
as recorded in the implementation document. [C mapping reuse](cache-two-mapping.md)
is now independently qualified; F execution overlap remains open.

2026-11-15. Investigation on the original integration checkout, after accepted
permission reuse B. No production RTL changes in this investigation. The next
implementation should share a small lookup-result directory and an owned,
indexed cache-bank interface with the later pipeline, while keeping each
shortcut independently measurable. C's second translation slot remains open;
the user prioritized this E investigation before implementing more changes.

## Measured locality, with an important fill distinction

An observer on frozen B CPU sources traces actual accepted D requests, registered
tag hit/way decisions, cached stores, RAM commits and mutations. All six original
kernels finish; every original per-window/whole-run timing, traffic and payload/
helper counter matches the accepted run. The observer traces one complete first
scored window per workload at synthetic 0:0. It does not modify guest code.

Two-entry LRU shadow records start empty, compare all 27 MVA line bits and reuse
an observed way only while its certificate is valid. They clear on any fill or
maintenance/invalidation/lock event. Resident stores may retain a certificate
because they change data/dirty state, not which line occupies the way. Data must
always be read freshly from the existing RAM. A second policy additionally
remembers that a line is absent, exclusively for nonallocating stores.

| Workload | Demands | Resident loads | Resident stores | Store misses | Resident-result reuse, 2 entries | Additional absent-store reuse | All reused / demands |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| matrix4 | 2,544 | 2,176 | 368 | 0 | 1,487 | 0 | 58.45% |
| transpose4 | 800 | 416 | 384 | 0 | 704 | 0 | 88.00% |
| triangle_edges | 1,712 | 800 | 912 | 0 | 1,040 | 0 | 60.75% |
| fill16_frame | 18,306 | 1 | 0 | 18,305 | 0 | 16,016 | 87.49% |
| fill16_tail | 514 | 1 | 513 | 0 | 448 | 0 | 87.16% |
| fill8_tail | 516 | 1 | 515 | 0 | 450 | 0 | 87.21% |

Every predicted presence/absence and resident way agrees with the actual lookup.
Eight model controls also pass, including deliberately stale-way/presence
rejection, exact-tag aliasing, capacity, SWP/uncached exclusion and refusal to
use an absence record for a read. These are potential skipped tag searches,
not measured clock savings or fast-path correctness tests.

**Full-frame fill has 18,305 write misses and no resident store hits in this
window.** Its writes are cacheable/bufferable, but the cache does not allocate
on write miss. A hit-only selected-way shortcut has zero coverage there. One
absence record already covers 16,016 consecutive stores to previously checked
missing lines (87.49% of all demands); two entries have the same coverage in
this case. Do not change cache policy to write-allocate merely to improve a
benchmark. A negative result is invalidated by a later relevant fill, and is
never permission to skip the current request's translation/attribute checks.

For the small fills, approximately 87% of store requests reuse one resident way.
For matrix, one shared resident record covers only 192/2,544 demands, while
two cover 1,487/2,544. Read-only records that clear on stores cover no fill
stores and only 64/800 transpose loads even with two entries. A load-only first
prototype can establish safe indexed reads, but cannot claim to address the
largest fill cost. Do not copy the instruction cache's two 256-bit stream lines
into the writable cache.

These windows contain no refill or maintenance events. Serialized baseline
execution also excludes overlapping read/write collisions. Neither absence of
hazards in this trace nor the shadow model qualifies mutation/overlap behavior.
[Machine-readable evidence](evidence/selected-way-investigation-20261115.json).

## Concrete hardware boundaries

Today `cache_access` accepts requests only in IDLE, holds one `mva/pa/wdata/ben`
record and sequences LOOKUP_CAPTURE → LOOKUP_WAIT → LOOKUP for every cacheable
request. The adapter's `launched` bit excludes the next request. The core holds
its stages through `data_stall` until one `zap_data_completion` record is valid.
These are serialization points independent of the number of tag/data registers.

The data RAM already has one synchronous read port and a separate byte-enabled
write port. There is no port-based requirement to wait for a previous **read**
response before starting the next RAM read. Same-slot read/write results are
explicitly unspecified, however; maintenance/refill share those same ports.

A selected way cannot simply replace `hit_way` in `cache_access`. The bank's
read segment comes from the delayed tag `lookup_address`; writes use captured
`commit_segment/way/enable/data`. Dirty-half updates in the tag M10Ks depend on
the matching-way vector and old dirty snapshot. Bypassing the lookup FSM while
leaving those inputs unchanged would use stale addresses/dirty flags, lose
partial stores or corrupt a different line.

Introduce an explicit **owned indexed access** boundary inside the bank:
segment + way + operation + byte mask/data, and a matching read-result owner.
Normal tag lookup and certificate lookup both feed this boundary. Indexed
stores must update data and both dirty-half flags coherently, with the current
line generation and all pending commits accounted for. The fallback CAM,
replacement, refill, write-buffer policy and architectural cache geometry stay.

Two shared records with valid, 27-bit line tag, 6-bit way and present/absent
class plus one replacement bit require approximately **71 directory bits**.
That is not a total implementation or ALM estimate: registered selectors,
hazard/owner metadata and muxes also cost logic. No extra line array or RAM port
is proposed. Keep 78 MHz PLL; preserve synchronous RAM/registered selection for
the 104 MHz objective. Actual fit/timing is a later independent gate.

## What survives a later pipeline, and what must change

| Part | Retained design | Work needed when requests/instructions overlap |
| --- | --- | --- |
| Exact line-result records | Presence/way matching, small capacity, fallback on unknown | Carry a validated result with its owner; handle revocation before admission |
| Permission reuse B | Separate R/W permissions and exact operation faults | Current P2 checks remain authoritative; capture outcomes rather than rereading a newer token |
| Indexed bank operations | Existing M10Ks, segment/way and byte-lane access | Register one selector/result owner per occupied stage; arbitrate maintenance/refill |
| Data freshness and dirty halves | Fresh RAM reads, exact byte stores and dirty OR rules | Same-slot interlock or qualified forwarding for pending data **and** dirty updates |
| Current `cache_access` FSM | Slow/miss/maintenance semantics and ordering | Replace the single request tuple with bounded stage valid/owner records |
| Adapter/completion/global hold | Exact-once completion, precise FSR/FAR and store ordering | Replace `launched`/one completion with ready/credits and ordered responses |
| Invalidation/context changes | Probes are revoked; older accepted work is precise | Begin with drain barriers; a one-bit epoch alone cannot protect tokens surviving multiple mutations |
| Later instruction execution | Existing ARMv4T effects, banked state and exceptions | Dependency/forwarding control, destination/flags ownership, kill and in-order architectural commit |

The lookup directory and indexed operations should not be redesigned for each
of those steps. The single-owner control and CPU handshakes must change: that
is substantial work, but it is separate from replacing cache storage or the
certificate algorithm. Define the boundary now so a single-owner prototype is
the first implementation of that contract, not a combinational ACK shortcut.

Start future overlap with **in-order, fully validated ordinary hits**. Stop and
drain on misses, CP15/maintenance, MMIO and SWP initially. A P1 address probe
may select a record or schedule a harmless RAM read while I completes; P2 must
validate the actual MVA/context, direction and alignment before accepting I+1.
A wrong-path probe cannot start a walk/refill, consume a fault, enqueue a store
or commit state. Snapshot PA, C/B, fault/FAR, format and destination only where
needed in the receiving stages. Use a drain/generation contract instead of
copying TTBR/DACR/context-wide records into every stage.

For concurrent hit requests, preserve program order at commit and forward or
stall load consumers and same-address stores. Starting a later independent ALU
instruction while an older fault-capable memory operation is unresolved also
requires ordered register/flags commit. The existing posted write buffer is a
transport queue, not a speculative store queue. Younger stores must never modify
cache/memory before older fault/kill conditions are resolved. This is additional
CPU work; faster selected-way lookup alone does not provide execution overlap,
multiple issue, or one memory operation per clock.

## Recommended implementation and tests

1. Establish the small result-directory and indexed-owner contract, with all
   mutations conservatively draining/revoking. Test real line/dirty RAM behavior
   before wiring an accelerated CPU response. Keep C independently measured.
2. Measure an absent-line **store-only** shortcut first, since it addresses the
   actual full-frame cost without changing dirty metadata. Reuse current checked
   PA/C/B, posted-write readiness and exact-once ownership. Unknown records take
   the old lookup. A pending fill/maintenance/SWP or unsupported class disables
   the shortcut; a negative certificate never services a read.
3. Measure resident indexed reads, then resident indexed stores separately.
   Store support needs atomic data/dirty commits and same-slot handling; it is
   not just the load path with its write bit set. Keep regular output formatting
   and the CPU completion owner. Do not merge tag comparison into BRAM timing.
4. Add address-only P1 overlap and validated P2 use under the same bank contract.
   Then, as a distinct F change, introduce stage credits/ordered completions and
   relax the CPU global hold for eligible independent work.

| Gate | Required checks |
| --- | --- |
| Directory truth | All line-tag bits, equal segment/offset aliases, 1/2/3-line replacement, unknown fallback, repeated miss→fill→hit, resident→evict→miss, cache off/on, maintenance/lock/context changes |
| Stores/dirty RAM | Every byte mask/word/half, both dirty halves, same way/segment consecutive stores, independent-slot overlap, read after pending write, metadata/data commit alignment, write-through versus write-back/no-allocation |
| Ownership | Poison all live inputs after admission; hold outputs/backpressure, exact-one store/response, reset/kill at every stage, certificate revocation between probe/accept/read/response |
| Ordering/faults | Read-allowed/write-denied, User/SVC/FIQ/LDRT/STRT, alignment, table/external faults, MMIO, SWP, buffer full/drain/error, CP15 before/after pending operations |
| Overlap | Independent streams versus pointer chase, RAW/WAW, store→load forwarding or stall, hit→miss→hit, oldest fault/kill and wrong-path probes; no speculative architectural writes |
| Performance | Same six checked payloads/controls plus hot load/store latency and independent initiation interval; separate directory coverage from measured saved clocks |
| FPGA/phone | ALM/LAB/M10K cost and routed 104 MHz objective with 78 MHz PLL unchanged; boot, phone/game/MMC/save ordering acceptance separately |

No acceleration RTL, benchmark speedup, FPGA fit/timing or board qualification
is claimed by this investigation. All production CPU source hashes still match
the accepted B snapshot. Existing uncommitted B work is preserved. No branch,
worktree, commit, push, CI or hardware operations were performed.

Local repeatable observer/model scripts and notes:
`scratch/selected-way-investigation-20261115/`.
Trace executable, bounded logs, frozen sources and counter qualification:
`build/sim/selected-way-observer-20261115/`.
