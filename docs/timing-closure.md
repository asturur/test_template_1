## 2026-11-08: pass14 improves to80.17MHz; reset distribution becomes visible

Run42439233437 /9e80d10148fcc18fcdf889935bc323291706d142 compiles/fits
successfully, then fails only the timing gate. Reported core Fmax80.17MHz
(previous68.31,+11.86/+17.36%); core setup-1.945ns (previous-4.622,+2.677ns).
TNS-4732.980ns versus-35764.692:86.77% less negative. Quote reported Fmax
and setup separately; neither establishes104MHz sign-off. HDMI setup+.607ns;
all reported hold/recovery/removal/pulse checks pass (global minima+.245,
+3.820,+1.118,+.961ns). ALMs30,793/41,910 (73%, down2076), registers41,429
(down4432), M10Ks462/553 (84%, up4). Fitter confirms each ICU bank is one
2048-bit M10K; low48 pads to64. Artifacts/reproducible endpoint audit:
`scratch/timing-closure/pass14-42439233437/analysis/`.

Worst1000 functional endpoint groups, sum1000:

| Area | Paths | Worst slack ns |
| --- | ---: | ---: |
| Cache metadata/tag flags |284|-1.789|
| Cache write-buffer enqueue/storage |250|-1.412|
| ARM CPU decode/issue |136|-1.538|
| NOR flash |86|-1.887|
| Sparse CAM |70|-1.399|
| DDR transport |43|-1.328|
| DSP mailbox hypothesis/MDI |39|-1.576|
| UEM CBUS |22|-1.379|
| UPP timers |17|-1.482|
| SDRAM transport |13|-1.430|
| LCD framebuffer readout |10|-1.457|
| Diagnostic observation |8|-1.334|
| Other cache controller/refill |7|-1.132|
| Test SIM/card model |5|-1.945|
| NOS I/O model |3|-1.629|
| UPP interrupt controller |3|-1.626|
| CPU bus response/fault |2|-1.470|
| Peripheral response boundary |2|-1.305|

Important source-versus-destination distinction: **all277 cache dirty-flag
endpoints start at loader.slot_valid[0]**, not the cache hit/victim lookup.
284 total paths start there (277 dirty flags,5 test-SIM,2 peripheral response).
The first two LUTs form the top-level reset/readiness cone (Template.sv reset
includes !loader_valid); its factored net has14,547 fanout. The worst path
continues through combinational test-card response construction,10 levels,
10.634ns data delay. The fitted net happens to inherit a sparse d_regs name;
it is not evidence that the sparse CAM owns the reset distribution.

The next independent worst family is flash (-1.887): bridge address decode
traverses ICU/owner priority and brd_claim exclusion into flash_start, then
NOR command/data enables. Source logic confirms mem_req excludes the aggregate
board/DMA claim even for disjoint NOR addresses. This is ownership routing,
not actual NOR chip speed. The write-buffer routes include stored-address
comparisons ->choose_refill ->new_group (fanout398) ->entry data/enables;
221 paths start at two buffer-address registers. ARM decode paths frequently
start at post-ALU signed-halfword control (160 total endpoints across groups).

The four prior targets worked: ICU-extra483→0 endpoints, CPU response/fault
35→2, diagnostics59→8 (no trace-readout /6 family), old read_victim_valid/dirty
snapshot endpoints→0. Current cache dirty writes are a different reset-driven
family. Shared named ACK/unmodeled route union38→3; absence in this ranked
subset does not prove a family meets104MHz. Sparse51→70 and buffer83→250
counts rose as more severe paths disappeared; their worst slacks improved
(-2.743→-1.399 and-3.320→-1.412 respectively), so counts alone imply no regression.

Recommended next sequence: (1) register/localize the reset/readiness release
with coherent per-chip cancellation and preserved warm/cold semantics; do not
mask reset paths with timing exceptions. This covers the shared284-path source
and worst SIM path, but SIM response construction may still need its own stage.
(2) Give NOR/SDRAM a captured regional owner so disjoint memory launch does not
traverse all peripheral claims; preserve actual overlap and unsupported-access
fault rules. (3) Rework buffer hazard/refill/enqueue control boundaries, then
review remaining CPU halfword-to-decode paths. Avoid rewriting cache tag lookup
again based solely on dirty-flag destination counts. No RTL edits, tests, commit,
push or new FPGA build were initiated by this timing review.

## 2026-11-08: implement the four post-pass13 targets

The peripheral owner and each local data/error cone now cross the same response
edge in internal-CPU mode. Separate per-device result registers feed an explicit
balanced masked-OR tree; accepted effects are suppressed while that response is
pending, including CBUS/MDI. The bridge retains the matching request record.
This adds one peripheral response clock; ICU bank reads additionally require
synchronous BRAM readiness. ICU low/DMA/epbus use three explicit M10K wrappers
with64-edge warm-zero scrub after reset release, independent of cold init_done.
Only the actual DMA-shadow/LCD owners receive their overlap exclusions.

Cache victim flags use the existing first-stage flag snapshot and victim index
in stage2, splitting segment and victim selection without increasing lookup
latency. Diagnostic readout uses fixed parallel address matches/reductions in
place of /6 and %6, preserving its one-clock NGD/export contract. No new timing
exceptions or slower physical clocks. Diagnostics retain the previous unconditional
sample pipeline and coherent delayed history qualifiers.

The top-level linter's V3Gate internal error on a packed registered return vector
was avoided by independent local word/owner/error registers and constant tree
slices. No linter optimization waiver was added. Combined validation and fresh
boot evidence are recorded in status.md and
`scratch/timing-closure/pass14-combined/`. Await the next Quartus fit to measure
all clock domains, area/M10Ks and the new worst1000 subset; the latest measured
baseline is still run42433854189 (68.31MHz, setup-4.622ns).

# MiSTer timing closure

## Thirteenth fit: peripheral read responses and register banks dominate

Reviewed42433854189 /6f34b89. Artifacts and reproducible endpoint audit:
`scratch/timing-closure/pass13-42433854189/analysis/`. Relative to d3364ea,
reported core Fmax **68.31MHz** versus69.19 (-.88), setup **-4.622ns** versus
-4.837 (+.215ns), TNS **-35764.692ns** versus-48910.486 (26.88% better).
ALMs32,869 (-576,78%), registers45,861 (+692), M10Ks458 unchanged (83%).
HDMI setup+.324ns; global hold+.244ns, recovery+3.544ns, removal+1.052ns,
pulse+.961ns. Compilation succeeds; timing gate fails. Quote the separately
reported Fmax and slack as-is; do not derive a new clock guarantee from either.

Target groups improved despite the small worst-path movement: upload RAM120
->2 endpoints, sparse CAM286 ->51 (worst now-2.743), LCD framebuffer103 ->0,
and old write-buffer pending-word/query arithmetic has no named routes in the
export. Counts refer to different ranked subsets, not proof that removed paths
meet104MHz. No new LCD or cache-pipeline rewrite is justified by this report.

Current functional endpoint counts (sum1000): ICU-extra banks483 (-3.601),
cache write-buffer enqueue/storage83 (-3.320), UEM/CBUS58 (-4.208), diagnostic
observation/readout59 (-4.622), NOR flash55 (-3.385), MDI51 (-3.483), sparse
CAM51 (-2.743), regional staging RAM40 (-3.411), timers37 (-3.269), CPU bus
response/fault35 (-4.437), remaining cache victim/tag/controller7 (-4.552),
other CPU/platform/control41 (-4.030). Shared error/ACK named-route union38
(33 ACK,6 unmodeled,1 overlap):bridge30,monitor4,diagnostics1,video3; no device
write destinations. Synthesized wb_dat_i-named LUTs also appear in address-
decode write paths; their names alone do not establish read-data feedback.

Recommended decision: next major refactor is **peripheral register/read-response
architecture**, with small independent victim-selection and diagnostic-readout
fixes. Keep coherent request/destination/data/error records and local effects;
registering a giant global mux again would just move its unchanged depth.

1. **Local read responses.** Worst path is address ->SIMIF selection ->large
   wb_dat_i mux ->monitor.sample_data,13.531ns/10 levels. Bridge master_read_data
   has another long boot/timer/board mux path at-4.437ns. Decode destination once
   and return a coherent local ready/data/error result through a registered
   owner/response boundary. Diagnostics should observe that registered response,
   with matching request/fault context, instead of adding their own always-live
   read-mux sampling burden. Optional diagnostic removal alone won't fix the
   real CPU return path. Preserve state-dependent claims, masks and read effects.
2. **ICU-extra register-bank storage/command ports.**483 paths target low_regs,
   dma_regs and epbus_regs. Their176x32 stored words are currently resettable FF
   arrays with variable reads/writes. Move memory-like latches to explicit BRAM
   with synchronous ready/readback and a reset-scrub protocol; keep true control
   flags/small probe state as registers. Preserve warm-reset zero semantics and
   avoid init_done/core_reset/scrub deadlocks. There is also a remaining global
   !lcd_dma_claim/direct-collision gate on the entire peripherals.commit in UPP;
   scope those exclusions only to their actual overlapping shadow-DMA/LCD owner.
   Do not reintroduce aggregate fault/ACK write gating. Use fitted-route and
   ownership tests to distinguish shared decoder LUTs from actual dependencies.
