# Peripheral memory placement — 17 November 2026

**Keep the two large UPP banks in BRAM for now. Investigate the reported MMC
write failure before implementing the proposed stream-tag storage change.**
The operator reports on 17 November that MMC writes still do not work. The
previous simulated write-path checks establish only their modeled boundary.
The failing operation, installed build, write-protection state and first
divergent transaction remain to be identified. Record this failure against the
current implementation so an area comparison cannot silently preserve it.
Reserve sixteen extra M10Ks for the independent banked-TLB experiment first.
Do not combine either change with its release fit. Moving upload/NOS backing
to DDR is a useful capacity option if that reservation or later audio work
exhausts BRAM, but does not itself remove a material ALM consumer.

This is a read-only architecture/resource audit plus fresh baseline tests.
No production RTL, firmware, PLL, Git index, branch, release input or running
simulation was changed. No new hardware fit, full boot or deployment was run.
The proposed MMC and DDR implementations below are **unimplemented contracts**.

## Evidence anchor and accounting

Latest locally retained physical report: seed42/debug-on run44123116917,
commit `ccba54f60a2c6f4741e74428b3306a19717ea58d`,
`build/fit/combined-5jk-20261117/quartus-logs-44123116917/output_files/Template.fit.rpt`.
Report SHA256: `3f95b5c0bc0d7c906c1b73e4a9cd0eb20a191476fd9999eea1f471f84b514b03`.
The [machine extraction](evidence/peripheral-memory-placement-20261117.json)
retains fourteen disjoint hierarchy rows and source hashes. All fourteen
selected current source files, including Template and both MMC modules,
match the report's compiled-source hashes at audit time.

Whole fit: **40,834/41,910 ALMs, 45,605 registers, 502/553 M10Ks,
4,190/4,191 occupied LABs**. Nominal margin is1,076 ALMs and51 M10Ks;
one free LAB is a separate packing constraint. Slow78MHz setup is
−1.069/−1.019ns,104MHz −4.274/−4.224ns; the PLL remains78MHz.
See [release evidence](cpu-load-release.md). No capacity arithmetic establishes
timing closure or usable routing space.

In the table, ALMs are **direct, excluding children**; memory is **inclusive**.
The rows are disjoint subtrees, so none includes another listed row. Registers
are direct too. These are fitted owner costs, not the potential savings from
its particular array. Memory primitive descendants must not be added again.

| Independent owner | Direct ALMs | Direct registers | Inclusive memory bits | M10Ks |
| --- | ---: | ---: | ---: | ---: |
| Upload bank |0.0|0|524,288|64|
| Generic NOS/shared bank |0.0|0|524,288|64|
| Auxiliary bank |0.0|0|131,072|16|
| GPIO bank |0.0|0|32,768|4|
| NOS4K bank |0.0|0|32,768|4|
| Boot latches/scratch |380.8|343|2,048|1|
| ICU extra registers |205.1|223|6,144|3|
| Sparse registers |173.4|197|4,096|2|
| CBUS UEM |389.5|390|4,096|1|
| EUART |124.2|159|256|2|
| UPP MDI, including ring/peer memory |230.7|249|8,192|2|
| MMC host |799.2|790|0|0|
| MMC card |2,137.0|2,009|65,536|8|
| SIMIF |97.8|146|0|0|

Upload and generic NOS each have **1.4 inclusive ALMs**, including their
wrapper/primitive children: **2.8 ALMs and128 M10Ks gross together**.
Zero direct ALMs does not mean no decode/scrub logic: shared logic lives in
the parent. Thus subtracting128 M10Ks from502 predicts374 only before the
new DDR requester/arbiter and any other changes; it predicts no large ALM gain.
The November16 estimate of64 per bank is confirmed by this newer actual fit.

The [banked TLB](tlb-area.md) currently reserves **10–16 additional M10Ks,
unfitted**:512–518 used,35–41 remaining. Adding three stream-tag copies would
give515–521 used and32–38 remaining. Budget the conservative32; these are
planning numbers, not the result of the release chat's pending matched fit.
Removing one large bank instead would nominally give448–454 after the TLB;
removing both384–390, excluding new memory/control costs.

## What the names actually own

