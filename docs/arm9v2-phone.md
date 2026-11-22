# Stock ARM9V2 on the NEM-4 board

This report archives the stock-geometry experiment at `af7909d` and `1b48db8`.
The current branch configuration and updated comparison are in
[the 32-byte refill report](arm9v2-cache32.md).

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

## Resolve A forwarding before writeback completion

At 104 MHz on `c90ea0f`, seed 42's slow 100 °C path ran from W's
alignment flag through D-cache acknowledgement, writeback completion,
the next producer masks, and A's operand priority encoder to its grant
register. The path missed setup by 2.856 ns. Seed 43 had a related path
from D-cache state through completion and the held-A match mask, with
2.734 ns of negative slack.

Execute now prepares A-entry and held-A matches for three outcomes in
parallel. M and W can stay in place, the next records can promote into
both slots, or W can retire while M stays. Each candidate resolves writer
masks and lane priority independently of writeback completion. Completion
selects the finished result. A retains the same newest-writer priority,
block base, and load-wait behavior on the existing pipeline edge.
Simulation assertions compare both the accepted and held A matches and
grants to the original equations on every relevant edge.

The four CPU contract groups and the directed alignment-abort replay
match the parent at both scalar wait settings, with and without line
transport. At physical 104 MHz the 15 fixed payloads and four native
PolyCount frames match the parent cycle for cycle. PolyCount completes
in 57,514,786 clocks with the same rendered output.

## Fetch queue backing RAM

The 104 MHz round-three fits place the fetch block's payload storage in
logic. The fetch block alone uses 853–858 ALMs and 1,209–1,211 registers.
The two M10Ks reported under fetch belong to its branch predictor.

The eight-entry queue keeps the head register that feeds decode. On each
clock, synchronous RAM prefetches the packet behind the next head. A pop
can copy that packet to the head register on the original edge. An empty
queue and a one-entry pop with a simultaneous push still take the new
packet directly. If a push writes the prefetched slot, the saved push
data supplies the next packet independently of RAM read-during-write
behavior. Pending-fill and fault bits stay in registers so a single fill
completion can update several entries.

The queue requests M10K storage for its 112-bit payload per slot. The
register implementation remains available for the comparison test. Run
the test with `sh tests/cpu/arm9v2_board/run-fetch-ram.sh fresh-fetch-ram`.
It compares 8,504 cycles, including full queues, wraparound, prefetch
collisions, faults, retries, and stalled redirects.

The 15 fixed workloads, four native PolyCount frames, 12 CPU contract
modes and mixed LCD, MMC and PCM pin replay match `6c569de` cycle for
cycle. The native replay completes in 57,514,786 clocks with the same
output. Quartus fits will verify the physical memory mapping and timing.

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
| Sega Rally full-screen scan with native FbsCli, 36,608 pixels | 8,290,663 / 8,422,080 | 3,426,522 / 4,677,108 |
| Asphalt table, 512 pixels visited | 41,169 / 41,169 | 21,806 / 24,385 |
| Asphalt double lookup, 512 pixels visited | 18,441 / 18,441 | 12,639 / 17,415 |
| Asphalt single lookup, 512 pixels visited | 12,731 / 12,731 | 8,287 / 8,908 |

The six-kernel SPMark throughput geometric mean is 1.732× / 1.210× at
equal clocks. JPEG is a separate 2.294× / 2.242×. The seven game-loop mean is
1.956× / 1.787×. Game timing includes the same marker, entry and return shims on
all three CPUs. The JPEG check accounts for the donor's separate Thumb BL
suffix retirements and checks the full scored payload PC histogram.

Sega Rally's full-screen scan is 2.419× / 1.801× faster. It independently
checks both guarded buffers, the bitmap cursor, stack and the 18,316 pixels
selected for writes. The original FbsCli `IncXPos` and `SetPixel` routines
execute with an independently initialized bitmap cursor. In the delayed
profile, the first scored donor window has 143,517 read words and 13,344
write words. Mainline has 33,288 read words and 10,366 write words in that
window, including its 32-byte fills. The smaller donor D-cache puts more
work on the memory bus even though this kernel still spends fewer clocks.

At `2:9` the matrix has 694 donor read fills (2,776 words), 94 other reads
and 1,280 writes in the first scored window. The mainline matrix sends zero
external requests in that window. For the frame fill the donor reads 18,315
words and writes 17,280. Mainline reads zero words and writes 18,295, then
takes another 105 clocks and ten writes to empty the buffer. Asphalt's double
lookup generates 502 read words and 360 writes with the donor, versus zero
external requests on the mainline. That drops its speedup from 1.459× at
`0:0` to 1.059× at `2:9`. These counts measure traffic and wait sensitivity.
They cannot determine physical SDRAM latency or overlap from synthetic waits.

The same standalone donor also passed the earlier 16-bit burst-responder
contract with early instruction delivery enabled. At `2:9`, matrix drops
from 47,637 to 35,925 clocks and full-frame fill from 371,988 to 275,892.
At `0:0` burst framing adds transfer clocks and moves those cases in the
opposite direction, to 23,675 and 105,069. This comparison changes service
framing and the early delivery guarantee together. The results motivate a
donor-width board refill path that preserves late fault handling.

