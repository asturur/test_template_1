# TI C55x DSP reference notes (for N-Gage UPP DSP stub/emulator)

Sources read: `docs/spru312.pdf` and `docs/TMS320VC5509AGHHAU-Texas-Instruments.pdf`. Page refs are PDF page indices (`pdf p.`) with printed page labels where noted.

## 1. Documents

- **spru312.pdf**: "TMS320C55x DSP Functional Overview", SPRU312 (2000 errata-era). 56 pages. Covers CPU overview, memory (ch.3), on-chip peripherals (ch.4: DMA, EHPI, McBSP, timers, EMIF). It is the only one of the two with EHPI/host-interface and boot-loader text. Generic; defers device specifics to the device datasheet.
- **TMS320VC5509AGHHAU-Texas-Instruments.pdf**: despite the filename, the content is **"TMS320C55x DSP Mnemonic Instruction Set Reference Guide (Rev. G)", SPRU374G, Oct 2002**, 679 pages. It is the instruction-set reference (syntax, descriptions, opcodes in ch.6). It is **not** the VC5509A device datasheet. No device memory map, pinout, HPI register map, or boot-mode pin table is present.

## 2. Core facts

- **Address space** (spru312 pdf p.10, p.20): "maximum of 8M words (16M bytes) of memory ... organized as a single program/data space." Table: "8M x 16-bit (16M-bytes) total addressable memory space" (pdf p.10 / line 239).
- **Byte vs word addressing**: spru312 states memory as 16-bit words. spru374 NOP description: "The program counter (PC) is incremented by 1 byte" (instruction reference, NOP section, printed p.5-344). So program addressing is byte-granular.
- **Instruction stream**: "variable byte width instruction set for improved code density" (spru312 pdf p.12). "The CPU fetches 32-bit packets from memory into the Instruction Buffer Queue (IBQ). The IBQ holds up to 64 bytes ... provides 6 bytes at a time to the instruction decoder" (pdf p.12).
- **Instruction length**: neither document gives an explicit min/max range in the text read. Examples in spru374 show 2-byte and 3-byte forms (`NOP_16` "2-byte instruction"; `NOP_16||NOP` "3-byte instruction", pdf p.495). Opcode patterns in ch.6 are 8-bit-aligned groups of up to 24-bit `P24`/`L16` fields (see section 4).
- **Endianness**: not stated in either document (grep for endian/little/big found nothing). Mark as **unknown**; derive from the ARM-side API RAM layout if needed.
- **Memory map**: spru312 pdf p.10 table: on-chip SARAM 32K words (64K bytes); on-chip DARAM 128K words (256K bytes); on-chip ROM 16K words (32K bytes); total 8M words. Exact address ranges are in the device datasheet, which is **not** in this set. DARAM = 2 accesses/cycle per block; SARAM = 1 access/cycle; ROM = single-access, 2 cycles per access (spru312 pdf p.20, printed 3-1/3-2).
- **Reset/boot**: spru312 "On-chip Bootloader (in ROM)" present (pdf p.10). "At power-up, these bootloaders can automatically transfer user code from an external source to anywhere in memory. The bootloader may support transfer of program information from any of the following sources: EHPI, external asynchronous memory, or serial ports" (pdf p.20, printed 3-2). **Boot mode selection pins, reset vector address, and boot-loader modes are not in these documents** (device datasheet item).
- **Clock after reset**: "The clock generator is is bypass mode after reset" (spru312 DPLL section; verbatim typo kept).
- **RESET instruction** (spru374 printed p.5-373): "performs a nonmaskable software reset." Affects ST0_55, ST1_55, ST2_55, IFR0, IFR1, T2. ST3_55, IVPD, IVPH **not** affected. INTM set to 1; pending IFR0/IFR1 cleared. Initialization differs from hardware reset (pdf p.465).

## 3. Host / shared-memory interfaces

