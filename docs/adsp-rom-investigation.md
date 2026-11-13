# External DA250 firmware and native startup diagnostic

Read-only source investigation2026-11-12. Original firmware unchanged; no
hardware access, FPGA build, CPU/PLL change or new DSP core implementation.
This advances the HDL-only boot investigation; it does not establish boot success.

## Inputs and architecture

NEM_4.ini explicitly selects E403A400H450.USB as AdspFile. Its1506378bytes
have SHA2560be93de04ebccd676d34ceaa2b9f4a901b3d0941565bc7b0f795e78ba8866429.
The second Disk1/data2 copy is identical. The update contains plain C55x code;
no decryption or ARM instruction substitution was needed to inspect these paths.
The leading08A5 metadata remains uninterpreted; it is not evidence that the
following code is encrypted.

The user-supplied docs/08-nem4-schematics.pdf is Issue2,09/2004, distinct from
the earlier Issue1 schematic. SheetA-8 visibly identifies D550TMS320DA250GHH-144
and D551M28W160BT100ZB6T, FLASH1Mx16. AMA-WD2_BUS links reset/INT1 and the
McBSP1 serial signals; McBSP2 connects MMC and McBSP0 the audio codec path.
Do not silently transfer every pin detail between schematic revisions.

User raised the possibility of an embedded ARM. TI's DA250-specific block
diagram identifies a C55x CPU and does not show ARM. This and the coherent
native C55x startup are positive evidence for the architecture being analyzed,
not a claim that every binary-looking section has been classified. No ARM core
or ARM executable section has been established in this ADSP image.
Primary source: https://www.ti.com/download/vf/audio/audiosolutionsguide1.pdf,
printed page18, DA250 block diagram. Other TI families with ARM do not establish
an ARM in this chip.

## Recovered mappings

At file1000,17 consecutive records contain big-endian32-bit destination WORD
addresses and counts of16-bit words, followed by payload. They end exactly at
17698; subsequent bytes areFF until external code starts at41200. The records
reconstruct91664 bytes into the256KiB analysis RAM address space. Holes remain
explicitly invalid; zero-filled output holes are not observed reset data.

The first record targets word80/program byte100, has80words and contains32
vectors at file1008..1107. TI SPRU280I explains that the first vector byte is
ignored and the next three encode the handler address. Thus the EA-leading
entries are vector DATA, not malformed branch opcodes or encrypted code.

| Item | Recovered program address | Original file location |
| --- | --- | --- |
| Reset vector target |441200|41200, candidate external flash byte base400000 |
| Common vector target |44E85D|4E85D |
| Native CALL000460 target |000460|112C, copied by record2 |
| Native CALL000900 target |000900|15CC, copied by record2 |
| Native CALL001E8B target |001E8B|2B57, copied by record2 |
| Vector13 handler |01D8EE|B8DA, copied by record8 |

Reset441200 initializes stack/register state, calls0022DE and000460, then
445277 and441305. Startup441305 calls000900 and001E8B. These RAM targets
are supplied by the image, not evidence of a missing internal-ROM routine.
Vector8 targets033B01 outside the17 initial copies and supplied external mapping;
its source remains unresolved (do not invent an overlay or ROM explanation).
The external400000 mapping is supported by cross-references and code boundaries,
not executed boot-ROM or physical flash qualification. The remaining tail of the
2MiB flash is not supplied by this shorter file and is not assumed erased.

Reproducer: tools/ngage_adsp_image.py, tests/tools/test_adsp_image.py. Native
mapping, unchanged ownership, five qualification tests and tamper/truncation
rejection pass. Private output: scratch/adsp-rom-20261112/recovered/image.json,
loaded-ram.bin and loaded-ram-valid.bin.

## Disassembler qualification and limits

Reference XVilka/c55xde pinned fe0630ce6592506b372d2c8bc1700fb16106394f.
Upstream was not reliable as downloaded: multi-byte operands reversed,4804
misidentified as RETI, and port substitution recursively expanded its own token,
causing an AddressSanitizer-confirmed stack overflow. Compilation also required
normalizing Unicode operators. The reproducible tools/c55x/decoder.patch fixes
these defects and supplies a file/range/base CLI. Selected TI opcode fixtures
and the formerly crashing port excerpt pass under ASAN after the fix.

