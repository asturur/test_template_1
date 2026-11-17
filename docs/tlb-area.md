# Area investigation — banked architectural TLB tags

**Retain this isolated area candidate for a matched physical fit; do not promote
it yet.** It preserves both complete64-entry mixed-page TLBs, reduces parallel
tag comparisons to eight per lookup, and moves their tags from registers into
explicit BRAM. All measured original warm workloads match the qualified5L
reference. A physical ALM saving has **not** been measured. The rejected5M
admission experiment is not part of this candidate; no further CPU pipeline
performance mechanism was introduced.

## Actual area baseline and alternatives

The anchor is the routed seed42/debug-on5K fit44123116917 at exactccba54f,
not a donor comparison or an unmapped synthesis estimate. Whole design:
**40,834/41,910 ALMs needed,45,605 registers,502/553 M10Ks,4,190/4,191 LABs**.
That leaves1,076 nominal ALMs,51 M10Ks and only one unoccupied LAB; these are
separate constraints. Placed ALMs40,883 and routing registers3,254 are separate
metrics again. Reducing declared storage does not prove LABs will become free.

The resource rows below come from that exact `Template.fit.rpt`. ALMs in the
comparison are **direct**, excluding child entities. Memory columns describe
the selected node including its memory children, and are not added twice.

| Independent area target | Direct fitted ALMs | Fitted registers at node | M10Ks at node |
| --- | ---: | ---: | ---: |
| I-side main TLB bank | 2,027.1 | 1,993 | 1 |
| D-side main TLB bank | 2,068.8 | 2,063 | 1 |
| MMC card controller | 2,137.0 | 2,009 | 8 |
| I-cache tag metadata | 1,386.7 | 864 | 64 |
| D-cache tag metadata | 2,067.0 | 1,309 | 66 |

The two TLB banks contribute **4,095.9 direct ALMs**. Do not add their parent
TLB totals2,308.3/2,427.3 on top. Cache metadata contributes3,453.7 direct ALMs;
the D-tag subtree total2,095.7 includes28.7 child ALMs and is not the direct
number. Nor may either cache-bank parent be added to its tag child.

Three designs were compared before choosing one prototype:

| Option, all capacities retained | Area/ports tradeoff | Latency and verification cost |
| --- | --- | --- |
| **Main TLB, eight comparisons** | Replace1,536 tag/kind register bits per bank with192-bit×8-row BRAM; retain the38-bit payload RAM; one write-A/read-B pair per memory. Plan+10–16 M10Ks across I/D. | First row can keep current bank latency; later rows add one clock each. Fill and MVA invalidation must serialize and CP15 must wait. Chosen. |
| MMC stream-tag RAM | Keep four metadata tags in registers; replicate12 stream tags for three simultaneous reads (low/high/prefetch), broadcast writes. Roughly+3 M10Ks and perhaps150–450 ALMs saved, **unfitted**. | Could retain the existing four-stage settle boundary, but shifts23-bit comparisons into the later stage. Needs careful simultaneous HPS/tag-write and collision equivalence. No MMC prototype was stacked. |
| Pack/scan cache tag metadata | Existing metadata is already RAM-backed, with64 parallel way read ports per side. Packing groups can release many M10Ks and reduce comparators while keeping64-way/16KiB. | Changes frequent cache lookup, dirty/maintenance, probe ownership and refill boundaries; savings are less directly tied to removing register tags. Higher integration risk than the selected TLB design. Not implemented. |

MMC's full2,137 ALMs are not all tags: CRC, command, capacity, streaming and
write logic remain. The small stream-tag estimate is not the entire controller's
area. Cache geometry, MMC behavior and diagnostic/peripheral modules are kept.

## Measure first: full searches are common, but hot entries are early

Passive observers run on the **exact retained5L CPU**, not5M. Original program,
ROM/payload hashes, independent oracles, payload/helper retirement counts,
five scored samples, repeats and wrong-output controls remain enabled. The
observer's six-kernel results match the earlier5L qualification exactly.

