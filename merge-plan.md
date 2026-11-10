# N-Gage donor integration plan

Updated 2026-11-11. **P0/S1/S2 and D1 committed. D2, D3 and S3 locally verified.**

This plan combines raw C:/PMM persistence, the DDR backend, SDRAM controller,
useful CPU changes, semi-real NOS/SIM, and the peripheral work. Creating the
branches and writing this document do not authorize a build, deployment or
firmware modification. Subsequent implementation should follow the stages and
acceptance gates below.

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
| P7 | PCM audio and selective NOS sound service | B1, P1, N4 |
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

### P3: MMC host, card and tooling

Port `upp_mmc`, `mmc_card`, CID/CSD/OCR metadata and `mkcard.py` concepts with
their tests. Preserve actual card identity for protected titles. Adapt 1-bit
clocking to our system frequency and audit NEM-4 routing/chip ownership; QD's
wiring is not automatically the original phone's wiring.

Support identification, single/multiple-block reads/writes, CRCs, busy,
timeouts, read-only cards, FIFO pacing and real source 21-24 behavior. Keep
guest card state distinct from host mount state. Retain safe removal limits;
donor warm swaps do not prove writable-card removal is safe.

Tests: independent bit-level host/card CRC checks, real metadata fixtures,
state errors, capacities/bounds, partial reads, write protection, CMD12 ordering,
host delays, CPU/DMA/LCD contention, remount/reset and malformed images.
Use local actual `hps_io` tests as well as the donor's modeled peer. Gate:
firmware mounts a card, reads files and launches a known scene without storage
corruption; writes/removal need separate acceptance.

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

### P7: PCM audio and NOS sound protocol

Port two-buffer PCM fetching, rate/volume/resampling and completion machinery
with the selective NOS sound service. Keep original SoundDevice/driver client
behavior where viable; synthetic hardware page/interrupt is explicitly an
emulator interface, not DSP or codec emulation. Audit source assignment rather
than borrowing timer 5 merely because the QD donor does.

Tests: start/stop/restart, reserve/release, completion order, last-buffer/underflow,
mono/stereo, rates, volume, alignment, guest-thread DFC writes, bus delay/reset
and concurrent MMC/LCD/saves. Compare captured PCM samples and expected timing.
Gate: repeated streams work and teardown frees resources; no silent real-DSP claim.

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
