# Permanent four-group installer library — 2026-11-16

The latest user request supersedes the large all-in-one card. The original
collection has been reorganized in place at:
`/Users/andreabogazzi/develop/nokia roms/Ultimate_SIS_Pack/`.
It now contains `Group_1` through `Group_4`, `Extras`, `README.txt` and
`groups-manifest.json`. All383 original installer instances, including the two
archived installers, were compared byte for byte before the replaced old layout
was removed. Title families remain together; original names/subfolders remain
inside each group (colliding paths receive the original unique card alias).
Non-installer documents, pictures and resources remain in Extras. Six archives
without SIS payloads are preserved unchanged there; the two archives containing
SIS were replaced with verified extracted installers and their non-SIS contents.
No package was executed, installed or discarded as incompatible.

| Permanent folder | Installers | SIS size | Title range |
| --- | ---: | ---: | --- |
| Group 1 | 103 | 51.97 MiB | 10 Ball Micropool – Crystal Cave-in |
| Group 2 | 89 | 53.12 MiB | Daedalus 3D – Kwoki |
| Group 3 | 105 | 54.69 MiB | Legacy – Rainbow Jek |
| Group 4 | 86 | 52.78 MiB | Rally Pro Contest – The Match 2 |

Every group has enough margin for a64MB FAT16 card, including4KiB allocation
rounding and index/readme. These are installer groups, not preinstalled apps:
the existing SPMark-specific extractor is not a general SIS installer and does
not reproduce arbitrary conditional installation, registration or dependencies.

## Current128MB Group1 card

`build/mmc/sis-group-1-128mb-ro.mmc` contains103 original installers under short
root aliases, with INDEX.TXT mapping to permanent group paths. FAT16/4KiB,
CSD temporary write protection,75.3828125MiB free;134185472bytes including
footer. SHA256 `899ea722eeba5063796d25ed524bb78bbcc0832ba0d119928d91bc55661dabc9`.
Full file readback and independent105-file FAT/identity/extent audits pass with
zero errors/warnings. `--size-mb128` is now accepted by the library builder.
Inputs/manifest: `runtime/mmc/sis-group-1/` and `runtime/mmc/sis-group-1.json`;
permanent collection manifest maps each source path and hash. Existing offline
Docker/mtools build command is recorded in scratch/sis-four-groups-20261116.

User authorized reboot after the SPMark run. Save queue0/quiescent was verified
before unloading to Menu. The old SD installer controls were then deleted with
all old image handles closed. The new128MB card was delivered to `/media/fat/games/NGage/sis-group-1-128mb-ro.mmc`,
fsynced and independently re-read in full: exact matching SHA256. Its original-
firmware cold boot reaches App Manager with Group1 installer aliases visible.
The120s/480-snapshot capture has no kernel panic/save errors and ends with
save queue0. Card left mounted, CPU running, save On. Agent sent no phone/Menu,
date or installer-confirmation input; the user may have navigated during capture.
This verifies native reading/discovery, not installation of all103 packages. The obsolete local
1GB/512MB/256MB/64MB installer/control images and their register sidecars were
deleted, plus their redundant staging copies. Logs, audit reports, hashes and source manifests remain for evidence. A later
explicit user request cleaned all obsolete generated files in build/mmc,
including16MB image outputs. That folder now contains only the new128MB MMC and
its manifest. Reports moved to scratch/sis-four-groups-20261116/retired-reports/;
other-chat source inputs, tools, simulations and checkpoints remain untouched.

The following is historical evidence for the deleted all-in-one images.

---

# Ultimate SIS installer library

Built from the supplied `Ultimate_SIS_Pack` on 2026-11-16, without executing
packages or changing the phone. Final requested capacity is **1 GB**, replacing
the earlier 256 GB / 512 MB proposals.

The delivered image is `build/mmc/ultimate-sis-1gb.mmc`: 383 original SIS files,
381 loose and two inside archives, plus README.TXT and INDEX.TXT. All eight
archives were inspected, including RAR data stored under a .zip filename.
Non-SIS extracted applications/assets, EXEs, previews and packaging files are
not automatically installed or included. Packages for different OS/phone
versions are retained; inclusion is not a compatibility guarantee.

All installers are at E:\ with unique uppercase 8.3 aliases. This uses 385 of
the original 512 root directory entries and follows the already-proven native
Tools → Manager installer-card layout. INDEX.TXT maps each alias to its original
game/package path. It avoids a dependency on an installed file browser and
mtools-sensitive release-directory names. Original installer bytes are unchanged.
Native discovery of this particular large card is still untested.

The image has a normal MBR at LBA32, FAT16, two mirrored FATs and 16 KiB clusters.
Its byte-addressed MMC identity advertises 1,073,479,680 payload bytes; the
required footer makes the file 1,073,480,192 bytes. This is the donor geometry's
1 GiB-class capacity, slightly below exactly 1 GiB. Free space is 845,217,792
bytes (**806.06 MiB**). The raw .img duplicate was removed to save local space.

The installed b707ebd core still forces MMC read-only. The image itself has a
write-capable CSD, ready for the new write interface. Writable MMC allows an
installer to use E: when its package permits it; packages requiring C: still
need the original internal storage. C: remains the phone's 4 MiB flash. Resizing
boot0.vhd to 256 MB would fail the core's exact geometry checks and would not
enlarge the firmware's internal filesystem.

## Verification and rebuilding

Every filename and source byte was read back through the donor FAT reader.
Independent allocation audit passes all385 files, mirror equality, chain bounds,
cross-links and orphan checks with zero errors/warnings. The production image
inspector verifies CID/CSD CRCs, full extent, capacity and footer. All381 loose
sources and all8 source archives were rehashed unchanged. These are offline
checks; hardware mount/installation and writable persistence need a new core.
[Image evidence](evidence/ultimate-sis-library-20261116.json).

The private staged installers and source inventory are under
`runtime/mmc/ultimate-sis-1gb/` and `runtime/mmc/ultimate-sis-1gb.json`.
The builder is `tools/mmc-card/build-sis-library.py`, using the existing pinned
`mkcard.py` without modifying it. Stage once with the supplied source directory;
then use `--build-only` in the existing offline simulator/mtools container.
It verifies staged SIS hashes, refuses an existing .mmc output and leaves the
phone and original collection untouched. Keep installed/modified card images
separate from rebuild outputs; rebuilding an installer library would discard
any later installations stored on that image.

## SD-card delivery — 2026-11-16

The user's Finder/Samba copy left only an AppleDouble metadata sidecar; the
actual image was absent. Root cause is unconfirmed: plenty of space and no
current I/O error were observed, although the SD boot log records an earlier
unclean unmount. No online filesystem repair was attempted.

The original card was subsequently delivered directly over SSH to
`/media/fat/games/NGage/ultimate-sis-1gb.mmc`. Full SD-card readback SHA256 equals
the verified local image, and size/MBR/footer also match through the user's
`/Volumes/sdcard/games/NGage/` Samba mount. No core input, card mount, C:/PMM
change or reboot was performed. This verifies file delivery, not native1GB
card discovery or phone-side installations.
