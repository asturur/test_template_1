# Cache-load latency and pipelining plan

The user selected removal of unnecessary waits before pipelining requests.
Astra reviewed the design read-only; implementation and simulation were done
by the main agent. No extra FPGA RAM, wider cache or clock increase is needed
for the first change. Current PLL remains78MHz;104MHz remains the timing target.

Current order after the user's clarification: **A (handoff waits), D (response
copy), then independently measured B/C (local permission/mapping reuse), E
(selected-way overlap), F (request pipelining)**. Letter labels remain stable
for dependencies and evidence; their section order is not the execution order.

## Measured current latency

A warmed ordinary load with a matching local translation token holds P2 for
9clocks. A resident mapping lookup/direction change raises that to11. Warm
stores hold10clocks, or12 after the local token changes. These are held-clock
counts, not instruction retirement latency or load initiation interval.

| Matching-token load | Held clocks | Reason |
| --- | ---: | --- |
| Legacy translation handoff |3 | pending_request → checked_request_prev → pending_translation |
| Cache admission |1 | Capture actual request owner |
| Tag RAM read |1 | Synchronous BRAM |
| Tag comparison |1 | Registered64-way matches |
| Selected data RAM read |1 | Synchronous BRAM |
| Word response register |1 | Cache response_data |
| CPU completion capture |1 | Owned raw word/fault response |
| Total |9 | P2 advances on the following release edge |

The local TLB token currently includes access direction. A change from read to
write repeats a resident main-table lookup; in the captured workload that costs
3busy clocks but only2additional held clocks because some wrapper work overlaps.
Matrix alternates between two different1KiB regions and likewise rebuilds the
single local token repeatedly. These are main-TLB hits, not external page walks.

The raw trace is taken only inside the first scored window of the original ARM
matrix/transpose functions. An initial attempt captured untimed setup and was
rejected. The corrected observer matches every original counter. Traces and
scripts are under `scratch/cache-load-latency-20261115/` and
`build/sim/cache-load-latency-hot-20261115/`.
[Preserved witnesses and prototype evidence](evidence/cache-load-latency-investigation-20261115.json).

## A — owned-translation admission (implemented; full simulation acceptance passes)

Patch0061 changes only the D-cache wrapper. The current actual P2 request may
bypass the legacy translation_wait when `checked_owner` is true and neither
`tlb_busy` nor `tlb_walk_pending` is asserted. The token already checks MVA1KiB,
read/write direction, effective P2 privilege, MMU state, S/R, DACR and TTBR.
Current low address bits supply the translated offset. Alignment/permission
fault delivery and cacheability remain in the adapter's existing predicates.

This is not permission speculation from P1. The cache retains its request
registers and the CPU retains its owned completion register. Unowned requests
and active walks retain the old wait path. The registered tag, comparison and
data-RAM pipeline is unchanged. No state bits, BRAM or ports are added; actual
ALMs and routed timing remain unmeasured. Existing ownership assertions remain.

The isolated single-change prototype gives:

| Original workload,0:0 waits | Before | Prototype | Throughput gain |
| --- | ---: | ---: | ---: |
| Matrix |78,336 |73,391 |6.74% |
| Transpose |12,589 |10,636 |18.36% |

Original guest output checks and payload/helper execution counts pass. Hot
matching-token loads become6held clocks; loads requiring the local token to
change become9. Stores become7/10held clocks. These timings are observed in
the prototype, not extrapolated from the sum of profiler buckets.

Production implementation uses a named `translation_ready` predicate with the
same logic.32production profile/integration runs plus28additional fault/MMU/
FIQ/cache/alignment runs pass at delays0/3. The prototype separately passed46
runs. The full production payload comparison passes:12case/profile rows,84windows,
two identical repeats and six wrong-output controls. Medians are73391matrix,
10636transpose,42175triangle,183381/201345full-frame fill,5229fill16tail and
5961fill8tail (0:0/2:9 profiles; other medians equal). Index versus immediate
ARMv4T predecessor is119.7790/117.9279; versus original baseline119.8124/117.9607.
This is19.78%/17.93% more kernel throughput for this change, not board SPMark
points or FPS. Total run526.802s. The delayed frame result reveals backing wait
that was hidden by the previous CPU overhead. No commit/push/CI/deploy yet.
[Full results](spmark-payload-results.md), [CPU/provenance evidence](evidence/cache-owned-admission-20261115.json).

