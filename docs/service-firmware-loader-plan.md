# Original service firmware and separate user images

## Scope and difficulty

Implementation plan for milestone 7.6, requested 2026-11-07. The first
firmware-only slice is now implemented; independent raw persistence remains
planned below.

## Implemented firmware-only slice (2026-11-07)

`rtl/ngage_service_loader.v` replaces the NGB download path in `Template.sv`.
Only the audited 4.03 pair is supported: copy the original `nem440.3c1` to
`boot.rom` and `nem440.326` to `boot1.rom` in the core's configured game folder.
These are unchanged service containers, not renamed assembled binaries.
Automatic indices00/40 and OSD F1 MCU/F2 PPM selectors are supported. Either
order works; each slot can be reloaded independently before mounting a save.
Legacy NGB remains a host migration/seed format and a tested old loader module,
but is no longer a top-level firmware input.

For this narrow slice **keep the existing NGA on S0 and diagnostics on S1**.
Load both firmware slots, then mount the existing working save. There are no
new raw C:/PMM files or block-device changes. Service loading never writes the
C:/PMM backing regions or guard. `ngage_save_header` profile0 accepts either
existing seed-provenance ID1/2 with the same exact firmware SHA fields, header
CRC, sizes and reserved words; legacy callers1/2 still require an exact ID.
NGA contents are never rewritten to migrate the profile. Firmware reload is
still blocked while a save is mounted, busy or in error. Phone reset retains
loaded firmware; only cold transport reset clears the two valid bits.

The HDL parser is deliberately fixed-profile: it skips exactly0x2def2 MCU
prefix bytes or0xd9 PPM prefix bytes, rather than searching markers or running
the host flashing algorithm. The full container length/CRC validates every
skipped byte. The maintained host oracle additionally parses bounded TLVs,
checks the exact algorithm preamble/length/tail boundary and canonical SHA-256.
Data records have bounded lengths, header/payload checksums and whole-record
firmware-range checks. Byte unpacking handles odd offsets and PPM's one zero
transport pad. The first load erases only firmware backing toFF; subsequent
loads clear only the selected slot's fixed ownership, preserving the other
slot. Registered DDR requests drain before slot validity; failures invalidate
the slot with no rollback, keeping the CPU held until a valid reload.

Run the read-only host comparison with `python3 tools/service_firmware.py`.
Run `tests/phone/service_loader/run.sh` inside `jotego/simulator:arm64` for actual
hps_io + production DDR adapter verification; outputs are under
`build/sim/service-loader/` and small retained logs under
`scratch/service-rom-loader/validation/`. See latest status for measured results.
The hps_io simulation uses only the existing test-only PS/2 scope qualification;
file-transfer logic is unchanged. Real Main auto-loading, board acceptance and
post-fit loader timing remain unverified. No new long-run checkpoint is claimed.

## Remaining complete-workflow scope

This is a **moderate loader/storage refactor**, not a CPU redesign. The address
translation is small and already understood. The main work is a byte-stream
container parser, deterministic overlay/reload behavior, and decoupling C:/PMM
sector ownership from the current NGA header. Expect several focused code/test
iterations plus a MiSTer acceptance session; no reliable elapsed-time promise
is implied. Keep this independent of the in-flight timing build.

Accepted end-user layout under the core's configured game directory:

| File | Contents / ownership |
| --- | --- |
| `boot.rom` | Original `nem440.3c1` MCU container, renamed/copied unchanged |
| `boot1.rom` | Original `nem440.326` PPM container, renamed/copied unchanged |
| `C.img` | Raw 4 MiB writable C: NOR contents; mounted on S0, byte zero is C: byte zero |
| `PMM.img` | Raw 64 KiB writable PMM; independent S1 mount, byte zero is PMM byte zero |
| `diagnostics.ngd` | Existing diagnostic disk, moved to S2 |

PPM is language/content firmware. PMM is writable phone parameter storage.
They are separate components. No bundled C: seed, firmware hash header or PMM
tail in `C.img`. Firmware remains resident in DDR. Renaming the two service
files is the only firmware preparation required from the user; no repacking,
plaintext conversion or workstation assembler prerequisite.

## Audited inputs and format

Initial support is **the exact audited NEM-4 4.03 pair**, not arbitrary Nokia
files or every language/version. Broader profiles can follow once tested.

| Input | Bytes | Records | Payload bytes | SHA-256 |
| --- | ---: | ---: | ---: | --- |
| `nem440.3c1` | 18,777,938 | 2,268 | 18,567,112 | `e948c435c977772a30ff2dd8ef608f7542a978c0acfd257bc0986925fd548690` |
| `nem440.326` | 1,361,703 | 167 | 1,359,816 | `fd4126eeaddf5c0cd72a9961f51e283bd1ed4245106e20f01d5a5551e85fddc7` |

