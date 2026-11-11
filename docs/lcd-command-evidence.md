## 2026-11-07: remove speculative row coverage and display suppression

## 2026-11-11: production DMA consumes the normal panel path

The [LCD DMA handover](lcd-dma-handover.md) replaces production source-offset
pixel placement with the normal queued FIFO/cursor path. A dedicated read
stream preserves old-reader throughput on matched backends; the general
frontend owns registers and IRQs. Full-width row bands follow the original
`lcd.ldd` end=start+rows and 264-byte-per-row header arithmetic. Malformed
windows invalidate geometry. Arbitrary rectangles and wrap remain unresolved.
Final Docker-dependent verification is pending as recorded in that document;
historical shortcut results below are retained as prior evidence.

## 2026-11-08: preserve CPU/DMA ordering across the registered panel boundary

Follow-up to712c811: the first queue held CPU commands behind raw DMA, which
could let a later DMA pixel overtake an accepted CPU packet. That approach is
superseded. CPU commands and DMA valid/address/data/full-frame now cross the
same one-clock boundary, preserving their original relative order (including
header+DMA on the same edge). Existing input-side direct-data/DMA collision
suppression remains. The live panel consumes one stage every clock; the generic
queue's hold/backpressure contract is retained and tested with a synthetic
consumer hold, not driven by raw DMA. DMA completion to the ICU gains the same
one-clock delay when the panel pipeline is enabled. Non-display mode retains
the original completion timing. Reset flushes pending CPU/DMA records together;
as already documented, it may cancel unconsumed work while retaining old GRAM.

A differential mixed-stream fixture compares the whole panel control state,
first32 pixels and each DMA target (covering the full18304-word address range)
against the original unqueued display with exactly one-cycle delay.419 checks
cover direct pixels followed by DMA to the same word, simultaneous header/DMA,
commands, window state, full pulses and drained warm reset. Pending-reset
cancellation is separately tested. This fixture catches the initial ordering
mistake; merely checking that queued commands were not lost did not.
Actual CPU integration additionally asserts DMA IRQ cannot precede committed
pixel data. Queue, connected board, mixed-stream and isolated CPU tests pass.
The isolated real-SDRAM5M boot also passes unchanged PC00006170,306874 transfers,
12 known fetch faults and zero data faults; all845 board events/cycle stamps
remain byte-identical. Logs `scratch/timing-closure/pass12-lcd-queue/`.
No FPGA build. This correction was boot-tested with the previous write buffer;
point4's separate source is restored only after committing this LCD fix.

## 2026-11-08: validated command queue and DMA backpressure

Point3 implemented independently after Astra's5ac507e sparse CAM. The board
contains a one-entry `ngage_lcd_bus_queue`: late transport validation qualifies
only the pending bit; address/data are sampled independently and panel decoding
and framebuffer writes consume registered fields one clock later. DMA-valid
holds a pending command. The queue can drain/replace on the same edge; a full
queue backpressures only selected LCD writes. Controller state changes only on
acceptance. Existing direct-data/DMA collision suppression remains conservative.
Warm reset clears pending work and panel/transport state together. No added
panel frequency, unknown-command success, firmware or memory-layout change.
Standalone boards without a display retain the prior unqueued transport contract.

Random queue tests pass4000 cycles (874 commands applied,23 reset cancellations),
including held/replaced packets and changing unrelated bus payloads. A connected
board test checks full-queue waits, immediate unrelated upload writes, exact
header/data ordering, DMA hold, local invalid-header suppression and pending
warm reset. Actual CPU integration checks rejected header isolation and a valid
queued display-on command, plus SIM/DMA/IRQ/FIQ/CAM-overflow/SDRAM waits.
Known LCD transport agrees with both C++ fixtures; full18304-word DMA passes.
Retained firmware-DMA replay is explicitly SKIP (fixture unavailable).

Fresh real-SDRAM5M boot passes unchanged PC00006170,306874 transfers,12 known
fetch faults and zero data faults. All845 board events and cycle stamps match
Astra's baseline byte-for-byte; trace SHA256
`ea4112346d90486e45bca592800959d43d83b1252e8ee8d1c245a9b19ecf7ecd`.
Early boot has no LCD traffic; queued LCD behavior is established by the directed
board/CPU tests, not a new cold-logo claim. Permanent checkpoints untouched.
Regional ownership sweep, SIM present/absent, warm/cold RAM, diagnostic monitor/
raster, top elaboration and source graph pass. Full CPU/cache suite finishes
119 PASS plus one expected legacy direct-map XFAIL; warm ADD stays1 cycle at0/3 waits. Evidence `scratch/timing-closure/pass12-lcd-queue/`.
No FPGA build or timing claim. Point4 write-buffer metadata is the next separate
commit; last measured fit remains69.19MHz/-4.837ns.

