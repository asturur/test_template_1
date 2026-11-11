# NGAGEMMC archival image tooling

Run the generated-fixture tests without Docker:

```sh
sh tests/tools/mmc_image/run.sh
```

The command-line tool uses only Python's standard library:

```sh
python3 tools/ngage_mmc_image.py inspect card.mmc
python3 tools/ngage_mmc_image.py export-raw card.mmc card.img
python3 tools/ngage_mmc_image.py import-raw card.img restored.mmc --metadata card.img.json
```

Export creates `card.img`, `card.img.sidecar` and `card.img.json`. The raw file
contains only guest sectors. The sidecar is the exact final 512-byte metadata
sector, including otherwise unused bytes. The manifest binds payload size,
sector count and SHA-256, sidecar bytes/SHA-256, whole-image size/SHA-256, card
registers, capacity interpretation and source provenance. Import with that
manifest verifies all bindings; it never follows paths stored in a manifest.
Every output is created exclusively. A failure removes only files newly
created by that invocation and never overwrites an existing source or output.

For an existing raw dump, provide its actual CID, CSD and OCR explicitly, or
supply `--metadata` pointing to a card image, exact 512-byte sidecar, or export
manifest. There is no default or generated card identity. CID/CSD inputs need
16 bytes with valid CRC7 and the terminal bit. To handle Linux-style 15-byte
registers or 16-byte registers whose CRC byte is zero, explicitly request
`--normalize-register-crc`; the manifest records original and stored register
bytes and the specific repair. Other bad CRC values are rejected. Existing
card/sidecar bytes are never silently normalized.

`inspect card.img --raw` accepts the same identity options. It writes nothing
and reports the checksum of the hypothetical image formed by appending that
metadata to the supplied raw sectors.

The donor's v1 layout is:

| Metadata offset | Length | Contents |
| --- | --- | --- |
| 0 | 8 | `NGAGEMMC` |
| 8 | 1 | Version 1 |
| 9 | 7 | Unused bytes, preserved on export/reimport |
| 16 | 16 | CID in card byte order |
| 32 | 16 | CSD in card byte order |
| 48 | 4 | OCR, most significant byte first |
| 52 | 460 | Unused bytes, preserved on export/reimport |

The capacity formula comes from the donor's `tools/mkcard.py` and
`rtl/board/mmc_card.sv`: `(C_SIZE+1) * 2^(C_SIZE_MULT+2) * 2^READ_BL_LEN`.
Import supports the locally evidenced MMC profile only: CSD structure 2,
specification version 3, `READ_BL_LEN=9` and byte-addressing OCR. This profile's
largest capacity is 1 GiB. Inspection/export preserves CRC-valid unsupported
profiles but reports capacity as unknown and refuses writable-mount eligibility.
It does not apply a possibly incorrect legacy formula to another layout.

A supported-profile payload larger than the CSD capacity is rejected. A
shorter sector-aligned payload can be inspected/exported, but import requires
`--allow-truncated`. This preserves an archival prefix without padding,
changing the CSD or claiming missing sectors exist. Its manifest explicitly
marks it **ineligible for writable mounting**, even if CSD write protection is
clear. Complete images are likewise ineligible for writing when CSD permanent
or temporary write protection is set. These fields describe format/extent
policy, not verified device or FPGA behavior.

The tests use small generated files and an independent polynomial-division
CRC oracle. They check exact metadata offsets, every round-trip byte, CRC
normalization provenance, observed retail capacity arithmetic, unknown
profiles, corrupt/version/truncated/oversize inputs, checksum/size/type errors,
read-only sources, output collision rollback, opaque metadata preservation,
FIFO rejection without blocking, and bounded streaming reads.

This slice does not parse Aaru archives, build FAT filesystems, modify actual
card dumps, implement MMC RTL, or demonstrate a protected game launching. It
creates raw sectors plus NGAGEMMC metadata, not a VHD container; future MiSTer
slot naming/integration is separate.
