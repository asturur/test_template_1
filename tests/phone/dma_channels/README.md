# DMA programming and scheduling fixture

Run `sh tests/phone/dma_channels/run.sh` from the repository root. It uses the
installed `jotego/simulator:arm64` image with networking and image pulling
disabled. Logs are in `build/sim/unit-dma-channels-{1,2,3}/`.

`ngage_dma_channels.v` snapshots eight channel descriptors into a configurable
execution pool (default three engines). Round-robin dispatch and word grants
preserve response ownership. Programming writes cannot mutate a queued or
running descriptor. A new start replaces a queued descriptor or stops and
drains its active predecessor before dispatch. A stop clears queued work and
keeps the busy read nonzero until an accepted word drains. Committed writes
remain committed. Reset must share the downstream route/drain boundary.

Only implemented channel registers are claimed. Programming uses aligned
full-word accesses; unsupported start codes reject. Source/destination modes
zero mean fixed and nonzero mean incrementing. Width codes are exactly 8, 16
and 32 bits. The unknown status registers at offsets `0x0c/0x10` read zero;
this is an explicit model placeholder.

The original NEM-4 driver supplies a byte extent through two count rules:

| Start | Engine byte budget |
| --- | --- |
| 1, memory | `2 * (raw_count + 1)` |
| 2, memory to fixed peripheral | destination width in bytes times `(raw_count + 1)` |
| 2, fixed peripheral to memory | source width in bytes times `(raw_count + 1)` |

Paced configurations with both endpoints fixed or both incrementing have no
established count rule and terminate with a diagnostic error. The generic
engine handles partial source and destination units without accessing extra
lanes. These rules reproduce the original driver's byte extent; they do not
establish physical UPP bus widths, timing, burst sizes or arbitrary unaligned
request support. The engine requires native-width alignment.

Completion latches a channel-relative IRQ. Offset `0x04=0` and `0x08=0`
acknowledge that channel. Errors terminate and latch the separate model
`error_pending` output, without raising a success IRQ or inventing an error
register. The original ISR uses a constant success status, so raising its
normal IRQ on a bus error would report a copy that did not finish.

The fixture connects the actual word router to byte-addressed SDRAM, shared
RAM and test FIFO endpoints. It checks all eight queued channels, immutable
snapshots, halfword memory counts at 32-bit width, byte peripheral TX/RX
counts, partial tails and sentinels, paced peers, selective IRQ ACK, accepted
word stop/restart, route/target errors, invalid descriptors, held commands,
SWP lock exclusion and coordinated reset. One-, two- and three-engine builds pass.
The byte FIFO at shared-RAM address `0x0c004080` is fixture-only; it adds no
production peripheral alias. CPU-side fairness remains covered by the B1
router/UPP tests. An execution pool occupied entirely by paused descriptors
cannot dispatch a ninth operation until an engine becomes free.

The maintained modules are listed in `files.qip` but have not taken ownership
from the production LCD channel. Original setup/start/stop routines pass in
`tests/phone/dma_original/`. Original ISR execution, request routing and the
LCD ownership/completion transition remain integration gates.

For the private-ROM static evidence, run:

```sh
python3 tests/phone/dma_channels/audit_rom.py /path/to/ngage-rom-0x50000000.dmp
```

This needs the existing Python Capstone installation. It verifies the fixture
hash, original register helpers, peripheral width/count tables and DMA IRQ
name indices. No firmware bytes are copied into the repository.


The programming-word readback payload now resides in a single 64x32 M10K.
All 32 bits of every implemented word are preserved; reset-valid bits mask
retained physical RAM. Source/destination/count mirrors and decoded width/
mode metadata remain live for immediate start snapshots. Raw programming
reads wait one RAM clock through `ready`; writes, selectors and active/status
reads retain their previous timing. The fixture includes arbitrary complete
readback, invalid high-bit width codes, high-bit-only nonzero modes, held and
changed queries, cancellation, reset masking and reads during queued work.

Run `sh tests/phone/dma_channels/run-concurrency.sh` for the production worker
comparison. It measures pools of one, two and three using the actual router,
LCD RAM mux and CPU/DMA arbiter. Synthetic memory has two wait-count clocks;
a continuous synthetic CPU memory-request stream checks arbitration fairness.
Modes cover a blocked MMC FIFO plus memory copy and a complete native fast-LCD
stream, isolated continuously-ready MMC, and isolated fast LCD. This is a
transport/concurrency comparison, not a physical card/phone speed measurement.
See [DMA readback RAM](../../../docs/dma-readback-ram.md) for the measured
results and boundaries.