The whole decoder remains unqualified. Some operand syntax is incomplete;
relative branch values are encoded offsets, not resolved target addresses.
Never classify data as instructions merely because it decodes. Retain raw bytes
and manually check critical instructions against SPRU374G. In particular use
function boundaries: the table immediately after44132F is data.

## Actual diagnostic42 handler found

The source contains a matching protocol sequence, rather than only a generic
DSP-health guess:

* Dispatcher451AAC compares incoming type2B and calls4519C3.
* Handler4519C3 allocates a reply through native01D9A9 and constructs type8B
  through01D957, matching the NOS client's expected reply type.
* It reads the requested test identifier and explicitly compares42 at451A10.
* Test42 calls451944, then serializes the result held at DSP data wordDBA6.
  Other test identifiers follow a different branch; do not return generic success.

Recovered test42 dependencies:

| Flag in data wordDBA7 | Original operation | Evidence / limitation |
| --- | --- | --- |
|0002|451B41 tests port1C00 bit0|Consistent with CLKMD LOCK; TI same-generation C55x clock reference gives LOCK bit0 and port1C00. DA250-specific pin/clock behavior remains unqualified. |
|0004|451B5C reads data word2B0000 and comparesFFFC|Byte address560000 maps to file160000, which actually containsFFFC. No fabricated marker is required. |
|0001|451944 sets this only when the transfer helper returns0|Setup02721B configures the3Cxx register bank with slave address1A, prescaler8 and clock dividers10/10. Write02729D sends1E00. This matches I2C and the AIC23 codec reset control word. |

Both451B41 and451944 set resultDBA6 to0 only when flags equal7; otherwise0C.
The handler also reports individual failures through native logging calls.

The codec inference is grounded in the full register sequence:3C09 mode,
3C01 interrupt enables,3C0C prescaler,3C03/04 clock dividers,3C07 slave address,
3C05 byte count2,3C08 transmit data and3C02 NACK/TX-ready polling. It is NOT
a timer wait: an initial exploratory filename test42-timer-poll.dis is obsolete
and refers to the I2C write routine. The16-bit word1E00 selects codec register15
and data0; TI AIC23 documentation defines this as reset. The schematic provides
the codec connection. A generic family manual alone does not establish every
DA250 address, but the native sequence and codec address give strong agreement.

Primary references:
* https://www.ti.com/lit/ug/spru146d/spru146d.pdf (C55x I2C registers/status).
* https://www.ti.com/lit/ug/spru317k/spru317k.pdf (CLKMD LOCK bit0).
* https://www.ti.com/lit/an/spra375f/spra375f.pdf (same-generation CLKMD port1C00).
* https://www.ti.com/lit/ds/symlink/tlv320aic23b.pdf (control word B15:9 selects register; register15/data0 resets).
* https://www.ti.com/lit/ug/spru280i/spru280i.pdf (vector entries, section7.1.1).

## Next implementation gate

Finish exact MADI framing, sequence/ACK, startup messages and reply byte layout
from the matching DSP sender/receiver and original host server. Then implement
bounded D550 protocol/control state and a distinct codec-control model, without
an additional DSP CPU or unconditional test-pass response. Tie diagnostic42 to
modeled clock readiness, the real image marker and an actual modeled codec reset
completion; exercise each failure independently. Shared UPP CTSI IRQ wiring is
still required. Native UART transport is qualified separately; no native MADI
round-trip or unmodified Menu boot is claimed by this disassembly work.

Area gate remains: renderer retirement already committed separately as c41d620;
DDR diagnostics retained. Operating PLL78MHz, timing design objective104MHz.
No full DSP ISA engine is proposed by this source investigation.

## 2026-11-13 implementation follow-up

The bounded native diagnostic42 operation and separate codec-control boundary
now exist and pass independently failed prerequisites and stalls at78/104MHz.
Native packet primitives have tests for preamble exclusion, checksum rejection
and all eight sequence values. Full transport/startup and production wiring
remain; see [sim-adsp-native-progress.md](sim-adsp-native-progress.md).
