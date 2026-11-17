# Collected exact5A hardware build

`verify.py` reads the downloaded existing run, checks all178 selected input
hashes, exact15 qualified payloads, unchanged physical78MHz PLL/effective QSF,
RBF size/SHA/commit, both routed frequency scenarios and collection protection.
It never submits a build, publishes a ref, deploys or runs a performance test.

[Build, timing, artifacts and audit](../../docs/cpu-frontend-delivery-fit.md).
The fit artifact is retained under build/fit/frontend-5a-20261117, with separate
RBF and Quartus-log subdirectories. Timing failure is distinct from successful
bitstream generation. Historical fit tags remain provenance; future builds
should select the existing default master branch.