User requested retaining only needed LCD logic. Removed the per-row complete
bitmap, contiguous-word counters, per-word /88/%88 and the frame_complete gate
on phone scanout. These were FPGA bring-up coverage/blanking policy, not
established panel behavior. The pinned Nortido LCD uses a simple linear burst
pointer, not that coverage mechanism. Existing framebuffer addressing is already
linear; leave it and the native176x208 raster intact. Display on/off and known
command/write validation remain.

Partial direct/DMA updates are visible while the panel is on. The explicit M10K
wrapper already uses zero power-up initialization; no runtime clear engine or
large validity bitmap is added. Warm reset retains pixel storage. Completion
flags now describe explicit full DMA/direct transfers only and are diagnostic;
out-of-order chunks no longer synthesize a full-frame-coverage event. They do
not suppress real pixels. Tests verify partial pixels, untouched initial black,
band addressing and explicit completion, with original command/protocol tests.
No new panel command, pin frequency or physical timing claim is introduced.

# Reached LCD commands and current decode limits

## Evidence and scope (2026-11-07)

The fresh stock-firmware HDL cold boot `logo-normal-2000m` produced the Nokia
logo. Its first 125 non-pixel LCD writes are preserved as the executable fixture
`tests/phone/lcd_display/startup_commands.hex`; cycle, PC and source-log hash are
in `scratch/logo-bringup/normal-startup-lcd.json`. This fixture comes from the
actual cold HDL run, rather than a host-injected or reconstructed frame.

The pinned Nortido core (`1be08b9bcf951a4523085747572ea102b96de65b`),
`rtl/ngage_lcd.sv` and `hps/lib/ngl_lcd.c`, supplies independent N-Gage-specific
packing and panel-column-offset leads. It does not decode window ends or model
initialization registers. Its forced-ready/ID readbacks and injected black clear
were not adopted. The stock ARM packing instructions match our service core;
see [reference review](nortido-hybrid-reference.md).

## Reached table

Lengths below are the UPP header's low-field count plus one, not independently
verified physical-panel bytes. Payload examples are raw 32-bit CPU port writes.

| Opcode | Parameter header / count | Observed payload | Current interpretation |
| --- | --- | --- | --- |
| `15` | `09240003` / 4 | `0B100002`, `0` | Column start 2, end 177; full visible panel. Decoded. |
| `75` | `09240003` / 4 | `0D000000`, `0` | Row start 0, end 208. Decoded; full-panel clipping convention unresolved. |
| `5C` | pixel header `8924D67F` | 18,304 pairs on initial clear | Direct full-frame RGB444 write, then firmware-generated logo observed. |
| `AF` | none | none | Display enable; verified by modeled scanout. |
| `CA` | `0924000A` / 11 | `F640F208`, `FD81FF00`, `F00DF000`, `F000F108` | Init register, unresolved. Preserve diagnostic. |
| `CC` | `0924000E` / 15 | `F312F413`, `F454F039`, `F504FD4A`, `F595F653`, `F785FE5B` | Init register, unresolved. Preserve diagnostic. |
| `BC` | `09240000` / 1 | `30` | Init register, unresolved. |
| `CD` | `09240000` / 1 | `1` | Init register, unresolved. |
| `D0` | `09240000` / 1 | `0` | Init register, unresolved. |
| `A6` | none | none | Normal-display family lead only; not treated as a successful no-op. |
| `94` | none | none | Sleep-out family lead only; not treated as a successful no-op. |
| `C6` | `09240000` / 1 | `80`, later `0` | Init register, unresolved. |
| `A9` | none | none | Partial-mode-exit family lead only; not modeled. |

