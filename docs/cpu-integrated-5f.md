# Integrated accepted 5F performance scorecard — 17 November 2026

**Retain 5F.** Relative to the 16-November architectural review, the six-kernel
equal-weight geometric throughput gain is **1.3348× at 0:0 and 1.3348× at 2:9**.
Separate original Thumb JPEG improves **1.0623×**. This is useful incremental
progress; it does not establish the review's broader pipeline or 4× objective.
Stock ngage2 remains **1.6486× / 1.3623×** faster over the six kernels, and
**2.3269× / 2.3028×** faster on the separate JPEG block. 5F wins full-frame fill.
No new RTL change, donor run, fit, CI, deployment or phone access belongs to
this assessment. The independently running Quartus work is outside this table.

## Matched work and cycles

Accepted CPU is `fae40167654949f9530e75eecd6d58c4fc74d013`; `5c3a0ea` completes
its regressions. Five kernel rows reuse the qualified 5F run. The missing exact
5F triangle was newly measured with the maintained original-payload runner:
**23,790 cycles in both profiles**, five constant scored samples, two identical
repeats, independent original-byte/math/Unicorn outputs and wrong-output rejection.

Review uses its actual receipt (`9c948da8`), not a later frontend baseline.
Work:16 matrices,32 transposes,16 triangle setups,36,608 frame pixels,
1,023 tail pixels,2,051 tail bytes. Lower cycles are better; the last column
is ngage2 cycles /5F cycles, above1 favoring5F.

### Synthetic I:D extra waits 0:0

| Original work | Review | 5F | Saved clocks | 5F speed / review | Stock ngage2 | 5F speed / ngage2 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| matrix4 | 52,275 | **45,736** | 6,539 | 1.1430× | 23,675 | 0.5176× |
| transpose4 | 5,328 | **3,591** | 1,737 | 1.4837× | 1,910 | 0.5319× |
| triangle_edges | 25,842 | **23,790** | 2,052 | 1.0863× | 12,634 | 0.5311× |
| fill16_frame | 71,263 | **71,259** | 4 | 1.0001× | 105,069 | 1.4745× |
| fill16_tail | 2,562 | **1,332** | 1,230 | 1.9234× | 707 | 0.5308× |
| fill8_tail | 2,629 | **1,647** | 982 | 1.5962× | 717 | 0.4353× |

### Synthetic I:D extra waits 2:9

| Original work | Review | 5F | Saved clocks | 5F speed / review | Stock ngage2 | 5F speed / ngage2 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| matrix4 | 52,275 | **45,736** | 6,539 | 1.1430× | 35,925 | 0.7855× |
| transpose4 | 5,328 | **3,591** | 1,737 | 1.4837× | 3,484 | 0.9702× |
| triangle_edges | 25,842 | **23,790** | 2,052 | 1.0863× | 13,844 | 0.5819× |
| fill16_frame | 201,306 | **201,302** | 4 | 1.0000× | 275,892 | 1.3705× |
| fill16_tail | 2,562 | **1,332** | 1,230 | 1.9234× | 760 | 0.5706× |
| fill8_tail | 2,629 | **1,647** | 982 | 1.5962× | 743 | 0.4511× |

| Equal-weight six-case throughput, relative to review = 1 | 0:0 | 2:9 |
| --- | ---: | ---: |
| Accepted 5F | **1.3348079×** | **1.3347998×** |
| Stock ngage2 | 2.2005106× | 1.8183974× |
| Stock ngage2 relative to 5F | 1.6485598× | 1.3622997× |

Each profile uses `exp(sum(log(reference_cycles / candidate_cycles)) / 6)`;
no profile pooling or JPEG inclusion. No review-relative regression.
33.48% more throughput is not33.48% fewer clocks.

### Separate original Thumb JPEG, 64 pixels

| Profile | Review | Accepted 5F | Stock ngage2 | 5F speed / review |
| --- | ---: | ---: | ---: | ---: |
| 0:0 | 89,610 | **84,353** | 36,251 | 1.0623× |
| 2:9 | 89,610 | **84,353** | 36,631 | 1.0623× |

5F saves 5,257 clocks (5.87%). Its scored windows remain
84399/84353/84353/84353/84353 at 0:0 and
84417/84353/84353/84353/84353 at 2:9. The current check covers this one original
8×8 converter; it is not a new four-converter or full-application qualification.

## Comparability and limits

All 12 ARM rows have identical wrapper hashes, linked payload/ROM, oracle outputs
and payload/helper counts across review, 5F and stock ngage2. Each has seven
windows, five scored, two exact repeats and wrong-output rejection. Triangle
still executes 6,656 GLES and 1,872 original firmware helper instructions per
window; no host division. Current/review JPEG selected wrapper, original inputs
and oracle match. Stock donor JPEG relies on its archived qualified receipt;
its raw manifest was retired, so no fresh donor JPEG source re-audit is claimed.

All **60 compiled CPU Verilog/include hashes** of the new triangle match accepted
Git CPU and 5F bundle `0db2f309…`. Generic bundle `e93e13bf…` differs only in
adoption metadata (`rtl/arm/README.md`, `UPSTREAM.json`, patch0078). Harness hashes
differ because 5F adds passive observers; responder and timing markers remain.
Stock ngage2 has its separately qualified completion observer. Donor `23541bb5`
uses **16/8KiB I/D**, two ways,16-byte lines; 5F retains **16/16KiB**,64ways,
32-byte lines. Cache/TLB conflicts and write allocation remain real differences.

