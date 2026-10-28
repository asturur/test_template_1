# Project workspace rules

- Use the repository's `scratch/` folder as the persistent kitchen sink for reference checkouts, experiments, staging copies, reproducers, and working notes.
- Do not keep project work only in `/tmp` or another OS temporary directory. Create new scratch work under this repository instead.
- Keep maintained implementation files in their normal project directories. Standard generated build outputs may remain under `build/`.
- `scratch/` is ignored by default. Selected small experimental source files are tracked for continuity; reference checkouts and generated outputs stay local.

## Development continuity

- On resuming N-Gage development, read `docs/status.md` first and use `docs/README.md` to find detailed evidence before repeating research or simulations.
- Keep the relevant topic docs and `docs/status.md` current when code, assumptions, measured stopping points, or next steps change. Record failed approaches worth avoiding.
- Simulation requirements, commands, diagnostics, and output locations are in `docs/bringup.md` under Running and Diagnostics. Read the latest checkpoint in `docs/status.md` for the current experiment and its assumptions before selecting a run.
- Use the existing `jotego/simulator:arm64` image for simulation. Do not download Quartus. Keep logs and generated files small; old build objects can be rebuilt. Screen captures, when produced, live under `build/sim/screens/`.
- Keep observed results, unverified board assumptions, and unimplemented experiments explicitly separate; a matching software/HDL trace does not verify the shared peripheral model against a phone.
