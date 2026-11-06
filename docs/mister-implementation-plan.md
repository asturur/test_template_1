# N-Gage simulation → MiSTer implementation handoff

Repository audit: 2026-11-05. Planning only: no firmware run, synthesis, image rewrite or checkpoint deletion. Read together with the newest entries in [status.md](status.md). The investigation's machine-readable hashes are in `scratch/mister-migration-plan/image-audit.json`; the essential inventory is retained below so the ignored scratch artifact is not required to execute this plan.

## Assessment and target

The reusable part is the patched ZAP CPU, MMU/cache integration, flash bank decoder, descrambler equations, and the C++ phone model. Simulation executes real NEM-4 firmware far enough to produce LCD traffic and screens, run the kernel/NOS and exercise writable flash. This is not a complete, validated physical phone. The FPGA top cannot presently boot equivalently: loader/address/lane handling is wrong, IRQ/FIQ are tied low, video is blank, controls are unused, and substantial device behavior is absent.

Target: cold-load the same useful firmware/profile, show actual firmware LCD output, deliver held/released phone keys, preserve writable media, and record a useful failure if firmware stops. Navigating a displayed menu/dialog is the eventual interactive acceptance criterion; receiving GPIO reads alone does not satisfy it. A reproducible observable firmware assertion is a valid intermediate hardware milestone, not a claim of a working phone UI.

Current limits to preserve:

- `scratch/current-boot/board/` is the maintained full baseline; `scratch/simif-board/board/` is the newer staged diagnostic-card variant, built by its own `build.py`. Neither is `sim/boot_profile.cpp`, and neither contains the live-control wiring in `scratch/live-controls/boot_profile.cpp`.
- Staged fresh-card lineage stops at 7,225,961,838 cycles; power-status-2 variant at 7,843,031,842; matched no-ATR lineage at 9,534,596,302. Fault tracing identifies the same `St_product.c:0xdf2` ADSP self-test assertion: expected message 0x8b, received 0x02 through dispatcher key 0x5902. Sources: newest status entries and `build/sim/runs/boot-v15-simif-{fresh-gss-8b,powerkey-faulttrace,noatr-faulttrace}/`.
- Synthetic SIM data, inferred controller/FIFO/FIQ behavior, no-ATR diagnostic and DSP MDI announcement/consumption are experimental. No-ATR is not a proven electrical no-card model. Do not infer SIM causation, fabricate ADSP replies, force MTC READY, patch assertions or shorten firmware waits.
- Recent 1.2B GSS replays are selected-PC observations, not full initialization proofs. Raw checkpoint SDRAM inspection omits dirty CPU cache.

## Verified images and their meanings

The useful current build is `build/sim/obj-simif-board/Vngage_cpu_sim`, built from current `rtl/ngage_cpu.sv`, `rtl/arm/`, `rtl/arm920/` plus the staged board. `scratch/simif-board/run.py` validates its build manifest. Its default C: is the saved 11B image; PMM is loaded only when `pmm-image=...` is actually passed. Restoring a checkpoint also restores mutable board state; it does not replace the need to bind external inputs.

| Role / current path | Exact bytes | SHA-256 |
| --- | ---: | --- |
| `build/firmware/nem4-factory/core.bin` | 18,612,224 (`0x11c0000`) | `be8b2ecdf5ff81f424b58838a8b93a1d1f65c0ae74890d2b96df8d5a7189b524` |
| `build/firmware/nem4-factory/extension.bin` | 2,293,760 (`0x230000`) | `cb6e0b39c90df00864fc21ee527624372b1e4f5c3ff3c985f397172d30446cf3` |
| `scratch/overnight/cdrive-11b.img` | 4,194,304 (`0x400000`) | `af5017dcc0d4979ae9c7313a3a77295922009f08e26fbb559bd90d9539190a47` |
| `scratch/overnight/pmm-aan.bin` | 65,536 (`0x10000`) | `c7075d001311f5f122137fc891b2ade159fb39931810ae0d9965aea2a07e2496` |
| Reference only: `build/firmware/thc/nos-image.bin` | 2,594,432 (`0x279680`) | `72787f4aed7c48e645a5db2ff3ccd28c1dbb71cf477497b9352554d38598f89b` |
| Reference only: `build/firmware/thc/nos-iat-region-0x6e030.bin` | 17,808 (`0x4590`) | `cc0d59312f720b3d2725c6926e0cbd6a7c5936dec2d8477440cb25261c61148b` |

The service inputs retained locally are `firmware/MCU/extracted/products/NEM-4/nem440.3c1` (18,777,938 bytes; SHA-256 `e948c435c977772a30ff2dd8ef608f7542a978c0acfd257bc0986925fd548690`) and `nem440.326` in the same folder (1,361,703 bytes; SHA-256 `fd4126eeaddf5c0cd72a9961f51e283bd1ed4245106e20f01d5a5551e85fddc7`). They are preparation sources, not direct simulator arguments. No separate additional “service file” is loaded by the latest runner. If that phrase refers to a different user file, identify it by contents/hash before assigning a region; it is not evidence of another required memory device.

Origin and actual loading:

