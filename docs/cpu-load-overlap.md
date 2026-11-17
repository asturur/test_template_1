# Bounded independent ARM load-pair overlap — Step 4D, 16 November 2026

Final 4C is the fixed control. One bounded offline experiment retains a measured
improvement: **original transpose 4,644 → 4,613 cycles (−31, −0.6675%)** in both
synthetic memory profiles. The independent 64-LDR-pair loop improves **698 → 634
cycles (−64, −9.1691%)**. The unchanged drained 64-store stream remains **71
cycles**. No fit, production adoption or physical speed claim follows this result.

| Identical guest work | Final 4C | Final 4D | Change |
| --- | ---: | ---: | ---: |
| Original transpose, I:D 0:0 | 4,644 | **4,613** | −31 |
| Original transpose, I:D 2:9 | 4,644 | **4,613** | −31 |
| Independent 64-pair loop, 0:0 | 698 | **634** | −64 |
| Independent 64-pair loop, 2:9 | 698 | **634** | −64 |
| Drained 64-store stream | 71 | **71** | 0 |

Transpose uses its original bytes, input setup, independent mathematical/Unicorn
oracle, 800 payload instructions, two warm-ups, five identical scored windows,
two full repeats and wrong-output rejection. The checked 2,048-byte output hash
remains `ebfe239b2a964064eb2556d23d86a1e69b04f0ae63503374d1e696af2c7dc2bd`.
The separate synthetic pair loop has 64 independent LDR pairs, dependent additions
consuming both values, then a checksum store. It executes 258 payload instructions;
Unicorn and independent arithmetic require checksum **0x8140**. It uses three
warm-ups and five identical scored windows, both profiles and two repeats, and
rejects a deliberately wrong checksum. Every scored window of both benchmarks
has zero external scalar/line traffic. These are offline CPU/cache measurements,
not an official SPMark score or a board-frequency qualification.

[Compact evidence, hashes and exact owners](evidence/cpu-load-overlap-20261116.json).

## Which earlier cycles are usable?

There are **192 recurring LDR pairs**, six per matrix. All have distinct loaded
registers, already independently resolved addresses and a shared 1 KiB translation
subregion. Their following STRs have true loaded-data dependencies. The existing
issue scoreboard prevents an address-dependent younger load from reaching P1
with an unresolved older input. There is no hidden opportunity to issue that
address at the same time as a genuinely independent address.

The first pair is `10002644: LDR r2,[r0,#4]` and
`10002648: LDR r3,[r0,#16]`, VA 80001004 / 80001010. Relative to the first
registered ALU address, the second ALU address exists at edge 1 and is held by P1
at edge 2. The first translation is unavailable through edge 4. Its permitted,
cacheable demand is accepted at 5; tag-owner capture/wait occupies 6–7; the actual
resident tag lookup and older RAM read occur at 8. **The way certificate only
becomes available at 9.** Thus edges 1–8 do not provide an already translated,
certified second demand that can simply be dispatched by a new queue.

At 9, however, the older load consumes the current synchronous RAM output and
that same port can prepare the younger line for the next edge. The previous
policy forbade private reads throughout every load response, including this
usable edge. This is the selected opportunity; no second demand queue was added.

At the older reply edge, the 192 pairs divide as follows:

| Observed opportunity | Pairs | Result |
| --- | ---: | --- |
| Existing lookahead already yields a fast second load | 96 | Unchanged |
| Certified younger line; older reply can share the read edge | **65** | One-clock second response becomes immediate |
| Younger line still lacks a certificate | 31 | Retains ordinary lookup |

The 65 gains are exactly 32 at PC 10002648, 32 at 10002698 and one at 10002658.
The same owner-by-owner classification holds in both profiles. The observer
records 739 paired P1/P2 edges: 550 IDLE, 96 LOOKUP_CAPTURE, 31 LOOKUP_WAIT,
31 LOOKUP and 31 READ_LINE. Six have unavailable translation, 160 still have an
older store credit, and 64 see a same-slot write collision. These counts overlap;
they are not additive lost cycles. The state-based read-port prohibition includes
both genuinely reserved tag/data service and the **65 reclaimed reply edges**.
All newly used edges have permission/translation settled, a current certificate,
zero pending stores and zero collisions. Missing-certificate and occupied-port
states were not converted into speculative lookups or external requests.

## Exact first overlap, completion and dependent store

Control base edge **149755**; final candidate base **149725**, both from scored
window 2. Absolute origins differ because earlier work also changes. Compare
relative edges, not the difference between these absolute timestamps.

