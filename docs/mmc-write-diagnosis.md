# MMC write diagnosis and persistence

## 18 November — v5 replay

V5 picked up master test commit `4f40489` as `50bf768`. The original
FileServer replay on a disposable image produced the same full-image SHA-256
as master. A fresh guest reopened and checked all 1,739 bytes. The read-only
write returned `-21` with zero backing writes. The independent checker
rejected both a changed file byte and a change in the adjacent sector.
The ARM fixture was built on the host and run with Linux Unicorn in the
existing simulator image. The reference kernel supplied the drive interface.

The separate CMD24 probe selected `NGAGE_ARM9V2` with the actual v5 CPU RTL
and simulation RAM primitives. It passed in 269,479 clocks with four backing
reads, one TX2 DMA write and 512 bytes checked through the backing peer and
through guest PIO readback. A corrupted last backing halfword failed the
oracle. This probe used synthetic MMC contents and the testbench's
halfword interface. The native MiSTer cold remount below used the master
RBF. V5 physical cold remount is pending.

Local results are under `build/sim/mmc-file-roundtrip-v5-offline/` and
`build/sim/mmc-write-arm9v2-offline/`. The latter keeps the probe runner
with v5 source selection, its selected-source hashes and the recorded results.

## 18 November — native file copy survives a cold remount on master

The installed 78 MHz RBF matches the archived `1928aee` fit from run
`44258633306`. MiSTer Main had the designated 128 MB image open read/write.
Its initial SHA-256 matched the local fixture. The original guest took one
FExplorer Copy/Paste from `E:\README.TXT` to `E:\WRITE_TEST\README.TXT`.
The destination initially held only `SEED.TXT`. FExplorer reported Paste
completion and listed the new 374-byte file.

An independent read of the Linux backing file found the complete new file
with the source SHA-256, matching FAT copies and all three allocated file
chains. Exactly LBAs 33, 161, 321 and 345 changed. The image's footer,
partition, neighboring sectors and original two files passed the checks.
A fresh Main process reopened the same image with the post-write hash.
After resuming CPU Run from the saved Hold setting, the freshly booted
guest opened the copied file and displayed its text. The final Linux file
hash matched the pre-remount capture. This run observed a working native
guest-to-Linux write and cold readback on the exact fitted revision.

The separate original FileServer replay creates and flushes a 1,739-byte
file under the reference kernel. The host syncs and closes the disposable
image. A new guest reads all bytes, and a read-only run rejects the write
with `-21` and issues no backing writes. All four file-data sectors and
the expected FAT and directory sectors changed. The checker rejects a
modified data byte and a change in an adjacent sector. The reference local
drive needs the FAT partition view starting at LBA 32. An early open before
EStart completed returned `-18`. Passing the MBR to the mounted FAT volume
after EStart returned `-20`.

The tested hardware write completed with the existing production transport.
No MMC RTL correction is required by this reproduction. Routed timing is
recorded in the original fit report, which missed the 78 MHz timing gate.
[Machine evidence](evidence/mmc-file-roundtrip-20261118.json) ·
[Reproducer](../tests/phone/mmc_file_roundtrip/README.md) ·
[Exact board fit](tlb-banked-third-fit.md).

## 17 November — original operator test card

The operator requested a fresh **128 MB writable card** for manual testing.
`build/mmc/write-test-128mb.mmc` is full-capacity FAT16 with two verified
files, matching FAT mirrors, no allocation errors, class4 writes enabled,
WRITE_BL_LEN9, valid register/footer CRCs and both protection bits clear.
Its target path is`/media/fat/games/NGage/write-test-128mb.mmc`.
The original audit left native write testing with the operator. Fixed
synthetic inputs are retained under
`tests/phone/mmc_write_diagnosis/card/`.
[Card manifest](evidence/mmc-write-test-card-20261117.json).

