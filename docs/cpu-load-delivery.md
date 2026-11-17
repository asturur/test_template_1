# Registered waiting-load probe scheduling — Step 4C, 16 November 2026

**A bounded measured improvement:** original transpose falls **4,676 → 4,644
cycles (−32, −0.6843%)** in both existing I:D wait profiles. Exactly 32 certified
loads per scored window each lose one wait clock; no other read latency changes.
The drained 64-store loop remains **71 cycles**. Keep this isolated candidate;
there is no broader rewrite, fit, frequency change or production adoption.

| Same guest work | Final 4B control | Final 4C |
| --- | ---: | ---: |
| Original transpose, 0:0 | 4,676 | **4,644** |
| Original transpose, 2:9 | 4,676 | **4,644** |
| Drained 64-store loop | 71 | **71** |
| Immediate fast returns / transpose window | 193 | 193 |
| Admission-edge short reads | 129 | **161** |
| Ordinary fallback read acceptances | 94 | **62** |
| CPU read-stall clocks | 834 | **802** |

Two complete repeats, two warm-ups and all five scored windows match exactly.
The original guest bytes, input/output oracles, 800 payload instructions per
window and backing-memory profiles are unchanged. The checked 2,048-byte output
has SHA256 `ebfe239b2a964064eb2556d23d86a1e69b04f0ae63503374d1e696af2c7dc2bd`.
Wrong-output controls are rejected. [Compact evidence and hashes](evidence/cpu-load-delivery-20261116.json).

## Fixed control and one registered change

The control is the final 4B design, source ID
`b104f42d3e661c9a8832e8d928babca8ac872dd67f76bdcfbfaa5f60626d6094`.
The new overlay is `tests/cpu/cpu_load_delivery/rtl/arm920/`, changing only
cache_adapter.sv and cache_access.sv. CPU instruction stages, translation,
permission, store-credit, tag/dirty and external bus logic remain unchanged.

The adapter adds **one registered waiting-P2 bit**. It privately remembers an
ordinary unlaunched read that has not received ACK. Such a read temporarily
gets probe priority over registered P1 **until the existing registered RAM
result already covers its full line tag**. Then normal P1 lookahead resumes.
cache_access exposes only that scheduling coverage comparison against the
registered P2 tag. It is not permission, a new response or architectural credit.

Both address payloads still capture unconditionally. Selection uses registered
waiting/launch state and existing registered RAM-result identity, rather than
a live ACK/translation decision. ACK only contributes to the new small bit's
next registered value. All collision, revoke, current permission and full
owned-admission checks remain at consumption. An admitted read keeps the
existing single-demand path. Hints cannot initiate a walk, refill or external
effect. This is a structural one-bit addition, not a fitted area/timing claim.

## Trace the first LDR and next LDR