3. **Cache victim context: small, latency-preserving opportunity.**3 paths run
   CP15 alignment/ack/request selection ->bank_mva ->nested segment/victim/flag
   mux ->read_victim_dirty/valid (-4.552ns). Existing read_valid_bits,
   read_dirty_bits and read_victim_way already snapshot the same source edge.
   Evaluate selecting compare_victim_valid/dirty from those captured arrays in
   the second stage instead of selecting both segment and victim flags on the
   live-MVA edge. This can split the mux without another cache lookup cycle;
   verify snapshot/collision/maintenance equivalence and warm ADD throughput.
4. **Diagnostic /6 mapping.**4 routes, worst-4.188ns, still traverse a full
   divider into trace read addresses/selection. Replace with bounded decode or
   a staged table; preserve NGD layout and explicitly retime the export read
   contract if needed. This is readout, not the completed fault-capture work.

After those, CBUS accepted-write validation feeding alarm decrement/start and
MDI forwarded-pointer/tick logic remain independent limits. Do not assign
physical slower clocks or add timing exceptions to conceal these model paths.
BRAM bank conversion could improve both timing and FF/LUT area; resource use
and all clock domains must be checked in the next authorized full fit.
No RTL changes, tests, commit, push or FPGA build were initiated by this review.

## Thirteenth implementation: precomputed write-buffer line membership

Point4 is separate from LCD712c811 and its ordering correctiondb992b9.
Each1..4-word contiguous buffer group spans at most2 cache lines, including
32-bit address wrap. Its first tag is already stored in the base address;
new `last_line` metadata captures the final word's27-bit line tag at allocation
and the incoming word's tag on a validated adjacent merge. Hazard queries now
compare these two tags per active physical slot, without per-word address
addition or length selection. Query/response latency, FIFO size, merging,
byte-enable/data ordering, errors/retries and conservative retired-word hazards
are unchanged. No new cache stage, allocation policy or timing exception.
The only new metadata is4x27 bits; no inferred memory or storage migration.

Independent logical FIFO/per-word hazard scoreboard first passes the old RTL,
then the new RTL with identical coverage:12021 cycles,1343 new groups,329
merges,497 crossings,163 wraps and1998 bus errors. It checks FIFO bus beats,
readiness and exact line membership before/after updates, unrelated lines,
simultaneous merge/retire/enqueue, backpressure, zero/partial masks and reset.
Existing directed16-word-buffer tests also pass. Full CPU/cache regression with
UPP bridge finishes **120 PASS +1 expected direct-map XFAIL** (one new hazard
scoreboard beyond the previous119); warm ADD remains1 cycle at0/3 waits.

Combined final-hardware CPU integration and real-SDRAM5M boot pass, including
LCD queued commands/local faults and completion-after-pixel assertion. Early
boot remains PC00006170,306874 transfers,12 known fetch faults,zero data faults;
all845 board events/cycle stamps match the baseline. Combined result logs were
produced with this write-buffer source and the corrected LCD/DMA hardware,
then preserved from `pass12-lcd-queue/{boot,board}-order-final.log` under
`scratch/timing-closure/pass13-write-buffer-lines/`. The write buffer was briefly
restored to its previous version to separately boot-verify the LCD-only follow-up,
then restored byte-for-byte (source SHA256
`11b703464faf739b6524dc35b1114b97cb24a75a00cf3e85eca0f74882acfd85`).
Final buffer/integration/top checks reuse the same implementation. No old long
checkpoint was loaded; no new logo claim. Last measured fit remains69.19MHz/
-4.837ns; this targets the87 write-buffer-query routes from that subset, not a
claim of87 passing paths. No FPGA build dispatched or monitored.

## 2026-11-08: staged sparse CAM with selected-device waits

Following regional commitd329a1d, the sparse model now captures request fields,
registers parallel match/free bits, registers the priority-selected slot/result,
then reads payload BRAM before ready. Stable requests reach ready after4 rising
edges; authorized writes publish tag, valid and payload together on the next
edge. Lookup works with commit low. A terminal held request cannot execute twice;
identity changes/withdrawal cancel pending work. Warm reset retains the table
but quarantines a canceled held request; cold reset clears validity. Only the
selected non-trace0d device waits. Exact contract: `docs/peripheral-ownership.md`.

Full-address matching, lowest-index priority, capacities1/2/3/5/64, byte merges,
zeroed allocation bytes, read misses and full-table faults are preserved. Unit
scoreboards test4000 randomized requests per capacity, sustained authorization,
arbitrary commit waits, same-address dependencies, exact write counts, and
reset/cancel/replacement at each occupied stage. Board tests verify trace
exclusion under full CAM and immediate unrelated upload access after cancel.

Peripheral/fixture/diagnostic units, actual CPU SIM/DMA/IRQ/FIQ/CAM-overflow and
sticky-fault integration, top elaboration, source graph and formatter pass.
Fresh real-SDRAM5M boot: PC00006170,306874 transfers,12 known fetch faults,
zero data faults; all845 board events/121 writes and cycle stamps exactly match
regional baseline. This early boot contains no0d accesses: CAM coverage comes
from the directed/CPU integration tests, not a new cold-logo claim. Evidence:
`scratch/timing-closure/pass11-sparse-cam/`.

Full CPU/cache suite:119 PASS plus one expected legacy direct-map XFAIL;
warm ADD remains1 cycle at0/3 waits. Both restructures are verified separately.

No FPGA build or timing claim. Last fit remains69.19MHz/-4.837ns; area and timing
of both restructures need the user's next fitted reports. Cache, firmware,
storage, clocks/constraints and permanent checkpoint pairs remain unchanged.

## 2026-11-08: regional peripheral RAM ownership decoding

Replaced the shared dedicated-claim exclusion on staging-RAM writes with
regional qualifiers. Upload0c03 and aux0c06ff no longer depend on boot/scratch
comparisons. NOS0c10 excludes only MDI; GPIO15 excludes actual SIM/NOS/loopback
claims; aux12/14 retain only boot/MDI overlaps; NOS4K excludes its45 boot latches.
The ownership map is in `docs/peripheral-ownership.md`. Dedicated response
priority, SIM injection snoops, keypad overlays, LCD DMA exclusion, byte-lane
rules, read readiness and warm/cold behavior remain unchanged. No latency added.

The connected-child ownership sweep covers131072 word addresses plus896
operation/lane/config overlap cases. Peripheral units, fixtures, board CPU
SIM/DMA/IRQ/FIQ/fault tests, top elaboration, source graph and formatting pass.
Fresh real-SDRAM5M boot: PC00006170,306874 transfers,12 known fetch faults,
zero data faults. All845 board events (including121 writes and cycle stamps)
are byte-identical to the new-cache baseline. Evidence and reproducible source
cone/trace checks: `scratch/timing-closure/pass10-regional/`.

Full CPU/cache suite:119 PASS plus one expected legacy direct-map XFAIL.
Warm ADD remains1 cycle with0/3 memory waits.

No FPGA build dispatched. Timing/resource effect is unmeasured; the last fit
remains69.19MHz/-4.837ns. Cache, firmware, storage and permanent checkpoints are
untouched. Sparse CAM remains the next separate change.

## Ninth fit: cache pipeline succeeds; regional peripheral decode is next

Reviewed42417251076 /d3364ea (fcb7dc2 cache pipeline +110b22d fixture refinement).
Reports under `scratch/timing-closure/pass9-42417251076/`; exact grouped counts
and reproducible script in `analysis/`. Core Fmax **69.19MHz** versus68.32;
setup **-4.837ns** versus-5.021 (+.184ns), TNS **-48910.486ns** versus
-56669.384 (13.69% improvement). ALMs33,445 (+1,176,80%), registers45,169
(+1,841), M10Ks458 (+2,83%). HDMI setup+.026ns; global hold+.199ns,
recovery+3.417ns, removal+1.320ns, pulse+.961ns. Compilation succeeds;
timing gate fails. Small full-core Fmax gain does not mean cache rewrite failed.

Old cache line/dirty/valid commit-path destinations are **absent** from top1000.
Direct cache destinations798 ->**74**:64 refill-data capture paths,7 write-buffer
payload/enables,3 victim valid/dirty snapshot paths. This subset does not prove
cache104MHz closure. Another23 cache-origin paths end in CPU bus merger.
All64 refill and23 merger paths traverse write-buffer `pending_words` hazard
logic. The new compare/commit boundaries exposed previously hidden limits.