Read-only hardware inspection now identifies the installed RBF exactly as
5F`8e70b1eb`, SHA256`621ca811b2b701dbe5f23f0b71a110924a10b7f8674a8440a0d49c634a97255a`.
Its compiled HPS adapter hash matches the implemented writable transport.
The open card at inspection was`games/NGage/sega-rally.mmc`, opened O_RDWR;
its footer has class4,WRITE_BL_LEN9 and neither CSD protection bit set.
Therefore the historical protected installer card is **not the current mount**.
The operator clarified there is no current captured error and requested the
fresh card to reproduce the problem. No failing CMD24/25 has yet been observed.

## Earlier offline investigation

The operator-reported hardware write failure remains unresolved. **Do not
implement the MMC stream-tag area rewrite yet.** Existing evidence does not
identify the failing operation, active RBF, active image or first failing
boundary. No running phone, card, write-protection setting or release fit was
changed during this investigation.

The existing actual-HPS fixture verifies bytes, not merely an ACK. A new
bounded authored-ARM fixture additionally connects TX DMA to the real card and
owned backing adapter. Its result is recorded below and in the machine receipt.
Neither fixture executes the original EPBUS write operation or persists a real
Linux file; hardware success is not inferred from their simulation results.

## What the existing tests prove

| Fixture | Real implementation exercised | Independent oracle | Missing boundary |
| --- | --- | --- | --- |
| `mmc_host/data_tb.v` | Native host TX/RX/CRC/token/busy and continuation types | Authored serial peer checks emitted bytes/CRC and injected errors | Real card, backing adapter, Linux, original driver |
| `mmc_production/dma_tb.v` | UPP capture/local arbitration, DMA frontend/engine/router, host; CPU replaced by authored bus master | Serial peer checks exact bytes, including rounded tails; SRAM sentinels | Card cache/HPS, actual ARM driver, Linux persistence |
| `mmc_hps/tb.v` | Production backing adapter | Direct halfword/count/reset/ownership checks | Real serial host/card, actual hps_io, disk |
| `mmc_hps/actual_tb.sv` | Real card, card cache/RAM, adapter and three-slot `sys/hps_io.sv` | Every outgoing halfword checked, copied into independent `payload[]`, then card reset/remount and readback from that array; footer guards | CPU/host/TX DMA, Linux Main and real file I/O |
| `mmc_mister` | Authored ARM CPU, full board/card/adapter and memory/DMA composition | Full-sector and odd reads, sentinels, synthetic HPS peer | Write path: old test explicitly rejects HPS writes and expects WP |
| New `mmc_write_diagnosis` | Authored ARM CPU, current full board/host, TX2 DMA, card, adapter; synthetic HPS peer | Full outgoing sector, independent stored sector, adjacent/footer guards, PIO readback; deliberate persisted corruption rejection | Actual hps_io in this combined fixture, original firmware, Linux file persistence, physical timing |

Saved `build/sim/mmc-writes-final-20261116.log` records direct48cases/33,287
clocks, and actual HPS20reads/4writes/604,018clocks. In
`tests/phone/mmc_hps/actual_tb.sv:574`, command0x18 reads256 halfwords through
actual hps_io; each is checked against an independent expected pattern before
being stored in `payload[]`. Lines649–692 check CMD24, CMD25, bad CRC exclusion,
unchanged footer and readback after protocol/cache remount. These are stronger
than local cache readback alone. The apparent persistence is **testbench RAM**:
there is no file open/pwrite/fsync or real MiSTer Main in that fixture.

`prepare_hps.py` copies local hps_io and adjusts existing PS/2 generated-scope
names only; it does not replace the MMC transfer logic. Conversely, the older
`mmc_mister` authored ARM test is a historical read-only fixture: its WP/R1
expectations must not be reused as proof that current writes fail. It was
written before writable adapter integration, and current adapter mount policy
now passes its input flag rather than forcing read-only.

## Source-level path and discriminating failures

1. Original EPBUS must choose CMD24/25, length512 and a valid aligned byte
   address; native DMA uses selector2 and TX control2, memory32-bit incrementing
   to fixed8-bit FIFO alias`10120624`. Host physical FIFO is`0c120624`.
   DMA completion says bytes reached the host FIFO; card acceptance/programming
   and host data-idle remain separate. No existing original-firmware write
   execution receipt covers that entire operation.