| Event | 4C relative edge | 4D relative edge |
| --- | ---: | ---: |
| First / second registered ALU addresses | 0 / 1 | 0 / 1 |
| Held P1 second address; first demand offered | 2 | 2 |
| First demand permitted and accepted | 5 | 5 |
| First resident lookup / physical RAM read | 8 | 8 |
| First ACK | 9 | 9 |
| **Useful second-owner physical RAM-B read** | **10** | **9** |
| First registered CPU completion (R2) | 10 | 10 |
| Second demand offered / permitted | 10 | 10 |
| Second ACK | 11 | **10** |
| First architectural register write (R2) | 11 | 11 |
| Second registered CPU completion (R3) | 12 | **11** |
| Second architectural register write (R3) | 13 | **12** |
| First dependent STR may issue | 12 | **11** |
| First dependent STR accepted | 17 | **16** |

The new work is an actual synchronous read at candidate edge **149734**:
`PAIR_WORK old_pc=10002644 next_pc=10002648 tag=4000080 way=6 word=4`,
RAM slot **48**, older ACK=1 and younger completion=0. It prepares the same
32-byte line for the younger word; P1 owns that address while P2 waits. At
149735 the fresh demand independently passes current translation/permission and
consumes the matching result. This is useful work before the younger demand,
not evidence based merely on a P1 hint being present.

R2 completes at 149735 with **0xa846e198**, R3 at 149736 with **0x1b1ee3ff**;
register writes follow at 149736 and 149737 in that order. The dependent STR
1000264c is accepted at 149741, writing **0x1b1ee3ff** to 80001004; the next STR
10002650 at 149742 writes **0xa846e198** to 80001010. The independent original
transpose oracle verifies the resulting memory across all matrices and windows.
The saved `PAIR_COMPLETE`, `PAIR_REGISTER` and `PAIR_DEPSTORE` records include
both controls, all six first-matrix pairs and the following call boundary.

## Mechanism and limits

The final selectable overlay is `tests/cpu/cpu_load_overlap/rtl/`, on exact final
4C. A single class bit follows the existing CPU stall, operand-owner and kill
paths. It identifies the original **unconditional ARM immediate word LDR,
pre-indexed, no writeback, no PC base/destination**, before macro expansion.
Both P2 and held P1 must have this class, distinct destinations and addresses,
alignment, matching privilege and the same 1 KiB subregion. Older exceptions,
interrupts, redirects, completion/kill and uncertain formats exclude the pair.
Same-register/address cases, true address dependencies, Thumb, conditional,
LDM, writeback and nonordinary accesses retain their existing demand sequence.

The adapter captures one private pair-control bit beside its existing registered
P1 address. Cache access permits a certified, collision-free probe on an ordinary
older load's reply edge. The old RAM output supplies the older completion while
the synchronous read prepares the next output. No new line payload register,
load completion buffer, demand queue, translation owner, tag-read port or external
request is introduced. Address/permission still belong to the eventual demand;
full line identity, collision, current permission and revocation checks still
control consumption. No live younger ACK enters global stall. The I-cache ties
the new input low. The twelve changed source files consist of this class-bit
plumbing and the bounded adapter/cache scheduling change; cache bank, tags,
geometry, DSP/NOS/BT, MMU and external-bus logic are unchanged.

Fixed 4C source ID:
`7f3ce0f6fdba8b358a57acc36fa144177cb51fd15e0dd4a1eb216c5b3463094e`.
Final 4D source ID:
`76d176e29ae091962ebe66efe2cf0060f0d551f844fce29c014a5fd64fe6b4bb`.

## Correctness qualification

- Real CPU original transpose and synthetic pair-loop outputs, retirement totals,
  repeats and wrong-output controls pass at both memory delays. The detailed
  first-pair observer verifies registered completion, actual register writes,
  loaded data, following dependent store addresses/data and ordering.
- A dedicated real-CPU guest verifies same-Rd, address-dependent, same-address,
  LDM, base-writeback and failed-condition cases. The new pair mechanism stays
  excluded; a positive independent pair is observed. An actual older unmapped
  load aborts while older stores remain active. Its younger LDR neither completes
  nor retires, and its destination sentinel remains unchanged. The existing
  active-credit IRQ test and forbidden younger-store checks also pass, twice.
- Real adapter/cache tests explicitly overlap the younger read with the older
  reply. The younger demand cannot bypass its own permission fault or pending
  translation, cannot consume a different address, and returns fresh data after
  an intervening alias store. Reset kills the private owner. No external transfer
  occurs for the private work or permission-fault case. Collision-poison BRAM
  strengthens the stale-read checks.
