## 2026-11-11 timing follow-up

Header/geometry validation is removed from per-pixel admission without another
LCD pipeline stage. Full-frame interval stays130,685 clocks. The generic local
DMA response is now registered: the complete normal/held ARM fixtures are
152,457/152,538 (one clock higher); MMC matrix runtime is unchanged. See
[timing recovery](lcd-dma-timing-recovery.md). Actual PLL stays78 MHz;104 MHz
is the RTL target, and new physical timing remains unverified.

# Production DMA and LCD handover

## 2026-11-19 — 16-byte LCD reads chosen

The v5 top uses 16-byte LCD DMA reads. CPU refills remain 32 bytes.
A 16-byte LCD request uses one BL8 and releases the shared port eight
halfword clocks earlier than a 32-byte request. An aligned full frame
still issues 4,576 physical READ commands at either burst width. The
32-byte path schedules those commands in pairs with less setup between
them, which accounts for its shorter upload.

| Same full-frame replay at 78 MHz | Scalar | 16-byte LCD | 32-byte LCD |
| --- | ---: | ---: | ---: |
| Upload with no competing memory traffic | 148,836 | 69,761 | 53,548 |
| Upload with CPU requests every 24 clocks | 165,251 | 80,419 | 63,487 |
| Worst CPU release-to-response wait, 24-clock interval | 194 | 27 | 43 |
| Upload with CPU requests every 40 clocks | 160,108 | 81,621 | 65,253 |
| Worst CPU release-to-response wait, 40-clock interval | 24 | 25 | 35 |
| Upload alongside 256 competing CPU cache refills | 155,275 | 76,087 | 59,830 |
| Worst CPU cache-refill completion | 46 | 42 | 50 |

The 16-byte mode keeps a 53% upload reduction from scalar and costs
about 0.21 ms per isolated upload relative to 32-byte LCD reads.
It reduces the worst measured CPU response on both contention
profiles relative to 32 bytes. All three widths preserve the
checked framebuffer, DMA IRQ, unaligned heads and tails, cancel/restart,
and concurrent 32-byte CPU refills with SWP lock exclusion.
The top-level RTL elaborates. This measures scheduled contention on
the physical SDRAM model at 78 MHz. The GLES full-frame fill still takes
124,998 CPU clocks. On-board 3DMark FPS remains unmeasured.

[Numbers and source hashes](evidence/lcd-sdram-burst-widths-20261119.json).
Run `sh tests/phone/lcd_stream/run-physical.sh fresh-lcd-widths` to repeat
all three physical simulations.

## 2026-11-19 — SDRAM line reads for LCD DMA

The first burst version gave aligned, in-range LCD uploads access to the same 32-byte
SDRAM read port as CPU cache refills. Each returned line buffers up to
eight words and feeds the existing 32-bit ordered LCD queue. Scalar
reads handle the head and tail of an unaligned upload. Once a line is
accepted it drains through cancellation. The DMA frontend raises
success only after the last pixel leaves the LCD queue.

The line arbiter alternates CPU and LCD line grants when both are
pending. A full LCD burst gives up to two scalar requests an opportunity
before the next LCD line. A CPU lock blocks new LCD admissions. The
scalar window avoids the CPU backlog that appeared when only one
scalar could run between consecutive LCD lines.

| Full-frame test at 78 MHz | Scalar LCD reads | 32-byte LCD reads |
| --- | ---: | ---: |
| LCD alone | 148,836 clocks | 53,548 clocks |
| 1,024 CPU reads released every 24 clocks | 165,251 | 63,487 |
| 1,024 CPU reads released every 40 clocks | 160,108 | 65,253 |
| 256 competing CPU line refills and lock exclusion | 155,275 | 59,830 |

An aligned upload uses 2,288 line requests and 4,576 pin READ commands
instead of 18,304 scalar requests and pin READs. The test programs the
actual DMA registers, checks every returned word and all 18,304 panel
BRAM entries, and waits for the completion IRQ. Unaligned and canceled
then restarted transfers also pass. Under the heavier load, worst CPU
release-to-response latency drops from 194 to 43 clocks as the backlog
clears. Under the lighter load, an already-issued LCD burst can hold the
bus longer, raising worst CPU latency from 24 to 35 clocks. These are
physical-pin simulations with scheduled competing requests. Native game
upload intervals and FPS remain unmeasured.