2. `ngage_mmc_host.v` consumes FIFO data serially, emits CRC16, checks the card
   response token and waits busy. Status bits: dataCRC0, responseCRC1,
   dataBusy2, cmdBusy3, busyTimeout5, responseTimeout6, dataTimeout7,
   responseReady8, missing/error-token10. Data/command completion cannot be
   inferred from DMA idle alone. Existing peer fixtures cover these mechanics.
3. `ngage_mmc_card.v:1271` admits CMD24/25 only in TRAN state with CSD command
   class4. It rejects WP with R1bit26, non512 block length with bit29,
   misalignment with bit30 and payload/capacity overrun with bit31. Missing
   class4 produces illegal-command bit22. Current write engine always receives
   a512-byte sector, independent of read partial-block support.
4. Card CRC/end validation precedes token and HPS request. W_PROG issues one
   sector even for CMD25; it holds DAT busy until backing completion. It then
   publishes the metadata-slot tag and invalidates/updates stream metadata.
   The metadata array can satisfy read-after-write locally: **successful same-
   session readback alone is not persistence proof**. The existing remount
   test and new independent backing oracle avoid that ambiguity.
5. `ngage_mmc_hps.v` captures mount read-only only on the selected slot2 mount
   pulse. It requires valid NGAGEMMC/v1 footer admission, single-sector writes,
   in-payload LBA, and exclusive direction. It captures direction/LBA/count and
   generation, advertises `sd_wr[2]`, counts address progress during0x18, and
   drains reset/replacement/ACK tails. A short/skipped/overlong/wrong-direction
   transfer sets fault and quarantines the slot. There is no Linux errno or
   storage-commit result input: adapter success is transport completion only.
6. Template connects selected mount/ACK and `sd_buff_din[2]` to that adapter;
   saves are slots0/1. Real hps_io command0x16 reports slot/direction/LBA;
   0x18 reads outgoing halfwords and advances the shared address. Tests exercise
   that RTL. Actual Main must service slot2 against the intended writable file
   and retain the bytes. Offline HPS emulation cannot establish that last step.

No concrete production RTL defect was demonstrated by this audit. Plausible
remaining boundaries are original driver/descriptor sequencing, mounted-media
policy, installed older read-only RBF, real Main slot/file service or physical
implementation behavior. They remain alternatives, not diagnosed causes.

## Write protection and image evidence

`write_protected = ro | csd[13] | csd[12]` in the card. Linux mount read-only and
CSD permanent/temporary protection are independent. Changing a shared metadata
bus for another slot must not alter captured slot2 policy; the actual-HPS
fixture explicitly tests this.

The saved local manifest `build/mmc/sis-group-1-128mb-ro.json` states
`core_readonly:true`, `csd_write_protected:true` and identifies image SHA256
`899ea722eeba5063796d25ed524bb78bbcc0832ba0d119928d91bc55661dabc9`.
The status entry for16November describes that protected installer card on
b707ebd. This makes protection a **supported possibility for that historical
session**, not proof about the currently failing operation. The actual image
file is no longer present in the inspected local build/mmc directory; its
footer was not re-read or modified here.

Folder-card generation is different: `tools/mmc-card/mkcard.py:711` supplies
class4 and WRITE_BL_LEN9 and explicitly clears both protection bits. Its old
README still says production forces read-only; that text is historical and
cannot identify the installed RBF. `tools/ngage_mmc_image.py inspect` reports
footer protection and writable eligibility, but needs the exact mounted file.
An image filename, absence of filesystem file attributes, or a writable Linux
path does not establish unprotected CSD. No protection was disabled.

## New narrow offline probe

