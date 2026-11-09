# Optional firmware overlays

Firmware has independent **NOS Compatibility: Off/On** and **Bluetooth
Compatibility: Off/On** selectors. Both default Off. No C: bypass, formatting,
UI or application startup patches are included. These are optional changes to
the executed guest view, not verified models of the phone's hardware.

| Component | Named manual package | Automatic alias | Manual index | Auto index |
|---|---|---|---|---|
| NOS Compatibility | `NOS_Compatibility.ngo` | `boot2.rom` | F3 |80|
| Bluetooth Compatibility | `Bluetooth_Compatibility.ngo` | `boot3.rom` | F4 |C0|

The automatic aliases are identical copies of their named packages, required
by stock MiSTer Main's numbered boot-file loading. Place them alongside the
existing boot.rom and boot1.rom in games/NGage. The named packages work with
**Load NOS Compatibility** and **Load Bluetooth Compatibility** on the Firmware
page. Existing official boot files do not move or change. Both packages target
only the audited NEM-4 v4.03 service files.

NOS supplies the minimal service-table bootstrap and narrow accessory/light/
vibration replies. It does not provide a cellular modem, SIM service, calls or
SMS. [NOS provenance](../firmware_overlays/nos/NOTICE.md).

Bluetooth redirects BTLDD's write/completion path to Nortido's local HCI
responder. It supports initialization, local settings and inquiry without real
peers; connections and remote names time out. It uses the original kernel ring
and completion routines. It does not require NOS to be enabled, and provides no
radio or actual Bluetooth link. [Bluetooth provenance](../firmware_overlays/bluetooth/NOTICE.md).

## Selection, checksum and loading

Either component ON skips the primary firmware checksum via its existing
absent-descriptor return. The original expected digest stays intact. Turning
one component OFF restores its own hook/payload bytes, while the checksum stays
skipped if the other component remains ON. Both OFF restore the original words
and primary checksum behavior. Secondary verification and the packages' own CRC
validation remain active. Original MCU/PPM files on disk and C:/PMM stay intact.

Main may transfer overlays before boot.rom. Each package stages in its own8KiB
explicit BRAM; application waits for both official service slots to validate.
The CPU remains held across validation, application, undo and checksum changes,
then restarts through the existing reset path. Warm phone resets preserve both
undo tables. Firmware reload triggers reconciliation before CPU release.

On with a missing/invalid package holds the CPU and does not enable the other
component. Off permits original boot after ordinary package errors; unexpected
target words require a firmware reload. Turn a component Off before replacing
its package; its manual picker is disabled while it is applied or either engine
is busy. Normal MiSTer configuration saving persists the selectors if desired.

No installed-Main end-to-end, FPGA timing/fit or UI boot result is implied by the
directed tests. Existing long simulations use their frozen builds; these source
changes do not alter those binaries, checkpoints or results. No fourth long run
is started for the Bluetooth addition.

## Build private packages

Host prerequisites: Python3 and arm-none-eabi GCC/binutils. From the repo root:

```sh
python3 tools/nos_overlay.py \
  --mcu 'firmware/NEM-04 v.04.03 N-GAGE/nem440.3c1' \
  --ppm 'firmware/NEM-04 v.04.03 N-GAGE/nem440.326' \
  --output scratch/mister-overlays/NOS_Compatibility.ngo
python3 tools/bluetooth_overlay.py \
  --mcu 'firmware/NEM-04 v.04.03 N-GAGE/nem440.3c1' \
  --ppm 'firmware/NEM-04 v.04.03 N-GAGE/nem440.326' \
  --output scratch/mister-overlays/Bluetooth_Compatibility.ngo
cp scratch/mister-overlays/NOS_Compatibility.ngo scratch/mister-overlays/boot2.rom
cp scratch/mister-overlays/Bluetooth_Compatibility.ngo scratch/mister-overlays/boot3.rom
```

