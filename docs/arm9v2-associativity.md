# ARM9V2 associativity scorecard

The control is the fitted v5 source tree at `2a84b50`. The CPU clock and
memory interfaces use 78 MHz, MMC uses 39 MHz, NOS uses 64 Hz, and flash
D2 holds 8 KiB. The experimental builds keep the L1 caches at 16 KiB per
side and 32 bytes per line. The I and D way counts can be selected
independently. The series changes both together from 2 to 64 ways.

The generator applies the experimental overlays to a disposable copy of
the pinned upstream RTL and emits the same kind of Verilog source that
Quartus selects for v5. The production generated source stays at the
fitted two-way control. The official macOS `sv2v` 0.0.13 release emits a
different module order and generated identifiers from the pinned artifact.
The original control uses the exact pinned artifact. The generalized
two-way build is checked against it at the guest output, raw timing
windows and bus-traffic levels.

This comparison covers offline RTL simulation. The archived control fit
identifies the production source. The experimental geometries have no
new fit, routed timing or board measurements.

## Results

All six cache sizes passed the six SPMark kernels, the seven short game
payloads, the Thumb JPEG, and the directed cache and bus contracts with
both writeback policies. The largest change in delayed SPMark geometric
mean was +0.0072% at 32 and 64 ways with half-line writes. The delayed
GLES fill moved from 237,167 to 237,065 cycles at those settings. The
stock two-way build remains 1.643× v4 and 1.232× original ngage2 across
the six kernels at `2:9`.

The fastest completed delayed Sega Rally frame was eight ways with
half-line writes, at 4,439,159 cycles versus 4,502,989 stock (1.42% fewer).
Eight ways with whole-line writes took 4,464,799 cycles. The largest
repeatable short-loop change was the Asphalt table loop at `2:9`,
22,005 to 21,327 cycles (3.08% fewer). Keep the stock two-way cache for
v5. Half-line writes substantially reduced the separate clean workload.

The 64-way whole-line sweep completed at 4,470,224 delayed Sega cycles.
At the requested snapshot, the 32- and 64-way half-line Sega suites were
still running. The verified 32-way half-line `0:0` result was 3,445,368
cycles. Both geometries have complete SPMark, short game, JPEG, and
maintenance rows.

## Implementation

- Preserve the two-way replacement path and use binary-tree pseudo-LRU
  for larger geometries, with invalid slots preferred. Accepted hits
  take precedence over a coincident fill on the shared set.
- Carry the complete way index into data forwarding and maintenance. The
  indexed CP15 operand uses the high way bits and the set bits above the
  line offset. The cache type reports the selected I and D geometry.
- The cleaner scans 32 groups of 16 slots at every geometry. The 32-way
  geometry uses one 16-slot group per way. At 64 ways each group joins
  adjacent eight-slot ways. Data and dirty metadata share the existing
  store/fill ownership and write-behind forwarding.
- The half-line trial packs both dirty flags into the existing metadata
  byte lane. It keeps one group reader and uses the flags to choose a
  four-word lower or upper writeback, or an eight-word full writeback.
  The packed control uses the same flags and eight-word writebacks. It
  isolates the writeback bandwidth effect from the metadata change.

## Control checks

The original and generalized two-way line-dirty builds match on seven
windows per payload at each of the `0:0` and `2:9` memory profiles. The
original and generalized CPU contracts also match at both wait settings
with supported and rejected bursts. The original directed check passes
clean, backing-memory, and highest-set I/D conflict probes.
The packed two-way whole-line control matches the original on the same
windows and all eleven directed phases. That control isolates the
transfer-width effect from the change in how dirty flags are stored.

In the two-way half-dirty trial, with accepted bursts and five added
memory-wait clocks, the resident-cache clean takes 18,936 clocks and
2,040 writes. The whole-line control takes 35,256 clocks and 4,080 writes.
An empty clean takes 66 clocks and scans 32 empty groups in both. A
single dirty half writes four words in 73 clocks, compared with eight
words in 105 clocks for the whole-line control. A line with both halves
dirty takes eight words and 105 clocks in either mode. The backing-memory
test writes a newer value into the clean half and checks that the
half-line writeback preserves it.

## Counters

