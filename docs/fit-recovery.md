# Integration fit recovery

## 2026-11-11: Logic-fit priority, packed D-cache metadata and VHD-only profile

The replacement user logs fail with **43,217/41,910 ALMs (103%)**, requiring
4,370 LABs versus4,191 available. This is a logic/LAB shortage, not an MLAB
shortage: detailed MLAB usage is zero; M10Ks are512/553. These logs supersede
the earlier113% result without erasing that evidence.

Production D-cache dirty halves now occupy the upper byte of each existing
simple-dual tag RAM. Native byte enables preserve tags during dirty/clean
updates. Valid flags remain resettable and mask stale RAM. Maintenance selects
the indexed row during the existing TAG_WAIT; no lookup, store or maintenance
stage is added. The source removes1,152 dirty-state/read-pipeline FFs and adds
a two-bit commit snapshot: intended net1,150 FFs, plus removal of their update
and selection logic. Each8x32 simple-dual RAM is intended to remain one M10K,
with no cache size/way reduction. Actual ALM savings, block count and104 MHz
routing/timing require a new Quartus result.

The production QIP comments out the retired NGA manager/header, legacy LCD-only
frontend, inactive bitmap dirty tracker, scalar DDR lanes, unconnected legacy
modem, instruction-only DDR cache and simulation disassembler. They remain
available to historical tests. There was already no active working.nga mount
instance in Template: C:/PMM use the raw VHD manager exclusively. The flush
menu now names C:/PMM. Shared sector transport and flash emulation stay because
the VHD manager still needs them; no image bytes or firmware ABI are changed.
The shared8 KiB flash cache explicitly selects ROM_CACHE=0. The inactive
source removals themselves save parsing, not fitted gates; Quartus already
eliminates unselected generate branches. The unused Linux ALSA mixer is now
compile-time disabled; this core currently supplies zero phone audio samples.

Keep the fast SDRAM LCD stream. Prior matched CPU measurements were130,685
frame clocks versus306,802 on the general word path (over2.3x as many clocks).
The general DMA workers remain necessary for MMC/copy and on-chip RAM LCD;
that route is not a duplicate full-frame stream engine. Both workers and all
eight guest channels remain. Semi-real NOS, SIM and peripheral models remain.

ARM dirty-writeback IRQ, cached SWP and single-line CP15 maintenance also pass
with zero/three memory waits; exact cycle counts are in the evidence.

Local checks pass: 11,025-cycle old/new cache equivalence with ordinary RAM,
Intel primitives and X-poisoned collisions; tags/bank/maintenance/access/buffer
suites; I-cache equivalence9,416/9,440 cycles;104 MHz timer-profile ARM board
and production DMA/LCD tests. Fast normal/held totals stay152,456/152,537 clocks,
with queued-tail/transport reset checks passing. Full4 MiB C: and64 KiB PMM
restore/readback pass in bulk mode (1,064,960 DDR writes, two snapshots).
Selected-source top elaboration passes with no UNOPTFLAT loop, and the Quartus
source preflight passes175 required files/nine QIPs. No fresh full boot,
hardware UI fix or successful physical fit is claimed. Other chats' simulations
and existing checkpoint pairs are untouched. Earlier uncommitted boot-observer
work is preserved separately. Build monitoring remains disabled.

See [evidence](evidence/logic-fit-profile-2026-11-11.json) and the maintained
[packed-cache regression](../tests/cpu/cache_dirty_packed/README.md).


## Failed build and resource attribution

CI run43016356272 compiled `6b7be5a` and failed device capacity. The user supplied
the full logs under `Downloads/quartus-logs`; they were read without alteration.
The failed summary reports47,296 required ALMs versus41,910 available and52,920
registers. The detailed fitter RAM report lists511/553 M10Ks, despite the
partial summary showing zero RAM blocks. Logical memory bits were2,882,214;
implementation allocation was5,232,640 bits. BRAM inference was present, with
only42 blocks of headroom.

The largest new peripheral contributions were the general DMA frontend
(2,362 local ALMs;3,599 including workers/stream), MMC card(1,941), host(785)
and HPS backing adapter(505). DDR transport/cache slices were much smaller.
Existing boot registers, sparse tags and cache metadata also retained useful
opportunities. The failed fitter's packing estimates are incomplete; adding
source-level savings cannot predict a new physical fit.

## Changes selected

| Area | Recovery | Behaviour and latency |
| --- | --- | --- |
| DMA programming words | One64×32 M10K retains full raw readback; live source/destination/count and decoded mode/width metadata remain available to dispatch | All32 readback bits, invalid widths, queues and captured descriptors preserved. Raw programming reads gain one RAM clock; writes/start/stop/status and streaming timing stay unchanged. |
| Boot scratch |45×32 data FFs move into one M10K; byte-valid flags remain resettable | Fixed boot latches stay immediate. Scratch reads wait for their RAM sample, including coherent error data. Unwritten bytes read zero after warm reset; data RAM needs no reset sweep. |
| Sparse register tags | One extra M10K replaces64 full-address FF tags and the CAM/selection network | Full capacity, cold/warm reset, partial writes, overflow, cancellation and exact-once commit preserved. Collision-free lookup is2 clocks versus4 previously; adversarial64-entry collisions take65, plus one replacement bubble. |
| Instruction cache | Static read-only specialization removes dirty metadata and its pipeline | No capacity, tag/data port, lookup stage or refill change. D-cache remains generic. Source-level omission is1,282 state bits, with zero extra M10Ks; physical savings require synthesis. |
| Execution pool | Production uses two general DMA workers, retaining all eight programmable channels | Native LCD streaming remains separate. Two workers retain the measured MMC-wait plus copy concurrency; a third adds no benefit in those jobs. |

