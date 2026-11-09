# Current NOS default

Hardware isolation found the fake bootstrap prevents the logo. Normal
NOS_Compatibility.ngo and boot2.rom now exactly match the tested driver-only
file: original NOS startup retained, replacement driver plus checksum skip.
Use the same existing RBF and NOS toggle. The old full replacement is preserved
only as TEST_NOS_Full_Experimental.ngo for investigation. No C:/UI patches.

## MiSTer runtime overlays

This is the permanent local folder for generated, ready-to-copy overlays.
Source code is maintained under `firmware_overlays/`; build intermediates live
under `build/firmware-overlays/`. Scratch contains experiments and old evidence.

| File | Purpose |
|---|---|
| `boot2.rom` | Automatic NOS Compatibility load |
| `NOS_Compatibility.ngo` | Identical NOS file for the manual Firmware picker |
| `boot3.rom` | Automatic Bluetooth Compatibility load |
| `Bluetooth_Compatibility.ngo` | Identical Bluetooth file for the manual picker |
| `SHA256SUMS` | Checksums of prepared local files |

Copy boot2.rom/boot3.rom beside the original boot.rom/boot1.rom in
`games/NGage` on MiSTer. Enable the relevant Firmware menu options and save
MiSTer configuration. Original boot files and C:/PMM stay separate.

Generated files include words derived from private firmware and stay ignored by
Git. This README and the builders are maintained. Build instructions and current
verification limits: [firmware overlays](../../docs/firmware-overlays.md).

## Temporary checksum isolation test

TEST_Checksum_Only.ngo changes only the two primary checksum descriptor words.
It contains no NOS bootstrap/driver changes. Build with
`python3 tools/checksum_only_overlay.py`. On the existing RBF: Bluetooth Off,
NOS Off, Load NOS Compatibility → TEST_Checksum_Only.ngo, then NOS On. The
NOS selector is reused only to apply this diagnostic file. Logo present points
to NOS changes; no logo implicates the checksum-skip path or its interactions.
Restore the full NOS package manually or cold-reload normal boot2 after testing.
The normal boot2.rom has not been replaced by this test file.

## NOS component isolation

Hardware reached the logo quickly with TEST_Checksum_Only.ngo. The remaining
failure is in NOS replacement code/initialization, not the primary skip alone.

- TEST_NOS_Driver_Only.ngo retains original NOS startup/bootstrap but installs
  the replacement driver/export/allocation words. Test this first.
- TEST_NOS_Bootstrap_Only.ngo replaces startup/service-table initialization but
  retains original driver exports.

Both include the tested checksum skip, use the existing NOS picker/toggle and
need no new RBF. For each: NOS Off, load the desired test file, NOS On. Keep
Bluetooth Off if present. These are diagnostic subsets, not complete backends.
Build with `tools/checksum_only_overlay.py --variant driver-only` or
`--variant bootstrap-only`. Their union is the full NOS pack; only descriptors
overlap. Original boot2 and firmware files remain unchanged.

Hardware result: TEST_NOS_Driver_Only.ngo also reaches Nokia. Original startup
plus replacement driver works to that point; full NOS overlay does not. Next
is the already-prepared bootstrap-only variant to distinguish bootstrap alone
from its interaction with the replacement driver. No claim of full UI yet.
