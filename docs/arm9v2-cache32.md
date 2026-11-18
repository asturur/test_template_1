# v5 with 16 KiB I/D caches and 32-byte refills

The v5 phone build now matches v4's capacity and line size: 16 KiB each for
I-cache and D-cache, with 32-byte lines. It retains ARM9V2's two ways and
native execution, translation and write policies. The pinned ngage2 source
is `a182204f87642d434bce5a27bacfda602c505192`. Its original geometry is
16 KiB I, 8 KiB D, two ways and 16-byte lines. The v4 comparison uses exact
master `a2c5863b1c01600ea1b0286097509ed0b401f772`.

The generated v5 netlist reports cache type `0514a14a`. Indexed D-cache
maintenance can address all 256 sets per way. The CPU presents aligned, linear eight-word read
bursts to the wrapper. The wrapper sends one request through the same line
path v4 uses, then returns each complete 32-bit word in order. SDRAM supplies
16 halfwords, and the board's DDR path supplies four 64-bit beats. Only
SDRAM and supported ROM array regions are eligible. Rejected offers replay
through the scalar route. Scalar MMIO, table walks and writebacks use the
existing word path. The accepted burst finishes before a younger SWP can
claim the external lock.

The board's supported line endpoints provide no physical error signal.
Synthetic line errors exercise the donor instruction cache's precise abort
path. Cacheable D-side external ERR retains the donor's per-word completion
behavior. Scalar external data aborts and MMU faults keep their existing path.

## Checked comparison

Each cell contains median CPU clocks at `0:0 / 2:9` added I:D waits. All
comparisons use the same original guest work, output and guard checks, two
warmups, five scored windows, matching repeats and wrong-output controls.
The original donor column runs the unmodified QIP-selected artifact read
from ngage2. It uses the established model for its native 16-byte bursts.
Resized v5 and v4 use the same 32-byte SDRAM line responder. The previous
v5 column is the archived scalar comparison. These models differ in
transfer framing and model memory service at equal CPU clocks.

| Fixed work | v4 | Original ngage2 | Previous v5 | Resized v5 |
| --- | ---: | ---: | ---: | ---: | ---: |
| SPMark matrix ×16 | 41,667 / 41,667 | 23,675 / 35,925 | 20,992 / 47,637 | 17,437 / 17,793 |
| SPMark transpose ×32 | 3,560 / 3,560 | 1,910 / 3,484 | 1,906 / 3,484 | 1,899 / 2,583 |
| SPMark triangle edges ×16 | 23,120 / 23,120 | 12,634 / 13,844 | 12,634 / 13,844 | 12,634 / 13,430 |
| SPMark/GLES 36,608-pixel frame fill | 71,259 / 201,302 | 105,069 / 275,892 | 77,605 / 371,988 | 92,612 / 237,167 |
| SPMark/GLES 1,023-pixel halfword tail | 1,332 / 1,332 | 707 / 760 | 707 / 760 | 707 / 724 |
| SPMark/GLES 2,051-byte tail | 1,647 / 1,647 | 717 / 743 | 717 / 743 | 716 / 727 |
| SPMark Thumb JPEG, 8×8 | 82,943 / 82,943 | 36,251 / 36,631 | 36,158 / 36,991 | 35,913 / 35,921 |
| Monkey Ball forward span | 31,103 / 31,103 | 16,875 / 17,173 | 16,692 / 17,882 | 16,413 / 16,424 |
| Monkey Ball reverse span | 31,058 / 31,058 | 16,608 / 16,759 | 16,530 / 17,032 | 16,413 / 16,424 |
| Sega Rally textured span | 32,908 / 32,908 | 15,990 / 16,143 | 15,965 / 16,237 | 15,912 / 15,932 |
| Sega Rally solid fill | 9,311 / 9,311 | 2,596 / 2,628 | 2,596 / 2,628 | 2,596 / 2,616 |
| Sega Rally full screen with native FbsCli | 8,290,663 / 8,422,080 | 3,471,563 / 4,503,455 | 3,426,522 / 4,677,108 | 3,461,218 / 4,502,989 |
| Asphalt table loop | 41,169 / 41,169 | 22,524 / 23,991 | 21,806 / 24,385 | 21,717 / 22,005 |
| Asphalt double lookup | 18,441 / 18,441 | 12,960 / 15,472 | 12,639 / 17,415 | 12,392 / 12,644 |
| Asphalt single lookup | 12,731 / 12,731 | 8,332 / 8,657 | 8,287 / 8,908 | 8,250 / 8,269 |

The six-kernel SPMark throughput geometric mean is **1.736× / 1.643×**
against v4, **1.076× / 1.232×** against original ngage2, and
**1.002× / 1.358×** against previous v5. The seven short game loops average
1.972× / 1.959× against v4. At `2:9`, the full Sega scan is 1.870× against
v4 and within 0.02% of original ngage2. This table measures fixed work at
the same clock. Native scores, game FPS and routed frequency remain open.

## Geometry and transport effects

- **Matrix.** The previous v5 incurred 694 line fills and 1,280 writes in
  the first scored delayed window. The new geometry removes those fills
  and writes. It still sends 96 scalar reads. Disabling the burst adapter
  on the resized CPU leaves both matrix scores unchanged at 17,437/17,793.
- **Frame fill.** The resized cache with scalar service takes
  63,370/356,202 clocks. Enabling the 32-byte bursts changes that to
  92,612/237,167. At `2:9`, the same 18,319 read words and 16,256 writes
  are serviced as 2,288 32-byte fills and seven scalar reads, saving
  119,035 clocks. At `0:0` the synthetic scalar bus can return one word
  per clock, while the line peer supplies one halfword per clock. The
  delayed burst result still takes 17.8% more clocks than v4's frame fill.

## Verification

The directed RTL guest read-allocates and dirties 512 separate 32-byte lines,
then reads every value back with zero external RAM reads during the measured
resident pass. It also verifies indexed maintenance in the upper half of the
sets, CP15 geometry, SWPB ownership and byte lanes, precise instruction abort
on an incomplete line, external and translation data faults, IRQ/FIQ, and
dirty clean-through to backing RAM. It passed at both waits with narrow RAM
and wide ROM delivery (514 RAM and 18 ROM line starts per trial). Both waits
also passed with forced rejection of all 532 burst offers and scalar replay.
The early capacity fixture warmed via stores and observed the donor's posted
write-miss path. Read allocation before dirtying made the test exercise
physical cache residency.

The 78 MHz pin-model firmware smoke passed 40 million clocks with 954,650
scalar transactions, 725 ROM bursts, zero RAM bursts in that boot interval
and zero data-bus errors. The standalone SDRAM controller regression checks
actual 32-byte RAM bursts, short reads, concurrent banks and the forwarded
clock at 78 and 104 MHz. All 12 configurations passed. The separate
factory firmware simulation uses the production DDR flash route and modeled
SDRAM backing memory. At the production 78 MHz and 64 Hz NOS settings it
cleared the ROM digest and entered the kernel by 260 million clocks, then
completed 400 million clocks with a valid Nokia startup logo and zero
data-bus errors. The checkpoint pair and framebuffer are retained.

## Replay

Use the [existing replay commands](../tests/cpu/arm9v2_board/README.md). Select
`--cpu ngage2` without `--scalar-refills` for the original donor column, and
use `--cpu arm9v2 --scalar-refills` to compare the same resized cache using
scalar service. The [machine evidence](evidence/arm9v2-cache32-20261118.json)
contains the input hashes and all timing windows. The [previous v5 report](arm9v2-phone.md)
covers the original cache geometry and its Quartus fit.
