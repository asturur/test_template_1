# Original guest FAT round trip

Use the exact disposable 128 MB fixture from
[`mmc_write_diagnosis`](../mmc_write_diagnosis/README.md). The runner checks
its hash before copying it. It also checks the locally prepared NEM-4 ROM
and uses the existing private NGVM reference, ARM cross compiler and Unicorn.
The ROM and generated images stay in ignored build directories.

```sh
python3 tests/phone/mmc_file_roundtrip/run.py mmc-file-roundtrip
```

The original ROM FileServer and FAT implementation create, write and flush
`E:\WRITE_TEST\ROUNDTRP.BIN`. A test-only local-drive adapter exposes the FAT16
partition to the guest and translates its writes back to absolute image offsets.
The host calls `fsync` and closes the image. A fresh guest process then opens the
image read-only and checks all 1,739 bytes. A third fresh process attempts a
write and must receive a guest error without issuing a backing write.

The independent FAT checker validates the new file, both FAT copies, allocation
chains, the two existing files, and a sector allowlist for this exact fixture.
The offline test also checks that replaying the recorded guest writes produces
the entire saved image byte for byte. The reference kernel supplies the drive
interface in this test. Use a board capture to check the native EPBUS and Linux
path together.

For a physical candidate, start from the unmodified fixture. In FExplorer,
copy `E:\README.TXT` into `E:\WRITE_TEST`, wait for Paste to finish, and read the
actual Linux backing file into a local capture. Run the same checker for the
374-byte copy, then close and remount the card and open the copy in the guest.

```sh
python3 tests/phone/mmc_file_roundtrip/verify_card.py --board-copy \
  build/mmc/write-test-128mb.mmc build/mister/<run>/after.mmc
```