Reusable additions: `tests/phone/mmc_write_diagnosis/run.py` and `tx.S`.
They extend the existing authored-ARM fixture under a dedicated build output,
not production. Generated identity/data are nonprivate. The writable CSD is
chosen explicitly for this synthetic test; no original identity is altered.
The existing full-sector reads run first. Then ARM fills512 source bytes,
issues CMD24/LBA3, programs source32/destination8 TX2 DMA, waits **both** DMA
idle and host data-idle, checks status, and reads512 bytes back through PIO.
The backing peer independently checks all256 outgoing halfwords, writes them
into its separate image array, and the terminal oracle checks all512 stored
bytes plus every other payload/footer halfword. A plusarg corrupts the final
persisted halfword after the outgoing-data check; the terminal oracle must
reject it even if card-cache readback succeeds.

Compile inputs are copied and hashed before compiling, so parallel CPU release
work cannot change a running executable. One offline simulator job runs at a
time with the existing `jotego/simulator:arm64` image, network disabled.
Reproduce from the active checkout:

```sh
python3 -B tests/phone/mmc_write_diagnosis/run.py --prepare
docker run --rm --pull=never --network none --platform linux/arm64 \
  -v "$PWD:/work" -w /work --entrypoint python3 jotego/simulator:arm64 \
  tests/phone/mmc_write_diagnosis/run.py --sim
```

This intentionally does not run the old fixture's read-only rejection case.
The source program remains uncached authored test code, not original EPBUS,
filesystem, CMD25 or board qualification. Actual hps_io and TX DMA are still
qualified in separate fixtures. No universal end-to-end claim is made by
combining those receipts.

**Measured:** PASS297,511 clocks,4 backing reads,1 write,512 independently
stored bytes and512-byte PIO readback; all adjacent payload/footer halfwords
unchanged. Corrupting persisted halfword1023 rejects at the terminal oracle
(nonzero exit), despite the preceding cache-backed PIO readback completing.
[Machine receipt and compiled input hashes](evidence/mmc-write-diagnosis-20261117.json).
Own compiler/source snapshots and generated inputs were removed after hashing;
compressed logs/receipts retain under1MiB. No other run's files were cleaned.

## Smallest additional observation and diagnostic sequence

First correlate the **installed RBF identity, exact mounted image, failing
operation and visible error**. Saved fitted artifacts do not prove which RBF
is running. Prefer existing build receipts and existing read-only logs; do not
reload or trigger a write to discover this. Read the exact image footer/manifest
and selected mount read-only if available; do not infer either from the name.

The smallest discriminating transaction observation is **whether the first
failing CMD24/25 is issued and its R1 response**. R1bit26 immediately localizes
a protected-card rejection before data/TX DMA; bit29/30/31 localizes length/
alignment/range, bit22 a command/profile/state issue. If no write command is
issued, investigate firmware/filesystem rejection and reported drive policy
before host/card transport.

If R1 accepts, capture the next boundary only: TX descriptor/control, DMA error/
completion, host terminal status/token and `card_sd_wr`. If no card write request
appears, stop at host/data/CRC/busy and do not blame Linux. If it appears, record
adapter fault, slot2`sd_wr`, requested LBA/count, selected ACK0→1→0 and outgoing
address count0→256. A transport fault or no selected ACK localizes the HPS
boundary. If all256 words drain, compare **that LBA's backing-file bytes** using
read-only inspection after the authorized operation has completed. Disk bytes
unchanged with successful transport points beyond card cache to Main/file
service; bytes changed correctly with phone error points back to firmware/
completion/filesystem interpretation. Remount/reboot persistence testing belongs
to a later authorized disposable-image test, not this read-only investigation.

Current DDR status exports only an aggregate OR of LCD unsupported, DMA error
and MMC HPS fault in Template; it does not independently expose every milestone
above. Absence of that aggregate error is not proof of writes or persistence.
A future passive capture should latch the first write command/R1 and the next
missing milestone, using existing observers where possible. Do not add a large
unbounded trace or perform a deployment in this diagnosis. If no saved capture
contains CMD24/25/R1, a new **read-only observation of an operator-authorized
failure** is required to localize it; simulation cannot substitute for that.
