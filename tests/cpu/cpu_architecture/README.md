# Combined CPU baseline and state-tagged fetch

Run from the repository root using the existing simulator image. Inputs
and prerequisites are the same as for the [third-mapping replays](../tlb_three_mapping/README.md).
The stock donor builder also needs the archived donor manifest, the local
ngage2 Git objects at the listed revision and the archived SPMark/JPEG
receipts. All generated source, code and logs go under
`build/sim/tlb-three-mapping/` or `build/sim/tlb-area/`. The active
checkouts stay on their current revisions.

Build the combined reference and the tagged variant with distinct names.
Use `--scan` for the full scan's enlarged memory aperture. A reproduction
of the archived receipt uses these build and output names. Choose fresh
names for independent runs and update the inputs at the top of
`architecture_ab`, `donor_compare` and `main` in `collect.py` to
audit them.

```sh
python3 tests/cpu/cpu_architecture/build.py arch-ref-18-v2
python3 tests/cpu/cpu_architecture/build.py arch-ref-scan-18-v2 --scan
python3 tests/cpu/cpu_architecture/build.py arch-tagged-18-v2 --prototype
python3 tests/cpu/cpu_architecture/build.py arch-tagged-scan-18-v2 --prototype --scan

python3 tests/cpu/tlb_three_mapping/run.py --build arch-ref-18-v2 --name arch-reference-work-18
python3 tests/cpu/tlb_three_mapping/run.py --build arch-tagged-18-v2 --name arch-tagged-work-18-v2
python3 tests/cpu/tlb_three_mapping/run.py --build arch-ref-scan-18-v2 --name arch-reference-scan-work-18 --suite scan --workers 2 --parallel-repeats
python3 tests/cpu/tlb_three_mapping/run.py --build arch-tagged-scan-18-v2 --name arch-tagged-scan-work-18-v2 --suite scan --workers 2 --parallel-repeats

python3 tests/cpu/cpu_architecture/donor.py arch-donor-game-18-v3
python3 tests/cpu/cpu_architecture/donor.py arch-donor-scan-18-v3 --scan
python3 tests/cpu/cpu_architecture/donor.py arch-donor-jpeg-extras-18 --jpeg --case diffuse_m10_16x8_jpeg --case diffuse_m10_8x8_random --case diffuse_m8_8x8_random
```

The collector uses the archived six donor SPMark kernels and original 8×8
JPEG from the [5C comparison](../../../docs/ngage2-vs-5c-benchmark.md).
The fresh donor JPEG run supplies the three previously unscored JPEG cases.
`ARCH_WINDOW` partitions the mainline scored clocks. Its external-service
and redirect counters can overlap those bins. The bounded `ARCH_EDGE`
and `DONOR_EDGE` journals number actual core edges after the first scored
begin marker. Donor `alu` describes execute accept because the probe
starts at A, while `ARCH_EDGE` distinguishes operand dequeue from ALU.
On both designs the `*_DATA` journal distinguishes request and ACK.
The ARM BX observer alias and the donor Thumb BL suffix count are resolved
during comparison. The logs retain the raw observations.

Run the interworking controls, the existing precise abort test and the
CPU checks before collecting the receipts.

```sh
python3 tests/cpu/cpu_architecture/interwork.py arch-interwork-control-18 --build arch-ref-18-v2
python3 tests/cpu/cpu_architecture/interwork.py arch-interwork-candidate-18 --build arch-tagged-18-v2 --prototype
python3 tests/cpu/thumb_early_load/directed.py arch-tagged-precise-18 --build arch-tagged-18-v2 --thumb
python3 tests/cpu/tlb_area/diagnostics.py arch-tagged-cpu-18 --build build/sim/tlb-three-mapping/arch-tagged-18-v2
python3 tests/cpu/tlb_area/core_checks.py --name arch-tagged-core-18 --build build/sim/tlb-three-mapping/arch-tagged-18-v2
python3 tests/cpu/cpu_product_bypass/irq.py arch-tagged-irq-18-v2 --build build/sim/tlb-three-mapping/arch-tagged-18-v2
python3 tests/cpu/cpu_architecture/collect.py
```

[Workload results and attribution](../../../docs/cpu-state-tagged-fetch.md)
