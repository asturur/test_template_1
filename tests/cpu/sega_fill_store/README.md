# Sega Rally indexed halfword-store credit

This is a focused comparison of the original 512-pixel fill on the retained
state-tagged core, the same core with the isolated STRH admission extension,
and the pinned stock ngage2 donor. Run from the project root with the existing
offline simulator image, ARM GNU binutils, Unicorn, and the private checked
game fixtures documented in the [shared runner](../tlb_three_mapping/README.md).

```sh
python3 tests/cpu/sega_fill_store/experiment.py build fill-store-tagged-control-18
python3 tests/cpu/sega_fill_store/experiment.py replay fill-store-tagged-work-18 --build fill-store-tagged-control-18
python3 tests/cpu/sega_fill_store/experiment.py donor fill-store-stock-donor-18
python3 tests/cpu/sega_fill_store/experiment.py build fill-store-strh-18-v2 --candidate
python3 tests/cpu/sega_fill_store/experiment.py replay fill-store-strh-work-18-v2 --build fill-store-strh-18-v2
python3 tests/cpu/sega_fill_store/schedule.py --out docs/evidence/cpu-sega-fill-store-20261118.json.gz --traces docs/evidence/cpu-sega-fill-store-20261118.traces.json.gz
```

Output lives under `build/sim/tlb-three-mapping/`. Use fresh names for new
runs and update `CASES` in `schedule.py` to collect them. The audit accepts
plain or compressed run logs. Compare actual operand dequeue and ALU
advance on mainline, A-stage advance on the donor and the independent cache
RAM byte-enable edge on both. Store acknowledgement can precede that edge
if the validated line and request already own a resident write credit.

[Results and diagnosis](../../../docs/cpu-sega-fill-store.md)

## Trace instruction supply

Repeat the same frozen control and pinned donor with the passive frontend
probes. The analysis checks the exact prior scores, guest effects and
execute intervals, then attributes the fetch delivery gaps.

```sh
python3 tests/cpu/sega_fill_store/experiment.py build fill-front-tagged-18 --frontend
python3 tests/cpu/sega_fill_store/experiment.py replay fill-front-tagged-work-18 --build fill-front-tagged-18
python3 tests/cpu/sega_fill_store/experiment.py donor fill-front-donor-18 --frontend
python3 tests/cpu/sega_fill_store/fetch_schedule.py
```

[Fetch attribution](../../../docs/cpu-sega-fill-fetch.md)

## Measure the instruction-line overlays

```sh
python3 tests/cpu/sega_fill_store/experiment.py build fill-stream-18 --retain-stream --frontend
python3 tests/cpu/sega_fill_store/experiment.py replay fill-stream-work-18 --build fill-stream-18
python3 tests/cpu/sega_fill_store/experiment.py build fill-stream-probe-18 --retain-stream --frontend
python3 tests/cpu/sega_fill_store/experiment.py replay fill-stream-probe-work-18 --build fill-stream-probe-18
python3 tests/cpu/sega_fill_store/experiment.py build fill-stream-path-18 --redirect-lookahead --frontend
python3 tests/cpu/sega_fill_store/experiment.py replay fill-stream-path-work-18 --build fill-stream-path-18
python3 tests/cpu/sega_fill_store/stream_safety.py fill-stream-unit-18 --build fill-stream-18
python3 tests/cpu/sega_fill_store/stream_safety.py fill-stream-unit-control-18 --build fill-front-tagged-18 --negative
```

The probe rebuild captures the stream slot tags. Rebuild the tagged control
using the instruction-supply commands above before the negative test.
The broad scores and CPU checks use the existing runners.

```sh
python3 tests/cpu/tlb_three_mapping/run.py --build fill-stream-18 --name fill-stream-matrix-18 --workers 3
python3 tests/cpu/tlb_three_mapping/run.py --build fill-stream-path-18 --name fill-stream-path-matrix-18 --workers 3
python3 tests/cpu/sega_fill_store/experiment.py build fill-stream-scan-18 --retain-stream --scan
python3 tests/cpu/sega_fill_store/experiment.py build fill-stream-path-scan-18 --redirect-lookahead --scan
python3 tests/cpu/tlb_three_mapping/run.py --build fill-stream-scan-18 --name fill-stream-scan-work-18 --suite scan --workers 2 --parallel-repeats
python3 tests/cpu/tlb_three_mapping/run.py --build fill-stream-path-scan-18 --name fill-stream-path-scan-work-18 --suite scan --workers 2 --parallel-repeats
python3 tests/cpu/tlb_area/core_checks.py --name fill-stream-path-core-18 --build build/sim/tlb-three-mapping/fill-stream-path-18
python3 tests/cpu/tlb_area/diagnostics.py fill-stream-path-diag-18 --build build/sim/tlb-three-mapping/fill-stream-path-18
python3 tests/cpu/cpu_architecture/interwork.py fill-stream-interwork-18 --build fill-stream-path-18 --prototype
python3 tests/cpu/sega_fill_store/stream_report.py
```

The report checks both versions against the archived tagged-fetch runs and
requires matching guest inputs, output oracles and architectural effects.

[Instruction-line results](../../../docs/cpu-icache-stream.md)

## Test STRH credit on the refined frontend

The control for this interaction is the archived 4,805-clock
`fill-stream-path-work-18` build and score, plus its full matrix and
scan. The build verifies the frozen refined source before applying the
existing store extension.

```sh
python3 tests/cpu/sega_fill_store/experiment.py build fill-store-icache-18 --store-on-lookahead --frontend
python3 tests/cpu/sega_fill_store/experiment.py replay fill-store-icache-work-18 --build fill-store-icache-18
python3 tests/cpu/tlb_three_mapping/run.py --build fill-store-icache-18 --name fill-store-icache-matrix-18 --workers 3
python3 tests/cpu/sega_fill_store/experiment.py build fill-store-icache-scan-18 --store-on-lookahead --scan
python3 tests/cpu/tlb_three_mapping/run.py --build fill-store-icache-scan-18 --name fill-store-icache-scan-work-18 --suite scan --workers 2 --parallel-repeats
python3 tests/cpu/sega_fill_store/store_safety.py fill-store-icache-safety-control-18-v2
python3 tests/cpu/sega_fill_store/store_safety.py fill-store-icache-safety-18-v2 --candidate
python3 tests/cpu/tlb_area/core_checks.py --name fill-store-icache-core-18 --build build/sim/tlb-three-mapping/fill-store-icache-18
python3 tests/cpu/tlb_area/diagnostics.py fill-store-icache-diag-18 --build build/sim/tlb-three-mapping/fill-store-icache-18
python3 tests/cpu/sega_fill_store/interaction_report.py
```

[Matched STRH interaction results](../../../docs/cpu-icache-strh.md)
