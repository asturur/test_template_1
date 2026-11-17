# Step4F: early store address with late owned data

[Measured report and edge ledger](../../../docs/cpu-store-late.md) ·
[Hashes and qualification](../../../docs/evidence/cpu-store-late-20261116.json)

Exact corrected4E is the control. Five isolated CPU files carry a pending-data
bit through existing store owners. Eligibility requires an original unconditional
ARM immediate word STR and its directly preceding original word LDR, matched
by PC and physical data register. Address/shift hazards remain unchanged.
Private address work can advance; no store demand occurs before matching older
success and the store's own checks. Aligned P2 data or exact formatted B commit
refreshes the existing held payload. No cache or general queue change.

- `bench.py [--control] --name NAME --case transpose4 --case matrix4`: original
  fixed work, both delays, oracles/repeats/negative controls, all192 owned early
  stores and384 actual transpose writes. Warm matrix has no eligible allocation.
- `run.py NAME [--control]`: unchanged64-store performance guest and physical
  data/dirty/order oracle. Add `--stress --safety --arg +i_wait=2 --arg +d_wait=9`
  for the separate long-stall, formatting, dependency, fault/permission/MMIO guest.
- `diagnostics.py NAME --build build/sim/spmark-payload/ACCEPTED_BUILD`: frozen
  candidate, isolated host build, existing ARM/Thumb/FCSE/prefetch/alias guards.
- `analyze.py`: audit accepted identities, edge/counter accounting, physical
  writes, focused event repeats and original outputs; save durable evidence.
- `../cpu_store_overlap/negative.py RUN`: deliberately wrong physical-byte check.

Use unique names and the installed simulator without network/pull. Generated
outputs stay under `build/sim/`. Physical timing, CI, production integration,
PLL, phone and existing runs/checkpoints are outside this experiment.