All37upstream SV/SVH token streams reconstruct through0061; strict byte
verification still has preexisting formatting drift. FPGA fit/timing and phone
boot remain separate gates. Keep the78MHz PLL unchanged.

## B — permit both access directions in one local mapping token

Dependency: A accepted and measured. Keep one context/1KiB mapping record,
but store separately checked read/write permission outcomes. A read-allowed
mapping must never authorize a denied write. Share mode/S/R/DACR/TTBR context
comparisons instead of duplicating a full token per direction.

Use explicit mapping publication versus one-shot fault publication. Invalid
L1/L2 descriptors and external walk aborts are operation-owned fault results;
they cannot be generalized as reusable mappings. Guard fault selection with a
live request: the legacy cache ACK also acknowledges idle cycles. A stale
idle tuple must not consume a fault or revoke a valid mapping.

Tests: AP0/1/2/3 with S/R, user read→denied write→read and reverse, same VA
across SVC/User/FIQ, LDRT/STRT, all1KiB AP boundaries, MMU off/on, TTBR/DACR/
FCSE changes, all/MVA invalidation, preserved entries, external L1/L2 abort
and retry across idle ACK. Run both I-side prefetch/CP15 tests and D-side tests
because translation code is shared. No promised speedup until remeasured.

## C — two small fully associative local mapping slots

Dependency: B independently measured. The matrix source arrays are4KiB apart;
access-direction changes are not its main local-token miss cause. Retain two
1KiB mappings under one shared context, with independent R/W permission outcomes
per slot. Do not change the architectural64-entry TLB, page sizes or CP15
replacement/lockdown semantics.

A second slot is estimated at roughly55–65additional state bits before
synthesis, plus a22-bit comparison and selection. This is not an ALM estimate.
Use fully associative lookup: choosing a slot from address bit10 would alias
these two arrays. Reset/invalidation/lockdown/MMU disable and shared-context
changes revoke both; main-table fill/replacement must also prevent stale local
mappings from extending architectural TLB lifetime. Keep transient fault results
separate and retain one owner until consumed.

Tests: alternate two virtual regions with equal low offsets, third-region
replacement, aliases, permission differences, same/different context, CP15
64/65-entry replacement and preserved slots, all page sizes and fault retry.
Measure separately from B and from cache-line shortcuts.

## D — ordinary-load response copy bypassed (full simulation acceptance passes)

A is independently measured and accepted. The D adapter now marks ordinary
non-SWP reads eligible at admission. `cache_access` captures that one-bit class
with the request, and revokes it on a miss. In READ_LINE the synchronous RAM's
owned raw word goes directly into existing `zap_data_completion`; the later
registered duplicate response is suppressed. The I-side, SWP, misses, stores,
MMIO and errors keep their previous response path. This is automatic request
classification, not a new user/OSD option.

The tag, match and synchronous data-RAM stages remain. `zap_memory_main` is still
the sole byte/halfword/sign/unaligned formatter. One eligibility bit and output
selection are added; no extra data array, cache line copy or RAM port is needed.
FPGA area/timing remain unmeasured. CPU trace now shows5held clocks on a matching
ordinary resident load and8when the local token must change, versus A's6/9.
Stores remain at A's7/10.

84production CPU runs pass at waits0/3, including all read widths, immediate
consumers, IRQ/FIQ/SWP/abort, protected/force-user requests, cold faults, MMU/FCSE
and alignment controls, plus CP15 drain/maintenance, translated prefetch,
lockdown and IRQ/FIQ/masked WFI. The dedicated `tests/cpu/cache_hit_response/sim.sh`
checks17exact-once requests, all word lanes, live-input poisoning, partial-store
freshness, miss/uncached/SWP-class fallback and reset revocation. Its cache
admission-to-response hit latency is3rather than4clocks. It is part of the normal
CPU suite. Standalone legacy clients explicitly withhold early delivery; the
existing cache dirty-packing cycle-equivalence, full cache-access/maintenance and
write-buffer integration tests pass unchanged in their timing contract.