The PLL setting is 78 MHz, and 104 MHz is the routed-analysis target. For
example, 36,991 clocks corresponds to 474 µs at 78 MHz or 356 µs at 104 MHz.
The reported phone index of about 224 already includes 104 MHz. Reaching 500
at the same clock would require 2.23× throughput on the actual measured workload.
The timing tables cover fixed work. Official SPMark04 scores and full-game
FPS remain open.

## Board checks and firmware

The focused RTL test uses the production scalar memory route, registered UPP
bridge and request stage. At both zero and five added wait clocks, the guest
checks CP15 ID and cache type, SWPB byte lanes and uninterrupted lock,
IRQ/FIQ entry and return, MMU activation, external and section translation
data aborts with FSR/FAR, dirty clean-by-MVA through to backing RAM, invalidate
and reload, and a prefetch abort on the third word of a line after two good
words. The faulting virtual address never reaches the physical device bus.
Both runs observe two failed fill attempts and one architectural prefetch
abort. Total/pending-bus clocks are 1,101/475 and 2,090/1,539 at the two delays.
The early fixture assumed one fault packet and placed the completion mailbox
descriptor at the wrong offset. Both corrections were confined to the fixture.

A separate 78 MHz, five-million-clock firmware test used the actual
`jtframe_sdram64` controller, SDRAM adapter, forwarded clock and local SDRAM
chip model. It passed with 5,588 transactions, three discarded instruction
bus errors and zero data bus errors. The test reached the first LCD command
and ended in the startup delay loop. This bounded test uses the harness's
legacy DDR model on the flash side.

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

The donor continued from its own checkpoints, initialized the LCD and passed
the factory ROM digest. It reached kernel code by 290 million clocks and
exercised timer, ICU, NOS, UEM, SIM and MDI register traffic. The Nokia startup
logo was visible by 400 million clocks. At 700 million the display had a valid
frame, 36,689 pixel words and the same logo. The trace had three discarded
pre-MMU instruction bus errors, zero data bus errors and a sticky unsupported
LCD command flag from the [modeled panel's initialization traffic](lcd-command-evidence.md).
The cold comparison used a 1 kHz NOS timer. A separate cold donor boot used
the production 64 Hz setting, reached the LCD DMA registers at 988,370,634
clocks and completed the billion-clock run with zero data bus errors and
three discarded instruction bus errors. The retained checkpoint pair still
shows the Nokia startup logo. Interactive home-screen completion and
physical qualification remain open.

## Quartus fit

Quartus 17.0.2 fitted `af7909d` with seed 42 and DDR debugger enabled.
Compilation, effective-source verification, routed analysis, all 16 SDRAM
DQ register checks and upload passed. The timing gate failed. The branch has
132 selected files. Among the 131 shared paths, only `files.qip` and the
CPU wrapper differ. The 47 reference CPU inputs give way to the selected
donor netlist. The board source hashes, effective QSF, physical 78 MHz PLL
and production BRAM match the banked third-slot reference.
[ARM9V2 run](https://github.com/asturur/test_template_1/actions/runs/44273812397) ·
[Mainline run](https://github.com/asturur/test_template_1/actions/runs/44258633306).

| Metric | Mainline | ARM9V2 | Change |
| --- | ---: | ---: | ---: |
| ALMs | 37,529 | 35,362 | −2,167 |
| Occupied LABs | 4,165 | 4,093 | −72 |
| Registers | 42,138 | 40,035 | −2,103 |
| M10Ks | 514 | 411 | −103 |
| DSPs | 41 | 41 | 0 |
| Worst 78 MHz setup | −0.743 ns | −1.371 ns | −0.628 ns |
| Worst 104 MHz analysis setup | −3.948 ns | −4.576 ns | −0.628 ns |

The worst path runs from the donor bus merger's registered address bit 25
to the DDR debugger snapshot BRAM. At the worst corner it takes 13.474 ns
across 11 levels. The export also shows a −0.831 ns internal path from the
donor TLB check into execute at 78 MHz. Worst hold is +0.099 ns, and 104 MHz
recovery slack reaches −0.465 ns. The generated 4,304,336-byte RBF is archived
with this timing result. SHA-256
`86ffc8d565d4a4e2f4d192daf6c05b816af3f585c50ee9a583462a1d8adbfaf9`.

## Recommendation

Keep ARM9V2 as the second CPU candidate. Its execution advantage survives
the board wrapper and helps all measured game loops, including the native
Sega scan. Memory traffic limits the gain in the delayed profile. The next
measurements should price native 16-byte bursts through the real memory
ports, then test donor D-cache capacity and write-allocation behavior against
matrix and full-frame fill at the same clock and with the same checks.
The fit leaves 98 LABs and 142 M10Ks free. Timing work should address the
board observation path and measure the remaining native TLB-to-execute path.

## Replay

Use new run names and the original local inputs. An example sequence is in
[the test notes](../tests/cpu/arm9v2_board/README.md). All clocks, windows,
input identities and initial boot receipts are in the
[machine-readable evidence](evidence/arm9v2-phone-20261118.json).
