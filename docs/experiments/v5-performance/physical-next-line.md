# Next physical SDRAM line census

The V5 pin-level simulation at 104 MHz observes the SDRAM demand stream with
16 KiB I-cache and 16 KiB D-cache. The source is
`b6d89816fb515c2bbd5cd7f868d28c05e42ea654`. The observer does no speculative
reads and changes no bus signal. The earlier [sequential I-line study](fixtures.md#sequential-i-line-opportunity)
uses fetch provenance and measures a different frontend opportunity.

The donor at `ngage2/5473d46` reads a speculative 16-byte physical block after the
16-byte WRAP4 demand, buffers it separately and lets refresh or a new read
cut that speculative tail short. In V5 the SDRAM scheduler uses two 16-byte
BL8 commands to return **one** 32-byte architectural fill. This
census looks for another aligned 32-byte line after that entire fill.
Seeing an adjacent physical address does not imply sequential instruction
flow. A branch or data request can consume the slot after the usual checks.

## Measurement

- Classify each accepted full SDRAM line by the CPU board line handshake's
  instruction/data origin. The physical stream is observed at the adapter
  acceptance, using the offset after board arbitration and address mapping.
  Scalar requests, page walks and DDR line reads do not seed candidates.
- Count when the next accepted full-line demand equals the predecessor
  plus 32 bytes. Reject the last aligned line of a 1 KiB physical SDRAM row
  or the end of the 16 MiB SDRAM aperture as a seed. Report row-crossing
  adjacencies separately.
- Independently replay one physical tag. Seed on the last beat of a
  completed non-hit. An unrelated full-line miss retires the old tag.
  A hit preserves the tag without seeding its successor. Reject a candidate
  when its 32-byte physical range is written by a nonempty posted write or
  an accepted scalar or 16-byte physical write; the canonical offsets
  include mapped CPU aliases. Candidate state starts empty in each timed
  window, including each native frame.
- Count coherent matches with 0, 16, 20 or 24 consecutive baseline idle
  clocks available before the matching demand. An idle clock requires both
  SDRAM controller and adapter ready and no observed CPU, shared DMA,
  LCD fast-interface or PCM request or bus lock. Pending refresh makes
  the controller busy. The counters also report matches with refresh
  due or a foreground request somewhere in their candidate lifetime;
  these events may occur outside the qualifying contiguous interval.
  The aperture count is a subset of row ends if the last SDRAM line is used.

A 32-byte speculative read needs 16 x16 data beats. The 20- and 24-clock
thresholds add margins for command and turnaround sensitivity. They
measure when an uninterrupted slot appears in the original execution.
The largest idle span uses future knowledge, and baseline idleness can
move when a speculative read is added. These scenarios exclude overlap
with returning demand beats and any resumable service. They also exclude
the cost of launching useless read-ahead, forced serialization at burst
boundaries, changes in SDRAM row state or CPU-stall exposure, real hardware
timing and cycle savings. The counters observe the qualified harness's
request mix. Production display and audio traffic can reduce available slots.

## Results

All four native frames matched their baseline counters and output hash.
All 15 fixed workloads matched all 105 timed windows and the recorded
third-window SDRAM request traces.

| Replay and origin → consumer | Full consumer demands | Raw same-row adjacent demands | 0 idle clocks | 16 | 20 | 24 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Native I → I | 691,932 | 426,514 | 251,897 | 11,415 | 11,208 | 10,979 |
| Native D → D | 33,736 | 2,365 | 2,254 | 453 | 442 | 439 |
| Fixed D → D | 48,671 | 18,786 | 11,232 | 4,108 | 3,210 | 3,210 |

There were no fixed-work I-code demands on this interface. Native had 30
immediately adjacent D → I full-line demands and none I → D. At zero
idle clocks the one-entry model permitted 23 D → I and 376 I → D
matches, with neither direction qualifying at 16 clocks or more. Native
had 14,651 raw row-crossing adjacencies, and fixed work had 588. At 24
clocks, native logged 181 physical-write invalidations, including 69
candidates subsequently requested. Of its 11,418 qualifying matches,
1,178 saw pending refresh and 210 saw foreground activity elsewhere in
the candidate lifetime.

At 24 clocks, 1.57% of all native physical line demands matched, and Sega
scan alone provided 3,192 of 3,210 fixed-work matches. The full-frame 16-bit
fill registered 8,008 coherence-checked address matches but only one at
24 clocks. A general read-ahead experiment is a low priority with this
request mix. A narrower D-stream experiment could keep a physical tag
and a staging buffer beside the scheduler, give demand, LCD, PCM and
refresh priority before each BL8, and discard partial data whenever
foreground traffic intervenes. A later checked demand could consume the
buffer once both bursts have completed and no overlapping write has
invalidated it. An active A/B would need to account for useless bursts,
row and refresh effects and delays introduced for other requesters.

## Replay

The [fixture patch](patches/physical-next-line-census-fixture.patch) puts the
observer and scripts in a private scratch area. See
[fixture prerequisites](fixtures.md) for the two checked all-four baseline
decks. Their original Verilator command lines, archived harness instances,
pin model and input images are required. The runners replace the archived
production RTL with the exact pinned V5 files while keeping those inputs
and checking the replay counters.

```sh
python3 docs/experiments/v5-performance/verify.py physical-next-line-census-fixture
git apply docs/experiments/v5-performance/patches/physical-next-line-census-fixture.patch
area=scratch/v5-donor-next-line
mkdir -p "$area/leg"
git archive b6d8981 rtl tests/phone/sdram tests/phone/hardware_boot/d2_measure.vh |
  tar -x -C "$area/leg"
python3 "$area/run.py"
python3 "$area/run_payload.py"
python3 "$area/summarize.py"
```

The native runner checks four per-frame records, completion counters and
the output buffer SHA-256. The fixed runner checks all 105 timed window
records and byte-for-byte SDRAM request traces from the third window of
each case in the prepared baselines. The [result JSON](../../evidence/v5-104-physical-next-line.json)
contains all per-frame counts and summaries per workload.
