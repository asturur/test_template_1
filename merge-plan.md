# N-Gage donor integration plan

Updated 2026-11-11. **P0 through S3 and D1 through D3 committed. The integration build enables D1, D2 and D3.**

Publication checkpoint: the user authorized committing and pushing the current
N1/N2 ABI evidence, P1/P2 DMA/LCD work and P3.0-P3.3 MMC implementation on
`codex/ngage2-integration`. The measured source hashes and stage results below
remain authoritative; older "uncommitted/no push" notes describe capture time.
A fresh RBF is needed for the new slot-2 menu. Controller/image attachment is
verified locally, while original-firmware filesystem mounting/use is P3.4 and
writable persistence is P3.5. No hardware deployment is part of this publication.

This plan combines raw C:/PMM persistence, the DDR backend, SDRAM controller,
useful CPU changes, semi-real NOS/SIM, and the peripheral work. Creating the
branches and writing this document do not authorize a build, deployment or
firmware modification. Subsequent implementation should follow the stages and
acceptance gates below.

### Production performance policy — 2026-11-11

When a faster implementation covers the same behavior and passes its required
tests, it replaces the slower production path; do not retain a performance
switch just for rollback. Preserve the historical branch and measured evidence.
Keep routes that serve different transactions and choices with measured workload
or resource tradeoffs until those are resolved. In particular, scalar DDR
requests and general DMA for on-chip RAM remain necessary functions.

The validated LCD stream is now automatic for eligible SDRAM descriptors:
`FAST_LCD` and the `PHONE_FAST_LCD=0` production CPU mode are removed. Generic
LCD DMA coverage now uses a real on-chip RAM source instead of disabling the
fast transport. Rerun CPU, ISR, host fences and bounded boot after this cleanup.
Next retire the slower `DIRECT_SDRAM=0` route after migrating its reset/ownership
fixtures, then remove obsolete legacy DMA ownership from the production shell.
DDR streaming/cache choices have measured cold/reuse/scan tradeoffs and need
the actual selected D1/D2/D3 production chain in the boot harness before further
retirement. See [path-retirement evidence](docs/performance-path-retirement.md).

## 1. Branches, sources and reproducible comparisons

Branches created before this plan was written:

- `codex/ngage2-baseline`: original committed implementation at
  `7f55e93982219b8ad5315b785e63be4d4532a756`.
- `codex/ngage2-integration`: active branch for this plan and subsequent
  integration work; initially based on the same commit.
- `master` remains at that original commit at plan creation.

The checkout already contained uncommitted changes in `docs/README.md`,
`docs/bringup.md`, `docs/status.md`,
`tests/phone/hardware_boot/logo_main.cpp`,
`tests/phone/hardware_boot/tb.v`, and untracked
`docs/hardware-checkpoints.md`. They were preserved without staging, stashing
or committing them. The baseline branch records committed source; it does
not snapshot those working files. This plan and its documentation links are
also uncommitted until explicitly committed later.

Donor: `/Users/andreabogazzi/develop/ngage2`, commit
`e3d2bf778319bdf4ef2bf21a4fc7376186b00a63`. It targets QD RH-29 4.60 and a TI
ARM925T. This project targets original N-Gage NEM-4 4.03 and ARM920T behavior.
Keep the donor checkout read only and preserve its license/provenance notices.

Branch and build rules for implementation:

1. Work and build from `codex/ngage2-integration`, recording the actual branch,
   full commit and any dirty patch/source hashes in every result manifest.
2. Complete one reviewable stage at a time. Do not mix firmware compatibility,
   memory scheduling, CPU semantics and clock changes in one experiment.
3. Before the first CPU replacement, preserve a **new common integration
   checkpoint with the existing ZAP CPU and the new peripherals/storage** on a
   branch such as `codex/ngage2-zap`. The original baseline alone cannot give
   a fair old/new CPU comparison once peripherals have changed.
4. Branch the ARM9V2 trial from that same checkpoint. Compare identical memory,
   firmware, clock, overlays, images and input sequences. Retain useful commits
   so changing branches can select either CPU with the integrated peripherals.
5. Do not switch branches through uncommitted work or automatically stash
   someone else's changes. Finish/preserve owned work first. If simultaneous
   checkouts become necessary, use the app's worktree tooling when authorized.
6. For a later remote CI build, use `gh` exclusively, push the intended branch
   when authorized, dispatch with that explicit branch ref, and verify the
   returned run's commit. Never accidentally build the default branch. No push
   or workflow dispatch is part of this planning step.
7. Keep experiments and reference fixtures under `scratch/`; generated build
   outputs under `build/`; screenshots under `build/sim/screens/`. Keep firmware,
   private overlay packages and user save images out of Git.

### Worktree isolation (2026-11-10 follow-up)

Integration work now belongs to this chat's managed worktree:
`/Users/andreabogazzi/.codex/worktrees/ngage2-integration/NGage_MiSTer`,
on branch `codex/ngage2-integration`. The original checkout at
`/Users/andreabogazzi/develop/NGage_MiSTer` is back on `master` for the other
chat. Its existing documentation, hardware-boot edits and running simulations
remain there; they were not copied or stashed. Only this plan and this chat's
plan-index/status additions were moved.

Use the integration worktree explicitly for all future edits and builds in
this chat. Keep separate output/log directories and immutable per-run source
manifests. Ignored firmware, scratch data and checkpoints are not automatically
available here; reference original immutable inputs read only or create an
explicit local copy when a later test needs them. Never redirect new outputs
into the other checkout's active build or simulation directories. Branches and
Git history remain shared, so coordinate repository-wide Git operations.

The baseline branch still records the original committed CPU. Future old/new
CPU branches should be created from the same integrated peripheral checkpoint
and used only in this worktree or separate explicitly assigned worktrees.

## 2. Final-core intent: semi-real NOS

**The final target keeps original NOS startup and meaningful original NOS
runtime behavior. A universal return-success or all-services-faked NOS is not
the final architecture.**

Use the already decoded NEM-4 code, existing reverse-engineering evidence in
`docs/modem-model.md`, and measured execution to retain original scheduling,
service registration and handlers wherever they work. Replace or model only
the specific unavailable external services/events that have an audited
boundary. The current hardware evidence favors keeping original NOS startup;
the replacement bootstrap prevented the logo and remains diagnostic only.

Evidence hierarchy: original NEM-4 code and reached transactions first, matching
phone observations next where available, donor/QEMU models as implementation
leads. A software/RTL match establishes consistency, not verified silicon.

The NOS service ownership table must identify, per resource/channel:

- Original code retained and the exact call/dispatch boundary.
- Whether the original handler runs or a replacement owns that request.
- Request/reply layouts, transaction/object identity and asynchronous delivery.
- Required state, cancellation, teardown, timer and interrupt behavior.
- Evidence, known gaps and explicit synthetic values.

Exactly one owner may complete a request. Original and replacement handlers
must not both reply, mutate shared state independently, or acknowledge each
other's interrupts. If a mixed original/replacement routing scheme cannot be
made safe at the audited boundary, stop and redesign that boundary; do not
silently expand the replacement to all NOS behavior.

Temporary fully synthetic profiles may help diagnosis, but must be named and
recorded separately. Final semi-real acceptance requires traces showing original
NOS runtime work, not merely one call to its entry point followed by a complete
stub. Keep an original/unmodified comparison profile and explicit compatibility
selection. Unknown requests remain visible; fabricate no blanket success.

SIM compatibility is a logical offline handset service, not a cellular network
or physical SIM implementation. Support explicit no-card and synthetic-ready
profiles only as their NEM-4 clients justify. Physical SIMIF/ATR/APDU work remains
separate and must not be presented as validated by logical SIM replies.

Exclude donor C: formatting/auxstart shortcuts, UI/startup bypasses, hardcoded
QD kernel addresses and Bluetooth retry-limit patches. A missing hardware
service should not be hidden by patching the application that waits for it.

## 3. Target boundaries and port selection

Retain ARM920T CP15/cache/TLB/maintenance semantics, original flash identities
and descrambling, existing firmware loading and chip-oriented board ownership.
Keep current 78 MHz operation for attributable comparisons; 104 MHz is a
separate measured target, not an assumed consequence of a port.

| Area | Decision |
| --- | --- |
| DDR flash backend | Adapt donor cache/beat-buffer/streaming architecture behind our physical mapping and NOR models |
| SDRAM | Evaluate complete alternative controller, then writes and bank mapping separately |
| C:/PMM | Move to separate raw images mounted through stock MiSTer block I/O |
| NOS/SIM | Retain working original runtime; adapt donor queues/replies only at audited missing-service boundaries |
| DMA/MMC | Port general DMA, host, card model, metadata/image tools and tests together |
| LCD | Adapt FIFO/packing/DMA transport; retain NEM-4 panel commands and investigate missing panel behavior |
| RTC/UEM/CBUS | Port wall-clock infrastructure; adapt only justified register/protocol behavior |
| Keypad | Keep original wiring and fixed W1C; evaluate generic matrix connectivity separately |
| Timers/ICU | Retain current rates and ownership; extend real device sources and validate semantics |
| Audio | Adapt PCM backend and NOS buffer protocol as explicitly modeled DSP replacement |
| Bluetooth | Retain existing independent HCI compatibility; verify integration, do not copy retry shortcuts |
| Traces | Adapt retirement/data/bus rings and decoder; not a hardware checkpoint system |
| CPU | Add useful tests and isolated changes; evaluate complete ARM9V2 integer pipeline later |
| NOR/chip models | Keep NEM-4 AMD geometry and physical component boundaries; no wholesale QD Samsung substitution |
| Unmodeled hardware | Keep RF, codec/FM and unsupported chip pins explicitly unimplemented unless a separately evidenced implementation is required |

Primary donor sources: `rtl/mem/ddram_flash.sv`, `rtl/mem/sdram.sv`,
`rtl/mister/flash_save.sv`, `rtl/upp/upp_dma.sv`, `rtl/upp/upp_mmc.sv`,
`rtl/board/mmc_card.sv`, `rtl/upp/upp_lcdif.sv`, `rtl/mister/rtc_wall.sv`,
`rtl/upp/upp_haudio.sv`, `model/nos-stub/`, `rtl/cpu/arm9v2/`,
`rtl/cpu/zap/`, and their `sim/` benches and tools.

Donor game/timing results are reported evidence, not independently reproduced
here. Its released core still fails 104 MHz timing. Some historical donor
measurement artifacts are no longer present; distinguish logs from available
reproducible fixtures.

## 4. Storage format and user flow

The donor's `releases/boot0.vhd` is exactly 4,194,304 bytes with no VHD container
footer. Here `.vhd` means a raw file mounted through MiSTer, not a dynamic VHD,
partitioned PC disk or FAT replacement for the phone's flash filesystem.

Our NGA already uses that block interface. The migration simplifies image
layout and automatic mounting; it does not by itself accelerate guest flash.

| Slot | Use | File and layout |
| --- | --- | --- |
| S0 | C: | `boot0.vhd`, exactly 0x400000 bytes, flash byte zero at file offset zero |
| S1 | PMM | `boot1.vhd`, exactly 0x10000 bytes, PMM byte zero at file offset zero |
| S2 | Future MMC | Optional `boot2.vhd` automatic alias or manually selected `.mmc` image |
| S3 | Diagnostics | Manually mounted diagnostic image; optional automatic alias only if deliberately provided |

Existing `boot.rom`, `boot1.rom`, NOS `boot2.rom` and BT `boot3.rom` are firmware
transfers in a separate namespace; preserve their semantics. Local retained
Main source supports `boot0.vhd` through `boot3.vhd`; installed-Main behavior
and four-slot routing still need testing. Move current S1 diagnostics to S3
with explicit OSD/documentation changes and migration instructions.

