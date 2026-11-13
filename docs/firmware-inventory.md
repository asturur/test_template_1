# Local firmware and filesystem inventory

Checkpoint: [status.md](status.md). Inspected 2026-10-27.
Reproduce with `make firmware-inventory`; detailed hashes, file addresses and
comparisons are saved in `build/firmware/inventory.json`.
Only local inputs were read. No firmware was executed, altered, or installed.
No HDL simulation was needed for this audit.

## The three distinct firmware sets

| Set | Version text in its unpacked tree | ROM bytes / MiB | Files named by ROM | Exact unpacked matches | Additional unpacked files |
| --- | --- | --- | ---: | ---: | ---: |
| Original N-Gage, NEM-4 | V 4.03, 26-11-2003 | 18,612,224 / 17.75 | 1,017 | 1,017 | 507 |
| QD retail, RH-29 | V 04.10, 09-09-2004 | 18,284,544 / 17.4375 | 1,060 | 1,060 | 517 |
| QD developer, bundle label RH-4 | G 04.10 Game Developer SW Variant, 29-11-2004; version text says RH-29 | 19,070,976 / 18.1875 | 1,164 | 1,164 | 18 IDA databases |

All three declare virtual base `0x50000000`; each header's ROM size equals its
file length. All 3,241 ROM filesystem entries have a byte-identical unpacked file.
The top-level `firmware/SYM.ROM` is an exact duplicate of the NEM-4 image, not a
fourth distinct version. The existing CPU/board profile remains pinned to NEM-4;
no QD image was substituted or authorized as an identical hardware map.

Paths:

- NEM-4 ROM/BOOT/ROOT: `firmware/Nokia N-Gage/Data/roms/NEM-4/`.
  Unpacked tree: `firmware/Nokia N-Gage/Data/drives/z/NEM-4/`.
- QD retail ROM/BOOT/ROOT: `firmware/Nokia N-Gage/Data/roms/RH-29/`.
  Unpacked tree: `firmware/Nokia N-Gage/Data/drives/z/RH-29/`.
- QD developer ROM/BOOT/ROOT:
  `firmware/Nokia N-Gage/N-Gage QD Dev (RH-4)/Data/roms/rh-4/`.
  Unpacked tree:
  `firmware/Nokia N-Gage/N-Gage QD Dev (RH-4)/Data/drives/z/rh-4/`.

ROM SHA-256 values:

- NEM-4: `afc1cc8b693f2b68d23ca203aa4d4eb4266baad4ab718f013a33b915d39574ef`.
- QD retail: `4595b100981ec64aae6194841c730ab44bfa044f007208539fc3653ccf14db69`.
- QD developer: `582a049f9e573c0245441ddb01bb5b3db76ede7677ec05cafc16f314a02ef6ef`.

The RH-4 folder/device configuration is a bundle label. Its own `sw.txt` says
RH-29 and Game Developer SW Variant; it is not an original NEM-4 developer ROM.
The developer bundle also contains external analysis artifacts, so its contents
are not assumed to be untouched factory media merely because of the folder name.

## Important discovery: retail ROOT contains additional ROM content

The retail ROOT files are not slices of their corresponding core ROMs:

| Set | ROOT bytes | Extra unpacked files found intact in ROOT | Inferred ROOT virtual interval, end exclusive |
| --- | ---: | ---: | --- |
| NEM-4 | 1,252,552 | All 507 | `0x5123e338..0x51370000` |
| QD retail | 1,316,008 | All 517 | `0x5123eb58..0x51380000` |
| QD developer | 15,835,536 | None beyond its 18 analysis databases | `0x50315e70..0x51230000` |

The developer ROOT is byte-for-byte the ROM interval from file offset `0x315e70`
to the ROM end. In contrast, all additional retail files are present in their
own ROOT snapshots, with most being extra language resources:

- NEM-4: 211 `.r02` and 211 `.r78` files, plus dictionary DLLs, sounds/configs,
  other resources. Additional files total 1,241,456 bytes.
- QD retail: 215 `.r02` and 215 `.r78` files and associated data.
  Additional files total 1,260,661 bytes.

### How the virtual placement was recovered

Two independent extra files, `System/T9Ldb/t9french.dll` and `t9romanian.dll`,
are found intact inside each retail ROOT dump. Their embedded XIP code addresses
identify their module bases after subtracting the 100-byte EKA1 serialized
module header. Subtracting each module's byte offset inside ROOT then gives the
same ROOT base twice. The header size follows the retained EKA2L1 ROM-image parser
(`src/emu/loader/include/loader/romimage.h`); linked addresses are read from the
actual supplied binaries, not invented from filenames.

NEM-4 anchors:

| File | Module virtual base | Byte offset inside ROOT | Implied ROOT base |
| --- | --- | --- | --- |
| `t9french.dll` | `0x513452a0` | `0x00106f68` | `0x5123e338` |
| `t9romanian.dll` | `0x51350bc0` | `0x00112888` | `0x5123e338` |

Both QD retail anchors independently imply `0x5123eb58`.
These are inferred **virtual** placements, not independently verified physical
chip offsets. The original ROOT block starts after the current scanner's next
virtual address `0x511c0000`, strongly supporting additional language/extension
ROM content beyond the core image.

### What is still missing

