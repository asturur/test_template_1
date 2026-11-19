# v5 phone RAM on ngage2's SDRAM controller

Phone RAM is served by ngage2's open-row SDRAM controller
(`rtl/sdram/ngage2_sdram.sv`, from ngage2 `f74148c`) behind
`rtl/ngage_sdram_fast.v`, which keeps the request and line ports of
`ngage_sdram_adapter`. `jtframe_sdram64` and the old adapter are no longer in
`files.qip`; their sources and unit tests remain. The clock counts are
simulation and the timing is one fit. On a board the fit boots the stock
firmware from a blank C: to the menu and completes SPMark04, 1 to 15 %
faster than `8546db1` with both changes (3D Game +11 %; see On a board).

## Why

A whole-board trace of the previous path (`tests/phone/membench`, 78 MHz)
shows what one posted word store costs: 13 clocks from the arbiter's grant to
the next grant, of which two are WRITE commands. The rest is handshaking: one
clock into the arbiter, one into the adapter, four from request to command in
the controller, three to `rdy`, then response, acknowledge and release. A
scalar read takes 11 clocks to its acknowledge. Store misses are posted to the
bus one word (or halfword) at a time, so fills and copy destinations pay this
on every store, and a dirty 32-byte line costs eight of them on eviction.

ngage2's controller keeps one row open per bank. A word write to an open row
is two WRITE commands and the next request is taken three clocks after it; a
word read returns its word five clocks after the request.

## What changed

- `ngage_sdram_fast` hands scalar requests to the controller as they are
  presented. A write is acknowledged in the clock after the controller takes
  it; a read when its word arrives. The cold-start scrub writes 16 bytes a
  request. `phone_reset` drops the answer of the operation in flight and
  `owner_ready` stays low until it has drained, as before.
- The controller copy has one addition, `line32`: a 32-byte read as two
  chained 8-halfword bursts, the second READ eight clocks after the first, so
  the sixteen halfwords follow each other. Without it a 32-byte line is two
  separate requests and line reads are about 10 % slower than before.
- Refresh is the controller's own; `REFRESH_PERIOD` and `rfsh` are gone.
- `Template.sv` drives `SDRAM_DQ` from `sdram_dq_o`/`sdram_dq_oe`. The clock
  forwarding (`ngage_sdram_clock`) is unchanged. Read data is captured in the
  DQ input registers on rising edges, `CAS + 1` clocks after the READ edge.

## Measured, 78 MHz

`sh tests/phone/membench/run.sh` before (`8546db1`) and after; CPU clocks of
each loop's second run. Loops that do not touch SDRAM are unchanged.

| Loop | Before | After | Change |
| --- | ---: | ---: | ---: |
| `wrw`, 16,384 word stores | 214,814 | 65,605 | −69 % |
| `fill16`, 36,608 halfword stores | 479,675 | 112,114 | −77 % |
| `copy`, 64 KiB by LDM/STM | 297,476 | 144,907 | −51 % |
| `rmw`, load, add, store back | 256,274 | 164,040 | −36 % |
| `uncw`, 2,048 unbuffered stores | 37,244 | 16,541 | −56 % |
| `unc`, 2,048 uncached loads | 39,271 | 33,187 | −15 % |
| `tlbs`, small-page walks | 176,253 | 127,170 | −28 % |
| `seq`, 4,096 line fills | 144,470 | 141,053 | −2 % |
| `row` / `list`, a new row each fill | 139,896 | 133,746 | −4 % |
| `tex`, textured span, 36,608 pixels | 961,169 | 921,882 | −4 % |
| `rcode96`, 96 KiB of code in RAM | 359,544 | 346,971 | −3 % |
| All 31 loops, ms at 78 MHz | 70.8 | 59.0 | −17 % |

The same guest on ngage2's whole-core bench (104 MHz, 16 KiB I, 8 KiB D)
takes 47.8 ms. The register-only loops take the same clocks on both cores,
so v5 is 1.33 times slower there by its clock alone.

For scale, ngage2 itself at both clocks on one DE10-Nano, SPMark04 Run Set
with all nine tests, one pass each (QD firmware 4.10, so the figures show
what the clock is worth and are no forecast for NEM-4): the 78 MHz build of
its `test-78` branch gives 3D Game 6.65 fps, FillRate 1.27 Mtexels/s and
PolyCount 21.47 Ktriangles/s against 8.88, 1.73 and 28.41 at 104 MHz
(`f74148c`), 0.73 to 0.76 of the faster build.

## On a board

One DE10-Nano, unchanged `nem440.3c1` and `nem440.326`, each run a first boot
from an erased C: with a PMM whose AUX startup reason record is 105 (the
stock firmware then formats C: itself), the SPMark04 card cold-mounted, the
images in the MiSTer's RAM disk, Background save Off. SPMark04 Run Set,
Custom, all nine tests, one pass per build; the figures are from the
`Result.txt` the phone saves on the card.