Retained sources: `firmware/NEM-04 v.04.03 N-GAGE/`; validated extraction
reports under `scratch/nem440-flash-extract/out/`. Format research is in
`scratch/nem440-flash-extract/extract.py`; factory assembly oracle is
`scratch/authentic-flash-image/assemble.py`.

Files have an A2 prefix, TLV metadata and addressed type-14 data records.
MCU also contains a host flashing algorithm (187,796 bytes), which the FPGA
must skip, never execute. For this profile the algorithm tail is exactly 66
bytes; MCU first data record is at 0x2def2, PPM first record at 0xd9. Do not copy
the exploratory extractor's unbounded scan for the next 0x14 marker. Promote
its discoveries into a bounded parser with exact state transitions.

Each data record has a ten-byte header: marker, big-endian 32-bit physical
address, payload checksum, big-endian 24-bit length, header checksum; then
payload. Maximum observed payload is 8,192 bytes. Header/payload sums are
checked independently. The 64-byte metadata signature is not being claimed
as cryptographically authenticated. A fixed-profile full-container CRC/length
can reuse existing CRC logic for non-adversarial identification; keep canonical
SHA-256 values in host tooling/fixtures. Do not add a large combinational hash
engine to the runtime critical paths.

## Address shifts: reuse the current backing layout

All ends below are exclusive. Add DDR base 0x30000000 to the backing offset;
no runtime relocation of firmware instructions is involved.

| Service physical address | Backing offset |
| --- | --- |
| `[00000000,00700000)` | `physical` |
| `[02000000,02400000)` | `00700000 + physical - 02000000` |
| `[04000000,04800000)` | `00b00000 + physical - 04000000` |
| `[00700000,007f0000)` | `01300000 + physical - 00700000` |

These match `rtl/ngage_rom_map.sv`. Writable C: `[02400000,02800000)` and PMM
`[007f0000,00800000)` are **not firmware load targets**. Reject payload writes
outside the selected profile's allowed ranges, including either writable bank.
Initialize only firmware backing `[0,013f0000)` to FF; retain the guard before
C: at 01400000. Preserve the existing erased personalization-hole assumption
at physical `[12c,164)`, rather than inventing per-device identity bytes.

PPM overlays MCU data; the split between old `core.bin` and `extension.bin`
is not the split between the two service files. In particular, `boot1.rom`
must not be copied wholesale to DDR+0x11c0000 or DDR+8 MiB.

The normal flash-array read path keeps the existing per-halfword descrambler
for physical `[0000a000,002b3000)`. DDR stores original scrambled payload.
Command/status responses and C:/PMM retain their current bypass rules. Verify
raw backing hashes and guest-visible digest behavior separately; raw-container
or raw-backing MD5 is not interchangeable with the firmware's decoded digest.
No digest/firmware patch is permitted.

## Loading order and transport details to handle explicitly

