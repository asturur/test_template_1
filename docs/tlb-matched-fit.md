# Matched 5L and banked-TLB physical fits

The qualified 5L control is promoted first, followed by the exact qualified
5L plus banked main-TLB candidate. Builds run serially on the same public
master workflow with seed 42, DDR debugger enabled, Quartus 17.0.2 and the
unchanged 78 MHz production PLL. Routed timing is also analyzed at 104 MHz.
Neither build authorizes hardware deployment.

The two remote names `asturur/NGage_MiSTer` (normal origin) and
`asturur/test_template_1` resolve to the same GitHub repository. Updating its
master therefore publishes to both names without duplicating a build.

Sources are recreated by `tools/tlb_matched_fit/prepare.py` from ccba54f,
then checked against all 60 qualified CPU/integration RTL/header hashes.
The upstream ZAP patch replay must match production byte for byte before
publication. The banked candidate changes exactly seven RTL files from 5L.
Fit manifests must contain the same 178 selected inputs, with only those
seven source hashes differing; constraints, PLL, production BRAM, toolchain,
seed and debugger configuration remain matched.

Build identities, complete reports, bitstreams, source manifests and comparison
are collected under `build/fit/tlb-matched-20261117/`. Final evidence and the
recommendation will be recorded here after both builds complete, including
negative timing results. Functional evidence remains in
[cpu-late-operand.md](cpu-late-operand.md) and [tlb-area.md](tlb-area.md).
