# Stock ARM9V2 on the NEM-4 board

`ngage-v5` starts from `a2c5863b1c01600ea1b0286097509ed0b401f772`. Its normal
`Template` project selects ngage2's full ARM925T subsystem at
`a182204f87642d434bce5a27bacfda602c505192`. The donor's Quartus QIP selects
`rtl/cpu/arm925t_gen.v`, SHA-256
`087714b2a692fb949bf8a0586674742118383eb18452f1357c4b4e786a69ab4c`.
The standalone comparison runs that artifact directly. It is newer than the
`23541bb` donor in the earlier 5C comparison.

The donor uses its stock branch predictor, TI CP15 ID `54029252`, cache type
`05109149`, low reset vectors, separate 16 KiB I and 8 KiB D caches, two ways
and 16-byte lines. D-cache uses write allocation on cacheable misses and
dirty writeback. The donor keeps its native translation and CP15 maintenance
logic, including two-way, 256-set small-page TLBs on I and D.

The generated phone netlist adds ports for the registered merger owner, full
cycle type, SWP ownership and existing fetch observations. Word responses go
through the existing NEM-4 SDRAM route or peripheral bridge. Each donor refill
is four individually serviced words and may wrap within its 16-byte line.
`bus_no_late_error` is low because a later word can fail on the board. The
fixed-size 32-byte refill channel is idle in this configuration. A SWP holds
the board lock while the instruction owns the W stage, including the gaps
between its memory operations. Firmware, board clocks, SDRAM, flash, peripheral
and DMA modules come from the base checkout. The old CPU is available for
simulation controls via `--cpu zap`.

Corresponding donor sources, notices, generation recipe and simulation-only
vendor primitive models are in [the pinned import](../rtl/arm9v2/upstream).
`python3 tools/gen_arm9v2_phone.py --stock /path/to/arm925t_gen.v --check`
reconstructs the wrapper-facing netlist byte for byte from the pinned artifact.
Omit `--stock` to regenerate from the included SystemVerilog using sv2v 0.0.13.
The imported source and generated source use the donor's formatting.

## Fixed-work results

Each cell is the median CPU clocks at extra I:D waits `0:0 / 2:9`.
Mainline uses its existing synthetic line transport. Both donor legs use the
same per-word scalar responder with unsafe early refill delivery disabled and
address-region wait selection. These timings exclude the board's device and
SDRAM service costs. All three configurations use the same guests and pass
independent output and guard checks, two warmups, five scored windows, two
repeats and deliberate wrong-output rejection. The standalone donor matches
all integrated donor window records. That establishes zero cycles of wrapper
overhead with the same responder and separates the bridge, arbitration and
memory service costs in the full-board run.

| Work | Mainline `a2c5863` | Phone ARM9V2 and standalone |
| --- | ---: | ---: |
| SPMark matrix ×16 | 41,667 / 41,667 | 20,992 / 47,637 |
| SPMark transpose ×32 | 3,560 / 3,560 | 1,906 / 3,484 |
| SPMark triangle edges ×16 | 23,120 / 23,120 | 12,634 / 13,844 |
| SPMark/GLES frame fill, 36,608 pixels | 71,259 / 201,302 | 77,605 / 371,988 |
| SPMark/GLES halfword tail, 1,023 pixels | 1,332 / 1,332 | 707 / 760 |
| SPMark/GLES byte tail, 2,051 bytes | 1,647 / 1,647 | 717 / 743 |
| SPMark Thumb JPEG, 8×8 | 82,943 / 82,943 | 36,158 / 36,991 |
| Monkey Ball forward span, 512 pixels | 31,103 / 31,103 | 16,692 / 17,882 |
| Monkey Ball reverse span, 512 pixels | 31,058 / 31,058 | 16,530 / 17,032 |
| Sega Rally textured span, 512 pixels | 32,908 / 32,908 | 15,965 / 16,237 |
| Sega Rally solid fill, 512 pixels | 9,311 / 9,311 | 2,596 / 2,628 |
| Asphalt table, 512 pixels visited | 41,169 / 41,169 | 21,806 / 24,385 |
| Asphalt double lookup, 512 pixels visited | 18,441 / 18,441 | 12,639 / 17,415 |
| Asphalt single lookup, 512 pixels visited | 12,731 / 12,731 | 8,287 / 8,908 |

