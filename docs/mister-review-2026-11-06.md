# MiSTer milestones 0–5 review — 2026-11-06

Scope: implementation commits from `16381df` through `3469ba7`, plus the current uncommitted milestone-5 SIMIF/card changes. This is a code and directed-test review, not FPGA synthesis, hardware validation or a new full firmware run. No implementation was modified by this review. Source images, screenshots and checkpoints were not changed.

## Assessment

Substantial, useful implementation with independently reproducible tests. The image preparer, loader and 64-bit DDR path address the original overlap/lane defects. The SDRAM adapter now uses the controller's later ready signal and schedules refresh. Flash/save support is functional under its test models. The board has explicit interrupt, timer, CBUS/UEM, MDI and memory ownership, and the new SIMIF/card port has unusually useful comparisons against the actual staged C++ sources, including stalled requests. The chip boundaries distinguish UPP, UEM, audio DSP and experimental card, while radio placeholders remain explicitly inactive.

“Completed through milestone 5” is reasonable as a description of **scoped device implementation and directed testing**. It is not yet a demonstrated complete HDL firmware boot, physical SIM, working MiSTer build or hardware persistence guarantee. The unconditional CPU reset hold in `Template.sv:131` remains, video is blank and keys are unused; these are intentional later gates.

## Confirmed finding: P1 — reset can deliver an old flash response to a new CPU request

`rtl/ngage_mister.v:97–102` clears `flash_issued` immediately on phone reset. The flash controllers deliberately drain accepted backing operations across reset, but their eventual `rsp_valid` still feeds `mem_ack`/`wb_ack` at lines 132–144. Neither cancellation nor a transaction generation distinguishes that old response from a request made by the restarted CPU.

A directed reproducer with the real `ngage_mister`, board, flash controllers and map replaces only the CPU with a scripted bus master. It accepts a flash read at PA `0x200`, pulses phone reset while backing memory is delayed, starts the restarted master's read at PA `0`, then returns the old read. Result:

```
new CPU PA=00000000 ack=1 data=deadbeef backend_accepts=1
REPRODUCED: pre-reset response acknowledges new CPU request without fetching its address
```

Source and evidence: `scratch/mister-review-20261106/reset_repro.v`, `reset_repro.f`, `reset-repro.log`. Rebuild/run inside `jotego/simulator:arm64` with `iverilog -g2012 -s tb -o scratch/mister-review-20261106/reset_repro -f scratch/mister-review-20261106/reset_repro.f` then `vvp scratch/mister-review-20261106/reset_repro`.

Fix before releasing the CPU: keep explicit ownership/cancellation of accepted flash operations across phone reset, suppress their old CPU completion/error, and reset command state once draining finishes. Alternatively hold CPU reset until accepted operations are safely drained and command state reset. Do not simply wait on the present `flash_busy`: it includes unfinished command sequences that themselves require CPU writes or reset to leave. Keep dirty events for writes that actually committed. Cover code reads, C: reads/program/erase, PMM writes, and reset coinciding with response. Check cold transport reset separately because the DDR adapter discards accepted read responses while flash controllers wait for completion.

The existing CPU test does not pulse reset during an outstanding operation, so its pass does not contradict this result. The current unconditional top-level reset hold masks this latent fault on hardware; removing the hold without a fix exposes it.

## Other limits to resolve, not newly discovered failures

- **Seeded PMM parity remains unresolved.** `ngage_codeflash.sv:127–128` ANDs first program data with the loaded seed; C++'s first overlay write ignores that seed. This is explicitly documented, but it means the seeded profile is not fully equivalent. Keep erased PMM as the initial comparison profile, and add a seed-with-cleared-bits test plus an explicit decision about both models before claiming seeded boot parity.
- **Firmware reach is shallow.** The reported 20M-cycle startup runs stop before the first modeled timer IRQ and SIM setup. The 132-address inventory tests ownership, not effects/order. The independent ARM integration test is valuable but uses a small synthetic program and delayed memory responders. A later firmware divergence remains plausible; tests do not show that ADSP/SIM limitations disappeared.
- **Hardware remains unvalidated.** Real Main/HPS disk traffic, reserved DDR range, PLL/QIP consistency, RAM inference, FPGA fit, timing and power-cycle persistence remain outstanding. Structural elaboration deliberately uses HPS/PLL stubs and `-Wno-fatal`; it is not a timing or warning-clean result. Its current log contains a `wb_ack` UNOPTFLAT path through ICU combinational blocks: determine whether block grouping causes a false dependency or there is real feedback before hardware closure.
- **Chip hierarchy is incremental.** Main flash/RAM backing remains outside the board hierarchy, and D551 DSP flash has no distinct model. The inventory labels those gaps honestly. Preserve these identities during new work; do not add invented DSP/radio replies or undertake pin-level reverse engineering solely to make the hierarchy look complete.
- **Continuity docs drifted.** `docs/mister-port.md` still describes absent flash/IRQ and broken loader behavior already replaced; `docs/mister-board-bringup.md` still says SIM FIQ is tied off. Refresh these before using them as the next agent's starting checkpoint.