- All previous primed-stale-A/new-A, full three-credit pressure, simultaneous
  allocate/return, active-probe/following-fault, dirty backing and reset tests pass.
  Peak=3, full holds=4, simultaneous allocation/return=1, active-probed waits=7.
- The unchanged store performance guest retains 448 ordered accepted instructions,
  actual physical writes, CPU completions and retirements, sixteen independently
  checked dirty backing words, all 63 one-clock warm acceptance/write gaps and
  **71** first-issue-through-final-write clocks. Its intentionally wrong first
  physical byte is rejected. The larger safety prologue needs additional warm-up
  (77 clocks in its first two noncold windows, then 71); it is not substituted for
  the unchanged store performance guest.
- Legacy probe suite: **402 requests / 164 fast reads / 123 blocked collisions**;
  admission suite: **256 short reads / three identity mismatches**. Permission,
  alignment, translation, SWP/device, maintenance, revocation and reset all pass.

Fixture corrections are retained, not accepted as design evidence: the initial
pair-loop end marker overlapped a checker read, so checker launch was padded
outside the marked window; its first scored attempt still had instruction-fetch
traffic, so three warm-ups are explicitly required. CPU safety assembly needed
literal comparisons for unencodable ARM immediates and untouched input words
outside the existing stressed stores. The early observer/source-wrapper binding
errors never produced accepted results. No failed DUT-output test was waived.
The initial broader decoded-format candidate and final original-class-qualified
candidate both measured 4613; only the latter source ID is accepted here.

## Gain accounting and next dependency

All 65 changed read owners fall from one clock offer→ACK to zero. Other read
latencies are identical. Fast returns rise **193→258** and admission reads fall
**161→96**; the 62 ordinary fallback reads remain. Total offer→ACK clocks fall
738→673. Read-stall clocks fall **802→737**, but empty-operand clocks rise
**1636→1670**. Write stalls=192, load locks=863, other locks=64 and other/advance
clocks=1087 are unchanged. These sum to 4613: **65 saved read clocks, 34 absorbed
by queue-empty scheduling, 31 net**. The experiment does not assign a new causal
root to all empty clocks or claim a 65-clock workload gain.

The next specific cache-side limitation is **31 second loads without a way
certificate**, plus first-load acquisition within the remaining 62 resident
fallback reads. True loaded-data dependence still keeps each following STR
behind the second registered completion; store→load ordering and its drain
clocks remain. Earlier safe tag/translation work would need separate owned
qualification. The measured result supports retaining this bounded offline
candidate, not adding a general queue or predicting another fit's outcome.

## Replay and preserved outputs

```sh
python3 tests/cpu/cpu_load_overlap/bench.py --control --name UNIQUE_CONTROL --case transpose4
python3 tests/cpu/cpu_load_overlap/bench.py --name UNIQUE_CANDIDATE --case transpose4 \
  --baseline build/sim/spmark-payload/UNIQUE_CONTROL/result.json
python3 tests/cpu/cpu_load_overlap/loop.py UNIQUE_PAIR_CONTROL \
  --build build/sim/spmark-payload/UNIQUE_CONTROL
python3 tests/cpu/cpu_load_overlap/loop.py UNIQUE_PAIR_CANDIDATE \
  --build build/sim/spmark-payload/UNIQUE_CANDIDATE
python3 tests/cpu/cpu_load_overlap/run.py UNIQUE_STORE
python3 tests/cpu/cpu_load_overlap/run.py UNIQUE_SAFETY --stress --safety
python3 tests/cpu/cpu_load_overlap/pressure.py UNIQUE_PRESSURE
```

Final original payload outputs:
`build/sim/spmark-payload/load-overlap-{control-final,candidate-measured}/`.
Independent loops: `build/sim/cpu-load-overlap/pairs-{control,candidate}-measured/`.
Store: `store-stream-final/`; CPU safety: `store-safety-final-03/`;
pressure: `pressure-candidate-01/`, all under `build/sim/cpu-load-overlap/`.
Compatibility: `build/sim/load-overlap-{probe,admit}-final/`.
`tests/cpu/cpu_load_overlap/analyze.py` re-audits the saved hashes, exact owners,
cycles, oracles, register/store traces and negative controls before saving evidence.

The original integration checkout/HEAD/index, final 4C control, production RTL,
project/workflow, physical 78 MHz PLL, phone, existing simulations and permanent
checkpoints were preserved. No agents, CI, fit, deployment or hardware access.
Stop at this measured intermediate improvement.
