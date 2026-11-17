# Resident-store streaming baseline — 16 November 2026

Step 1 of the pipeline handoff is complete on the existing
`codex/ngage2-integration` checkout, revision
`9c948da8da413a882e0fe8e559c380ea0cadabf4`. This is an offline cache-port
baseline, not a new cache implementation or a CPU performance claim.
Production RTL, project/clock settings, Git history, CI and the running phone
were untouched. Existing unrelated working-tree changes were preserved; the
run's source manifest records them and records an empty production RTL diff.

## Rerun and outputs

From `/Users/andreabogazzi/develop/NGage_MiSTer`, choose unused output paths:

```sh
sh tests/cpu/cache_resident/sim.sh build/sim/resident-store-legacy-rerun
sh tests/cpu/cache_resident_stream/sim.sh build/sim/resident-store-stream-rerun
```

The streaming runner builds once, runs normal/repeat/wrong-byte cases, compares
all deterministic events, checks source hashes before/after, and emits
`source.json`, `result.json`, `build.log`, `normal.log`, `repeat.log` and
`negative.log`. Every Docker invocation uses the existing
`jotego/simulator:arm64`, `--pull=never --network none`, Linux ARM64.
Image ID: `sha256:df6f55924d5fab96083d01332e45cd734f22277c4dd3b34f55a09cd8dbc3eb8d`.

Verified output directories:

- `build/sim/resident-store-legacy-20261116-01/`: unchanged fixture, PASS,
  94 resident requests; legacy/indexed read task latency 3/1, store 2.
- `build/sim/resident-store-baseline-20261116-03/`: final streaming fixture,
  exact deterministic repeat and deliberate wrong-byte rejection.
- Compact durable result: `docs/evidence/cache-resident-stream-baseline-20261116.json`.

Reusable files are in `tests/cpu/cache_resident_stream/`: `test.v` contains the
independent generator/scoreboard, `observe.vh` contains all hierarchy-specific
observations, `sim.sh` and `report.py` capture and summarize the experiment.

## What is checked

Real lines are warmed with ordinary cache reads/refills. Additional ordinary
reads seed both resident records after refill invalidates the directory facts.
The generator depends only on stream ID and the number of accepted requests;
it keeps the next valid store present without waiting for response, holds the
full payload while backpressured, and advances at the falling edge following
acceptance. All 256 stores per stream are cacheable, bufferable, ordinary
write-back accesses with deterministic distinguishable data and nonzero masks.

The independent memory starts at `0x51000000 XOR byte_address`. Accepted
address/data/mask update the golden word and enqueue expected effects. Each
actual RAM write must match the next accepted store's tag/slot, word, full byte
enable and every enabled data byte. Actual RAM contents are checked after the
write, including untouched bytes. Actual packed tag-RAM dirty halves must match
the accumulated independently expected dirty halves. Responses are counted
separately, assigned in acceptance order, checked for faults/duplicates, and
cannot precede actual mutation. There are no transaction IDs or meaningful
store response data on this blocking interface; the independent RAM effect and
ordered response counters establish ownership, not an ACK alone.

After each measured stream, ordinary reads verify both lines, clean writes
back exactly four words per dirty half, and backing bytes must match the golden
model. A second clean must produce zero transfers. Readback, warming, clean and
second-clean clocks are excluded from the reported intervals. External read and
write transfers are counted over the whole measured burst including its drain.

Edge 1 is the first rising clock edge in the simulation. All offers, ready/valid
handshakes, responses and actual data-RAM write-port controls are sampled
**before nonblocking assignments** at each rising edge. Actual RAM and dirty
tag bytes are checked at +1 ns. The driver changes inputs only on falling edges.
Full OFFER/ACCEPT/RESPONSE/COMMIT records are retained in each raw normal log.

## Measured baseline

| Stream, 256 stores each | First/last accept | First/last RAM commit | Accept→commit | Accept / commit interval histograms | Rate, each | Clean words |
| --- | --- | --- | ---: | --- | ---: | ---: |
| Successive words, both halves | 63 / 1083 | 66 / 1086 | 3 | 4 clocks × 255 / 4 clocks × 255 | 0.25/clock | 8 |
| Alternating two resident lines | 4244 / 5264 | 4247 / 5267 | 3 | 4 × 255 / 4 × 255 | 0.25/clock | 16 |
| Same word, rotating single-byte masks | 8435 / 9455 | 8438 / 9458 | 3 | 4 × 255 / 4 × 255 | 0.25/clock | 4 |
| Lower half only | 12612 / 13632 | 12615 / 13635 | 3 | 4 × 255 / 4 × 255 | 0.25/clock | 4 |
| Upper half only | 16789 / 17809 | 16792 / 17812 | 3 | 4 × 255 / 4 × 255 | 0.25/clock | 4 |