The failed candidate-header read corresponds to virtual `0x511c001c` under the
current mapping. It is before the recovered ROOT block's start. The original
extension header and earlier directory metadata are therefore not supplied by
this ROOT snapshot. Some child-directory pointers in its first root directory
also point before the snapshot, confirming a missing directory prefix.

Do not concatenate BOOT + ROOT + SYM or call ROOT a whole raw chip image.
The additional file bytes and much of their virtual placement are now known;
exact extension metadata, possible gaps and the physical mapping still require
recovery or an explicitly documented reconstruction. The previous proposal to
fill all remaining retail ROM space as erased/no-extension must now be revisited:
there is real additional retail ROM content already present in the inputs.

## Named driver and OS references now available

For NEM-4, verified ROM entries provide these direct disassembly targets:

| File | Virtual module base | File offset in SYM.ROM | Why useful |
| --- | --- | --- | --- |
| `System/Libs/ekern.exe` | `0x50320f9c` | `0x00320f9c` | Kernel startup and later device/HAL paths |
| `System/Libs/medint.pdd` | `0x50384990` | `0x00384990` | Internal-media/flash access lead |
| `System/Libs/lcd.ldd` | `0x504001e0` | `0x004001e0` | LCD command/status/data routines |

NEM-4 `lcd.ldd` contains the same virtual LCD interface addresses already inferred
from bootstrap: `0x58121200/04/08`. `medint.pdd` contains candidate constants
`0x581201c0`, `0x58120a00`, `0x59e011c0`, `0x59e01a00`; the QD counterparts include
`0x59a011c0/0x59a01a00` instead. Numeric matches are leads for disassembly, not
complete register semantics. Do not transplant QD addresses into NEM-4.

MIDP UI, installer and recognizer files are present and byte-verified in each core
ROM. The complete Java engine/dependency path has not yet been identified or run.

Header pointers at `0xa0/0xa4/0xd0` decode to ROM **directory entries**, not directly
to executable headers. In these images they name `ekern.exe`, `EFile.exe`, and
`rtc.dll` respectively. Follow each entry's payload pointer before decoding a
module; do not interpret `0xd0` as a ready-to-use BSP code address merely from
an assumed field name.

All three BOOT files are 8-KiB runtime snapshots. Their first 64 bytes occur in
kernel code in the corresponding ROM; the complete 8-KiB snapshots are not exact
ROM slices. This does not make them cold-reset bootloaders.

## Developer analysis databases

The developer tree has 18 `IDA1` database files: ApEngine, ApGrfx, BitGdi, C32,
EFSrv, EStor, ETel, EUser, Econs, EikCoctl, EikCore, EikSrvc, FbsCli, FntStr,
Palette, Rfs, Ws32, and scdv. These are the only non-ROM files in that tree.
Visible strings include analyst paths under EKA2L1 and function/import labels.
They may save later symbol/OS-interface work, but are not official vendor symbols;
no IDA project or embedded script was executed and no full symbol extraction was
performed. There is no corresponding `ekern.idb` in this set.

## Other local archives

Archive directories were inspected without extracting game payloads:
`Nokia N-Gage.zip` contains the original nested retail/developer archives;
`ROMS.zip` contains 127 game ZIPs; `nokia2games.zip` contains the SIS game pack
(1,406 archive entries). These are not additional identified raw flash images.
`Ultimate_SIS_Pack/` is unpacked application/game content, not another OS tree.

## Follow-up after the inventory

The subsequent [extension reconstruction](extension-reconstruction.md) uses the
recovered NEM-4 ROOT unchanged and verifies all 1,524 merged files. Missing
directories/header fields are synthetic and marked in its manifest. That opt-in
run has passed the old flash stop and enabled the MMU/caches; do not repeat the
payload search or describe the reconstruction as still unimplemented.

Still useful:

1. Authenticate the original extension metadata and physical bank placement if
   independent raw-image or hardware evidence becomes available.
2. Use named NEM-4 `lcd.ldd` and `medint.pdd` as hardware-reference targets.
3. Keep QD developer firmware as a separate, self-contained reference/control;
   an executable profile needs its own inspected offsets and image hash.
4. Revisit the 18 IDA databases when named OS interfaces become a bottleneck.
   They are analyst artifacts, not additional raw flash contents.

## ADSP firmware package located (2026-11-12)

The original NEM-4 Phoenix product configuration explicitly names
`AdspFile=e403a400h450.usb` at line10 of
`firmware/MCU/extracted/products/NEM-4/NEM_4.ini`.
The corresponding `E403A400H450.USB` file is present in that directory and has
an identical copy under `firmware/Disk1/data2/products/NEM-4/`.
Size1506378 bytes; SHA256
`0be93de04ebccd676d34ceaa2b9f4a901b3d0941565bc7b0f795e78ba8866429`.
It begins08A5, followed by mostly binary payload; its container/encoding and
mapping to the2MiB D551 flash are not decoded or qualified yet.

This is positive package evidence that we already possess the external ADSP
firmware update file. Earlier statements implying no ADSP firmware was supplied
were premature. Do not confuse this file with ARM-side adspserver.exe/adsp.dll,
the internal UPP DSP upload, or an already decoded raw D551 chip dump. Next:
identify the update format, decode its records and recover reset/MADI/self-test
behavior before looking externally for a replacement ROM. Source file untouched.
