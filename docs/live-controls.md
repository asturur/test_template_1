## Live diagnostic text and named controls (2026-11-07)

The new diagnostic display replaces the bars in the integrated MiSTer core
with a 40x30 text page. A hand-defined 5x7 uppercase font in 8x8 cells occupies
one explicit 1024x8 M10K ROM, initialized at compile time from
`rtl/ngage_debug_font.mif`. `tools/generate_debug_font.py` generates that MIF
and the identical simulator HEX. No font file is loaded from the SD card.

The page samples its fields together every 16 frames (about four times/second).
The blinking header marker runs from video frames independently of the CPU.
It remains visible with CPU Hold/reset. All raster controls and RGB, including
Phone mode, have the same single-clock pipeline delay; phone pixels, active
rectangle and aspect ratio are otherwise unchanged.

- FETCH PC is the **current instruction-fetch virtual address**, not a retired
  instruction PC. LAST FETCH PC/OP is a paired accepted fetch address/raw word;
  Thumb fetch words can contain two instructions. These may be speculative.
- CPSR is the ALU-stage flags/mode register. Counters show active CPU cycles,
  accepted fetches, completed Wishbone ACK/error beats, current wait and maximum
  wait (system clocks). Counts wrap at 32 bits; wait counters saturate.
- BUS address/data/flags are sampled live and may be idle/stale. LAST BUS fields
  retain the last completed transfer, choosing write data or returned read data.
- DATA FAULT, FAULT FETCHPC/DATA/FLAGS/REASON preserve the **first non-fetch
  fault** until cold reset/core reload. FAULT FETCHPC is the contemporaneous
  fetch VA, not necessarily the faulting instruction. A warm reset/Hold retains
  context. FAULT DATA is requested write data, or the unvalidated raw read-data
  bus for a read fault. Reason 1 is board/protocol rejection, 2 unmapped, 3 flash error.
- BUS FLAGS: bits 0 CYC, 1 STB, 2 write, 3 instruction/code, 4 ACK, 5 ERR,
  6 atomic lock, 10:7 byte enables. FAULT FLAGS: 0 write, 1 code, 2 board claim,
  3 DMA claim, 4 board ready, 5 board unmodeled, 6 RAM hit, 7 flash hit,
  8 memory request, 9 flash error, 14:12 reason, 16 valid.
- BOOT FLAGS bits 0..7: PLL lock, firmware loaded, SDRAM scrub done, board init,
  save mounted, first data fault, export busy, export error/unsupported LCD.
  Higher BOOT FLAGS bits: 8 OSD Run selected, 9 firmware loader failed,
  10 save error, 11 save-manager busy, 12 phone reset request,
  13 save writing, 14 blocked firmware load, 15 firmware download,
  16 known firmware identity. CPU FLAGS bits 0..8: core reset, IRQ, FIQ, board claim, board ready,
  memory request, RAM hit, flash hit, flash transaction pending.
- The right pane names individual gate/status bits. Required boot gates are
  green/red; fault/error flags are red only when asserted; inactive activity
  flags are gray. Reset is amber when held. KEYS HELD shows the logical Nokia
  key mask; hold a key through a page refresh to inspect it.

The existing 1024-byte exported diagnostic format is unchanged; these live
CPU/bus fields are **screen observations**, not newly added export fields.
They add observability and do not resolve the first-board 0x08000000 failure.

### Controller definition now uses Nokia names

Re-run MiSTer's **Define joystick buttons** for this core after installing the
new RBF. Bind physical buttons to the named phone actions; A/B/X/Y placement
is controller-dependent and is no longer used to describe phone keys. D-pad
remains Right/Left/Down/Up in standard joystick bits 0..3.

| Prompt | Joystick bit | Nokia key bit | Keyboard |
| --- | ---: | ---: | --- |
| OK | 4 | 4 | Enter or A |
| Clear | 5 | 7 | Backspace |
| End | 6 | 24 | Escape |
| Menu | 7 | 6 | Tab |
| Left soft | 8 | 5 | F1 |
| Right soft | 9 | 9 | F2 |
| Send | 10 | 23 | Unassigned |
| Power | 11 | 26 | F10 |
| Music | 12 | 25 | C |
| Radio | 13 | 8 | Unassigned |
| Shift | 14 | 21 | Either Shift |
| Star | 15 | 10 | Shift+8 or keypad multiply |
| Hash | 16 | 11 | Shift+3 or keypad divide |
| 1..9 | 17..25 | 12..20 | Number row 1..9 |
| 0 | 26 | 22 | Number row 0 |

