# N-Gage project documentation

**Resume with [status.md](status.md).** It records completed work, exact measured
stopping points, assumptions, missing hardware, next steps and when to rerun checks.
Checkpoint verified 2026-10-27 against the saved local simulation reports.

| Document | Purpose |
| --- | --- |
| [status.md](status.md) | Current development checkpoint and ordered resume work |
| [TODO.md](TODO.md) | Assumptions and shortcuts to replace, with evidence and validation |
| [display-bringup.md](display-bringup.md) | Firmware-driven LCD and startup display experiments |
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

ARM reference manuals are local PDFs in this folder. Reference checkouts and
supporting research are retained under project `scratch/`; generated traces and
result/provenance JSON are under `build/`.

When development advances, update the relevant topic document and `status.md`.
Record the exact firmware/profile, changed assumption, result path and next unknown.
Keep evidence, hypotheses and unimplemented ideas distinct. Preserve failed
approaches that would otherwise be tempting to retry; do not rerun expensive
checks just to reconstruct already documented results.
