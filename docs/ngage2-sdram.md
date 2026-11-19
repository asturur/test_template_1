# v5 phone RAM on ngage2's SDRAM controller

Phone RAM is served by ngage2's open-row SDRAM controller
(`rtl/sdram/ngage2_sdram.sv`, from ngage2 `f74148c`) behind
`rtl/ngage_sdram_fast.v`, which keeps the request and line ports of
`ngage_sdram_adapter`. `jtframe_sdram64` and the old adapter are no longer in
`files.qip`; their sources and unit tests remain. The clock counts are
simulation and the timing is one fit. On a board the fit has booted the stock
firmware to the Nokia logo and no further (see Limits).

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
- Board: one DE10-Nano, the seed-43 fit with the 64 KiB flash cache,
  unchanged `nem440.3c1` and `nem440.326`, erased C: and PMM images, the
  SPMark04 card in slot 2. The Nokia logo appears and stays. `8546db1`'s CI
  RBF does the same on that board with the same files, and the two captures
  are byte-identical. Neither build passes the logo from an erased C:, the
  stop [symbian-startup.md](symbian-startup.md) records.

## Limits

- On hardware only as far as the Nokia logo. The menu, SPMark04 and games
  have not run on this change: they need an initialized C: and PMM. ngage2
  runs this controller at 104 MHz on DE10-Nano SDRAM modules, and its 78 MHz
  build ran a full SPMark04 pass on the board used here.
- The capture point is fixed in clocks. At 78 MHz the rising edge three
  clocks after READ lies about 0.6 ns before the worst-case end of the chip's
  data window by the controller's own bound (its header, with 4.5 to 7 ns of
  board and I/O delay); at 104 MHz it is centred with 1.4 ns either side.
- The simulation models that delay by sampling the chip model's output at
  the falling edge before the capture edge. It checks protocol and data, not
  board timing.