Smaller controllers can use the primary phone controls and keyboard for the
remaining keys; press Space to skip an optional mapping prompt. Main supports
up to 28 named buttons; these 23 actions fit its existing interface (checked
against upstream `input.cpp` get_btn/parse_buttons and `menu.cpp` mapping hints). Opening OSD suppresses all phone controls and clears keyboard
holds. Power is the existing UEM-level hypothesis; naming it does not add a
new electrical power/reset model. The former duplicate End mapping at joystick
bit 11 is now Power. Keep matrix/shared-IRQ/OSD and one-hot host tests passing.

The older A/B/X/Y descriptions below are historical and superseded by this
explicit map. Guest UI and physical key wiring still require phone validation.

## MiSTer diagnostic controls (2026-11-06)

The MiSTer port now routes held inputs through the same **experimental** GPIO matrix as the live-control simulation. Arrow keys/D-pad are rocker; Enter or keyboard A/controller A is OK; F1/controller X is left softkey; F2/controller Y is right softkey; Tab/Start is Menu; Backspace/B is Clear; Escape/Select or R is End; controller L is Send. The number row, Shift+3/Shift+8 and keypad multiply/divide provide digits and star/hash, Shift maps to the matrix, and F10 drives a separate UEM status-level power-key hypothesis. Keyboard make/break events and controller holds are ORed, so releasing one does not release the other. Opening the OSD suppresses controls and clears held keyboard state. These mappings have directed tests but have not been verified in a booted phone UI. Actual PWRONX electrical behavior, keyboard cleanup on USB disconnect and the need for a keypad interrupt remain unproven.

The MiSTer OSD defaults to CPU Hold and the diagnostic test display; select CPU Run and Phone display deliberately after loading a valid bundle and mounting a save. The diagnostic screen cells show PLL, bundle, SDRAM scrub, board init, save, first data fault, export busy and export/LCD-command error. The save cell is gray when unmounted, amber when dirty, cyan while saving, green when saved and red on error. For export, create a 1024-byte disk with `python3 tools/ngage_diagnostics.py create /path/to/diagnostics.ngd`, mount it using **Mount diagnostic disk**, select **Export diagnostics**, then decode it using `python3 tools/ngage_diagnostics.py decode /path/to/diagnostics.ngd`. Standard MiSTer block traffic and the actual `hps_io` disk protocol are tested in simulation; actual Main and media are not verified. See `status.md` for the current validation gates.

# N-Gage live control experiment

Start `python3 scratch/live-controls/start.py NAME` from the project root; it resumes the saved 23B checkpoint and writes images under `build/sim/screens/boot-v15-NAME-live/`. In another terminal send `python3 scratch/live-controls/keys.py tap leftsoft` (default 8 seconds of host time). `press KEY`, `release KEY`, and `clear` allow held keys; `list` shows names. Only run one such simulation at a time: the input file is shared. The initial image is copied from the last frame before the checkpoint.

Schematic A-13: rocker up GENIO1, right GENIO2, down GENIO10, OK GENIO11, left GENIO13; matrix COL0–5 GPIO8/9/10/11/16/30 and ROW0–5 GPIO12/13/14/15/17/18. Rows: 0 leftsoft/menu; 1 clear/radio; 2 rightsoft/star/hash/shift; 3 1/2/3/0; 4 4/5/6/send; 5 7/8/9/end. Music is GENIO28. Power PWRONX is not implemented. GPIO30 and GENIO28 inputs are hypotheses and not yet proven at the UI.

The rocker input mapping reaches the firmware scan and down translates to logical 0x80000. Matrix scan voltages, pull-ups, GPIO30 and music mapping are experimental hypotheses, not hardware-verified; leftsoft reaches column and row reads but UI response is not yet confirmed. The simulated real-time rate is slower than 104 MHz; use holds of several seconds of wall time. `latest.png` and numbered frame files update only after modeled LCD DMA writes; no image update is guaranteed for a key press.
## 2026-11-06 reference update

