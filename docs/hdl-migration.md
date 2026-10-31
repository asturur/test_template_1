# HDL migration plan: from the C++ board model to the MiSTer core

(written with Claude, 2026-10-31, at the user's direction: "transfer this in
HDL and be able to sim the HDL. We still need to keep this C thing work if we
want to iterate faster with simulation, and keep savestate compatibility in
HDL so also sims in HDL can be done recovering from a point.")

## Architecture

The Verilated sim keeps ONE bus dispatch (main.cpp), with two servers:

    ZAP (SV) --wishbone--> [ rtl/ngage_board.v  (HDL devices, claim/rdata) ]
                               | unclaimed
                               v
                           [ BootProfile (C++ devices, boot_profile.cpp) ]

- `rtl/ngage_board.v` (jtcores-style Verilog-2001 per project rules; ZAP
  stays SV) owns migrated devices. For each CPU access it outputs `claim`
  and, for claimed reads, `rdata`. It will also grow `irq`/`fiq` outputs
  that OR into the CPU lines as interrupt-driving devices migrate.
- main.cpp consults the HDL board first; only unclaimed accesses reach the
  C++ BootProfile. bus.tsv logging is unchanged (main.cpp logs every CPU
  transaction either way), so all trace tooling keeps working; HDL-claimed
  rows keep their familiar device labels.

## Two binaries, two checkpoint lineages

- `build.py` -> obj-boot-v15-nosprobe: C++-only, UNTOUCHED. Its rolling
  checkpoints and fast iteration workflow stay exactly as they are. This is
  the research vehicle.
- `build-hdl.py` -> obj-boot-v15-hdl: same main.cpp compiled with
  -DNGAGE_HDL_BOARD, the wrapper `ngage_cpu_sim_hdl.sv` (instantiates
  ngage_board) and rtl/ngage_board.v. Own checkpoint stem (hdl-*). Each
  device-migration batch changes the Verilated model and so invalidates
  ONLY this lineage; one from-reset with rolling checkpoints re-seeds it.

## Savestate compatibility

Verilator --savable serializes the whole Verilated model: every register in
ngage_board.v is saved/restored through the existing .cpu file with NO extra
work. The C++ .host file keeps serving the not-yet-migrated devices. Rules:
- A device lives on exactly one side at a time; its state moves from the
  .host (BootProfile save_state) to the .cpu (Verilated) when it migrates.
- The board checkpoint version (v6 today) bumps when C++ fields leave, with
  load-compat for one version back where practical.
- HDL-lineage checkpoints bind to the exact Verilated model (same rule we
  already live with for the CPU): batch migrations, re-seed with one
  from-reset per batch.

## Migration order (self-contained first; SDRAM/DMA last together)

 1. LCD transport regs 0x0c121200/204/208 (status 0x40000000 read, header/
    control/data latches). Last hop of the logo. <- STARTING HERE
 2. GPIO/keypad/system-control latch banks (0x0c14f0xx, 0x0c1500xx-0x5ff,
    0x0c120c0x) incl. the 0x0c150514 TX-idle bit 2 quirk. Needs the C++
    exclusion list (latches_/probe_regs_ overrides) resolved statically.
 3. Timer units + periodic tick + ICU current/enable banks + FIQ banks
    (the interrupt heartbeat; ngage_board grows irq/fiq outputs).
 4. CBUS/UEM engine (command/response state machine).
 5. Flash state machines (amd16 ROM window, cdrive LFFS program/erase).
 6. SDRAM to HDL (MiSTer SDRAM controller) + LCD DMA engine (needs memory
    port) + NOS/stub flash windows; at this point main.cpp's C++ fallback
    is only instrumentation and the board model is the verification oracle.
 7. MiSTer top: wire ngage_board + ZAP + SDRAM + LCD framebuffer scaler
    into Template.sv/sys (video out from the DMA'd frames, keypad from HPS).
 8. FLASH OPTION (proven feasible 2026-10-31, docs/firmware-integrity.md):
    the flash stores the Nokia service payload VERBATIM, so "flash the
    service package" = parse nem440 records ([0x14][addr:4 BE][ck1]
    [len:3 BE][ck2]+payload) and write payloads at record addresses (HPS
    side), 0xFF elsewhere; per-device hole = 56 B at [0x12c,0x163). This
    reproduces authentic on-chip content. Only NOS-from-flash execution
    additionally needs the unsolved read-side descrambler (until then:
    THC plaintext NOS + authentic IAT region, as in the sim).

## Validation per device

A/B from-reset runs (300M-1000M cycles, minutes): same firmware, C++-only
binary vs HDL binary; diff bus.tsv rows for the migrated address range
(values AND cycle alignment), plus the existing 28 board unit tests for the
C++ side. A migrated device must be bit-identical on the observed boot path
before the next one starts.
