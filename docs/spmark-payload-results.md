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
| two-mapping | 60,850 / 60,850 | 7,510 / 7,510 | 37,360 / 37,360 | 135,318 / 201,321 | 4,328 / 4,328 | 5,052 / 5,052 | 149.1744 / 139.6171 | [JSON](evidence/spmark-payload-two-mapping-20261115.json) |
| load-forward | 60,784 / 60,784 | 7,060 / 7,060 | 36,686 / 36,686 | 135,314 / 201,317 | 4,324 / 4,324 | 5,048 / 5,048 | 151.2480 / 141.5576 | [JSON](evidence/spmark-payload-load-forward-20261115.json) |
| data-probe | 60,094 / 60,094 | 6,420 / 6,420 | 35,982 / 35,982 | 135,314 / 201,317 | 4,322 / 4,322 | 5,046 / 5,046 | 154.4752 / 144.5781 | [JSON](evidence/spmark-payload-data-probe-20261115.json) |
| fifo-flags | 60,094 / 60,094 | 6,420 / 6,420 | 35,982 / 35,982 | 135,314 / 201,317 | 4,322 / 4,322 | 5,046 / 5,046 | 154.4752 / 144.5781 | [JSON](evidence/spmark-payload-fifo-flags-20261115.json) |
| branch-owned | 63,972 / 63,972 | 6,372 / 6,372 | 35,328 / 35,328 | 107,865 / 201,312 | 3,591 / 3,591 | 3,728 / 3,728 | 172.9566 / 155.8735 | [JSON](evidence/spmark-payload-branch-owned-20261115.json) |
| branch-return | 56,489 / 56,489 | 6,102 / 6,102 | 28,331 / 28,331 | 105,589 / 201,321 | 3,527 / 3,527 | 3,587 / 3,587 | 186.9337 / 167.8711 | [JSON](evidence/spmark-payload-branch-return-20261115.json) |
| store-commit | 56,009 / 56,009 | 5,784 / 5,784 | 27,744 / 27,744 | 87,288 / 201,316 | 3,015 / 3,015 | 3,076 / 3,076 | 206.0389 / 179.2512 | [JSON](evidence/spmark-payload-store-commit-20261115.json) |
| completion-overlap | 56,082 / 56,082 | 5,719 / 5,719 | 27,667 / 27,667 | 71,269 / 201,314 | 2,574 / 2,574 | 2,624 / 2,624 | 225.1646 / 189.3816 | [JSON](evidence/spmark-payload-completion-overlap-20261115.json) |

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

`two-mapping` implements C as a second checked 1KiB mapping under shared
context, with separate R/W permissions and exact primary walk faults. All 12
groups/84 windows per repeat, two exact repetitions and six wrong-output
controls pass on the final source (440.557s). Matrix throughput improves 8.51%,
transpose 3.68%, triangle 4.40%; the suite improves 2.7630% / 2.7626% over
resident-store. Table indices retain the original baseline100, independently
computed from each original workload's cycles. The runner's normal comparison
field uses the immediate predecessor, and the tracked JSON additionally names
`original_baseline_index_by_profile` to keep these denominators explicit.

Final acceptance includes 96 CPU runs, seven relevant unit suites and four
negative controls, including a consumed-fault owner bug found in the initial
prototype and corrected before the accepted benchmark. Added state is 65 bits
per I/D controller, 130 total; no new RAM or PLL change. Fit/timing and phone
boot remain unverified. [Design and qualification](cache-two-mapping.md).

`load-forward` is the declared joint early/late CPU producer-availability step:
aligned word loads forward from the existing P2 completion register, other
formatted loads become available on their effective Memory B-commit edge.
Paired base/load priority is preserved. Full12groups/84windows, exact repeats
and all six wrong-output controls pass (421.588s). Suite gain1.3900%/1.3899%
over C; transpose6.37%, triangle1.84%, matrix0.11%.98CPU runs plus44IRQ/FIQ edge
sweeps, five related units and four negative controls pass. No new state/RAM;
FPGA cost/timing/boot need the requested next build. The table keeps the original
baseline100; the JSON explicitly records both original and predecessor indices.
[Implementation and dual-port next step](cpu-load-forwarding.md).

`data-probe` is F1: a registered address/way pre-read uses data RAM B while an
independent older store commits on A, then actual P2 checks gate completion.
Full original-byte suite passes both profiles/repeats/negative controls; +2.1338%
over load-forward.98CPU/44edge runs,20related units, five broken controls and
poisoned mixed-port RAM pass. Added68metadata bits, no line/dirty copy or new RAM.
Matched microkernels separately improve579→325clocks/128streamed loads and
321→259/32LDR+ADD iterations, two exact repeats. These are not hardware scores
or a pure cache initiation interval. [Design/tests](cache-data-probe.md).

`branch-owned` qualifies predictor feedback with a decoded owner rather than
ALU result success: full-suite gain11.9640%/7.8126% over fifo-flags. Matrix loses
in that intermediate step; other kernels improve. `branch-return` fixes the
MOV pc,lr matcher and trace-proven undefined target on successful confirmation;
another8.0813%/7.6970%, combined21.0121%/16.1110% over fifo-flags. Matcher-only
does not change these payload windows and was not accepted alone after a call
microbenchmark regression. All final sources/repeats/controls pass; fitted
timing/native score remain separate. [Contracts and controls](cpu-branch-return.md).

`store-commit` removes redundant ordinary write-back completion waits. All12groups,
84windows/repeat, two exact repeats and six wrong-output controls pass. Suite
throughput adds10.2203%/6.7791%; no new state/RAM/stage or clock change.
[Contract and qualification](cache-store-completion.md).

`completion-overlap` reuses the registered response credit while its old P2 owner
advances. Full-suite throughput +9.2825% /5.6515% over store-commit; matrix
slightly regresses56009→56082 (+0.13%cycles). Full repeated profiles preserve
every benchmark counter. This is bounded consume/admit parallelism; unresolved
cache waits still hold the pipeline. [Contract/tests](cache-completion-overlap.md).
