# Step5M: registered actual-demand permission

**Rejected on measured cycle costs; keep the separately qualified5L overlay.**
This directory retains the one experiment, its exact routed-path motivation,
context-negative fixture and reproducible drivers. Production is never edited.
`setup.py` first applies the exact5L generator, then overlays Core, CP15,
D-cache and Top. Cache/adapter/Issue are unchanged from5L. The165added source
state bits register the actual request's permission/physical/fault fields and
a CP15 context-change event. No live wide context comparison qualifies token
consumption. Retained translation/resync is cleared on token revocation.

Before this experiment, all six original SPMark workloads passed on exact5L;
see `../cpu_late_operand/six_analyze.py` and its separate evidence.

Use fresh names and run **serially** with the installed offline simulator:

```sh
python3 tests/cpu/cpu_load_admission/bench.py --name NEW_MATRIX
python3 tests/cpu/cpu_load_admission/context.py --build build/sim/cpu-load-admission/NEW_MATRIX --name NEW_CONTEXT
python3 tests/cpu/cpu_load_admission/safety.py --build build/sim/cpu-load-admission/NEW_MATRIX
python3 tests/cpu/cpu_load_admission/diagnostics.py NEW_DIAGNOSTICS --build build/sim/cpu-load-admission/NEW_MATRIX
python3 tests/cpu/cpu_load_admission/response_controls.py --name NEW_RESPONSE --build build/sim/cpu-load-admission/NEW_MATRIX
```

The final matrix is `step5m-04`; context fixture `step5m-context-03`;
focused diagnostics `step5m-diagnostics-01`; response controls `step5m-response-01`.
Safety is inside the final matrix directory. Fixed-name
`python3 tests/cpu/cpu_load_admission/analyze.py` audits these against the saved
exact5L `build/sim/cpu-late-operand/step5l-03` receipt/logs and writes compact
machine evidence. It audits matching original programs/oracles/retirement
streams, scored windows, steady useful starts, exclusive wait accounting,
permission source cut, frozen sources, response controls and context negatives.

The context fixture drives the actual candidate D-cache/TLB/cache. A remap
performs both cache and TLB maintenance because the ARM920 cache has virtual
tags. It also checks permission denial causes no data read, wrong-address token
rejection, killed admission and TLB mutation. The revoke input models the
registered event produced alongside CP15 exported context. The actual CPU
MMU/FCSE diagnostics exercise the connected CP15 path separately.

`path_trace.py` extracts the original routed5K13.073ns path from the already
saved fit report; it performs no Quartus work. The original completion was
already registered. Physical retiming placed the reported endpoint under
`late_p1_ready`; do not reinterpret that as live RTL ACK→issue feedback.

History: `step5m-01` had an instance-generation syntax error; `step5m-02`
completed normal work but the first context test exposed missing retained-
translation cancellation. `step5m-03` was interrupted before simulation after
an edit failed to apply; its compiler is stopped. `step5m-04` contains the fix.
The second context fixture expected a remap without required virtual-cache
maintenance; only the fixture was corrected for `step5m-context-03`.
These failed/interrupted receipts are not qualified results or extra mechanisms.

Do not reuse5L safety as5M safety: the CPU inputs changed. Only unchanged
cache/adapter collision-pressure evidence is reused, after exact hash checks.
No5M JPEG/fullsix campaign or new fit followed its material performance failure.
Only own completed compiler/frozen-input/private-derived trees are disposable;
compressed journals, manifests, synthetic fixtures and public-safe evidence stay.

[Measured report and recommendation](../../../docs/cpu-load-admission.md).
