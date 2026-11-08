# N-Gage project documentation

**Resume with [status.md](status.md) - start at its "HANDOFF / START HERE"
block (2026-11-01).** It records completed work, exact measured stopping points,
assumptions, missing hardware, next steps and when to rerun checks; the dated
entries below the handoff are the evidence log, newest first.

| Document | Purpose |
| --- | --- |
| [peripheral-ownership.md](peripheral-ownership.md) | Regional UPP RAM ownership and sparse-register transaction contracts |
| [cpu-operand-stage-contract.md](cpu-operand-stage-contract.md) | Slice1 exact operand ownership/cycle contract, differential reference and measured latency/throughput tradeoffs |
| [cache-lookup-stage-contract.md](cache-lookup-stage-contract.md) | Slice2 cache lookup ownership, lookahead epochs, latency attribution and validation |
| [cpu-cache-sdram-104mhz-plan.md](cpu-cache-sdram-104mhz-plan.md) | Source-grounded whole CPU/cache/memory review, proposed 104 MHz architecture, cycle/resource budgets and ordered implementation gates (plan only) |
| [timing-closure.md](timing-closure.md) | 104 MHz baseline, worst-1000 timing exports, CI gate and path analysis |
| [phone-clocks.md](phone-clocks.md) | Phone reference clocks, slower interfaces, timebase assumptions and bus-bridge follow-up |
| [quartus-memory-audit.md](quartus-memory-audit.md) | Actual Quartus RAM inference, register-heavy arrays and resource-reduction priorities |
| [rtl-style.md](rtl-style.md) | Phone RTL formatting rules and reproducible formatter/check command |
| [status.md](status.md) | Current development checkpoint and ordered resume work |
| [TODO.md](TODO.md) | Assumptions and shortcuts to replace, with evidence and validation |
| [lcd-command-evidence.md](lcd-command-evidence.md) | Fresh HDL LCD fixture, decoded window framing and unresolved initialization commands |
| [display-bringup.md](display-bringup.md) | Firmware-driven LCD and startup display experiments |
| [nortido-hybrid-reference.md](nortido-hybrid-reference.md) | Hybrid-core LCD/keypad/MMC leads, local trace cross-check and limits of patched guest behavior |
| [bringup.md](bringup.md) | CPU integration boundary, simulation tools, diagnostics and output locations |
| [cpu-patches.md](cpu-patches.md) | Why the ZAP patches exist and how they were checked |
| [branch-prediction.md](branch-prediction.md) | BTB collision root cause, self-contained return reproducer and patch 0006 |
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
