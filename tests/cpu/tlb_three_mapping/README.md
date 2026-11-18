# Third checked D-side mapping experiment

The control is published 5L at commit `0c380ab9bae92916d297b72d6a303d251f1d49d9`.
The candidate applies [the two-file patch](third-mapping.patch) to a frozen
copy of that commit. Both retain the original 64-entry architectural tables.
The source freezer verifies all 60 RTL and header hashes against the
qualified 5L record and audits the two-file delta. The simulator is the
installed `jotego/simulator:arm64` image with networking disabled.

Run these from the project root. Use fresh names under
`build/sim/tlb-three-mapping/`. The offline runner needs ARM GNU binutils,
Python with Unicorn/Pillow, the established private originals and the
hash-qualified local NEM-4 core ROM.

```sh
python3 tests/cpu/tlb_three_mapping/build.py --name control
python3 tests/cpu/tlb_three_mapping/build.py --name candidate --candidate
python3 tests/cpu/tlb_three_mapping/run.py --build control --name control-work --workers 3
python3 tests/cpu/tlb_three_mapping/run.py --build candidate --name candidate-work --workers 3
python3 tests/cpu/tlb_three_mapping/build.py --name scan-control --full-scan
python3 tests/cpu/tlb_three_mapping/build.py --name scan-candidate --full-scan --candidate
python3 tests/cpu/tlb_three_mapping/run.py --build scan-control --name control-scan --suite scan --workers 2
python3 tests/cpu/tlb_three_mapping/run.py --build scan-candidate --name candidate-scan --suite scan --workers 2
python3 tests/cpu/tlb_three_mapping/units.py --name units --build control --build candidate
```

The two full-frame cases take substantially longer than the bounded loops.
`--workers` runs independent case/profile pairs. For the full scan,
`--parallel-repeats` runs both positive trials and the failing control per
profile concurrently. The defaults are serial, with a limit of five scored
windows, two initial warmups and two identical positive trials. Use the
original SPMark, JPEG and Monkey Ball fixture locations specified by their
maintained drivers. The Sega and Asphalt inputs live in the Git-ignored
`tests/cpu/sega_rally/local/` and `tests/cpu/asphalt_urban_gt/local/`.
Generated wrappers and derived binaries belong under the run directory.

The matched CPU diagnostics and their FIQ/SWP/ordering peer accept a bench's
frozen source directory through `--build build/sim/tlb-three-mapping/NAME`.
Run each of these for the two source variants with distinct output names.

```sh
python3 tests/cpu/tlb_area/diagnostics.py control-diagnostic --build build/sim/tlb-three-mapping/control
python3 tests/cpu/tlb_area/core_checks.py --name control-core --build build/sim/tlb-three-mapping/control
```

`report.py --help` lists the inputs needed to reproduce the audited table
and compressed evidence. Each comparison checks executable and source
provenance, matching guest payloads, work and timing boundaries, memory
effects and ordinary-retirement fingerprints. The archived first scored
Monkey Ball trace includes all 4,608 acknowledged demand addresses in order.
`MAP_WINDOW` and `MAP_TOTAL` separate timed and whole-run translation events.

[Results and workload details](../../../docs/cpu-third-data-mapping.md)