1. The first two files are a split of a `0x13f0000`-byte assembled logical image, not individual chip dumps. `scratch/authentic-flash-image/assemble.py` assembles extracted `nem440.3c1` MCU and `nem440.326` PPM records, overlays PPM after MCU, preserves the erased personalization hole `0x12c..0x163`, pads gaps with FF and splits at `0x11c0000`. `scratch/nem440-flash-extract/extract.py` documents and checks container record headers/checksums. The service package is an input to offline preparation, not a fifth independent phone memory region. The .326 PPM language/content file is distinct from writable **PMM**.
2. `firmware/Nokia N-Gage/Data/roms/NEM-4/{BOOT,ROOT,SYM.ROM}` are a different input family. BOOT is an 8-KiB runtime snapshot, ROOT contains additional filesystem payload, and SYM.ROM is the 17.75-MiB logical dump. Do not concatenate these, load BOOT as the reset bootloader, or substitute them into this profile. QD RH-29 and developer RH-4 bundles require separate profiles.
3. The assembled extension contains real .326 content and a passing extension descriptor. The old reconstructed ROOT extension remains a historical separate experiment. Do not describe the selected factory extension as synthetic.
4. `descramble-window` in staged `main.cpp:56` transforms every halfword in physical `[0xa000,0x2b3000)` before construction. It obtains real NOS content from the service image. Current `run.py` hashes the THC NOS and IAT reference files but does **not** pass `nos-image=` or `nos-iat-region=`; they are not loaded by the selected command. Optional legacy overrides are PA `0x9d280+` and `0x6e030+`, gated on periodic initialization, and must remain disabled for this profile. Do not require these two files on MiSTer merely because provenance lists them.
5. C: descends from a firmware-formatted simulation volume, later extracted after 11B write-through boot activity (`scratch/c4-after-boot/wt-cdrive-11b.img`); it is not a physical user-flash dump or a clean erased volume. The historical 12B volume was not saved. Preserve the current source; initialize a separate working copy.
6. **PMM loading discrepancy:** current `scratch/current-boot/live.py` explicitly supplies `pmm-image=...`, but the newer matched SIM launchers and staged runner defaults do not. Their provenance still advertises/hashes `pmm-aan.bin`. `main.cpp:261` loads it only when the argument exists, and `save_state()` does not serialize `pmm_image_` (only programmed overlay state). Thus the latest matched replay reads untouched PMM as FF plus restored overlay, not automatically the advertised seed. Older fresh-run provenance lacks extra arguments, so do not infer its external PMM from its metadata alone. For exact matched-profile parity, use an explicit erased 64-KiB PMM section plus the intended from-reset profile; for the maintained seeded profile, use the seed below and explicit RTC input. Do not conflate either cold start with a checkpoint restore. Milestone 0 must resolve and record this profile choice before a boot comparison.

   PMM is a synthetic formatted seed with NVD date records made by `scratch/pmm/seed_pmm.py`, not a physical PMM dump. `docs/status.md` records the a,a,n seed and `cbus-input=0x24=1` RTC hypothesis. The seed script's older explanatory text contains superseded argument-order assumptions: preserve the verified bytes/hash instead of regenerating an allegedly equivalent seed during the port.
7. The factory manifest's statement that the core digest is unmatchable is stale. [firmware-integrity.md](firmware-integrity.md) and `scratch/flash-cipher-r4/reproduce_stock_digest.py` establish the stock MD5 `2c09c86ff047484fdcc0e226f49c44a9` after descrambling. Do not use `digest-probe-core` or rewrite expected digests.

The names `boot.rom`, `boot1.rom`, `boot2.rom` currently appear in `Template.sv` comments as core/extension/C:, with high index bits 00/01/10. This is an intended loader convention, not verified HPS behavior. There is no fourth PMM load in the top, and only one file-select entry. The user's “three boot files, service file and user disk” therefore cannot be treated as five independently mapped images: preserve both naming families in the preparation instructions and show the user the four resolved components and hashes.

### CPU map and proposed backing allocation

Use `rtl/ngage_rom_map.sv`, already boundary-tested in `tests/phone/mister_map/tb.sv`. Offsets refer to core+extension concatenation; CPU addresses are byte addresses.

| Phone PA, end exclusive | Length | ROM concatenation offset / role |
| --- | ---: | --- |
| `00000000..00700000` | `700000` | `0000000` |
| `02000000..02400000` | `400000` | `0700000` |
| `04000000..04800000` | `800000` | `0b00000` |
| `00700000..007f0000` | `0f0000` | `1300000` |
| `007f0000..00800000` | `010000` | independent PMM |
| `02400000..02800000` | `400000` | independent C: |
| `0a000000..0b000000` | `1000000` | phone RAM, external SDRAM |

Proposed DDR allocation, relative to a framework-safe core base B: ROM `[0,0x13f0000)`, guard `[0x13f0000,0x1400000)`, C: `[0x1400000,0x1800000)`, PMM `[0x1800000,0x1810000)`. Load extension at `B+0x11c0000`, not `B+0x800000`. Optional diagnostics begin after `0x1810000`. Reserve 32 MiB for the core. Candidate B=`0x30000000`; verify it against the installed MiSTer Main/Linux reservation before hardware use. The local framework exposes global addresses and reserves other windows (scaler at `0x20000000`, arcade video default `0x24000000`); 1 GiB physical DDR does not mean 1 GiB is free for this core. This host reservation is an explicit remaining platform check, not established by the 29-bit interface alone.

