# Step 5L: late unshifted arithmetic source

Isolated original overlay on promoted master
`ccba54f60a2c6f4741e74428b3306a19717ea58d`. Production is never edited.
`setup.py` reproducibly overlays only Issue and Core. It accepts AL ADD/CMP
with exactly one missing unshifted source owned by the starting P1 word load;
registered completion fills the existing execute-operand register. Other
sources and intervening/predicated writers retain scoreboard protection.

Run serially, with new names, using the installed offline image:

```sh
python3 tests/cpu/cpu_late_operand/bench.py --name NEW_NAME
python3 tests/cpu/cpu_late_operand/safety.py --build build/sim/cpu-late-operand/NEW_NAME
python3 tests/cpu/cpu_late_operand/diagnostics.py NEW_DIAGNOSTICS --build build/sim/cpu-late-operand/NEW_NAME
python3 tests/cpu/cpu_late_operand/qualify.py --jpeg --name NEW_JPEG
python3 tests/cpu/cpu_late_operand/response_controls.py --name NEW_RESPONSE --build build/sim/cpu-late-operand/NEW_NAME
```

The bounded response-control runner builds a testbench against the same
frozen CPU, withholds a cold external response for 128 clocks, then separately
injects one CPU-boundary retry and checks exact dependent replay. It does not
modify production/cache behavior. The safety guest runs twice at 0:0, 2:9 and
0:97 and checks accepted-but-killed arithmetic, saved flags and long cold holds.

`bench.py` composes the maintained 5K/5J harness and original 5I span fixture.
Both 512-pixel patterns, guards, mathematical/Unicorn oracle, original retirement
sequence, mutation/byte counts, five scored windows, repeats and negative controls
are preserved. Original game/ROM bytes stay private and ignored. `observe.vh`
adds acceptance, completion-edge observation and registered ALU-result events.
Fault-edge completion observations are not successful pickups; the safety audit
requires the killed operation never produce a valid ALU result.

Qualified matrix: `build/sim/cpu-late-operand/step5l-03`; diagnostics:
`step5l-diagnostics-01`; response controls: `step5l-response-01`; JPEG:
`build/sim/jpeg-payload/step5l-jpeg-01`. Initial `step5l-01` corrected a generated
port-selection error; `step5l-02` has identical functional RTL but an overly
strict assertion on fault completion. Neither is the final safety qualification.

`python3 tests/cpu/cpu_late_operand/analyze.py` audits the final fixed names
against saved `build/sim/cpu-load-lookup/step5k-lookup-02` control measurements.
It verifies all 60 promoted RTL/header hashes, source changes, exact original
program/oracle identity, full retirement order, every targeted dynamic issue,
pickup/execute/retire/next-issue schedules, response controls and safety receipts.
It writes durable public-safe evidence under `docs/evidence/`. Completed compiler
trees/derived private inputs are disposable; compressed logs and manifests remain.

[Measured decision and pipeline contract](../../../docs/cpu-late-operand.md).

The later exact six-original-kernel qualification is `step5l-six-01` under
`build/sim/spmark-payload/`. Replay with
`python3 tests/cpu/cpu_late_operand/qualify.py --name NEW_SIX --baseline build/sim/spmark-payload/combined-5jk-release-01/result.json`.
`python3 tests/cpu/cpu_late_operand/six_analyze.py` preserves the separate broad
receipt. Triangle improves23,568→23,520; the other five canonical cases are
unchanged at both profiles. This evidence preceded the rejected5M experiment.
