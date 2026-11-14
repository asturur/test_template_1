# Production MMC boundary tests

Run `sh tests/phone/mmc_production/run.sh` from the repository root with host
Icarus, or `sh tests/phone/mmc_production/run-pinned.sh` with the existing offline
`jotego/simulator:arm64` image. Outputs are in `build/sim/unit-mmc-production/`.
Do not overlap runners because they share that directory.

`bus_tb.v` uses an independent native CMD/DAT peer and the real
`ngage_upp_peripherals` captured response owner. Thirty cases cover exact
1/2/3/5/511/512-byte TX/RX, rounded-four zero/drop padding, individual FIFO
lanes, held completed requests, FIFO clock stalls, CRC/end/token/busy/start
errors, continuation types5/6/7/8/9/10 and reset. Final-block cases also prove
the internal prefetch-stop hint is asserted before the data block and remains
through its busy interval and the native command NRC interval. ICU register operations prove
21/23/24 selection and source22 suppression. A raw native IRQ signal is read
for the peer's timing assertions only; all host operations use the public bus.
The wire/CRC peer is adapted from the standalone host test, so that test is
not claimed as independent evidence of the same shared protocol model.

`dma_tb.v` substitutes an authored Wishbone master (`cpu_peer.v`) at the CPU
leaf of the real internal-UPP composition. It executes no ARM instructions.
The real memory route, capture bridge, CPU/local arbitration, peripheral
response owner, general DMA frontend/engines and DMA router remain present.
The independent native peer checks every byte and CRC on the wire. All eight
channels run TX control2 / RX control3 with selector2, fixed eight-bit FIFO
and incrementing 32-bit memory at lengths1/2/3/5/511/512. Logical host lengths
remain exact while DMA counts round up to four. Sentinel memory proves no
write outside that rounded extent. Live selector edits cannot repace the
captured job. ICU masking leaves pending DMA state intact; channel ACK
removes it. Additional cases cover CPU/peer-memory progress while RX awaits
bytes, cancellation of an owned RAM read, replacement behind that read,
reset with an owned read followed by fresh RX, unsupported selector diagnostics
and rejection of control1 FIFO transfers. The latter errors never become
success IRQs. DMA completion is separate from host/card CRC and busy status.

Current host results: bus30 cases /132,221 clocks; DMA96 matrix transfers plus
focused boundaries /667,085 clocks, with98 completed host data phases. The
compiled design is strict Verilog-2001. Existing Icarus warnings, if emitted,
include broad array sensitivity for `always @*`; these are not test oracles.

Production defaults follow GENERAL_DMA, preserving explicit legacy bus-only
fixtures. Host access at0c120600 merges native read masks with the existing
storage bank; physical FIFO0c120624 and DMAalias10120624 share captured ownership.
MMC single-byte offers are admitted atomically with local permission; unavailable
FIFO offers do not occupy the shared router. The permission is registered, and
CPU work can cross a boundary before another paced byte. The LCD path and its
queue completion fence remain separate from MMC completion.

The board's resolved CLK/CMD/DAT0 connection is explicitly a transaction
shortcut around the unimplemented D550/AMA-WD2 path. The audited donor command-busy prefetch hint
is an internal optimization, not a phone or D550 pin. QD-derived clock/timeout
behavior, physical electrical timing, general malformed-response status
handling and concurrent host command-register edits remain unverified or
unsupported. Native IRQ22/dataBusy is observable in the test but remains
unconnected to production ICU. The separate `mmc_mister` authored-ARM fixture
covers the actual board/card/HPS-adapter boundary. These tests do not establish
original EPBUS execution, a mounted phone filesystem or protected-title launch.

## Native RX2 correction

The runner now executes the complete8-channel matrix and focused controls for
RX_CONTROL=2 (native) and3 (retained alias). Both pass669385clocks with96matrix
transfers plus focused controls. The guest run value remains the programmed
control. Original kernel start/stop code is separately covered with production
admission by dma_original; full board/card/HPS reads use RX2 in mmc_mister.
