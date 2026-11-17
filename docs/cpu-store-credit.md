# One spare registered store credit — Step 4B, 16 November 2026

**Keep the spare-credit candidate for its measured store-stream gain.** The
same drained 64-store ARM sequence improves **102 → 71 clocks (−30.39%)**.
All 63 warm acceptance and physical-write gaps are one clock. Original transpose
**plateaus at 4,676 clocks** in both existing wait profiles. Its next observed
dependency is resident load delivery and load-to-store operand readiness,
including the store-to-load drain boundary, rather than another store credit.

## Single change and matched comparison

The fixed control is final Step 4A, source ID
`dcbc85875b34ffaeafe289cea6ecd6e806ec37878fdbb5a8c85f7ded0c93edcb`.
The explicit candidate overlay is
`tests/cpu/cpu_store_credit/rtl/arm920/cache_adapter.sv`. Relative to 4A it
changes only the two `store_pending < 2` admission tests to `< 3`, the matching
overflow assertion and its comment. The existing counter remains **two bits**;
no payload FIFO, eligibility change, new state bits, RAM or DSP is introduced.
The newly allowed grant uses registered count, with no response-dependent
same-edge credit bypass or new path into global CPU stall/fast ACK.

Both variants select identical 4A CPU/cache/production-BRAM sources apart from
that one adapter file. The 64-store guest binary is byte-identical to final 4A;
warm-up, delays and independent output/dirty/retirement oracles are retained.
Fresh runs reproduce 4A's 102-cycle loop and 4,676-cycle transpose baseline.
All measurements use two repeats and five scored windows after two warm-ups.
[Hashes, samples and exact input audit](evidence/cpu-store-credit-20261116.json).

| Measured warm quantity | 4A control | One spare credit |
| --- | ---: | ---: |
| First CPU issue through final physical write, inclusive | 102 | **71** |
| Clocks per architectural store, including fill/drain | 1.593750 | **1.109375** |
| First acceptance through final physical write, inclusive | 97 | 66 |
| Whole marked window, including following load/byte checks | 123 | 92 |
| CPU issue gap histogram, 63 gaps | 1:33, 2:30 | **1:62, 2:1** |
| Acceptance gap histogram, 63 gaps | 1:32, 2:31 | **1:63** |
| Actual RAM-write gap histogram, 63 gaps | 1:32, 2:31 | **1:63** |
| Natural peak outstanding count | 2 | 2 |
| Simultaneous allocation/return edges over seven windows | 209 | 418 |
| Warm external reads/writes/line transfers | 0 / 0 / 0 | 0 / 0 / 0 |
| Transpose 0:0 median | 4,676 | **4,676** |
| Transpose 2:9 median | 4,676 | **4,676** |

There is one CPU-issue startup bubble, not a recurring bubble after every
pair. The warm accepted-store and physical-write streams are uninterrupted.
Cold marked window 0 remains 389 clocks in both; instruction fills hide the
small cold store difference. No cold-fetch or whole-phone gain is claimed.

## Three distinct ARM stores and the removed bubble

Scored-window PCs A/B/C are **0x18c / 0x190 / 0x194**; they store
0x11111111/0x22222222/0x33333333 at VA 0x80001000/+4/+8. Relative to first
acceptance (absolute 95731 control / 95700 candidate):

| Event | 4A A/B/C | Spare A/B/C |
| --- | --- | --- |
| Actual CPU issue | −5 / −4 / −3 | −5 / −4 / −3 |
| Adapter/cache acceptance | 0 / 1 / **3** | 0 / 1 / **2** |
| Registered CPU completion | 1 / 2 / 4 | 1 / 2 / 3 |
| Actual RAM writes | 2 / 3 / 5 | 2 / 3 / 4 |
| Architectural retirement | 2 / 3 / 5 | 2 / 3 / 4 |

At edge +2, the control has count=2 and returns A, but cannot allocate C from
that registered full count. Its count becomes 1. C retries at +3 alongside B's
return, and registered CPU completion has a hole: global data_stall rises at
+3 and upstream issue pauses. The spare-credit version has count=2, grants C
and returns A **on the same edge**, leaving count=2. At +3 it grants D and
returns B; CPU issue continues. The implementation does not combinationally
subtract an arriving response to obtain credit.

Thus three grant slots do **not** imply three live cache payloads in ordinary
operation: the spare covers the registered return phase. Actual outstanding
count naturally peaks at two. The separate full-pressure test reaches three
by delaying only response publication, so the bound and backpressure are tested
rather than inferred from an unexercised overflow assertion.

## Ordering and boundary qualification

- **Actual CPU/memory:** each matched run checks 448 accepted stores, physical
  writes, registered completions and architectural retirements in order, with
  actual RAM slot/word/mask/data checks and all sixteen dirty backing words.
  Two complete event repeats match. The reused deliberately wrong first
  expected byte is rejected at the first physical RAM mutation.