The current software model intentionally serves 4 MiB C: only. The firmware's overlapping 6-MiB type-3 descriptors do not justify extending it through `0x02a00000`. Keep gaps faulting and record any accesses. Three physical 8-MiB flash devices remain the board evidence; logical bank order is a separate mapping.

### Loading and persistence design

Use an offline Python preparer under maintained `tools/` to accept the existing four files or checked NEM-4 .3c1/.326 containers. It must validate sizes, record hashes/profile/version and produce a versioned bundle (header + four sections with explicit lengths/destinations/checksums); preserve all originals. A single MiSTer OSD bundle selection avoids dependence on automatic boot-name ordering. Individual explicit load indices may remain a developer option; bind them to the same manifest. Do not parse Nokia service records inside FPGA logic.

Implement a loader FSM with bounds checks, section coverage, checksums, `ioctl_wait`, a pending-write queue and explicit “loaded/failed” status. Reset remains asserted across gaps between downloads and until all four sections, DDR writes, SDRAM initialization/clear and board initialization complete. Resetting the phone must not clear the loader-valid flags or flash contents. An aborted/short/out-of-order/oversized load leaves the CPU held with an error. HPS download is privileged initialization; CPU access must go through flash command state. Check both 64-bit halves and a partial final word.

For persistence, prefer the local `hps_io.sv` virtual disk API (`img_mounted/img_size/img_readonly`, `sd_lba`, `sd_rd/sd_wr/sd_ack`, sector buffer). Mount a **working save image**, separate from the immutable bundle, with a small versioned header bound to firmware hashes followed by 4 MiB C: and 64 KiB PMM. Guest C: remains raw LFFS NOR, not FAT. First use copies the selected seed or explicit erased PMM into this save image; subsequent boot loads saved C:/PMM after ROM. Reject incompatible/read-only saves for writable mode visibly.

Track dirty 512-byte sectors on committed program/erase, and flush through an arbitrated sector buffer. Serialize writes against snapshots of sectors: a sector dirtied again during flush stays dirty. Give each flash operation a coherent completion boundary; a normal reset drains accepted writes/flushes before resetting device command state, retaining array bytes. Expose Saving/Saved/Error and an explicit flush/eject action. Gate reconfiguration/reset while a requested save is pending. Test mount, save, reset, reload and real power-cycle recovery before claiming persistence. Unannounced power loss can lose unflushed changes; for stronger guarantees add a bounded sector journal with checksums/sequence numbers and recovery, rather than claiming SD writes are atomic. Require save acknowledgement before telling the user it is safe to power off. Preserve prior save generations on the host.

`ioctl_upload` is not a proven substitute: the local header explicitly says Main support is core-specific, and `Template.sv` supplies constant `16'hffff`. Remove/disable the misleading Save action until real readback exists. A fallback export workflow must save a new file and successfully reload it; never overwrite `boot2.rom` or the canonical source image implicitly.

## What must move to synthesizable HDL

Use the actual staged `BootProfile::access`, `tick`, `flash_command`, `cdrive_access`, `run_lcd_dma` and header IRQ helpers as the software contract. Extract an address/side-effect inventory from these functions before moving code. Generic latches do not cover devices that mutate on reads, FIFO pops, timer events or masked IRQ generation.

| Area | Existing RTL / software evidence | Required implementation |
| --- | --- | --- |
| CPU/MMU/cache | Shared `rtl/ngage_cpu.sv`; patched `rtl/arm/`; associative cache macro enabled in `files.qip` and current build | Keep current CPU and CP15/cache fixes. Verify dirty eviction, maintenance/drain, MMU/TLB held responses, aborts, byte lanes, SWP bus lock under real waits. Cache BRAM inference and 104-MHz timing remain unknown. |
| Bus/map | `ngage_mister.v` partial decode; disconnected `ngage_rom_map.sv` / `ngage_ddr_lanes.sv` | One latched transaction, exactly one ACK or ERR, stable responses, masked writes and bounded arbitration; decode before dispatch, illegal access records fault. |
| Memory-controller/boot scratch | C++ `latches_`, `scratch_`, probe registers and copied routines | Port exact `0x080000xx` controls and initialized executable scratch around `0x0c004748..0x0c0047fc`; do not silently convert unknown regions into zero RAM. |
| GPIO/system blocks | `ngage_board.v` devices 2/4/5/6 implement broad latch ranges and some status quirks | Preserve write masks and read side effects in C++ priority order; separate independent address banks; add dynamic input, loopback/routing, set/clear semantics, NOS interrupt state, trace sink and reset initialization. |
| Clocks | device 3 has ideal-clock truth table, PLL wrapper separately creates FPGA clocks | Retain exact observed ideal statuses as assumptions; isolate unknown combinations. Define peripheral timebase explicitly, independent of memory completion. |
| IRQ/FIQ, timers | C++ header: timer/UEM/DMA/NOS IRQ; unit60 and SIM FIQ | Three ICU banks, set/clear/current/pending/priority; boot timer, periodic tick, unit1 settle, unit60 FIQ, NOS compare/counter; wire active-high CPU IRQ/FIQ. Implement masks and acknowledgements, not just event pulses. |
| UEM/CBUS/RTC | Stateful C++ CBUS transport, ADC, power/status, RTC masks/status/alarms and routing | Port command/response sequencing and per-register semantics, configured ADC values, boot power input then release, tick and RTC behavior. Keep unverified values in named diagnostic profiles. |
| Code flash / PMM | No FSM in FPGA; C++ AMD identify/burst and AMD/Intel program/status/lock overlay | Independent per-chip command state with addressed-bank status scope; PMM seed/overlay, readback, reset/lock behavior. Normal ROM must not turn into status words during PMM operations in another bank. |
| C: NOR | C++ `cdrive_access`, four-MiB backing | Halfword AA/55/A0 program, identify, erase setup/confirm/poll/suspend/reset; array byte/halfword/word reads and observed ignored plain word writes. Mark dirty only on actual mutation. |
| LCD | RTL transport validates headers/control but drops pixels; C++ DMA records | Command/data decoder, direct pixels, DMA SDRAM master, framebuffer and video. IRQ only on completed accepted transfer, status/ack exact. |
| NOS/ASIC/DSP | C++ ASIC BX-LR page, upload memories, DSP MDI ring pointers/announcement/consumption and NOS status bits | Keep these explicit experimental device models. Port shared RAM/ring/byte ordering and IRQ delivery before evaluating ADSP progress. No real DSP executes in current model. |
| SIMIF | Staged `simif_status.h`, `test_card.h`, reserved map state | Separate diagnostic controller/card module, RX/TX/FIFO/status W1C, group status, FIQ bank0 bit26; explicit present/no-ATR profile. Unconditional ATR is no longer the only behavior. |
| Bluetooth / ISI modem / audio / MMC | `rtl/ngage_modem.v` standalone responder; `rtl/ngage_bt_hci_stub.sv` isolated HCI experiment | Neither is the real firmware NOS transport. Do not wire them to guessed registers. Port observed UART/status/MDI assumptions; investigate newly reached accesses. Actual audio, RF modem and external MMC need separate work and are not prerequisites unless firmware blocks on missing behavior. |