Functional destination grouping (sum1000): sparse CAM286 (-4.465ns), peripheral
staging RAM166 (-4.837;upload120/NOS41/aux3/GPIO2), ICU/config106 (-3.899),
LCD framebuffer/forward104 (-4.223), timer/NOS78 (-4.093), cache74 (-4.688),
flash50 (-3.977), CPU bridge response32 (-4.695), diagnostics29 (-4.738),
MDI25 (-4.028), CPU bus merger23 (-4.444), keypad18 (-3.972), SDRAM arbiter7
(-3.930), CPU fetch/issue2 (-3.874). Named error/ACK union25, all `unmodeled`
(no named wb_ack); sparse CAM logic occurs on311 routes. Counts overlap with
destination groups and are not a claim of that many independent bugs.

Recommended next restructures, in order:

1. **Regional peripheral ownership/write commands.** Worst route: captured
   bus_address[3] fanout1245 ->boot scratch-claim exclusion ->generic GPIO write
   ->upload BRAM WE (14.612ns data,10 levels). Upload0c03xxxx cannot overlap
   the boot-register/scratch windows. Replace the global `dedicated_claim`
   exclusion with per-region ownership: upload,0c10 NOS/MDI, GPIO15, aux,
   0c004 scratch, etc. Keep only real overlaps local. Stage a coherent regional
   command/address/data/mask if needed, with exactly-once commit/response;
   don't rebuild a global ACK->all-side-effects chain.
2. **Stage the temporary sparse-register lookup/allocation.**286 destination
   paths are CAM comparison ->miss/capacity decision ->allocation/tag write.
   Capture request and matched/free-slot decisions before updating tag/payload.
   Selected-device waits only; retain full-table fault, existing-address writes,
   byte masks and cancellation semantics. Do not replace it with aliasing RAM
   or pretend it is verified phone hardware. Address nets also feed over1000
   loads; regional capture can reduce that physical fanout.
3. **Local LCD transaction queue.**103 framebuffer RAM endpoints plus1 forward
   register. Local transport `lcd_bad` decoding still feeds panel command/
   direct_pixel decode ->BRAM WE in one cycle. Capture the validated LCD
   transaction payload, qualify DMA/direct collisions and apply it next cycle.
   Preserve command ordering and partial display; don't guess a panel clock.
4. **Cache write-buffer hazard metadata.**All87 refill/merger routes compute
   queued-address+word-offset ->line compare ->issue/ACK ->refill capture.
   Precompute line membership when enqueueing/merging groups, not on every query.
   Each contiguous1..4-word group spans at most2 32-byte lines; stored first/last
   line tags plus valid membership can replace16 runtime address additions.
   Preserve simultaneous enqueue/merge/retire/error behavior, cross-line groups,
   and no false-negative hazard. Existing conservative retired-word stalls can
   remain. Don't redo the successful tag/data pipeline for this separate issue.
5. **Diagnostic readout arithmetic.**The second-worst overall path is now
   `read_word` offset ->combinational `/6` divider ->trace RAM address (-4.738).
   This is export/readout, not the already pipelined fault capture. Replace
   arithmetic with a bounded decode/table or staged mapping and explicitly
   preserve/retime the diagnostic-export read contract and unchanged file format.

Timer same-cycle write/clear/rearm plus counter updates (77 main timers),
MDI forwarded-pointer comparisons (25), and reset/error/access-window fanout
(62 ICU destinations on a reset-origin route) are later local targets. Do not
infer that all need slower physical clocks or add broad false/multicycle paths.
Maintain tests, source/QIP correctness, state coherence and cold boot evidence;
future fits must validate both improved target groups and other newly exposed
limits. No RTL edits, commit/push or build dispatched by this analysis request.

## Ninth implementation: registered cache lookup and coherent commit

Both I/D instances retain 16 KiB, eight segments, 64 ways, 32-byte lines,
MVA tags, stored physical writeback addresses and two dirty halves. The shared
bank now separates these paths:

1. The tag RAM reads a segment while registers snapshot its valid/dirty bits,
   replacement index and victim flags. This removes the live segment flag mux
   from the post-RAM compare path.
2. Parallel comparisons register a 64-bit match vector with the request MVA,
   dirty bits and victim physical address. The existing balanced priority tree
   and one-hot priority selection consume this record, preserving lowest-way
   duplicate priority.
3. A mutation pulse captures a complete commit record. The bank records segment,
   way, byte enables and payload; tags record MVA, physical address, selected
   ways, operation qualifiers and replacement mode. Refill versus store selects
   the payload from the operation type, independently of permission. Permission
   qualifies the recorded write mask. Live inputs cannot redirect a pending write.
4. The following edge writes line RAM, tag RAM, physical address and flags
   together. Replacement advances on this edge. Reset, global invalidation,
   lockdown or indexed maintenance suppress both halves of a pending mutation.

Flags remain resettable registers; storage primitives and geometry are unchanged.
This deliberately avoids a new flag-RAM read/modify/write and collision protocol.
The full-cache associative lookup is still serialized. Tag result latency is two
edges instead of one; selected data is available after a third edge. The debug
physical-hit query still follows the tag result by one edge. Indexed scan latency
is unchanged. Direct callers must pulse mutations, drain the commit edge, then
allow a fresh read/compare/data sequence before consuming results; the focused
fixtures explicitly wait four edges after a mutation pulse. Collision-cycle RAM
outputs are not architectural results and are not used by the controller.

`cache_access` inserts LOOKUP_WAIT and MAINT_WAIT, and reports stores only on
STORE_COMMIT. A buffered store is enqueued once before this completion stage.
`cache_refill` inserts COMPARE_WAIT and COMMIT; its done pulse follows the actual
commit edge, then the access controller waits for a fresh lookup. Cached bus
errors still retain/retry victims; write-buffer acceptance and bus ownership
rules are unchanged. The adapter consumes ready/response/done handshakes and
needs no fixed-cycle change. SWP lock, abort and MMU permission logic is unchanged.

Streaming requests carry pending/address context through the extra comparison
stage. The two streaming line slots remain separate from the full cache; a
serialized access or maintenance flushes them, and a completed read can prime
one slot. Cold latency increases, while a resident streaming hit retains the
existing one-instruction-per-cycle path. ZAP patch 0041 advances lookahead from
eight to twelve bytes for the extra stage. The first implementation left it at
eight bytes and failed the unchanged warm ADD assertion (five-cycle intervals
at a line boundary); the corrected version measures min=max=1 over 120 warm
samples with both zero and three memory waits. Keep that failed attempt as a
regression explanation, not as accepted throughput.

Validation evidence is recorded under `scratch/timing-closure/pass9-cache-pipeline/`.
Fresh real-SDRAM 5M boot passes at PC `00006170`, 306874 bus transfers,
12 known speculative fetch faults and zero data faults. Baseline was PC
`00006160` and 326761 transfers. The cycle-free board trace has 845 events versus
962: all 121 writes match in order and every field; the full current sequence
is the baseline sequence with exactly 117 reads of `0x0c004778` / `0xe18030b4`
removed. This is consistent with changed speculative instruction-fetch timing,
not byte-identical execution. `compare_boot.py` and `boot-comparison.json`
retain the comparison and first difference. This is early boot only, not a new
cold-logo result or validation of the peripheral model against a phone.

The instruction-TLB ordering fixture initially lost its required overlap.
Tracing showed the descriptor queued at cycle2592, accepted at2631, and the
instruction walk starting at2693, after intervening cold sequential fetches.
Raising all memory waits from20 to40 or100 did not restore the hazard. The
fixture now explicitly prefetches four sequential lines before issuing the
buffered descriptor store and inserts four NOPs before the branch. Its original
20-cycle delay, nonzero-overlap assertion and descriptor/result checks are
retained; it also passes at100 waits. Prefetching without the NOPs exposed an
instruction-walk/store-enqueue race that also fails with unchanged baseline RTL
(603fd8b); that is not repaired by this cache change. The fixture ensures its
intended older-write ordering scenario rather than relying on cold-fetch timing.
The warmed no-NOP reproducer and baseline failure are retained as
`order-prefetch-abort.S` and `icache-order-warm-baseline.log`; separately audit
whether software synchronization or CPU-side ordering is required there. Temporary
trace instrumentation was removed; `order-full.log` preserves the diagnosis.

Validation completes with119 CPU/cache PASS and one expected legacy direct-map
XFAIL. The main run passed100 cases before the fixture's missing-overlap check;
`cpu-tail.sh` repeats the corrected fixture and the remaining18 cases using the
unchanged commands from `tests/cpu/run.sh` (`CPU_BUS_BRIDGE=1`). No assertions
were relaxed. Board SIM/DMA/IRQ/FIQ/local-fault integration, fresh real-SDRAM
boot, structural top elaboration, Quartus source-graph preflight, formatting
and exact pinned-upstream-plus-patches verification pass. `summary.json` and
`source-hashes.json` record final coverage/source identity. Implementation is
fcb7dc2, with the fixture adjustment separately committed as110b22d.

