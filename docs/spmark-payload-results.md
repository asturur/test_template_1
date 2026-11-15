# SPMark payload performance results

Each result cell lists **I:D waits 0:0 / 2:9**, in that order. Cycle values
are medians of five measured samples after two warm-ups; lower is better.
The equal-weight throughput index uses the original `baseline` as100 for every
row; higher is better.
These are original-payload CPU/cache simulation results, separate from the
phone's official SPMark score. Keep workload membership and inputs fixed.

| Name | Matrix ×16 | Transpose ×32 | Triangle edges ×16 | Fill16: 36,608 pixels | Fill16: 1,023 pixels | Fill8: 2,051 bytes | Index | Evidence |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| baseline | 78,336 / 78,336 | 12,589 / 12,589 | 46,592 / 46,592 | 238,234 / 238,234 | 6,774 / 6,774 | 7,507 / 7,507 | 100.0 / 100.0 | [JSON](evidence/spmark-payload-baseline-20261114.json) |
| armv4t-profile | 78,336 / 78,336 | 12,589 / 12,589 | 46,592 / 46,592 | 238,223 / 238,223 | 6,763 / 6,763 | 7,507 / 7,507 | 100.0279 / 100.0279 | [JSON](evidence/spmark-payload-armv4t-profile-20261115.json) |
| owned-translation | 73,391 / 73,391 | 10,636 / 10,636 | 42,175 / 42,175 | 183,381 / 201,345 | 5,229 / 5,229 | 5,961 / 5,961 | 119.8124 / 117.9607 | [JSON](evidence/spmark-payload-owned-translation-20261115.json) |
| early-hit-response | 71,119 / 71,119 | 10,220 / 10,220 | 41,391 / 41,391 | 183,380 / 201,344 | 5,228 / 5,228 | 5,960 / 5,960 | 121.6327 / 119.7529 | [JSON](evidence/spmark-payload-early-hit-response-20261115.json) |
| permission-reuse | 71,119 / 71,119 | 9,164 / 9,164 | 40,991 / 40,991 | 183,380 / 201,344 | 5,228 / 5,228 | 5,960 / 5,960 | 124.0646 / 122.1471 | [JSON](evidence/spmark-payload-permission-reuse-20261115.json) |
| store-absence | 71,119 / 71,119 | 9,164 / 9,164 | 40,991 / 40,991 | 135,329 / 201,332 | 5,228 / 5,228 | 5,960 / 5,960 | 130.5092 / 122.1483 | [JSON](evidence/spmark-payload-store-absence-20261115.json) |
| resident-read | 66,253 / 66,253 | 8,522 / 8,522 | 40,317 / 40,317 | 135,327 / 201,330 | 5,226 / 5,226 | 5,958 / 5,958 | 134.0546 / 125.4664 | [JSON](evidence/spmark-payload-resident-read-20261115.json) |
| resident-store | 66,031 / 66,031 | 7,786 / 7,786 | 39,005 / 39,005 | 135,327 / 201,330 | 4,334 / 4,334 | 5,058 / 5,058 | 145.1635 / 135.8637 | [JSON](evidence/spmark-payload-resident-store-20261115.json) |

Baseline measured2026-11-14, source HEAD555a510; exact frozen RTL, inputs,
raw windows and qualification are preserved in the evidence.
[Runner and measurement details](spmark-payload-simulation.md).

`armv4t-profile` measured2026-11-15 on patch0060's frozen working RTL. All12
case/profile rows,84windows, exact repeats and six wrong-output controls pass.
The index improves0.0279%; full-frame16-bit fill saves11cycles (0.0046%),
1023-pixel16-bit tail saves11cycles (0.1624%); the other four kernels are
unchanged. Tail scored samples are6785/6763/6763/6763/6763 at0:0 and
6787/6763/6763/6763/6763 at2:9, so the table uses the declared median.
This is effectively cycle-neutral; FPGA area/timing are still unmeasured.
[Pruning scope and CPU qualification](cpu-armv4t-profile.md).

`owned-translation` measured2026-11-15 on patch0061. All12case/profile rows,
84windows, exact repeats and six wrong-output controls pass. Table index is
119.8124 /117.9607 against original baseline. Against the immediate ARMv4T
predecessor the index is119.7790 /117.9279:19.78% /17.93% more throughput.
Full-frame fill now exposes backing-wait cost at2:9; its zero-wait result is
183381cycles versus201345 with the delayed backend. Other warmed medians remain
identical between profiles. No FPGA timing/area or board speedup is inferred.
[Design, tests and next response-stage change](cache-load-optimization-plan.md).

`early-hit-response` measured2026-11-15. All12rows/84windows, exact repeats and
six negative controls pass. The response-copy reduction adds1.5193% throughput
over `owned-translation`. Combined with the handoff change it gives21.5989% /
19.7196% more throughput than `armv4t-profile`; the table keeps the original
baseline denominator for all rows. Matching resident LDR holds5clocks, down
from original9. No extra BRAM; one captured response-eligibility bit. FPGA
area/timing and board boot remain unverified.
[Qualification](evidence/cache-early-hit-response-20261115.json).

`permission-reuse` measured 2026-11-15. All 12 case/profile groups and 84
windows pass, with two identical repeats and all six wrong-output controls.
Only the TLB controller differs from the prior accepted CPU source closure.
Transpose improves from 10,220 to 9,164 cycles (11.52% more throughput),
triangle from 41,391 to 40,991 (0.98%); matrix and all fills are unchanged.
The equal-weight suite adds 1.9993% throughput over early-hit-response in both
profiles. Total measurement time is 521.052 s. This is kernel throughput, not
phone SPMark points or board FPS. The independently qualified transpose observer
confirms hot stores hold 7 rather than 10 clocks.
[Implementation and 86 CPU regressions](evidence/permission-token-reuse-20261115.json),
[plan and future pipeline contract](cache-load-optimization-plan.md).

`store-absence` measured 2026-11-15. All 12 groups/84 windows, two exact
repeats and six wrong-output controls pass. Full-frame fill improves from
183,380 to 135,329 cycles at 0:0 (+35.51% throughput), and 201,344 to 201,332
at 2:9 (+0.00596%). The other five kernels are unchanged. Suite index gains
5.1946% / 0.000993% over permission-reuse, using that predecessor only for the
step delta; the table retains original baseline100. The delayed backing-write
profile limits full-frame throughput after lookup work is reduced. Measurement
wall time is 521.394 s.
[Implementation, 30 declared bits and qualification](cache-store-absence.md).

Full `store-absence` reprofile also passes all six cases/both memory profiles,
84 windows per repeat and two identical repetitions, with every original raw
counter unchanged. Nine profile-parser controls pass. No new performance row
is added because this pass changes no CPU RTL or measured benchmark cycles.
[Current attribution and chosen resident-way priority](spmark-payload-profile.md),
[profile evidence](evidence/spmark-payload-cycle-profile-store-absence-20261115.json).

`resident-read` is the declared joint two-result directory/indexed-read step:
+2.7165% throughput over E0. `resident-store` independently adds indexed WB
stores: +8.2869% over E1, +11.2285% cumulative over E0. Both full suites pass
all12groups/84windows, exact repeats and six wrong-output controls. E1 elapsed
503.308s; E2 elapsed513.391s. Table indices retain the original baseline100.
[Implementation, tests and CPU-owner timings](cache-resident-way.md).