No silent default PMM creation or formatting. A complete handset backup contains
both C: and PMM. Raw images lose NGA's embedded provenance check: retain validated
firmware gates and host-side conversion manifests, explicitly document that
ordinary raw mounting cannot establish the image's original firmware identity.
Renaming an NGA file does not convert it. Keep original NGA files for rollback.

## 5. Dependencies and completion rules

Dependencies denote an accepted interface/decision, not compulsory adoption of
every experimental implementation. For example, R1 may conclude that the
existing controller is preferable; later CPU work still needs its stable
contract. No delegation or parallel agents are implied by independent tracks.

| ID | Deliverable | Depends on |
| --- | --- | --- |
| P0 | Baseline, provenance, contracts and measurements | Branch setup |
| S1 | Raw-image specification and lossless NGA conversion | P0 |
| S2 | Raw C:/PMM mount/restore/flush on existing scalar backend | S1 |
| D1 | DDR ownership and streaming interfaces | P0 |
| D2 | General coherent flash read cache | D1 |
| D3 | Bulk sector snapshots and wider restore writes | D1, S2 |
| S3 | Ordered bounded background saving | S2, D3 |
| R1 | Alternative SDRAM controller and stable wrapper | P0 |
| R2 | Consecutive word writes and gathered line writes | R1 |
| R3 | Optional four-bank interleaving | R1 |
| B1 | Peripheral-master route and atomic arbitration | P0, D1 and stable SDRAM contract |
| N1 | NEM-4 NOS service/ABI ownership audit | P0 |
| N2 | Selective channel transport, queues and completion | N1 |
| N3 | Stateful missing-service and SIM handlers | N1, N2 |
| N4 | Overlay capacity, loading and semi-real integration | N2, N3 |
| P1 | Timer/ICU/UEM ownership and peripheral source map | P0, N1 |
| P2 | General DMA | B1, P1 |
| P3 | MMC host/card/image tooling | P2, S2 slot layout |
| P4 | LCD transport and partial-update behavior | P2, P1 |
| P5 | RTC and UEM calendar integration | N1, P1 |
| P6 | Keypad connectivity and input integration | P1 |
| P7 | ARM game PCM audio | B1, P1; minimal guest playback bridge |
| P8 | Bluetooth coexistence and remaining chip audit | P1, D2 coherence contract |
| Z1 | CPU behavior audit and regression additions | P0 |
| Z2 | MLAB register-file experiment | Z1 |
| Z3 | Arithmetic/prediction experiments | Z1 |
| Z4 | Early refill completion and hits during a miss | Z1, stable D2/R1 interfaces |
| Z5 | Optional ARM9V2 integer-core branch | Z1, common integrated ZAP checkpoint |
| T1 | Hardware trace rings/decoder | D1, Z1 observation definitions |
| I0 | Combined simulation, fit and hardware qualification | Selected completed stages; semi-real NOS gate mandatory |

Each stage records source changes, dependencies, exact tests, results, measured
limits and disposition: planned, in progress, accepted, rejected or deferred.
P0/S1/S2 are locally implemented and regression-accepted as recorded below.
Physical/Main acceptance remains explicitly deferred. All other port stages
remain planned; their tests below are future work.

## 6. P0: baseline and contracts

Record exact sources, firmware/profile, overlays, CPU, clocks, inputs and existing
dirty work before implementation. Preserve current simulator archives and all
paired permanent checkpoints. Do not restart or modify the active long run.

Write acceptance/completion/cancellation contracts for scalar requests, line
requests, flash mutations, save snapshots, peripheral masters and reset. Enumerate
all DDR writers: loader, overlays, restore, NOR program/erase, diagnostics.
Preserve explicit unsupported-operation diagnostics.

Measure cold and cache-active workloads separately: CPU-visible latency,
architectural instructions, branch/load/store throughput, DDR commands/beats,
flash cache reuse, SDRAM row locality/occupancy/refresh, restore/flush time and
resources. Simulator host cycles/second are not phone performance. A cache-off
startup delay loop does not measure cache speed.

Tests/gate: reproduce relevant existing CPU, line, flash, reset, storage and
SDRAM regressions before attributing later failures to the donor. Use the
existing `jotego/simulator:arm64` image. Retain original NEM-4 clocks and
peripheral assumptions in the first comparisons.

### P0 result — 2026-11-10: locally accepted

Baseline commit `7f55e93982219b8ad5315b785e63be4d4532a756`, isolated branch
`codex/ngage2-integration`. Full tracked source hashes/initial dirty patch:
`scratch/ngage2-integration/p0/{source.json,dirty.patch}`. Baseline donor remains
read-only `e3d2bf778319bdf4ef2bf21a4fc7376186b00a63`; no donor implementation
has been imported in P0/S1/S2. Existing image:
`sha256:df6f55924d5fab96083d01332e45cd734f22277c4dd3b34f55a09cd8dbc3eb8d`.
Detailed contracts, firmware identities and retained-versus-future measurements
are in [docs/integration-baseline.md](docs/integration-baseline.md).

Fresh results: full CPU suite **180 PASS**, **13/13 selected phone suite entry
points PASS** after repairing stale test fixtures. Suites: legacy `save_hps`
(two actual-HPS tests including NOR/scalar DDR), full-size `save_manager`,
`save_sector`, `sd_sector`, `dirty_tracker`, `reset_gate`, `diag_export`,
`flash_reset`, `line_refill`, `memory_owner`, `sdram`, `sdram/run-ddio.sh`, and
`sdram/run-short-reads.sh`. Both original 78MHz and explicit104MHz/model-delay
SDRAM cases exercised; no new phone clock/profile changes.

Failures established first: missing private NOR firmware fixtures (copied
immutable inputs locally with hashes); standalone save-sector synchronous-BRAM
sampling error reproduces against original baseline bridge; three reset CPU
stubs lacked preexisting line-interface ports/parameter. Repaired only the test
fixtures. Failure summaries and retained pristine/stub failure logs are in P0 scratch. The initial manifest's statement
that no firmware was copied describes its capture time; completion supplement
and `fixtures.json` record later immutable copies. NOR tests read/compare those
bytes; they do not execute firmware. No running simulation/checkpoint touched.

Logs: `scratch/ngage2-integration/p0/{cpu.log,run.log,remaining.log}` and final
corrected bench logs; source graph171files/9QIPs and structural top elaboration
PASS. Hardware resources/timing/Main auto-mount/power-cycle and new whole-phone
performance measurements are deferred gates, not implied by local acceptance.

## 7. S1-S3: raw persistent storage

### S1: converter and rollback

Validate the existing NGA header/CRC/profile, then extract C: at offset 0x200
and PMM at offset 0x400200 into new exact-size files. Create a provenance/hash
manifest and support byte-exact reconstruction using original metadata.
Never overwrite inputs or silently import QD saves as NEM-4 saves.

Tests: valid and corrupt/truncated NGA, wrong sizes/profile, existing-output
rejection, first/last bytes of each region, unchanged source hashes and complete
round trip. Gate: identical extracted payloads and a usable rollback procedure.


#### S1 result — 2026-11-10: locally accepted

Implemented `split-raw` / `join-raw` in `tools/prepare_mister_save.py`.
The manifest retains the original NGA header verbatim, original source and
payload hashes, firmware/profile identity and region geometry. Reconstruction
validates header CRC/reserved metadata/profile and permits exact-size modified
payloads; NGA contains no payload CRC requiring recomputation. Exclusive output
reservation rejects existing files (including inputs) and rolls back only files
created by the failed operation. Source images remain untouched.

Validation: `python3 tests/phone/save_image/raw_test.py`, **7/7 test groups PASS**,
covering full-size payload equality/first/last bytes, both supported profiles,
byte-identical roundtrip, changed-payload valid metadata, wrong sizes, malformed
headers/CRC/reserved/profile, manifest mismatch and no-overwrite for each output.
Log: `scratch/ngage2-integration/s1-tests.log`. Fixtures are synthetic NEM-4
metadata, not QD imports or a private firmware execution claim. Hardware/Main
mounting and durability remain S2/later gates.

### S2: raw mounting before performance changes

Split `ngage_save_manager.sv` responsibilities into per-image mount/restore state
and shared transport as appropriate. Initially retain scalar DDR access so
format conversion is independent of D1-D3. C:/PMM file LBAs start at zero.
Restore both images before CPU release, in either mount order. Preserve reset
coordination, timeouts and protection against writing old dirty data to newly
mounted media. Define read-only/invalid/missing media outcomes; retain normal
persistent-mode rejection of unsuitable read-only images.

Extend `Template.sv` to four disk slots, arrays, masks and shared-buffer routing.
Keep manual mounting and explicit save. Saved means both images are clean and
their HPS handshakes complete. Do not interpret it as durable physical storage.

Tests: adapt `save_hps`, `save_sector`, `save_manager`, `reset_gate`, `sd_sector`
and `diag_export`. Exercise actual local `hps_io`, both mount orders, automatic
mount event timing, all four slots, delayed ACK, zero-size unmount, first/last
sectors, media replacement while dirty and resets during load/save. Gate:
old scalar-backend contents and raw-image contents agree byte for byte.

#### S2 result — 2026-11-10: locally accepted

Added `rtl/ngage_raw_save_manager.v`, with per-image pending/restored/error
state and a shared serialized scalar sector bridge/dirty tracker. Every raw
image starts at file LBA0; bridge default behavior preserves the legacy NGA
path for equivalence tests. Mount metadata is captured at the event, including
before firmware validation and during the peer's restore. Both images gate
CPU release. Missing/invalid/read-only/zero-size/replacement policies, dirty
protection, manual Save/error/ACK/reset behavior and raw provenance limits are
specified in [docs/raw-persistence.md](docs/raw-persistence.md).

`Template.sv` now routes all four stock `hps_io` slots: S0 C:, S1 PMM, S2
reserved/non-driving, S3 diagnostics. Firmware `.rom` namespace and independent
NOS/BT overlays are unchanged. No automatic background save or DDR cache/bulk
path was added. Save waits for both mounted regions, clean dirty scan/flash
quiescence and the final ACK fall. A rejected peer retains its own error until
that same slot is corrected; valid media on another slot cannot hide it.

Fresh tests on the existing simulator image:

- `tests/phone/raw_save/run-hps.sh`: **28 directed checks PASS**, actual four-slot
  `hps_io`,39reads/11writes. Both mount orders; both mounts before firmware;
  late peer during load; shared geometry metadata; readonly/size/peer errors;
  reserved buffer isolation; first/last C/PMM LBAs; concurrent S3; delayed ACK;
  re-dirty; zero-unmount; dirty idle/live replacement; short read/timeout;
  warm reset during load/save; cold cancellation during load/save.
- `run-nor.sh`: actual NOR program/commit and scalar DDR adapter/arbiters through
  real four-slot HPS, **8reads/8writes PASS**, C:/PMM independent flush/reload,
  cross-sector halfword, concurrent mutation and byte-identical immutable
  20,905,984-byte firmware region.
- `run-full.sh`: **all1,064,960words compared PASS** after full4MiB+64KiB restore
  and reload, with last-sector mutation/flush; no header/footer offset.
- Existing scalar/NGA suites retained; corrected P0 fixtures pass. Top structural
  elaboration,171-file/9-QIP source graph, Verilog-2001 parse/elaboration of the
  new manager and pinned formatter/whitespace checks pass.

Maintained evidence: `docs/evidence/ngage2-storage-2026-11-10.json`.
Logs: `scratch/ngage2-integration/final-aligned.log` and
`build/sim/unit-raw-save-{hps,nor,full}/{build.log,run.log}`. No Quartus fit,
installed-Main automatic mounting, hardware UI/save/power-cycle durability or
new full-phone execution/performance result is claimed. Those remain later
acceptance gates. D1 through D3 and S3 have separate results below.

### S3: ordered background saving

