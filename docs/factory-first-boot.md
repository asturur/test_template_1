# First boot from a blank C:

A blank `boot0.vhd` boots when the PMM image carries the record that makes
the stock firmware format C: by itself: AUX startup reason (PMM group 212,
record 3) = 105. `tools/ngage_factory_images.py` writes both images. No RTL
and no firmware byte changes.

```sh
python3 tools/ngage_factory_images.py --cdrive boot0.vhd --pmm boot1.vhd
```

Observed on one DE10-Nano with the CI RBFs of `8546db1`, `dfe4bc1` and
`70b8ef3` (runs 44419903846, 44535096106 and 44555714064), the unchanged
4.03 service files and those two images: Nokia logo, the first-start
Time dialog about 75 s after the core load, the idle screen after two
confirmations, Menu, and a complete SPMark04 run from a cold-mounted card
(Menu key, down, down, right, right, OK; then Options, Run Set, Custom).

## What happens without the record

With an erased C: and an erased PMM the phone shows the Nokia logo and the
kernel parks at `50324294` a few seconds later: 8.1 to 8.4 s after the CPU
starts on the board, 6.34 s (cycle 494,727,802) in the whole-board simulation
at the production settings. The panic record is `503AD63C / E59FF044 /
10000000`, the stop [symbian-startup.md](symbian-startup.md) recorded on
2026-11-11. The simulation, with an observer on that abort, gives the chain:

1. **EStart** cannot mount LFFS on an erased C:. It then sends HelperDrv
   request 1 (`503EEC8E`), prints `auxstart %d` (`503EECB6`) and formats C:
   only when the answer is 105 (`503EECBE`, format loop at `503EE990`).
   Otherwise it removes the file system, frees the media driver and mounts
   the RAM drive in C:'s place (`503EECCA`-`503EED66`). The query is not made
   when C: mounts.
2. **helper.ldd** request 1 (`503841F8`) answers 100 by itself while variant
   flag bit 0 is clear and otherwise asks NOS service 3, request 12
   (`5038426C`). NOS sets the flags to 1 at cycle 276.9M and to 3 at 301.5M
   (setter `50349D8C`, called from `514A4AD4`), so the question reaches NOS.
3. **NOS** (the descrambled CS0 window runs at `51400000` + its CS0 offset)
   passes request 12 (`514A4844`) to its EKIF task as
   `EKIF_READ_AUX_STARTUP_REASON`. The handler at `516689D4` reads two bytes
   of PMM group 212, record 3. When the read returns 17 it traces
   `EKIF: AUX startup reason not found from PMM` and answers 100
   (`516689FC`). The routine before it (`51668980`) writes the same record.
4. With 100, C: is a RAM drive and **Starter** runs its short start-up list.
   At the end of it (state machine `5096C970`, state 2) it builds an object
   whose `ConstructL` (`5096DBC4`) calls `CBaBackupSessionWrapper::NewL`.
   Nothing on that list has started the Eikon server, so the connect to
   `BackupServer` returns `KErrNotFound` and `NewL` leaves. The clean-up runs
   the object's destructor (`5096DB80`), which calls
   `CBaBackupSessionWrapper::DeregisterFile` on its still-null member. That
   reads the word at address 8 (`E59FF028`, an exception vector), adds `1C`
   and calls `RArrayBase::Count` (`503AD63C`): a data abort in user mode
   (CPSR `80000010`) in a system-critical thread, hence the kernel fault.

