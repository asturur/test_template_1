> **Current checkpoint (2026-11-06):** This file retains historical port notes below; several statements about loader, flash, interrupts, SIMIF and DMA are superseded. Read [status.md](status.md) and [mister-review-2026-11-06.md](mister-review-2026-11-06.md) for current implementation, validation and open risks. CPU Hold remains the default, and no hardware boot is claimed.

# MiSTer port of the phone simulation

See the [2026-11-05 implementation handoff](mister-implementation-plan.md) for the code-audited image/profile inventory, additional SDRAM/storage defects, persistence design and executable milestones. Its findings supersede conflicting historical architecture notes.

The running boot simulation uses `scratch/current-boot/board/boot_profile.cpp` as its phone model. That model contains boot-enabling assumptions; matching it is a bring-up target, not proof of physical N-Gage behavior. Do not alter its inputs during an active run. No FPGA synthesis is planned until the CPU and a fresh long boot have been evaluated.

## Current state

`files.qip` includes the shared `ngage_cpu`, ARM changes and associative ARM920 cache. `rtl/ngage_mister.v` instantiates that CPU, but its phone integration is incomplete. IRQ and FIQ are tied inactive, LCD outputs are blank, keys are unused, and C: and PMM flash behavior are absent. The RTL board device is not equivalent to the C++ simulation model. No MiSTer build, timing closure or hardware operation has been verified by these observations.

The present loader and memory path must be replaced together: the extension image overlaps the main image; the loader assumes 32-bit DDR words even though the MiSTer port is 64-bit; busy/backpressure and CPU flash writes are not implemented. The existing ROM decoding also maps banks incorrectly. Do not use it as evidence that the firmware is loaded correctly.

## Memory map used by the current simulation

These offsets index the **concatenation** of `core.bin` and `extension.bin`, in bytes. The firmware's bank table supplies these regions; they are not asserted to describe the individual physical flash chips.

| CPU physical address | Length | Concatenated image offset |
| --- | ---: | ---: |
| 00000000–006fffff | 700000 | 0000000 |
| 02000000–023fffff | 400000 | 0700000 |
| 04000000–047fffff | 800000 | 0b00000 |
| 00700000–007effff | 0f0000 | 1300000 |

The tested image has core length `0x11c0000`, extension length `0x230000`; the concatenation ends at `0x13f0000`. The model also maps PMM at `0x007f0000–0x007fffff`, C: at `0x02400000–0x027fffff`, and 16 MiB RAM at `0x0a000000–0x0affffff`. `rtl/ngage_rom_map.sv` captures this decode and has boundary tests; it is deliberately not connected to the incomplete DDR interface yet.

## Ordered port work

1. Design the 64-bit MiSTer DDR adapter: address units, byte lanes, read/write handshakes, busy handling, bus locking and CPU/download arbitration. Place the concatenated ROM, writable 4 MiB C: and 64 KiB PMM in non-overlapping DDR regions. Load all four images with explicit indices, reject incomplete images, and hold reset until loading finishes. Verify against the actual MiSTer DDR contract, including CDC and odd-sized transfers.
2. Connect the tested address decoder and implement the NOR command state, read/write and erase behavior using the simulation as a behavioral reference. Preserve C: writes and PMM separately; define how they persist to the host. Test bank boundaries, command sequences, lanes and resets. Compare transaction traces against the simulation.
3. Port board registers in small tested groups: interrupt controller and FIQ/IRQ, timers, clocks, GPIO/keypad, CBUS and other devices reached during boot. Distinguish confirmed hardware from simulated stubs, including Bluetooth timeout behavior. Run directed RTL tests for side effects, reset values and interrupt clearing.
4. Port the LCD command/data path, framebuffer and display timing. Reproduce both direct writes and DMA behavior exercised by the model. Test image pixels, orientation, timings and keypad-driven changes; then connect MiSTer video and input.
5. Exercise the integrated board with short deterministic transaction replays and CPU tests. Run a fresh cycle-zero long firmware simulation only after the outstanding CPU work and peripheral integration are ready. Compare boot milestones, errors and captured screens with the current model; retain billion-cycle checkpoints. FPGA synthesis and timing are later steps, after the requested long-simulation assessment.

Keep `docs/status.md` and the topic notes current as each stage becomes real. Do not assume inferred FPGA RAM type or timing from a passing behavioral simulation.

## DDR lane preparation