The timing consequence is **unmeasured**: no FPGA build was launched. The last
fit remains 8395967, 68.32 MHz and -5.021 ns setup. Added registers and the remaining
selection/enable trees require full fitted setup/hold/recovery/removal/pulse and
resource review. Audit both cache instances across all exported path families.
The separate peripheral staging-RAM ownership path (-4.903 ns in that fit) is
unchanged; cache improvements alone cannot establish full-core 104 MHz closure.
No firmware, peripherals, constraints or historical checkpoint lineage changed.

## Eighth fit: 68.32 MHz, cache transaction-pipeline rewrite recommended

Reviewed completed42411324930 /8395967. Fmax **68.32MHz** versus65.40;
setup **-5.021ns** versus-5.378 (+.357ns), TNS **-56669.384ns** versus
-54599.524 (3.79% worse magnitude). ALMs32,269 (+220), registers43,328 (+121),
M10Ks456 unchanged. HDMI setup+.042ns. Still fails104MHz; Quartus compilation
succeeds and timing gate fails. Reports, classification script and exact counts
under `scratch/timing-closure/pass8-8395967/analysis/`.

Shared error/ACK union is now **11/1000**, all bridge `master_read_data`.
Diagnostic capture endpoints drop315 ->18 (+1 separate video path). No named
`store_commit` routes remain in this top1000; the small edit did remove that
chain, without solving the cache's overall same-cycle scheduling.

**798 cache destinations**: data RAM183 (ICache47, DCache136), valid/dirty
flags546 (dirty396+valid150), tag RAM16, controller53. Other groups: peripheral
staging RAM97, sparse CAM7, bridge26, diagnostic observers18+video1, MMU/
predecode21, memory merger11, instruction FIFO2, CP15/maintenance5, SDRAM
arbiter12, LCD scanout2. All1000 are violated. Subset counts do not establish
whole-design timing or compare identical paths across fits.

Worst route is ICache tag M10K ->64-way match/selection -> bank `fill_commit`
(fanout313) ->256-bit write-data selection -> line M10K data input. Data delay
13.708ns,9 levels. `write_data` and `write_way` incorrectly depend on the late
permission rather than the known operation type; their invalid-cycle values
could be preselected independently. But changing those muxes alone just
exposes the -4.903ns peripheral RAM and -4.827ns metadata paths. A controlled
rewrite of the cache bank/controller transaction pipeline is recommended,
not replacing the whole CPU or changing64-way ARM920 geometry.

Proposed direction: explicit tag/metadata read, registered match/selection,
and registered operation/commit records; choose payload early, publish data
and metadata coherently. Maintain read/store/refill/maintenance hazards and
fast-line streaming throughput. Metadata in BRAM or an early registered
segment snapshot is a design option to investigate, not an implemented fix.
Peripheral RAM has a separate broad ownership-decode bottleneck: address ->
boot claim exclusions -> GPIO write -> BRAM WE; localize ownership by coarse
address region later. Cache-only work cannot certify the complete core104MHz.

User requested a new-cache handoff. Persistent brief:
`scratch/handoff-cache-104mhz.md`. No HDL changes, commit, push or new build in
this review. The prior explicit **no-build** preference remains in force;
user triggers fits and supplies completed links. No104MHz claim without STA.

## Eighth implementation: cache store intent and per-way metadata validation

Cache follow-up is separate from pushed diagnostic commit46a113c. Routed-path
inspection of ef6511b found631 metadata endpoints (534 dirty/97 valid);492
routes include named `store_commit` logic. Worst-4.973ns path is tag M10K ->
global hit reduction -> bank store qualifier -> high-fanout dirty-flag enable.
Evidence `scratch/timing-closure/pass8-cache-local-store/baseline-paths.json`.

`cache_access` now sends a store request without a redundant live-hit term in
the write-through path. `cache_bank` separates store intent from actual data
write: encoded RAM writes still require global hit, while metadata receives
intent and uses its existing per-way priority-selected tag match. Therefore
miss stores neither allocate, dirty nor overwrite the encoded default way.
Reset/refill/invalidate/lock suppression, dirty halves, duplicate-tag priority,
writeback, memory primitives and request/response latency are unchanged. No
new cache stage, extra hit cycle or timing exception. Refill miss validation
is genuine cache behavior and remains; this edit does not promise all631
metadata routes or all492 targeted routes now meet104MHz.

Expanded bank test passes miss-store preservation of every one of64 ways and
empty-mask suppression, alongside tags/dirty-halves/victim/lock tests. Actual
CPU SIM/DMA/IRQ/FIQ/local-fault integration passes. Fresh real-SDRAM5M cold boot
passes unchanged PC00006160,326761 transfers,12 known fetch faults and zero
data faults; all963 board-trace lines match the pre-diagnostic baseline.
Top elaboration and source preflight pass. Full CPU/cache suite with the UPP
bridge enabled finishes **119 PASS +1 expected legacy direct-map XFAIL**. Warm
ADD stays1 cycle at0/3 memory waits. Logs `scratch/timing-closure/pass8-cache-local-store/`.

User requested **no FPGA build**. No Quartus dispatch or timing claim for these
changes; next fitted baseline remains65.40MHz/-5.378ns until measured later.
Do not restore long-run states into this changed executable.

## Seventh implementation: coherent diagnostic capture pipeline

`ngage_debug_monitor` now samples an unconditional PC/instruction/bus payload
record plus event/reset bits before counters and sticky history. ACK/error/
fault qualifiers no longer directly enable the wide context registers.
PC/address/read-or-write-data/flags/reason are all taken from the same sampled
edge; back-to-back events cannot mix requests. Hold preserves an already
sampled event; cold reset flushes pending history. `ngage_diagnostics` uses the
same one-stage fault/payload discipline for independent first fetch/data faults.
Trace-ring timing, readout latency, file format and text screen layout stay
unchanged; history is visible one clock later. Live CPU response/error logic
and peripheral behavior are untouched. No clock/timing exceptions added.

Directed tests pass write/read payload alignment, different consecutive fault
contexts, consecutive fetch/data kinds, sticky first event, warm Hold and cold
flush. Diagnostic text/font/raster, ring export/decoded NGD and actual hps_io
export pass. CPU integration including CAM overflow, rejected LCD header,
SIM/DMA/IRQ/FIQ and sticky first fault passes. Fresh real-SDRAM cold5M boot:
PC00006160,326761 transfers,12 known fetch faults, zero data faults. All963
board-trace lines byte-identical (SHA256
`07f2b1710e027039be4743eccc0226caa992935e13197026015aad15af51a398`).
Top elaboration/format/source checks pass. No new cold-logo claim; old long
checkpoints remain bound to their saved executable and are untouched.
Evidence `scratch/timing-closure/pass7-diagnostic-pipeline/`.

This is bring-up instrumentation, removable/disableable for a final core;
real CPU abort/completion handling is separate and remains required. Commit
and push diagnostic work first, **no Quartus build**, then address cache in a
separate change. Baseline remains ef6511b/65.40MHz/-5.378ns until a future fit.

## Sixth fit: 65.40 MHz, remaining shared routes are observers/responses

Reviewed completed **42405201963 / ef6511b** (includes service loader9d87477
and separate local-validation change). Core worst setup **-5.378ns**, slow
Fmax **65.40MHz**, versus-6.633ns/61.55MHz: +1.255ns/+3.85MHz (+6.26%).
Core TNS **-54599.524ns** versus-94439.842ns,42.19% smaller magnitude.
ALMs32,049 (76%) versus32,507 (-458), registers43,207 versus43,949 (-742),
M10Ks456 versus457 (-1). HDMI setup+.360ns; global hold+.250ns,
recovery+3.373ns, removal+1.348ns and pulse+.961ns remain positive.
Quartus compilation succeeds; timing gate fails. Still not104MHz closure.
Because loader first enters this fit, do not attribute every placement/resource
change exclusively to the local-validation source edit.

Full-route audit of all1000 setup paths (-5.378..-4.226ns), same named-node
method as preceding fit:

| Route marker | Previous | Current |
| --- | ---: | ---: |
| Peripheral `unmodeled` | 991 | 347 |
| Named `wb_ack` | 721 | 210 |
| Either error/ACK marker (union) | 991 | 347 |
| Sparse `d_regs` CAM logic | 801 | 0 |

The210 ACK paths overlap the347 error paths; do not sum them. Remaining shared
paths end **only** in debug monitor280, diagnostic export/capture35 and UPP
bridge response32. **Zero exported shared paths feed peripheral writes**
(LCD/framebuffer/DMA, timers, MDI, staging RAM). Route-name auditing is a
repeatable subset measurement, not a proof about all fitted paths or semantic
logic renamed by optimization.

Worst path now: registered bridge address -> UEM CBUS selected-access bad
checks -> peripheral `unmodeled` -> diagnostic fault qualifier ->
`diagnostics.first_fetch_address` (10 levels,14.294ns data delay). This is a
fault-context capture bottleneck, not a peripheral write enable. The original
cross-device write fanout has been removed from this exported set.
Remaining top1000: shared response/diagnostic347; cache metadata631
(dirty534+valid97, worst-4.973ns); cache bank17 (-4.871); cache-access/merger3;
instruction-cache/fetch2. Cache-family total651; fetch2; sum1000.

