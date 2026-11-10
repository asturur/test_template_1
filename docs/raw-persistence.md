# Raw C: and PMM persistence

The default build retains original NEM-4 firmware, ARM920/ZAP, phone/timer
profile, NOR models and scalar DDR persistence transport. C: and PMM mount
independently through stock MiSTer virtual-disk I/O. The D3 build adds
[bulk persistence](ddr-bulk-persistence.md) and
[ordered background saving](background-save.md) with the same image format.

## Files and migration

| Slot | Image | Exact size | Region/file offset |
| --- | --- | --- | --- |
| S0 | `boot0.vhd` | 4,194,304 bytes | C: byte zero at file byte zero |
| S1 | `boot1.vhd` | 65,536 bytes | PMM byte zero at file byte zero |
| S2 | Reserved for future MMC | Unsupported | No disk requests; reads return `ffff` |
| S3 | Diagnostic `.NGD` | Existing diagnostic format | Previously S1 |

These are raw byte arrays. The `.vhd` suffix does not imply a VHD header/footer,
partition table or FAT filesystem. Renaming NGA is not conversion. Both images
are mandatory; no PMM is created or formatted implicitly. Move an existing
manually mounted diagnostic image from S1 to S3. Do not name it `boot1.vhd`.
The `.rom` namespace is unchanged: `boot.rom`, `boot1.rom`, NOS `boot2.rom` and
Bluetooth `boot3.rom` still carry firmware/services and independent overlays.

Convert an existing validated NEM-4 NGA into **new** files:

```sh
python3 tools/prepare_mister_save.py split-raw handset.NGA \
  --cdrive boot0.vhd --pmm boot1.vhd --manifest handset-raw.json
```

The converter checks exact NGA size, magic/version, supported profile, C:/PMM
geometry, zero reserved metadata and header CRC. It extracts C: at `0x200` and
PMM at `0x400200` without changing any byte. The manifest records source path,
source and payload hashes, complete original header, firmware/profile identity
and region geometry. Every destination is created exclusively; existing files,
including inputs or aliases, are rejected. Partial output reservations from a
failed operation are removed, while existing files remain untouched. Keep the
original NGA and manifest for rollback and backup **both** raw images together.

Rebuild NGA using the current raw contents and original metadata:

```sh
python3 tools/prepare_mister_save.py join-raw handset-raw.json \
  --cdrive boot0.vhd --pmm boot1.vhd --output restored-handset.NGA
```

Unchanged raw files reconstruct the NGA byte for byte and match its source
hash. Guest-modified exact-size raw payloads are also supported: the original
header remains valid because its CRC covers metadata, not mutable payloads.
This tool does not import QD/RH-29 saves or convert a foreign flash filesystem.
Raw mounts themselves cannot authenticate which firmware created their data;
retain conversion manifests and use matching NEM-4 images. The existing verified
stock-firmware load gate remains required before restoration can begin.

## Mount, save and reset contract

A mount event captures its own geometry and read-only flag immediately, even
before firmware validation or while the other slot restores. The shared HPS
metadata is not consulted later. C: and PMM may arrive in either order. One
scalar bridge, sector buffer and DDR requester serialize both devices; file
sector zero maps to region sector zero. Slot ACK selects buffer ingress, with
one retained ACK cycle for registered HPS data at handshake termination.
Diagnostic S3 uses its own buffer and ACK; reserved S2 never drives traffic.

The CPU remains held until **both** images finish restoring. Each image must
be writable and exactly the listed size. Missing/unmounted/invalid images hold
boot. Invalid geometry/read-only rejection persists per slot until that slot
is corrected or explicitly unmounted; an unrelated valid mount cannot hide it.
A zero-size event cleanly unmounts a clean image. A clean replacement restores
its image again, holding CPU release until complete.

Any replacement/removal of an active image, any replacement during a flush, or
any media change with dirty data/pending flash mutation fails closed. The
manager blocks further sector/DDR issue, retains DDR/dirty state, reports Error
and requires an explicit cold transport reset. A different image's first mount
is allowed while the first restores. An interrupted sector already acknowledged
by the host is uncertain; no rollback or atomic cross-image guarantee is made.

Save remains explicit through the existing OSD action. It waits for NOR
quiescence, snapshots dirty sectors and retries sectors changed during snapshot
or HPS transfer. A mutation during the final flush scan causes another pass.
Saved requires both images mounted, no new dirty event/pending flash mutation,
a completed dirty scan, and the final HPS ACK assertion **and deassertion**.
It means the host protocol completed; it does not prove physical storage
survives power loss. Timeouts/short reads/uncertain transfers report Error and
preserve unsaved DDR contents until explicit cold reset.

Warm phone reset requests defer until load/save finishes. CPU release is also
separately gated by both mounts and firmware/board initialization. Cold transport
reset is immediate: it cancels transfers, clears mount/tracker state and requires
both media to be mounted again. Dirty data is not promised to survive that
explicit cold reset. The D3 build can also run
[ordered background passes](background-save.md) when enabled in the OSD.

## Local verification

Run host conversion checks with `python3 tests/phone/save_image/raw_test.py`.
Run the following inside the existing `jotego/simulator:arm64` image with this
worktree mounted at `/work`, working directory `/work`, and network disabled:

```sh
sh tests/phone/raw_save/run-hps.sh
sh tests/phone/raw_save/run-nor.sh
sh tests/phone/raw_save/run-full.sh
```

The NOR test uses immutable stock core/extension fixtures at the existing
`build/firmware/nem4-factory/` paths and verifies all 20,905,984 firmware bytes
remain unchanged. The HPS tests use the actual maintained `sys/hps_io.sv`, with
only the existing test-only PS/2 generate-scope compatibility adjustment.
Full-size restore/reload compares all 1,064,960 C:/PMM words through the scalar
bridge. Small tests exercise four-slot routing, both mount orders, early events,
first/last sectors, simultaneous diagnostics, delayed ACK, mutation, invalid
media, active replacement, timeout and warm/cold reset.

Installed MiSTer Main automatic `boot0.vhd`/`boot1.vhd` mounting, physical Save
and power-cycle recovery, FPGA fit and timing have **not** been exercised here.
No firmware boot/UI completion or phone performance improvement is claimed.
