# Isolated full-product DSP mapping experiment

Not selected in the production QIP and not part of b707ebd. Functional/cycle
qualification is not a physical area/timing result. See docs/dsp-mapping-audit.md.

From the repository root, `sh scratch/dsp-full-product-20261116/run.sh` generates
deterministic independent signed/unsigned/accumulation vectors and compares
this candidate against production. Existing local simulator only, no network.
The generated vectors and objects need not be tracked. `run-payload.py` freezes
an isolated candidate CPU snapshot for the maintained original-payload runner;
it changes neither production sources nor the phone. Use a fresh --name.

The production-name adapter is generated privately; the maintained candidate
keeps a distinct module name so the unit comparison can instantiate both.
CPU integration qualification lives in build/sim/dsp-full-product-cpu-20261116.