Next candidates: pipeline coherent fault/transaction capture in diagnostics
without changing screen contents, simplify selected response/error capture,
and further shorten cache flag enables. Keep PC/address/data/reason from the
same transaction when adding observer latency. No new RTL, commit, push or
build started by this review. Reports and reproducible audit script/JSON:
`scratch/timing-closure/pass6-ef6511b/analysis/`.

## Sixth implementation: local device access qualification

Separate timing commit after loader9d87477. UPP now distributes `bus_access`
from the active captured request (reset/init/error qualified), without using
combinational CPU ACK or aggregate `unmodeled` as a global side-effect enable.
CPU ACK/error/data response and registered invalid-access faults are unchanged.
Each child retains claim/bad checks; SIM alone checks its busy/overflow, GPIO
checks supported lanes and dedicated ownership, LCD exports its locally
validated write strobe. Clock writes no longer consult unrelated validators.
Sparse CAM capacity/lookup affects only that device's state and selected CPU
fault response, not LCD/timer/MDI/RAM write enables. No new clock, exception,
extra bus pipeline stage, firmware patch or default-success response.

Actual LCD DMA owns its registers exclusively, rather than also changing the
legacy ICU-extra DMA shadow. DMA/direct-LCD collision suppresses only that
access until accepted; synchronous GPIO read validity clears at its own ready
edge, and SIM pops cannot repeat while the service pipeline is busy.

Verification passes: actual CPU program fills all64 sparse slots, faults on
new allocation, preserves existing data, then writes/reads a timer while the
table remains full; invalid LCD header faults without changing transport or
panel header. IRQ/FIQ, SIMIF, DMA pixel, SDRAM waits and sticky first-fault
context still pass. LCD transport tests offer invalid operations with the
access window asserted and confirm local suppression against both C++ models.
Full18304-word DMA, board ownership132 pairs, unimplemented chip boundaries,
SIM present/absent, transaction fixtures and warm/cold RAM tests pass. Retained
firmware-DMA trace replay is explicitly SKIP (fixture unavailable), not passed.

Fresh **real-SDRAM5M cold boot**: PC00006160,326761 transfers,12 known fetch
faults, zero data faults. All963 recorded board-trace lines are byte-identical
to the prior run; SHA256
`07f2b1710e027039be4743eccc0226caa992935e13197026015aad15af51a398`.
This verifies the existing bounded stopping point, not a new cold Nokia-logo
run. Frozen billion-cycle states remain untouched and are not restored into
this changed HDL. Logs `scratch/timing-closure/pass6-local-validation/`.

**Diagnostic screen needs no redesign:** PC/opcode/CPSR, completed bus
transactions, wait counts, sticky fault PC/address/reason and text raster remain
observers of the existing response signals. Their directed monitor/raster tests
pass unchanged. They do not authorize device writes. Top elaboration, source
preflight and formatting pass. Next build includes separate loader commit plus
this timing change; measure new slack/Fmax and paths against61.55MHz/-6.633ns.
User monitors CI; no automatic monitoring requested.

## Fifth fit: 61.55 MHz, shared peripheral validation/commit dominates

Completed build42400361438 is **7d80fc6**, excluding the later local service
loader commit9d87477. Quartus compilation/source preflight succeed; action
fails only the timing gate. Reports retained at
`scratch/timing-closure/pass5-7d80fc6/`, functional classification and script
under `analysis/`. Core setup **-6.633ns**, Fmax **61.55MHz**, versus
-9.070ns/53.52MHz: +2.437ns/+8.03MHz (~15%). ALMs32,507 (78%), down1,421;
registers43,949, down1,240; M10Ks457 unchanged (83%). Core setup TNS regresses
from-89226.544 to **-94439.842ns** (~5.84% larger magnitude). Improving the
single worst path does not mean overall timing closure. PLL remains104MHz.
Core hold+.255ns, recovery+6.919ns, removal+1.754ns; global fast hold+.072ns,
recovery+3.409ns, minimum pulse+.961ns, global removal+.980ns; HDMI setup+.087ns.

All1000 exported setup paths still violate (-6.633..-4.959ns), one worst per
endpoint. **11 chosen functional groups /18 destination instance hierarchies**:
MDI/DSP-mailbox hypothesis131 (-6.633); LCD framebuffer/command diagnostics410
(-5.859;408 BRAM pins+2 diagnostic regs); peripheral upload/NOS/aux staging
RAM94 (-5.718;54+31+9); UPP ICU/config74 (-5.592;72 extra+2 ICU); ARM920
D-cache bank6 (-5.538); UPP/NOS timers200 (-5.496;199+1); FPGA debug/trace7
(-5.486;6+1); boot/control17 (-5.448); LCD DMA41 (-5.410); unidentified0x0d
sparse-register model19 (-5.235); bridge response1 (-5.013). Sum1000.
These are destination groups, not11 independent root causes or proven phone
chip timing domains. Staging RAM, MDI and unidentified registers remain models.

**994 launch at UPP bridge address registers; only6 launch at cache tags.**
Full-route substring audit:801 include sparse `d_regs` CAM logic,991 include
peripheral `unmodeled` logic,721 include named `wb_ack` logic. Counts overlap;
optimization can rename equivalent logic. Worst route is bridge address ->
sparse hit/full decode -> unmodeled -> ACK/commit -> MDI forwarded ring/pointer
logic -> pointer register (11 levels,15.465ns data delay). LCD BRAM endpoints
are predominantly write address/data/enable controls on that shared commit
route, not the removed divider or a measured panel serial-clock failure.
Old SIM FIFO, LCD /88/%88 and cache dirty/valid metadata destinations are
absent from this subset; this does not prove their full-design timing passes.

Next recommended target: separate address/error validation from peripheral
commit/write enables with a registered boundary, preserving exactly-once
commit, bus-error suppression and read/IRQ behavior. Diagnose shared fault/CAM
fanout before independently patching all destination modules. MDI additionally
has same-cycle forwarded ring comparisons worth splitting once the common
path is cut. Cache-bank write/merge remains a separate6-path group. No RTL
change, push or new build initiated by this timing-analysis request.

## Fifth iteration: SIM enable, minimal LCD and cache flag writes (2026-11-07)

User selected a slower SIM service enable plus registers, a simpler LCD model,
and full-speed cache metadata repair. A subsequent clarification explicitly
removed the speculative LCD row-completeness machinery rather than retaining
or optimizing it. Firmware, loader, CPU/SDRAM clocks and SDC remain unchanged.

- **SIM:** board card uses CLOCK_DIV=32: 104 MHz /32 = **3.25 MHz**, as Nokia
  documents (not 3.5 MHz). Committed TX/pop events enter a system-clock holding
  register, transfer to CEN-only work registers, then execute at the following
  enable. The extra CEN stage gives even an event arriving just before an enable
  a complete service interval before FIFO processing. Pending/work busy holds
  subsequent SIMIF requests via ready until state/bytes are current. No events
  are dropped or re-sampled from changing bus data. This is a transaction-level
  service cadence, **not electrical SIM clock generation or ISO7816 baud timing**.
  Direct card fixtures retain CLOCK_DIV=1 as an immediate semantic oracle.
- **LCD:** reviewed pinned Nortido `rtl/ngage_lcd.sv`: it uses a linear burst
  pointer and has no runtime per-word quotient/remainder. Our `/88` and `%88`
  existed only to reconstruct complete rows and suppress pixels until all rows
  arrived, not to address the framebuffer. Removed that row bitmap/counters,
  divide/modulo, and full-frame scanout gate entirely. Panel on/off, known
  commands, write address bounds, direct/DMA pixels, framebuffer and native
  176x208 raster remain. BRAM already initializes to zero on FPGA configuration;
  partial updates show immediately and warm reset does not erase stored pixels.
  `frame_complete/incomplete` remain lightweight diagnostic flags for explicit
  full transfers and direct full bursts; chunks no longer fabricate a coverage
  completion event. No speculative slower panel clock is introduced: updates
  already occur only on accepted write/DMA enables, with scanout independent.
- **Cache:** each valid/dirty flag has a fixed per-segment/per-way enable from
  matched-way bits and a lower-way prefix OR. This preserves lowest-way priority
  while removing the binary hit-way encode -> decode -> flag-write path. Keep
  encoded hit_way for data-bank addressing. Reset, lock, scan invalidate/clean,
  hit invalidate/clean/write, replacement and dirty-half priorities are retained;
  tag/data M10Ks, lookup latency and warm throughput are not serialized.

No blanket false/multicycle exceptions were added. Internal CEN-to-CEN work
has explicit service registers, but input holding, ready/status, FIFO readout
and CPU paths still need fast boundary timing. This fit deliberately retains
conservative constraints; any later slow-enable timing allowance needs precise
fitted endpoint/enable verification, not a whole-card exception.