After D3, add quiet/max-age scheduling and an ordered queue of committed dirty
blocks. Define duplicate/generation handling and requeue on mutation during a
snapshot or transfer. Preserve existing error retention and reset coordination.
Use a global save action that drains C: and PMM and reports each device's failure.

Do not blindly adopt the donor's unordered bitmap-sweep overflow fallback.
Specify bounded overflow handling before implementation; retain unsaved data
and report failure if safe progress cannot be guaranteed. A coalescing dirty
queue is not a journal or proof that a cut image equals an exact write prefix.

Tests: interleaved changes, repeated sectors, queue wrap/full, re-dirty at every
snapshot/transfer boundary, continuous writes, failed ACK, unmount/remount,
manual save and warm reset. Controlled interruption/remount tests must exercise
the actual original-firmware filesystem. Gate: no lost dirty events; explicit
failure handling; hardware durability remains separately measured.

#### S3 result — 2026-11-11: implemented and locally verified

S3 uses the D3 bulk configuration and adds an OSD **Background save** switch
that starts Off. With it enabled, the scheduler can start after one second
quiet or five seconds pending. A background pass saves at most 16 sectors.
Manual Save drains both devices. Pending warm reset and overlay operations
hold off new background passes.

The queue holds one generation per sector across all 8,320 C:/PMM sectors,
plus one active entry. A new write to a waiting sector coalesces. A write
after dequeue joins the tail. Failed transfers and queue faults stop saving
and retain unsaved DDR contents. Slot 3 diagnostics export C: and PMM errors.

Verification passed for 606 randomized offers, full capacity and wrap,
explicit overflow and failed ACK, ordered and scalar HPS, bulk NOR with D2,
full-size bulk restore and save, diagnostic export, and both top configurations.
See [S3 implementation and evidence](docs/background-save.md). The
original-firmware filesystem interruption/remount test, physical durability,
and fitted timing and resource checks remain open.

The DDR adapter, arbiter and save sector bridge are listed as Verilog-2001
`.v` sources in the Quartus manifest. The MiSTer top still uses SystemVerilog
at the stock HPS interface, which takes unpacked arrays for the disk slots.

#### Integration hardware configuration — 2026-11-11

The integration branch enables D1 streaming, an 8 KiB D2 cache and D3 bulk
persistence. S3 uses the D3 queue and exposes **Background save** in the OSD,
initially Off. Commit `027aa18` is the same implementation with the three
build settings at zero for comparison. Both top configurations elaborated
locally. Run `ci_build.yml` on the integration branch for the fitted RBF.

## 8. D1-D3: DDR backend

### D1: ownership and streams

**2026-11-10: locally accepted as an opt-in transport candidate**, explicitly
authorized after committing P0/S1/S2
as `b232f1e` (`feat(storage): add raw C and PMM persistence`). The integration
worktree is isolated; no D1 commit, push/CI/deployment or other-chat simulation
operation is authorized. Initial source/image/donor identities are in
`scratch/ngage2-integration/d1/initial-source.json`.


Adapt the donor below our NOR models and physical-to-backing mapping. Provide
scalar reads/masked writes, 32-byte line reads, 512-byte snapshots and streaming
restore writes. Capture owner/address/operation/length/masks on acceptance,
hold commands stable through busy, and retain response ownership to final beat.
Start with one outstanding read; preserve CPU locks and bounded fairness.
Separate phone reset from transport reset and drain accepted reads before reuse.

Tests: independent memory scoreboard, randomized busy/data-ready, earliest legal
response, exact beat counts, simultaneous clients, held writes, reset at every
phase and loader readback while CPU reset. Gate: cache-disabled equivalence to
the existing backend's ordered effects; no stale or misrouted response.

#### D1 initial result — 2026-11-10: full-buffer candidate, superseded by overlap below

Implemented `rtl/ngage_ddr_stream.v` and `ngage_ddr_stream_legacy.v`, selected
by the adapter's `STREAM_TRANSPORT` parameter. Template explicitly leaves
`D1_STREAM_TRANSPORT=0`; this stage accepts the implemented/tested candidate,
not default adoption or measured hardware qualification. Existing ROM cache,
NOR/backing map, 32-bit lane semantics, outer captured-owner/SWP arbitration,
phone clock/timer profile and scalar raw-save consumers remain unchanged.
D2 caching and D3 consumer migration are not implemented.

Descriptors capture owner/address/op/count/masks; one read reserves a complete
512-byte synchronous `ngage_bram` before issue, then delivers a backpressured
ordered stream. Counts1..64 support scalar,32B line and512B snapshot reads.
Streaming restore registers independent64-bit masked burstcount1 writes;
MiSTer multi-beat write-burst behavior is not assumed. Invalid geometry/count/
last marker rejects before the offending side effect. Commands already offered
remain stable through busy/reset until accepted; canceled reads then drain and
current offered writes commit once, with partial/cancel status and no later
stream beats. Noncancellable loader readback works while phone reset stays
asserted. Production NOR retains its existing warm-reset drain/bookkeeping.

Initial full-buffer results, existing simulator image df6f55924d5f, network none:

- `tests/phone/ddr_stream/run.sh`: **483descriptors,209physical reads,
  330masked writes,5501returned beats PASS**. Independent byte memory and
  accepted-descriptor read address/count/owner oracle, every256byte mask,
  poisoned live descriptor pins, randomized busy/data/client backpressure,
  earliest response,32/512B crossings, malformed descriptors/last markers,
  committed prefix, separate reset phases and held payload stability.
- `run-equivalence.sh`: **355old/new ordered transactions PASS**, cache disabled,
  independent byte images, all16scalar masks in both32-bit halves; **6ROM-cache
  configurations PASS** (64/128/256bits × line0/1), original hit latency1clock.
- `run-fabric.sh`: real outer arbiter + opt-in adapter **31grants/28completions
  PASS**, including24alternating competing grants, CPU scalar/line/loader
  ownership, finite SWP idle gap, loader readback, busy-held scalar/line reset.
- `STREAM_TRANSPORT=1 tests/phone/raw_save/run-nor.sh`: **8reads/8writes PASS**,
  real NOR program/commit, scalar DDR adapter/arbiters and actual four-slot HPS,
  C:/PMM flush/reload, mutation and20,905,984immutable firmware bytes unchanged.
- **9/9default regression entrypoints PASS**: mister transport, ROM cache,
  line refill (including physical SDRAM), flash reset, memory owner, raw HPS,
  raw NOR, full-size raw restore/reload and structural top. Existing CPU180PASS
  baseline retained; no CPU logic or default behavior change justified rerun.
- Both new modules **Verilog-2001 PASS**; default and staged-opt-in whole-top
  structural elaboration PASS (HPS/PLL stubbed), source graph**173files/9QIPs**,
  pinned four-file formatter/idempotence and whitespace checks PASS.

Review corrections before acceptance: preserve busy-held commands during reset,
including adapter mux/busy gates; use BRAM/preload for physical read bursts;
scoreboard reads against accepted requests rather than observed DDR commands;
keep noncancellable loader phone reset asserted through response; cover the
scalar mask×lane Cartesian product; exclude historical hierarchical timeout
aliases from synthesis. The retained legacy ISSUE command remains reset-gated; the candidate deliberately
finishes an offered busy-held command before cancel/drain. Normal ordered-effect
equivalence does not imply matching reset trajectories: candidate-specific tests
establish the new reset policy independently. No measured phone performance
regression was inferred from draft test/code corrections.

Contracts and reproduction: [docs/ddr-stream-transport.md](docs/ddr-stream-transport.md).
Evidence: `docs/evidence/ddr-stream-2026-11-10.json`;
`scratch/ngage2-integration/d1/{initial-source.json,completion.json,final-source.json}`.
Final focused log: `final-checks.log`; default suite log: `regressions.log`;
staged opt-in top: `top-stream-result.log`. Generated tests under
`build/sim/unit-ddr-stream/` and `unit-d1-raw-save-nor/`.

Fairness is bounded in grants with finite locks, finite stream producers and
DDR/client progress. No fake timeout discards missing accepted DDR beats.
Wrapper hierarchy changes do not establish checkpoint serialization compatibility;
old lineages/checkpoints and the other chat's simulations are untouched.
FPGA fit/resources/timing, phone/UI performance, default enablement and physical
persistence remain unverified. No D1 commit, push, CI, Quartus download/build or
deployment was performed. Next authorized work requires a separate request;
D2/D3/S3 and NOS/peripheral/CPU ports remain outside this completed stage.

#### D1 latency refinement — 2026-11-10: locally accepted, default unchanged

User prioritized flash latency. The refined candidate reserves the full512-byte
BRAM but returns registered head beats as DDR arrives, without waiting for the
physical tail. Separate7-bit received/consumed counters and synchronous RAM
lookahead sustain one beat/clock with continuous DDR and a ready client.
Registered same-address forwarding hides undefined mixed-port collision values;
a stalled head remains unchanged as it switches back to BRAM. No combinational
DDR-data path or early successful completion. Descriptor ownership ends only
after physical drain and final logical consumption.

The legacy adapter exposes the already registered head directly and stages
prefix bytes during the physical tail. Its terminal completion and cache-line
publication still require the full fill. A delivered prefix is provisional:
cancellation suppresses remaining logical beats, drains the physical tail and
requires the consumer to discard the canceled fill. This does not restart the
CPU on a critical word or implement D2/D3.

Matched synthetic probes compare the **initial full-buffer D1 candidate**,
frozen in `scratch/ngage2-integration/d1/fullbuffer-baseline/`, with the refined
candidate. Clocks from first physical capture to logical consumption:

| Schedule | First logical beat, initial → overlap | Last logical beat, initial → overlap |
| --- | --- | --- |
| Continuous4beats | 5 → 1 | 8 → 4 |
| Delayed tail,4beats | 25 → 1 | 28 → 24 |
| Continuous64beats | 65 → 1 | 128 → 64 |
| Delayed tail,64beats | 85 → 1 | 148 → 84 |

The separate delayed4beat adapter probe measures **1clock to first logical
beat in both retained legacy and refined D1**. The table is not a comparison
against the default production DDR path, a phone workload or a hardware speed
claim. The final streaming beat may precede the terminal completion pulse;
outer ownership remains held until completion. CPU cache validity still waits
for a complete successful fill.

`tests/phone/ddr_stream/run-overlap.sh` PASS: delayed4/64tail and continuous
matched probes, full64beat stall/drain, midstream stall, catch-up to empty,
gapped arrivals, same-edge enqueue/consume (including final physical capture),
response stability, prefix cancellation with63physical beats pending under
both reset domains, stale-byte/tag exclusion, actual adapter prefix staging and
fresh fill. Initial gapped test advanced past a one-cycle terminal pulse; the
driver now retains completion status and rejects duplicates. No RTL failure
was inferred from that stale test wait.

Final focused regressions PASS: generic483descriptors/209reads/330writes/
6305returned beats,355ordered legacy/new transactions,6ROM-cache configurations,
real arbiter31grants/28completions including24alternating, opt-in raw NOR/HPS
8reads/8writes with immutable firmware unchanged. Randomized beat counts differ
from the initial candidate because PRNG progress depends on timing; only matched
directed probes substantiate the latency comparison. Previous9default suite
passes retained; no default behavior changes justified repeating them. Both new
modules Verilog2001, pinned formatter,173-file/9-QIP graph, whitespace and
default/opt-in structural top checks PASS.

Final logs: `scratch/ngage2-integration/d1/overlap/{refinement.log,direct-beat.log}`;
updated tracked evidence `docs/evidence/ddr-stream-2026-11-10.json`. D1 was
committed as `386f576` and remains opt-in (`D1_STREAM_TRANSPORT=0`). No timing/fit/phone-speed claim,
checkpoint migration, other-chat run operation, push, CI or deployment.

### D2: coherent general flash cache

D1 is committed as `386f576` with `D1_STREAM_TRANSPORT=0` in the default build.
D2 starts from this revision as an optional shared cache after DDR arbitration.