`rtl/ngage_ddr_lanes.sv` converts a word-aligned byte address and 32-bit data into the MiSTer 64-bit DDR lanes. It follows the local `sys/arcade_video.v` convention: address bits `[31:3]`, bit 2 selects the half, and the byte enables select the four bytes within it. Directed tests exercise both halves and all 16 byte masks. This is combinational preparation only: it is not connected and does not handle `DDRAM_BUSY`, read responses, arbitration, crossing clock domains, or write completion. A controller must latch the selected lane until each read response arrives.

## Standalone transport work (2026-11-05)

`ngage_ddr_adapter.sv` and `ngage_loader.sv` have directed standalone tests, but are not integrated into the top or tested together. The v1 bundle generated by `tools/prepare_mister_images.py` is provisional. See the latest `docs/status.md` for verification and remaining work; the legacy top-level loader remains unsafe.

## Bundle transport connected (2026-11-05)

`Template.sv` now selects a single NGB bundle and connects loader, registered-owner arbiter and 64-bit DDR adapter. CPU remains unconditionally in reset for later SDRAM/flash/board work. Byte-exact full-image simulated readback passes through both loader and CPU-side DDR requests. `0x30000000` remains an unverified DDR reservation; actual HPS, power-loss persistence and hardware use are not validated. See latest status for tests and commands.

## Native HDMI image and centered analog raster (2026-11-07)

Phone framebuffer and HDMI input active area are **176x208 pixels**, RGB444 in 16-bit pixel slots. Original aspect is **11:13**; diagnostic mode retains 320x240 and 4:3. The timing raster remains 400x262 pixel clocks, with phone pixels centered at x=72..247/y=16..223 and black elsewhere. H/V blanking/DE enclose only the phone rectangle; the HDMI scaler therefore sees 176x208, rather than a 320x240 image containing borders. Analog RGB/sync retains a centered image with surrounding black intervals. Actual CRT frequency/porch tolerance remains a board-test item; no analog timing compatibility is claimed from simulation.

Reference: MiSTer-devel/Gameboy_MiSTer `f6796f3a021db61f804c3151678941ce4d74a3b9`, `rtl/lcd.v` keeps a larger timing raster and separate game/border blanking, with selectable analog width; `Gameboy.sv` uses native aspect. We adopted the separation of pixel rectangle and timing raster, not its Game Boy clock numbers or Super Game Boy border. The read-only checkout is under `scratch/reference-gameboy-mister/`.

Phone mode now emits only guest pixels. Unknown/incomplete state remains available on the diagnostic page, export flags and command logs; no colored error stripe is drawn over the phone image. New logo-run scanout PNGs are 176x208, captured through CE and DE with coordinates normalized to the phone origin. The frozen old simulation and its bordered 320x240 captures remain unchanged.

`sh tests/phone/lcd_display/run-native.sh` checks every active pixel in two coordinate-coded frames, exactly 36,608 DE pixels per raster, all sync pulse counts, native/diagnostic blanking and black analog padding. A separately labeled display-only replay of the observed Nokia framebuffer also matches every pixel and the original framebuffer PNG hash. It is not a new phone cold boot.

## GitHub Quartus build source preflight

The manual `CI Build` action is the supported Quartus 17.0.2 build environment; local Jotego tests do not produce an RBF. `tools/check_quartus_sources.tcl` evaluates the selected project/QIP graph, resolves quoted HDL includes and checks required paths and duplicate QIPs. It runs inside the existing Quartus action container before compilation; locally `tclsh tools/check_quartus_sources.tcl` checks 167 required source/constraint/script/header files and nine unique QIPs. Two absent optional HDMI/audio component-symbol files are not synthesis inputs.

`files.qip` includes the ARM header search path and owns the core PLL inclusion once. `rtl/pll.qip` is a maintained source-only manifest, using the existing `pll.v`/`pll_0002.v` HDL rather than contradictory generated 20-MHz/one-output metadata. The HDL still specifies two 104-MHz outputs; only clock 0 is used, and SDRAM clock forwarding uses its existing DDIO path. No PLL ratios, SDRAM phase or controller behavior were changed by manifest cleanup. Real Quartus fit, inference, timing and SDRAM pin placement remain build/hardware gates.

### Quartus generate-loop parser compatibility

The first manual build reported Error 10170 for `generate for (genvar lane=0;...)` in `rtl/arm920/cache_lines.sv`. The index is now declared with module-scope `genvar lane;`, and the loop starts `for (lane=0;...)`. This preserves the 32 byte-lane instances and their hierarchy; cache-line and associative-bank regressions pass. Re-run the manual action to verify Quartus compilation and expose any subsequent build errors.