These storage changes intend three additional M10Ks. Full-width register
contents are retained rather than truncated to fit. They do not enable a slower
LCD implementation or reduce cache capacity. Runtime OSD settings or an absent
MMC image do not remove gateware; compile-time selection of two workers does
remove the third worker.

### DMA worker measurements

The same native18,304-word LCD stream, router, RAM mux and CPU/DMA SDRAM arbiter
were exercised with one/two/three workers. With one MMC FIFO stalled, one worker
completed no copy words by LCD completion. Two and three both completed128 copy
words and had identical timing. CPU maximum acknowledgement gap was8 clocks
in every case.

| Workload | One worker | Two workers | Three workers |
| --- | ---: | ---: | ---: |
| Isolated normal MMC,256 bytes |1,284 clocks |1,284 |1,284 |
| Isolated full LCD |146,434 clocks |146,434 |146,434 |
| LCD with stalled MMC and copy |146,431; copy blocked |148,479; copy complete |148,479; copy complete |
| Finish outstanding work after MMC release |3,324 clocks |1,272 |1,272 |

The2,048 additional LCD clocks in the concurrent case are useful shared-RAM
copy traffic, not a worker overhead. These are synthetic transport measurements,
not phone throughput. A future workload with multiple independently blocked
peripherals may justify a larger pool. Current wired peripherals are LCD and
MMC; memory copies are another job class. On-chip-RAM LCD uses a general worker;
the normal SDRAM LCD stream has its own path.

## Structural DMA timing correction

The failed build also reported a combinational feedback path through live MMC
`cmd_valid`, local admission, CPU exclusion and CPU cancellation decode.
Logical MMC reservation made a functional oscillation unproven, but cutting
that timing path was not acceptable as a timing solution.

The router now exports `local_waiting` directly from its captured LOCAL_WAIT
state. UPP excludes CPU admission using that state and the existing registered
LCD/MMC reservations. Actual DMA take/accept timing is unchanged; every accepted
word must still exclude the CPU. No DMA state or transfer clock was added.
The final structural elaboration reports no UNOPTFLAT loop. A new Quartus run
must confirm that its own loop/timing warnings are gone.

## Local validation

- Boot scratch: directed reset/byte-valid tests plus12,000 randomized cycles,
  both ordinary RAM and the existing Intel `altsyncram` model.
- Sparse storage:22,430 oracle transactions across capacities1/2/3/5/64,
  with both RAM models, full collisions, all address bits, cancellation at
  every probe/result stage and cold/warm reset.
- DMA: old/new packet, dispatch, IRQ and full readback equivalence for
  one/two/three workers;397 readbacks each. The worker benchmark above also
  compares old/new externally visible transactions.
- Instruction cache: cycle equivalence for wide and halfword refill, five
  generic cache suites, twelve CPU cache/prefetch/IRQ runs and patch replay.
- Combined board: IRQ/timer/keypad, ownership, registered response and clocks;
  actual MMC bus plus98 all-channel DMA phases; fast LCD queue/tail fences.
- Combined ARM at the104 MHz timer profile: board IRQ/FIQ/keypad/local DMA/
  LCD/fault checks and production full-frame/row-band/copy/hold/reset tests.
  Normal/held totals remain exactly152,456/152,537 clocks; the fast frame
  interval remains130,685 clocks.

Evidence is in [fit-recovery-2026-11-11.json](evidence/fit-recovery-2026-11-11.json),
[I-cache evidence](evidence/icache-read-only-2026-11-11.json), and the isolated
scratch paths it references. The generic DMA default remains three for tests;
production explicitly selects two. Hardware PLL selection remains78 MHz, with
104 MHz kept as the architectural timing target. No local Quartus download,
other checkout simulation operation or old checkpoint mutation occurred.

Actual ALM/register/M10K allocation and timing remain pending a new CI fit.
Neither this recovery nor the pointer observer proves full firmware UI wake.

## First CI retry: primitive-port mismatch

Run43032422026 at0a47a0f failed synthesis before resource allocation. Its32
missing-source errors identify DMA programming RAM's unsupported simple-mode
`q_a` read. That connection is corrected to read-B, and the wrapper's ordinary
model now matches Intel's write-A/read-B contract. All three worker counts
pass397 raw reads against the actual vendor model; the prior connection fails
the tightened ordinary model. RAM, actual MMC DMA and LCD host regressions pass.
See [DMA readback](dma-readback-ram.md). Actual area/timing still require retry.