Port cache organization/beat buffers for ordinary data reads and eligible I/D
line refills. Cache raw backing bytes before address-dependent descrambling.
Retain status/query/identification fallback through NOR ownership. Start with
8/16/32 KiB configurable capacities; evaluate 64/128 KiB only if reuse and fit
justify them. Do not trade more BRAM for an unmeasured benefit.

Define a single coherence contract for every DDR writer. Update/invalidate at
a documented ordered acceptance/commit point. Do not publish an incomplete line.
Overlay undo/reload and save restore must participate; trace writes outside
flash must not unnecessarily flush it. Keep registered CPU responses initially.

Tests: hits/misses/tag aliases, all scalar lanes/masks, 32-byte lines, line/scalar
transitions, both NOR regions, program/erase/status, descrambling boundaries,
overlays all combinations, undo/reload/restore and reset during fill. Gate:
same decoded bytes and side effects as uncached reference, measured latency,
hit ratio, resource and timing results.

#### D2 result — 2026-11-10

The shared raw flash cache is wired after the final DDR arbiter. The
`D2_FLASH_CACHE_BYTES` build setting selects 8, 16 or 32 KiB and defaults to
zero. It uses the same line for scalar and eligible I/D refill reads and
keeps NOR interpretation and address-dependent decoding above the cache.
Every masked backing write passes through the same port and invalidates a
matching tag before DDR issue. A scalar miss can respond from the requested
beat while its fill retains ownership. Tag publication waits for the complete
line and terminal backend response.

All six cache/transport test configurations passed the ordered word and
line oracle, with 1,939 transactions per uncached case and 1,940 per cached
case. Directed probes covered early word return with a stalled tail, reset
drain, masks, aliases and out-of-range bypass. The actual NOR/HPS test
passed with D2 and D1 enabled, including changed C:/PMM restore into warm
entries, program, erase, identification, status and descramble boundaries.
The cache-off NOR/HPS fixture also passed. Actual NOS/BT HPS testing with
synthetic packages passed all four overlay views, rapid toggles and exact
undo. Both top configurations elaborated, the new modules parsed in
Verilog-2001 mode, and the source graph passed with 175 files and 9 QIPs.

Matched D1 reuse probe, 256 requests. D2 reduced DDR reads from 256 to 16
and elapsed clocks from 1,920 to 1,280. A scalar hit took one clock and a
cold first-word miss took six, versus four uncached through D1. The separate
24 KiB two-pass scan took longer at all three capacities than D1 alone.
The cache remains opt-in pending representative firmware latency/hit-rate
measurements and fitted resource/timing results. See
[the D2 cache contract and measurements](docs/ddr-flash-cache.md) and
`docs/evidence/ddr-flash-cache-2026-11-10.json`.

### D3: bulk persistence transfers

Capture each sector with one 64-beat read instead of 128 scalar 32-bit requests.
Add wider restore writes. Buffer a complete stable sector before HPS write.
Serialize mutations against capture or use explicit generation/retry rules;
preceding writes must be in the snapshot and later ones remain dirty. Avoid
arbitrary mixtures of partially captured old/new words. Then evaluate 4 KiB
host restore reads within local HPS transfer/buffer limits.

Tests: patterned sectors, exact beat count, missing/delayed data, boundaries,
concurrent mutations, cached reads during saving, both persistence disks,
reset drain and scalar-versus-bulk byte equivalence. Gate: fewer transactions
with unchanged contents and dirty-event behavior.

#### D3 result — 2026-11-10

`D3_BULK_PERSISTENCE=1` uses one 64-beat snapshot and 64 individual
64-bit restore writes per sector. The scalar path stays selectable and is
the default build. Each snapshot retains the shared DDR grant through
its last beat and then finishes copying into the existing HPS sector
buffer before publication. Later mutations remain dirty. Bulk restore
invalidates the affected sixteen D2 indices before scalar traffic resumes.

The actual HPS/NOR fixture passed in scalar, bulk and bulk with D2 modes.
It checked both disks, changed-image reload, a cache hit during the host
save, program/erase/status, and mutation during host transfer. The
ownership test held a sector behind a D2 fill and SWP lock, buffered a
stalled snapshot, serialized a queued mutation and drained a reset
snapshot before the next scalar read. The full-size tests compared
1,064,960 words on each restore and reload in both modes and verified both
last-sector saves. The two full-image restores used 2,129,920 scalar DDR
writes or 1,064,960 bulk DDR writes. Six snapshots in the HPS/NOR fixture
used 768 scalar commands or six 64-beat commands with the cache off.

The local 4 KiB assessment found that eight 512-byte blocks fit the
HPS protocol. A larger host request needs a 2,048-halfword buffer and
whole-request validation. Main already reads ahead. The bulk path
uses the current one-sector host framing. Hardware timing and installed
Main validation remain open. See [D3 details](docs/ddr-bulk-persistence.md)
and `docs/evidence/ddr-bulk-persistence-2026-11-10.json`.

## 9. R1-R3: SDRAM controller

### R1: whole-controller comparison

Wrap the donor as a build-time alternative behind existing 16 MiB word and
32-byte-line interfaces. Initially preserve our physical mapping; adapt its
16-byte bursts into complete ARM920 lines without another duplicate RAM image.

Audit the entire capture/clock schedule. The donor samples differently from
our current input-DDIO falling-sample/resynchronization path. Preserve that
validated boundary where feasible; any replacement needs an independent timing
argument and tests. Do not copy controller counters and assume pin alignment.
Derive power-up/refresh from real clock/chip requirements: existing JTFRAME
refresh debt and donor single-refresh intervals are different contracts.

Tests: original four-state Micron model plus donor timing checker, shared
request scoreboard, all masks, banks/rows/end boundaries, refresh during
sustained traffic, read/write direction changes, short/full lines, reset and
DMA/SWP locks. Run at 78/104 MHz with pin delays and a failing wrong-edge
negative control. Gate: no memory/timing-model error; physical fit still needed.

### R2: captured consecutive writes

Implement consecutive halfword writes for each word before gathering contiguous
buffered words/dirty half-lines. An early ACK transfers ownership to reserved
queue capacity, not to an unlatched live input. Preserve masks, reset draining,
read-after-write order, maintenance/drain and CPU locks.

Tests: all enables, zero/partial groups, capacity/backpressure, write/read,
write/table-walk/refill, eviction/maintenance, interrupts, DMA and SWP. Check
physical commands and independent readback. Gate: lower write overhead with
correct ordering and no unexplained read-latency regression.

### R3: optional bank interleaving

Evaluate four-bank bijective address remapping independently. Update physical
test helpers, preserve guest addresses and all contents. Four banks share DQ;
they are not independent simultaneous ports.

Tests: mapping uniqueness over all phone RAM, walking addresses/bits,
bank/row/end boundaries, refresh and mixed masters. Gate: repeatable measured
benefit; reject or defer the mapping if gains do not justify it.

## 10. B1 and P1: shared peripheral infrastructure

### B1: peripheral-master route

General DMA and audio need SDRAM, on-chip RAM and peripheral FIFO access rather
than the current LCD-only SDRAM read path. Add explicit master routing and
captured ownership while retaining separate memory/chip boundaries. Normalize
DMA peripheral aliases only after confirming NEM-4 usage. Preserve SWP locks
across read/write gaps; the donor arbiter has no explicit lock input.

Pace peripherals before taking the shared bus so a waiting MMC/audio endpoint
cannot indefinitely block CPU progress. Define ordering against cached CPU
data and firmware DMA maintenance; do not silently invent snooping.

Tests: CPU/DMA/audio contention, fairness, held requests, FIFO stalls, bus
errors, reset in flight, aliases and SWP reservation. Gate: stable exact-once
transactions and no deadlock/starvation on bounded scripted workloads.

#### B1 result — 2026-11-11: existing SDRAM route qualified

The arbiter passed 32 alternating CPU/DMA grants, captured masked writes,
SWP reservation and reset cancellation. Real-controller tests verified
DMA write/readback, refresh and reset drain at 78 and 104 MHz. The ARM board
and synthetic 18,304-word LCD frame also passed. Retained firmware-frame
replay was skipped because the fixture was unavailable in this worktree.
Reuse the existing word transport. On-chip RAM and paced FIFO routing,
endpoint error delivery and verified MMC aliases remain open before P2/P3.
See [peripheral integration](docs/peripheral-integration.md).

#### B1 follow-up — 2026-11-11: DMA word router implemented

The production LCD reader now uses a captured word router ahead of the
existing SDRAM arbiter. Its full-frame regression matches the direct path
at 18,304 words, checksum `02b0e100` and 366,390 ns. The real SDRAM model
passes routed DMA writes, SWP and readback at 78 and 104 MHz. The standalone
shared-local-bus fixture checks masked RAM, CPU progress while the LCD FIFO
is full, alias scope, target errors and reset cancellation.

The new route allows only validated address regions. It rejects boot-scratch
accesses and leaves the donor MMC alias unresolved. Next bind the local
route to the live UPP bus and use the captured command interface for P2.
General DMA channel programming and MMC remain separate stages.

#### B1 follow-up — 2026-11-11: live UPP route locally verified

The router's local port now reaches the existing UPP device bus through
the MiSTer and board modules. Admission waits for the CPU bridge to be idle,
an unlocked bus and LCD queue space where applicable. The UPP captures an
owner, uses the normal device commit path and returns exactly one terminal
result. A request-low cycle clears the peripheral response before handoff.

The ARM board test passed concurrent CPU/DMA NOS4K access, a DMA masked
write, one accepted LCD FIFO word and an error for a rejected one. The
standalone pacing/SWP/reset checks, both UPP bridge modes, keypad, LCD,
Verilog-2001 and structural top checks passed. The SDRAM and local word
interfaces are ready for P2. New device addresses, channel programming and
hardware fit remain open.

### P1: timer, ICU and UEM/CBUS ownership

Establish a complete source map before adding devices: DMA channel sources,
MMC 21-24, shared NOS/keypad 25, UEM/CBUS and any audio source. Verify each
against NEM-4 code. Eliminate overlapping placeholder claims only for the
addresses actually modeled. Retain explicit unknowns elsewhere.

Keep the current 26 MHz timer and 64 Hz NOS experimental profile for initial
comparisons. QD's 104/3 MHz setting and battery constants are not our reset
specification. Preserve UEM transaction-level shortcuts as labeled shortcuts;
do not claim donor register storage implements serial CBUS pins.

Tests: source enable/mask/current priority, IRQ/FIQ separation, shared pending,
simultaneous event/ACK, byte lanes, control modes, rollover and clock scaling;
replay reached CBUS/ADC/RTC transactions. Gate: existing startup/device events
remain understood and new interrupts have one documented owner.

#### P1 result — 2026-11-11: IRQ current and source map

The retained NEM-4 kernel reads all three IRQ current registers. Each bank
now reports the lowest enabled pending source, using one-based numbering.
All 96 sources and 1,584 within-bank priority cases passed. ARM board, timer,
NOS, keypad and CBUS checks passed. The prior ICU failed on the first
previously unsupported priority slot. Current device wiring, raw IRQ status,
FIQ semantics and timing profile are preserved. The source map records the
observed NEM-4 EPBUS registrations and unresolved MMC, general DMA, audio
and request-line assignments. Peripheral routes require their own evidence.

#### P1/P4 flow correction — 2026-11-11: locally verified

The donor comparison reproduced five retained IRQ/timer differences at both
8ff8b11 and6b7be5a. Raw IRQ status now exposes all sources; FIQ current applies
its enable mask and full within-bank priority. Timer programming no longer
changes ICU masks, and timer1 acknowledges only its own register. Original
NEM-4 tables qualify all six timer levels on both planes.

