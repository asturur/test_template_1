# MMC port: original contract, images and donor safety

P3.0 image preservation is implemented and tested on the host. P3.1 has
reproduced donor write-loss, footer-version and CMD16-cache fixes on a separate branch.
Host/card ports and read-only production wiring are verified locally in
Verilog-2001. Original-driver execution and firmware card mounting remain open.
The full dependency/test sequence is in [merge-plan.md](../merge-plan.md#p3-mmc-host-card-and-tooling).
Final P2 CPU/boot checks pass again after the production MMC ownership changes.

## Original NEM-4 evidence and physical boundary

The donor host is derived from RH-29/QD v4.60. Original NEM-4 instructions
corroborate these register uses:

| Physical address | Original use |
| --- | --- |
| `0c120604` | Control, start bit 0 polled until clear; write types 5/6/7, read types 8/9/10, initialization `40` |
| `0c120608` | Exact logical data length |
| `0c12060c/610` | Initialized with `1dc130`; timebase is unverified |
| `0c120614` | Initialized with `280`; divider interpretation is unverified |
| `0c120618` | Bit 3 command busy, bit 2 data busy, bit 8 response available |
| `0c12061c/620` | Command/argument; response FIFO at `620`, bytes extracted most significant first |
| `0c120624` | Byte-stream FIFO, DMA alias `10120624`, request line 2 |

Original status extraction at `503f52e4` recognizes command errors in bits
1/6/9 and data errors in bits 0/5/7/10. The donor does not generate every
recognized condition. Type 4/R1busy behavior and clock/timeout semantics need
independent peer tests before adoption.

The original kernel name table begins at `503236c0`, with eight-byte entries:

| Source | Name | Table entry | Bound by original EPBUS |
| --- | --- | --- | --- |
| 21 | IrqMMCDataIdle | `50323768` | Yes |
| 22 | IrqMMCDataRdy | `50323770` | No |
| 23 | IrqMMCCmdIdle | `50323778` | Yes |
| 24 | IrqMMCCmdRdy | `50323780` | Yes |

Names and bindings do not establish every asserted level. In particular,
the donor's `22 = dataBusy` policy remains unverified for NEM-4.

EPBUS writes the exact host length at `503f4c24`, then rounds DMA length up
to four bytes (`add #3; bic #3` at `503f4cd8/4cdc`) before the TX/RX wrappers
at `503f57b8/57bc`. The FIFO therefore needs zero RX padding and discarded
TX padding for up to three bytes after the logical payload. DMA completion
must remain distinct from CRC acceptance and the card's programming busy
period. Lengths 1/2/3/5/511/512 are required integration cases.

The [chip inventory](chip-inventory.md) places the MMC connector X553 on the
D550 audio-DSP/card-interface path, with `AMA-WD2_BUS(4:0)`. A direct host-to-card
CLK/CMD/DAT0 model must remain a named transaction-level shortcut. Preserve
the separate DSP boundary and explicitly unimplemented AMA behavior. No
phone pin timing or electrical behavior is verified by this source audit.

The audited core fixture is the assembled NEM-4 4.03 service-image profile
(`be8b2ecd…`), distinct from the stock THC dump (`26ca1dd9…`). Direct byte
comparison proves the entire audited `50320000..503fd800` interval identical
between them. Exact source paths, sizes, hashes, instructions and findings
are recorded in [source-audit evidence](evidence/mmc-source-audit-2026-11-11.json);
bounded excerpts remain in `scratch/ngage2-integration/p3-audit/`.

## P3.0: lossless image preservation

`tools/ngage_mmc_image.py` uses Python's standard library. It streams in 1 MiB
chunks, opens sources read-only, creates outputs exclusively and rolls back
only outputs created by that invocation. No actual user disk/card image was
changed for this slice.

```sh
python3 tools/ngage_mmc_image.py inspect card.mmc
python3 tools/ngage_mmc_image.py export-raw card.mmc card.img
python3 tools/ngage_mmc_image.py import-raw card.img restored.mmc --metadata card.img.json
sh tests/tools/mmc_image/run.sh
```

The container is raw 512-byte sectors followed by one `NGAGEMMC` v1 metadata
sector: magic at 0, version at 8, CID at 16, CSD at 32 and big-endian OCR at 48.
Export preserves the entire footer, including opaque unused bytes, in a
512-byte sidecar. JSON binds payload/footer/image bytes, sizes, SHA-256,
identity, interpreted capacity and source provenance. Import from that JSON
verifies all bindings; paths in metadata are never followed automatically.

Raw imports require explicit actual CID/CSD/OCR or metadata from an existing
card/sidecar/manifest. There is no synthesized default identity. CRC7/end bits
must be valid. Explicit `--normalize-register-crc` supports 15-byte or zero-CRC
Linux register readbacks and records both supplied and stored bytes. Existing
card metadata is never silently repaired.

Strict import supports the locally observed CSD structure 2, specification
version 3, READ_BL_LEN 9 and byte-addressing OCR. The capacity is
`(C_SIZE+1) * 2^(C_SIZE_MULT+2) * 2^READ_BL_LEN`, up to 1 GiB for this profile.
CRC-valid unknown profiles can be inspected/exported with capacity unknown;
strict import rejects them. Unknown footer versions are rejected. Empty,
unaligned and oversized payloads are rejected. A shorter payload needs
`--allow-truncated` and is explicitly ineligible for writable mounting; no
missing sectors are fabricated. Full-size write-protected images are likewise
ineligible for writing. Eligibility is a format policy, not a demonstrated
hardware mount.

All **14 generated host tests pass**. They use an independent polynomial
CRC7 oracle and cover all-byte round trips, offsets, identity and repair
provenance, observed retail capacity arithmetic, unknown profiles, corrupt
metadata/manifests, partial extents, read-only inputs, output collisions,
rollback, nonregular input rejection and bounded reads. A retained generated
2,560-byte image round-trips exactly, SHA-256
`556750788346c46aff8079434115fccc5d5ba5bd1c7386eef27977b78117de70`.
See [tool evidence](evidence/mmc-image-tool-2026-11-11.json) and
[usage/tests](../tests/tools/mmc_image/README.md).

This tool does not build FAT filesystems or parse Aaru archives. MMC card
metadata and identity are separate from the C:/PMM flash-image work; no
MiSTer MMC slot or protected-title launch is implied.

## P3.1: reproduced donor EOF write loss

At donor base `7be19cd`, CMD24 at byte 1536 on a three-sector payload with
four-sector CSD capacity returns successful R1 `00000900`, accepts data token
`00101`, releases busy and performs **zero HPS writes**. The normal new
regression fails this baseline at clock 7,922. A plain one-sector raw image
also exposes the defect because the donor's generated CSD advertises a
minimum of four sectors.

The reviewed patch checks actual payload extent as well as CSD capacity for
initial CMD24/25 and continued CMD25 blocks. Wide byte arithmetic preserves
carries and prevents a next-block address above 4 GiB aliasing LBA 0. Defensive
out-of-file handling sets OUT_OF_RANGE and cannot publish valid cache data
or continue successful programming. Read-zero tails beyond partial payloads
remain. Existing write-protection, length, alignment and range error precedence
is preserved.

The independent wire/HPS test passes **five mounts, four reads, four persisted
writes and 282,492 clocks**, with warning-free host Icarus 13 builds. It checks
initial/continued EOF rejection, final backed-sector persistence, delayed ACK,
CRC rejection, read padding, CMD12/CMD13 recovery, WP precedence, tiny raw
images and sparse 4 GiB boundary arithmetic. It drives only external ports,
not internal forced state. Astra's source review found no blocking regression
within this payload-bound scope.

The fix and portable regression are applied on donor branch
`codex/mmc-payload-eof-fix`, based on `7be19cd`; the actual donor rerun also
passes. Old donor branches remain intact. No commit or push has occurred for
this step. [Portable patch](evidence/donor-mmc-payload-eof-2026-11-11.patch)
and [evidence](evidence/donor-mmc-payload-eof-2026-11-11.json) include exact
source/log hashes. From the donor root:

```sh
sh sim/mmc-eof/run-one.sh
```

The defensive lost-bound path reuses negative token `01011` plus R1
OUT_OF_RANGE. Its native MMC 3.x semantics and direct lost-bound branch
coverage are unverified; normal EOF rejection occurs before data acceptance.
Atomic replacement of an already issued HPS write is also unverified.
Pinned-image execution and the existing donor C++/Verilator MMC regression
subsequently pass after Docker recovery; see the final verification below.

## P3.1: reject unknown footer versions

The EOF-fixed donor still accepts a footer with version 2 and interprets its
CID/CSD/OCR as version 1. An external-port baseline witness reproduces this;
the new policy regression fails that baseline at clock 1,388.

The loader now checks byte 8 independently of magic. Full magic with an
unsupported version leaves the model absent until another mount; it cannot
fall back to raw sectors and expose the footer as card data. This is a
software container policy, not a physical card behavior claim. Version 1
continues to preserve opaque unused bytes, and no-magic raw images keep the
existing fallback.

The applied donor test passes **seven mounts, 11 HPS reads, zero writes and
196,894 clocks**, including versions 0/2/255, v1 with nonzero reserved bytes,
no response after rejection, raw last-sector reads and reset/remount recovery.
The EOF test also passes again after this loader change (282,492 clocks).
Both host builds are warning-free. Source and result hashes are in
[version evidence](evidence/donor-mmc-footer-version-2026-11-11.json).
The [portable version patch](evidence/donor-mmc-footer-version-2026-11-11.patch)
applies after the EOF patch and includes its standalone regression.
No commit or push occurred; pinned-image and broad donor regressions subsequently pass.

## P3.1: preserve the last accepted CMD16 length

An independent host-register/CMD/DAT peer first accepts CMD16=64, then rejects
CMD16=128 with BLOCK_LEN_ERROR. The original host nevertheless emits 128 bytes
on the next length-zero data phase; the ordinary accepted-length oracle fails.

The cache-only fix requires short R1, matching command index, card transmission
bits, terminal end bit, valid CRC7 and no classified rejection bits. Original
NEM-4 instructions at `503f9fbc..503f9fc8` give error mask `fd3fa020`; the donor's
explicit COM_CRC_ERROR/ILLEGAL_COMMAND rejection adds bits 23/22, yielding
`fdffa020`. R2 and type-2/R3 cannot update the cache. Software CRC suppression
does not establish a valid accepted CMD16. The existing length clamp, response
FIFO and status behavior remain unchanged.

The applied donor test passes **31 pin-observed length-zero probes in 118,914
clocks**, covering all 18 rejection bits, CRC/framing/type errors, timeout,
status-only successful responses and reset. Outgoing payload length and CRC16
are checked independently, without internal state reads/forces. Icarus emits
its existing conservative `always_*` sensitivity notice; this is not a
notice-free build. The fixture is a native transaction peer, not an original
driver execution or phone timing measurement.

See [CMD16 evidence](evidence/donor-mmc-cmd16-cache-2026-11-11.json),
[original mask audit](evidence/mmc-cmd16-original-response-2026-11-11.json)
and the [portable patch](evidence/donor-mmc-cmd16-cache-2026-11-11.patch).
The [combined eight-file safety patch](evidence/donor-mmc-safety-2026-11-11.patch)
contains all three fixes/tests relative to `7be19cd`; its reverse check passes
against the actual donor checkout. [Final source hashes](evidence/donor-mmc-safety-2026-11-11.json)
preserve the applied snapshot. No commit or push occurred.

**General malformed-response error/status handling remains unchanged and
unfixed.** A malformed frame can still be delivered without a new framing
error; the cache guard only prevents CMD16 poisoning. This and mount/reset
abandoning or retargeting HPS ownership remain P3.1/P3.2 gates.

## Remaining acceptance sequence

Final P2 checks, standalone ports and P3.3 read-only production wiring pass.
Next run unchanged original EPBUS/DMA functions before a bounded firmware identify/mount/read
trace. Writable persistence and removal require separate HPS ownership,
reset, delayed-ACK, metadata/neighbor guards and persisted-byte checks.

## P3.2: standalone Verilog-2001 host and card

Added `rtl/ngage_mmc_host.v`, `rtl/ngage_mmc_card.v` and internal backing-cache
helper `rtl/ngage_mmc_dpram.v`. They preserve donor licenses/provenance and the
reviewed safety fixes. New maintained RTL compiles strictly as Verilog-2001;
no SystemVerilog port was added. This standalone stage preceded the production
QIP/board wiring below; neither invents the physical D550/AMA path.

| Check | Observed result |
| --- | --- |
| Host CMD16 independent public-pin peer | 31 probes, 118,914 clocks |
| Host TX/RX, lengths 1/2/3/5/511/512, rounded padding, FIFO stalls, CRC/token/timeout/reset and 5/6/7, 8/9/10 ordering | 28 cases at DIV4/FIFO16: 82,004 clocks; DIV12/FIFO8: 244,751; donor results match exactly |
| Card EOF/version wire/HPS tests | 282,492 / 196,894 clocks; four-state donor/port public-output lockstep passes |
| Unchanged card C++ suite | Donor, port and lockstep wrapper each pass 13,907,842 clocks with identical logs |
| Both native modules in donor peripheral harness | 3,665,197 clocks, runtime output byte-identical to donor; only two test-local instantiation names changed |

Pinned formatting is idempotent. Strict lint has no width/truncation warning;
intentional unused-bit/array-sensitivity notices are recorded in child evidence.
Astra independently reviewed priority, widths/casts, indexing, static temporary
lifetimes, task/reset ordering and dual-port RAM semantics; no translation
defect was found in the final hashes. Same-address dual RAM writes remain
undefined and outside valid traffic. General malformed-frame status, IRQ22,
native timing/defensive token and in-flight HPS replacement remain inherited
gaps, rather than solved phone behavior.

See [stage evidence](evidence/mmc-native-port-2026-11-11.json),
[host tests](../tests/phone/mmc_host/README.md) and
[card tests](../tests/phone/mmc_card/README.md). Private card/trace replays in
the peripheral harness are unavailable and explicitly skipped. No original
EPBUS execution, firmware mount, game launch, production slot or FPGA fit is
claimed by this standalone stage. P3.3 subsequently wires these ports as below.

Docker recovered after completion of the user's stalled application restart;
its VM was already stopped, and no data/settings reset or project checkpoint
operation occurred. All three focused fixes now pass inside the pinned image.
The existing donor MMC and peripheral C++ regressions also pass, including
3,665,197 peripheral clocks; the unavailable private game-card replay is
explicitly skipped. These results do not establish production MMC wiring,
an original-driver firmware mount or physical phone behavior. Final P2 CPU
and bounded-boot checks pass separately, including the subsequent removal of
the slow LCD selection. Pinned donor results and exact skips are in
[the verification manifest](evidence/donor-mmc-pinned-2026-11-11.json).

## P3.3: read-only production wiring

Template exposes **Mount MMC card (read only)** on slot 2 (`.mmc` files), with
C:/PMM on 0/1 and diagnostics on 3. The production QIP includes all native
modules and `ngage_mmc_hps.v`; no performance-selection switch is introduced.
The host belongs to UPP, the card to the board. Their direct CLK/CMD/DAT0
connection remains a shortcut for the missing D550/AMA path.

Host MMIO at `0c120600` participates in the captured UPP response owner,
including retained register bits and byte-lane FIFO side effects. Selector 2
TX (control 2)/RX (historically tested as control 3) descriptors capture route/width/count at start. Native RX uses control2; see the correction below.
MMC byte offers acquire the router and UPP FIFO reservation atomically, so
waiting for data/space need not occupy the shared route. All eight channels
retain independent ACK/error ownership. IRQ 21/23/24 use the modeled host
levels; 22 remains low. The internal command-busy hint suppresses speculative
prefetch for queued final CMD12 without blocking demand reads.

`ngage_mmc_hps.v` preserves native 1..8-sector bursts on actual WIDE1/BLKSZ2
HPS, qualifying global buffer writes by captured slot 2 ACK and its pipeline
tail. Before permitting the initial loader ACK to finish, it checks original
NGAGEMMC v1 metadata, supplied CID/CSD CRC7/end bits, supported structure 2,
specification 3, read length 9 and byte-addressing OCR, sector alignment and
payload capacity. Raw fallback or silently repaired identity cannot expose
a production card. Images are between 1,024 and 1,073,742,336 bytes including
the footer. Prefix images may be read-only; the adapter blocks requests beyond
their actual payload and never exposes the footer as ordinary card data.

Once advertised, HPS LBA/count ownership remains until ACK and delayed strobes
drain, even across reset/remount. Exact ordered halfword counts reject short,
duplicate or out-of-range transfers. Invalid sessions are quarantined; valid
streaming prefixes may already have been consumed before a later failure.
Guest reset/CPU Hold retains and reloads the latest mount after drain; cold
transport initialization forgets it. Size-zero removal is quiet, while invalid
nonzero media sets the existing diagnostic error indication. All card media
is forced read-only and HPS slot 2 write is hard-low. Writable snapshots,
replacement and persistence remain P3.5 work.

Pinned verification passes 36 direct HPS cases, an actual four-slot HPS/native
card fixture at 265,094 clocks, 30 captured bus/pin cases, and 96 all-channel
DMA matrix transfers plus focused boundaries at 667,085 clocks. The real
ZAP/MiSTer fixture passes exact CID, DMA 5+3 padding, odd PIO, ICU/ACK and WP
at 29,010 clocks, or 29,424 when CPU Hold interrupts metadata. It uses generated
nonprivate sectors and behavioral HPS/memory; the actual HPS fixture separately
covers two 4 KiB reads, other-slot traffic and seven delayed final words. Its
slot 0/1 peers are dummy pending requests, not the raw-save/NOR managers.

Existing LCD CPU/reset tests retain 130,685 frame clocks, and the original DMA
ISR/fresh 5M boot pass. The bounded boot has no mounted MMC or completed UI;
it also does not cover Template's selected D1/D2/D3 DDR chain. Formatter,
strict language tests, 185-file source graph and stubbed top pass. All 169
inputs remain unchanged through final verification. Astra's source review
found no remaining blocker; hardware fit/timing and original EPBUS/firmware
mount remain unverified. See [production evidence](evidence/mmc-production-2026-11-11.json),
[HPS tests](../tests/phone/mmc_hps/README.md),
[bus/DMA tests](../tests/phone/mmc_production/README.md) and
[authored ARM test](../tests/phone/mmc_mister/README.md).

## Original NEM-4 long-response correction (2026-11-14)

The first real SPMark04 mount failed at CMD2 before FAT reads. Native driver
execution now reproduces the response-ready/command-idle ordering failure and
verifies the small host correction. See [R2 evidence](mmc-r2-order.md). Hardware
mounting remains open; older authored tests alone did not establish it.

## Native receive start correction (2026-11-14)

The earlier RX3 qualification used an authored caller and missed native RX2.
Original kernel/helper execution with PRODUCTION enabled now catches and
verifies the corrected admission/pacing. R2 enumeration passes on FPGA, and
sector transfers pass locally with native RX2; final native mount requires the
next RBF. See [exact descriptor and tests](mmc-native-dma-control.md).

## Native hardware read acceptance: observed on 2026-11-14

Both original-driver gaps are corrected in HDL. The existing SPMark04 MMC
mounts with native16MB capacity and matching used bytes, and its application
loads/launches using original firmware. No source image or functional firmware
patch was needed. Benchmark3D Game reports failure, with no score; why remains
open. [Full result](mmc-spmark04.md). Writable cards/removal, wider titles,
end-to-end native file hash comparison and timing-clean sign-off remain separate
gates; the tested RX2 build misses setup by0.270ns.
