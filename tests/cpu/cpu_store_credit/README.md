# Step 4B: one spare registered store credit

[Measured report](../../../docs/cpu-store-credit.md) ·
[Compact evidence](../../../docs/evidence/cpu-store-credit-20261116.json)

`run.py NAME [--control]` reuses the byte-identical 4A ARM program and independent
oracles, with a pinned final 4A control. The candidate changes only the admission
bound in `rtl/arm920/cache_adapter.sv`, retaining the same two-bit counter.
Additional observers export count, allocation/return, actual issue/write and
full gap histograms. `--stress` selects a separate functional guest for actual
CPU fault/IRQ at active occupancy and a following same-address load.

`bench.py [--control] --name NAME --case transpose4` retains original payload
checks, profiles, repeats and wrong-output controls, while observing the first
payload stall and accounting every measured clock once. `pressure.py NAME`
uses the real adapter/cache with collision-poison RAM and test-only delayed
physical-response publication to exercise full count=3, a held fourth request,
simultaneous return/allocation, valid probe/load, fault, dirty writeback and
reset. This altered publication seam is never used for performance numbers.

Reuse `../cpu_store_overlap/negative.py RUN_DIRECTORY` for the deliberately
wrong physical byte. `analyze.py` checks the fixed inputs and saved final run
names before writing evidence. All build outputs stay under `build/sim/`;
Docker uses the installed simulator image without pulls or network access.
Nothing here integrates into production, invokes CI or touches the phone.
