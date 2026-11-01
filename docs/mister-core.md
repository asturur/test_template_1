# MiSTer core architecture — memory, flash, and video

## Memory map: phone → FPGA

| Phone PA | Size | Content | MiSTer resource | DDR3 offset |
|---|---|---|---|---|
| 0x00000000 | 8MB | CS0 flash (main firmware, scrambled [0xa000,0x2b3000)) | DDR3 read-only | 0x000000 |
| 0x02000000 | 4MB | CS1 flash (extension ROM) | DDR3 read-only | 0x800000 |
| 0x04000000 | 8MB | CS2 flash (second chip) | DDR3 read-only | 0xC00000 |
| 0x007f0000 | 64KB | PMM/security sector (erased on factory flash) | DDR3 R/W | 0x7f0000 (in CS0) |
| 0x0a000000 | 16MB | phone SDRAM | DE10 SDRAM | 0x000000 |
| — | 4MB | C: drive LFFS image | DDR3 R/W | 0x1400000 |
| — | 73KB | LCD framebuffer 176×208 RGB444 | BRAM | — |

**Total DDR3:** ~24MB (well within 1GB).
**SDRAM:** 16MB of 32MB used; second 16MB available for future (MMC, audio buffers).

## HPS data loading (accent accent accent accent the .rbf)

The MiSTer framework loads data files via `ioctl_download`:
1. **ROM file** (ioctl_index 0): the user's `core.bin` (18.6MB, the scrambled
   factory flash assembly) → DDR3 at offset 0. The HPS copies it verbatim;
   the FPGA descrambles on read (below).
2. **Extension** (ioctl_index 1): `extension.bin` (2.3MB) → DDR3 at 0x800000.
3. **C: image** (ioctl_index 2): `cdrive-stamped-4mib.img` → DDR3 at 0x1400000.

These map to the MRA's `<rom>` entries. The user assembles them from the
Nokia service files using the documented recipe (docs/firmware-integrity.md).

## Read-side flash descrambler (inline, combinational)

The 16 GF(2) formulas (build/firmware/thc/scrambler-model.json) are pure
XOR + AND of ciphertext bits and address bits — each output bit is:

    P_i = const_i ⊕ (⊕ selected C bits) ⊕ (⊕ selected A bits)
                   ⊕ (A_j0 & A_k0) ⊕ (A_j1 & A_k1)

At most 2 quadratic (AND) products per bit, the rest is XOR trees. This is
~50 LUTs total for the full 16-bit descrambler — trivial on Cyclone V.
The descrambler applies to halfword reads in the window [PA 0xa000, 0x2b3000)
only; all other flash reads pass through unchanged.

The module takes {halfword_address[21:1], ciphertext[15:0]} and produces
plaintext[15:0], purely combinational, one-cycle latency = zero (or
register the output for timing if needed).

## Flash read path

```
CPU PA ──→ [address decode] ──→ DDR3 read (2-3 cycle burst)
                                    │
                                    ▼
                              [descramble?] ──→ CPU data bus
                              (PA in window)
```

For writes (PMM flash program): the C++ model's `block14d_` overlay lives in
BRAM (64KB PMM sector) or DDR3. Reads check the overlay first; unprogrammed
halfwords fall through to the DDR3 flash image.

## Video output

The LCD DMA engine writes 176×208 pixels in RGB444 (4 bits per channel,
packed as 0x0RGB halfwords, two per 32-bit word). The framebuffer sits in
dual-port BRAM (176×208×2 = 73,216 bytes ≈ 72KB); the DMA write port fills
it, the video scan reads it.

MiSTer video: the scaler accepts any resolution. Output a 176×208 frame at
~60Hz with appropriate blanking; the OSD and scaler handle the rest. Color
expansion: 4→8 bits per channel via `{nibble, nibble}` (×17/255 = the sim's
render_lcd_frame.py mapping).

## CPU clock

ZAP on Cyclone V is unproven at high speed. Start at 26 MHz (real phone
crystal = 26 MHz before the PLL); the ideal-clock model means the firmware
doesn't care about the actual frequency — it ran at 1 access/cycle in the
sim. SDRAM wait states are the main concern; the firmware tolerates them
(it ran on real SDRAM hardware).

## Build / sim separation

- `build/sim/` — the C++ Verilator sim (boot_profile.cpp, checkpoints,
  bus traces). This is the fast-iteration research vehicle.
- `build/mister/` — Quartus synthesis output (.rbf, .sof, reports).
  Completely separate checkpoint and result lineage.
- `rtl/` — shared HDL source (ngage_board.v, ngage_modem.v, ngage_cpu.sv,
  ngage_mister.v). Changes here affect both sim and synthesis.
