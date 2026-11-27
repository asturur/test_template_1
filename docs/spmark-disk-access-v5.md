# SPMark04 Disk Access and v5 storage

The runtime A/B uses ngage-v5 commit `dfe4bc1` with the 32 KiB D2 flash
cache, the existing ordered D3 persistence path and a 78 MHz system clock.
The 104 MHz fitting objective remains a separate check. The experiments
are archived under `build/sim/disk-access/`. The v5 production RTL now
uses update-on-hit and reproduced all six cases. [Production verification](ddr-flash-cache.md#2026-11-19--v5-updates-resident-data-on-committed-writes).

## What the app times

The original SPMark.app creates a fresh RFs connection with four message
slots through EFSRV ordinal 18 at `0x10004788`. It constructs
`TestFile0.dat` through `TestFile24.dat` using the literals at file
offsets `0xf888` and `0xf89c`. The preflight opens and removes existing
test files. The measured loop repeats four times from `0x100048dc`. It
creates 25 files, writes and flushes each file, closes them, opens and
reads them, and closes and deletes them. The file mode is `0x200`.
The write descriptor at file offset `0xf6c4` contains 446 bytes, and the
read buffer has 512 bytes of capacity. Each round carries 11,150 payload
bytes in each direction. The app uses the same relative names regardless
of where its executable resides.

| File API in the measured loop | EFSRV ordinal | Original NEM-4 export |
| --- | ---: | ---: |
| RFile::Create | 25 | `0x503df105` |
| RFile::Write | 194 | `0x503df309` |
| RFile::Flush | 50 | `0x503df58d` |
| RFile::Close | 15 | `0x503de0ad` |
| RFile::Open | 121 | `0x503df0ed` |
| RFile::Read | 136 | `0x503df151` |
| RFs::Delete | 29 | `0x503de8e1` |

The original EFile/EFSRV ran these calls in order in a private NGVM copy
of an archived NEM-4 C: image. Each round reopened the relative test file
as the absolute `C:\TestFile0.dat`. All 100 readbacks matched the original
446 bytes, and the deletion check passed after each round. The timed media
trace captured 12,539 reads (1,307,903 bytes) and 6,764 writes (159,840 bytes)
to unit 0, C:. It recorded zero erases for this image and job. Original
EFile ran with NGVM's instruction-paced kernel and media, so its virtual
time serves as file-path evidence. The RTL comparison below uses a smaller
authored flash-operation proxy. The archived image's SHA-256 matched
before and after the guest run.

C: is the LFFS volume in the 4 MiB raw `boot0.vhd` (HPS slot 0).
PMM is independent 64 KiB raw NEM-4 backing in `boot1.vhd` (slot 1).
E: uses the MMC card and slot 2, including CMD18 4 KiB prefetch. The
`.vhd` names for C:/PMM identify raw byte arrays. Contacts is a separate
CNTMODEL workload. The available replay exercises EFile and the Disk
Access operations, so Contacts remains unmeasured in this scorecard.

## Runtime C: NOR and backing-file intervals

The RTL proxy creates 25 synthetic directory records and writes 446 bytes
per record through the real C: NOR program commands. It reopens and verifies
data, deletes by programming the metadata, then waits separately for the
final HPS write acknowledgment. It uses the original C: NOR, raw save
manager, D2/D3, DDR transport and actual three-slot `hps_io` with an
in-memory host peer. The proxy host reopens its own saved bytes after a
cold transport reset and checks all contents, including the final unwritten
two bytes in each readback word. Cold reopen here restores the small
fixture of 32 C: and two PMM sectors. Full-size restore is measured below.

Update-on-hit forwards the identical write-through DDR request. A matching
cache line changes only after DDR completion, with the byte enables on the
selected half of the 64-bit beat. A write miss still goes to backing and
leaves the resident tag alone. Reset and D3 restore keep their existing
invalidate rules.

| Proxy interval at 78 MHz, eight added host clocks, autosave disabled | Invalidate on program | Update on hit |
| --- | ---: | ---: |
| 16 halfword programs plus readback in one line | 496 clocks, 17 DDR reads | 330 clocks, 1 DDR read |
| Create and write 25 records | 157,500 clocks, 5,625 DDR reads | 102,373 clocks, 375 DDR reads |
| Reopen and read | 17,498 clocks, 375 DDR reads | 14,125 clocks, 0 DDR reads |
| Delete | 439 clocks | 438 clocks |
| Combined guest proxy | 175,437 clocks, 11,115 files/s | 116,936 clocks, 16,676 files/s |
| Guest finished to final host ACK release | 37,712 clocks | 37,712 clocks |
| Cold restore and reopen | 67,076 clocks | 67,076 clocks |

The combined proxy uses 33.35% fewer clocks. Both policies send 5,625
physical creates/program writes, 25 delete writes and 27 snapshots, each
sent to the host in a 512-byte transaction. The create/write phase issues
22,500 NOR commands in either policy. Its pending-state time falls from
146,251 to 91,124 clocks. D2 program invalidations fall from 5,625 to zero
and the create/write refills fall from 5,625 to 375. This gain belongs to
the flash access interval.

| Added clocks per HPS request | Final ACK, either policy | Cold reopen, either policy |
| --- | ---: | ---: |
| 8 | 37,712 | 67,076 |
| 256 | 44,421 | 75,522 |
| 4,096 | 148,088 | 206,068 |

Each final ACK interval contains the same 27 physical DDR snapshot reads
and 13,824 host payload bytes. At the longest delay, 110,592 clocks are
injected before host service. The observed write order begins with LBA 0,
continues through 2–17, returns to LBA 1, then writes 18–26. Grouping only
successive adjacent sectors with a maximum of eight per group could reduce
that one modeled pass to six requests and remove up to 86,016 startup
clocks. This is a bound from the observed order. The tested save path
retains individual sectors and the original re-dirty behavior.

With accelerated autosave triggers, the eight-clock run records 142
host writes for the control and 91 for update-on-hit through the final ACK.
The candidate changes when the scheduler snapshots the same guest work.
The default production quiet and maximum-age timers are 1 and 5 seconds.
The overlap run uses 1,024 and 8,192 clocks to create overlap in the short
test, so its request counts describe that stress condition. Both policies
pass the existing actual-HPS re-dirty during transfer, retained snapshot,
changed C:/PMM restore and firmware read-only checks. Both also pass the
32 KiB D2 byte-mask, tag alias, early-fill tail and reset contract.

## Erase handling

The optional C: erase overlay fetches a 32-byte inspect line, then submits
the same ordered stores for non-erased 32-bit words. It preserves the
dirty event count and the ordered address signature. Isolated erase of the
proxy's used block takes 113,675 clocks with the pushed path, 88,839 with
update-on-hit, and 48,850 with update-on-hit plus line inspection. The last
two legs have 1,675 physical DDR reads and 2,833 physical DDR writes.
Batching mainly removes scalar controller lookups and handoffs on the
same physical traffic. All three legs give the same two status polls and
2,833 dirty events. Tests cover the existing B0 drain behavior, array
reads outside the affected sector, warm-reset recovery and cancellation
of a deferred erase on cold reset. The original file-service fixture had
no observed erase, so the isolated improvement applies to an erase
interval when that work occurs.

The production CPU refill decoder admits ROM and RAM. Its flash line
selection excludes C:/PMM, even though D2 already fetches 32-byte backing
lines for scalar array reads. A separate CPU wide-read experiment needs
evidence of cacheable C: requests and the array/status ownership contract.

## Full C: and PMM restore

The donor comparison uses only its aligned 4 KiB host-read protocol
(`sd_blk_cnt=7`). The candidate buffers and validates a whole host packet,
then supplies eight sectors locally to the existing raw restore engine.
The baseline streams 512-byte packets to that engine. The modeled host
has the same two clocks per incoming halfword in both modes. The tested
candidate includes an extra one-clock-per-halfword local replay. Each
leg writes exactly 532,480 physical DDR beats and checks every byte of
both full images on initial restore and on remount after two actual
boundary-sector saves.

| Added clocks per HPS request | 512-byte restore | Buffered 4 KiB restore |
| --- | ---: | ---: |
| 8 | 7,596,163 clocks (97.39 ms) | 9,667,843 (123.95 ms) |
| 256 | 9,659,523 (123.84 ms) | 9,925,763 (127.25 ms) |
| 4,096 | 41,608,323 (533.44 ms) | 13,919,363 (178.45 ms) |

Host requests fall from 8,320 to 1,040, carrying the same 4,259,840 bytes.
The measured buffered design breaks even near 293 added clocks per
request. Truncated 512-byte and 4 KiB first packets and replacement during
an active 4 KiB packet leave DDR untouched and report error. A separate run
with actual `hps_io` verified count seven, independent slot routing, 2,048
ordered halfwords on each C:/PMM slot, and concurrent isolation from slot 2.
These are transport simulations. Physical MiSTer Main service time,
power-loss durability and FPGA fitting remain unmeasured.

## E: command profile

Separate card tests use the existing serial card/HPS fixture at 78 MHz
system and 39 MHz serial. These timings begin at command issue and verify
the payload/token or stop sequence, with synthetic host backing. CMD18
requests one required 4 KiB extent plus one lookahead. The fixture also
checks CRC rejection, write persistence after remount and footer isolation.

| Added HPS startup clocks | CMD17 one block | CMD18 eight blocks and stop | CMD24 one block | CMD25 two blocks and stop |
| --- | ---: | ---: | ---: | ---: |
| 13 | 9,406 | 67,270 | 9,544 | 19,088 |
| 256 | 9,650 | 67,510 | 9,786 | 19,572 |
| 4,096 | 13,490 | 71,350 | 13,626 | 27,252 |

## Reproduce

The original app and firmware are local inputs. Use a read-only archived
LFFS image with `guest.py`, which makes its own private copy.

```sh
python3 tests/phone/disk_access/guest.py --name efile-actual-native \
  --app "$SPMARK_APP" --rom "$NEM4_SYM_ROM" --reference "$NGVM" --cdrive "$ARCHIVED_C"
python3 tests/phone/disk_access/run.py --name nor-446-final --autosave
python3 tests/phone/disk_access/run.py --name nor-446-erase-final --policy update --erase-line --wait 8
python3 tests/phone/disk_access/run.py --name nor-host-order --policy update --wait 4096 --autosave
python3 tests/phone/disk_access/run.py --name nor-ordering --regression
python3 tests/phone/disk_access/cache_check.py --name d2-cache-contract
python3 tests/phone/disk_access/restore.py --name restore-512 --batch 0
python3 tests/phone/disk_access/restore.py --name restore-4k --batch 1
python3 tests/phone/disk_access/mmc.py --name mmc-39-final
python3 tests/phone/disk_access/mmc.py --name hps-restore-slot-4k --restore-protocol
python3 tests/phone/disk_access/scorecard.py --output docs/evidence/disk-access-v5-20261119.json
```

[Machine-readable scorecard](evidence/disk-access-v5-20261119.json).
