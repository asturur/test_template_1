# N-Gage fitted resource comparison

## 2026-11-16 — Which costs are worth investigating

The supplied ngage2 release fit and our Stop 3B fit both use Quartus
17.0.2 and 5CSEBA6U23I7. The donor used seed 60, selected after a 16-seed
sweep, and targeted 104 MHz in the fitter. Ours used seed 42, DDR debugger on,
and a 78 MHz fit followed by same-placement 104 MHz analysis. The donor's
release record associates the matching seed, slack pair and RAM count with
`ed143ca` hardware. The fitted map parameters independently confirm 16 KiB I,
8 KiB D, two ways and 16-byte lines. Our contract stays 16 KiB I and D,
64 ways, 32-byte lines, two separate 64-entry fully associative TLBs, and our
existing DSP, NOS and Bluetooth behavior. The two projects model different phones.

Quartus **ALMs needed**, inclusive entity rows, rounded to the nearest ALM.
Delta is ours less ngage2. Subtotals are labeled to avoid double counting.

| Fitted scope | Stop 3B | ngage2 | Delta |
|---|---:|---:|---:|
| Instruction cache subsystem including I-TLB | 4,825 | 2,339 | +2,486 |
| Data cache subsystem including D-TLB | 6,818 | 3,574 | +3,244 |
| Execution core including register file | 5,995 | 8,726 | −2,731 |
| Remaining CPU logic (residual) | 243 | 113 | +129 |
| **CPU subtotal** | **17,881** | **14,753** | **+3,129** |
| Everything outside the CPU (residual) | 21,654 | 19,362 | +2,292 |
| **Whole design** | **39,535** | **34,115** | **+5,420** |

Rounding can move subtotals by one. The I/D subsystems together cost 5,730
additional ALMs. Of this, **2,335** is the difference in the two inclusive TLB
rows (4,749 vs 2,414); **3,395** is the remainder. CPU M10Ks are 168 vs 65,
while whole-design M10Ks are 503 vs 479. Outside the CPU the donor actually
uses 79 more M10Ks. Total registers are 44,752 vs 39,671; physical DSP blocks
41 vs 42. Those DSP counts neither describe phone DSP behavior nor price a
change to our multiplier or peripheral constraints. Our production control at
9c948da8 used 39,594 ALMs; the cross-project gap predates the store prototype.

**First two experiments, in order**

1. Keep Stop 3C on the registered pre-read/admission boundary. Our hot 104 MHz
   critical path ends at probe-owner way with −4.531 ns. The donor hot path
   starts at D-cache `tr_cache_word[6]` and ends at dirty metadata
   `dirty_initialized_q`, 10.601 ns of data delay and −1.597 ns slack.
   Cold-corner setup is −4.725 vs −1.553 ns. Both violate setup. The donor
   eight-stage pipeline's registered effective address and RAM/TLB overlap
   are useful scheduling comparisons. Test our own ownership and warm-load
   cycles; a smaller comparator count in another cache gives no ALM or cycle
   entitlement in ours. [Stop 3B path evidence](cache-resident-store-pipeline-fit.md)
2. Test **sharing the TLB address comparators across lookup and maintenance**.
   Today each of 64 entries evaluates page coverage for normal lookup,
   invalidate-by-MVA and overlap removal on fill (both directions).
   Payloads already reside in BRAM. First measure normal lookups, token hits,
   fills and invalidations in fixed work. Prototype sharing the compare input
   and using a registered maintenance phase, or scanning groups for rare
   mutations. Keep normal hot lookup throughput; block publication until
   overlap removal completes. Differentially verify all four page sizes,
   overlapping smaller/larger mappings, invalidate, lockdown, preserved
   entries, permissions, walked faults and reset during maintenance. Compare
   fixed-work cycles and matched-seed routed area/timing against the same
   baseline. Quartus may already share some logic; only the net fit measures
   savings. [Current TLB bank](../rtl/arm920/tlb_bank.sv) · [TLB contract](arm920-tlb.md)

The four named debugger instances in our instrumented fit total about
1,696 ALMs (DDR telemetry, text FIFO/recorder, monitor and diagnostics).
A same-source debugger-off fit can price the release configuration. Keep
debugger on for CPU A/B comparisons. It would be misleading to attribute the
entire non-CPU gap to instrumentation or to NOS/BT. Likewise the current RF is
959 ALMs vs the donor's 1,614, so the older RF savings estimate below is stale.
The older DMA storage recommendation has also been implemented: live source,
destination and count share RAM banks with the immutable snapshots. Repeating
that migration would save nothing. [Current DMA storage](../rtl/ngage_dma_channels.v)
The existing UPP external-backing proposal targets physical RAM blocks primarily.
Keep it independent. [DDR3 experiment](upp-ddr3-backing-handoff.md)

**How much faster?** The donor's seed-60 release log records 8.86 fps Game,
1.73 Mtexels/s FillRate and 28.41 Ktriangles/s PolyCount. Our recorded 78 MHz
`a745119` board build produced 1.82, 0.40 and 8.10 respectively. Those ratios
are **4.87×, 4.33× and 3.51×**, across different firmware/builds. Our board
numbers predate several CPU changes and Stop 3B. The frequency ratio alone
is 1.33×. For CPU attribution, run the same original binary/inputs and
output checks on both models with equal external wait profiles. Split warm
hit loops from cold fills, record cycles per completed work, load-use and
store spacing, branch recovery and external beats. Boot or QD versus NEM-4
wall time alone cannot assign the difference to the CPU. [Our native results](spmark04-benchmark.md)

Source locators: supplied `~/Downloads/ngage2/output_files/NGage.fit.rpt`
(SHA256 `f5371c69121469a0f14990f43fa83bafa5dc0ae33e7ef7e855eed4bd96ccf6f7`),
`NGage.map.rpt`, `build/timing-corners.tsv`, `build/critical-paths.rpt`;
our `build/fit/resident-store-20261116/candidate/output_files/Template.fit.rpt`
(SHA256 `e1340eef062952f2061236ad66893aaa998e782ec271415ea427149ebdee3a10`).
Use “Fitter Resource Utilization by Entity” in each report. Donor board and
seed provenance: sibling `docs/PROGRESS-LOG.md`, “the second release of the
day: the phone's cache sizes, seed 60”. The November 11 comparison below
records different revisions.

## 2026-11-11 scope and comparison limits

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

## Follow-up implementation — 2026-11-12

RF MLAB is now fitted; timer/ICU passive storage is shared. The next safe
reduction moved366 timer control/status upper bits into that same M10K
(net~353 FF bits after metadata). Production LCD/MMC clocks are unchanged;
ALM savings await mapping. See [timer readback RAM](timer-readback-ram.md).
DMA programming mirrors remain next; queue/worker compaction follows. This
supersedes the older prospective ranking and read-only scope above.

## Further implemented follow-up — 2026-11-12

DMA live parameters now share queue banks; boot latches share scratch RAM;
NOS/RTC/MDI/refresh and DMA indices use bounded widths. Net declared state
reduction~1,323 bits beyond the previous timer353, without intended additional
M10Ks. Measured setup overhead is one clock per start, no per-beat waits.
[Implementation/tests](area-reductions-2026-11-12.md),
[JTAG replacement exploration](jtag-diagnostics-plan.md). Earlier prospective
DMA mirror priority is complete; physical area/timing and JTAG board gates remain.