Six parallel programmable counters replace boot-value whitelists, stored-only
counts and fixed unit60 delay. Original repeated synchronous delay exposed
stale completion; new count resets completion without clearing pending IRQ.
The clearing-write assignment is an explicitly documented transaction-level
inference. Keypad GPIO data/direction/enable now governs actual pin edges;
loopback-owned configuration commits and stable GENIO1 level are connected.
CPU bus stages and the fast LCD stream are preserved.

All source/priority cases, timer/ICU ownership, original timer and keypad code
at78/104 MHz and zero/three memory waits pass. Combined board ownership,
registered response, clock and ARM integration checks pass. The pointer
observer also passes four original-instruction fixtures, but does not identify
the real hardware caller. No full firmware UI wake,104 MHz fit or selected
D1/D2/D3 full-boot proof is claimed. Old checkpoints remain frozen.

See [flow corrections](docs/irq-timer-keypad-flow.md),
[timers](docs/general-timers.md), [controls](docs/live-controls.md), and
[startup](docs/symbian-startup.md). User queued the failed113% ALM build's fit
investigation after these fixes, followed by commit/push and rebuild. The
provided Quartus logs are read-only inputs; resource recovery must preserve
behaviour, the fast LCD path and explicit memory/timing contracts.

#### RAM conversions implemented — 2026-11-11

Four queued-descriptor M10Ks plus timer/ICU passive-word M10Ks replace~1,801
net source FF state bits (intended6 blocks). Preserve start-time snapshots,
full-width readback/reset values and live counter/IRQ timing. One fetch clock
precedes DMA launch; passive reads wait one sample. One/two/three workers,
Intel/poison collision fences,12,788-transaction old-register oracle and
original NEM-4 timer/DMA/ISR fixtures pass. Full LCD frame stays130,685 clocks;
MMC matrix+101/667,085 clocks (~0.015%). Actual PLL78 MHz; RTL target104 MHz.
Physical area/timing pending. [Details](docs/ram-conversions.md).

#### Fit margin: donor architecture/storage comparison — 2026-11-11

Read-only comparison identifies our always-built diagnostics (~1,186 ALMs),
FF RF (~2,008), fully associative TLB banks (~3,987), 64-way tag modules
(~3,400), 896 queued DMA descriptor bits plus768 live programming mirrors,
and768 timer spare/224 ICU passive readback bits. Costs are not savings;
no matching current donor whole-core report is available locally. Donor uses
RAM-backed programming/passive words and already has the latest-writer MLAB RF.
Prioritize preserving guest bits/snapshots in RAM and controlled isolation of
the last timing patches; then consider a compile-time diagnostic profile and
RF port. Cache/TLB or whole-CPU substitutions require separate qualification.
See [comparison and gates](docs/donor-resource-comparison.md). No HDL changes,
simulation starts, branch switches or CI monitoring in this audit.

#### Timing patch area regression — 2026-11-11

840e3d4 fails4277/4191 LABs (42,407 required ALMs). Only LCD prevalidation and
local DMA response RTL changed; actual78 MHz/SDC/options are identical. Map
FFs increase67 and DSPs2. Required ALMs rise3,412 but placed ALMs rise1,059;
dense-packing recovery estimate drops2,533->1. Prior93% required headline
already had97% placed occupancy. Do not assume spare area from that headline.
Isolate LCD-only/DMA-only fits before keeping either timing change or adding
features. [Evidence/analysis](docs/lcd-dma-timing-recovery.md).

#### Timing recovery after successful fit — 2026-11-11

New logs fit93% ALMs/90% M10Ks; only setup qualification fails (-2.657 ns at
78 MHz, reported64.61 MHz Fmax). Keep actual78 MHz; design stages toward104 MHz.
LCD window/byte-count validation now commits before pixel streaming. Local DMA
returns registered data/error after peripheral acceptance; SDRAM/fast LCD stay
on their original timing. Old/new LCD matches1,135,723 checks across43,681 row
pairs. Full frame stays130,685 clocks; complete ARM fixture+one clock. MMC98
phases/667,085 clocks unchanged. Reset/ownership and real SDRAM78/104 checks
pass. Physical timing remains pending a new build, without CI monitoring.
[Details and evidence](docs/lcd-dma-timing-recovery.md).

#### Temporary lean overlay/menu profile — 2026-11-11

Comment out both NOS/BT compatibility menus and compile guards/source entries;
keep the entire implementation for restoration. Previous report attributes
678 ALMs and14 M10Ks to both package loaders. Semi-real NOS peripherals remain.
Remove manual MCU/PPM pickers and the empty Firmware submenu; automatic
boot.rom/boot1.rom loading remains. Ignore saved overlay selectors and boot2/3
transfers in this profile. Selected/re-enabled-engine top checks pass; preflight
is173 files/nine QIPs. Hardware boot, area and timing remain unverified.
Restoration instructions are in [firmware overlays](docs/firmware-overlays.md).

#### Production diagnostic SIM removal — 2026-11-11

Remove the OSD selector and compile out the test-card responder, retaining
SIMIF no-card behavior and all semi-real NOS work. Prior-fit card attribution
is441 ALMs; actual saving remains pending Quartus. Four board cases pass,
including forced-high presence with the card omitted and compilation without
its source. Production top and174-file/nine-QIP preflight pass. The diagnostic
screen is retained. No simulation/checkpoint or build-monitor operation.

#### Second fit recovery — 2026-11-11: selected production profile

New logs reduce the failure to103% ALMs (43,217/41,910), zero MLABs and512/553
M10Ks. Priority is a buildable core before further porting. Pack D-cache dirty
metadata into existing tag RAM with byte enables; intended net1,150 fewer FFs,
no extra M10Ks, cache size reduction or transaction stages. Ordinary/Intel/
X-collision old/new equivalence all pass11,025 cycles. Cache suites, I-cache
cycle comparison,104 MHz timer-profile ARM board and full fast LCD/reset tests
pass. Fast CPU normal/held totals stay152,456/152,537 clocks. Raw VHD bulk
restore/save passes full4 MiB C:/64 KiB PMM. ARM dirty-writeback IRQ, cached
SWP and CP15 single-line maintenance pass with zero/three waits.

Commented out nine inactive source entries, including legacy NGA mount/header
and LCD frontend; raw VHD manager remains the only production disk interface.
Disabled unused Linux ALSA mixer; explicitly disabled superseded instruction-
only ROM cache. Keep fast LCD, both workers, MMC, SIM and semi-real NOS. Top
elaboration and175-source/nine-QIP preflight pass. Physical area/timing remain
pending the next build; do not monitor CI. Prior boot-observer changes remain
uncommitted and separate. See [fit recovery](docs/fit-recovery.md) and
[evidence](docs/evidence/logic-fit-profile-2026-11-11.json).

#### Fit recovery — 2026-11-11: local checks pass, CI fit pending

Failed build43016356272 used6b7be5a. Detailed reports contain511/553 M10Ks;
the zero-RAM summary does not mean BRAM inference disappeared. The new DMA/MMC
paths account for most added peripheral logic. Recovery moves full DMA raw
readback and45 scratch words into RAM, replaces sparse CAM tags with a hashed
BRAM store, and explicitly removes instruction-cache dirty metadata. Capacity,
readback bits, queues and lookup stages are retained. The added RAM budget is
three M10Ks; fitted savings are not assumed.

Measured one/two/three-worker tests show two preserve useful stalled-MMC/copy
concurrency, while three add no current benefit. Production selects two with
all eight channels and the separate fast LCD path. A captured local admission
signal also removes structural DMA cancellation feedback without a new state
or transfer clock. Normal/held full CPU LCD tests remain152,456/152,537 clocks,
frame interval130,685; real MMC all-channel tests retain98 phases/667,085 clocks.
Instruction-cache equivalence/provenance, vendor RAM conformance and combined
chip/board tests pass. Hardware area/timing and full UI boot remain unverified
until CI/hardware. See [fit recovery](docs/fit-recovery.md). Commit/push and
manual CI rebuild are authorized by the user after these fixes.

First recovery CI43032422026 at0a47a0f stopped before fit: DMA raw RAM used
portA readback in simple dual-port mode. Corrected to portB with the same
handshake/latency; the ordinary wrapper now matches Intel's write-A/read-B
contract. All three worker counts pass vendor-model raw-read tests, and the old
connection fails the tightened ordinary model. Resource/timing measurement
remains pending a retry; no area success is inferred from this synthesis error.

## 11. N1-N4: original NOS plus selective services and SIM

### N1: service/ABI and original-runtime audit

Use decoded NEM-4 NOS and actual call traces to map startup, original server
dispatch, kernel/service exports, channel vtables, object lifetimes, globals,
DFCs and timer/IRQ dependencies. Donor fixed addresses belong to RH-29 and
must not enter our payloads unverified. Identify real work to retain before
choosing a replacement boundary.

Reconcile donor request layouts with the existing `rtl/ngage_modem.v` and
`scratch/modem/` C reference/fixtures. The existing HDL responder is isolated;
its historical 2022-vector agreement does not establish integration. Do not
invent a physical modem mailbox: original NOS runs on the same ARM, and a
software call/dispatch bridge may be the correct compatibility seam.

Tests: NEM-4 request/client parsing fixtures, original-handler traces, expected
pending requests, service registration and no-double-completion assertions.
Gate: written per-resource ownership/evidence table and named runtime paths
retained. If boundary safety is unresolved, N2 cannot replace that resource.

#### N1 result — 2026-11-11: original runtime boundary verified

The ROM checks confirm the original NOS entry branch, two LDD imports,
`gsmstuff` export table and channel endpoint vtable. A retained NEM-4
instruction trace contains original DFC and mailbox-pump entries. The
existing C/HDL responder passed 2,022 frame vectors. The audit defines which
startup, channel, DFC and service paths to retain and records the donor
patterns worth adapting. Original request/reply capture and actual channel
completion tests remain open before N2 intercepts a resource. See
[semi-real NOS](docs/semi-real-nos.md).

### N2: selective transport and asynchronous completion

Adapt donor channel queues/descriptor handling/cancel/teardown and bridge only
selected services. Keep original registration and dispatch for other services.
Reuse one canonical service-state definition across C and any RTL backend;
avoid competing contradictory modem models.

Retain transaction IDs, object/device routing and exact frame lengths. Deliver
async replies in the correct process/thread context. A deterministic shim
transport, if needed, must be marked emulator-only rather than Nokia hardware.

Tests: multiple channels/receivers, descriptor forms, short/malformed frames,
queue limits, receive-before/after-send, cancellation races, close/reopen,
thread address-space changes, DFC reentrancy and shared IRQ activity. Gate:
one completion per request and unchanged behavior of delegated original paths.

#### N2 audit — 2026-11-11: original completion ownership verified