The native NOS executable is flash-backed ARM software, including startup,
scheduling, channel registration and message delivery. `nosmem_ram` is merely
the fallback store for a UPP address window. They are different objects.

| Guest object / owner | Width × depth and ports | Reset / byte semantics | Evidence and coverage limit |
| --- | --- | --- | --- |
| `0c030000..0c03ffff`, UPP upload |32×16,384; one write + synchronous read,4 byte enables|Cold16384-edge parallel bank scrub; phone warm reset retains; keypad config and legal lane sets gate writes|Original firmware uploads internal UPP DSP code. Model permits arbitrary write/read/ARM fetch. Peer does not execute uploaded DSP instructions. Full runtime high-water mark unknown.|
| Generic `0c10xxxx` excluding MDI |32×16,384; same ports|Same cold scrub/warm retention; MDI claim wins before fallback write/read|Backing physically covers entire64KiB; effective generic tail begins`03f0`. No tail address in the old inventory; no proof of disuse.|
| MDI `0000..03e7`, pointers`03e8/03ec` |32×256 true dual port with4 byte enables; CPU and DSP-peer engine;500 halfwords used,24 bytes padding; pointers in FF|RAM power-up zero; phone reset resets engine/control/pointers, does not scrub ring payload|Two250-halfword rings;2 M10Ks **additional to** generic bank. Native driver/protocol fixtures establish ownership. Not NOS executable storage.|
| Auxiliary `0c06ffxx`, selected`0c12/0c14` |32×4,096;1W/1R,4 byte enables|Cold scrub, warm retain; region-specific exclusions|`0c06ffxx` uses rows`800..83f`; it is part of16KiB auxiliary RAM, not either64KiB bank. Existing aux-index aliases remain model behavior.|
| GPIO `0c150xxx` selected ranges |32×1,024;1W/1R,4 byte enables|Cold scrub/warm retain; SIMIF/NOS/UART/loopback claim first|Only modeled ranges accepted; unclaimed SIM injection snoop must remain.|
| NOS4K `0c004xxx` except boot scratch |32×1,024;1W/1R,4 byte enables|Cold scrub/warm retain; unlike generic GPIO path, all byte masks retained|Boot owns45 words`4748..47f8`;`47fc` stays here. ASIC`0c000xxx` is read-only constant47704770, not this RAM.|
| Boot eleven latches +45 scratch words |32×64;1W/1R,4 byte enables;224 FF validity bits plus zero-byte state|Warm reset invalidates bytes;08000040 specially readable zero; payload is not blanket scrubbed|Already BRAM. Its380.8ALMs include address/valid/fault decode; not56×32 FF payload waiting for conversion.|
| ICU extra low48/padded64 +DMA64 +epbus64 |Three32×64 1W/1R memories; accepted whole words; five probe words in FF|Every reset starts64-edge post-release scrub; selected accesses wait|Already3 M10Ks. Low control exclusions and probe byte semantics matter.|
| Sparse`0d` |Tags64×32 +payload64×32;1W/1R each; payload4 byte enables,64 valid FFs|Cold invalidation, warm payload/valid retention, pending transaction cancel|Already2 M10Ks; bounded hashed probe. Trace requests bypass it.|
| CBUS UEM register values |16×256;1W/1R; small mirrors/flags in FF|Written validity and special defaults select visibility; forwarded writes avoid collisions|Already1 M10K, not old256×16 FF array. Clock backend and serial protocol are separate costs.|
| EUART RX/TX |Two8×16 1W/1R queues|Reset clears occupancy/pointers, not a payload scrub; registered sampling|Already2 M10Ks. Folding them together would share ports and save BRAM, not necessarily ALMs.|
| MMC card data cache |16×4,096 true dual-port words (=8KiB)|Slot validity/zero flags gate stale data; mount/reset invalidate|Already8 M10Ks, independent of tags. HPS fill and serial/card accesses must coexist.|
| MMC card tags |23×16 FF words; stream12 +fully associative metadata4; concurrent low/high/prefetch checks and metadata write/invalidation checks|Validity/zero flags reset/invalidate; stale tag contents ignored; whole-tag publication|Remaining candidate. Full2137ALMs are not tag cost. Stream tags276FF bits; metadata92FF bits; compare/pipeline logic adds cost.|
| MMC host FIFO |8×16 FF, four packed bus-byte reads/writes +serial head/pop/push|Reset/new transfer resets pointers/count; payload not scrubbed|128 payload bits only. Masked bus bytes compact into queue order, potentially cross wrap. A single synchronous byte RAM cannot preserve these ports.|
| UPP DSP-peer header |8×11 FF; one streaming writer, fixed-field validation and reply selection reads|Reset clears received/active; payload retained but unusable without frame|88 source bits; whole peer66.4 directALMs/108FF, nested in MDI, **not additive** to its inclusive total.|
| SIMIF/live ICU/NOS/timers |Small live registers, IRQ/W1C/counter operations, not bulk storage|Immediate control and event/reset priorities|No broad interchangeable RAM array; converting live state changes contracts.|

