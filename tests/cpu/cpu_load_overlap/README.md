# Step 4D: bounded independent ARM load-pair overlap

[Measured report](../../../docs/cpu-load-overlap.md) ·
[Hashes and owner traces](../../../docs/evidence/cpu-load-overlap-20261116.json)

Fixed final 4C is the control. The explicit `rtl/` overlay carries one original
unconditional ARM word-LDR class bit through existing owned stages, then permits
a certified younger private RAM read on an older ordinary hit's reply edge.
The existing held P1 owns its address. Demand delivery stays in order and retains
current permission/translation, full identity, collision and revoke checks.
No second demand queue, speculative external request or copied line is added.

- `bench.py [--control] --name UNIQUE --case transpose4`: original guest,
  both wait profiles, two repeats, independent oracles, wrong-output checks,
  all-pair coverage and exact completion/register/dependent-store events.
- `loop.py UNIQUE --build build/sim/spmark-payload/ACCEPTED_BUILD`: synthetic
  64 independent LDR pairs, dependent checksum, Unicorn, three warm-ups/five
  checked samples, both profiles, repeats and wrong-checksum control. Source
  and executable hashes must match the accepted build.
- `run.py UNIQUE [--control] [--stress] [--safety]`: unchanged real-CPU store
  performance guest, or the separate active-credit exception/load-class guest.
- `pressure.py UNIQUE`: actual cache with collision-poison RAM, new pair-owner,
  permission/translation, mismatch/alias/reset tests and previous store-pressure
  cases. The delayed store-response seam is never used for performance.
- `compat.py OUTPUT --fixture cache_probe` (or `cache_admit_probe`): existing
  broad probe regression, with the new pair input explicitly disabled.
- `analyze.py`: audit the saved accepted runs and write compact durable evidence.

Use unique output names. Installed simulator only, no network/pull. Source
freezing starts at 9c948da8 and verifies the 3C/4A/4B/4C layer hashes. Production,
PLL, running simulations, hardware, CI and fits are outside this experiment.