| First scored0:0 window | Clocks | I full searches | D full searches | Exposed bank-wait union | Fills / invalidates / lockdown writes |
| --- | ---: | ---: | ---: | ---: | --- |
| Matrix | 45,073 | 160 | 801 | 1,904 (4.224%) | 0 / 0 / 0 |
| Transpose | 3,560 | 0 | 3 | 6 | 0 / 0 / 0 |
| Triangle | 23,520 | 258 | 225 | 964 (4.099%) | 0 / 0 / 0 |
| Full frame | 71,259 | 0 | 73 | 144 | 0 / 0 / 0 |
| Halfword tail | 1,332 | 0 | 3 | 4 | 0 / 0 / 0 |
| Byte tail | 1,647 | 0 | 4 | 6 | 0 / 0 / 0 |
| Original Thumb JPEG | 84,353 | 796 | 1,219 | 3,972 (4.709%) | 0 / 0 / 0 |

I/D waits count LOOKUP-state fetch/data holds; walks, installation and cache
waits are separate. They can overlap, so only their union is quoted as a
combined blocking count. These are observed stalls, not an additive recoverable-cycle
budget. Search starts/results can straddle a timing boundary, so one more
search start than in-window completed hits is expected in several cases.
Whole-run counters include cold setup fills and all mutations, not just scored
windows: for example matrixI/D searches1,133/5,701 and fills2/3; JPEG
5,575/8,758 and fills2/4. Complete per-window/profile and whole-run records remain
in the machine receipt. Directed suites exercise substantial mutation traffic:
permission coverage alone issues793 full searches,777 fills,776 invalidations
and one lockdown write while preserving3,092 hot permission checks.

The checked two-mapping path therefore shields many accesses but does **not**
make full searches negligible. A blanket extra clock at every full search would
matter. The corrected row audit finds every scored matrix/triangle/JPEG main-bank
hit in **row0, entries0–7**. The candidate starts with that row but can search
all eight rows; it neither shrinks the TLB nor uses a benchmark address.

The first observer sampled `selected_entry` after the old hit vector cleared,
reporting its default row7. That row histogram was caught and discarded before
selection. Corrected observers register the selector on `compare_valid`, then
associate it with the following result. Independent corrected control audits
and the candidate agree. Initial search/mutation/wait counters were valid;
the initial row histograms are explicitly excluded from the decision.

No new whole-phone boot was run. Old walk counts from a different boot model
are not treated as current full-search frequency or a measured boot overhead.

## Selected design and architectural schedule

The implementation stays under `tests/cpu/tlb_area/`; production is untouched.
It overlays only seven files on exact5L: bank, TLB controller, I/D wrappers,
Top, Core and CP15. The ordinary CPU arithmetic/shifter/issue implementation,
cache capacity/ways/ports and78MHz PLL are unchanged.

Each bank has eight192-bit BRAM rows containing eight24-bit tag/kind records.
A native byte-enable mask writes only the selected24-bit lane. Existing
valid/preserved bitmaps and base/victim/P state remain; payloads still occupy
all64 entries of the original38-bit RAM. Every row supports section, large,
small and tiny mappings. Lookup order and first-hit priority remain ascending
physical slot order, with no direct-mapping restriction.

On lookup acceptance, row0 is synchronously read and the MVA captured. Eight
comparators inspect that registered row. On a hit, the eight-way selector drives
the existing synchronous payload RAM and publishes a registered bank result.
A first-row hit takes the same **two sampled edges** as the original bank;
subsequent rows add one edge each. Exhausting row7 returns a true miss.
Permission publication remains in the unchanged controller task after the bank
result; no RAM output bypasses directly into CPU completion.

Fill captures its complete mapping, target and preserve state. Eight row scans
collect an overlap mask using **both coverage directions**. Only the final
commit writes the tag/payload, applies the mask, sets valid/P and advances the
victim; partially scanned entries are not prematurely invalidated. A TTBR/MMU
context-cancelled install performs no commit. All-invalidate still preserves
P entries, while MVA invalidation scans mapping coverage and removes matching
P entries too. Lockdown base/victim/P and wrap-to-base semantics remain.