Port descriptions are logical interfaces. `ngage_bram_be` uses the explicit
M10K simple-dual primitive wrapper; outputs follow a sampled address, and
mixed-port collisions are undefined. Existing consumers prime, wait or forward.
Do not rely on behavioral old-data collision output.

Other already converted small stores include the shared32×32 passive timer/ICU
bank, DMA programming64×32 and four immutable descriptor banks. See
[RAM conversions](ram-conversions.md) and `rtl/ngage_dma_channels.v`.
Dirty maps, save-sector buffers, diagnostics and cache metadata were converted
earlier too; [the original audit](quartus-memory-audit.md) is historical, not a
current FF-savings list. `ngage_modem.v` has a64×8 FF buffer but is absent from
the selected production graph: optimizing it cannot recover this fit's ALMs.
Likewise omitted diagnostic SIM storage is not production savings.

External **D550** audio firmware belongs to the separate TI DSP and D551 flash
boundary; current modeled D550 has protocol/control state, no C55x execution
or full packet/firmware RAM. Do not count its firmware as either UPP bank.
See [chip inventory](chip-inventory.md) and [native audio link](adsp-native-link.md).

## Observations versus unresolved use

The132-pair inventory samples four old traces. Seven unique`0c10` addresses
are`0014,0018,001c,0020,0024,0028,03e8`: **all dedicated MDI**, not the generic
tail. A decoder replay neither counts accepted bus traffic nor captures caller
PC, lanes, writes or instruction fetches. No new broad runtime access coverage
was inferred from it or from sparse live DDR snapshots.