Run `sh tests/phone/lcd_stream/run-physical.sh fresh-lcd-burst` to repeat
the comparison using the prepared Micron Verilator model.
[Machine-readable upload and contention results](evidence/lcd-sdram-burst-20261119.json).

## Current result

The production MiSTer profile now uses the general DMA frontend for all eight
channels. `GENERAL_DMA=1` is the `ngage_mister` default; eligible SDRAM LCD
descriptors always use the fast stream. The `FAST_LCD` switch is retired.
The former LCD register owner and source-address-derived framebuffer writes
remain available only for explicit legacy comparison fixtures.

LCD transfers with a validated request line, incrementing 32-bit SDRAM source
and fixed 32-bit LCD destination use `ngage_lcd_stream.v`. The stream reads
RAM directly and presents normal LCD FIFO words. It bypasses the per-word
UPP bus write, while the frontend retains count, stop, restart, error and IRQ
ownership. On-chip RAM sources use the general word route. This is an explicit
transaction-level shortcut, not a physical LCD serial-bus model.

The final CPU phase-10, fresh bounded boot, formatter and structural checks
pass. The production-only fast selection also passes a fresh rerun; see the
verification limits below.

## Speed

The matched transport test uses the actual RAM arbiter, identical synthetic
memory delays, no CPU traffic and an always-ready pixel sink. Timing starts at
the first read request and ends at the final pixel/completion; register setup
is excluded. Every full 32-bit word is compared independently and between
implementations.

| RAM response delay | Old LCD reader | New fast stream | Words |
| --- | ---: | ---: | ---: |
| 0 | 36,608 clocks | 36,608 clocks | 18,304 |
| 1 | 54,912 clocks | 54,912 clocks | 18,304 |
| 3 | 91,520 clocks | 91,520 clocks | 18,304 |

There is no measured streaming throughput penalty on these matched backends.
This does not measure physical SDRAM timing, FPGA fit or complete phone speed.

The separate production CPU fixture includes setup, polling, CPU header
interleaving and a three-wait memory model. Its full-frame interval is
130,685 clocks with the stream versus 306,802 through the general LCD word
engine: 7.139696 versus 16.761473 clocks per word, a 2.347645 ratio. At 78 MHz
those synthetic intervals correspond to 1.67545 ms and 3.93336 ms. They are
not a matched comparison with the old reader and are not board measurements.

## Ownership and ordering

- The frontend alone owns implemented channel registers and IRQs. Channel
  `n` drives ICU bank-0 bit `6+n`; channel `+04=0` or `+08=0` acknowledges it.
  ICU masking preserves pending channel completion.
- Production request selection owns `0c120064/68`. The model follows the
  original software helper: write `68` to clear a nibble mask, then `64` to
  set the request value. LCD uses line 7. The physical register polarity is
  unverified. Unsupported paced configurations return a diagnostic error.
- Starts capture eligibility, source and extent. Later programming or
  selector writes do not modify an active descriptor. One fast stream can
  serve any channel; further LCD descriptors wait without taking its owner.
- CPU commands and stream words enter the same registered LCD queue. The
  panel cursor and programmed window determine pixel placement; the source
  RAM address does not. Transport control/header eligibility and panel pixel
  mode must both permit a word. An error handshake does not enqueue it.
- Completion waits for the actual queue tail to retire. A separate canceled
  completion fence handles stop/restart, including the engine's final-done
  edge. An accepted read drains before cancellation; committed pixel prefixes
  remain. No canceled or failed job raises a success IRQ.
- General routed LCD words use registered admission/reservation to preserve
  CPU ordering without a cancellation/grant combinational loop. An enqueued
  pixel may wait while the route and other DMA channels make progress.

`ngage_dma_ram_mux.v` combines fast LCD reads and general DMA RAM traffic
without adding a request pipeline. It captures payload and response owner
only on the outer arbiter's grant, alternates completed words between the two
producers and preserves byte masks. The outer CPU/DMA arbiter still owns SWP
exclusion.

`ngage_mister.dma_reset` exports the actual registered core-reset domain.
Template uses it for the DMA route, RAM mux, CPU/DMA arbiter and SDRAM adapter
cancellation. CPU Hold, loader readiness and warm reset therefore cannot
leave an old local transaction waiting on a reset UPP. Initial SDRAM scrub
remains a separate cold-start operation; logical cancellation does not clear
RAM. The modeled backing-memory harness also discards old accepted responses.

## Bounded LCD geometry

