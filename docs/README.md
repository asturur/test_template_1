# N-Gage project documentation

**Resume with the newest dated entries in [status.md](status.md).** Older
handoff blocks are historical evidence, not the current experiment. Follow the
topic links before repeating research or simulations.

| Document | Purpose |
| --- | --- |
| [spmark-disk-access-v5.md](spmark-disk-access-v5.md) | Original EFile drive verification, C: NOR A/B, host ACK and 4 KiB restore timings |
| [game-pcm.md](game-pcm.md) | Shared game audio bridge, native playback evidence, and v5 audio/MMC/LCD qualification |
| [arm9v2-sdram-stream.md](arm9v2-sdram-stream.md) | Production SDRAM scheduler, 32-byte refill and checked original-code speedup |
| [arm9v2-sdram-handoff.md](arm9v2-sdram-handoff.md) | Pin-level SDRAM write cadence, faster scalar handoff and checked CPU replays |
| [arm9v2-donor-frame-gap.md](arm9v2-donor-frame-gap.md) | Same-stream SDRAM timing, v5/ngage2 frame proxies and SPMark guest-time audit |
| [arm9v2-cache32.md](arm9v2-cache32.md) | v5 16 KiB per cache and native 32-byte board bursts, with v4 and original ngage2 measurements |
| [arm9v2-associativity.md](arm9v2-associativity.md) | v5 fixed-capacity cache associativity and half-line writeback payload comparison |
| [arm9v2-phone.md](arm9v2-phone.md) | ngage-v5 stock donor, NEM-4 bus and firmware qualification, checked SPMark and game loop comparisons |
| [cpu-store-postindex.md](cpu-store-postindex.md) | Step5F original tail gains, unchanged base forwarding, resident admission, precise IRQ/fault/RAM proof and zero-state patch0078 |
| [cpu-target-delivery.md](cpu-target-delivery.md) | Step5E exact5D call/return timelines, rejected zero-state BTB handoff, mixed cycles and wrong-path drain evidence |
| [cpu-comparison-strategy.md](cpu-comparison-strategy.md) | Current CPU and whole ARM9V2 donor strategy, larger-cache experiments, board integration and final comparison |
| [ngage2-vs-5c-benchmark.md](ngage2-vs-5c-benchmark.md) | Checked original workloads on both CPUs, cycle counts, memory traffic and call/return and post-indexed store schedules |
| [cpu-paired-delivery.md](cpu-paired-delivery.md) | Step5D matrix47887→45736, actual paired writes/advancing consumers, bounded opportunity and complete offline qualification |
| [cpu-5bc-summary.md](cpu-5bc-summary.md) | Accepted5B/5C sources, cycles vs redesign start, one matched fit, current limits and ranked next action |
| [cpu-owner-split-fit.md](cpu-owner-split-fit.md) | Master5B seed42 RBF/source proof,319 fewer ALMs,78/104 setup gains and new private-probe feedback bottleneck |
| [cpu-product-bypass.md](cpu-product-bypass.md) | Step5C original matrix50033→47887, all1024 product/write/consumer schedules and paired/IRQ/hold qualification |
| [cpu-owner-split.md](cpu-owner-split.md) | Step5B cycle-preserving private owner split, exact5A schedule audit and matched master fit |
| [master-consolidation.md](master-consolidation.md) | Accepted5A source/history consolidation, sole master and limited owner-reported board observation |
| [cpu-frontend-delivery-fit.md](cpu-frontend-delivery-fit.md) | Verified78MHz RBF, exact178-input audit, seed42 resources and actual78/104 timing; timing gate red |
| [cpu-frontend-delivery.md](cpu-frontend-delivery.md) | Step5A matrix52125→50033 and ThumbJPEG86428→84353, zero added state, matched call/return ownership and failed/corrected traces |
| [cpu-store-second.md](cpu-store-second.md) | Step4G two pending bits, transpose4041→3625, exact4F comparison and held/fault/banked ownership |
| [cpu-store-late.md](cpu-store-late.md) | Step4F private early store address, exact late data,192-pair/384-write ledger, transpose gain and fault/permission/MMIO qualification |
| [cpu-issue-recovery.md](cpu-issue-recovery.md) | Step 4E exact 65-load/34-clock causal accounting, registered CPU redirect handoff, original transpose/matrix gains, FCSE correction and focused hazards |
| [cpu-load-overlap.md](cpu-load-overlap.md) | Step 4D independent ARM load-pair qualification, actual reply-edge RAM work, ordered register/store traces, pair-loop/transpose gains and preserved store stream |
| [cpu-load-delivery.md](cpu-load-delivery.md) | Step 4C registered waiting-load probe choice, exact 32-cycle transpose gain, first-load classification, stale/fault checks and preserved 71-cycle stores |
| [cpu-store-credit.md](cpu-store-credit.md) | Step 4B spare registered credit, one-clock store acceptance/write stream, peak-pressure/reset checks and transpose's remaining load dependency |
| [cpu-store-overlap.md](cpu-store-overlap.md) | Step 4A real ARM store overlap, first instruction pair, ordered memory/exception checks and loop/transpose cycle gains |
| [cache-probe-admission-retime-fit.md](cache-probe-admission-retime-fit.md) | Stop 3D matched seed-42 fit, actual input audit, new probe/RAM endpoints, 78/104 MHz corner comparison and remaining admission/exclusion retiming |
| [cache-probe-admission-retime.md](cache-probe-admission-retime.md) | Stop 3C registered probe scheduling, preserved store/admission gates, actual CPU cost and next-fit decision |
| [cache-resident-store-pipeline-fit.md](cache-resident-store-pipeline-fit.md) | Matched seed-42 full-core resources, 78/104 MHz routed analysis, input audit and retiming decision |
| [cache-resident-store-pipeline-qualification.md](cache-resident-store-pipeline-qualification.md) | Stop 3A lifecycle/probe/refill qualification, corrected pulse/fast-return ownership, failing traces and matched-fit decision |
| [cache-resident-store-pipeline-prototype.md](cache-resident-store-pipeline-prototype.md) | Isolated Step 2 store pipeline, one-clock acceptance/actual commit, dirty forwarding and replayable source overlay |
| [cache-resident-stream-baseline.md](cache-resident-stream-baseline.md) | Verified Step 1 cache-port streaming fixture, actual RAM/dirty-half checks, four-clock baseline and implementation handoff |
| [cpu-pipeline-architecture-review.md](cpu-pipeline-architecture-review.md) | Current CPU/cache cycle traces, same-clock speed limits, recommended pipeline, resource budgets and ordered qualification plan |
| [dsp-mapping-audit.md](dsp-mapping-audit.md) | Fitted CPU full-product mapping, DSP inventory, original instruction mix and workload qualification |
| [mmc-writes.md](mmc-writes.md) | Implemented MMC write interface, RAM/ACK ownership and local protocol/DMA qualification; physical gates pending |
| [sis-library.md](sis-library.md) | Verified 1 GB installer MMC with383 SIS packages, native Manager layout and internal C: limits |
| [jpeg-next-performance.md](jpeg-next-performance.md) | POP/BX return recognition adopted in b707ebd: +9.40% local JPEG throughput, four state bits; physical/native gates pending |
| [cache-probe-timing.md](cache-probe-timing.md) | b313 worst-path analysis, parallel probe selection and reset payload separation with unchanged benchmark cycles |
| [calendar-benchmark-flash.md](calendar-benchmark-flash.md) | Native C: block-read fault during deferred erase, bounded NOR width correction and CPU/save qualification |
| [cache-certificate-capacity.md](cache-certificate-capacity.md) | Eight checked-line metadata records; JPEG +7.06%, precise ownership,212 bits and physical gate pending |
| [block-transfer-sequencing.md](block-transfer-sequencing.md) | Quarantined block-transfer fusion; native privileged POP fault isolated and corrected candidate tested |
| [cache-admission-probe.md](cache-admission-probe.md) | Reuse the admission-edge RAM pre-read; one metadata bit, JPEG +2.39%, original indices230.32/193.72 |
| [thumb-prediction-address.md](thumb-prediction-address.md) | Removed false Thumb mode-bit redirects; original JPEG +2.29%, unchanged ARM suite, bounded ALU change |
| [cpu-optimization-status.md](cpu-optimization-status.md) | Complete implemented/remaining CPU-cache ledger; P0, Thumb and admission-read improvements; original indices230.04/193.48 |
| [cache-completion-overlap.md](cache-completion-overlap.md) | First F2 consume/admit overlap, no new state, indices225.16/189.38; deeper unresolved-request parallelism remains |
| [cache-store-completion.md](cache-store-completion.md) | Owned posted/resident store completion, no new state, indices206.04/179.25 and full qualification |
| [cpu-branch-return.md](cpu-branch-return.md) | Owned BTB feedback, corrected returns/confirmed targets, indices186.93/167.87 and matched branch/call controls |
| [fifo-flag-timing.md](fifo-flag-timing.md) | Late-ACK FIFO flag rewrite, unchanged cycles, exhaustive boundaries and pending routed timing |
| [spmark-jpeg-profile.md](spmark-jpeg-profile.md) | Native pixel-conversion hotspot, checked Thumb RTL benchmark and F2 priority |
| [spmark-jpeg-results.md](spmark-jpeg-results.md) | Dedicated original JPEG bitmap baseline table, separate from the six-kernel index |
| [spmark-jpeg-hang.md](spmark-jpeg-hang.md) | Confirmed input-decode timeout/scheduler deadlock, original-code reproduction and native trace |
| [mmc-remount.md](mmc-remount.md) | Accepted cold-mounted Sonic launch; optional QD-style hot-swap investigation |
| [mmc-native-dma-control.md](mmc-native-dma-control.md) | Hardware-qualified R2 fix, original RX2 rejection, donor contract and small DMA correction |
| [mmc-r2-order.md](mmc-r2-order.md) | Native CMD2 failure, donor comparison, original-driver reproduction and small long-response host correction |
| [cache-data-probe.md](cache-data-probe.md) | F1 independent read-B/write-A overlap, owned pre-read, collision proof and indices154.48/144.58 |
| [cpu-load-forwarding.md](cpu-load-forwarding.md) | Measured P2/Memory load-consumer overlap, producer priority, indices151.25/141.56 and next dual-port build gate |
| [cache-two-mapping.md](cache-two-mapping.md) | Second shared-context 1KiB mapping, exact faults, architectural TLB lifetime and measured C experiment |
| [cache-resident-way.md](cache-resident-way.md) | Independently measured indexed reads/stores, fresh dirty-RAM ownership and indices145.16/135.86 |
| [cache-store-absence.md](cache-store-absence.md) | E0 store-miss shortcut, 5→2-clock cache response, full benchmark and CPU/buffer qualification |
| [selected-way-pipeline-investigation.md](selected-way-pipeline-investigation.md) | Measured resident/absent lookup reuse, full-frame write-miss distinction and pipeline-compatible bank/owner contract |
| [cache-load-optimization-plan.md](cache-load-optimization-plan.md) | Measured9→6clock handoff reduction, owned-admission fix, staged permission/response improvements and later pipelining |
| [spmark-payload-profile.md](spmark-payload-profile.md) | Cycle-pressure profiling: internal data completion dominates, qualified observer and reordered optimization priority |
| [spmark-payload-results.md](spmark-payload-results.md) | Comparison table of original-payload simulation results, starting with baseline |
| [spmark-payload-simulation.md](spmark-payload-simulation.md) | Original SPMark/GLES kernels on current CPU RTL, fixed-work baseline, validated runner and skill |
| [spmark04-benchmark.md](spmark04-benchmark.md) | Completed native SPMark3D results, Thumb LDM CPU fix, delayed MMC insertion and timing/RTC limits |
| [mmc-spmark04.md](mmc-spmark04.md) | SPMark04 hardware mount attempt, native corrupted-card result, image identity and remaining boundary |
| [phone-functions.md](phone-functions.md) | Sequential on-hardware Calendar, Contacts, Profiles and remaining function verification, data readback and unresolved latency |
| [sim-mandatory-files.md](sim-mandatory-files.md) | Native serving-to-rejected transition, missing mandatory BCCH/Kc/FPLMN reads and small constant-profile correction |
| [sim-fifo-single-write.md](sim-fifo-single-write.md) | Native SIM SELECT byte loss, physical RAM-port correction and original RX CPU/board qualification |
| [bt-adsp-startup-race.md](bt-adsp-startup-race.md) | Native late Bluetooth result/shared ADSP waiter reproduction and actual CBUS transport leads |
| [adsp-native-link.md](adsp-native-link.md) | Actual unexpected ADSP response, original D550/ARM startup exchange, bounded transmitter and remaining production gates |
| [rf-native-media.md](rf-native-media.md) | Native media12 RF fix, exact-packet reproduction, hardware1E=00 qualification and subsequent native panic |
| [board-boot-91045a6.md](board-boot-91045a6.md) | Deployed build, clean cardless Phone, corrected active blocker and native MTC/SIM observations |
| [pmm-native-flash.md](pmm-native-flash.md) | Native PMM erase/status/program-tail controller fix, exact original-driver CPU tests and reset/dirty integration |
| [phone-profile-startup.md](phone-profile-startup.md) | Native profile count5 versus6 causes recreation/Phone timeout; C-only initialized-data control, original-ROM Phone progress and reader gaps |
| [menu-blocker-map.md](menu-blocker-map.md) | Consolidated Phone/ViewSrv, EStor wait, PMM/DSY panic, SIM and self-test evidence; standalone software observer |
| [lcd-pair-order.md](lcd-pair-order.md) | Shared low-first scanout correction, independent natural-coordinate oracle and CRT/HDMI source tests |
| [board-boot-b656156.md](board-boot-b656156.md) | Original-ROM automatic boot passes old reset, healthy queue, idle/logo foreground gate and failed seed44 timing |
| [save-queue-fault-2026-11-13.md](save-queue-fault-2026-11-13.md) | Qualified SDRAM IO packing/fit, clean boot queue-fault reset, containment and next DDR cause/count capture |
| [sdram-early-boot-2026-11-13.md](sdram-early-boot-2026-11-13.md) | New bad-pointer captures, dbe5bc6 isolation, SDRAM pin-register correction and subsequent IO-packing/board qualification |
| [crt-pixel-hold.md](crt-pixel-hold.md) | Reproduced CRT left-edge RGB corruption, existing-register hold fix and continuous-output tests |
| [diagnostic-disk-retirement.md](diagnostic-disk-retirement.md) | Removed diagnostic disk/OSD and fourth HPS slot; retained DDR debugger and verification |
| [euart-production-integration.md](euart-production-integration.md) | Completed production UART/CTSI host boundary, native CPU FIQ tests and remaining D550 peer gate |
| [sim-adsp-native-progress.md](sim-adsp-native-progress.md) | Native SIM dynamic-flags tests, D550 test42/codec implementation and remaining transport/readiness gates |
| [donor-stub-update-2026-11-12.md](donor-stub-update-2026-11-12.md) | Retail-input versus patched execution, new IMEI/SIM completions and native HDL-only applicability |
| [adsp-rom-investigation.md](adsp-rom-investigation.md) | Original DA250 image, RAM relocation, architecture evidence and matching diagnostic42 handler |
| [native-startup-hdl.md](native-startup-hdl.md) | Strictly original-firmware startup requirement, native RF/ADSP contracts and hardware qualification gates |
| [menu-bringup-2026-11-12.md](menu-bringup-2026-11-12.md) | Live DDR C: capture, Phone exit, no-radio Bluetooth comparison and guarded exit tracing |
| [ui-startup-processes.md](ui-startup-processes.md) | Frozen6B/7B process inventory, CPU ownership, waits and next Phone/EFile request trace |
| [installation-flash-stall.md](installation-flash-stall.md) | Native SIS completion, stopped flash context,217 unsaved sectors and passive wait-state visibility |
| [save-blockers-2026-11-12.md](save-blockers-2026-11-12.md) | Autosave/manual error isolation, Main ACK/file-write ordering and remaining stall evidence |
| [ddr-diagnostics.md](ddr-diagnostics.md) | SSH runtime text/snapshots, DDR format, verification and deferred save/video defects |
| [sim-ui-run.md](sim-ui-run.md) | Fresh frozen integration simulation, 1B/100M checkpoint schedule and live key commands |
| [checkpoint-compatibility.md](checkpoint-compatibility.md) | Verified old10.5B restore, integration incompatibility and fresh production-path boot profile |
| [timing-78-recovery.md](timing-78-recovery.md) | All1,000 paths from43083011635, four root-cause fixes, measured costs and ngage1 deployment |
| [register-file-area-audit.md](register-file-area-audit.md) | Production RF cost/port ownership, safe area candidates and upcoming PCM audio headroom |
| [lcd-dma-timing-recovery.md](lcd-dma-timing-recovery.md) | Successful fit/new setup failure, LCD header validation and local DMA response boundary;78 MHz operation/104 MHz objective |
| [cpu-armv4t-profile.md](cpu-armv4t-profile.md) | First CPU optimization: remove ARMv5/5TE execution paths, conditional UND/Thumb links, regression and payload evidence |
| [cpu-donor-import-plan.md](cpu-donor-import-plan.md) | Ordered benchmark-first CPU imports, full difference coverage, measurement/acceptance rules and Call of Duty validation |
| [cpu-donor-baseline-results.md](cpu-donor-baseline-results.md) | First480 measured ARM baseline runs, deterministic/counter qualification, refill tradeoff and remaining phase00/01 gates |
| [cpu-donor-comparison.md](cpu-donor-comparison.md) | Current ZAP versus donor ARM9V2 execution/decode, specific port candidates and benchmark limits |
| [donor-resource-comparison.md](donor-resource-comparison.md) | Active architecture/resource differences, extra FF snapshots/readback, diagnostics and donor MLAB RF candidates |
| [area-reductions-2026-11-12.md](area-reductions-2026-11-12.md) | DMA/boot RAM reuse, bounded state, tests and measured launch costs |
| [jtag-diagnostics-plan.md](jtag-diagnostics-plan.md) | JTAG/SSH DDR3 process and log diagnostics, host requirements and hardware gates |
| [timer-readback-ram.md](timer-readback-ram.md) | Timer control/status upper-word RAM conversion and expiry ordering |
| [ram-conversions.md](ram-conversions.md) | DMA queue/passive timer-ICU BRAM conversions, snapshot/reset contracts and measured performance |
| [fit-recovery.md](fit-recovery.md) | Failed integration fit attribution, BRAM/register recovery, DMA worker measurements and verification |
| [irq-timer-keypad-flow.md](irq-timer-keypad-flow.md) | Original NEM-4 IRQ pending/current, programmable timers, configured keypad edges and combined verification |
| [general-timers.md](general-timers.md) | Six parallel programmable counters, original timer routines, reprogram/ACK semantics and 78/104 MHz rate evidence |
| [lcd-dma-handover.md](lcd-dma-handover.md) | Production DMA/IRQ ownership, fast LCD stream, matched speed results, row bands, reset and remaining verification |
| [mmc-port.md](mmc-port.md) | Read-only production MMC slot, native host/card, FIFO/DMA/IRQ and HPS ownership tests, image tooling and remaining driver/hardware gates |
| [performance-path-retirement.md](performance-path-retirement.md) | Faster-path replacement policy, LCD switch retirement, next direct-SDRAM cleanup and measured DDR tradeoffs |
| [peripheral-integration.md](peripheral-integration.md) | B1 SDRAM/local route, P1 IRQ ownership, P2 byte-count engine/original-driver tests and DMA/MMC integration gates |
| [semi-real-nos.md](semi-real-nos.md) | N1/N2 original NOS ownership, ARM cancel/receive/charger fixtures and selective service boundaries |
| [mister-rtc.md](mister-rtc.md) | MiSTer Unix-time UEM clock, original-firmware tests and remaining PMM calendar boundary |
| [background-save.md](background-save.md) | S3 ordered C:/PMM queue, background scheduling, failure reporting and verification |
| [ddr-bulk-persistence.md](ddr-bulk-persistence.md) | D3 sector snapshots, restores, ordering and 4 KiB host assessment |
| [ddr-flash-cache.md](ddr-flash-cache.md) | D2 shared flash backing cache, writer ordering, sizing and tests |
| [ddr-stream-transport.md](ddr-stream-transport.md) | Opt-in D1 scalar/line/sector stream transport, buffered ownership/reset contracts and verification |
| [raw-persistence.md](raw-persistence.md) | Raw C:/PMM images, lossless NGA migration, three-slot mount/save/reset policies and verification |
| [integration-baseline.md](integration-baseline.md) | P0 source/toolchain identities, transaction contracts, retained measurements and fixture repairs |
| [merge-plan.md](../merge-plan.md) | Complete ngage2 integration plan: branches, semi-real NOS/SIM, peripherals, raw C:/PMM images, DDR/SDRAM and CPU candidates with dependencies and tests |
| [factory-first-boot.md](factory-first-boot.md) | Why a blank C: stopped at the logo, the PMM record that makes the stock firmware format it, the factory image tool and board runs |
| [symbian-startup.md](symbian-startup.md) | Current hardware panic, passive category/reason recorder, corrected simulation and next boot evidence |
| [peripheral-ownership.md](peripheral-ownership.md) | Regional UPP RAM ownership and sparse-register transaction contracts |
| [cpu-operand-stage-contract.md](cpu-operand-stage-contract.md) | Slice1 exact operand ownership/cycle contract, differential reference and measured latency/throughput tradeoffs |
| [cache-lookup-stage-contract.md](cache-lookup-stage-contract.md) | Slice2 cache lookup ownership, lookahead epochs, latency attribution and validation |
| [cpu-performance-redesign-notes.md](cpu-performance-redesign-notes.md) | Future cache/LSU/CPU performance redesign options, latency baseline and104MHz verification gates |
| [memory-performance-baseline.md](memory-performance-baseline.md) | Collected cache, TLB, SDRAM and DDR cycle measurements, provenance and new-core comparison procedure |
| [direct-sdram-path.md](direct-sdram-path.md) | Dedicated CPU SDRAM route, retained registers, admission/cancellation contract and cache-miss measurements |
| [uncached-fetch.md](uncached-fetch.md) | Measured boot-delay costs, resident instruction hits and CPU request/return handoffs |
| [sdram-native-validation.md](sdram-native-validation.md) | Native SDRAM runtime procedure, measured latency results and remaining board/fit gates |
| [sdram-request-ownership.md](sdram-request-ownership.md) | Shared scalar write payload, reset-drain admission, unchanged latency and cache refill/commit storage explanation |
| [fpga-build-43327385834.md](fpga-build-43327385834.md) | Fitted resource comparison, 78 MHz setup failure at two diagnostic snapshot RAM endpoints and retained timing evidence |
| [cache-line-refill.md](cache-line-refill.md) | Registered ARM line transport, DDR bursts, direct SDRAM fill and overlapping logical-port follow-up |
| [ddr-rom-cache.md](ddr-rom-cache.md) | Instruction-only DDR ROM buffer, 64/128/256-bit × 1/2/4 KiB boot comparison, reset/reload and validation |
| [write-buffer-stage-contract.md](write-buffer-stage-contract.md) | Pipelined write-buffer reservation, local commit, capacity/hazard ownership and latency validation |
| [cpu-cache-sdram-104mhz-plan.md](cpu-cache-sdram-104mhz-plan.md) | Source-grounded whole CPU/cache/memory review, proposed 104 MHz architecture, cycle/resource budgets and ordered implementation gates (plan only) |
| [ngage2-timing-investigation.md](ngage2-timing-investigation.md) | Separate donor104 MHz investigation, per-corner failing1000 export, worker/LCD port assessment and portable patches |
| [timing-closure.md](timing-closure.md) | 104 MHz baseline, worst-1000 timing exports, CI gate and path analysis |
| [phone-clocks.md](phone-clocks.md) | Phone reference clocks, slower interfaces, timebase assumptions and bus-bridge follow-up |
| [quartus-memory-audit.md](quartus-memory-audit.md) | Actual Quartus RAM inference, register-heavy arrays and resource-reduction priorities |
| [rtl-style.md](rtl-style.md) | Phone RTL formatting rules and reproducible formatter/check command |
| [status.md](status.md) | Current development checkpoint and ordered resume work |
| [TODO.md](TODO.md) | Assumptions and shortcuts to replace, with evidence and validation |
| [lcd-command-evidence.md](lcd-command-evidence.md) | Fresh HDL LCD fixture, decoded window framing and unresolved initialization commands |
| [display-bringup.md](display-bringup.md) | Firmware-driven LCD and startup display experiments |
| [nortido-hybrid-reference.md](nortido-hybrid-reference.md) | Hybrid-core LCD/keypad/MMC leads, local trace cross-check and limits of patched guest behavior |
| [firmware-overlays.md](firmware-overlays.md) | Independent NOS/Bluetooth menus, private packages, automatic loading, shared checksum and checks |
| [nortido-compatibility-inventory.md](nortido-compatibility-inventory.md) | Counted NOS/Bluetooth/audio/boot substitutions and a concrete reset-only OSD backend design |
| [hardware-checkpoints.md](hardware-checkpoints.md) | Current export limitations and required hardware-to-Verilator checkpoint design |
| [bringup.md](bringup.md) | CPU integration boundary, simulation tools, diagnostics and output locations |
| [speculative-fetch-deadlock.md](speculative-fetch-deadlock.md) | Queued return blocked by an abandoned I-cache refill, scoped fix, checkpoint recovery and verification limits |
| [cpu-patches.md](cpu-patches.md) | Why the ZAP patches exist and how they were checked |
| [branch-prediction.md](branch-prediction.md) | BTB collision root cause, self-contained return reproducer and patch 0006 |
| [arm920-tlb.md](arm920-tlb.md) | Production64-entry I/D TLBs, CP15 replacement/lockdown, staged lookup and legacy-cache removal |
| [mmu-reference.md](mmu-reference.md) | Opt-in native MMU execution, physical access checks and comparison scope |
| [extension-reconstruction.md](extension-reconstruction.md) | Preserved ROOT, reconstructed extension, opt-in boot I/O and MMU-stage debugging |
| [uem-control-bus.md](uem-control-bus.md) | Post-MMU conversion sequence, retained UEM reference and missing battery-identification input |
| [firmware-integrity.md](firmware-integrity.md) | Embedded MD5 mismatch, independently verified FPGA digest and read-only reproducer |
| [firmware-inventory.md](firmware-inventory.md) | All firmware variants, verified Z: files, recovered retail ROOT content and developer analysis databases |
| [flash-layout.md](flash-layout.md) | Confirmed chip capacity, bank-table audit and unresolved dump placement |
| [boot-model.md](boot-model.md) | Physical map, flash/register experiments, strict limits and assumptions |
| [software-reference.md](software-reference.md) | EKA2L1 findings, executable software comparison and LCD trace |
| [references.md](references.md) | Pinned sources, physical versus virtual maps and dump provenance |
| [modem-model.md](modem-model.md) | Reversed ISI/Phonet protocol and NOS servers (energy, phone-info, SIM); spec for scratch/modem + rtl/ngage_modem.v |
| [sdram-104mhz-ddio.md](sdram-104mhz-ddio.md) | 104 MHz DDIO clock/read-capture fix, timing-model evidence and remaining hardware gates |
| [mister-review-2026-11-06.md](mister-review-2026-11-06.md) | Independent milestones 0–5 review, reproduced reset bug, validation and revised next steps |
| [service-firmware-loader-plan.md](service-firmware-loader-plan.md) | Original boot.rom/boot1.rom service files, order-independent overlays and separate raw C:/PMM implementation plan |
| [mister-implementation-plan.md](mister-implementation-plan.md) | Code-audited migration plan, image inventory, persistence, controls and hardware validation gates |
| [hdl-migration.md](hdl-migration.md) | C++ board model -> rtl/ngage_board.v plan, migrated devices, what is still C++-only |

ARM reference manuals are local PDFs in this folder. Reference checkouts and
supporting research are retained under project `scratch/`; generated traces and
result/provenance JSON are under `build/`.

When development advances, update the relevant topic document and `status.md`.
Record the exact firmware/profile, changed assumption, result path and next unknown.
Keep evidence, hypotheses and unimplemented ideas distinct. Preserve failed
approaches that would otherwise be tempting to retry; do not rerun expensive
checks just to reconstruct already documented results.

- [MiSTer SDRAM transport and verification](mister-sdram.md)

- [MiSTer flash and working save](mister-flash-save.md)

- [MiSTer board-device migration](mister-board-bringup.md)

- [Chip inventory and interconnect status](chip-inventory.md): schematic-based NEM-4 component identities, current HDL boundaries and explicitly unmodeled pins.