The earlier [ownership audit](peripheral-ownership.md#firmware-use-and-the-two-64-kib-allocations)
records a36,248-byte upload reconstruction at offsets`0100..8e97`, matching
decoded flash offsets`0104..8e9b` after swapping halfwords in each reconstructed
word. Source table is flash physical`a000`; that is a source-table location,
not an instruction-fetch base for the generic NOS bank. The historical
`scratch/dsp/dsp-ram-0c030000.bin` is now absent. Its recorded hash/comparison
is retained evidence, **not rerun or newly verified here**. A full-size writable
contract is still exercised deliberately by board tests, independently of how
many bytes a particular boot happens to upload.

Direct readback from the original firmware is therefore unsuitable as a drop-in
RAM replacement: before upload the model returns zero, payload formatting and
offsets differ, writes may modify any word/lane later, and warm reset retains
those independent writes. NOR address-dependent decoding, command/status reads
and erase/program semantics are owned by codeflash/cflash, not the UPP store.
A ROM alias would need overlay-valid and writable storage plus initialization
rules, largely recreating the RAM problem. Keeping actual accepted payloads in
private DDR avoids all those assumptions.

## Deferred area implementation: MMC stream tags into registered BRAM

Use three replicated16×24 physical memories (23 useful tag bits), one per
low/high/prefetch lookup. Keep four metadata tags, tvalid/tzero, replacement and
invalidation bitmaps in registers. All three RAM copies receive the same
single accepted stream-tag update; metadata writes remain local. Retain all
sixteen data-cache slots and the original modulo-three mapping.

Schedule: retain registered candidate-address stage0; compute stream slot and
sample its RAM from those registers at stage1; at stage2 compare returned tag
against the matching registered sector and captured validity; register selected
hits/miss priority at stage3; form HPS parameters at stage4. Carry the metadata
hit vectors and context through the added stage. This deliberately permits
**one extra booking-pipeline edge**, not an address-adder→modulo→RAM→comparator
path. Extend the existing four-stage settle guard to cover all five stages;
verify its exact edge count against the old design rather than just renaming it.

Keep the current procedural priority for stream-tag writers at lines700 and871
of`ngage_mmc_card.v`. If their conditions can coincide, choose the last current
assignment and publish that same winning address/data to every copy once;
assert this equivalence. RAM collision output is poisoned in tests. A
`bk_touch`/mount/reset event kills booking-pipeline validity and rearms settle;
no HPS request consumes a tag sampled before that event. Writes/invalidations
must restart settling even when tvalid numerically stays unchanged. Drain an
already accepted HPS owner and reject stale generation data using existing
mount/bridge rules; do not change save ownership or HPS transfer ordering.

Expected cost is **+3 M10Ks** and276 stream-tag source FFs removed, plus far
fewer stream comparators. Added stage/context/control offsets that saving.
The existing TLB document's150–450ALM estimate is plausible but **unfitted**;
there is no measured lower bound. A material win requires a matched physical
fit with lower total ALMs/LAB pressure and no new104MHz critical cone. Do not
claim all2137 card ALMs, all799 host ALMs or the128-bit host FIFO as savings.
Host FIFO BRAM and the88-bit peer header rank lower: both have small maximum
payload savings and require new read/forward/port scheduling.

This audit does not implement the tag change: the release chat already owns
the better-qualified TLB area experiment, and no additional production area
change should enter that frozen comparison. A later isolated MMC equivalence
fixture must cover stream12/metadata4 identities, simultaneous HPS publication,
zero slots, writes/invalidation, wrapping/modulo cases, mount/reset in each
stage and withheld HPS responses; then run the existing MMC/DMA fixtures.

## Conditional DDR implementation, if BRAM capacity becomes limiting

Reserve upload`31810000..3181ffff` and generic NOS`31820000..3182ffff`
as **proposed private DDR addresses**, not a deployed allocation. Offset map:
`base[owner] + {guest[15:2],2'b00}`. These lie immediately above the current
ROM/C:/PMM maximum`3180ffff`, outside debug`313f0000..313fffff` and the
framework scaler base`20000000`/arcade video base`24000000`. The installed
Linux reservation documented in [DDR diagnostics](ddr-diagnostics.md#memory-and-reader)
puts these outside Linux System RAM too. Check target Main/other core users
before adoption; historical installation evidence is not a global allocator.
The64KiB debug gap cannot hold two64KiB banks and is already occupied.

Use a registered one-entry scalar requester on the **core DDR side**, before
the existing auxiliary/loader arbitration, bypassing flash command controllers
and flash cache allocation. Keep one core-demand owner among codeflash,
cflash and private UPP requests; they cannot bypass each other's completion.
Share existing loader/save/debug arbitration fairly between complete packets,
retain CPU-lock reservation, and do not inject the private requester as an
unbounded high-priority loader. Diagnostic/background bursts remain bounded.
No new raw DDR-ready→UPP ACK/decode/CPU execute path is permitted.

Transaction contract:

1. Capture owner, guest word address, read/write/fetch identity, data and byte
   enables only from the held UPP request after existing config/lane validation.
   MDI owns`0000..03ef` first;`0c06ffxx` remains auxiliary. No fallback DDR
   launch for illegal masks, malformed access, cold init or withdrawn request.
2. Separate admission from mutation. Existing `local_access` depends on ready;
   it cannot launch DDR and simultaneously wait for DDR ready. Register an
   authorized bridge demand, issue it once, then expose ready/terminal response
   only after its scalar completion. A changed request before launch cancels.
3. Submit exactly one scalar32-bit transaction with four byte enables; use the
   existing adapter's64-bit lane mapping. Do not implement masked writes with
   an unlocked external read/modify/write. Disable bulk/line modes. Instruction
   fetch uses the same ordered read path and returns the written payload.
4. Keep address/data/enables stable until arbitration accepts; retain owner
   through completion. A write ACK waits for backend completion; the next read
   or fetch cannot overtake it. Return one registered response, then require
   request withdrawal before reuse. Held response must not repeat a write.
5. Before DDR acceptance a reset/cancel discards the offer. After acceptance,
   drain the transaction while suppressing its canceled guest response;
   accepted effects are not rolled back. Quarantine the held old request.
   Do not reset arbiter ownership under an outstanding physical DDR request.
   Warm reset preserves completed/accepted writes; admit no new request until
   the old response drains. Generation/owner, not current address, routes done.
6. On cold init, block phone release, drain old accepted traffic, then explicitly
   zero all32768 words across both regions using the same masked scalar path.
   Assert init_done only after the last zero completion and existing local
   sweeps. Do not assume HPS DDR power-up zero. Warm reset never starts scrub.
   A repeated cold event restarts after drain; a late write cannot land after
   its region was cleared. Prevent init_done/reset-gate circular dependency.
7. Leave codeflash unlock/program/status/erase decode, C:/PMM dirty tracking,
   save queue and sector ownership entirely outside this requester. Private
   writes must not dirty flash or be included in saves. Adjacent firmware,
   debug and PMM regions remain guarded in tests.

Replacing only generic NOS first is the smaller reversible rollout:64M10Ks
gross recovered, local MDI unchanged, and upload timing preserved. Retain the
full address space even if instrumentation records no tail traffic. Move upload
second only after measured boot/upload cost. Removing both is the old handoff's
128-block **capacity** proposal; net ALMs will likely rise due to requester,
scrub and arbitration state. A paired fit must measure net results.

External module SDRAM is less attractive for this first experiment. Current
adapter uses address bit23 and BA0/1 for two physical8MiB banks: all16MiB are
guest RAM. No hidden tail can be carved out. Enabling BA2 for private backing
could preserve that capacity on a suitable32MiB module, but requires geometry,
bank enables/write/refesh/arbitration/physical timing verification and changes
the busy RAM/DMA fabric. Do not simply widen AW or assume a16MiB physical bank.
See [SDRAM validation](sdram-native-validation.md). DDR already supports the
required scalar requester and avoids that geometry change.

## Tests performed and remaining gates

Fresh existing fixtures ran sequentially in the installed
`jotego/simulator:arm64` image, network disabled, with separate outputs under
`build/sim/peripheral-memory-placement-20261117/`:

* `regional_ownership`: PASS exhaustive eight64KiB windows plus overlap,
  lane and configuration cases; no accepted-access runtime count implied.
* `board_wrapper`: PASS sparse wait/cancel/full/trace exclusion, independent
  upload storage and warm-retain/cold-clear behavior.
* `board_inventory`: PASS all132 retained-trace device/address pairs.
* Resource extraction: PASS fourteen unique disjoint subtrees,128 total bank
  M10Ks, fourteen current-source hashes matching the fitted input manifest.

The first Docker attempt could not access its socket in the restricted
environment; approved execution succeeded. An initial wrapper omitted Docker
stdin forwarding and therefore ran no tests; this was corrected with`-i` and
only actual PASS-bearing runs enter the retained receipt. Logs and timings
are attached to the [machine evidence](evidence/peripheral-memory-placement-20261117.json).
Own generated test executables were removed; no other build directory cleaned.

These are baseline measurements, not proof of either proposed implementation.
No new CPU upload-execution run was made: the existing original ARM fixture
at`tests/phone/board_shadow/scratch_exec.S` establishes that required contract,
and its old frozen-executable runner must not be silently reused as current RTL.

A DDR candidate still needs directed first/last words, equal offsets/different
banks, all legal masks, arbitrary post-upload writes and instruction fetch,
MDI boundary/pointer ownership, aux exclusion, firmware/save guards, varied
DDR latency/backpressure, exact-once responses and cancellation/reset on every
offer/accept/completion edge. Reuse the board/reset fixtures, extend them with
the actual outer arbiter and collision-poison backing rather than a bypass.
Then cold-boot the identical original runtime data through upload and Menu,
service activity and warm reset: count **accepted** reads/writes/fetches by
owner/offset/PC/enables, exclude scrub, record upload/boot cycles, contention
and first divergent access. Missing generic traffic is still not deletion proof.
Finally a matched seed42/debug-on fit must audit exact source inputs, total
ALMs/LABs/M10Ks, and routed78/104MHz setup/hold. Both full boot and physical fit
remain open for any memory-placement change.