Original `lcd.ldd` SHA-256
`50b89c21f72a03cdadd611c2fceb73b770103074d4924ed5ee121e51b86e9f06`
supplies the software contract. File offsets `224..244` calculate row end as
start plus row count and transport bytes as `264 * rows`; `364..394` emit
the packed row bounds and trailing zero; `460..484` emit command `5c` and
header `89240000 | (264 * rows - 1)`.

The panel now accepts these full-width row bands: columns 2..177, nonempty
row intervals within 0..208, 88 words per row. Pixels retain high-halfword-first
RGB444 packing. The previous full-frame row-end 207/208 compatibility case
is retained explicitly; it does not establish general inclusive endpoints.
Malformed/interrupted parameter framing invalidates the window rather than
reusing stale geometry. Arbitrary columns, rectangles, wrap and unknown
initialization commands remain unimplemented and diagnostic.

## Verification

- Matched old/new transport: all 18,304 words identical at three RAM delays.
  The new stream also passes 244 direct/native-arbiter cases covering stalls,
  literal counts, overflow, errors, cancellation and reset.
- Production CPU fixture: all eight memory channels and IRQ positions,
  selective ACK and mask preservation; full frame; rows 3..10 from an
  unrelated source address with surrounding-row guards; CPU command
  interleaving; stopped prefixes/restart; held queue with peer CPU/DMA
  progress; queued reset; CPU-Hold-only cancellation and fresh channel work;
  on-chip LCD fallback and unsupported request/address rejection.
- Current-source host tests: final-done stop/restart fences, all eight fast
  owners, queued-tail cancellation and actual board/UPP/panel rejection of a
  midstream transport reset after four pixels. LCD protocol/malformed-window,
  ICU 96-source/1,584-pair, bridge, route, legacy LCD and RAM mux checks pass.
- Original NEM-4 ISR and callees execute unchanged on ZAP at zero/three waits
  in 11,067/16,449 cycles: three ISR entries, one next chunk, two callbacks,
  ACK before restart/callback and preserved memory guards. Synthetic kernel
  objects/page tables and direct function invocation are explicit fixture
  boundaries; full kernel interrupt dispatch is not claimed.
- Four-state Micron/controller DDIO tests pass at 78 and 104 MHz across
  0/0.25/0.5/1 ns modeled clock-pin delays. The wrong-edge negative control
  fails as expected. Source graph passes with 181 files and nine QIPs.

Runners: `tests/phone/dma_handover/run.sh`, `run-host.sh`,
`tests/phone/lcd_stream/run.sh`, `run-comparison.sh`,
`tests/phone/dma_ram_mux/run.sh` and `tests/phone/dma_isr/run.sh`.
The historical general/fast A/B logs are retained. `PHONE_FAST_LCD=0` is retired;
the required generic-route fence now uses a real on-chip RAM source.

## Remaining verification

The last fast-path transport eligibility fix passes the actual-board host
test and final CPU phase 10. The previous boot build failed writing a precompiled
header with `No space left on device`, followed by Docker metadata I/O errors.
The user freed 91 GiB and initiated a restart. The VM stopped cleanly but its
old application backend remained stuck; the ordinary restart command also
timed out. Quitting only the stale application and relaunching with the VM
already stopped recovered engine 28.0.4 and the unchanged pinned image. No
settings/data reset, other simulation action or checkpoint mutation occurred.

The pinned formatter now passes on all 13 selected maintained files: board/UPP
formatting changed, followed by a clean idempotence check. The 60 measured
original-ISR source hashes remain identical to the passing prior run.

Final sequential A/B runs pass normal/held/queued-reset/CPU-Hold modes with the
same 1,376-byte program. Normal/held totals are 152,456/152,537 fast versus
334,970/335,072 general; frame intervals remain 130,685/306,802. Phase 10 waits
for four committed pixels before resetting transport. The later removal of
the slow switch passes all four production modes again at the same fast totals,
plus original ISR execution at 11,067/16,449 clocks and host fences.

Fresh bounded boot passes at exactly 5M cycles: 351,379 transactions, 12 known
instruction-side faults, zero data errors, last fetch `00006164` in the original
low-ROM delay loop. It has no LCD data words/frame or DDR writes. Its legacy
DDR adapter does not cover Template's selected D1/D2/D3 chain. Stubbed top and
181-file source graph pass. FPGA fit/timing and new MiSTer hardware validation
remain open separately.

Evidence: [final verification](evidence/lcd-dma-final-2026-11-11.json) and
[earlier handover manifest](evidence/lcd-dma-handover-2026-11-11.json).