One older mutation drains before a queued CP15 mutation executes. A busy signal
is connected through both wrappers to CP15; its new wait state includes the
registered command pulse, preventing early completion before bank acceptance.
Consequently the one-entry pending command cannot overflow under the actual
serialized caller. An assertion rejects a caller that ignores this contract.
The TLB controller waits for a fill's overlap scan/commit before publishing its
local mapping. Its old rule discarding both local mappings on a main-table fill
is explicitly retained at the delayed publication edge.

## Measured performance and exposed costs

The final source passes both0:0/2:9, five scored windows and two identical
repetitions. All six original medians and **all scored raw window counters**
match5L, with original retirement/oracle checks and six corrupted-output controls.

| Original work, both profiles unless shown | Exact5L | Banked candidate |
| --- | ---: | ---: |
| Matrix | 45,073 | 45,073 |
| Canonical transpose | 3,560 | 3,560 |
| Triangle | 23,520 | 23,520 |
| Frame0:0 /2:9 | 71,259 /201,302 | 71,259 /201,302 |
| Halfword /byte tails | 1,332 /1,647 | 1,332 /1,647 |
| Native Thumb JPEG | 84,353 | 84,353 |
| Original forward /reverse512-pixel spans | 34,995 /34,920 | 34,995 /34,920 |
| One-line /eight-line streams | 343 /499 | 343 /499 |

Game output/guards/source/stack,10,240 retirements,512 ordered actual RAM
mutations and byte enables remain checked. All256 stream starts/retirements
remain; the favorable interior is still224 useful starts in224 clocks.
Cold setup and later rows are **not free**. Complete six-kernel wrapper runs
add40–112 clocks, including setup, warm-ups and output checking. Triangle2:9
also fetches two additional untimed instruction lines; scored traffic is
unchanged. Complete JPEG runs add58/48 clocks at0:0/2:9. These whole-run deltas
are retained separately rather than counted as zero-cost initialization. The randomized/direct bank comparison
observes lookup response latencies2–9 edges;537 of867 queries exercise the
nine-edge path, including misses. Mutations show292 eight-clock drains and
queued cases up to14 additional drain clocks in that fixture. These are actual
unit observations, not an assumed zero-latency scan.

Matched actual-CPU diagnostics quantify other costs at0/3 memory waits:

| Complete diagnostic program | Control0 | Candidate0 | Added0 /added3 |
| --- | ---: | ---: | ---: |
| MMU/FCSE | 94,797 | 94,925 | 128 /134 |
| TLB lockdown | 94,887 | 95,001 | 114 /99 |
| Two local mappings /eviction | 99,836 | 99,900 | 64 /61 |
| Translated prefetch | 100,555 | 100,635 | 80 /90 |
| Instruction TLB write ordering | 727 | 796 | 69 /65 |
| Data TLB write ordering | 381 | 455 | 74 /56 |

The short data ordering program is **19.42% slower at0 wait**; do not hide that
behind the long page-table setup in other diagnostics. It is a mutation/miss
stress case, while measured warm application work is unchanged. A populated
OS TLB can place entries in later rows; boot/OS cost remains to be measured
before production adoption.

## Correctness and failed approaches retained

Five existing unit suites pass: all64 mixed-size slots/65th replacement,
lockdown/wrap/preservation/all-and-MVA invalidation, page attributes/fine tables,
lookup/walk ownership, external aborts,3,092 permission checks and dual local
mapping lifetime/eviction. A separate original-table comparison passes **867
queries**, including329 later-row hits,50 queued mutations and50 cancelled
installs, twice with poisoned same-row mixed-port reads. A deliberately truncated
eight-entry table fails the unchanged oracle. No physical slot was removed.

Twenty-two matched actual-CPU diagnostic runs pass. Additional proper core-peer
stimuli pass FIQ store/return, SWP permission abort, translated prefetch and
buffered-write/TLB-walk ordering. The banked miss can let a short buffered write
drain before a walk begins: the strong overlap assertions remain enabled, using
15/31 data waits and63/127 instruction waits to force actual overlap. An earlier
FIQ attempt used a board harness without FIQ stimulus and timed out; the proper
core peer passes. Neither harness correction changes RTL or waives an assertion.
The5L flag/predicated-writer/IRQ/precise-fault/MMIO/cold-load safety guest passes
twice at0:0,2:9 and0:97 on the candidate.