The corresponding [Epson S1D15G00 command table](https://www.olimex.com/Products/Modules/LCD/MOD-LCD6610/resources/S1D15G00_REV1_0.pdf)
and [S1D15G10 datasheet](https://people.ece.cornell.edu/land/courses/ece4760/FinalProjects/s2008/djf35_swl28/djf35_swl28/epson_lcd_datasheet.pdf)
suggest the A6/94/A9 names. They are **family comparisons, not panel
identification**. In particular G10's `CC` is a parameterless EEPROM-control
exit, whereas this phone sends a 15-unit payload. Its `CA`/`BC` parameter counts
also differ. Copying their entire command tables would invent phone behavior.
TriX's shared LCD helper is another Nokia-family comparison; it does not resolve
this mismatch. No exact NEM-4 controller datasheet was established.

## Implemented behavior and explicit rejection

The display module now retains the selected command, captures the two-word
`09240003` parameter transaction and stores both start and end coordinates.
The stock firmware intentionally emits the second zero word; it is not an
extra duplicate transaction. Header changes before that word, nonzero trailing
words and malformed packing are diagnosed.

Only full-panel windows are accepted for direct rendering: columns 2..177,
rows starting at zero with end 208 (stock clear) or 207 (reference helper).
Both describe the existing full-frame path after visible-panel clipping; this
acceptance **does not settle inclusive versus exclusive row endpoints**.
Partial/nonzero/odd windows retain their values, flag unsupported, and do not
silently draw a full frame at zero. There is no fabricated partial-window wrap
policy. DMA remains the existing source-offset/line-band model; it does not yet
consume programmed panel windows, and this work does not claim that it does.

Unknown reports now retain header, selected command and data. New-build logo
logs retain command/header/parameter writes beyond the first clear, suppress
bulk pixel data and sample at most 32 unknown events. The sticky unknown flag
and latest module context remain available after that console budget is used.
Unknown init operations remain visibly flagged; the red diagnostic strip has
not been suppressed.

Tests cover the actual startup fixture, both full-window encodings, malformed
and interrupted payloads, odd/nonzero starts, rejection of unimplemented
geometry, CPU/DMA write priority and preservation of unknown context. Existing
full-frame, line-band, DMA/arbitration and board CPU integration tests pass.

## Next evidence needed

Disassemble the stock `lcd.ldd` / `LcdPartialMode.dll` and capture a bounded later
partial-update stream with its source/count and window writes. Resolve end
clipping/wrap and transport-unit packing before adding rectangle writes or
assuming other controller initialization bits. The local firmware and pinned
reference are already available; no guest modification is necessary. A fresh
cold phone run is required for changed LCD/keypad HDL; old snapshots remain
resumable only on their saved executable or an explicitly verified conversion.

## Stock `lcd.ldd` cross-check

The retail service tree's `lcd.ldd` SHA-256 is `50b89c21f72a03cdadd611c2fceb73b770103074d4924ed5ee121e51b86e9f06`. ARM disassembly uses file-relative offsets here, avoiding an assumed code-address mapping. Functions `548..578` and `57C..5B0` explicitly select CA/CC with counts 11/15 and emit four/five port words. Tables at file offsets `4B48`/`4A8C` exactly match the retained raw payloads. Recorded words, table pointers and proof hashes: `scratch/logo-bringup/lcd-driver-evidence.json`; disassemblies remain in scratch. This rules out treating the count mismatch as accidental trace duplication.

Row packing at `364..394` matches the early bootstrap's 8-bit start/end plus trailing zero. The generic column setter at `3C0..3F8` additionally supports high end-coordinate bits in the second word; the implemented full-panel decoder deliberately accepts only the zero-high-byte case. Row-band helper `224..244` supplies end=start+length while sizing the pixel transport to 264*length. Single-pixel paths use y-1/y for row bounds. This strengthens the software half-open-row-range interpretation, but does not show how excess data would wrap on the panel; generic rectangle wrap remains unsupported. The driver also has a second init path using CB with a 126-unit table, so claiming all panel initialization is understood from the first boot stream would be premature.

## Pocket core checked at the user's direction

Local `~/develop/n-gage`, commit `755ad13b0b5d3f01d228558f29acd0ec1c2007c2` (clean checkout when inspected), provides useful **display output** evidence, but no physical Nokia LCD command decoder. `docs/hardware.md` explicitly states that `sw/kernel` replaces the EKA1 kernel and Nokia drivers, modeling the LDD interface. `sw/kernel/chan.c:289` replaces the Lcd channel: control 8194 triggers `IO_LCD_SHOW` and returns success. Its observed argument is `{0xA,0,0xD0}` for lines 0..208; the implementation copies the whole framebuffer and does not interpret a physical row-window end. Other controls log and return success, rather than execute the stock LCD driver. These substitutions must not be copied into the unmodified-firmware board model.

Concrete useful leads:

- `sw/include/ngvm_hw.h:139`: 176x208, row-major halfwords, 0RGB / RGB444. Independent cross-check for the existing captured-image format.
- `rtl/ngvm_sys.sv:125`: a show request cleans its D-cache before the LCD copy starts. This is a cache-visibility regression lead, not permission to force cache cleaning on the phone. Actual Nokia firmware cache operations and DMA reads must remain observable.
- `rtl/ngvm_lcd.sv:25`: copies 36,608 pixels into a separate frame store in up-to-32-halfword bursts, queues one further show while busy, and scans the copied frame. Useful output/storage/arbitration patterns; its custom IO protocol is not UPP LCD transport.
- `sim/tb_lcd.cpp`: coordinate-coded pictures verify every pixel, orientation and both raster directions. Useful test patterns for our scanout, without adopting Pocket-specific timings.
- `tools/ngvm/ngvm.py` and captured boot frames can supply comparison images after executing the same user firmware on the replacement kernel. They cannot verify stock kernel/device behavior or establish the same cycle milestones.

No CA/CC/BC/CD/D0/C6 decoder or physical 15/75 window-wrap implementation was found in these LCD/kernel/reference paths. Thus this core does not settle the remaining panel commands or row-end ambiguity. Source hashes and revision are preserved in `scratch/logo-bringup/pocket-lcd-review.json`. Nothing was edited or run in the Pocket checkout; no HDL or running model changed during this review.