Important incompatibilities confirmed in code:

- `ngage_mister.v` RAM decode includes both 0x0a and 0x0b high bytes (32 MiB), despite its 16-MiB comment. CS1's bit pattern decodes the wrong region; CS2's pattern corresponds to 0x02000000 rather than 0x04000000. The endpoint comparison uses an aligned address and is not a substitute for a correct range decode. Replace these expressions; don't patch offsets independently.
- The flash address concatenations use 23-bit literals `0x800000`/`0xc00000`, which cannot represent the intended offsets. Some offsets truncate even before the interface's byte-versus-word error.
- Current loader uses 32-bit units and 32-bit data on the real 29-address-bit, 64-data-bit, 8-byte-enable DDR port; it discards high read lanes, ignores BUSY, can repeat reads, drops a final unmatched halfword and releases reset before proving completeness. `DDRAM_WE` only serves download; CPU flash writes are absent. Descrambler result is computed but unused; its input address uses shifted bits rather than the equations' absolute PA convention.
- `ngage_board.v` says low-16 indexing cannot collide, but `0x0c100000`, `0x0c030000`, `0x0c150000` and other claimed ranges share `gidx=a[15:2]`. Its 0x0d RAM aliases by low 12 bits. C++ stores full addresses. Add pairwise separation tests. These broad claims also hide stateful devices and `unmodeled` currently never reaches CPU ERR.
- `ngage_bram_be.v` has neither reset nor explicit initialization, while comments promise zero. Verilator's zero initialization is not proof of FPGA reset semantics, and `ALLOW_POWER_UP_DONT_CARE` is on. Use a bounded scrubber or valid bits; scrub again on phone reset where the software model resets latches. Do not reset arrays in a way that prevents BRAM inference.
- `Template.sv` treats `jtframe_sdram64` `ack` as data-ready; in `jtframe_sdram64_bank.v`, ack is `st[READ]`, with separate `dst/dok/rdy`. It samples data too early in principle; the replacement must establish actual data capture edges from the controller's pipelined signals. It also drives requests from live CPU fields and ties distributed refresh input low. These are additional blockers beyond the DDR findings.

Flash-model fidelity issue to resolve explicitly: C++ C: program assigns bytes, allowing 0→1; PMM overlay ANDs subsequent writes but the first write does not AND with its seed. Physical NOR normally requires erase before 0→1. First add tests exposing these cases and check reached firmware operations. Preserve a named simulation-compatible mode if needed for comparison; adopt erase-before-program semantics as a reviewed model correction in both C++ and HDL. Do not silently make the FPGA more permissive or change only one oracle. C: erase completion currently advances on status reads (first returns 0x0008, next erases); preserve this experimental contract until replaced with justified timing in both models.

## Controls and LCD behavior

### Controls

Reference is `scratch/live-controls/boot_profile.cpp:1330`, `keys.py`, [live-controls.md](live-controls.md), schematic sheet A-13. Active-low closures:

- Rocker input is upper halfword of PA `0x0c150208`: idle mask `0x2c06`; up GENIO1, right2, down10, OK11, left13. Clearing a bit presses; restoring it releases.
- Matrix scan drives bits 0..5 in upper halfword of `0x0c15040c`. The low five column inputs are low-halfword `0x0c150400`, idle `0x1f`; selected row/pressed contact clears its column bit. Low-halfword `0x0c15040c` is idle row detection, idle `0x3f`, with any pressed row pulled low.
- Physical columns 0..5 are GPIO8/9/10/11/16/30; rows 0..5 GPIO12/13/14/15/17/18. Matrix: row0 col0 leftsoft, col1 menu; row1 col0 clear, col1 radio; row2 col2 rightsoft, col3 star, col4 hash, col5 shift; row3 col2/3/4 = 1/2/3, col5 0; row4 col2/3/4 = 4/5/6, col5 send; row5 col2/3/4 = 7/8/9, col5 end.
- Column5/GPIO30 is represented separately by `0x0c120c04` bit19; music GENIO28 by `0x0c15020c` bit12. These paths and the voltage/pull-up model remain hypotheses. The live patch supplies read levels; it does not implement a new keypad interrupt source. Rocker scan has been observed (down→logical 0x80000), while softkey UI action is not established. Determine from firmware whether polling is sufficient or a GPIO transition IRQ is required before assigning any interrupt bit.