The traced original payloads pass their output and retirement checks: matrix
71119vs73391cycles, transpose10220vs10636. The complete production suite passes
12case/profile groups,84windows, exact repeats and all six negative controls.
This step adds1.5193% kernel throughput over A in either profile. Combined A+D
improves21.5989%/19.7196% over the ARMv4T-only predecessor. Original-baseline
indices are121.6327/119.7529. Full run519.074s; full-frame and tails save only
one clock here because their timed work is stores, while load-heavy kernels
benefit more. [Results table](spmark-payload-results.md),
[CPU/cache/trace evidence](evidence/cache-early-hit-response-20261115.json).

The implementation is in maintained `rtl/arm920` modules, outside upstream ZAP;
0061 remains latest ZAP patch. The slow-class response register physically
remains for its existing clients; ordinary eligible loads bypass its extra
latency. One eligibility bit and a32-bit selection are added, no BRAM/line copy.
Fit/timing and phone boot remain unverified; no commit/push/CI/deployment.

## E — selected-way certificates before a larger pipelined interface

Dependency: A–D ownership contracts and measured locality. A same-line-only
shortcut is cheap but misses the interleaved matrix input pattern. Investigate
two exact MVA-line tags plus selected way; read fresh data from existing M10Ks,
rather than copying two256-bit cache lines or adding RAM ports.

Two line-tag/way certificates are roughly69state bits plus two27-bit compares
and a6-bit mux before synthesis. Conservatively invalidate on stores first,
then independently qualify surviving store hits if useful. Refill/replacement,
maintenance, reset and lockdown invalidate affected certificates. A preserved
certificate must never expose a same-slot mixed-port RAM collision or stale
byte lanes after store. Current P2 permissions and C/B still gate completion.

Targets, not measured results: selected-way scheduling from P2 can approach
3held clocks; P1 address-only preselection may approach2. One held clock is
possible only when the previous same-line output is already valid, or an earlier
harmless RAM read has completed and the actual P2 owner is revalidated. The
current blocking completion still imposes a bubble; these are not one-load-per-
clock claims. Do not use ALU `i_address_nxt` as a trusted request or reuse
another stage's live privilege. Address-only probes cannot create bus traffic,
faults, stores or architectural results.

Tests: exact-address and line-tag collisions, two alternating lines with equal
low index bits, third-line replacement, store hit/miss and same-slot hazards,
virtual aliases, permission/FCSE changes, maintenance/kill/reset, miss fallback,
and ALM/104MHz routed timing. A full-line fast path copied from the I-cache is
not the default choice given91%ALM use.

## F — pipeline independent requests after reducing avoidable latency

The tag and data blocks are already registered stages, but `req_ready` and the
CPU's global `data_stall` serialize memory requests. Overlapping tag read for
I+1 with comparison for I is feasible. A throughput pipeline needs per-stage
valid/owner metadata, effective privilege/direction/format/destination, aligned
responses and precise faults; it cannot reuse the controller's single `mva`
register for several operations.

First overlap address-only lookups with existing CPU stages and validate P2.
To approach one independent hit per clock, also redesign completion credits and
the global hold; merely pre-reading tags cannot overcome the mandatory blocking
completion bubble. Track wrong-path probes and misses, and preserve program
order across stores, MMIO, SWP, CP15 and fault-capable older work. Dependent loads
still wait for their producer; benchmark latency and initiation interval
separately. Use a bounded small queue if necessary, with explicit ALM cost.

Tests: long independent hit streams and dependent pointer chase, alternating
loads/stores, RAW/WAW and same-address forwarding, hit→miss→hit backpressure,
multiple widths/destinations, exceptions at every stage, oldest fault wins,
wrong-path cancellation, write-buffer ordering, SWP atomicity, maintenance and
random stalls/reset. Full payload and phone/game validation follow timing/fit.

## Locality evidence and limits

These are initially empty LRU models over short captured warmed prefixes, not
full-workload hit rates or simulated speedups:

| Prefix | Demands / loads | One direction-keyed mapping | One both-direction mapping | Two both-direction mappings |
| --- | ---: | ---: | ---: | ---: |
| Matrix |68 /55 |6 |6 |46 |
| Transpose |100 /52 |48 |92 |98 |

For load-only line certificates, matrix hits0/55 with one slot and33/55 with
two when stores clear them; retaining across stores raises two slots to36/55.
Transpose gives8/52 when stores clear either size, versus16/52 and40/52 when
one/two slots survive stores. This justifies testing two small fully associative
records, and testing store freshness explicitly. It does not establish area,
timing, whole-game speedup or an exact final pipeline budget.