- **Active CPU credits:** a separate functional guest variant offers an older
  unmapped load while count=2 and injects a real IRQ at count=2. Both fault and
  IRQ occur once; handlers verify older store data, and forbidden younger STR
  PCs never reach acceptance. The following same-address load is offered with
  credits active (14 observed hold clocks per run), and cannot consume an old
  store response. Its returned value and the following byte store are correct.
  This functional variant is separate from the unchanged timed binary.
- **Full-pressure/return:** the actual adapter/cache, with collision-poison RAM,
  receives a test-only four-clock physical-response publication delay. Real RAM
  writes retain their timing. Count reaches **3**, the fourth store is held for
  **four full-pressure clocks**, and simultaneous allocation/return is exercised.
  Independent ordered write checks and dirty writeback pass.
- **Active probed load/fault/reset:** the pressure fixture holds an already
  valid independent B probe while stores remain active (**six clocks**), with
  neither fast ACK nor demand ACK allowed. B readback and following same-address
  A readback are correct. A following fault waits for older credits and cannot
  leak its younger write. Reset at count=3 clears credit/cache owners; eight
  idle clocks show no stale reply/probe and a fresh backing read passes. This
  retains the existing hard-reset cancellation contract, not persistence of
  uncleaned stores through reset.

All these cases pass exact repeats. The pressure fixture's first attempt
compared dirty resident data with stale backing data during the next warm-up;
cleaning before each phase corrected the fixture. The candidate RTL did not
change between attempts.

## Why transpose plateaus; first remaining workload stall

Each scored transpose window still has **384 qualified stores, 384 admission
credits and 192 overlapping acceptances**. Original instruction/oracle hashes,
payload/helper retirement windows, all checked outputs, deterministic repeats
and wrong-output rejection match. The added observation-only profile reproduces
4A's existing raw counters exactly. Both profiles and both variants have the
same first-stall trace and exclusive priority buckets:

| Bucket | Clocks/window |
| --- | ---: |
| Read data stall | 834 |
| Write data stall | 192 |
| Load operand lock outside data stall | 863 |
| Other operand lock | 64 |
| Empty operand queue | 1,636 |
| Other/advancing | 1,087 |
| Total | 4,676 |

These are occupancy classifications, not additive predictions of recoverable
cycles. The first actual payload instruction is **0x10002644, LDR r2,[r0,#4]**.
At edges **149826–149833** it stalls with **pending stores=0**, no valid probe,
and a dependent **STR at 0x1000264c** locked in issue. ACK arrives at 149833;
its registered completion is available at 149834. The next LDR at 0x10002648
gets a completion at 149836, finally releasing that store's operand lock.

The original code is `LDR, LDR, STR, STR`, repeated for six element swaps.
Those two stores allocate at **149841/149842**; at 149843 the next offer is
already a **load**, not a third eligible store. It waits through count=2→1→0,
then resident read/probe and registered completion, before the next dependent
store can issue. The same pattern yields exactly 192 store pairs per window.
More store credits cannot remove these load and operand waits. The next
workload-focused experiment should inspect certified resident load delivery,
store→load drain/probe availability and dependent store-data release, while
preserving the same ordering and fault guards. It is not implemented here.

## Replay and stopping point

```sh
python3 tests/cpu/cpu_store_credit/run.py NEW_CONTROL --control
python3 tests/cpu/cpu_store_credit/run.py NEW_SPARE
python3 tests/cpu/cpu_store_overlap/negative.py build/sim/cpu-store-credit/NEW_SPARE
python3 tests/cpu/cpu_store_credit/run.py NEW_PEAK --stress
python3 tests/cpu/cpu_store_credit/pressure.py NEW_PRESSURE
python3 tests/cpu/cpu_store_credit/bench.py --control --name NEW_TRANSPOSE_CONTROL --case transpose4
python3 tests/cpu/cpu_store_credit/bench.py --name NEW_TRANSPOSE_SPARE --case transpose4 \
  --baseline build/sim/spmark-payload/NEW_TRANSPOSE_CONTROL/result.json
```

Raw final loops: `build/sim/cpu-store-credit/{control-final,spare-final}/`;
peak CPU cases: `{control-peak-01,spare-peak-01}/`; pressure: `pressure-02/`.
Original workload outputs: `build/sim/spmark-payload/store-credit-{control,spare}-01/`.
Durable runners/tests/one-file overlay: `tests/cpu/cpu_store_credit/`.

One offline design experiment only. Final 4A and other chats' runs remain
unchanged. Production RTL/project, integration branch/HEAD/index, physical
78 MHz PLL, phone and other simulations/checkpoints were untouched. There is
no fit, deployment, fitted area claim or new routed timing result. Stop here.
