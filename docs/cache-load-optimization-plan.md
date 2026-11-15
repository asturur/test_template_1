# Cache-load latency and pipelining plan

## Latest checkpoint — first F2 handoff overlap qualified

Registered completion consumption now overlaps admission of an eligible next
P1 owner. No new state/RAM/stage; precise context and conservative fault/PC/SWP
guards remain. Full-suite indices **225.1646 / 189.3816**, +9.2825% / 5.6515%
over store-commit. Independent loads325→235 clocks; dependent loads stay259.
JPEG hotspot gains only0.6265%; its native deadline remains unresolved.
78architectural/44interrupt-edge runs, owner scoreboard, five exercised broken
variants and complete repeated benchmark/profiles pass. Physical gates pending.

This completes the first bounded F2 step. One unresolved demand/global hold
remains: deeper miss overlap requires additional owned credits and precise
ordered completion. Thumb load-use/frontend work remains especially relevant
to JPEG; the older CPU/arithmetic plan is retained.
[Contract, limits and evidence](cache-completion-overlap.md).

The user selected removal of unnecessary waits before pipelining requests.
Astra reviewed the design read-only; implementation and simulation were done
by the main agent. No extra FPGA RAM, wider cache or clock increase is needed
for the first change. Current PLL remains78MHz;104MHz remains the timing target.

Current order after the user's clarification: **A (handoff waits), D (response
copy), then independently measured B/C (local permission/mapping reuse), E
(selected-way overlap), F (request pipelining)**. Letter labels remain stable
for dependencies and evidence; their section order is not the execution order.

## Latest profiling checkpoint — JPEG bitmap conversion

The JPEG deadline investigation adds a checked original Thumb error-diffusion
workload. Current8x8case118705clocks:35.27%data completion,14.19%load dependency,
19.79%empty operands; warm external wait0. Latest store change gains3.444%on
this workload. F2's owned credits/completion/global-hold overlap remains first
structural work, with explicit Thumb PUSH/POP/LDM/STM and dependent-load cases.
Frontend/call-return is next. Existing A–F dependencies/tests remain; this does
not authorize an unqualified memory or CPU replacement. [Profile/baseline](spmark-jpeg-profile.md).

## Latest checkpoint — store completion accepted

Ordinary posted/resident writes now complete at their durable reservation/commit
boundaries. No extra state/RAM, full suite +10.2203%/6.7791%, indices206.0389/
179.2512. F2 credits/precise ordered completion remain the next structural
boundary, pending final profile attribution. [Contract](cache-store-completion.md).

## Earlier checkpoint — F1 simulation-qualified while predecessor builds

User authorized continuing during the pinned a745119/run43719932412 build.
F1 now pre-reads a registered certified P1/current address using existing RAM B,
overlapping independent A commits; P2 checks remain authoritative.68metadata
bits/no new RAM/data copy. Full suite +2.1338%, original154.4752/144.5781;
98CPU/44edge/20units/five controls and poisoned mixed-port RAM pass.
Still one CPU request outstanding; F2 credits/ordered completion/global-hold
relaxation remain separate. Scheduled hardware work tests a745119, not F1.
[Contract, tests and next boundary](cache-data-probe.md).

## Previous checkpoint — CPU load-use overlap accepted; build next

Phase08's early/late producer availability now uses registered P2 aligned words
and actual formatted Memory commits, without changing cache RAM/control.
Indices151.2480/141.5576; full suite/98CPU+44edge/five units/four controls pass.
Build feedback precedes another optimization. Then F1 should exploit independent
A-write/B-read use with owned stages and explicit same-slot interlocks/forwarding.
Modest extra BRAM is allowed for useful port/buffer capacity. P1 probes alone do
not create multiple accepted CPU requests or permit speculative device effects.
[Contract and measured results](cpu-load-forwarding.md).

## Previous checkpoint — C's second checked mapping accepted in simulation

C now shares two 1KiB mappings under one context, retaining independent R/W
permissions and exact primary fault ownership. Final full payload qualification,
96CPU runs, seven relevant unit suites and four negative controls pass. Suite
throughput improves2.7630%/2.7626% over E1/E2, original indices149.1744/139.6171.
Only the TLB controller changes in the production source closure. Added state
is65bits per I/D instance,130total; no RAM/PLL change or simultaneous requests.
Current78MHz/104MHz objective remains; physical gates are unverified. Later P1
probes must validate/capture current P2 permissions and PA with each owner;
F credits/ordering, load dependencies and fetch attribution remain open.
[Design, tests and rejected prototype](cache-two-mapping.md).

## Previous checkpoint — resident indexed reads/stores accepted

E1 jointly extends the result directory and adds indexed reads; E2 independently
adds indexed ordinary WB stores. Full payload repeat/negative controls pass
both stages, with92/94CPU runs and19unit suites each. The controller uses50more
declared state bits than E0 and no new RAM or line/dirty copies. Common indexed
cache responses improve reads3→1and stores5→3clocks; CPU holds are3/5versus5/7.
Indices versus original baseline100 are145.1635/135.8637 (0:0/2:9), +11.2285%
over E0. Current78MHz PLL/104MHz target; fitted cost/timing/boot unverified.

The directory holds no permission or data results. Actual P2 checks precede
admission; selectors and metadata travel with the owner. Existing M10K read,
store capture and paired data/dirty commit boundaries remain. Later P1/F work
must interlock/forward same-slot hazards and introduce ordered stage credits;
C and CPU dependency/branch attribution stay open. Original9/11-clock latency
below is historical starting evidence. [Implementation and tests](cache-resident-way.md).

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