Reviewed official Main at
[`cc47bad62f4c9b6edea55aee3de12bf90855667c`](https://github.com/MiSTer-devel/Main_MiSTer/blob/cc47bad62f4c9b6edea55aee3de12bf90855667c/user_io.cpp#L1687).
It tries numbered boot files with indices `i << 6` before falling back to
legacy `boot.rom` at index zero. Consequently **boot1.rom can arrive before
boot.rom**. The installed board Main revision is not yet audited. Add explicit
manual MCU/PPM selectors too; test their indices as well as automatic 00/40
indices through the actual `hps_io` interface. Do not assume arrival order or
accept a filename/extension alone as a validated firmware profile.

Recommended first implementation: **fixed-profile byte ownership**. PPM owns
exactly these physical ranges for this pair:

- `[00000000,0000012c)` and `[00000164,00010000)`;
- `[00700000,0076c000)`;
- `[04730000,04800000)`.

MCU parsing validates all its bytes/checksums but does not overwrite these
PPM-owned bytes. PPM writes its owned bytes. This preserves logical MCU-then-
PPM priority in either arrival order without retaining both containers or
adding a loader read/replay client to DDR. A selected file reload clears only
its owned ranges. Admit only the audited header/profile and check each address
before writing; full-file CRC validity is established only at EOF. Streaming
may have written a rejected file's bytes into firmware backing, so invalidate
that slot before loading and keep the CPU held after any error until a complete
valid reload. Do not promise rollback to the previous firmware. C:/PMM must
remain untouched even on failure.
A new/unknown profile cannot reuse a previous profile's valid flags.

For future arbitrary profiles, stage the PPM container in a separately audited
DDR region and replay it after MCU changes, or derive an ownership map from a
fully validated staged pair. Do not extend the hardcoded 4.03 ranges by guess.
`boot0.rom` plus `boot1.rom` can be offered as a natural-order alias, but the
requested `boot.rom`/`boot1.rom` workflow must work too.

Software feasibility check already passes both orders and same-file reloads:
`scratch/service-rom-loader/check_mapping.py`; tracked result
`docs/evidence/service-rom-mapping-check-2026-11-07.json`. All 2,435 record
checksums and all 20,905,984 assembled backing bytes match the current oracle.
This is **not** an HDL parser, erase/reload-state or real HPS validation.

The PPM file length is **odd**, and its data starts at odd file offset 0xd9.
Keep WIDE=1 initially to preserve the existing 16-bit sector-buffer interface.
Add a two-byte stream unpacker and byte enables; do not assume record/payload
headers are aligned to ioctl words. Main's
[`spi_write`](https://github.com/MiSTer-devel/Main_MiSTer/blob/cc47bad62f4c9b6edea55aee3de12bf90855667c/spi.cpp#L185)
sends a zero high byte for a final odd byte. The audited profile permits only
that single transport pad at its known endpoint; it is not part of the file
checksum/payload. Current hps_io does not expose the original byte length, so
one appended zero is indistinguishable from that transport padding. Do not
claim arbitrary exact-byte EOF verification from this interface.

## Work packages and acceptance gates

**7.6a — strict host oracle and fixtures.** Promote the scratch parser/assembly
rules to maintained read-only tooling. Validate bounds/truncation/TLV lengths,
algorithm/tail boundaries, header/payload checksums, record ranges, known pair,
coverage and holes. Produce profile constants and compact expected-write
fixtures. Never change the original inputs. Both input orders and reloads must
produce current core/extension SHA-256 values and the unchanged decoded digest.

**7.6b — streaming service loader.** Add the byte unpacker, parser, ownership/
address mapper and acknowledged DDR writer. Use small registered stages and
`ioctl_wait`; never chain a full record checksum in one clock. No whole-file
BRAM buffering. Clear firmware-owned bytes only; keep C:/PMM untouched. Track
MCU-valid, PPM-valid, download/erase/drain and visible failure reason. File-valid
is set only after EOF/checksum checks and the **last DDR acknowledgement**.
Phone reset retains loaded firmware; cold reconfiguration requires fresh loads.
Test both orders, reload after valid load, bad pairs, corruption, extra/truncated
data, odd transport endings, stalls, reset and abort at every parser state.

**7.6c — independent raw persistence.** Refactor `ngage_save_manager.sv` so
restores/flushes use C: LBA0..8191 and PMM LBA0..127 on separate devices; remove
NGA header validation/firmware binding from the raw image path. Reuse dirty
tracking, sector snapshots and acknowledged `ngage_sd_sector` transfers.
Increase `Template.sv`/hps_io VDNUM from 2 to 3; widen and route all mount, LBA,
ACK, read/write and sector-buffer ownership signals, moving diagnostics to S2.
Latch the shared image-size/read-only metadata on the correct device's mount
event. Handle concurrent requests with one explicit owner; do not mix ACKs.
Reject wrong-size images, missing media and read-only writable mounts visibly.
Do not silently seed/recreate a missing or damaged user image.

**7.6d — top integration and migration kit.** Replace bundle-only OSD/reset
predicates with firmware-pair-ready plus C-restored/PMM-restored gates. Serialize
firmware loads against saving, dirty user data, outstanding flash operations
and CPU execution, reusing `ngage_bundle_gate` protections with the new meaning.
Do not let a firmware load clear dirty flags or an authoritative mounted image.
Keep a selectable legacy diagnostic path during transition, with explicit input
indices, or retire it after acceptance; it must not remain the normal user flow.
Provide a non-overwriting migration helper: old NGA bytes `[200,400200)` become
C.img, `[400200,410200)` become PMM.img. No firmware rewriting is required.
Creating a fresh erased PMM must be an explicit one-time action on a new file.

**7.6e — full validation and MiSTer session.** Replay original service files
through actual hps_io protocol into the HDL loader and modeled DDR. Compare
every backing byte/hole/overlay and descrambled boot reads to the oracle, then
cold-run current hardware-bound CPU with the same stock firmware. Swap two raw
C: files, modify/flush/remount them and PMM independently, checking first/last
sectors, dirty/re-dirty races, missing/changed media, timeouts and warm reset.
Firmware hashes must remain unchanged while switching user files. Verify S2
diagnostics during persistence traffic. Build/STA and a disposable-image MiSTer
session are separate acceptance gates. Preserve frozen long-run checkpoints;
new loader/backing state requires a new simulation lineage.

Suggested implementation order: finish 7.6a while timing builds run; then
7.6b, then persistence/top integration in one coherent change before advertising
the new user workflow. Delivering just renamed assembled binaries would not
satisfy this milestone. Changes must enter a separate build from the current
bus-pipeline timing measurement so results remain attributable.