- **EHPI (Enhanced Host Port Interface)**, spru312 §4.5, printed p.4-14/4-15, pdf p.34-35:
  - "16-bit wide parallel port through which a host processor can directly access the DSP's memory space, with the host acting as master of the interface."
  - 20-bit address bus (non-multiplexed), 16-bit bidirectional data bus, HRDY handshake, multiplexed and non-multiplexed modes, "Shared-access mode (SAM) where the EHPI, CPU and DMA all have access to the same memory space."
  - Mode selected by **HMODE** pin. Non-multiplexed: internal HPIA/HPIC not available. Multiplexed: address/data share the data bus; **HCNTL0/HCNTL1** select transaction type; internal registers:
    - **HPIA** = address register (20-bit, autoincrement),
    - **HPIC** = control register (config, handshake, error, DSP interrupt, host reset control), multiplexed mode only,
    - **HPID** = data register.
  - EHPI reaches memory via a dedicated auxiliary DMA channel (pdf p.34).
  - Can download code while DSP held in reset; "a device reset on the DSP puts the device in a reset state ... the EHPI can load memory and then ... release the device from reset" (pdf p.35, §4.5.3).
  - Bit-level HPIC/HPIA/HPID layout, register addresses, and interrupt bit definitions are **not** given in these documents (device datasheet item). Do not invent them.
- **Mailbox / interrupt-to-host**: spru312 says HPIC provides "host/DSP interrupts, handshaking, error conditions, and DSP reset control by the host" (pdf p.34). No mailbox register set described. The specific ARM<->DSP mailbox of the UPP ASIC is **not** a TI C55x-standard block here; it is proprietary to the UPP and must come from the N-Gage side.
- **Interrupt vector table** (spru374): software interrupts use `IVPD`/`IVPH` pointers combined with a constant. `INTR k5`: "The interrupt vector address is defined by the content of an interrupt vector pointer (IVPD) combined with the unsigned 5-bit value" (printed p.5-157/5-158, pdf p.250). `TRAP k5` likewise (pdf p.598). Table base, vector spacing, and IVPD/IVPH width are **not** given here; check device datasheet.
- **Host interrupting DSP**: spru312 says HPIC carries DSP interrupts, but the bit/line that a host sets is not documented here.

## 4. Instruction encodings (spru374 ch.6, Table 6-1 "Instruction Set Opcodes", printed 6-2..6-8)

Quoted exactly. `E` = parallel enable bit ("Indicates if the instruction contains a parallel enable bit", spru374 glossary; "E: Parallel Enable bit is cleared to 0"). `x`/`k`/`L`/`P` are operand fields.

| Instruction | Opcode (verbatim) | pdf p. |
|---|---|---|
| NOP | `0010000E` | 617 |
| RET | `0100100E xxxxx100` | 619 |
| RETI | `0100100E xxxxx101` | 619 |
| B L7 | `0100101E 0LLLLLLL` | 619 |
| B L16 | `0000011E LLLLLLLL LLLLLLLL` | 616 | not checked |
| CALL L16 | `0000100E LLLLLLLL LLLLLLLL` | 616 |
| B P24 | `01101010 PPPPPPPP PPPPPPPP PPPPPPPP` | 620 |
| CALL P24 | `01101100 PPPPPPPP PPPPPPPP PPPPPPPP` | 620 |
| B ACx | `10010001 xxxxxxSS` | 620 | not checked |
| CALL ACx | `10010010 xxxxxxSS` | 620 | not checked |
| RESET | `10010100 xxxxxxxx` | 623 | not checked |
| INTR k5 | `10010101 0xxkkkkk` | 623 |
| TRAP k5 | `10010101 1xxkkkkk` | 623 |

Note: the `E` bit is the parallel-enable bit, so NOP's 8-bit form is `00100000` (E=0) or `00100001` (E=1). The E=1 case is not separately listed in the text read. RET/RETI use `xxxxx100`/`xxxxx101` tails. Rows marked "not checked" were located by text search without a page check.

## 5. Other useful items (brief)

- **Timers** (spru312 §4.7, pdf p.39): "16-bit countdown timers"; interrupts to CPU or DMA; TIN/TOUT pin; 4-bit prescaler (pdf p.10 "16-bit timers with 4-bit prescalers"). Two timers on this device class (pdf p.10 table).
- **DMA** (spru312 §4.4, pdf p.33-34): 6 channels; 8/16/32-bit transfers; triggers include McBSP, timer, external interrupt; EHPI has a dedicated DMA port.
- **McBSP** (spru312 §4.6, pdf p.36): full-duplex, "very similar to (and compatible with) those found on the C54x DSP"; 3 McBSPs (pdf p.10).
- **Instruction cache**: 24K bytes configurable (pdf p.10).
- **EMIF**: async/SBSRAM interface; BE[3:0] byte enables (spru312 §4.3).
- **Gaps for a stub**: no device memory map, boot-mode pins, reset vector, HPIC/HPIA bit layout, mailbox definition, endianness, or cycle timing in either document. Those must come from the device-specific TI datasheet (SPRS for VC5509A) or from measured N-Gage behaviour.