The abort is the same with and without an MMC card, and on a fit with a
faster SDRAM path (pull request 3's, there about two seconds sooner). C: is
still entirely `0xFF` at the stop: nothing was formatted.

## What the record does

With group 212, record 3 = 105 in the PMM the kernel text reads
`auxstart 105`. EStart erases and formats C:; read back from DDR at 45 s it
is an LFFS volume (`603B3B50` at offset 4, all 64 blocks in use, 411,823
non-erased bytes). The firmware then replaces the record itself: the tag of
the old one goes from `F4` to `A4` and a new record with 100 follows, so the
next boot does not format again. A phone presumably leaves the factory in
this state; what a factory PMM holds besides is not known here.

A PMM record is `F4`, group, record number (16 bits), `55 FF FF FF`, length,
offset of the next record, payload; the chain starts at offset 32 of a
catalogue sector. The image the tool writes is 65,536 bytes of `0xFF` with
the four 32-byte sector headers the firmware writes when it formats an erased
PMM (taken from such a PMM, read back from DDR) and that one record at
offset 32: 67 non-erased bytes. After a first boot from it the first
catalogue sector holds 78 records, the firmware's own, with reason 100.

`python3 tools/ngage_factory_images.py --inspect boot1.vhd` reports the
reason a PMM image holds.

## Board runs

All from an erased C:, the card in slot 2 at load, Background save Off, the
images in the MiSTer's RAM disk:

"The tool's image" is its output, byte for byte. "Record added" is a PMM the
firmware had formatted in an earlier boot (read back from DDR, 54 records)
with the one record appended, the form in which the record was first tried.

| Build | PMM | Result |
| --- | --- | --- |
| `8546db1` CI RBF | erased | logo, kernel fault at 8.1-8.4 s |
| `8546db1` CI RBF | the tool's image | Time dialog, idle (first run); Time dialog at 75 s, idle, SPMark04 complete (second run) |
| `8546db1` CI RBF | record added | Time dialog at 75 s, idle, SPMark04 complete |
| `dfe4bc1` CI RBF | the tool's image | Time dialog, idle, SPMark04 complete |
| `70b8ef3` CI RBF (debugger on, seed 42) | the tool's image | Time dialog, idle, SPMark04 complete |
| the two fits of pull request 3 (seed 43) | record added | Time dialog at 68 s, idle, SPMark04 complete |
| `8546db1`, debugger on, seed 43 (setup -0.76 ns), two fits | record added | one to the Time dialog and SPMark04; the other a kernel fault at about 42 s |

SPMark04, Run Set, Custom, all nine tests, one pass each, from the
`Result.txt` the phone saves on the card:

| Test | `8546db1` | `8546db1` again | `dfe4bc1` | `70b8ef3` |
| --- | ---: | ---: | ---: | ---: |
| 3D Game, fps | 5.79 | 5.79 | 6.59 | 6.59 |
| 3D FillRate, Mtexels/s | 1.13 | 1.13 | 1.26 | 1.27 |
| 3D PolyCount, Ktriangles/s | 18.96 | 19.06 | 21.25 | 21.25 |
| 2D Image, fps | 27.86 | 27.68 | 30.65 | 30.76 |
| Image Scaling, bitmaps/s | 1.29 | 1.29 | 1.33 | 1.33 |
| JPEG Encoding, Kpixels/s | 122.19 | 121.85 | 123.34 | 123.07 |
| Contacts, contacts/s | 2.48 | 2.49 | 2.72 | 2.70 |
| Calendar, events/s | 5.11 | 5.10 | 5.59 | 5.58 |
| Disk Access, files/s | 13.53 | 13.68 | 15.17 | 15.20 |

Each run is a first boot, so C: is freshly formatted and the storage tests
start from the same state. The nine tests take about 250 s on `8546db1` and
239 s on the two later commits. For scale, ngage2 on the same board gives
3D Game 6.65 fps at 78 MHz and 8.88 fps at 104 MHz (QD firmware 4.10).

The fault in the last row of the first table has the category `FILE: FI`
and reason `10001`: an NOS assertion (its text is
`FILE: %s LINE: %d EXP: %s`, `516C95DC`), after
`CSysApAppUi::ConstructL: Start listening`. It did not recur in the eight
other first boots. Both of those debugger fits miss 78 MHz timing; the file
and line of the assertion were not captured.

## Limits

- One board, nine first boots. SPMark04 is the only application run.
- Images left by an interrupted first boot are not a starting point: a boot
  from the C: and PMM of the faulted run stayed on the logo for 4.5 minutes
  without a fault. Start again from the factory pair.
- Background save was Off, so no run wrote the formatted C: back to its
  image. With it Off, the image files stay in factory state and every load
  of the core is a first boot.
- The sector headers are this firmware's own bytes for an erased PMM; other
  firmware versions were not tried.