Create `ngage_input.v` with a held-key vector at least 26 bits (current 16-bit port is insufficient), keyboard make/break state from `ps2_key`, and OR-combined controller state. Default: arrows/D-pad → rocker; Enter/A → OK; F1/X → leftsoft; F2/Y → rightsoft; Tab/Start → menu; Backspace/B → clear/back; Esc/Select → end; digits/*/#/Shift from keyboard; L/R → send/end; F10 → modeled power input. Keep back/clear separate from end-call. Power PWRONX is absent from the live model: add a distinct UEM/power path with traced press/release semantics, not reset or a permanent startup-status bit. Expose hardware reset separately in OSD. The model already changes held-power status after initialization; preserve that behavior until a better electrical model exists.

Tests: every key press/hold/release, row drive including no/multiple selected rows, simultaneous keys, mixed keyboard/controller ownership, OSD opening/disconnect/reset clearing held state, GPIO mux/loopback priority and read widths. Do not synthesize host auto-repeat as repeated presses. On the phone UI, demonstrate two moves and a return after release, both softkeys, menu then clear/back, and OK on a reversible dialog. If firmware cannot reach that UI, record where input reaches scan logic and leave interactive acceptance open.

### LCD and video

`DirectLCD` recognizes command header `0x09200000`, memory write 0x5c, display-on 0xaf, full-frame data header `0x8924d67f`; words are little-endian pairs of RGB444 `0x0RGB`. Existing compositing assumes row-major 176×208, source FB `0x0a000020`, 352 bytes/row. DMA channel at `0x0c120340` starts on `0x348=2`, uses source `0x354`, destination `0x360`, words-minus-one `0x36c`; accepts LCD destination `0x10121208` (DMA alias) or `0x0c121208`. C++ copies RAM immediately and marks DMA done; real HDL must arbitrate and finish before setting IRQ bank0 bit7. Capture the header at arm, not after transfer.

Implement `ngage_lcd.v` and `ngage_lcd_dma.v`: bounded command/data FIFO, address/window/format state for reached commands, direct-write cursor, DMA transfer progression and partial-update positioning. Existing host renderers recognize limited patterns; source-address-derived line positioning is a tested software convention, not verified LCD controller addressing. Decode observed controller window/orientation commands where possible; unsupported commands must produce a visible diagnostic rather than silently assembling a false frame. CPU dirty cache must be cleaned by firmware before noncoherent DMA; DMA reads physical SDRAM, with no invented snooping of dirty lines.

Use a 73,216-byte dual-port framebuffer initially (or 54,912 bytes if packed 12-bit storage is required for fit). One writer domain, one scan domain; vblank synchronization for optional frame swaps. Preserve portrait aspect ratio 176:208 = 11:13; `Template.sv` currently declares 4:3. Produce a defined stable raster, e.g. a standard 640×480 diagnostic/video canvas with the portrait image centered and integer-scaled where it fits, rather than assuming a bare 176×208 raster works on every output. Expand nibbles ×17. Check labels/top-left, asymmetric color corners, halfword order and line stride against recorded firmware screenshots; orientation remains a hypothesis until compared with physical UI evidence. Never rotate merely to fit the screen.

Add a small hardware diagnostic page alongside the phone image: build/profile ID, section-loaded bits, last completed bus address, IRQ/FIQ pending/enables, timer progress, DMA frame count, save state and first fault. Capture a bounded ring of recent MMIO/flash commands and guest debug characters (`0x0de00000/0x0dfd0000`) for HPS export through a verified interface. Preserve last good LCD image on faults. A PC watchdog can log a hang, but must not force firmware forward; expose PC/retirement only through a synthesizable optional tap. LEDs provide loading/running/fault even before video works.

## Ordered execution milestones

Each milestone is a reviewable unit. Proposed module names below are new work, not existing files. Do not start with a billion-cycle boot. Independent device tests must run before integration firmware tests.

### 0. Freeze an executable reference and fixture inventory

Files: add `tools/prepare_mister_images.py`, `tests/phone/fixtures/` manifests, board-profile documentation; preserve source hashes of both current and staged boards plus live keypad patch. Capture complete resolved runtime options from runner defaults plus extras; provenance currently lists stale synthetic-NOS/extension claims and can hash unused files. Record PMM argument presence, C: hash, UEM 1-versus-2 setting, SIM mode and exact CPU macro. Choose staged diagnostic-card as comparison profile, with no-ATR as a second named profile; neither silently replaces the maintained baseline.

Create small transaction fixtures by calling the actual board directly: bus request, masked response, accepted side effects, elapsed logical ticks and IRQ/FIQ state. Include negative/unmodeled accesses. Use existing C++ tests and small windows of retained `bus.tsv` rather than rerunning firmware. No trace fixture may depend on an undocumented checkpoint-state mutation.

Done: four resolved components validate (PMM may be an explicitly generated erased section for the matched diagnostic profile); stock core/extension digest checks pass on derived working bytes; fixtures reproduce under fixed hashes; unused THC reference files are not runtime dependencies. Preserve all originals, existing screenshots and CPU/host pairs. Changes in HDL serialized state start a new lineage; don't restore old .cpu files into a changed Verilated design.

### 1. Replace memory transport and loader (recommended first code task)

Files: new `rtl/ngage_ddr_adapter.sv`, `rtl/ngage_loader.sv`, memory arbiter; change `Template.sv`, `ngage_mister.v`, `files.qip`; connect existing ROM map/lanes and add them to the source list. Start with a fake DDR responder in a directed test, without CPU or flash command FSM.

DDR contract from `sys/sys_top.v:1701`, `sys/sysmem.sv` and `sys/arcade_video.v:210`: 29-bit address in 8-byte beats, 64-bit data, 8-bit byte mask, BUSY=waitrequest, read return valid separate from acceptance. Latch full byte address, requester, half selector and masks; hold command stable while BUSY; after accepted read deassert RD and await one response; acknowledge a write only after acceptance (and drain/fence before save/readback where required). Use burstcount=1 initially. Word lane comes from byte-address bit2; halves use their own byte enables. Keep accepted reads alive across phone resets so stale responses cannot answer a new requester.

Single `clk_sys` for HPS core interface/arbiter/DDR port is simplest. The framework handles the HPS DDR crossing; don't add a guessed CDC at DDRAM_DOUT. Cross any independently clocked request via FIFO/toggle handshake with stable payload; synchronize reset release per domain. CPU/download/save/DMA ownership is registered. Respect wb_lock through the entire SWP read/write reservation, allowing refresh but no other RAM master between them; cap service bursts so DMA/save can't starve CPU. CPU is held while loading. Unknown/unmodeled slave cycles return ERR once and record the first fault.

Done: map boundary tests, both DDR halves, all masks, delayed BUSY, delayed valid, back-to-back requests, reset during outstanding read, loader holes/duplicates/short sizes, end-of-file tail and arbitration produce exact memory bytes with no duplicated transactions. Firmware sections never overlap. First/last words and section checksums read back correctly. No CPU required for acceptance.

### 2. Repair SDRAM and establish platform reset/time semantics

Files: extract `Template.sv` two-halfword adapter to `rtl/ngage_sdram_adapter.v`, retain `rtl/sdram/*`, add refresh scheduling and RAM clear controller; update PLL/SDC as needed.

Latch CPU/DMA address/data/masks, perform low/high halfword transactions and collect data on the controller's actual data-valid phases (`dst/dok/rdy` must be established from a short waveform). Do not use early ack as a data-valid indication. Insert refresh at the controller's specified cadence, honoring its request/grant behavior even under continuous bus load. Gate CPU until SDRAM init and the chosen zero-RAM scrub complete. Verify bank geometry AW=22 against installed SDRAM size; model only 16 MiB and explicitly reject 0x0bxxxxxx. Atomic word stores hold arbitration across both halves.

The generated `rtl/pll/pll_0002.v` actually requests 104 MHz and -2404ps SDRAM phase. The QIP has old 20-MHz/one-clock metadata; reconcile it before regeneration. Start with a fixed, achievable clock and report it; if reduced, preserve the explicit 104M-model-tick/RTC and 3174-cycle NOS-counter relationship with a deliberate enable/timebase design. Do not assume firmware timing is frequency-independent: waits, peripheral ticks and added bus latency interact. Changing the timebase is a measured model change, not an optimization to bypass timeouts.

Done: SDRAM behavioral model sees correct masked byte/halfword/word accesses at bank boundaries, refresh under sustained traffic, no bus recapture after ACK, deterministic RAM/reset state and no stale response. Re-run existing CPU width/MMU/cache/SWP/drain/abort tests with variable wait states using the current associative configuration. Fit remains unproven.

### 3. Port NOR and make persistent save real

Files: `rtl/ngage_flash.v`, `rtl/ngage_save.v`, hps_io virtual disk hookups in `Template.sv`; `tests/phone/flash/` extended for both C++ boards and RTL.

Implement chip ID/protocol/mode separately from backing address decode. Give C: priority over overlapping code-flash command windows as C++ does. Port addressed-bank PMM lock/status scope and command-looking program data priority. Dual descramblers use **absolute even PA** and transform both halfwords only in the configured read window; commands/status/PMM bypass descrambling. Reference `board/descramble_model.h`, not the unused top-level wire.

Test identify/burst/reset, program values 0x60/0xf0, independent chips, PMM lock in same/different 2-MiB bank, seed/overlay read merging, C: unlock addresses, 64-KiB sectors and four top 16-KiB sectors per 2-MiB die, erase polling/suspend, malformed widths and the 0→1 discrepancy. Use `tests/phone/flash/test.cpp`'s existing lock regression; its script currently compiles the current board only.

Done: software/RTL transactions agree on the chosen explicit semantics, CPU instruction fetch is unaffected by another flash bank's status, stock digest passes on HDL readback, save/reload reproduces all modified C:/PMM bytes and untouched sectors remain identical. An interrupted save reports failure and recovers the previous committed generation where journaling is implemented. Normal reset retains mutations; a fresh-load action is explicit.

### 4. Port heartbeat and boot-critical register behavior

**Status:** Completed for the scoped board-model port and directed acceptance tests; see `docs/mister-board-bringup.md` for evidence and limits. SIM/card, LCD DMA/video/input, hardware diagnostics and full hardware-bound validation remain in milestones 5–7.

Files: split/repair `rtl/ngage_board.v`; add `ngage_icu.v`, `ngage_timers.v`, `ngage_cbus_uem.v`, `ngage_nos_io.v`. Add to `files.qip` and an HDL simulation wrapper selecting one owner per device. Include boot latches/executable scratch, clock tables, CBUS ADC/power/RTC, epbus clock block, NOS timers/status, shared RAM/upload blocks and trace sinks from the inventory above.

Unit60's real current-model destination is **FIQ bit3**, not the historical IRQ-source3 approach. IRQ source numbers observed include timer0 current=1, UEM/unit1=2, DMA=8, NOS=26 (zero-based mask bits 0/1/7/25). Verify priority and read/ack behavior directly against `access()`; do not confuse current-index-plus-one with bit index. FIQ bank set/clear differs from IRQ bank conventions. Tests must cover simultaneous pending sources, masked events becoming unmasked, write-one clear, byte enables, compare wrap and counter read aliases. Read-side effects commit exactly once, even with bus stalls.

Done: tick/event-driven fixture comparisons match data and interrupt edges, broad latch-bank alias tests pass, ASIC/upload/scratch executable bytes persist correctly, unknown operations fault visibly. A short CPU test receives and acknowledges both IRQ and FIQ. HDL/C++ state is never updated twice for the same device. No full phone run yet.

### 5. Port diagnostic SIMIF and retain DSP limits

Files: separate `rtl/ngage_simif.v` and bounded test-card state, staged `simif_status.h`/`scratch/simif-investigation/test_card.h` as references; model DSP MDI ring/status behavior in `ngage_nos_io.v`. Keep no-ATR option explicit and apply it from reset/pre-card state, not midway through an initialized card.

Done: `status_test.cpp`, `test_card_test.cpp`, `no_atr_board_test.cpp` vectors translated to RTL verify reset/ATR one-shot, RX FIFO thresholds, TX-to-card, W1C status/reassertion, group status, byte order and bit26 FIQ masking. Diagnostic file responses remain byte-identical, including absent optional EF-OPL/EF-PNN relationship. Preserve existing modeled DSP consumption/announcement with clear diagnostics; do not invent a successful self-test response. A no-ATR profile is acceptable for an initial comparison but cannot stand in for porting reached controller registers.

### 6. Deliver visible video and held/released controls

Files: LCD/DMA/input modules described above; framebuffer RAM and scanout in `ngage_mister.v`, `Template.sv` video/OSD aspect/input mapping; directed fixtures in `tests/phone/lcd/` and new input tests.

Bring up a test pattern and hardware diagnostics with CPU held first, then replay saved direct LCD writes and DMA line-band fixtures through real arbitration. Existing `tests/phone/lcd/test_direct.py` covers the host renderer, not HDL video. Add asymmetry/partial transfers, command order/display-on, invalid destination/count, DMA masked IRQ/ack, CPU/DMA contention and cache-clean visibility tests. Never write fake “booted” graphics over guest output.

Done: output dimensions/timing are stable; RGB and exact framebuffer checksum match reference fixtures; incomplete frames are visibly marked; key matrix/rocker held/release tests pass. The overlay shows memory progress and first fault independent of LCD activity.

### 7. Integrated short verification and build gate

Files: new HDL-board harness under `sim/`, focused runner under `tests/phone/`, separate `build/sim/obj-...` lineage. Use `jotego/simulator:arm64` (no new image/tool download). Run short standalone firmware routines/transaction replays and existing CPU tests before considering a fresh full boot. Programmed waits may differ from C++ zero-latency: compare device ordering, data, event time in logical ticks and causal IRQ acknowledgements; require cycle equality only when replay timing is deliberately identical.

Do not connect a sparse old HDL wrapper and assume C++ fallback validates an all-HDL board. Produce a report of every reached device and which side owns it; hardware-bound profile must have no required C++ fallback. CPU/cache source and serializable model changes invalidate old Verilator .cpu restore compatibility. Keep paired .host/.cpu inputs immutable. Any later long run must preserve **every** billion-cycle checkpoint including the terminal boundary; old retention exceptions do not apply.

Done: no unresolved unknown response on selected boot-critical fixtures; CPU tests pass under arbitration/waits; stock digest matches; images/save/video/input all tested; source list includes actual new modules; reset/CDC lint and memory inference review are ready. Only then schedule the first synthesis. A long firmware simulation is a separate explicit follow-up, not part of this investigation.

### 8. First synthesis, timing and resource closure

Use an existing licensed/available Quartus setup compatible with the local Cyclone V project (QSF names 17.0.2); do not download it as part of this plan. No toolchain or MiSTer access was verified during this audit. Build a distinct hardware output under `build/mister/` and preserve build/source/profile hashes.

Before a full compile, elaborate the exact `files.qip`, generated PLL and `sys/` dependencies. Confirm FPGA part/pins from the project, selected SDRAM geometry and Main interface. Check PLL/QIP consistency. Review Analysis & Synthesis reports for M10K inference of cache/board/framebuffer and unintended register arrays; resource budget includes the whole MiSTer framework, not CPU alone. The current generic 64-KiB GPR plus separate 4-KiB RAMs and caches/framebuffer compete for BRAM; solving aliases with many duplicated full-sized RAMs can exhaust it. Use sparse register storage and bounded shared upload memories, measuring inference rather than assuming fit.

Full compile acceptance: fits the actual device, no latches/multiple drivers/width truncations, no unconstrained paths, setup/hold closure at the chosen clock for all corners used, justified CDC exceptions, SDRAM I/O timing and refresh requirements met. The current Template.sdc contains only PLL derivation/uncertainty; complete external timing constraints rather than declaring timing closed from Fmax alone. If 104 MHz fails, reduce/decouple clocks with tested timer semantics, not cache removal or firmware hacks. Export .rbf only from a passing build.

### 9. First on-board run through interactive acceptance

Needs: DE10-Nano MiSTer with verified external SDRAM capacity, SD card and installed Main supporting the selected virtual-disk protocol, HDMI/display, USB keyboard and controller; a deployment path and a log/readback route (SSH or local SD) must be established. Physical-phone captures/raw chip IDs are useful for authenticity questions but not prerequisites for reproducing the simulation profile. Hardware deployment authorization/access is a future execution step; this request authorizes planning only.

1. Boot diagnostics with CPU held. Confirm clocks, live video, DDR/SDRAM address-pattern/checksum/refresh tests and input events. Validate reserved DDR base before writing any firmware backing there.
2. Load validated bundle plus a disposable working save. Check section length/checksum/readback and stock digest; only then release CPU. Record build/profile/tick settings and hashes.
3. Observe reset fetch, flash identify, MMU/cache setup, kernel tick/CBUS/RTC, NOS initialization, first direct clear, DMA frames and input scan. Export first fault/ring and guest debug text when progression stalls. Use the last successful firmware milestone rather than an elapsed-wall-time guess to compare with C++.
4. Exercise phone UI wherever reached using directions/OK/softkeys/menu/back with explicit releases. Retain screenshots/video and input timestamps. If ADSP assertion recurs, capture its message/routing and timing; a different stop needs memory/IRQ/timing comparison, not an assumption it is caused by SIM.
5. Perform a reversible guest C: change when reachable; flush, soft reset, reload core, then power cycle after Saved. Verify C:/PMM host bytes and guest result. Keep the original save and source images untouched.

Done for the hardware-observation milestone: real firmware output plus traceable input scan and reproducible diagnostic stop. Done for **interactive boot**: a firmware UI responds to movement, OK, both softkeys, menu/back and releases, and save/reload works. If firmware stops before navigation, report this goal as still incomplete with the precise blocking evidence.

## Documentation corrections and open decisions

This document supersedes conflicting implementation guidance in these historical descriptions; retained measurements remain useful:

- `docs/mister-core.md`: per-chip memory offsets, extension-at-8-MiB and three-input flow are wrong for the current concatenated image; scaler acceptance and frequency-independence are unverified. `docs/mister-port.md` accurately flags the core DDR/map gaps but omits the SDRAM, alias and reset problems above.
- `docs/hdl-migration.md`: generic GPIO/clock/device coverage has advanced beyond its partial listing, yet is not equivalent to the stateful current C++ model; original checkpoint version/build paths and synthetic-extension/NOS discussion are historical. `docs/bringup.md` still says caches are direct mapped; current builds enable `NGAGE_ASSOC_EXPERIMENT`.
- `docs/display-bringup.md` “latest run” is an older timer frontier; use newest status plus current direct/DMA tools. `docs/live-controls.md` names a 23B replay whose old seed screenshot was deleted (recorded Nov 3); don't execute that launcher as the new baseline.
- `docs/sim-presence.md` says no runtime ATR switch exists; staged header/main now implement `simif-no-atr`, with matched comparisons completed. Neither profile is physically verified.
- `build/firmware/nem4-factory/manifest.json` and old assembler comments still call stock digest unmatchable; do not regenerate inputs during active investigations to fix prose.

Remaining decisions/blockers: verify Main DDR reservation and persistence behavior on installed software; establish SDRAM data-valid timing in a testbench; fit/timing of the associative CPU/cache and independent board memories; correct NOR first-program behavior; confirm LCD addressing/orientation beyond renderer assumptions; determine whether keypad needs an IRQ; implement PWRONX beyond startup status; resolve the ADSP response path without fabricated success. SIM/modem/audio fidelity remains a research track after transport parity, not a reason to weaken firmware checks.

Recommended first implementation assignment: **milestone 1, a tested 64-bit DDR transaction adapter + nonoverlapping loader integrated with `ngage_rom_map` and `ngage_ddr_lanes`**. Begin from the four exact input hashes and fake-DDR tests; stop that change at verified image readback, CPU held. It resolves the unavoidable loader/transport foundation and is small enough to review before any peripheral migration or expensive firmware run.