Validation: C++ SIM bytes/FIFO reference, saturation/reset and 600-response
scoreboard pass; a new enabled-versus-immediate card test covers 160 long
responses, concurrent TX/pop, capture/hold, 32-clock cadence and pending reset.
Absent/present board SIMIF matches 31/194 reference operations with real busy
waits. Those benches previously sampled ready in the same delta cycle as
changing request fields; add a settle step before the wait loop so they honor
backpressure, rather than bypassing a newly asserted busy.

The full CPU/cache suite with CPU_BUS_BRIDGE=1 passes **119 checks plus one
expected legacy direct-mapped associativity XFAIL**. Expanded tags test writes
and checks both dirty halves across all64 ways, then cleans every line. Warm
cached ADD remains one clock at memory delays0/3. LCD direct/protocol/bands
checks verify immediate partial visibility, deterministic untouched black,
out-of-order band addressing and explicit full-transfer status. Further final
native raster, board and cold-SDRAM checks are recorded in `status.md`.

Logs: `scratch/timing-closure/pass5-sim-lcd-cache/`. Compare the next fit with
**53.52 MHz / -9.070 ns**, 33,928 ALMs /457 M10Ks. No new measured Fmax yet;
user monitors the next GitHub build, do not poll it.

## Registered bus measured result and next decision (2026-11-07)

Completed **42383337100 / c08939d** fits and fails the intended timing gate.
Reports: `scratch/timing-closure/pass4-c08939d/`. Source ac6ca1f only adds the
later loader plan, so this measurement is the isolated bus-bridge change.

| Metric | Before bridge cc89013 | Bridge c08939d |
| --- | ---: | ---: |
| Core setup slack at 104 MHz | -10.644 ns | **-9.070 ns** |
| Core slow-model Fmax | 49.36 MHz | **53.52 MHz** |
| Core setup TNS | -123805.311 ns | **-89226.544 ns** |
| ALMs | 33,589 | **33,928 (81%)** |
| Registers | 45,643 | **45,189** |
| M10Ks | 457 | **457 (83%)** |

Improvement is 1.574 ns / 4.16 MHz; setup TNS magnitude falls **27.93%**.
Other worst metrics remain positive: hold +0.247, recovery +3.677, removal
+0.878, pulse +0.961 ns. HDMI setup +0.427 ns. This remains a failing 104 MHz
build and does not establish a passing slower-clock board configuration.

**Zero of the newly exported 1,000 paths show the old shared fault/ACK -> CPU
next-request combinational traversal** (912 before the bridge). This is
structural evidence that the intended chain was cut; it is not proof all the
old endpoints pass, since selected paths and launch registers change.

New leading groups (endpoint counts are disjoint within this table):

| Group | Paths | Worst slack | Actual structure |
| --- | ---: | ---: | --- |
| SIM FIFO | 28 | -9.070 ns | Sparse hit/full -> shared unmodeled/ACK -> SIM occupancy checks -> multiwrite FIFO address/data/bypass |
| LCD division/modulo tracking | 18 | -7.937 ns | `/88` and `%88` in row completeness tracking -> next DMA word/row state |
| Cache metadata endpoints | 816 | -7.765 ns | 649 tags->tags plus 167 access->tags; representative tag-RAM -> match/priority way encode -> way decode -> dirty-bit write |
| Other endpoints | 138 | -7.189 ns or better | Includes cache bank output, response capture, diagnostics and remaining memory/control paths |

The largest intra-tag group shows an avoidable **encode then decode** path:
`hit_tree` -> `way_tree`/`hit_way` -> synthesized Decoder3 -> dirty flags. These
are not evidence of failed BRAM inference: the launch is an explicit tag RAM
and the target is deliberately registered valid/dirty metadata. Keep the
synchronous tag/data RAMs and their latency while simplifying flag write enables.

Suggested next pass, **pending user selection**, has three independent targets:

1. Register the SIM committed-event/response boundary before FIFO occupancy and
   multiwrite selection. Preserve byte order, availability/status transitions,
   overflow and simultaneous pop behavior with reference tests; a one-clock
   shift in visible card state must be explicitly integrated, not hidden by
   adjusting expected bytes. Do not patch firmware or disable the test SIM to
   remove its timing paths. A complete serialized BRAM queue is a larger
   alternative and should not be mixed in without an explicit protocol design.
2. Remove or pipeline the LCD row-tracker divider/modulo path. This is metadata
   tracking, not the native raster size or framebuffer contents. Carry valid,
   address/frame markers and reset/command ordering together through any new
   stage. Test row boundaries, incomplete/out-of-order bands, full frame, reset,
   direct-pixel interleaving and exact 176x208 pixels. Do not introduce a panel
   protocol guess as a timing fix.
3. Use one-hot matched-way flag updates instead of converting matched ways to
   an index and decoding it back for dirty/valid writes. Preserve lowest-way
   priority, replacement, reset/global invalidate, indexed scan/clean and both
   dirty halves; retain the encoded way output where data-bank addressing needs
   it. Measure area/fanout and run cache metadata/maintenance plus CPU miss,
   eviction, SWP and interrupt/abort regressions. Do not serialize ordinary warm
   cache hits just to meet timing.

Recommendation: tackle all three in one bounded timing pass, with separate
functional checks for each. Fixing only the worst SIM endpoint would reveal
LCD/cache limits around **57 MHz** at this placement (an estimate using current
slacks, not a new fitted result). Therefore none alone establishes a path to
104 MHz; all currently exceed the 9.615 ns CPU period. Refit may expose paths
outside the current 1,000. Keep loader/storage work and clock-rate experiments
separate from this measurement.

This review changes evidence/status docs only: no RTL edits, tests, new commit,
push or build. User requested analysis and a next-step decision.

## Third measured result; registered bus iteration (2026-11-07)

Completed **42379146118 / cc89013** fits but fails setup. Reports:
`scratch/timing-closure/pass3-cc89013/`. CAM change saves area but does not
improve timing in this fit:

| Metric | Before CAM 4040395 | After CAM cc89013 |
| --- | ---: | ---: |
| Core setup slack at 104 MHz | -9.582 ns | **-10.644 ns** |
| Core slow-model Fmax | 52.09 MHz | **49.36 MHz** |
| Core setup TNS | -117903.504 ns | **-123805.311 ns** |
| ALMs | 33,857 | **33,589 (80%)** |
| Registers | 45,783 | **45,643** |
| M10Ks | 457 | **457 (83%)** |

Setup regresses 1.062 ns / 2.73 MHz, while ALMs fall 268. Worst other reported
metrics: hold +0.249, recovery +2.639, removal +1.088, pulse +0.961 ns. Keep
the functional CAM simplification for the next structural experiment; do not
claim it closed paths. The worst path starts in timer/peripheral logic and
passes shared claim/ACK into SIM FIFO space/address logic (20.103 ns max data).

Actual detailed-path coverage: **946/1,000** traverse shared fault/ACK;
**912/1,000** continue through CPU/cache next-request combinational logic after
that predicate. These 912 cross the response boundary being registered.
**36** paths involve SIM FIFO and **727** traverse sparse lookup; these are
traversal groups, not disjoint totals or promised timing passes. The worst
shared ACK -> SIM FIFO path is not removed in full by a CPU response register.
SIM multiwrite address/bypass logic is a clear follow-up after measuring this
isolated change. No SIM protocol/queue change is mixed into this iteration.

User authorized option 2 after measurement. `ngage_upp_bus_bridge`, a leaf
module in the existing `rtl/ngage_upp.v`, is enabled in the internal-CPU branch.
The external-master test interface retains its behavior. Existing QIP already
includes this file; no new source dependency or Quartus source entry is needed.
This is an explicitly transaction-level UPP integration boundary, not a claim
about physical Nokia bus pins, clocks or wait-state configuration.

One outstanding classic beat follows IDLE -> ACTIVE -> RESPONSE -> IDLE.
Request address/data/mask/write/code are captured before downstream decode.
Downstream ACK/error/data are captured before CPU completion. Downstream
requests drop during RESPONSE, so side effects commit once on successful
ACTIVE completion and cannot repeat while the CPU receives the delayed ACK.
Error wins over simultaneous ACK/error. Reset masks/cancels request and response;
CYC withdrawal cancels an unfinished request. Upstream response does not depend
on CPU STB, avoiding ZAP's combinational STB suppression on ERR. The production
master's contract remains holding CYC through completion except on shared reset;
non-reset cancellation is not a target-controller flush/recovery protocol.
SWP LOCK remains
direct from the CPU and spans response/idle bubbles; it is not tied to ACTIVE.

This adds external-access latency (two extra edge intervals for an isolated
immediately acknowledged beat), affecting **memory misses/uncached traffic as
well as MMIO**. Warm cached execution remains one ADD per clock in the measured
CPU test. Timer/RTC/SDRAM clock rates, firmware and SDC exceptions are unchanged.
A fresh simulator lineage is required; old frozen checkpoints are untouched.

