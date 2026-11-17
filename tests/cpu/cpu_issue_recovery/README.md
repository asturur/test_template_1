# Step 4E: registered CPU redirect handoff

[Report and causal edges](../../../docs/cpu-issue-recovery.md) ·
[Hashes and qualification](../../../docs/evidence/cpu-issue-recovery-20261116.json)

Fixed final 4D is the control. Only `rtl/arm/zap_writeback.sv` changes. An already
saved redirect target enters the first PC stage when the old fetch drains,
instead of first reloading the PC source register. It handles ended and repeated
strobes, retains fault/interrupt/changed-target priority, and preserves mapped
FCSE successor behavior. No cache or issue-queue change, no new state bit.

- `bench.py [--control] --name NAME --case transpose4 --case matrix4`: matched
  original payloads, both delays, repeats, output/retirement oracles and full
  transpose stage traces. `--four-c` selects the prior 4C solely for causal replay.
- `redirect.py NAME`: 17 real-writeback ownership/priority cases, twice, including
  held fetches, ARM/Thumb, FCSE carry, changed targets, exceptions and reset.
- `run.py NAME`: unchanged measured real-CPU store guest. Add `--stress --safety`
  for the separate CPU hazard guest; its prologue is not a performance baseline.
- `diagnostics.py NAME --build build/sim/spmark-payload/ACCEPTED_BUILD`: hash-checked
  frozen RTL, fresh isolated host build, existing ARM/Thumb, FCSE, prefetch-abort
  and BTB-alias-return diagnostics at two response delays. No phone model/run.
- `analyze.py`: re-audit the saved accepted run identities, exact 65-load/34-clock
  causal accounting, architectural interval savings and all final gates.

Use unique names. Outputs stay under `build/sim/`; existing simulations and
checkpoints are never reused or changed. Installed simulator only; no network,
fit, CI, PLL change, production integration or deployment.
