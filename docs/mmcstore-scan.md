# mmcstore startup scan, 2026-11-10

Hardware must reach UI within 20 seconds; an observed hour without UI is an
unresolved failure. These replay results establish local progress, not full boot.

| Measurement | Original, 4B + 5M clocks | Reduced, 2B + 20M clocks |
| --- | ---: | ---: |
| Unique scan entries | 20 | 1050 |
| Repeated entries | 0 | 0 |
| Block exits | 0 | 2 |
| Complete synchronous reads | 19 | 1050 |
| Median read clocks | 174936 | 16165 |
| IRQ/NOS share of complete-read time | 71.34% | 0.45% |
| C backing bus share of complete-read time | 0.033% | 0.494% |

The reduced trace exits block34 at 2,003,325,299; enters block33 at
2,003,341,311; exits block33 at 2,012,582,179; enters block32 at
2,012,598,008. Each full block has up to486 metadata records, offset0x30
through bound0x3558 in increments28. Uniqueness keys include block number,
not just a reusable node address. A complete observed block takes9,240,868
clocks. No evidence here of a permanently stuck individual read or block scan.
A later repeated complete scan or a later startup wait remains possible.

StartupThread80409884 is waiting in RFile::Open for the firmware literal
c:\system\mmcstore (F32 function27); FileServer Main services ELocal /
RBusLocalDrive reads. Snapshots contain EKern and EFile, no UI process yet.
The original final C read position is0x00302a14 (block48); reduced2B is already
at block34. Original3B and4B were at blocks59 and51. This is progress, not UI.

Attribution uses IRQ mode and last writeback PC code regions; it is not a
perfect call-stack profile. Stall categories are exclusive; do not sum them
with overlapping PC-region attribution. Raw C timing is a simulation backing
model, not a physical DDR latency measurement. ROM buffering, direct SDRAM and
clock changes differ between builds, so the speedup cannot be assigned to NOS.

NOS counter frequency remains a hypothesis. Changing it to64Hz changes firmware
deadline units and the ADSP staged tick, not merely interrupt frequency. The
separately supported26MHz general timer /64Hz OS tick does not prove that the
NOS comparator should also be64Hz. See phone-clocks.md.

Evidence kept locally: scratch/metadata-scan-audit/original.log,
reduced-final.log, original-final.json and restore-check.log. Sources original.cpp
and reduced.cpp instrument frozen models without firmware/C edits. The invalid
overlapping replay log is excluded. Original final checkpoint at4,433,931,411
restores byte-identically with its exact binary; only reduced long run continues.

Next: observe the whole open return/restart and process creation, establish NOS
counter units, and compare a fresh hardware PC/fault capture. Screenshot API
was unreachable during this audit. Do not treat waiting to12B as a solution to
the hardware20-second requirement.
