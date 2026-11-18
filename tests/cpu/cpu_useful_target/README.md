# Step 5H — passive useful-target delivery research

No RTL overlay. `setup.py` freezes accepted5F `8e70b1e`; the maintained5F
store observer supplies the ARM harness. `timeline.vh` extends5E with the FIFO
head/array, assembly/predecode readiness and permitted code response.

Run serially, with unique names:

```sh
python3 tests/cpu/cpu_useful_target/bench.py --name NEW_ARM \
  --case matrix4 --case fill8_tail --profile 0:0 --jobs 1
python3 tests/cpu/cpu_useful_target/jpeg.py --name NEW_JPEG
```

`analyze.py` audits the named final runs `useful-target-5f-arm-02` and
`useful-target-5f-jpeg-01`, exact60RTL hashes, repeated journals, original PCs,
seven timing windows and bad-output rejection, then writes
`docs/evidence/cpu-useful-target-20261117.json`. Update its explicit run list
when auditing a fresh run. Compressed journals are accepted.

The **one** modeled mechanism consumes an existing permitted F packet into the
existing empty FIFO head register, once, even while its successor demand is
held. A single consumed bit avoids duplication. All modeled paths retain
registered decode/operand edges. The primary `plausibly_exposed_clocks` is the
union of hold-aware saved intervals, with source retirement as a conservative
operand certificate. `free_issue_slot_clocks_without_source_retirement_certificate`
is a separate, unqualified screen; `straight_path_*` is a diagnostic subset,
not an additional design or additive budget. No count predicts a new complete
execution; later readiness, memory and predictor behavior stay frozen.

`source_complete_encoding_in_F` and `first_matching_target_value_available`
separate source bytes from existing computed/predicted targets. A correct
prediction is identified against the checked stream, not asserted authoritative.
`later_execution_correction` records the actual ALU correction of a wrong hint.
The dynamic target issue PC is checked against the *next* retirement occurrence.
Per-transfer first-blocker intervals and union counts avoid overlap inflation.

`storage.py` retires only this step's three named completed build trees,
generated binaries/hex inputs and frozen sources after recording executable
hashes; it losslessly compresses all logs. Observer snapshots, manifests,
oracles, guest assembly, results and storage ledgers remain. `arm-01` is excluded:
its obsolete5E late-store assertion rejected5F; the unchanged CPU passes with
the maintained5F observer in `arm-02`.

The main JSON receipt contains summary and witness dictionaries. Complete
per-occurrence records are in the linked deterministic `.events.json.gz`
receipt, with compressed and raw SHA256 values. Source encoding availability,
existing target signals and authoritative correction are separate columns.

[Report and limitations](../../../docs/cpu-useful-target.md).