Validation: focused 200-beat bridge test checks zero/variable waits, captured
fields/data/errors, back-to-back beats under continuous CYC, exact-once writes,
CYC cancellation and reset during wait/response. CPU tests can exercise this
same bridge with `CPU_BUS_BRIDGE=1` in `tests/cpu/core/sim.sh`; this is opt-in
bench wiring and does not alter the standalone CPU module. Run
`sh tests/phone/upp_bus_bridge/cpu.sh` for the focused CPU matrix and
`sh tests/phone/upp_bus_bridge/run.sh` inside the simulator image for the bridge
unit test.

The bridge tests, warm timing, SWP/basic/cached/bufferable and DMA competition,
IRQ/FIQ, read/write/IRQ aborts, cache refill/writeback interrupts, alignment,
cache external abort and SDRAM-adapter SWP checks pass at memory delays 0/3.
Integrated ARM board/SIMIF/LCD DMA/fault/IRQ/FIQ/SDRAM-wait checks and synthesis/
structural lint pass. Fresh cold 5M smoke: modeled memory PC **00006164**, 328479
bus transfers, 12 fetch faults, zero data faults; actual SDRAM-controller/Micron
model PC **00006160**, 326761 transfers, 12 fetch faults, zero data faults.
Both have no LCD yet. Different fixed-cycle PCs/counts reflect the changed
latency; they are not an instruction-by-instruction equivalence claim.

Logs: `scratch/timing-closure/pass4-bridge/`. Next compile must measure new
slack/Fmax/resources and remaining path groups against **49.36 MHz / -10.644
ns**. User monitors the build; do not poll it. Registering CPU responses is not
physical timing closure until measured, and external SDRAM constraints still
need their separate board-validation work.

## Third iteration: sparse CAM/full split (2026-11-07)

User selected candidate 1, then one measurement build; candidate 2 (registered
bus boundary) must wait for those results. `ngage_sparse_regs.v` now derives
full directly from `req && we && !any_hit && all_valid`. The shared fault/ACK
predicate no longer depends on encoded signed-integer hit/free indices.
Independent balanced lowest-index trees select the hit and free slots for
payload and tag writes. Padding leaves are absent in both trees for non-power-
of-two capacities. Each tag/valid slot has a fixed write enable, preserving
lowest-free allocation without a dynamic integer-index write.

Payload remains the same byte-enabled M10K, with the same address width, reset,
new-word zeroing, hit-byte merge and synchronous read latency. Full tables can
still update existing addresses and must refuse unrelated new addresses.
No bus pipeline, timing exception, PLL/clock/timebase or firmware change.

The original sparse-store test and a new independent queue/table scoreboard
cover capacities 1, 2, 3, 5 and 64; full-table updates/refusal; all byte masks;
full address identity; lowest-free allocation; read latency; reset; and
withheld requests/commits. Same-address mixed-port RAM collision data remains
unspecified, so the scoreboard checks those updated bytes on subsequent reads.
Each capacity receives 4,000 randomized cycles plus directed fill/update/read.

Validation and new physical timing results are recorded in `status.md`.
Compare the next build against **52.09 MHz / -9.582 ns / 33,857 ALMs / 457
M10Ks**, then decide the registered-bus experiment from the measured paths.
Do not attribute all 929 prior traversals to proven timing passes.

## Second measured result and decision point (2026-11-07)

Completed **42375426237 / 4040395** fits and fails only the required timing
step. Reports: `scratch/timing-closure/pass2-4040395/`. No new RTL or build
was requested at this review/decision point.

| Metric | Baseline 697f598 | First 2bcac9d | Second 4040395 |
| --- | ---: | ---: | ---: |
| Core setup slack, 104 MHz target | -43.702 ns | -10.023 ns | **-9.582 ns** |
| Core slow-model Fmax | 18.76 MHz | 50.92 MHz | **52.09 MHz** |
| Core setup TNS | -215405.214 ns | -138677.094 ns | **-117903.504 ns** |
| ALMs | 33,832 | 34,214 | **33,857 (81%)** |
| Registers | 44,523 | 45,346 | **45,783** |
| M10Ks | 457 | 457 | **457 (83%)** |

Last step gains 0.441 ns worst setup slack / 1.17 MHz Fmax (~2.3%); TNS
magnitude falls ~15%. It saves 357 ALMs and adds 437 registers. All 1,000 newly
selected paths still fail. Other worst metrics remain positive: hold +0.184,
recovery +3.721, removal +0.952, minimum pulse +0.961 ns. HDMI setup is only
+0.079 ns on its own clock; do not overlook this small margin in future fits.

**969 prior paths traversed code we changed, not 969 paths guaranteed fixed.**
The new worst path still ends at SIM FIFO address capture, but now starts at
shared WB address bit 17 and goes through sparse-register lookup/full logic,
shared unmodeled/ACK, then SIM pop/space checks and FIFO address/write muxes.
The representative CPU feedback path continues from sparse decode/fault ->
WB ACK -> instruction-cache next state -> merger address mux -> sparse CAM.
**929/1,000 detailed paths traverse both sparse CAM and shared unmodeled.**
Maximum data delay in this subset is 18.536 ns, versus a 9.615 ns core period;
small local decode changes alone are unlikely to close every such path.

Concrete candidates, pending user selection:

1. **Sparse CAM lookup/full split (small, preserves latency).** Current
   `ngage_sparse_regs.v` priority-encodes hit/free indices into integers and
   derives full from their signs. Derive full directly from any matching tag
   and all-valid bits; select hit/free indices with a balanced lowest-index
   tree. Preserve exact address identity, allocation order, byte merge/zeroing,
   full-table refusal and synchronous payload latency. Test full-table update
   versus new-address refusal, reset, duplicate-free allocation and multiple
   sizes including non-power-of-two. This directly targets the newly dominant
   shared ACK predicate, but may leave the bus feedback and SIM tail long.
2. **Registered phone-bus request/response boundary (larger, structural).**
   Capture the CPU request, decode held fields, commit downstream side effects
   once, latch data/error and return a registered response. Keep response paired
   with its request across waits and reset; retain SWP lock across bridge gaps.
   This cuts the decode/ACK/next-request/decode chain. It adds external-access
   latency, so rerun CPU/cache/abort/SWP/interrupt, board and cold firmware
   checks, checking that warm cached ADD throughput stays one per clock.
   Topology needs a deliberate change at ngage_upp/ngage_mister bus ownership;
   registering ACK alone while repeatedly committing a held request is wrong.
3. **SIM FIFO write path (remaining endpoint cost).** Even after /25 serial
   increments were removed, multiple immediate byte writes still create FIFO
   address/bypass muxes after occupancy checks. Consider a staged packet writer
   or banked queue with explicit availability/busy semantics, tested against
   the full SIM byte reference and concurrent-pop/saturation behavior. Treat
   changed response visibility as a protocol change, not an equivalent rewrite.

Suggested order: try the focused CAM/full split as a small measured iteration;
then add the registered bus boundary if feedback remains dominant. Expect that
reaching 104 MHz can require both and expose new paths outside this 1,000-endpoint
subset. Slower physical flash/MMC/SIM clocks are separate evidence, not grounds
for relaxing these CPU-domain paths. Timer-rate correctness can proceed as a
separate experiment after the current decision; it does not itself fix setup.

## Measured first result and second optimization (2026-11-07)

Completed run **42372012944 / 2bcac9d** fits and exports reports correctly;
CI fails at the intended timing gate. The summary permission fix works.
Reports: `scratch/timing-closure/pass1-2bcac9d/`.

| Metric | Baseline 697f598 | First optimization 2bcac9d |
| --- | ---: | ---: |
| Core setup slack at 104 MHz | -43.702 ns | **-10.023 ns** |
| Core slow-model Fmax | 18.76 MHz | **50.92 MHz** |
| Core setup TNS | -215405.214 ns | -138677.094 ns |
| ALMs | 33,832 (81%) | 34,214 (82%) |
| Registers | 44,523 | 45,346 |
| M10Ks | 457 (83%) | 457 (83%) |

Worst reported hold +0.219 ns, recovery +3.961 ns, removal +0.930 ns and
minimum pulse width +0.961 ns remain positive. This is **still a failing
104 MHz design**; Fmax alone does not certify the board/external interfaces.
All newly exported 1,000 setup paths still fail (the selected endpoints change
as bottlenecks improve). Worst data delay is now 19.178 ns, maximum depth
18 levels in this subset; worst endpoint slack -10.023 ns has 17 levels.

The previous report's 152 SIM endpoints, 466 cache-tag endpoints and 312
write-buffer-hazard traversals formed 930 distinct affected paths. Those are
structures touched, not 930 timing passes. The measured improvement above
is the result of that combined change and placement, not per-fix attribution.

**Second optimization:** 969 of the new 1,000 detailed paths traverse boot
register `Selector`/`Mux` logic before shared `unmodeled`/ACK, then reach SIM
FIFO, CPU request generation and sparse CAM/other peripheral endpoints. The
boot module encoded an address into an integer index and selected validity
from 11 boot/45 scratch words (including subtraction for scratch indexing).
Replace this with constant address comparisons, parallel per-latch validity
checks, fixed per-latch writes and a balanced OR tree for read data. Preserve
all addresses/holes, byte-valid read faults, mask behavior (boot masked,
scratch whole word), zero-reset register 0x08000040, commit gating and latency.
Storage stays registers; this pass does not claim another BRAM conversion.