Builders verify original service profiles and the decoded stock MD5 before
creating a pack. The only common records are descriptor words at8F18/8F1C,
changed to FFFFFFFF. NOS and BT payload ranges do not overlap. Bluetooth adds
only the three-word BTLDD write hook, allocation size and erased-tail payload;
Nortido's separate BTLDD delay-literal shortcuts are not included. Each changed
word has its original undo value. Generated packages contain words derived from
the user's firmware: keep them private and out of Git.

## Transport and diagnostics

NGO1 v1 uses a64-byte header followed by up to640 twelve-byte records: raw DDR
firmware offset, original LE32 and replacement LE32. NOS is component ID1;
Bluetooth is ID2. Each picker rejects the other's file. Header fields contain
both service CRC identities, original primary MD5, record count/size, total
length and body/header CRC32.

The entire package and all target words are checked before the first write.
Offsets must be ordered, aligned and below13F0000, excluding C:/PMM. ROM writes
use the existing adapter cache invalidation path; CPU reset clears CPU caches.
Checksum selection is latched for each pass and reconciled against current
selectors before CPU release, including changes during a pass.

Diagnostic boot flags retain NOS requested/applied/loaded/busy at17..20. BT uses
25..28 in the same order. Error code21..24 prioritizes NOS; bit29 indicates a BT
error. Existing loader-failure flag also includes either overlay error. Codes:
1 format/profile/component/length,2 CRC,3 bounds/order,4 unexpected target,
9 attempted active package replacement.

## Verification

Inside the existing jotego/simulator:arm64 image:

```sh
sh tests/phone/overlay/run.sh scratch/mister-overlays/NOS_Compatibility.ngo
OVERLAY_ID=2 sh tests/phone/overlay/run.sh scratch/mister-overlays/Bluetooth_Compatibility.ngo
sh tests/phone/overlay/hps-run.sh scratch/mister-overlays/NOS_Compatibility.ngo \
  scratch/hardware-live/service-loaded-boot/core.bin \
  scratch/hardware-live/service-loaded-boot/extension.bin \
  scratch/mister-overlays/Bluetooth_Compatibility.ngo
sh tests/phone/mister_transport/lint-top.sh
```

Host tests include `package_test.py <NOS-package> <BT-package>` for allowed patch
scope and shared descriptor agreement, and `bluetooth_guest_test.c` linked with
`firmware_overlays/bluetooth/bt_hci.c` for HCI behavior and output bounds. Both
host payload tests can run with address/undefined-behavior sanitizers.

The earlier independent NOS full-core runner uses `run-logo.py --nos-overlay
<package>` and lineage-checks its package SHA. It has no Bluetooth full-core
runner option. Directed HPS tests cover both loaders and all four combinations,
not firmware execution of the BTLDD hook. See [status](status.md) for evidence
and the pending guest startup/ABI/hardware checks.

## NOS bootstrap callback correction (2026-11-09)

The initial NOS port incorrectly installed an object binder at global800004AC.
Pinned Nortido installs a no-op there. The old callback writes80006F64 through
r0+4; an actual ZAP microtest with r0=0 reproduces a write to00000004. The
corrected callback preserves r0 and does not write memory. Both pinned reference
and corrected bootstrap pass the same CPU test, including service-table layout,
null/object callback arguments, clear helper and repeat initialization. This
confirms a porting defect, not that the real missing-logo cause is established.

This change is in the loaded guest payload, not synthesized RTL. Rebuild the
NOS package and update boot2.rom (and the named manual file if used). A new RBF
alone still loads the old file. Existing RBF loaders accept the corrected NGO1
ID1 package unchanged. Corrected pack447records/5428bytes, SHA256
992c8a0837dea0135943f28d4bc28332922a3ee14f463f85c3912197832d5c69.

After building a NOS pack, test its assembled bootstrap independently:

```sh
sh tests/phone/overlay_bootstrap/run.sh scratch/mister-overlays/nos-build/bootstrap.bin
```

This uses host ARM binutils and the existing Jotego Docker image to execute our
actual ZAP CPU. Do not use the local Python Unicorn emulator on this machine;
it crashed with SIGILL. No phone simulation, original firmware file or long-run
checkpoint is changed by the test. Hardware logo/startup remains to be retested.
