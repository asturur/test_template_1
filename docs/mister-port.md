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
