# Step 4C: registered waiting-load probe scheduling

[Report](../../../docs/cpu-load-delivery.md) ·
[Evidence](../../../docs/evidence/cpu-load-delivery-20261116.json)

The fixed control is final 4B. Only the candidate cache adapter/access files
in `rtl/arm920/` are substituted after the verified 3C + 4A + 4B sources.
One new registered waiting bit gives an unlaunched P2 read priority until a
registered RAM result covers its line; then P1 lookahead resumes. Coverage is
only scheduling information, with no new architectural permission or ACK.

`bench.py [--control] --name NAME --case transpose4` runs original transpose in
both established wait profiles with independent outputs, repeats and wrong-output
controls. The observer classifies every read and traces the first registered
ALU address through permission, cache hit, physical RAM slot, completion and
dependent issue. `run.py NAME [--control] [--stress]` reuses the 4B real-CPU
store/older-exception tests. `pressure.py NAME` adds a primed stale-A result,
new A stores and competing P1 B, alongside active-probe/fault/reset/full-pressure
checks on the real cache with collision-poison RAM. Its delayed response seam
is never used for performance measurements.

`compat.py OUTPUT --fixture cache_probe` and `--fixture cache_admit_probe`
reuse the maintained probe/admission suites with explicit disabled store
credits. Reuse `../cpu_store_overlap/negative.py RUN_DIRECTORY` for a deliberately
wrong physical byte. `analyze.py` audits the saved final identities, exact
32-read attribution and preserved store loop before saving compact evidence.

Use unique names; output is under `build/sim/`. All Docker calls use the installed
simulator with `--pull=never --network none`. Production, PLL, CI and the phone
are outside these runners.