Validation: original boot test and a new independent 12,000-cycle scoreboard
exercise all 56 latches, all masks, unaligned aliases, holes, absent requests,
withheld commits and reset. Integrated ARM board and fresh cold 5M smoke pass
at unchanged PC 00006178, 18 known speculative fetch faults, zero data faults;
shared RTL lint passes. New fitted timing/resource effect is pending CI.

The user also requested the phone's actual slower buses/timebases. ARM920T
has separate fast CPU/bus clock modes, and Nokia documents several slower
reference/pin clocks. See `phone-clocks.md` for primary evidence, current
model assumptions and the registered peripheral bridge investigation. Do not
infer all phone blocks run at 104 MHz, or relax today's paths merely because
the corresponding physical serial interface is slower. No PLL, SDC, CPU clock,
timer rate or firmware change in this optimization.

## First path-driven optimization (2026-11-07)

Run **42368700686**, source **697f598**, successfully exported the full 1,000
paths. Local artifact: `scratch/timing-closure/baseline-697f598/`. All exported
setup paths fail. The report script works with real Quartus 17; the subsequent
host summary failed with `PermissionError` because Docker created its output
directory as root. CI now creates `output_files/timing` as the runner before
starting Quartus. The timing gate remains enabled.

Measured baseline groups (one worst path per endpoint):

| Path group | Endpoints | Worst slack | Longest data delay | Maximum logic levels |
| --- | ---: | ---: | ---: | ---: |
| LCD DMA -> SIM FIFO address/control | 152 | -43.702 ns | 52.857 ns | 37 |
| Cache access -> sparse registers | 158 | -28.092 ns | 36.906 ns | 23 |
| Cache access -> boot registers | 42 | -26.917 ns | 35.696 ns | 25 |
| Cache tags -> cache tags | 464 | -19.285 ns | 28.101 ns | 16 |

The worst detailed path starts at `lcd_dma.source[2]`, passes through the DMA
range check, shared `wb_ack`, SIM pop accounting and a long sequence of SIM
`Add*` nodes, then reaches the inferred FIFO write address. The SIM `emit` task
previously advanced tail/occupancy after every byte, serializing as many as
25 conditional increments in one clock. It now uses offsets from the original
tail and parallel room checks, then caps the accepted response length and
updates occupancy/tail once. The byte protocol, immediate response visibility,
simultaneous pop-before-enqueue, saturation and sticky overflow are preserved.
This is still a multiwrite response queue; no new single-port BRAM claim is made.

Rank 113 starts at the data write-buffer head, passes through rotating queued
address/length selection, `query_line_pending`, cache bus eligibility and the
Wishbone merger before reaching the sparse CAM. Hazard detection now compares
the four physical slots in parallel and qualifies each by its distance from
head. It still includes already-retired words within a live group conservatively
and handles groups crossing a cache-line/address-wrap boundary.

The cache tag loop's lowest-way priority is expressed as a balanced six-level
tree instead of serial `!hit` selection. Lowest matching way, associated dirty
bits, no-hit outputs, synchronous BRAM reads and lookup latency are unchanged.

**These are structural RTL fixes, not measured timing closure.** Keep 104 MHz,
timer constants, SDRAM configuration, firmware and timing constraints unchanged.
Compare the next fitted 1,000 paths, Fmax, slack, ALMs and M10Ks before choosing
further changes. Remaining candidates include the cache/Wishbone request and
response boundaries and sparse CAM selection; the current artifact does not
establish how much each change improves the next fit.

Validation passes: SIM C++ fixture and absent/present board comparison, new
600-response FIFO scoreboard, cache tags/bank/access, write-buffer ordering and
all-head-position/address-wrap hazard checks, integrated ARM board test, CPU
warm ADD timing at memory delays 0/3, fresh cold 5M-cycle hardware-bound smoke
(PC 00006178, known 18 speculative fetch faults, zero data faults), shared RTL
lint and seven timing-tool tests. These simulations do not model physical
setup/hold failures; the next Quartus build supplies that evidence.

## Observed baseline and current scope

Completed build **d068883**, action **42365167112**, fits the device but fails
setup timing: **-43.702 ns** core-clock slack, **18.76 MHz** reported Fmax,
**-215405.214 ns** setup TNS. The PLL is still **104 MHz**. Resource use is
33,832/41,910 ALMs and 457/553 M10Ks. Reports are retained locally under
`scratch/hardware-bringup/build-d068883/`.

That artifact contains aggregate STA panels but no detailed critical paths or
fitted database. Node-level launch/capture/routing paths cannot be reconstructed
from the summaries alone. A new post-fit analysis must run while the database
still exists on the GitHub runner.

The user explicitly chose to **keep 104 MHz unchanged** for the next baseline
and request the worst **1,000** paths. The earlier 50 MHz proposal is deferred.
No PLL, clock frequency, timer, SDRAM mode, RTL, SDC or timing exception changed
in this reporting step. Do not attribute the failure to a particular CPU/cache
or debug block before inspecting the actual paths.

## Build artifacts

After normal Quartus compilation the action runs:

```sh
quartus_sta -t tools/report_quartus_timing.tcl Template 1000
python3 tools/summarize_quartus_paths.py output_files/timing/worst-setup.csv \
  --output output_files/timing/path-summary.md
python3 tools/check_quartus_timing.py output_files/Template.sta.rpt
```

The `quartus-logs` artifact always includes `quartus_timing_details.log` and
`output_files/timing/`, even when the timing gate fails. Main outputs:

| File | Contents |
| --- | --- |
| `worst-setup-full.rpt` | Worst 1,000 slow-model setup paths, full launch/capture clock paths, cells and detailed routing |
| `worst-setup.csv` | Rank, slack, data delay, logic levels, source/destination clocks and complete node names |
| `path-summary.md` | Group counts/worst slack by source/destination block and ten worst node pairs; also shown in action summary |
| `hold-slow-full.rpt`, `hold-fast-full.rpt` | Worst 100 hold paths in each model, with routing |
| `recovery-slow.rpt`, `removal-slow.rpt` | Worst 25 reset/asynchronous recovery/removal paths |
| `clocks.rpt`, `fmax-slow.rpt` | Derived clock identities/periods and slow-model Fmax |
| `unconstrained-slow.rpt` | Unconstrained interfaces/paths, kept visible for follow-up |

The setup selection uses `-npaths 1000 -nworst 1`: the worst path to each of
up to 1,000 distinct endpoints. This spreads analysis across many bottlenecks
rather than spending all rows on alternate routes to one register. The text
report and CSV use the same selection. No full path dumps are printed to chat
or the action console; detail stays in the artifact.

The report script analyzes the existing post-fit netlist with normal slow/fast
models. The original compile's multicorner `.sta.rpt` remains the timing-gate
input. Changing or omitting constraints is not a timing fix.

## Timing gate and limits

Quartus can exit successfully and generate an RBF despite a timing failure.
The new gate rejects `Timing requirements not met`, any negative reported
setup/hold/recovery/removal/minimum-pulse slack, and missing metric summaries.
It runs **after** detailed reports are generated. A failed-timing run is
therefore expected to be red while still providing its timing artifact.
Normal RBF upload requires this gate to pass.

This gate checks reported **constrained** timing. It does not certify the
unconstrained external SDRAM/other IO paths. The current interface constraints
still need evidence-backed board-delay work; no false paths, multicycles or
asynchronous-clock exceptions were added to hide them. See
`sdram-104mhz-ddio.md` for that separate hardware gate.

Local verification: `python3 tests/timing/test_tools.py` checks positive,
negative, incomplete and contradictory timing reports, rejects the actual
failed board report, and exercises CSV ordering/grouping/escaping. A mocked
Tcl API validates control flow/output handling only, **not Quartus semantics or
physical timing**. No local Quartus installation/download is used. Real API
execution and the measured paths require the GitHub build.

After obtaining the artifact: group the 1,000 paths, inspect logic depth versus
routing and shared fan-in, identify the real critical structures and make a
measured RTL change. Run the relevant CPU/chip/video regressions and compare
new STA, resources and hardware behavior. Keep each RBF paired with its source
and timing reports. The user monitors new builds; do not watch/poll the action.

Quartus 17 command references:
[report_timing](https://resources.altera.com/quartushelp/17.0/tafs/tafs/tcl_pkg_sta_ver_1.0_cmd_report_timing.htm),
[get_path_info](https://resources.altera.com/quartushelp/17.0/tafs/tafs/tcl_pkg_sta_ver_1.0_cmd_get_path_info.htm),
[report_ucp](https://resources.altera.com/quartushelp/17.0/tafs/tafs/tcl_pkg_sta_ver_1.0_cmd_report_ucp.htm).