Astra reviewed the original ROM and donor shim. Kernel cancellation already
completes each selected request with `-3` before the callback, which receives
a request number. The donor's mask-based callback and additional completion
are incompatible. The receive-0 length descriptor and kernel status slot
are separate. Preserve the original channel, mailbox and DFC path and trace
the charger-status handler before considering a leaf substitution. The
instruction-level cancel/receive fixture and live resource traces remain
open. See [semi-real NOS](docs/semi-real-nos.md#n2-cancellation-abi-and-first-service-probe).

#### N2 result — 2026-11-11: original ARM fixtures passed

The new ZAP fixture executes original kernel cancellation, LDD and NOS
endpoint instructions at zero and three memory-wait cycles. Four cancel
cases verify request-number callbacks, cleared status, `-3`, exact signal
counts and repeat-cancel handling. The original mailbox pump passes short
receive (`-4` plus required length), cancellation before retry, a complete
retry and a second pump after completion. Checked thread-descriptor leaves
stand in for a full process address space. Actual kernel completion and
descriptor constructors execute unchanged.

Five original charger-handler cases check valid/invalid flags, exact reply
bodies and frame allocation. The state providers execute unchanged against
a zero byte in the modeled NOS4K state. The fixture replaces only pool
allocation and the three descriptor kernel leaves. Private source images
retain their hashes and test redirects are listed in a generated manifest.

Two isolated original-model replay windows at 6.1B and 8.2B observed one DFC
and one pump, with no watched charger request or completion. Keep original
service ownership. The next evidence is a real request and its state-field
producer, followed through original dispatch and completion. Cross-process
descriptors and DFC concurrency remain open integration gates. See
[fixture details](docs/semi-real-nos.md#original-instruction-fixtures).

### N3: stateful missing services and logical SIM

Implement individually audited SIM/security, self-test, battery/charger,
phone/product information and accessory/light behavior that the original
runtime cannot provide with currently modeled hardware. Prefer retaining real
service state transitions over fixed success bytes. Every synthetic state is
named and observable.

Provide consistent no-card and synthetic-ready policies as supported by NEM-4
clients. Include PIN/security indications, SIM flags/identity comparison,
ciphering/service-table/operator/ALS queries only after auditing their parsers.
Unsupported network/call/SMS requests must not falsely report real service.
Keep real NOS handler execution and compatibility decisions in trace evidence.

Tests: request/reply golden fixtures, state transitions, repeated queries,
indication ordering, polling/cancel/teardown, pending startup completion and
error replies. Test Phone/Menu/ETel wait paths in full firmware. Gate: named
startup waits resolved without C: formatting/UI patches, and original NOS
runtime still demonstrably active.

Physical SIMIF remains a distinct P8 audit item: no-card/ATR/APDU behavior needs
its own physical-interface evidence and tests before connecting it to logical
SIM state. Never run two independent SIM state owners silently.

### N4: overlay capacity and semi-real profile integration

Audit code/BSS placement, current 8 KiB staging and 640-record limits before
packaging richer payloads. Extend transport only if required, with exact bounds,
expected-original-word checks, CRC/profile identity and complete undo. Preserve
independent NOS/BT selection and shared checksum ownership. Record retained
original exports, hooks and every replacement service in package metadata.

Original NOS startup remains active. Any bootstrap experiment is separately
named and excluded from the default semi-real profile. Compatibility checksum
handling stays explicit; source firmware and C:/PMM are untouched.

Tests: host payload sanitizers, actual ARM channel/DFC execution, all overlay
selection combinations, arrival order, malformed/oversized packs, overlapping
payloads, wrong target, partial load, reapply/reload, reset and byte-exact undo.
Then boot with original and semi-real profiles from separate disposable images.
Gate: original mode restores all bytes; semi-real traces demonstrate meaningful
original runtime and bounded replacements. A fully synthetic boot alone fails
the final semi-real requirement.

## 12. P2-P8: peripheral ports

### P2: general DMA

Port channel registers, width conversion, fixed/incrementing modes, count
semantics, execution engines and completion/stop behavior. Validate NEM-4's
channel/register/alias usage and replace overlapping LCD programming ownership
in a controlled transition. Do not globally swallow DMA errors as the donor's
model may do; define error reporting and preserve diagnostics.

Tests: memory copies/fills, 8/16/32-bit conversion and tails, simultaneous
channels, stop/restart in flight, CPU progress during paced waits, IRQ ACK,
locks and reset. Gate: a standalone scripted master proves transfers before
firmware DMA depends on them.

#### P2 result — 2026-11-11: byte engine and channel pool verified

Sol High implemented the standalone Verilog-2001 byte engine. The frontend
captures eight channel descriptors into a default three-engine pool, with
round-robin dispatch/word grants, immutable packets and response ownership.
Stop/restart drains an accepted word, preserves committed write prefixes and
does not issue stale success. Endpoint errors terminate and latch a model
diagnostic without raising the original ISR's success IRQ.

Astra's NEM-4 audit found a donor count bug: memory start counts halfwords
even with 32-bit SDRAM widths, while paced transfer count follows the fixed
peripheral width. The frontend normalizes those counts to literal byte
extents. The engine handles partial final source reads and destination
writes without accessing trailing lanes. Original NEM-4 name lookup and IRQ
enable also confirm DMA channel `n` uses bank-0 bit `6+n`.

The engine passes 4,914 byte-oracle cases / 52,326 owned words. One- and
three-engine frontend/router tests pass queued channels, captured settings,
selective IRQ ACK, memory/peripheral count rules, exact tails, pacing,
stop/restart, errors, lock and reset. Strict Verilog-2001, formatter, source
graph, existing LCD and structural-top checks pass. Detailed evidence and
unverified hardware assumptions are in
[peripheral-integration.md](docs/peripheral-integration.md).

The original setup/start/stop routines also pass on ZAP without instruction
substitutions: zero waits in 11,130 cycles; three waits in 16,814 cycles.
Four exact 16-byte transfers check SDRAM copy, MMC-style FIFO send/receive
and on-chip RAM copy, all memory trails, request-selector writes and kernel
bookkeeping. MMC is an explicit test-only endpoint; production admission is
still P3 work.

This standalone checkpoint preceded the production handover recorded below.
That follow-up installs the frontend, request selection and IRQ routing;
final fresh boot/CPU reruns remain pending as described there.

#### P2 production handover — 2026-11-11: fast LCD path installed

Production `ngage_mister` now defaults to `GENERAL_DMA=1`; eligible SDRAM LCD
descriptors always use the fast stream, with no `FAST_LCD` selection.
One frontend owns all eight channels and ICU sources 6..13. Channel ACK is
independent of ICU masking. Production request-selection writes follow the
original software helper and capture LCD line 7; unsupported paced devices
produce diagnostic errors. Physical selector polarity remains unverified.

Eligible LCD descriptors use the dedicated SDRAM read stream, sharing the
normal ordered panel FIFO and cursor. They bypass the per-word UPP write
overhead while retaining general register/count/stop/restart/IRQ ownership.
The zero-request-latency RAM mux arbitrates fast reads and general DMA before
the existing CPU/SWP arbiter. On-chip LCD sources retain the general route.
Source addresses no longer determine framebuffer placement. Original-driver
full-width row bands, variable pixel headers, packing and guard rows are
covered; arbitrary rectangles/wrap remain P4 work.

The last queued pixel must retire before completion IRQ. Stop/restart also
fences canceled tails, including the engine's final-done edge. Invalid
transport control/header or panel state returns an owned error without
enqueueing another pixel or reporting success. Exported core `dma_reset`
aligns the route, mux, arbiter and adapter cancellation with CPU Hold as well
as reset, preserving accepted physical drain and retained RAM.

Matched old-reader/new-stream tests compare every word of the same
18,304-word frame on identical RAM/arbiter timing:

| RAM delay | Old LCD reader | New fast stream |
| --- | ---: | ---: |
| 0 | 36,608 clocks | 36,608 clocks |
| 1 | 54,912 clocks | 54,912 clocks |
| 3 | 91,520 clocks | 91,520 clocks |

No streaming throughput penalty was measured in those tests. The separate
CPU/interleaving fixture measures 130,685 clocks with the fast path versus
306,802 with the general LCD engine (2.347645 ratio). Those synthetic
intervals are not fitted hardware timings or complete phone speed claims.

Verified: full production CPU frame/band/copy/IRQ tests in both profiles;
held queue with peer CPU/DMA progress; queued reset and CPU-Hold cancellation
followed by fresh channel work; fallback and request/address errors; current
host final-done/fast-owner/tail fences and midstream transport reset. The
unchanged original ISR runs on ZAP at zero/three waits in 11,067/16,449
cycles, with one next chunk, two callbacks, ACK ordering and guards checked.
Stream 244-case, mux, engine/channel/route, LCD protocol, ICU, bridge, keypad
and four-state 78/104 MHz DDIO checks pass. Source graph passes at 181 files.

**Final local verification passes:** the final 1,376-byte CPU phase-10 program
passes normal, held queue, queued-tail reset and CPU-Hold reset in both historical
profiles. Fast normal/held totals are 152,456/152,537 clocks; general totals
334,970/335,072. Frame intervals remain 130,685/306,802. The later retirement of
the slow switch passes all four production modes again with identical fast
totals, original ISR 11,067/16,449 clocks and the host fences. The general fence
now uses on-chip RAM, preserving necessary fallback coverage.

Fresh 5M boot, pinned formatter, stubbed top and source graph pass. The boot
stops in the original low-ROM delay loop at `00006164`: 351,379 transactions,
12 known fetch faults, no data errors or LCD frame. It does not exercise
Template's selected D1/D2/D3 chain. FPGA fit/timing and new MiSTer hardware
validation remain open. [Final evidence](docs/evidence/lcd-dma-final-2026-11-11.json)
separates this result from the earlier pre-phase-10 logs.

The user freed 91 GiB and initiated a Docker restart. Its VM stopped cleanly,
but the old application backend remained stuck and the normal restart command
timed out. Quitting only that stale application and relaunching with the VM
already stopped recovered engine 28.0.4 and the existing pinned image. No
data/settings reset, other simulation action or checkpoint mutation occurred.
The final pinned formatter passes on 13 files (idempotent check clean).
Original-ISR evidence is refreshed after the frontend cleanup and its current
60 measured source hashes match. No other simulation or checkpoint was changed.

Detailed contracts, runner commands and evidence boundaries:
[lcd-dma-handover.md](docs/lcd-dma-handover.md). No commit/push or deployment
was performed for this handover.

#### Donor fix — 2026-11-11: count bug reproduced and committed

The donor RTL and C transfer functions both reproduced source overreads for
a 10-byte 32-bit memory copy and a 512-byte MMC transmit. They now normalize
counts to byte extents and mask the final source read as well as the final
destination write. Existing peripheral test programming was corrected to
use halfword memory counts and peripheral-width paced counts.

Donor branch `codex/dma-byte-count-fix` contains local commit `7be19cd`;
`master` remains the pinned `e3d2bf7` baseline. The applied nine-file patch
matches the tested snapshot hashes. Focused RTL and actual C transfer
functions each pass 2,650 cases; RTL covers 37,433 words. Strict `-Wall`
lint passes without warnings. The existing peripheral regression passes
3,665,197 clocks, including CPU/DMA concurrency, stop, LCD and synthetic
MMC. The private game-card fixture was unavailable and skipped; a full QEMU
build and physical controller timing are not verified. No push occurred.

The portable [patch](docs/evidence/donor-dma-count-fix-2026-11-11.patch) and
[evidence](docs/evidence/donor-dma-count-fix-2026-11-11.json) preserve the
reproducer and fix independently of the moving donor branch.

### P3: MMC host, card and tooling

Port `upp_mmc`, `mmc_card`, CID/CSD/OCR metadata and `mkcard.py` concepts with
their tests. Keep the host register frontend inside UPP and the card at board
level. Maintained ports must be Verilog-2001. The donor's RH-29/QD direct
CLK/CMD/DAT0 path is an explicit transaction-level shortcut: the NEM-4
schematics show the separate D550 audio DSP/AMA/card interface. Do not remove
that chip boundary or claim verified phone pin behavior.

The original NEM-4 EPBUS driver confirms the byte FIFO at `0c120624`, DMA
alias `10120624`, request line 2 and eight-bit peripheral width. It programs
the **exact** host length but rounds DMA length up to four bytes: RX must
zero-fill and TX discard the final zero to three padding bytes. Original
IRQ names confirm sources 21 DataIdle, 22 DataRdy, 23 CmdIdle and 24 CmdRdy;
this EPBUS binds 21/23/24. Source 22's asserted-level meaning remains open.
Preserve actual card identity for protected titles; no implicit replacement
CID/CSD/OCR. See [MMC port details](docs/mmc-port.md).

| Step | Dependencies and implementation | Required checks / gate |
| --- | --- | --- |
| P3.0 image preservation | Independent of pending P2 simulations. Inspect/import/export raw sectors plus exact `NGAGEMMC` v1 footer; explicit actual identity, CRC validation, size checks and provenance. Keep unknown CSD profiles opaque for inspect/export. | Independent CRC7 vectors; all-byte round trip; full/partial/oversized/empty extents; read-only input and overwrite protection; opaque footer bytes; corrupt manifest/footer rejection; bounded streaming. No user image changes. |
| P3.1 donor safety fixes | Pin `7be19cd`; isolate payload-EOF write loss before reuse. Audit ignored footer version, failed CMD16 changing cached length and incomplete response framing. Preserve read-zero padding behavior. | Baseline must reproduce each claimed defect. Wire/HPS peer: last backed write persists once, first unbacked write errors, CMD25 cannot cross EOF or wrap, WP precedence, delayed ACK, bad CRC, CMD12/CMD13 recovery. Rejected CMD16 retains prior length; malformed response/version rejected. |
| P3.2 standalone native host/card | P3.0/P3.1 and P2 final reruns. Separate card and host modules; adapt 1-bit clock to our system frequency. Keep DIV4/DIV12 timing assumptions visible. Start with read-only mounting and explicit HPS transaction ownership. | Independent pin peer and HPS memory peer, rather than just matching host/card models: CMD0/1/2/3/7/9/13/16/17/18/24/25/12, R2 word order, CRC/error/timeout, byte order, FIFO stall clocks, lengths 1/2/3/5/511/512 and exact padding. Strict Verilog-2001 and reset cancellation. |
| P3.3 UPP/DMA/IRQ binding | P3.2; captured local-bus owner and request selector 2; existing eight-channel DMA and ICU. Keep host length, DMA completion and card CRC/busy completion distinct. | RX FIFO bytes packed into RAM and reverse TX with byte enables; partial tails; CPU/LCD/other DMA contention; stall/stop/restart/reset; captured route; idle/ready interrupt timing. Source 22 semantics need independent evidence before a production assertion policy is claimed. |
| P3.4 original driver read acceptance | P3.3, S2 slot layout and actual `hps_io` contract. Run original NEM-4 EPBUS/DMA paths unchanged. | Original identify/response/IRQ/rounded-tail fixtures, then bounded fresh firmware mount/read trace and known file/scene hashes. A synthetic host/card pass is not a firmware mount or game-launch result. |
| P3.5 writable persistence and replacement | P3.4 plus explicit full-capacity writable-image policy. Separate guest card state from mount state; drain or cancel accepted HPS work before replacement. | Actual `hps_io` tests with delayed ACK, ACK already high, reset/remount during reads/writes, footer/neighbor guards and persisted byte comparison. No acknowledged write may be dropped or retargeted. Writable hot removal is a separate acceptance gate. |

#### P3 progress — 2026-11-11: audit and isolated image/bounds work

The source audit is complete. It records original register/status/IRQ and
rounded DMA-tail evidence, physical ownership limits and donor hazards.
`tools/ngage_mmc_image.py` passes 14 generated standard-library tests for
P3.0, including an exact all-byte image round trip; final results are recorded
in [MMC port details](docs/mmc-port.md).
Strict import supports only the locally observed CSD structure 2/spec 3/
READ_BL_LEN 9 profile (up to 1 GiB), with byte-addressing OCR. Unknown layouts
remain archival inspect/export inputs; partial payloads are explicitly
ineligible for writable mounting.

An isolated donor patch reproduces the EOF write-loss baseline and passes a
282,492-clock wire/HPS regression with five mounts and four persisted writes.
It adds actual payload bounds alongside CSD capacity, including CMD25 and
wide carry checks; read-zero tails remain. The reviewed fix and test are now
applied on donor branch `codex/mmc-payload-eof-fix`, based on `7be19cd`;
the actual donor rerun also passes. This step has no commit or push, and the
old donor branches are preserved. This is host-Icarus evidence;
pinned-image and existing donor C++ regressions subsequently pass after Docker recovery.
The defensive lost-bound negative-token semantics remain unverified. No
production MMC RTL has been connected, and no card mount/launch is claimed.

A second donor patch now rejects unknown `NGAGEMMC` footer versions instead
of silently parsing them as v1. Its baseline failure is reproduced; the actual
donor external-port test passes seven mounts / 196,894 clocks, preserving v1
opaque bytes, raw no-magic fallback and reset/remount recovery. The EOF test
also passes again after this change. This conservative absent-card policy is
software metadata validation, not verified phone behavior. Portable layered
patches and hashes are linked from [MMC port details](docs/mmc-port.md).

The CMD16 cache defect is also reproduced and fixed on that donor branch:
accepted length 64 followed by rejected length 128 previously made a zero-length
host transfer emit 128 bytes. The bounded cache guard now passes 31 independent
pin-observed probes / 118,914 clocks against the actual donor, including every
classified R1 error, bad CRC/framing/type, timeout, status-only success and reset.
General response framing error/status policy remains unchanged and open.
The combined eight-file donor patch and final source hashes are retained in
[safety evidence](docs/evidence/donor-mmc-safety-2026-11-11.json). Pinned-image and
existing donor integration regressions now pass; no commit/push occurred.
All three focused tests pass in the pinned image, alongside the 13,907,842-clock
MMC and 3,665,197-clock peripheral suites. Missing private card/trace replays
are explicitly skipped. See [pinned results](docs/evidence/donor-mmc-pinned-2026-11-11.json).

#### P3.2 result — 2026-11-11: standalone native host/card verified

`ngage_mmc_host.v`, `ngage_mmc_card.v` and internal cache helper
`ngage_mmc_dpram.v` are strict Verilog-2001, preserving licenses and pinned
donor semantics plus the reviewed fixes. No production QIP/board binding changed.
Host tests pass 31 CMD16 probes /118,914 clocks and 28 data cases at DIV4/FIFO16
and DIV12/FIFO8 /82,004 and244,751 clocks, exactly matching donor. Card public
EOF/version and four-state lockstep tests pass; the unchanged C++ card suite
passes donor/port/lockstep at13,907,842 clocks each. Both native modules together
pass the donor peripheral suite at3,665,197 clocks with identical runtime output.
Pinned formatter, strict-language compile and independent Astra translation
review pass; lint notices and skips remain explicit.

[Stage evidence](docs/evidence/mmc-native-port-2026-11-11.json) records final
hashes and limits. P3.3 captured UPP/DMA/IRQ wiring and actual `hps_io` read-only
mount adaptation are next. Original EPBUS/firmware acceptance, IRQ22 semantics,
general frame-error status, physical timing, writable HPS ownership/reset/hot
replacement and FPGA fit remain open. No commit/push or deployment occurred.

#### P3.3 result — 2026-11-11: read-only production wiring verified locally

The production QIP now includes the native host/card/cache helper and new
`ngage_mmc_hps.v`. Template slot 2 is exposed as **Mount MMC card (read only)**;
slots 0/1 retain C:/PMM and slot 3 diagnostics. The host is inside UPP, the
card is at board level, and the direct CLK/CMD/DAT0 connection remains an
explicit shortcut for unimplemented D550/AMA behavior. Known IRQ21/23/24 are
wired; IRQ22 remains low pending evidence. No slow/fast performance selector
is introduced.

The HPS adapter preserves native 1..8-sector reads and validates original v1
CID/CSD CRC/end bits, supported CSD/OCR fields and payload bounds before card
admission. Missing metadata cannot synthesize a production card identity.
Captured slot-2 ownership survives guest reset/remount until ACK and delayed
buffer strobes drain; malformed ordered-word counts quarantine the session.
Size-zero removal is quiet. Guest reset retains/replays a mount; cold transport
initialization forgets it. Writes are explicitly disabled for this read-only
gate; the separate P3.5 snapshot/persistence/removal work is still required.

The donor's internal command-busy prefetch hint is retained through UPP to
the card, suppressing speculative reads when final CMD12 is queued. It is
not a new phone pin or interrupt. Required demand reads remain enabled.

Final pinned results, with 169 source/test hashes unchanged across the runs:

| Check | Result |
| --- | --- |
| Captured MMIO/pin owner and FIFO lanes | 30 cases / 132,221 clocks; held responses, IRQ 21/23/24 and 22 low, final-command/busy/NRC ordering |
| Eight-channel paced DMA | 96 TX/RX transfers for 1/2/3/5/511/512-byte lengths, 98 completed host phases including focused boundaries / 667,085 clocks; guards, selector capture, ACK/mask, stop/reset, invalid requests and blocked-peer progress |
| HPS adapter | 36 direct cases / 24,435 clocks |
| Actual four-slot `hps_io` plus native card | 265,094 clocks; 9 card/2 other-slot reads, two 4 KiB bursts, 7 ACK-low final words, 2,128 overlapping cycles; metadata/slot isolation, reset/remount and malformed-transfer quarantine |
| Authored ARM in actual MiSTer/UPP/card composition | 29,010 clocks normal; 29,424 with CPU Hold during metadata. Exact CID, DMA 5+3 padding, odd PIO, ICU mapping/ACK and WP rejection pass |
| Existing LCD CPU/reset regression | All modes pass; frame 130,685 clocks, normal/held 152,456/152,537 unchanged |
| Original DMA ISR | Zero/three waits 11,067/16,449 clocks, no instruction substitutions; refreshed current source hashes |
| Fresh bounded boot | 5M cycles, 351,379 transactions, 12 known fetch faults, zero data errors; original low-ROM delay loop at 00006164; no LCD frame |
| Formatter, source graph and stubbed top | 11 files / 0 needed; 185 required files / 9 QIPs; structural elaboration passes |

Sol High implemented the two owned slices; Astra independently reviewed the
final adapter, ownership/DMA/IRQ and prefetch delta with no remaining blocker.
The all-channel matrix caught a new helper-function sensitivity dependency;
explicit readiness arguments fixed it before freeze. Test-peer timing bugs
and the reset/removal corrections are recorded with the evidence.

[Production evidence](docs/evidence/mmc-production-2026-11-11.json) includes
final source/log hashes and child manifests. The real-ARM test uses behavioral
backing memory/HPS; the separate actual-HPS fixture uses dummy pending peers
for slots 0/1, not the raw-save/NOR managers. There is no original EPBUS execution,
whole-firmware card mount, file/game launch, physical timing or FPGA-fit claim.
P3.4 original-driver/firmware read acceptance is next; P3.5 writable persistence
and replacement remain separate gates. No commit/push or deployment occurred.

### P4: LCD transport and controller behavior

Adapt command/data FIFO, transfer lengths, packing and DMA pacing. CPU and DMA
must reach one ordered transport instead of address-specific framebuffer
shortcuts. Retain NEM-4 `15/75/5C` behavior; do not substitute QD DCS `2A/2B/2C`.
Investigate partial windows, odd starts, endpoints, wrapping, idle/partial mode
and display state from our firmware before implementing missing commands.

Tests: retained cold-boot command fixture, CPU/DMA interleaving, queue fullness,
packing lengths, subwindows, odd columns, bounds, reset/GRAM retention, scanout
and screensaver/wake sequences with fixed-pixel expectations. Gate: full and
partial updates reach correct locations without hiding unsupported commands.

### P5: wall clock and UEM calendar

Adapt MiSTer RTC ingestion/calendar counting and reset survival. Map its time,
day count and original NOS date-event semantics through audited NEM-4 services.
Avoid two timebases or a fake date initializer replacing real state silently.

Tests: host RTC updates, unset clock, leap/month/year rollover, day-counter wrap,
guest writes/alarms where implemented, warm reset and NOS service notifications.
Gate: clock/settings survive normal resets and advance coherently; no claim of
physical UEM timing without evidence.

### P6: keypad and host controls

Retain original rocker/matrix wiring, public key numbering and shared source-25
W1C fix. Evaluate donor generic connectivity/ghosting independently of QD pin
maps. Audit direction/interrupt enables only against original-firmware usage.

Tests: all contacts both directions, held/release/repress, simultaneous keys,
ghosting, direct keys, press/ACK races, shared NOS pending, OSD inhibition and
full key-to-IRQ-to-handler flow. Gate: Menu/softkeys act from a matched reached
UI/screensaver state; a changing KEYS HELD field alone is insufficient.

### P7: ARM game PCM audio

User scope (2026-11-11): game audio produced/controlled by ARM software. No DSP
execution, telephony/voice services, radio audio or physical codec emulation
for this phase. Keep only the minimal guest playback/API bridge needed by games.
Linux ALSA is independent; the native MiSTer core audio output remains available.

Adapt the donor two-buffer PCM fetching, rate/volume/resampling and completion
machinery as an explicit software-audio interface. Preserve original game-side
start/stop/buffer expectations where viable. The donor HLE register page is an
emulator invention; do not present it as physical D550/UPP hardware. Do not make
this depend on full phone NOS sound services or restoring the whole NOS/BT
compatibility overlay mechanism. Any minimal guest shim must be scoped and
counted explicitly. Port maintained new HDL as Verilog-2001.

Tests: captured PCM reference comparison, mono/stereo, rates, volume, alignment,
start/stop/restart, reserve/release, completion order, last-buffer/underflow,
guest buffer submission, bus delay/reset and concurrent MMC/LCD/saves. Measure
the PCM engine plus MiSTer output logic that becomes active with nonzero audio.
Gate: repeated game streams work and teardown frees resources, with explicit
area/DSP/104 MHz timing budgets. No claim of DSP or phone-service emulation.

### P8: Bluetooth, SIMIF and remaining chip boundaries

Keep existing independent BT HCI compatibility and verify it survives new NOS,
memory coherence and overlay packaging. Do not add donor retry-limit edits.
Physical LRB-2, RF, codec/FM and missing DSP-flash behavior remain explicitly
unimplemented unless separately evidenced. Keep each relevant chip boundary
and its non-driving unsupported pins per `docs/chip-inventory.md`.

Audit existing diagnostic SIMIF separately from logical SIM replacement before
any connection. Define a single state owner if they are ever combined.

Tests: BT init/local/no-peer responses and cancellation, BT/NOS selector matrix,
reset/reload coexistence, SIMIF no-card/ATR/APDU fixtures where supported, and
chip-boundary/source-inventory tests. Gate: no regression or invented successful
physical protocol. Missing implementations stay visible in documentation.

## 13. Z1-Z5: useful CPU changes

### Z1: conformance and donor-fix inventory

Classify donor changes as already present, applicable/missing, ARM925-specific
or ARM9V2-dependent. Import directed/random instruction and fault/retry tests
with ARM920-appropriate references, not TI CP15 identity expectations.

Tests: repaired L1/L2 faults without invalidation, interrupted Thumb BL, failed
conditions, multiply flags, banking, widths/rotation, abort base restoration,
prediction aliases and variable memory latency. Run the complete current CPU
suite and signature/instruction comparisons. Gate: no unexplained architectural
differences before changing execution/storage internals.

### Z2: MLAB register-file candidate

2026-11-11 audit: first compare word-local FF write decoding and a CP15 selector
specialized to its architectural/banked read set. Production background port C
is already tied off; dummy registers are used. Keep compact indexed reads as
the baseline, all valid bank/microcode state, no extra CPU clocks and104 MHz.
Only then assess RAM/latest-writer replication, including MLAB's logic cost.
See [RF area audit](docs/register-file-area-audit.md) for evidence/tests.

Adapt replicated banks/latest-writer/pending-write bypass to the existing owned
operand stage. Preserve all 40 physical registers, normal/background write
priority, dedicated CP15 reads, reset values and same-edge collisions.

Tests: independent write scoreboard, every address, simultaneous writes,
held/just-committed bypass, banked/SPSR values, stalls/clears/reset, operand-edge
tests and full CPU suite. Gate: intended cycle/architectural equivalence and a
measured resource/routed timing benefit.

### Z3: arithmetic and predictor candidates

Separate rotate/prepared-shift controls, registered DSP multiplication and
frontend/predictor/return-stack changes into independent comparisons.

Tests: shift 0/31/32/>32, immediate/register/RRX, signed/long accumulation,
flags/failed conditions; predictor source/state aliases, calls/returns,
overflow/underflow, speculative repair, mode/context changes, IRQ/FIQ and
stalled redirects. Gate: correct behavior and useful latency/throughput/area
or timing results. Reject regressions rather than bundling compensating changes.

### Z4: early refill completion and hits during a miss

Carry requested-word identity in descriptors and return it before full-line
installation. Preserve ownership of remaining beats and existing error policy.
Execution before instruction-fill completion needs an explicit no-later-error
guarantee or pending-fault machinery. Do not copy donor error consumption.
Add hits during a miss only after early completion is stable, excluding refill,
victim, install-collision and maintenance hazards.

Tests: every critical-word position, late/missing beats/errors, redirects,
interrupts, dependent consumers, same-set accesses, stores/maintenance/reset
and exact-once completion. Test both DDR and physical SDRAM. Gate: proven safe
progress and improved miss penalty; no early stale or duplicate result.

### Z5: complete ARM9V2 trial

Preserve a common integrated ZAP branch first. Adapt ARM9V2 integer execution
to our ARM920 CP15/cache/TLB interfaces, precise retirement and locks. Do not
copy QD cache geometry, larger advertised-mismatched caches or direct-mapped
TLBs. Keep donor source provenance and reproducible conversion; never hand-edit
the large generated CPU. All introduced synthesis HDL must meet repository
Verilog-2001 compatibility requirements; imported source style remains intact.

Tests: all current/donor-derived cases, independent architectural traces,
randomized stalls/faults/interrupts, branch/load/store/multiply windows, then
same-firmware/peripheral/image/input full-phone comparisons. Gate: whole-device
fit/timing/resources and useful phone throughput. Eight stages and donor game
success alone are not acceptance criteria. Switching branches must restore the
old CPU without silently mixing simulator/checkpoint lineages.

## 14. T1: observable runtime and hardware traces

Adapt separate retired-instruction/exception, completed-data-access and bus
rings with trigger/freeze/export and a versioned decoder. Include NOS resource
ownership, pending requests and completion state sufficient to audit semi-real
behavior. Count architectural retirement separately from micro-ops/fetches.
Use existing disk export or a documented DDR transport without overlapping
firmware/save memory. Trace freeze is not CPU halt or a resumable checkpoint.

Tests: ring wrap, simultaneous trigger/event, reset, export backpressure,
decoder format/version, synthetic known event sequences and observer
noninterference. Gate: traces diagnose keys, service waits and faults without
changing guest execution in the tested observation controls.

## 15. I0: combined validation and release gates

Promote only independently accepted stages. Preserve old/new builds and the
integrated-ZAP reference. Do not merge every experiment merely because it builds.

Functional checks:

- Complete CPU, ownership, line-transfer, SDRAM, NOR/descrambling, overlays,
  reset, storage, chip and peripheral regressions appropriate to selected changes.
- Actual `hps_io` raw C:/PMM and diagnostic/card slot concurrency, original
  service loader order independence and overlay coexistence.
- Real-controller cold firmware boot and cache-active workloads. Fast backing
  arrays cannot validate the physical SDRAM controller or pin capture.
- Original versus semi-real profiles with identified original NOS runtime work,
  consistent SIM state, no duplicate replies and no UI/C: format bypasses.
- Keypad wake/Menu, card mount/game launch, repeated audio, RTC and real guest
  save/load behavior as each feature becomes available.

Physical checks on later authorized builds:

- Source graph, generated/patch reproduction and formatter/whitespace checks.
- Whole-device resources/RAM inference, all-corner setup/hold/recovery/removal/
  pulse checks, DDIO packing and external SDRAM timing. No false/multicycle
  exception copied without proving its transaction relationship locally.
- Hardware pattern/mask/bank/refresh tests before relying on firmware behavior.
- Disposable C:/PMM guest change, Save, reset/remount and controlled power-cycle
  verification. HPS ACK alone is not storage durability.
- Report branch/full SHA, source changes, clock/firmware/profile, scene/inputs,
  resource/timing limits and original-versus-donor evidence for every comparison.

Use fresh simulator lineages for changed hardware. Any migration requires its
own named-state and continuation-equivalence audit. Preserve every billion-cycle
CPU/host pair and record missing milestones. Keep logs bounded and do not touch
the current long run merely to establish a new baseline.

## 16. Existing test entry points and planned additions

These are starting points, not commands run by this planning step. Read the
latest `docs/status.md` and `docs/bringup.md` before selecting future runs.

| Track | Existing local coverage to retain/extend | New focused coverage |
| --- | --- | --- |
| CPU | `tests/cpu/run.sh`, operand/reference/edge, TLB, CP15, cache and SWP benches | donor-derived random/fault/retry cases, new storage/frontend miters |
| DDR | `tests/phone/ddr_rom_cache/run.sh`, `line_refill/run.sh`, `memory_owner/run.sh`, `flash_reset/run.sh` | coherent general cache, owner/reset fuzzing, 64-beat sector snapshots |
| SDRAM | `sdram/run.sh`, `run-ddio.sh`, `run-short-reads.sh`, `line_refill/run.sh`, `direct_sdram/` | donor wrapper, captured writes, alternate bank-map and negative timing tests |
| Storage | `sd_sector/run.sh`, `save_hps/run.sh`, `save_manager/run-full.sh`, `save_sector/run.sh`, `dirty_tracker/run.sh` | raw conversion, dual persistence images/four slots, ordered autosave/overflow |
| NOR/loader | `cflash/`, `codeflash/`, `flash_decode/`, `service_loader/`, `mister_transport/` | all new-writer cache-coherence and raw-restore cases |
| NOS/overlays | `overlay/run.sh`, `overlay/hps-run.sh`, `overlay_bootstrap/run.sh`, `nos_io/` | real-runtime ownership, channel/DFC ABI, queues, SIM/service state, package bounds |
| Peripherals | `icu/`, `timers/`, `timer_rates/`, `cbus/`, `keypad/`, `lcd_*`, `simif_*`, `chip_boundaries/` | general DMA, MMC bit protocol, RTC calendar, PCM and shared IRQ/master tests |
| Full phone | `hardware_boot/run.sh`, `compare-run.sh`, `run-real-sdram.sh`, `run-logo.py` | versioned semi-real profiles, matched input scripts and integration matrices |

Shell/Python runners must use the existing simulator image and record source
identity. No Quartus download or unrequested hardware deployment is needed.
Donor tests that silently skip absent private fixtures must be reported as
skipped, not counted as exercised firmware/card coverage.

## 17. Recommended execution order

1. Finish P0 and Z1 baseline definitions. Run N1 early so the semi-real NOS
   requirement constrains the implementation rather than being added afterward.
2. Complete S1/S2 independently on the existing memory path. In parallel as
   ordinary task scheduling permits, resolve P1 and the N2 service boundary.
3. Implement D1/D2/D3, then S3. Stabilize B1 and port P2/P3 DMA/MMC.
4. Integrate N3/N4 in a controlled semi-real profile. Use T1 when needed to prove
   original runtime and diagnose remaining UI waits. Do not replace startup.
5. Complete P4 LCD, P5 RTC, P6 input and P7 audio; validate P8 coexistence.
6. Evaluate R1/R2 with independent physical tests; keep R3 optional. Isolated
   Z2/Z3 experiments may follow Z1 when measurements justify them.
7. Save the common integrated **old-ZAP** branch checkpoint. Evaluate Z4 and
   the separate Z5 ARM9V2 branch against it with identical remaining components.
8. Run I0 on the chosen configuration and record deferred physical features.

First usable milestone: raw C:/PMM automatic mounting with unchanged original
guest behavior. Next: coherent DDR/bulk saving and general DMA/MMC. Final
functional acceptance additionally requires semi-real NOS runtime, responsive
UI/input and the selected peripheral features, with memory/CPU improvements
promoted only when measured and validated.