See the [Nortido hybrid keypad review](nortido-hybrid-reference.md#keypad-matching-rocker-wiring-missing-behavior-in-ours): rocker GENIO mapping agrees; per-bit drive set/clear, reverse contact scanning and press/W1C IRQs are concrete investigation leads beyond our current model. Reconcile source 25 with existing NOS pending state, normalize different key bit numbering, and verify firmware behavior before implementing. No keypad behavior changed in this review.


## Routed GPIO and startup self-tests

With the keypad enabled, GENIO1's idle rocker pullup previously hid a low driven by the existing UEM loopback. The new board-keypad regression reproduces that failure and verifies routed high/low, key grounding and disconnect. UPP passes staged `route2a[3]` as `genio1_driven`; the keypad merges its open-switch level with the driven base input. This retains an existing transaction-level routing hypothesis, not physical pin verification. Keep this test passing when expanding keypad direction/IRQ behavior.

## 2026-11-06: drive-bank bit set/clear correction

The existing staged six-line bank at `0C15040C` now ORs lane-2 bits `21:16` into its drive state and clears lane-3 bits `29:24`, with clear priority for overlapping masks. Previously a lane-2 write replaced all six lines and lane-3 writes were ignored. This uses the pinned Nortido register-semantics lead while retaining our current key map/direction approximation. Focused tests cover unrelated-line preservation, both byte enables, zero masks, no commit and simultaneous set/clear. They fail old RTL and pass the fix; existing board UEM/GPIO and CPU integration also pass. The long 12B simulation uses its frozen earlier build, so it is not validation of this fix. Other bank/direction/edge-IRQ work remains open.

## 2026-11-07: bidirectional scanning and shared IRQ implementation

Using the pinned Nortido keypad/input source, translated **by key name** into our existing numbering, the keypad now models both drive banks: row lines 0..4 at `0C150400`, six column lines at `0C15040C`, set/clear masks in byte lanes 2/3 with clear priority. The sixth row uses inverted bit 19 on full-word `0C120C14` writes, read at `0C120C04`. Reset drives all six row lines and floats columns, matching the reference. Previous tests now explicitly float the row drivers when exercising column-driven scans. Pressed contacts conduct a driven level in either direction; floated contacts no longer assert an input merely because a key is held. This is the reference's one-hop digital contact model, not a measured electrical/ghosting model.

Matrix press edges latch bit 2 at `0C150100`; up/down/left/right/OK/music latch bits 21/17/19/23/18/22. Read overlays own only mask `00EE0004`, preserving unrelated NOS data and respecting byte enables. W1C respects commit/byte lanes; a coincident press wins. Held/released keys produce no repeat events, while release/repress does. Keypad IRQ is ORed with existing NOS IRQ on ICU source 25. ICU masking does not acknowledge keypad status; keypad W1C cannot clear NOS pending state. No change to the NOS `3680` event mask or routed GENIO1 self-test merge.

`tests/phone/keypad/protocol_tb.v` checks both directions for all 20 matrix keys, default drives, direct-key events, W1C/hold/repress and lane behavior. Board tests verify shared NOS/keypad pending and independent acknowledgements plus ICU masking/re-enable. Existing host input and UEM loopback tests pass. Actual firmware UI responsiveness, physical pin delays and higher-order ghost contacts remain unverified. These changes are in a separate new build; the frozen 12B simulation retains the old keypad.


## Firmware panic report

The bottom diagnostic `PANIC` row shows the first full writes to physical
`0C0047F0`, `0C0047F4`, `0C0047F8`: two little-endian category words, then raw
reason. Special reason10000000 preserves exception PC/address instead of a
category string; the decoder identifies that packet. `MASK 7` means all three words were observed; cold reset clears them.
They are reporting attempts; ordinary categories must not be read as a PC. Export after the firmware
parks and decode with `tools/ngage_diagnostics.py decode diagnostics.ngd`.
The optional NGD extension occupies halfwords396..403 (magic504E, mask, payload);
old snapshots decode with `panic_report: null`. See [symbian-startup.md](symbian-startup.md).


### 2026-11-10: hardware input confirmed; shared W1C commit fix

User reaches Nokia screensaver with moving clock band; controls have no UI
effect. User confirms diagnostic KEYS HELD changes with OSD closed. This proves
hardware inputs reach the public Nokia key bits, not firmware recognition.

Auditing Template -> ngage_keys -> ngage_mister -> board/UPP/keypad finds no
missing enable/wire. However board keypad regression FAILS before the fix:
0C150100 remains00201004 after matrix W1C, expected00001000. Keypad commit was
only gpio_access, whose gpio15_selected explicitly excludes nos_claim. NOS owns
0C150100; keypad press pending could never acknowledge, so first key leaves a
shared source25 asserted. This is a real RTL defect; hardware responsiveness
after the fix remains unverified.

Local fix in ngage_upp_peripherals.v authorizes keypad W1C on accepted valid
NOS-owned writes at0C150100, keeping NOS storage independent. Existing GPIO
commit remains for drive registers. New board test covers all6direct events,
wrong byte lane versus proper upper-byte W1C, held input no repeat and IRQ clear.
Host map, full20key bidirectional matrix, board, NOS counter/status and registered
peripheral-response tests all PASS. Logs scratch/post-nokia-startup/
{keypad-tests.log,keypad-after.log,keypad-final-tests.log}. Actual ARM/UPP integration also PASS: software injects public key levels through
an SDRAM test mailbox, reads matrix/direct status, verifies ICU source25,
acknowledges low/upper byte events and verifies IRQ deassertion. This is directed
CPU verification, not a full-firmware key-input replay or hardware validation.
Keypad fix is separate from pending Bluetooth harness work; one hardware build
will test board responsiveness. Source preflight and pinned RTL formatting PASS.
