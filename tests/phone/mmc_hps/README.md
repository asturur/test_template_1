# Production MMC HPS transport

`ngage_mmc_hps.v` owns the MMC slot's read transactions and admits manually
mounted production images before the native card becomes present. Template
must connect only slot 2 mount/ACK/request signals; the halfword buffer bus is
shared. Slots 0/1 remain C:/PMM; MMC uses slot 2. The diagnostic disk
slot was removed. The adapter contains no phone chip or D550/AMA wiring.

The actual local `sys/hps_io.sv` contract is WIDE=1, 13-bit halfword index,
16-bit data, and a six-bit blocks-minus-one count. It supports up to 32 sectors
(16 KiB). The pinned native card emits single-sector or up-to-eight-sector
reads; the adapter preserves that 4 KiB bulk path and rejects larger native
requests. It captures LBA/count before advertising work and holds them through
HPS acceptance. An advertised request cannot be withdrawn safely because Main
has no separate acceptance/cancellation channel; it drains through ACK fall and
the known local HPS write pipeline even across reset or mount changes.

## Admission and read-only gate

A nonzero mounted image must be 512-byte aligned, at least 1,024 bytes and no
larger than 1 GiB plus its 512-byte footer. Size zero is ordinary removal:
quietly absent, with any old request drained. The native card's first request
must fetch the last image sector, with a one-sector extent. There is no duplicate
preflight read. Its original bytes must contain:

- `NGAGEMMC` magic and byte-8 version 1.
- Valid supplied CID and CSD CRC7/end bits. The production path does not repair
  bad original identity bytes or synthesize a raw-image identity.
- Supported CSD structure 2, specification version 3 and READ_BL_LEN 9; nonzero
  decoded capacity covering the entire payload.
- Byte-addressed OCR access bits `[30:29] == 0`. Other OCR bits remain opaque;
  no extra voltage restriction is inferred from the local evidence.

The first HPS read's words go to the loader cache as they arrive, but its ACK
fall is held until complete ordered data and original-byte admission pass. On
failure the adapter resets/quarantines the card before it can become present.
Later requests must fit the payload, excluding the footer. Subsequent bulk
prefixes forward immediately; no whole-4-KiB staging delay is introduced.

Every selected-slot transfer must contain exactly its captured extent in
strictly increasing halfword order from index zero. Short, duplicate,
out-of-range or extra words quarantine the card; a malformed word is never
forwarded and a failed transfer never returns a live completion. Already
forwarded prefixes can precede a later error and are provisional on cancellation.
The shared write strobe is qualified by the owned slot's ACK or previous ACK,
preserving the final pipelined word after ACK falls while isolating other slots.

`card_img_readonly` is always one, even when Linux mounted the file writable.
`hps_sd_wr` is always zero. An unexpected native write faults/resets the card
without advertising a write or returning a fake ACK. Enabling writes requires
a separate stable sector snapshot, retained HPS readback source and a defined
media/HPS ownership policy across remount/reset; those are outside this gate.

## Reset and media ownership

`init_reset` is the cold/global transport initializer (`~pll_locked` in the
production wiring). Its rising edge may forget retained media, but it still
drains any already advertised transaction. Configuration-time initialization
establishes the transport state; runtime reset does not erase owned HPS work.
`guest_reset` covers ordinary Reset and CPU Hold. It retains the latest slot-2
size and replays exactly one synthetic mount notification after old transport
work and the HPS pipeline drain. A new mount supersedes old retained metadata.
Generations plus sticky cancellation prevent old data or ACK from entering a
reset/re-mounted card. Init takes precedence over guest-only replay; a genuine
simultaneous new mount can supply fresh metadata.

A fault remains quarantined until a new mount or init event. The adapter does
not invent a timeout or success response if Main stops servicing its request.
This read-only drain policy does not establish atomic writable hot replacement
or durability on MiSTer Main. Physical native-card timing and routing remain
unverified.

## Verification

Run inside the installed offline image from the repository root:

```sh
MMC_HPS_OUT=scratch/ngage2-integration/p3-production/hps/pinned \
  tests/phone/mmc_hps/run.sh
```

The direct external-port fixture compiles with `iverilog -g2001` and passes
36 cases in 24,435 clocks. It covers size and all identity/admission checks,
minimum/maximum media geometry, source/count capture, 4-KiB streaming prefixes,
metadata/payload boundaries, exact word count/order, unrelated bus strobes,
ACK already high, delayed ACK, resets before ACK and during transfer, init plus
guest reset, removal during ownership, repeated/latest remounts and write
rejection. It checks that invalid metadata cannot produce a live ACK fall.

The second fixture runs the actual local three-slot `hps_io.sv`, the standalone
native card and adapter. It passes in 265,094 clocks: nine card reads, two
simultaneous other-slot reads, two 4-KiB reads, seven final halfwords captured
after slot-2 ACK fell and 2,128 cycles of overlapping slot requests. A real
1-bit MMC peer identifies the card, checks read data/CRC16, performs CMD18,
CMD12 and verifies forced WP. The fixture checks other-slot mount isolation,
guest reset during accepted HPS data, retained metadata reload, original-footer
quarantine, short-transfer quarantine and valid remount recovery.

`prepare_hps.py` makes the same PS/2 generated-scope naming compatibility copy
used by existing HPS fixtures. It changes only PS/2 scope references, not the SD
protocol. The actual module's command `16`, `0217`, mount `1c`, size `1d`, ACK
and buffer-pipeline behavior are exercised. C:/PMM peers in this test are
independent pending slot requests, not the complete save manager.

Pinned Verible is idempotent. Strict 1364-2001 Verilator lint passes with only
`UNUSEDSIGNAL` disabled for the intentionally ignored Linux readonly flag,
unused card write data and opaque OCR bits. This does not establish synthesis,
fit, complete firmware mounting or physical card operation. Evidence/source
hashes are in `scratch/ngage2-integration/p3-production/hps/results.json`.
