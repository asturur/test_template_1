# Writable MMC production interface

Requested 2026-11-16. Write integration is implemented and locally qualified
below. The currently installed b707ebd RBF remains read-only; the new HDL needs
a fresh FPGA build and native persistence testing.

## Implemented and qualified locally

The adapter latches the selected mount's read-only flag and captures write
direction alongside LBA/count. CMD24/25 use the native card's existing one-sector
RAM and TX DMA; two control bits are added, with no new RAM, DMA worker or FSM
stage. The read streaming path and wait schedule are retained. Template's MMC
menu no longer says read-only. Linux read-only and CSD permanent/temporary
write protection remain enforced.

HPS command0x18 reads the card's registered RAM port. Its advancing halfword
address validates exactly256 outgoing words; incoming buffer-write strobes are
rejected during a write. The held native RAM-slot selector remains stable
through guest/init reset until old transport drains. Actual-HPS testing proves
the entire selected sector remains correct after reset. A replacement during
an advertised write is quarantined; no atomic hot replacement is promised.
An already advertised host write cannot be rolled back. Wait for writes to
finish before replacing media, and cold-mount cards as established for NEM-4.

Final direct test:48 cases,33,287 clocks. Actual three-slot HPS/native-card test:
20 reads,4 persisted writes,2 other-slot reads,2 bulk reads,18 delayed tail
halfwords and2,128 overlapping-request clocks,604,018 clocks total. Checks cover
CMD24, two CMD25 blocks, independent readback after remount, CRC rejection,
Linux/CSD WP, EOF/footer exclusion, short/skipped/overlong/wrong-direction data,
reset before ACK/during readout, init reset and busy replacement quarantine.
Strict Verilog-2001 lint passes. Existing card EOF/version,33 CMD16 probes,
28 host-data cases at each of two clock/FIFO profiles,30 MMIO/pin cases and
98 DMA/IRQ cases for each native RX selector also pass. Private outputs are
under build/sim/mmc-writes*-20261116*. No firmware, CPU clock or current phone
session was changed; fitted ALMs/timing and native writes remain unverified.

The following sections record the original scope and acceptance plan.

## Original missing boundary

The host already has transmit commands and TX DMA. The card already implements
CMD24 and CMD25, data CRC checks, a write response token and busy handling.
Its write protection combines the mounted image's read-only flag with the
permanent/temporary CSD write-protect bits. Game images can therefore stay
protected while ordinary data cards are writable.

Before this change, the production backing-store adapter, `rtl/ngage_mmc_hps.v`, forced
`card_img_readonly=1`, rejected `card_sd_wr`, drove `hps_sd_wr=0` and returned
`ffff` for outgoing halfwords. This was the missing integration boundary, rather
than a need for a new DMA engine or a new filesystem format. Linux sector writes
would persist each accepted MMC write independently of C:/PMM Background save.

The change is modest, but connecting these four signals alone is insufficient.
The existing adapter verifies incoming halfwords and drains the registered HPS
write pipeline. An outgoing transfer uses a different bus direction and must
preserve its buffer and slot ownership until Linux finishes reading it.

## Implementation order and dependencies

1. Latch the read-only flag only on the MMC slot's mount pulse. Other slots
   share the image metadata bus and must not change the mounted card's policy.
   Preserve footer admission, actual payload extent and CSD protection.
2. Capture request direction alongside the existing LBA/count/generation.
   Reject simultaneous read/write requests, writes before footer admission,
   read-only writes and any request reaching the metadata footer. The card
   currently writes one 512-byte block at a time, including during CMD25;
   explicitly check that contract instead of advertising an untested burst.
3. Route the selected HPS read address to the card's registered RAM port and
   route its returned halfword to the selected HPS slot. Keep incoming buffer
   writes disabled during outgoing transfers. Confirm first/last-halfword
   alignment using the actual three-slot `hps_io`, not a zero-latency mock.
4. Hold advertised writes through reset/media-change cancellation and drain
   the selected-slot ACK before releasing the old image/buffer owner. The card
   resets its protocol state but retains the HPS RAM-slot selection registers;
   prove that the selected sector cannot be overwritten during the drain.
   If that lifetime cannot be guaranteed, take a sector snapshot in BRAM before
   advertising the write; do not introduce a 4,096-bit flip-flop buffer.
5. Acknowledge completion to the card only after the HPS transfer completes.
   Retain existing read streaming/admission checks and late-tail suppression.
   Outgoing transfers must not be validated using the incoming word counter.

## Verification

Extend the existing direct adapter tests with writable/read-only mount policy,
other-slot metadata changes, bounded outgoing requests, illegal direction,
footer/EOF rejection and reset/media-change cancellation at each ACK boundary.

Extend `tests/phone/mmc_hps/actual_tb.sv` to service the real HPS write command
0x18. Compare every outgoing halfword against an independent sector model,
including distinct first/last values and delayed reads. Run mixed traffic on
all three slots. Require CMD24 and CMD25 readback, persisted bytes after card
reset/remount, unchanged footer bytes, CRC rejection without persistence,
Linux and CSD write protection, short/late transfers and cancelled-owner tests.

Keep the card/host/TX-DMA and production integration regressions. Check fitted
ALMs, M10Ks, timing and unchanged read behavior before hardware acceptance.
On a writable disposable data image, use the original phone to create/copy,
read and delete a file, then reboot and verify the image from Linux. Do not use
the user's installed C: or a unique game image as the write-test target.