The scorecard records all seven windows and aggregates the five scored
ones. I/D fills are completed refills. D responses count acknowledged
requests, and the I-accept counter counts pushes into the fetch buffer.
I-port acknowledge clocks can include a held address. The TLB columns
count accepted page-table bus beats. The first-word latency pairs a
fill with the first accepted fetch at its original address. A refill
whose demand was flushed may have no first-word sample. Stall, refill,
and writeback events can overlap, so their counts cannot be added into
a single cycle budget.
The stock build and first three whole-line runs predate the accepted
fetch and first-word instrumentation. A repeat of the triangle kernel
with the new observer gives identical fetch metrics for all four builds.
In the first measured window the mean time to accept a matching fetch
is 4.84 clocks at `0:0` and 9.98 at `2:9`. Full refills average 10.09
and 27.46 clocks respectively. There are no sampled refills in the five
scored windows of that kernel.

The [previous payload comparison](arm9v2-cache32.md#checked-comparison)
contains archived v4 and original ngage2 numbers for the same work.
The donor uses its native 16-byte bursts and v5 uses 32-byte bursts.

## Isolating the instruction and data caches

The eight-way whole-line result was the fastest delayed Sega frame among
the first four completed geometries. The mixed-geometry runs replay the
same full frame, both waits, two repeats, and the wrong-output controls.

| I ways | D ways | `0:0` cycles | `2:9` cycles |
| ---: | ---: | ---: | ---: |
| 2 | 2 | 3,461,218 | 4,502,989 |
| 8 | 2 | 3,461,218 | 4,502,989 |
| 2 | 8 | 3,450,204 | 4,464,799 |
| 8 | 8 | 3,450,204 | 4,464,799 |

The D-cache alone reproduces the entire eight-way difference. The
delayed frame with both caches at eight ways had 4,108 D refills per
scored window, down from 4,633 at two ways. Scored I refills were zero in
both, and D-TLB traffic remained at 109,850 page-table beats per window.

## D-side section translation conflicts

The [section-index report](arm9v2-section-xor.md) records the Sega Rally
translation conflict and the separate folded-index benchmark.

## Payload cycles

Each cell gives median CPU clocks at `0:0 / 2:9` added I:D waits.

### Whole-line writebacks

| Workload | v4 | Original ngage2 | Stock two-way | 2 | 4 | 8 | 16 | 32 | 64 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| matrix4 | 41,667 / 41,667 | 23,675 / 35,925 | 17,437 / 17,793 | 17,437 / 17,793 | 17,437 / 17,793 | 17,437 / 17,793 | 17,437 / 17,793 | 17,437 / 17,793 | 17,437 / 17,793 |
| transpose4 | 3,560 / 3,560 | 1,910 / 3,484 | 1,899 / 2,583 | 1,899 / 2,583 | 1,899 / 2,583 | 1,899 / 2,583 | 1,899 / 2,583 | 1,899 / 2,583 | 1,899 / 2,583 |
| triangle_edges | 23,120 / 23,120 | 12,634 / 13,844 | 12,634 / 13,430 | 12,634 / 13,430 | 12,634 / 13,430 | 12,634 / 13,430 | 12,634 / 13,430 | 12,634 / 13,430 | 12,634 / 13,430 |
| fill16_frame | 71,259 / 201,302 | 105,069 / 275,892 | 92,612 / 237,167 | 92,612 / 237,167 | 92,612 / 237,167 | 92,612 / 237,167 | 92,612 / 237,167 | 92,605 / 237,105 | 92,605 / 237,105 |
| fill16_tail | 1,332 / 1,332 | 707 / 760 | 707 / 724 | 707 / 724 | 707 / 724 | 707 / 724 | 707 / 724 | 707 / 724 | 707 / 724 |
| fill8_tail | 1,647 / 1,647 | 717 / 743 | 716 / 727 | 716 / 727 | 716 / 727 | 716 / 727 | 716 / 727 | 716 / 727 | 716 / 727 |
| monkey-forward | 31,103 / 31,103 | 16,875 / 17,173 | 16,413 / 16,424 | 16,413 / 16,424 | 16,413 / 16,424 | 16,413 / 16,424 | 16,413 / 16,424 | 16,413 / 16,424 | 16,413 / 16,424 |
| monkey-reverse | 31,058 / 31,058 | 16,608 / 16,759 | 16,413 / 16,424 | 16,413 / 16,424 | 16,413 / 16,424 | 16,413 / 16,424 | 16,413 / 16,424 | 16,413 / 16,424 | 16,413 / 16,424 |
| sega-span | 32,908 / 32,908 | 15,990 / 16,143 | 15,912 / 15,932 | 15,912 / 15,932 | 15,912 / 15,932 | 15,912 / 15,932 | 15,912 / 15,932 | 15,912 / 15,932 | 15,912 / 15,932 |
| sega-fill | 9,311 / 9,311 | 2,596 / 2,628 | 2,596 / 2,616 | 2,596 / 2,616 | 2,596 / 2,616 | 2,596 / 2,616 | 2,596 / 2,616 | 2,596 / 2,616 | 2,596 / 2,616 |
| asphalt-table | 41,169 / 41,169 | 22,524 / 23,991 | 21,717 / 22,005 | 21,717 / 22,005 | 21,412 / 21,506 | 21,306 / 21,327 | 21,306 / 21,327 | 21,306 / 21,327 | 21,306 / 21,327 |
| asphalt-double | 18,441 / 18,441 | 12,960 / 15,472 | 12,392 / 12,644 | 12,392 / 12,644 | 12,331 / 12,351 | 12,331 / 12,351 | 12,331 / 12,351 | 12,331 / 12,351 | 12,331 / 12,351 |
| asphalt-single | 12,731 / 12,731 | 8,332 / 8,657 | 8,250 / 8,269 | 8,250 / 8,269 | 8,250 / 8,269 | 8,250 / 8,269 | 8,250 / 8,269 | 8,250 / 8,269 | 8,250 / 8,269 |
| sega-scan | 8,290,663 / 8,422,080 | 3,471,563 / 4,503,455 | 3,461,218 / 4,502,989 | 3,461,218 / 4,502,989 | 3,443,857 / 4,477,623 | 3,450,204 / 4,464,799 | 3,447,773 / 4,468,229 | 3,446,232 / 4,470,469 | 3,446,713 / 4,470,224 |
| diffuse_m10_8x8_jpeg | 82,943 / 82,943 | 36,251 / 36,631 | 35,913 / 35,921 | 35,913 / 35,921 | 35,913 / 35,921 | 35,913 / 35,921 | 35,913 / 35,921 | 35,913 / 35,921 | 35,913 / 35,921 |
| SPMark throughput vs. stock (%) | — | — | — | 100.000 / 100.000 | 100.000 / 100.000 | 100.000 / 100.000 | 100.000 / 100.000 | 100.001 / 100.004 | 100.001 / 100.004 |
| SPMark throughput vs. prior ways (%) | — | — | — | — | 100.000 / 100.000 | 100.000 / 100.000 | 100.000 / 100.000 | 100.001 / 100.004 | 100.000 / 100.000 |

### Half-line writebacks

| Workload | Stock two-way | 2 | 4 | 8 | 16 | 32 | 64 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| matrix4 | 17,437 / 17,793 | 17,437 / 17,793 | 17,437 / 17,793 | 17,437 / 17,793 | 17,437 / 17,793 | 17,437 / 17,793 | 17,437 / 17,793 |
| transpose4 | 1,899 / 2,583 | 1,899 / 2,583 | 1,899 / 2,583 | 1,899 / 2,583 | 1,899 / 2,583 | 1,899 / 2,583 | 1,899 / 2,583 |
| triangle_edges | 12,634 / 13,430 | 12,634 / 13,430 | 12,634 / 13,430 | 12,634 / 13,430 | 12,634 / 13,430 | 12,634 / 13,430 | 12,634 / 13,430 |
| fill16_frame | 92,612 / 237,167 | 92,607 / 237,127 | 92,607 / 237,127 | 92,607 / 237,127 | 92,607 / 237,127 | 92,600 / 237,065 | 92,600 / 237,065 |
| fill16_tail | 707 / 724 | 707 / 724 | 707 / 724 | 707 / 724 | 707 / 724 | 707 / 724 | 707 / 724 |
| fill8_tail | 716 / 727 | 716 / 727 | 716 / 727 | 716 / 727 | 716 / 727 | 716 / 727 | 716 / 727 |
| monkey-forward | 16,413 / 16,424 | 16,413 / 16,424 | 16,413 / 16,424 | 16,413 / 16,424 | 16,413 / 16,424 | 16,413 / 16,424 | 16,413 / 16,424 |
| monkey-reverse | 16,413 / 16,424 | 16,413 / 16,424 | 16,413 / 16,424 | 16,413 / 16,424 | 16,413 / 16,424 | 16,413 / 16,424 | 16,413 / 16,424 |
| sega-span | 15,912 / 15,932 | 15,912 / 15,932 | 15,912 / 15,932 | 15,912 / 15,932 | 15,912 / 15,932 | 15,912 / 15,932 | 15,912 / 15,932 |
| sega-fill | 2,596 / 2,616 | 2,596 / 2,616 | 2,596 / 2,616 | 2,596 / 2,616 | 2,596 / 2,616 | 2,596 / 2,616 | 2,596 / 2,616 |
| asphalt-table | 21,717 / 22,005 | 21,717 / 22,005 | 21,412 / 21,506 | 21,306 / 21,327 | 21,306 / 21,327 | 21,306 / 21,327 | 21,306 / 21,327 |
| asphalt-double | 12,392 / 12,644 | 12,392 / 12,644 | 12,331 / 12,351 | 12,331 / 12,351 | 12,331 / 12,351 | 12,331 / 12,351 | 12,331 / 12,351 |
| asphalt-single | 8,250 / 8,269 | 8,250 / 8,269 | 8,250 / 8,269 | 8,250 / 8,269 | 8,250 / 8,269 | 8,250 / 8,269 | 8,250 / 8,269 |
| sega-scan | 3,461,218 / 4,502,989 | 3,460,258 / 4,466,349 | 3,443,779 / 4,451,783 | 3,448,410 / 4,439,159 | 3,446,849 / 4,442,709 | Pending | Pending |
| diffuse_m10_8x8_jpeg | 35,913 / 35,921 | 35,913 / 35,921 | 35,913 / 35,921 | 35,913 / 35,921 | 35,913 / 35,921 | 35,913 / 35,921 | 35,913 / 35,921 |
| SPMark throughput vs. stock (%) | — | 100.001 / 100.003 | 100.001 / 100.003 | 100.001 / 100.003 | 100.001 / 100.003 | 100.002 / 100.007 | 100.002 / 100.007 |
| SPMark throughput vs. prior ways (%) | — | — | 100.000 / 100.000 | 100.000 / 100.000 | 100.000 / 100.000 | 100.001 / 100.004 | — |

## Replay

Use `sv2v` 0.0.13, the existing offline `jotego/simulator:arm64` image,
and the local original assets described in the [ARM9V2 replay README](../tests/cpu/arm9v2_board/README.md).
For the stock control, run the original CPU netlist at `2a84b50` with
the fixed run names expected by the scorecard.

```sh
python3 -B tests/cpu/ngage2_compare/run.py --cpu arm9v2 \
  --name v5-assoc-original-spmark --payload-dir "$NGAGE_FIXTURES/spmark_payload/local"
python3 -B tests/cpu/arm9v2_board/games.py --name v5-assoc-original-games \
  --fixtures "$NGAGE_FIXTURES" --leg arm9v2=v5-assoc-original-spmark --workers 3
python3 -B tests/cpu/arm9v2_board/games.py --name v5-assoc-original-sega \
  --fixtures "$NGAGE_FIXTURES" --leg arm9v2=v5-assoc-original-spmark --sega-scan-only --workers 6
python3 -B tests/cpu/ngage2_compare/jpeg.py --cpu arm9v2 --name v5-assoc-original-jpeg \
  --jpeg "$NGAGE_FIXTURES/spmark_payload/local/TEST.JPG"
ARM9V2_ASSOC_WAYS=2 sh tests/cpu/arm9v2_board/run-contract.sh v5-assoc-production-directed-b
```

Run the generated candidates from the same checkout.

```sh
sh tests/cpu/arm9v2_board/run-associativity.sh line
sh tests/cpu/arm9v2_board/run-associativity.sh half
sh tests/cpu/arm9v2_board/run-associativity.sh packed 2
python3 -B tests/cpu/arm9v2_board/associativity_scorecard.py
```

Pass `--qualify-only` after the mode to replay the cache, maintenance and
bus contracts alone. A list of way counts after the mode or qualification
flag selects individual geometries. The exact guest programs, simulator
logs and source snapshots are under `build/sim/`. The generated
Verilog and launch logs are under `build/arm9v2-assoc/`.

[Experiment plan](arm9v2-associativity-plan.md) ·
[Raw counter records](evidence/arm9v2-associativity-20261118.json).