The six-kernel SPMark throughput geometric mean is 1.732× / 1.210× at
equal clocks. JPEG is a separate 2.294× / 2.242×. The seven game-loop mean is
1.956× / 1.787×. Game timing includes the same marker, entry and return shims on
all three CPUs. The JPEG check accounts for the donor's separate Thumb BL
suffix retirements and checks the full scored payload PC histogram.

At `2:9` the matrix has 694 donor read fills (2,776 words), 94 other reads
and 1,280 writes in the first scored window. The mainline matrix sends zero
external requests in that window. For the frame fill the donor reads 18,315
words and writes 17,280. Mainline reads zero words and writes 18,295, then
takes another 105 clocks and ten writes to empty the buffer. Asphalt's double
lookup generates 502 read words and 360 writes with the donor, versus zero
external requests on the mainline. That drops its speedup from 1.459× at
`0:0` to 1.059× at `2:9`. These counts measure traffic and wait sensitivity.
They cannot determine physical SDRAM latency or overlap from synthetic waits.

The PLL setting is 78 MHz, and 104 MHz is the routed-analysis target. For
example, 36,991 clocks corresponds to 474 µs at 78 MHz or 356 µs at 104 MHz.
The reported phone index of about 224 already includes 104 MHz. Reaching 500
at the same clock would require 2.23× throughput on the actual measured workload.
The timing tables cover kernels. Official SPMark04 scores, full-game FPS and
the performance of Sega Rally's full-screen native FbsCli path remain open.

## Board checks and firmware

The focused RTL test uses the production scalar memory route, registered UPP
bridge and request stage. At both zero and five added wait clocks, the guest
checks SWPB byte lanes and uninterrupted lock, external data abort FSR/FAR,
IRQ/FIQ entry and return, MMU activation, dirty clean-by-MVA through to backing
RAM, invalidate and reload, and a prefetch abort on the third word of a line
after two good words. The test observes two failed fill attempts and the
guest reaches the abort handler. Total/pending-bus clocks are 941/411 and
1,778/1,315 at the two delays. The early fixture assumed one fault packet and
placed the completion mailbox descriptor at the wrong offset. Both fixture
errors were corrected without changing the CPU.

Matched cold five-million-clock boots used unmodified factory core and
extension, freshly formatted 4 MiB C:, normal power-up, the production DDR
flash path, direct SDRAM, 78 MHz CPU and 26 MHz timer enable. The harness
uses modeled backing memories and the HDL phone peripherals. The first LCD
write reached the same register and value at 55,548 donor clocks and 97,877
mainline clocks. Both then executed the same startup delay loop. The first
apparent mismatch in the bounded retirement logs is the `MCR p15` at `0x2e28`,
which the donor observer includes and ZAP's ordinary-retirement observer omits.
Both reached LCD and RAM with zero data bus errors. The pre-MMU speculative
instruction reads that raised board errors were discarded by both pipelines.

The donor continued from its own checkpoint, initialized the LCD and passed
the factory ROM digest. It reached kernel code by 290 million clocks and
exercised timer, ICU, NOS, UEM, SIM and MDI register traffic. It was still
progressing through application/UI startup at the 380-million-clock sample.
The continuation beyond that point and physical qualification are pending.

## Replay

Use new run names and the original local inputs. An example sequence is in
[the test notes](../tests/cpu/arm9v2_board/README.md). All clocks, windows,
input identities and initial boot receipts are in the
[machine-readable evidence](evidence/arm9v2-phone-20261118.json).
