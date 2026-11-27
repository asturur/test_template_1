# Project workspace rules

- Treat `scratch/` as disposable: its contents must be safe to trash. Use it for temporary reference checkouts, experiments, staging copies, reproducers, and working notes.
- Do not keep project work only in `/tmp` or another OS temporary directory. Create new scratch work under this repository instead.
- Keep reusable software and helpers in `tools/` or their normal implementation directories, permanent tests in `tests/`, durable runtime inputs in `runtime/`, and useful findings in `docs/`. Promote useful experiments before relying on them; do not leave their only copy in `scratch/`.
- Keep reproducible generated outputs and downloaded tool caches under `build/`. `scratch/` is ignored. Keep reusable software and tests in their maintained directories.

## Single working branch and checkout

- The active development checkout is `/Users/andreabogazzi/develop/NGage_MiSTer`,
  on the existing default `master` branch.
- The legacy chat path `/Users/andreabogazzi/.codex/worktrees/ngage2-integration/NGage_MiSTer`
  is an empty compatibility directory for this chat sandbox. Always set the
  working directory to the active checkout above; do not develop in the legacy
  path or turn it into another worktree/copy. A symlink there breaks the sandbox.
- Use `master` for future builds. Do not create or switch to another branch, create worktrees, or continue development
  from a detached HEAD unless the user explicitly changes this instruction.
- Reconcile accepted work onto `master`. Keep it as the sole local and remote branch; preserve historical fit tags as build provenance. Preserve other threads'
  running simulations and permanent checkpoints.

## Development continuity

- On resuming N-Gage development, read `docs/status.md` first and use `docs/README.md` to find detailed evidence before repeating research or simulations.
- For MiSTer input, reloads, screenshots and DDR capture, use `/Users/andreabogazzi/.codex/skills/mister-control/SKILL.md` and its helper/cached references; avoid repeating API/key discovery.
- For ngage1 reboots, follow the mister-control reboot reference and `tools/mister/ngage_boot.py`: timed startup, safety margin and the user-authorized two time/date confirmations. Avoid repeated conversational setup checks.
- Do not create SD-card backups of files reproducible from local inputs. Keep rebuild sources/manifests in the project; replace generated card files directly after verification.
- Keep the relevant topic docs and `docs/status.md` current when code, assumptions, measured stopping points, or next steps change. Record failed approaches worth avoiding.
- Simulation requirements, commands, diagnostics, and output locations are in `docs/bringup.md` under Running and Diagnostics. Read the latest checkpoint in `docs/status.md` for the current experiment and its assumptions before selecting a run.
- Use the existing `jotego/simulator:arm64` image for simulation. Do not download Quartus. Keep logs and generated files small; old build objects can be rebuilt. Screen captures, when produced, live under `build/sim/screens/`.
- Keep observed results, unverified board assumptions, and unimplemented experiments explicitly separate; a matching software/HDL trace does not verify the shared peripheral model against a phone.
- Preserve every billion-cycle checkpoint permanently for long simulations; rolling retention must never delete those checkpoints. Keep the CPU and host files together and record any missing milestones.

## Chip-oriented hardware organization

- Give each relevant physical NEM-4 chip at least one distinct HDL module, organized using `docs/chip-inventory.md`. The phone board connects chip modules; a chip module may contain smaller functional blocks. Explicitly mark unimplemented components rather than inventing behavior.
- Name and model inter-chip signals after the schematics when known. Mark transaction-level shortcuts, guessed directions, timings and missing pin behavior explicitly; do not invent physical behavior or silently connect experimental protocol stubs.
- Keep new HDL Verilog-2001 compatible. Preserve existing behavior and run relevant chip, board and CPU integration tests when changing boundaries.

## RTL readability

- Keep maintained phone RTL and `Template.sv` readable according to `docs/rtl-style.md`: explicit ports, aligned connections, separated statements and four-space indentation. The reproducible formatter is `tools/format_phone_rtl.py` with `.rules.verible_format`. Preserve imported-source styles.