The same offline simulator image and synthetic scalar/16-bit-line contract
apply. [Backend, source and observer qualification](ngage2-vs-5c-benchmark.md)
include normalization of donor's905 extra Thumb BL suffix completions. Raw
retirement counts are not a portable CPI. No physical SDRAM/DMA/OS contention,
frequency scaling, full SPMark score or whole-phone speed is inferred.

## Actual issue, memory commit and drain

The resident64-store stream retains **71 clocks from first actual issue to last
physical RAM write**. Its seven windows have448 ordered accept/write/completion/
retirement events. [5F qualification](cpu-store-postindex.md) independently checks
dirty backing bytes, faults, IRQ, devices and wrong-byte rejection.

First two original post-index stores, offsets from first real dequeue:

| Event | 5D | 5F |
| --- | --- | --- |
| Issue / correct address |0,1 /2,3 |0,1 /2,3 |
| Acceptance |5,8 |5,6 |
| Actual RAM write |7,10 |7,8 |
| Base commit and retirement |9,12 |7,8 |

The next store receives the correct old base. First eight acceptance offsets
are0,1,2,3,4,5,6,9; RAM writes0,1,2,3,4,5,6,12; retirements0,1,2,3,4,5,6,14,
relative to each event class's first event. The eighth store crosses a line.

Frame2:9's original median is **201,302** (range201300–201302). Ten pending
writes add105–107clocks to the passive first-empty boundary: **201,407 for all
five samples**. Donor frame has zero extension: **275,892**. At0:0 both end
without pending writes. First-empty runs normal check code concurrently and
is not a full dirty-cache clean. No matching review first-empty measurement
exists; the six-case index retains original body boundaries.

## Ranked remaining opportunities

Ranks reflect observed scale and breadth; none is an additive promised budget.

| Rank | Opportunity / breadth | Recoverable-clock evidence |
| --- | --- | --- |
| 1 | Useful target delivery; matrix, transpose, triangle, JPEG | Matrix/JPEG transfer intervals contain13,939/11,322 empty clocks, not removable budgets. One request-stage target counts633/519 clocks, but5E regressed matrix+1,196. No retained net mechanism. |
| 2 | Owned load-use delivery; JPEG and other load-heavy code |2,372 original immediate load consumers: removing one exposed clock each would target at most2,372 (2.81% of JPEG), before eligibility/overlap.39,845 first-window data-hold/load-lock clocks are not all recoverable. |
| 3 | Shifted product consumers; chiefly matrix |1,024 helpers retain3 holds each:3,072 observed clocks (6.72%). Full removal is an upper screen, not a demonstrated bypass budget; paired restart was already removed. |
| 4 | Resident line-transition ownership; both small fills |Two extra local acceptance stages ×63/64 crossings: conditional126/128 clocks. Do not add longer RAM/retire gaps or fill8's250 extra empty clocks. |
| 5 | Frame external service; streaming frame only |2:9 costs130,043 more clocks than0:0; zero resident-credit accepts. No quantified CPU-only service gain; current miss policy already beats donor. |

5D matrix/JPEG evidence is reused where5F has identical cycles, scored PCs and
bucket totals. Triangle gets no invented causal breakdown. Broader review
load-completion/independent-ALU goals remain unproven.

## Exactly one proposed next experiment

**Warm resident line-transition probe ownership**, on exact5F. Trace the eighth
post-index store; prepare its next resident, permitted line owner across a
registered probe boundary, serialize if unavailable. Target two local admission
clocks, preserving tag/permission, same-slot hazards, late data, faults and
drain. This concrete recurrence offers a bounded test; broader ranked areas
lack a retained mechanism. No implementation is included.

First reconcile all scored crossings/useful issue against conditional126/128
targets. Retain only with **≥4% fewer median clocks in each tail/profile**, no
**>0.5%** other-kernel/JPEG regression, and the71-cycle completed store stream.
Require original outputs/oracles, seven windows/repeats/negatives; real
issue→accept→RAM→base-write/retire traces and disjoint cycle accounting;
byte/order/dirty-half, faults/base, peakIRQ, MMIO, load/late/held-owner and drain
checks. Reject if unsafe or gains vanish in frontend phasing. A fit is separate.

## Evidence and replay

[Machine scorecard, exact windows, outputs, source and receipt hashes](evidence/cpu-integrated-5f-20261117.json).
Existing qualification receipts are unchanged. Reproduce the missing row with:

```sh
python3 tests/cpu/cpu_store_postindex/bench.py --name NEW --case triangle_edges --jobs 1
python3 tests/cpu/spmark_payload/scorecard_5f.py \
  --triangle build/sim/spmark-payload/NEW
```

The replay command freezes the original pinned5D+5F overlay, so subsequent
working-tree repairs cannot enter the measurement. The audit uses named saved
runs and accepted Git objects, not the current working multiplier. This assessment's triangle run is
`build/sim/spmark-payload/integrated-5f-triangle-01/`. Its manifests, oracle,
results and compact logs remain; only its own completed compiler/frozen-source
and generated binary/hex files were removed after hash collection. Other runs
and the running fit were preserved. Stop at this scorecard.
