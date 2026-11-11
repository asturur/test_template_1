# Why our integration costs more than the donor (2026-11-11)

## Scope and comparison limits

The integration checkout remains `codex/ngage2-integration` at840e3d4. Donor
checkout was already restored to `codex/mmc-payload-eof-fix`; current donor master
is91a6d08. Architectural findings below were checked against master using Git
objects, without switching its branch or modifying its experiments.

Our user's completed fit report provides38,995 required ALMs,40,492 placed
ALMs,497 M10Ks. Our latest failed report provides42,407 required ALMs and
4,277 required LABs. Use the completed fit for stable block attribution, not
failed-fit parent rows that move heavily with physical synthesis. A matching
current donor whole-core report is not available locally. Donor documentation
contains historical whole-core fits around34k ALMs, but different revisions,
seeds, caches and clocks make those unsuitable for a precise delta table.
No CI job was queried or monitored for this audit.

## Confirmed differences

| Block | Our completed-fit cost | Donor master / consequence |
| --- | ---: | --- |
| Diagnostic renderer + monitor |836.3 ALMs | Donor compiles diagnostics only under NGAGE_DEBUG; ours builds them even when Phone display is selected. |
| Recorder/export in addition |349.9 ALMs | Full listed diagnostic group is1,186.2 ALMs. Keeping recorder/export while omitting the screen is a possible release tradeoff; it removes live on-screen fault viewing. |
| CPU register file |2,007.6 ALMs | Our40x32 FF storage/five read muxes versus donor replicated asynchronous MLAB banks, latest-writer selection and collision-safe held/committed bypass. |
| I/D TLB bank storage/compare |3,986.5 ALMs | Our two64-entry fully associative mixed-page CAMs; donor direct-mapped per-page-size buffers. Donor lockdown is stored/read back without effect. This is different behavior, not unused hardware. |
| I/D cache tag modules |3,399.8 ALMs | Our16 KiB+16 KiB/64-way/32-byte line caches versus donor32 KiB+32 KiB/two-way/16-byte line caches. Donor spends more data RAM but much less parallel-associative machinery. |
| DMA frontend including workers/stream |2,497.8 ALMs | Donor reads src/dst/count from a small descriptor RAM during dispatch. We retain live programming mirrors and full queued snapshots in FFs. Ours has two workers; donor defaults to three. |
| Six timers |1,080.7 ALMs | Our live count/reload plus full-width readback registers; donor retains passive/raw values in shared peripheral BRAM and only active timer state in FFs. |

These rows are costs, **not promised savings**. Do not add CPU total to its RF,
TLB and cache children; do not add the DMA frontend parent to its workers. The
completed-fit CPU total is17,462.1 ALMs, already including RF/TLB/cache blocks.
MMC is shared functionality, not a spare feature: our card alone is1,997.5 ALMs.
NOS/BT overlay loaders and the diagnostic SIM are already compiled out. The
fast LCD path and retained two-worker concurrency are not redundant copies of
an unused donor path. The legacy Jotego ROM-request cache is excluded too.

### Concrete storage overhead we can remove without dropping phone behavior

- Timer spare0/spare_c/spare_14/spare_1c alone hold**768 resettable FF bits**.
  Our ICU's cfg0/cfg1/global_enable add**224 bits** of passive readback state.
  Preserve arbitrary full-width readback and reset behavior in BRAM rather
  than deleting it. Timer counters/reload and actual ICU enables remain live.
- DMA queued src/dst/35-bit budget/widths/increment/request/fast flags hold
  **896 bits**, in addition to**768 bits** of live src/dst/count mirrors.
  Existing raw programming readback already uses RAM, so that previous recovery
  did not remove these copies. A packed queued-descriptor RAM can preserve
  immutable start snapshots and dispatch semantics with a short launch stage;
  the donor's multi-cycle parameter loader is a useful reference, but reading
  mutable programming RAM later would weaken our current start-time contract.