## B — both access directions in one local mapping token (implemented; full simulation acceptance passes)

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

B now passes the tests above. The pre-change controller fails the new direction-
reuse test as expected; the candidate passes 3,092 hot checks through actual
descriptor publication, plus a CPU loop with 32 denied force-user stores and
read recovery at delays 0/3. Full benchmark indices versus original baseline
are 124.0646/122.1471; throughput gain over A/D is 1.9993%.
The qualified transpose profile reduces translation-related holds from 12.19%
to 2.07% and data holds from 58.85% to 54.10%. These are overlapping
occupancies; they are not additive recoverable loss.

### B implementation and later pipeline contract

`arm920_tlb` now publishes a checked mapping separately from an exact walk-fault
result. A mapping stores read-allowed and write-allowed bits under one existing
1 KiB/context record. Direction changes select those registered outcomes without
republishing or rerunning the CAM/BRAM lookup. The two denied directions share
the existing domain/AP FSR field; no duplicate context, physical mapping or FSR
register is needed. A permission fault leaves the mapping available for a later
allowed read. Invalid-descriptor/table-bus faults instead match the full captured
address and direction and are discarded only by their live owner's completion.
Idle legacy ACKs cannot consume them.

Three state bits per TLB instance are added (mapping/result class and two
permission outcomes), six across the instruction/data instances before synthesis.
There is no new RAM, cache line copy, descriptor bank, port or outstanding request
slot. Permission calculation stays at descriptor publication, outside the hot
request-direction selection. Current BRAM/read/compare stages and the 78 MHz
PLL are retained; 104 MHz remains the routed-timing objective. FPGA area/timing
is not inferred from the state-bit count.

This makes the record a reusable mapping capability rather than the current
request's completion record. Use that boundary for subsequent overlap:

1. An address-only P1 lookup may probe the current mapping while the previous
   P2 request completes. A probe must not launch a walk, publish/consume a fault,
   allocate a completion, issue external traffic or perform a store.
2. At P2 admission, validate the actual MVA/context, effective privilege,
   direction, alignment and current mapping generation. Capture physical
   address, C/B, permission/fault/FAR, byte formatting and destination ownership
   with the request. A later response must not read a newer live token.
3. An overlapping tag-read/compare/data pipeline needs per-stage valid/owner
   metadata and ready/credit handling. Invalidation/context changes revoke
   probes; accepted older work must still drain or fault precisely. Preserve
   ordering for stores, MMIO, SWP and CP15; do not weaken the global hold until
   completions and oldest-fault handling support more than one request.

These are dependencies for E/F, not extra hardware silently bundled into B.
Before enabling overlap, test token replacement/invalidation while an older
response is held, read/write permission differences at both stages, wrong-path
probes, hit/miss backpressure, oldest faults and exact-once stores. Measure load
latency and independent initiation interval separately. C remains an independent
locality experiment; its results should decide whether an additional mapping
slot is justified before any larger request queue.

## C — two small fully associative local mapping slots (simulation-qualified)

Dependency: B independently measured. The matrix source arrays are4KiB apart;
access-direction changes are not its main local-token miss cause. Retain two
1KiB mappings under one shared context, with independent R/W permission outcomes
per slot. Do not change the architectural64-entry TLB, page sizes or CP15
replacement/lockdown semantics.

The implementation adds65declared state bits per I/D instance before
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

C final results: matrix66031→60850, transpose7786→7510,
triangle39005→37360; fills improve by6–9cycles. All original bytes, outputs,
payload/helper counts and repeat/negative controls pass. Main-bank fills revoke
both old local records before publishing a new primary; publication otherwise
retains the prior primary using FIFO, with no hit-time payload swap. The exact
fault/checked-owner corner discovered in the prototype has its own test and
negative control. [Complete evidence](evidence/cache-two-mapping-20261115.json).

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

E1/E2 are now implemented and independently measured. See
[resident indexed access](cache-resident-way.md): two small line-result records,
owned data read selection, fresh dirty RAM for indexed stores and paired commits.
The tests prove all8segments/both dirty halves; assertions enforce current
single-owner mutation exclusion. No P1 speculation/multi-request pipeline yet.
The earlier investigation below remains planning evidence, not current status.


E0 implementation checkpoint: [absent-line stores](cache-store-absence.md) now
pass full simulation acceptance. One 28-bit line-result record and two owned
class bits accelerate only ordinary cacheable buffered write misses. SWP,
uncached and write-through classes keep their old paths; a read/refill revokes
the record. Captured PA/data/mask and completion ownership are retained under
queue stalls and later directory revocation. No indexed resident bank path or
multi-request pipeline is implemented. The negative shortcut therefore remains
a separately measured predecessor for resident-way and P1/F experiments.


Investigation update 2026-11-15: the user prioritized E feasibility before
implementing C. [Measured lookup and pipeline investigation](selected-way-pipeline-investigation.md)
qualifies an unchanged-timing observer on all six B kernels and checks 1/2-entry
shadow records against actual tag decisions. Full-frame stores are all misses
in the sampled window: positive selected-way reuse alone cannot help them.
A store-only absence record covers 16,016/18,306 demands. Resident reuse covers
1,487/2,544 matrix and 704/800 transpose demands with two shared records.
These are potential skipped searches, not speedups. Recommend one common
presence/way directory and owned indexed bank contract; measure store-miss,
resident-read and resident-store shortcuts separately before P1/F overlap.
Existing data/dirty commits and single-owner CPU control require explicit
interfaces, not only a `hit_way` mux. See the investigation for tests and what
carries into a later execution pipeline. B production RTL remains unchanged.


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