The initial delayed fill forgot the old local-mapping discard rule; the dual-slot
unit caught it and the final controller preserves it at `INSTALL_WAIT`. Atomic
overlap-mask commit also prevents a cancelled install damaging prior mappings.
Strict Verilog-2001 elaboration caught one forward declaration accepted by
Verilator. The final file moves that declaration and was requalified; the new
bank passes `iverilog -g2001`. Production files were left untouched; no donor code was imported, and no
hardware access, donor run or CI search was performed.

## Resource estimates, headroom and matched-fit plan

**Measured candidate ALMs/registers/LABs/M10Ks/timing are unavailable.** No host
`quartus_sh` or configured trusted Quartus installation was found in the existing
build image; no tools were downloaded and no CI was launched.

At source level, one bank changes **1,744→324 declared state bits (excluding unrolled loop indices and RAM implementation)**; across
I/D that is **−2,840 source bits**. The1,536 tag/kind bits per bank move to RAM;
new snapshot/queue/overlap-mask/control state is included in324. Those are not
fitted register counts. The explicit tag RAMs add3,072 logical stored bits.

A conservative planning envelope is **1,000–2,500 fewer ALMs across both banks**,
not a mapped result or a guaranteed whole-design subtraction. Native packing
suggests roughly **+10 M10Ks** for two192-bit rows; reserve up to **+16** pending
actual packing. Relative to502/553, that is **512–518 used and35–41 remaining**.
Reject a soft-memory implementation or unexpectedly fragmented mapping rather
than silently spending the remaining51 blocks. MMC's+3 alternative would leave
48, but its projected ALM saving is materially smaller. No LAB or routing-register
saving is inferred from declared storage.

The new timing path is tag-RAM output→eight mapping compares/priority→payload
RAM address. It merges comparison and small selection after a synchronous tag
read; locality is improved but104MHz closure is **unverified**. Row control,
byte-enable/write-data selection, atomic valid-mask commit, cancel and bank-busy
fanout must be examined. The existing live checked-context/ACK path identified
in5K is not claimed fixed by this area work. The physical PLL remains78MHz and
104MHz remains the design objective, with no new exceptions or multicycle claim.

A concrete physical qualification is a **serial matched pair**:

1. Freeze the178 selected non-experiment inputs from the verified5K fit; retain
   device, seed42, debugger enabled, physical78MHz PLL, Quartus17.0.2 and all
   timing/SDRAM-I/O settings. Stage copies under `build/fit/`; use no worktree,
   production edits, public push or CI merely to search.
2. Control is exact offline5L; candidate is that same source plus this bank
   overlay. The5K routed report is the actual resource anchor, but a5L control
   fit is necessary to attribute bank savings independently of unfitted5L.
3. Collect selected-input/module manifests, direct and whole ALMs needed/placed,
   registers including routing replication, occupied LABs, inferred hard RAM
   names/widths/ports and actual M10Ks. Verify both64-entry tables and unchanged
   cache geometry. Check the planned+16-block budget against553.
4. Compare all78/104 slow/fast setup and hold corners, the new tag→payload path,
   hot permission/ACK cone and all16 SDRAM DQ I/O registers. No Fmax is inferred
   by subtracting logic or the old13.073ns path. Only then decide promotion or
   a revised area design, followed by boot/OS qualification.

The warm performance evidence and architecture checks justify **retaining** the
candidate for that physical measurement. They do not establish the ALM target
or complete phone correctness. Production/master/public history,5L's separate
reference, rejected5M and other chats' runs remain intact. Only own completed
compiler/frozen-input/private-derived outputs are cleaned after compact receipts.

[Reproduction and run inventory](../tests/cpu/tlb_area/README.md) ·
[Resource, frequency and qualification receipt](evidence/tlb-area-20261117.json).
