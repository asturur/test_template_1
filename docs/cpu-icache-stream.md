# Retaining resident instruction lines across a predicted loop

The original Sega Rally fill takes **4,805 clocks** with the two I-cache
changes, down from **9,311** on the tagged control at both memory profiles.
That is **48.4% fewer clocks**, or **1.94× throughput**. The one-file retention
change alone takes 5,473. Each variation retires the same 2,567 instructions,
writes the same ordered 512 halfwords and passes the full output and guard
checks. [Matched fetch diagnosis](cpu-sega-fill-fetch.md)

| 512-pixel fill | Tagged control | Keep completed lines | Also steer idle lookahead | Stock ngage2 |
| --- | ---: | ---: | ---: | ---: |
| 0:0 | 9,311 | 5,473 | **4,805** | 2,596 |
| 2:9 | 9,311 | 5,473 | **4,805** | 2,628 |
| Clocks per pixel at 0:0 | 18.19 | 10.69 | **9.38** | 5.07 |

The control is the exact frozen state-tagged source with the banked main
TLB, third D-side mapping and qualified Thumb word loads. Source hashes
match the archived tagged receipt. The first overlay changes only
`rtl/arm920/cache_access.sv`. The second adds a change in
`rtl/arm/zap_cache.sv`. Both use the original program, firmware and
memory responder. The STRH credit change and the BTB launch path are
outside this experiment. The overlay adds zero declared state.

## Warm instruction lines

The cache uses two existing copied instruction lines for streaming.
A serialized resident demand changed the lookup epoch and invalidated
both copies, even though the tagged backing cache lines survived. In
the read-only instance, the first overlay preserves the completed copies
across ordinary serialized hits. Ownership changes still cancel each
in-flight lookahead. Maintenance, invalidate, lock changes, refill and
translation-context changes revoke both copies. The adapter continues
checking live cache enable, translation permission and exact address.
The D-cache still takes its original generated path.

The first overlay removes every serialized CMP request in the steady
loop, but the returning MOV still takes the long cache path on 255
of 511 complete fetch recurrences. In the three predicted-target
launch bubbles the old fallthrough PC stays on the request wires
and feeds the sequential +16 lookahead. One observed bubble probes
`1001ca20`, which shares a slot with `1001c9e0`, the line holding
the loop's MOV. The completed speculative read later overwrites
that slot.

The second overlay uses the next checked PC during invalid request
cycles. Valid requests retain the ordinary +16 lookahead. The old
fallthrough addresses therefore stop displacing the branch target
on this loop. The positive traces still show three no-request clocks
on the predicted branch, with only two serialized demands for the
loop's MOV in the whole first score and none for CMP. The instruction
FIFO is full on 579 edges. Most MOV-to-MOV execute intervals are nine
clocks, and 31 are 12 clocks at the store line boundary.

| Disjoint scored clocks | Tagged control | Keep completed lines | Also steer idle lookahead |
| --- | ---: | ---: | ---: |
| Global data hold | 1,652 | 1,652 | 1,652 |
| Operand lock outside hold | 523 | 523 | 523 |
| Empty operand stage outside hold and lock | 4,563 | 725 | 54 |
| Remaining clocks | 2,573 | 2,573 | 2,576 |
| Total | 9,311 | 5,473 | 4,805 |

At 4,805 clocks the scan of stage occupancy and queue fullness points
to data hold as the larger exposed residual. The same original STRH
stores still account for 1,635 global hold clocks and the CMP-to-BLE
dependency for 512 lock clocks. A faster branch launch would shorten
instruction delivery upstream. A new A/B is needed to measure what
would remain visible to execution with the current D path. The useful
follow-on is to revisit the measured STRH completion boundary on this
faster frontend, where the previous experiment no longer describes
which stage holds up the next iteration.

## Matched workload results

All 42 workload/profile comparisons match original retirement and store
effects on both overlays. The one-file change is faster in 28 rows and
ties 14. The two-file change is faster in 28, ties 12 and slows the two
matrix profiles. The six SPMark/GLES geometric throughput ratios versus
the tagged control are 1.0441× and 1.0489× for the two overlays in both
wait settings. The favorable ARM control still starts 224 operations in
224 clocks.

| Selected original case | Waits | Tagged control | Retention | Retention and steered lookahead |
| --- | --- | ---: | ---: | ---: |
| Sega Rally full scan | 0:0 | 5,375,298 | 5,363,317 | 5,176,864 |
| Sega Rally full scan | 2:9 | 5,506,714 | 5,494,733 | 5,308,282 |
| Thumb JPEG 8×8 | both | 80,379 | 80,133 | 78,647 |
| Triangle setup | both | 23,120 | 22,242 | 21,386 |
| Byte fill tail | both | 1,617 | 1,378 | 1,378 |
| Matrix | both | 41,667 | 41,587 | 42,248 |

The second change saves about 3.7% on the full Sega scan at 0:0 and
3.6% at 2:9. Its matrix regression is 581 clocks or 1.4%. The matrix
has 16 additional I-TLB searches, unchanged D hold and zero external
traffic in the sampled window. The complete matrix attribution remains open.

## Qualification and decision

The cache adapter test exercises resident alternation, live translation
denial, the context gate, a third-line refill that revokes the other
slot, and invalidation plus changed backing bytes. The exact old source
fails the alternation expectation. A separate CPU test checks MMU
translations, prefetch and fault behavior, pending writes, and the
usual CPU diagnostics on the refined overlay. All 32 CPU/MMU checks pass.
The same-address ARM/Thumb guest passes at all three waits with 41
correct predictions and five wrong-state recoveries per run.

Retain the one-file overlay with its clean workload comparison. Keep the
two-file overlay as the faster simulation candidate and record the matrix
trade-off before publication. Physical area, timing and hardware results
are unmeasured.

The subsequent matched STRH test brings the fill to 4,200 clocks on this
frontend. [Interaction test](cpu-icache-strh.md)

[Full scorecard, hashes and qualification](evidence/cpu-icache-stream-20261118.json.gz) ·
[Original fill edge journals](evidence/cpu-icache-stream-20261118.traces.json.gz) ·
[Reproducer](../tests/cpu/sega_fill_store/README.md)
