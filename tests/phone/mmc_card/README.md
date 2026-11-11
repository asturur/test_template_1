# Standalone native MMC card model

`rtl/ngage_mmc_card.v` ports the pinned donor card to strict Verilog-2001.
`rtl/ngage_mmc_dpram.v` is its dual-port backing-cache helper, not a physical
phone chip. This fixture verifies the standalone port. P3.3 subsequently
connects it at board level through the read-only HPS adapter; see
[MMC production details](../../../docs/mmc-port.md).

Pinned source is ngage2 `rtl/board/mmc_card.sv`, SHA256
`3dad56b55982c4589b173850066ca4e8297c68d88fb376d7529912ac5f73c434`, and
`rtl/board/tdp_ram.sv`, SHA256
`e235b8c071c5b2faa97bc263d51f1e79e7ad52786be4edb7bf2667c4e91fe344`.
Both retain their GPL-2.0-or-later SPDX notice. The card snapshot includes the
reviewed payload-EOF and footer-version fixes. The source conversion and
pinned reference snapshots are retained under
`scratch/ngage2-integration/p3-native-card/` for this integration session.

The public interface preserves the donor's 1-bit native CLK/CMD/DAT0 peer and
MiSTer WIDE=1 HPS backing interface. Defaults, identity/footer parsing, CRC7 and
CRC16, command responses, streaming-buffer behavior and modeled timing remain
as in the pinned donor. Conversion changes types, syntax and names: explicit
wires/registers, Verilog-2001 function/task bodies, priority-preserving function
returns, sized casts expressed as bit slices, and separate loop indices.

## Verification

From the repository root inside the installed offline simulator image:

```sh
MMC_CARD_OUT=scratch/ngage2-integration/p3-native-card/logs/pinned \
  tests/phone/mmc_card/run.sh
```

Both external-wire/HPS tests compile with `iverilog -g2001`. EOF coverage passes
282,492 clocks; footer-version coverage passes 196,894 clocks. These retain the
independent command/data CRC peer, sparse backing-image oracle, delayed HPS
ACK, write persistence, readonly precedence, unknown-footer rejection, raw
fallback, reset and remount checks. No internal decoder or state is forced.

To run the original donor C++ suite, including a cycle-by-cycle public-output
comparison, from the host:

```sh
NGAGE2_DONOR=/path/to/pinned/ngage2 \
  MMC_CARD_DONOR_OUT=scratch/ngage2-integration/p3-native-card/donor-suite \
  tests/phone/mmc_card/run-donor.sh
```

This checks the two donor source pins, mounts that checkout read-only, uses
`jotego/simulator:arm64` with `--pull=never --network none`, and keeps every
output in this checkout. The unchanged `sim/harness/mmc_main.cpp` and `common.h`
are read from the donor. `--prefix Vmmc_card` preserves its generated include
and C++ class name while the port's top module is `ngage_mmc_card`.

The donor, port and public-output lockstep wrapper each pass the same original
suite at exactly 13,907,842 clocks with seed 1 and identical output/streaming
metrics. It exercises retail CID/CSD, writable and read-only raw cards,
identification and CRCs, command state/errors, reads/writes, partial/misaligned
reads, stop, data CRC failure, streaming quarters/cache and delayed HPS. Its
printed final HPS counts describe the final fixture, not aggregate write
coverage; the separate EOF oracle verifies four actual persisted writes.
The lockstep wrapper also runs both external-wire/HPS regressions, comparing
active CMD/DAT values, presence/WP, HPS ownership, requested extents and write
bytes. Inactive line data and unowned buffer contents are intentionally ignored.
These are exercised-trace equivalence checks, not a formal equivalence proof.

Pinned Verible v0.0-4298-g085eef05 with the project settings is idempotent.
Verilator's strict 1364-2001 lint passes with only `UNUSEDSIGNAL` disabled for
intentional inherited unused bits (`img_size`, OCR, CCC and sector-helper input).
No width, truncation, blocking-sequential or other warning is suppressed.

## Explicit limits

- This is a standalone card/backing-store model. It does not invent the phone's
  unmodeled D550/AMA routing, level shifting, power, card detect or physical pin
  timing. The donor's sampled-clock assumptions and minimum phase duration are
  retained and are unverified against a real phone/card.
- Defensive out-of-payload DAT0 rejection reuses the donor's existing negative
  token `01011` plus R1 `OUT_OF_RANGE`. Its native MMC 3.x meaning is unverified;
  initial and continued EOF rejection normally use the earlier R1 range path.
  The lost-bound W_END/W_PROG fallback is not directly exercised.
- Backing-cache RAM keeps the donor simulation contract: own-port writes return
  new data and mixed-port read/write returns the old data in this model.
  Simultaneous writes to the same address remain undefined; no FPGA collision
  behavior or fit is established.
- Atomic hot replacement while HPS already owns a transfer remains unresolved.
  A model reset/card remount is not proof that an old backing-store transaction
  has drained. The donor's existing HPS ownership gap is retained.
- Command/address support remains the donor's tested model. Stream read CMD11,
  erase, write-protection groups, lock CMD42 and multi-card open-drain arbitration
  remain unimplemented. Sector-tag extraction retains the donor's 32-bit address
  limit; the tested write guard prevents rollover writes from aliasing LBA 0.
- No whole-firmware card mount, boot, UI, physical hardware, synthesis/fit or
  production HPS connection claim is made. No user card/image was modified.
