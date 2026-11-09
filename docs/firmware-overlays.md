# Optional firmware overlays

Firmware → **NOS Compatibility: Off/On** selects the first supported overlay.
Default is Off. Turning it On applies the GPL NOS bootstrap/driver adapted from
Nortido, and **skips the primary firmware checksum**. Turning it Off restores
all original words, including the checksum descriptor. Original MCU/PPM files
on disk, C: and PMM are unchanged. This changes the executed guest view; it is
an optional compatibility mode, not a verified model of the baseband hardware.

The NOS replacement supports narrow accessory/light/vibration messages. It does
not provide a cellular modem, SIM service, calls or SMS. Bluetooth and audio
substitutes are not yet exposed. Next priorities are a separate Bluetooth
responder and an investigated SIM compatibility backend. C: drive bypasses,
formatting changes and UI/startup patches are explicitly excluded. Provenance: [NOS notice](../firmware_overlays/nos/NOTICE.md).

## Files and menu

The recognizable package name is **`NOS_Compatibility.ngo`**, matching the menu.
Stock MiSTer Main requires an additional identical **`boot2.rom`** copy for
automatic loading. Place boot2.rom beside the existing boot.rom and boot1.rom
in games/NGage. Keep NOS_Compatibility.ngo for the manual **Load NOS
Compatibility** picker on the Firmware page. Existing official boot files do
not move or change. The package is specific to NEM-4 v4.03 service files.

Main can send boot2 before boot.rom. The loader stages the package in 8KiB BRAM
and waits for both official firmware slots to validate. The CPU is held while
validating or applying the selected view, then restarts through the normal reset
path. Warm resets preserve the undo table. Toggle Off before loading a replacement
package; the manual picker is disabled while the overlay is applied or busy.
Persist the menu selection with MiSTer's normal configuration saving if desired.

On with a missing/invalid package holds the CPU. Off permits original firmware
boot after ordinary package errors; an unexpected target word requires an
original firmware reload rather than releasing a partially altered guest view.
No hardware build, timing fit or installed-Main end-to-end check is implied by
simulation results.

## Build a private package

Host prerequisites: Python3 and arm-none-eabi GCC/binutils. From the repo root:

```sh
python3 tools/nos_overlay.py \
  --mcu 'firmware/NEM-04 v.04.03 N-GAGE/nem440.3c1' \
  --ppm 'firmware/NEM-04 v.04.03 N-GAGE/nem440.326' \
  --output scratch/mister-overlays/NOS_Compatibility.ngo
cp scratch/mister-overlays/NOS_Compatibility.ngo scratch/mister-overlays/boot2.rom
```

The builder verifies the original service profiles and decoded stock MD5 before
creating the pack. It does not replace the expected digest. It sets descriptor
words at raw offsets 8F18 and 8F1C to FFFFFFFF, selecting the original verifier's
absent-descriptor return, as Nortido does. Secondary verification remains intact.
Every replacement has an undo word. The generated pack includes words derived
from the user's firmware; keep it private and out of Git.

## Transport contract and checks

NGO1 v1, overlay ID1, 64-byte header followed by up to640 twelve-byte records:
raw DDR firmware offset, original LE32 word, replacement LE32 word. The header
contains both service CRC identities, original primary MD5 identity, record
count/size, total length, body CRC32 and header CRC32. CRC validation remains
active even when the guest firmware checksum is skipped.

Before writing, the HDL validates the entire package, ordered aligned firmware
addresses below13F0000 and every target word. No record can address C:/PMM.
A complete preflight precedes the write pass. Firmware reloads trigger
reconciliation of original/already-patched words before reapplication. ROM
writes use the normal adapter invalidation path; CPU reset clears its caches.
Diagnostic boot flags: bit17 requested,18 applied,19 loaded,20 busy,24:21 error.
Errors:1 format/profile/length,2 CRC,3 target bounds/order,4 unexpected target
word,9 attempted package replacement while active. The existing loader-failure
flag also covers overlay errors.

Directed checks:

```sh
# Inside the existing jotego/simulator:arm64 image:
sh tests/phone/overlay/run.sh scratch/mister-overlays/NOS_Compatibility.ngo
sh tests/phone/mister_transport/lint-top.sh
sh tests/phone/overlay/hps-run.sh scratch/mister-overlays/NOS_Compatibility.ngo \
  scratch/hardware-live/service-loaded-boot/core.bin \
  scratch/hardware-live/service-loaded-boot/extension.bin
# On the host:
cc -std=c11 -Wall -Wextra -Werror tests/phone/overlay/nos_guest_test.c \
  -o build/sim/unit-overlay/nos-guest-test
build/sim/unit-overlay/nos-guest-test
```

An independent full-core run uses `run-logo.py --nos-overlay <package>` alongside
explicit core/extension/C: inputs and clock options. It transfers the package
through the actual overlay engine and DDR adapter before CPU release; it does
not prepatch source images. Its manifest includes package SHA and rejects stock/
overlay checkpoint mixing. See [status](status.md) for the observed stopping point.
