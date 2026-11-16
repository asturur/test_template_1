# Production MMC HPS transport

`ngage_mmc_hps.v` owns slot2 read/write requests. The native card owns its
sector RAM; this adapter connects it to the actual shared MiSTer HPS buffer
bus. It is a backing-store adapter, not invented D550/AMA pin routing. C:/PMM
remain slots0/1. No new RAM, DMA worker or FSM stage is added for writes.

## Admission and read path

A mounted image must be512-byte aligned, at least1,024bytes and at most1GiB
plus its512-byte footer. Zero size removes the image. The first request must
read exactly the footer. All original identity bytes are retained: NGAGEMMC/v1,
CID/CSD CRC7 and end bits, observed MMC3.1 CSD structure2/spec3/READ_BL_LEN9,
byte-addressed OCR and decoded capacity covering the payload. No raw fallback
or identity repair is allowed. ACK completion waits for all footer words and
CRC/admission checks before the card can become present.

Later reads fit the payload excluding the footer and use at most8sectors.
Prefixes forward immediately; no full4KiB staging delay. Selected-slot ACK or
its previous-cycle value qualifies incoming halfwords, preserving the last
registered word and isolating the other slots. Exact order/count is checked;
short, skipped, duplicated or extra data quarantines the card.

## Write path

Only the selected mount pulse captures image size/read-only. Shared metadata
changes for other slots cannot alter the card. Native card CSD permanent/
temporary write protection is retained. One-block writes capture direction,
LBA/count and generation before advertisement; CMD25 still transfers one block
at a time. Writes before admission, outside payload, to the footer, with both
directions asserted or with unsupported counts are rejected.

HPS0x18 reads the existing registered card RAM port. Its address advances after
sampling each outgoing halfword, allowing the reused transfer counter to check
exactly256ordered words. Incoming write strobes during outgoing traffic are
invalid. The card's selected RAM slot and bytes remain stable until ACK/tail
drain, even when the guest resets; the actual-card test verifies every word
across that reset. No extra sector snapshot is necessary for this contract.

## Reset and media ownership

Configuration initialization is distinct from runtime init/guest resets.
Advertised work drains because Main has no separate acceptance/cancellation
channel. Guest reset suppresses obsolete completion, retains media and replays
one mount after the drain. Init forgets retained media; a new selected mount
supplies fresh metadata. Old read data cannot enter a remounted card.

A media replacement during an advertised write quarantines the card and
requires a fresh mount after the old transaction drains. This cannot roll back
an already advertised host write or establish atomic writable hot replacement.
Do not replace a busy image. Cold mounting remains the established NEM-4 flow.
The adapter does not invent a success or timeout if Main stops servicing it.

## Verification

Run in the existing offline simulator image:

```sh
MMC_HPS_OUT=build/sim/UNIQUE tests/phone/mmc_hps/run.sh
```

Final2026-11-16 direct fixture:48cases/33,287clocks PASS. It covers original
read/admission controls plus writable policy, immutable descriptors, exact
outgoing extent, wrong-direction/short/skipped/extra words, footer/EOF,
read-only capture, guest reset before ACK/during transfer, init reset and busy
replacement quarantine.

The actual local three-slot hps_io/native card fixture passes604,018clocks:
20reads,4persistedwrites,2other-slot reads,2bulk reads,18delayed tail halfwords
and2,128overlapping-request clocks. Serial MMC peer checks CMD24, two CMD25
blocks, independently expected HPS halfwords, readback after remount, CRC
rejection, Linux and both CSD WP flags, EOF/footer and selected RAM-slot
retention through guest reset. It retains metadata/short-transfer quarantine,
other-slot isolation and the existing read/reset controls.

prepare_hps.py changes only the existing PS/2 generated-scope names for simulator
compatibility; the actual HPS SD protocol is unchanged. Strict1364-2001 lint
passes. Existing card EOF/version, host and UPP/TX/RX DMA/IRQ tests pass too.
Fitted area/timing, native phone writes and Linux reboot persistence remain
unverified; see docs/mmc-writes.md and evidence/mmc-writes-20261116.json.