Each row has 256 accepted requests, 256 sampled responses and 256 actual RAM
mutations. Each measured burst has zero external reads and zero external
writes. Each has 1021 offered edges, including 765 backpressured offers. Rates
use `(N−1)/(last−first) = 255/1020`, not `N/elapsed`. Dirty-half pairs for the
two lines are respectively `11/00`, `11/11`, `01/00`, `01/00`, `10/00`; second
clean writes zero words in every case.

For two adjacent stores in stream 0, the next address is already offered on
edge 64, without waiting for the first response:

| Edge | Offered address | State before edge | Accept | Sampled response | RAM mutation |
| ---: | --- | --- | --- | --- | --- |
| 63 | 0x100 | IDLE | store 0 | — | — |
| 64 | 0x104 | LOOKUP_CAPTURE | — | — | — |
| 65 | 0x104 | STORE_HIT | — | — | — |
| 66 | 0x104 | STORE_COMMIT | — | store 0 | store 0 |
| 67 | 0x104 | IDLE | store 1 | — | — |
| 68 | 0x108 | LOOKUP_CAPTURE | — | — | — |
| 69 | 0x108 | STORE_HIT | — | — | — |
| 70 | 0x108 | STORE_COMMIT | — | store 1 | store 1 |

The first blocker is `req_ready = (state == IDLE) && !invalidate_all &&
!lock_write && !maint_valid` in `rtl/arm920/cache_access.sv`: immediately after
acceptance, `LOOKUP_CAPTURE` deasserts ready. `STORE_HIT` captures data/dirty
intent, then `STORE_COMMIT` applies the RAM and dirty update and samples the
response. Ready returns only after that edge. No backing-memory transfer or
write-buffer capacity limits these bursts.

## Witness reconciliation and handoff

The review's transpose stores accept at 44/48 and commit/ACK at 47/51. Subtract
19 from the standalone trace above and the two sequences agree exactly:
accept-to-commit 3, recurrence 4. Absolute edges differ because this fixture
warms directly at the cache port rather than executing the CPU window. The
unchanged latency fixture reports store **2** because its task starts counting
after the acceptance tick and observes the combinational response after an
edge; that response becomes sampleable at the following rising edge. It is
not the rising-edge acceptance-to-actual-write latency. No unexplained handshake
difference remains.

Normal and repeat runs have identical offers, acceptances, responses, mutations,
edge traces, summaries and checks. Verilator's walltime/speed footer is excluded
from event comparison. `+corrupt_expected` flips the independently expected low
byte at the first store; the same checker aborts at edge 66 with
`checker byte mismatch (negative control=1)`. Production RTL is unchanged in
the negative control. The runner requires this specific failure and rejects
an unexpected negative success or an unrelated failure.

Development attempts 01/02 are not qualified final results: 01 compared entire
logs and failed only on nondeterministic Verilator walltime footer; 02 correctly
rejected changed fixture source fingerprints while logging was being extended.
Use attempt 03, whose sources remained fixed through the complete build/run.

Existing six-kernel and JPEG results are reused from
`docs/evidence/cpu-pipeline-review-20261116.json` and its original source/hash
references; no new workload-performance claim or payload replay was needed for
this test-only step. Their CPU-level results are separate from this direct
cache-port measurement.

The next implementation can reuse the offer generator and independent golden
model, updating only the hierarchy adapter when needed. One acceptance **and
actual commit** per clock is a future candidate's gate, not this baseline's
pass condition. It must retain ordered responses, byte/slot ownership, dirty
halves and zero external traffic in these resident bursts. Overlap needs to
address same-slot dirty/data ownership and registered ingress credit; this
step establishes the measurement seam and makes no RTL change. Broader fault,
reset, permission, CPU integration, fitter/timing and workload gates remain in
the architecture review. Stop here before production implementation.