- Our cache tags allocate**64 tiny M10Ks per cache:128 blocks total**, holding
  just28,672 declared tag/dirty bits, about2.2% of those blocks' raw bit capacity.
  This buys64-way parallel lookup. They cannot simply be packed into one RAM
  without changing read-port bandwidth/lookup latency. Moving them to MLABs
  would consume the scarce LAB fabric; freeing M10Ks alone does not fix LABs.

### RF is a real porting opportunity, not just an idea

The donor already has the latest-writer MLAB RF from Z2. It retains five
asynchronous reads and bypasses held writes plus the just-committed write, so
undefined mixed-port RAM collision data is not consumed. Reset invalidates
metadata rather than clearing RAM words. It includes a dont_retime boundary.
Our version retains FF data and the read mux network. Porting the memory
strategy can target that2k-ALM block without reducing architectural registers.
MLAB cells also occupy LABs, so count total physical LAB usage, metadata,
replicas and bypass before claiming a win. Our generic background mask allows
multiple bits while the donor assumes one-hot writes; production background C
is already tied zero. Preserve or explicitly specialize that contract.

### CPU differences must not be labeled dead logic

The donor now uses its ARM9V2 pipeline plus ZAP-derived caches/MMU/CP15/RF, not
our owned-operand ZAP pipeline. It also identifies as TI ARM925T. Our cache and
TLB structures are ARM920-shaped model choices; the donor's larger two-way
caches, direct-mapped TLBs and no-op lockdown cannot be copied as an invisible
storage change. Original NEM-4 boot, bank/permission/maintenance tests, CP15
behavior, aliasing and throughput must all be qualified. This is a larger
CPU/backend experiment after cheaper storage reductions, not the first fit fix.

## Next optimization priorities

Diagnostics remain enabled until Symbian boots, per the user's decision. The
~1,186-ALM diagnostic group is excluded from near-term savings. Keep78 MHz
operation and design toward104 MHz; retain the semi-real NOS and fast LCD.

1. **Validate the current RAM conversions in a real fit.** Timer/ICU passive
   storage now shares one M10K; DMA queues use four. If LABs still overflow,
   isolate the two840e3d4 timing changes against the last completed fit. Compare
   required/placed ALMs, packing recovery, LABs, DSPs and setup/hold. This is a
   bounded comparison when reports are available, not CI monitoring.
2. **Prototype the ZAP MLAB register file.** It targets a~2,008-ALM block with a
   donor implementation to study. Savings are unmeasured. Preserve five read
   operands, writer priority, banked/SPSR/microcode words, reset and held versus
   committed bypass. Require independent RF/CP15/operand checks, stalled journal
   refresh, collision poisoning and CPU integration before adoption.
3. **Reduce remaining duplicated/passive FF storage.** DMA has768 live
   programming mirror bits. Timer raw control/status upper bits merit an audit,
   not an assumed removable count. Preserve start-edge snapshots and concurrent
   live timer/IRQ updates. Use readback/reset/cancellation differential tests,
   original instruction fixtures, LCD/MMC throughput and measured area/timing.
4. **Compact DMA BRAM, including suitable worker storage.** Record as a TODO:
   fewer physical RAMs are useful but do not directly solve LAB pressure.
   Multiword fetch/staging can cost registers and launch clocks. Preserve eight
   channels, two workers, immutable queued payloads, cancellation and accepted
   ownership; test collision/reset, blocked peers, all IRQs and MMC lengths.
   Reject a transfer-beat slowdown or loss of the130,685-clock LCD frame.
5. **Consider CPU cache/TLB geometry only as a separate later experiment.**
   Those blocks are large, but donor associativity/lockdown behavior differs.
   Require architectural differential tests, abort/alias/lockdown coverage and
   measured firmware latency. High risk relative to storage-only changes.

All new maintained HDL remains Verilog-2001. No candidate has a promised ALM
saving until mapped; moving small tables into MLABs can consume the same scarce
LAB resources we are trying to recover.

## Work performed

Read-only RTL/report comparison and this documentation/evidence. No HDL,
configuration, clocks, branches, simulations or build jobs changed. Other-chat
uncommitted diagnostics and donor experiment folders are intact.
