# Production DMA/LCD handover

`sh tests/phone/dma_handover/run.sh` assembles an authored ARM fixture and runs
ZAP plus the production MiSTer/board/UPP composition in the existing offline
simulator image. Eligible SDRAM LCD transfers always use the optimized native
RAM read stream. The old `PHONE_FAST_LCD=0` comparison option is retired.
On-chip RAM LCD sources still use the general route. Both routes share the
fair DMA RAM mux, CPU arbiter, three-wait RAM model and normal LCD command
queue/panel cursor.

The CPU programs all eight channels, copies four words per channel with
trailing guards, checks IRQ priority/selective channel acknowledgment and
proves mask disable/re-enable preserves pending DMA completion. LCD checks
cover stopped prefixes, a full 18,304-word restart, CPU header interleaving,
last-pixel-before-IRQ, original-driver rows 3..10 from an unrelated source
address, packed pixels and unchanged surrounding rows. NOS4K-to-LCD uses the
general fallback. Invalid headers, transport reset, unsupported MMC/request
lines and a control-1 FIFO bypass fail without normal completion.

The same executable also runs with:

- `+hold`: holds the first accepted queued pixel until a CPU-programmed peer
  DMA copy and CPU RAM marker complete, then releases the queue and finishes.
- `+reset-tail`: resets an accepted queued pixel before panel commit and checks
  that neither data nor channel/router completion leaks afterward.
- `+hold-reset`: asserts only MiSTer's CPU Hold/reset input, keeping raw test
  reset low. Exported `dma_reset` cancels the route, RAM mux and CPU arbiter;
  the RAM model drains/discards the old accepted read. Releasing Hold restarts
  the CPU and completes eight fresh DMA copies.

`fence_tb.v` targets stop/restart on the general engine's done-generation edge
with a held tail. `fast_channels_tb.v` covers every channel on the native
stream, literal counts, selective ACK and stop/restart while the final pixel
remains queued. Both compile as Verilog-2001. `transport_tb.v` programs the actual board
composition and resets transport after four pixels, checking rejection even
while panel mode remains valid. `sh tests/phone/dma_handover/run-host.sh` runs
these three focused checks without Docker.

These are bounded model tests, not original firmware execution or physical
phone/FPGA timing validation. Original driver/ISR fixtures remain separate.
Logs and ARM images live in `build/sim/unit-dma-handover/`; retained A/B results
are under `scratch/ngage2-integration/lcd-handover/`.

## Recorded verification, 2026-11-11

The fast and generic full CPU fixtures both passed their normal, held-queue,
queued-reset and logical CPU Hold reset runs before the final transport-gate
refinement. Their retained logs are respectively:

- `scratch/ngage2-integration/lcd-handover/fast/`: normal 151,093 clocks;
  held queue 151,174 clocks; complete-frame interval 130,685 clocks,
  7.139696 clocks per word.
- `scratch/ngage2-integration/lcd-handover/generic/`: normal 333,523 clocks;
  held queue 333,632 clocks; complete-frame interval 306,802 clocks,
  16.761473 clocks per word.

The matched complete-frame interval is 2.348 times faster with the stream.
These intervals include CPU setup/polling/header interleaving and the same
three-wait synthetic RAM backend. They are not measured FPGA display latency.
The older immediate-memory LCD fixture's approximately two clocks per word
uses a different backend and is not a matched performance comparison.

After the final transport gate, `run-host.sh` passes all three checks on the
current sources, including an actual board/UPP/panel midstream transport reset
that retains exactly four pixels and returns a diagnostic without a success
IRQ. The final ARM program assembles/links to 1,376 bytes. The existing LCD
protocol/display, ICU 96-source/1,584-pair, both UPP bridges, DMA router and
legacy LCD full-frame checks also pass on the current sources.

The final full CPU program adds phase 10 for midstream transport reset. After
Docker recovery, both historical profiles pass all four modes with the final
1,376-byte program and pinned formatter. Fast normal/held totals are
152,456/152,537 clocks; general totals are 334,970/335,072. Frame intervals
remain 130,685/306,802. Evidence is under
`scratch/ngage2-integration/lcd-handover/final-pinned/`.

The production slow-LCD switch has since been removed. Run
`sh tests/phone/dma_handover/run.sh` for the single production path. The
generic final-response fence uses an on-chip RAM source, whose transport
requires the general engine, and no longer disables the SDRAM stream.

Phase 10 waits for four committed pixels before resetting transport, so
its midstream premise is deterministic even if CPU/cache timing changes.
