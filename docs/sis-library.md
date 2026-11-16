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
