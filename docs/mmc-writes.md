# Writable MMC production interface

Requested 2026-11-16. Investigation only: production MMC remains read-only and
this change is not included in the running b707ebd build.

## Scope and existing implementation

The host already has transmit commands and TX DMA. The card already implements
CMD24 and CMD25, data CRC checks, a write response token and busy handling.
Its write protection combines the mounted image's read-only flag with the
permanent/temporary CSD write-protect bits. Game images can therefore stay
protected while ordinary data cards are writable.

The production backing-store adapter, `rtl/ngage_mmc_hps.v`, forces
`card_img_readonly=1`, rejects `card_sd_wr`, drives `hps_sd_wr=0` and returns
`ffff` for outgoing halfwords. This is the missing integration boundary, rather
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
