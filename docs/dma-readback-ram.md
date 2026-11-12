# DMA programming readback in embedded RAM

## Storage and timing boundary

The eight channels retain all eight raw 32-bit programming words in a single
64x32 `ngage_bram` M10K: enable, source, source mode, source width,
destination, destination mode, destination width and count. No reserved or
unknown readback bit is truncated. Sixty-four per-word valid bits make every
word read zero after reset without clearing physical RAM.

Only descriptor inputs needed on the accepted start edge remain live:
768 source/destination/count bits, sixteen zero/nonzero mode flags and
48 decoded width bits. Width decoding compares the complete original word;
only exactly8/16/32 are valid. A high-bit-only nonzero mode remains
incrementing. Enable is readback-only except that an accepted zero write
acknowledges that channel, as before. Queued descriptors remain complete
immutable snapshots, and the35-bit byte-count conversion is unchanged.

The raw programming storage changes from2048 flip-flop bits to832 live
mirror/metadata bits plus64 reset-valid and8 read-lookup bits: a source-level
reduction of1144 flip-flops and one additional M10K. This is not a measured
ALM saving; new synthesis/placement must determine fit and104 MHz timing.
The prior failed fit's DMA frontend alone used2361.9ALMs/3142registers.

The new trailing `ready` output delays only raw programming reads by one RAM
clock. Writes, request selectors, active/control and placeholder status reads
remain immediately ready. A lookup captures the raw word address and its
reset-valid bit; a changed or canceled query cannot reuse another word's
ready result. Read-side lookup has no commit effect. UPP waits for this
readiness before capturing its response. Start/stop, queued dispatch, engine
execution and the separate fast LCD stream do not wait for readback RAM.

## Worker-count experiment

Eight programmed channels share a configurable execution pool. A worker owns
a transfer while that transfer is paused by its peripheral. The fast LCD
stream is a separate execution path; all traffic still shares memory.

`tests/phone/dma_channels/concurrency_tb.v` connects the production frontend
to the actual DMA router, fast/general RAM mux and CPU/DMA SDRAM arbiter.
A synthetic memory model acknowledges after two wait-count clocks; a
continuous synthetic CPU memory-request stream checks memory arbitration.
The test FIFO either withholds capacity or accepts MMC bytes continuously.
These are transport measurements, not card, phone or CPU-instruction timings.

The stalled experiment starts a256-byte MMC transmit and withholds FIFO
capacity after its first source fetch. It then queues a512-byte ordinary
memory copy and a native18,304-word LCD frame. FIFO capacity is released
only after the frame. The observed results are:

| Workers | Copy words finished at frame end | Frame clocks with stalled MMC/copy | Clocks after FIFO release until all work finishes |
| --- | --- | --- | --- |
| 1 | 0 of128 | 146,431 | 3,324 |
| 2 | 128 of128 | 148,479 | 1,272 |
| 3 | 128 of128 | 148,479 | 1,272 |

The extra2048 frame clocks with two/three workers are useful copy reads and
writes sharing RAM with LCD. One worker leaves that copy queued behind the
blocked MMC transfer. Two and three produce identical progress and timing.
The maximum gap between continuously requested CPU memory acknowledgements
is8 clocks in every experiment; CPU progress continues while MMC is stalled.

Isolated continuously-ready MMC completes256 bytes in1284 clocks with all
three pool sizes. An isolated native LCD frame takes146434 clocks with all
three. The three-clock phase difference versus the stalled one-worker frame
comes from preceding arbitration state, not a faster stream. In the matched
old/new frontend experiment, every generic command, LCD read/pixel, active
bit and IRQ agrees on every cycle for all pool sizes and all three modes.

Two workers therefore preserve the demonstrated MMC-plus-memory concurrency;
a third does not improve these measured workloads. A third independent paced
transfer could benefit from a third worker if two others were simultaneously
blocked. That is a future workload tradeoff, not a claim that every possible
three-transfer schedule is unchanged. The generic module remains configurable;
production pool selection belongs to UPP.

## Verification and reproduction

The full queued/stop/restart/IRQ/router test now builds pools of1/2/3. It checks
all64 raw words through arbitrary complete patterns, preserved high bits,
invalid width rejection without traffic, high-bit-only mode semantics, held
and changed read queries, canceled reads, reset masking, queued snapshot
ownership, accepted-word stop/restart, errors, Lock and reset. An isolated
baseline from source commit`1dd285e4d185a0b8fa46808a0930f9579cf540e8` receives
identical bus transactions and response traffic; packet/dispatch/IRQ cycles
and every accepted raw read match exactly.

Run `sh tests/phone/dma_channels/run.sh` for the channel suite and
`sh tests/phone/dma_channels/run-concurrency.sh` for the worker experiment.
Both use the existing pinned simulator image with no pull or network.
`PHONE_TEST_OUT` selects a unique concurrency output directory. Original
DMA/ISR CPU fixtures now qualify their DMA read acknowledgement with`ready`;
their instructions are unchanged. The two host LCD channel fixture builds
include the new RAM dependency.

All focused evidence is retained under
`scratch/ngage2-integration/fit-recovery-2026-11-11/dma/`. Original firmware,
the other checkout, existing long simulations and billion-cycle checkpoint
pairs are untouched. No fitted resource/timing result or complete phone boot
is claimed by these focused tests.

Final frontend SHA-256 is
`dc17656725436483eea8aee5c715fcf97dd2852e6163500fb4dc46b37c485a0d`.
The [evidence manifest](evidence/dma-readback-ram-2026-11-11.json) records full
source/input identities, every worker experiment and the original CPU runs.
The final channel A/B suite accepts397 reads, including387 raw reads with
exactly387 added read clocks, at each pool size. Its totals are3169 clocks
with one worker and3055 with two/three. Original setup/start/stop remains
11130/16814 clocks at zero/three memory waits; original ISR/chunk restart
remains11067/16449 clocks. Instruction substitutions remain zero.

## Quartus simple-dual-port correction

The first recovery build (`0a47a0f`, run43032422026) stopped during synthesis:
programming RAM incorrectly consumed `q_a` while `READ_ONLY_B=1` selected
write-A/read-B simple dual-port mode. The ordinary RAM model had allowed this
unsupported read, so the behavioral-only register tests did not catch it.

The RAM now reads `q_b` at the programming address; its write port and read
handshake are unchanged. The common wrapper also exposes `q_a=0` in this mode
in both simulation and synthesis, matching Intel's library. The added vendor
runner checks all raw words with one/two/three engines using an existing local
`altera_mf.v`; it never downloads Quartus. All397 reads pass in each pool. The
previous connection fails the corrected ordinary model at channel0 offset04,
returning0 instead offfffffff. The explicit RAM suite also checks this contract.

Run `sh tests/phone/dma_channels/run-vendor.sh /existing/path/altera_mf.v`.
This corrects a primitive-port mismatch without another read or transfer clock.
No area/timing result was produced by that failed synthesis; a new fit is needed.

## Live programming mirrors removed — 2026-11-12

The remaining768 src/dst/raw-count FF bits now occupy live rows in the
existing queued-descriptor banks. A ready-qualified one-clock start sample
feeds an immutable committing-edge snapshot; raw readback stays unchanged.
See [area reductions](area-reductions-2026-11-12.md) for row layout,
withdrawn/channel-switched/gapless-start tests, Intel/poison coverage and
LCD/MMC launch cost. Earlier no-start-wait descriptions above are historical.