| Test | `8546db1` (CI run 44419903846) | This change | With the 64 KiB flash cache |
| --- | ---: | ---: | ---: |
| 3D Game, fps | 5.79 | 6.42 | 6.43 |
| 3D FillRate, Mtexels/s | 1.13 | 1.20 | 1.27 |
| 3D PolyCount, Ktriangles/s | 18.96 | 20.76 | 20.84 |
| 2D Image, fps | 27.86 | 29.43 | 29.54 |
| Image Scaling, bitmaps/s | 1.29 | 1.32 | 1.34 |
| JPEG Encoding, Kpixels/s | 122.19 | 123.61 | 123.65 |
| Contacts, contacts/s | 2.48 | 2.67 | 2.71 |
| Calendar, events/s | 5.11 | 5.40 | 5.54 |
| Disk Access, files/s | 13.53 | 15.02 | 15.53 |

All three are seed-43 fits. A second pass of `8546db1` gave 5.79, 1.13,
19.06, 27.68, 1.29, 121.85, 2.49, 5.10 and 13.68, so a pass repeats within
about 1 %. FillRate is counted in whole seconds and moves in steps of about
0.07. On the same board ngage2's 78 MHz build gives 6.65, 1.27, 21.47,
30.88, 1.42, 125.15, 2.92, 5.57 and 16.33 (QD firmware 4.10).

The Time dialog appeared 75 s after the core load on `8546db1` and 68 s with
both changes; the nine tests took about 250 s and 239 s.

## Fit

Quartus 17.0.2, seed 43, DDR debugger off, PLL 78 MHz, the CI flow's
`quartus_sh --flow compile Template` on a local server (not a CI run).

| | `8546db1` (CI run 44419903846) | This change |
| --- | ---: | ---: |
| Worst setup, slow 100C / −40C | −0.185 ns (worst corner) | +0.586 / +0.432 ns |
| Worst hold, slow 100C | +0.248 ns | +0.243 ns |
| ALMs | 36,309 | 36,249 |
| M10K | 437 | 437 |

`tools/check_quartus_timing.py` and `tools/check_sdram_io_registers.py` pass
on this fit's reports: all 16 DQ pins keep their input, output and enable
registers in the I/O cells. Over all four corners the worst hold slack is
+0.113 ns (fast −40C). The previous worst path was inside
`jtframe_sdram64` (13.25 ns); the worst paths are now from the D-side TLB
check into the bus merger and from the merger into the peripheral bridge.

With the PLL, `SYS_CLK_HZ` and `MMC_CLK_DIV` (4) set for 104 MHz the same seed gives
−3.408 ns on `8546db1` and −3.530 ns with this change, so the SDRAM
controller is not what holds the clock. The worst chain in both is the
CPU's bus address through `ngage_arm9v2_refill.line_target`,
`ngage_sdram_arbiter.choose_cpu` and the bridge's `bus_cyc` into
`ngage_dma_channels.start_request` and a DMA engine's `source_left`
(12.4 ns, 11 levels); CPU-internal paths sit near −3.0 ns at that target.

## Verification

- `tests/phone/sdram_fast/run.sh`: the service against the SDRAM chip model
  at 78 and 104 MHz: 23,949 scalar writes with random byte lanes, 7,295 scalar
  reads, 7,034 line reads and 154 reads dropped by `phone_reset`, checked
  against a shadow memory. The model reports no timing violation.
- `tests/phone/membench/run.sh`: `memtest` (word, byte and halfword stores,
  cached and uncached, dirty lines written back on eviction, line reads of
  known data) and all 31 `membench` loops on the whole board, zero bus errors.
- `tests/phone/hardware_boot/run-real-sdram.sh`, its Verilator command run
  outside the container with the production settings (78 MHz, line refills,
  short reads), the audited 4.03 core and extension images and an erased C:.
  It passes its 5M-clock bound, and a 400M-clock run ends with
  `bus=4845138 errors=3 data_errors=0 lcd_words=18353 ram_lines=72474
  rom_lines=1586246` at PC `514af610`: 72,474 RAM line reads through the
  new service and 18,353 writes to the LCD data register.
- Board: both seed-43 fits boot from an erased C: to the Time dialog, the
  idle screen and Menu, and complete SPMark04 (On a board). With an erased
  PMM as well they stop after the logo exactly as `8546db1` does, the stop
  [symbian-startup.md](symbian-startup.md) records.

## Limits

- One board and one SPMark04 pass per build. Games, MMC writes and
  Background save have not run on this change. ngage2 runs this controller
  at 104 MHz on DE10-Nano SDRAM modules.
- The capture point is fixed in clocks. At 78 MHz the rising edge three
  clocks after READ lies about 0.6 ns before the worst-case end of the chip's
  data window by the controller's own bound (its header, with 4.5 to 7 ns of
  board and I/O delay); at 104 MHz it is centred with 1.4 ns either side.
- The simulation models that delay by sampling the chip model's output at
  the falling edge before the capture edge. It checks protocol and data, not
  board timing.