The apparently slow first instruction is **0x10002644: LDR r2,[r0,#4]**,
VA 0x80001004, followed by **0x10002648: LDR r3,[r0,#16]**, VA 0x80001010.
Their control trace starts at edge **149824**, when the first registered ALU
address is available. Relative edges below also describe the final candidate;
this initial uncertified path was not shortened.

| Event | First LDR | Next LDR |
| --- | ---: | ---: |
| Registered ALU address available | 0 | 1 |
| P1/check address available | 1 | 2 |
| Actual demand offered | 2 | 10 |
| Settled permitted translation for this demand | 5 | 10 |
| Cache accepts owned request | 5 | 10 |
| Physical data RAM-B read | 8 | 10 |
| Demand ACK | 9 | 11 |
| Registered CPU completion | 10 | 12 |
| Dependent STR may issue | — | 12 |

The first LDR has neither a reusable translation token nor a line-directory
certificate. The **TLB bank hits** at relative edge 4; at 5 the mapping is
owned, read permission is allowed, cacheable=1 and fault=0. The normal cache
sequence is LOOKUP_CAPTURE → LOOKUP_WAIT → LOOKUP(hit) → READ_LINE. RAM-B uses
slot **48** (way 6, segment 0). There is **no external miss/walk** in this
scored request. The next LDR reuses that translation and newly learned
certificate; its accepted probe reads the same line at edge 10 and supplies
the existing one-clock admission response. At 12 the dependent STR at
0x1000264c gets its loaded operand and issues.

Across a scored window there are **416 reads: 354 initially certified and 62
initially uncertified**. Every uncertified read resolves as a resident tag hit:
60 take four clocks offer→ACK, two take seven including a three-clock TLB-bank
lookup. All 416 have zero external transfers. This differs from cold window 0,
which has 95 initially uncertified reads, 33 scalar reads and 71 line transfers.
The first unusual TLB-token lookup alone is not a recurring 32-call target.

## Recurring delay selected and removed

At **0x10002654: LDR r2,[r0,#8]**, the current line A is certified and permitted,
but it follows a pair of A stores. P1 already names the next LDR at
0x10002658, in initially uncertified line B. In 4B, P1 priority directs the
private hint to B just when A becomes safe to read. The cache admits A without
a matching pre-read, then spends the extra ordinary indexed-read clock.
This exact case occurs **32 times**, once for each matrix.

Representative edges, relative to this LDR's first offer (absolute **149843**
control / **149774** candidate):

| Relative edge | Both designs | 4B | 4C |
| --- | --- | --- | --- |
| 0 | pending=2; translation ready; A certificate valid | No probe read | No probe read |
| 1 | pending=1; same-slot commit collision | No probe read | No probe read |
| 2 | pending=0; port free; accept A | Hint B has no certificate | **Hint A reads RAM-B; owns admission result** |
| 3 | Owned LOOKUP_CAPTURE | No reply yet | **ACK from matching registered A result** |
| 4 | — | ACK from ordinary line read | Registered completion; next LDR offered |
| 5 | — | Registered completion; next LDR offered | Next LDR in progress |

Its latency changes **4 → 3**: the two store-drain clocks are retained. The
dependent store after the next LDR becomes ready one clock sooner. Independent
read-owner matching finds exactly these 32 changed latencies and no others.
Total offer→ACK clocks fall **770 → 738**, and CPU read stalls **834 → 802**;
write stalls 192, load-operand locks 863, other locks 64, empty-queue clocks
1,636 and other/advancing clocks 1,087 are unchanged. The buckets reconcile
to 4,644, but are occupancy counts, not additive forecasts of further speedup.

## Failed first implementation and correction

The first implementation kept waiting P2 priority even when its RAM result
was already ready. It saved the targeted 32 clocks but displaced P1 lookahead
for **96 following loads**: their immediate ACK became a one-clock admission
response. Read stalls rose by 64, empty-queue clocks by four, and transpose
regressed to **4,744 cycles (+68)** with correct outputs. The coverage guard
restores all **193** original fast returns while retaining the 32 new short
reads. This is a refinement of the same scheduling experiment; no other CPU
path was redesigned. The failed variant's measured profile is retained.

## Correctness and next measured blocker

- The unchanged store guest retains all 63 one-clock acceptance/write gaps,
  448 ordered accepts/writes/completions/retirements, independent sixteen-word
  dirty backing checks and the 71-cycle drain. The deliberately wrong physical
  expected byte is rejected.
- A targeted stale-read case primes an old A result, writes new A data through
  active credits, points P1 at competing B, and then reads A. It returns the
  new **0xc0011234**, never the stale value. Real collision-poison RAM, exact
  slot/word/byte checks, dirty writeback and two event repeats pass.
- The actual CPU peak variant offers an older unmapped load and injects an
  IRQ at two outstanding stores. Older data and handlers are correct; forbidden
  younger STR PCs never reach acceptance. A same-address load with active
  credits cannot consume an older store response.
- Full three-credit pressure, simultaneous allocation/return, an active valid
  probe, following fault, reset and fresh backing read pass. The existing
  actual-adapter suite passes 402 requests/164 fast reads, including permission,
  alignment, translation, SWP, revocation and reset. All **256 one-clock admission
  reads and three identity mismatches** still pass.

The next measured **cache-side** cost is the remaining **62 uncertified resident
reads**, now exactly the remaining fallback reads: normal certificate/tag
acquisition rather than external miss service. Registered load completions and
dependent operand waits also remain. The larger empty-operand bucket was not
given a new causal attribution here. Do not widen this experiment into a cache
or CPU rewrite on the strength of these counters alone; other workloads and
integrated timing remain unmeasured in this slice.

## Replay and evidence

```sh
python3 tests/cpu/cpu_load_delivery/bench.py --control --name NEW_CONTROL --case transpose4
python3 tests/cpu/cpu_load_delivery/bench.py --name NEW_CANDIDATE --case transpose4 \
  --baseline build/sim/spmark-payload/NEW_CONTROL/result.json
python3 tests/cpu/cpu_load_delivery/run.py NEW_STORE_CANDIDATE
python3 tests/cpu/cpu_load_delivery/run.py NEW_PEAK_CANDIDATE --stress
python3 tests/cpu/cpu_load_delivery/pressure.py NEW_STALE_PRESSURE
```

Final workload outputs: `build/sim/spmark-payload/load-delivery-{control,candidate}-final/`;
failed first policy: `load-delivery-candidate-01/`. Final CPU/pressure outputs:
`build/sim/cpu-load-delivery/{store-control-01,store-candidate-final,peak-candidate-final,probe-pressure-final}/`.
The durable overlay, detailed observers and runners are in
`tests/cpu/cpu_load_delivery/`; compact edges, classification counts, source
hashes and oracle outcomes are in the linked evidence JSON.

Final 4B, production RTL/project, integration branch/HEAD/index, 78 MHz physical
PLL, phone and other runs/checkpoints remain unchanged. No agents were delegated,
no fit was submitted and no deployment occurred. Stop at this measured result.
