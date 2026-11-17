# FAT12 MMC card tools

Build a 16,32,64 or128 MB card from any folder, including an empty one.
The default remains16MB. Long filenames and
subdirectories are preserved. Every file is read back and compared with its
source. The builder writes a raw `.img`, register sidecars, a MiSTer `.mmc` with
its required NGAGEMMC footer, and a JSON manifest.

## Ready cards and adding files

- Durable local inputs: `runtime/mmc/` (private payloads are ignored by Git).
- Generated cards and reports: `build/mmc/`.
- `spmark-ready.mmc`: extracted app in System/Apps/SPMark and System/help.
- `spmark-installer.mmc`: unchanged original installer at E:\SPMARK.SIS.
- `blank-fat12.mmc`: card built from `runtime/mmc/empty-files/`.

Put files in `runtime/mmc/files/` to add them to the installer card, or in
`runtime/mmc/empty-files/` for the blank/custom card. With Docker running,
double-click `tools/mmc-card/rebuild.command`, or run it from any directory.
It rebuilds all three cards under `build/mmc/`. Mount the `.mmc` in the current
core's **Mount MMC card** entry. Mount before a fresh phone boot for app discovery.

To build only one source folder under `runtime/mmc/`:

```sh
tools/mmc-card/rebuild.command empty-files my-card
```

With native Python 3.9+ and mtools, from the repository root:

```sh
python3 tools/mmc-card/build-card.py runtime/mmc/empty-files build/mmc/my-card
```

For128MB, add`--size 128` before the source folder. These cards use FAT16;
the16MB default uses FAT12. Both have writable-capable CSD metadata.

The Docker shortcut uses the existing `jotego/simulator:arm64` image and mtools
under `build/tools/mtools/`; rebuilding needs no network. If that disposable
cache has been removed, run `tools/mmc-card/setup.command` to download it again.

## SIS extraction and inspection

`extract-spmark.py` supports this package's single-language old SIS with ordinary
files and text notices. It rejects conditional/special installer records and
destinations outside the selected card drive. Messages are saved as data outside
the card. It is not a general SIS installer or dependency resolver.

```sh
python3 tools/mmc-card/extract-spmark.py /absolute/path/to/SPMark.sis
python3 tools/mmc-card/audit-fat.py build/mmc/spmark-ready.mmc
python3 tools/ngage_mmc_image.py inspect build/mmc/spmark-ready.mmc
```

Extraction defaults to `runtime/mmc/`; an optional second argument selects
another output folder. It writes `extraction.json` with source/payload hashes.
The frozen `mkcard.py` comes from the adjacent ngage2 checkout; its provenance
is recorded in `builder-provenance.json`. The independent FAT allocation auditor
checks chains, mirror agreement, bounds, cross-links and orphan allocation;
it uses short aliases rather than validating long-name entries.

The permanent synthetic integration check lives in `tests/tools/mmc_folder/`.
It exercises a long filename, a nested directory and a file spanning clusters,
using generated temporary inputs under `build/`, never `scratch/`.

## Phone limits

Current production HDL implements MMC write transport and respects mounted
read-only flags and CSD protection. Phone-side writes remain under investigation;
offline verification does not establish native persistence. Normal installation from the SIS card has not
been tested; select internal C: if offered. Extraction alone does not create
App Manager installation/uninstallation records. These newly generated images
have passed local checks but have not been booted on hardware.

All cards use 32760 payload sectors, an MBR partition at LBA32, FAT12, 4 KiB
clusters, two mirrored FATs and synthetic folder-card identities. The original
ready/installer/blank cards have 15032/15644/16304 KiB free respectively.
