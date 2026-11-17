# Step5C registered product / zero-addend delivery

One isolated `zap_shifter_multiply` state transition on qualified5B: S1 retains
its registered DSP product capture; zero addends skip S2's redundant sum/hold.
Nonzero accumulators retain the previous route. No additional state or DSP
arithmetic is introduced. [Report](../../../docs/cpu-product-bypass.md).

- `bench.py --control --name UNIQUE --case matrix4 --case transpose4` freezes
  exact5B; default selects the one-file candidate. It retains original guests,
  mathematical/Unicorn oracles, scored windows, repeats and wrong-output gates.
- `multiply.vh` is a read-only trace of every original SMULL owner, registered
  factor/product, low/high result, register writes and first consumer. It is
  unrelated to synthesis and never drives the DUT.
- `unit.py UNIQUE` checks2048 independent signed/unsigned/zero/random-addend
  products,4096 paired outputs/flags, random holds,16 held cancellations and
  15 stage/priority reset/clear cases against the fixed5A DSP source.
- `irq.py UNIQUE --build BUILD` asserts a real IRQ in S1 and rejects partial
  destination pairs, then checks signed/unsigned/accumulating/predicated code.
- `jpeg.py --name UNIQUE`, `run.py UNIQUE --safety`, and
  `diagnostics.py UNIQUE --build BUILD` reuse the existing original JPEG,
  ordered-memory/exception and ARM/Thumb/FCSE/fetch-fault fixtures.
- `analyze.py` audits named final runs, exact source/program/oracle identities,
  all1024 pairs and disjoint cycle accounting. Large logs may be losslessly
  compressed; source/executable/metadata and hashes remain underbuild/sim.

Use fresh output names. Build reuse is strict, including fixture hashes; a
changed read-only trace can require a new build even when unused by that guest.
No fit per microchange, deployment, phone command or game extraction is included.