## Checks independently rerun

All passed with the existing `jotego/simulator:arm64` image:

- 27 focused script groups (38 PASS lines), covering transport/map/loader, reset gate, flash, dirty/save/disk components, board ownership/inventory, chip placeholders, ICU/timers/NOS/boot registers, GPIO, MDI, LCD transport and SIMIF/card. The SIM comparison repeats both no-ATR and present profiles; the card matches 554 reference operations.
- `tests/phone/mister_board_cpu/run.sh`: actual ARM, board, SIMIF, IRQ/FIQ, abort, flash fetch and SDRAM request path, with delayed memory responders.
- All 18 reference source hashes; both saved C++ transaction fixtures; stock core and extension digest checks, including stock core MD5 through the actual RTL descrambler.
- SDRAM controller with the retained Micron model, refresh under traffic, CPU/DMA lock arbitration, and full 16-MiB cold scrub (8,388,608 halfwords).
- Full-size bundle load/readback: 25,165,952 input bytes, 12,582,912 accepted writes, correct sections and guard; full-size 4-MiB C:/64-KiB PMM save restore/flush/reload.

Small review logs are under `scratch/mister-review-20261106/`. No long phone simulation, synthesis, Quartus download or hardware deployment was performed. The reset reproducer is an additional failing correctness case despite the above regression passes.

## Recommended next assignment

Insert a short integration step before the full milestone 6, then split milestone 6 so observation arrives first:

1. **Reset and transaction lifecycle.** Fix the confirmed stale-response bug and add permanent regressions across real core/flash/DDR boundaries, including cold reset and committed-write dirtiness. Resolve the seeded-PMM test/profile decision and triage the top-level acknowledgement warning. Acceptance: every post-reset CPU completion belongs to a newly accepted request; backing writes drain without losing dirty tracking; no deadlock from reset midway through a command.
2. **Milestone 6a — observation first.** Implement a stable test raster, build/profile/loading/save/fault status, bounded MMIO/debug-character ring and an actual readout/export path. Use a deliberate diagnostic CPU-hold mode rather than removing the reset constant casually. Acceptance: test pattern and diagnostic state work independently of guest LCD activity, and a controlled bus fault is captured with its address/reason.
3. **Milestone 6b — firmware LCD.** Add UPP LCD DMA plus the separate LCD-controller/display boundary, framebuffer and video. Replay retained direct-write and partial-DMA fixtures through the real memory arbiter, testing completion IRQ, cache-clean visibility and orientation. Acceptance: framebuffer checksums match fixtures and IRQ occurs only after the last transferred word.
4. **Milestone 6c — physical controls.** Merge the live-input hypothesis into the current UPP GPIO model, with keyboard/controller press/hold/release and separate power handling. Acceptance: row/column/rocker tests, then actual visible UI actions when firmware reaches a navigable screen.
5. **Before a full firmware/hardware run**, add a harness for the real hardware-bound core/flash/map/memory-adapter composition with no C++ device fallback. Compare reached events against the selected staged profile incrementally; retain every billion-cycle CPU/host pair if a subsequent run becomes long. Target the next observable milestone, not an arbitrary larger cycle budget.

For an earlier on-board checkpoint, a CPU-held memory/video diagnostic build is useful after steps 1–2. First reconcile PLL metadata, verify the installed Main DDR reservation and synthesize for inference/resource/timing checks. This is an early platform validation slice, not a phone boot. Full pin-level CBUS/AMA modeling and additional SIM/ADSP research need not delay LCD/diagnostic work unless actual firmware evidence identifies them as the blocker.
