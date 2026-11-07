# Nortido hybrid N-Gage reference review — 2026-11-06

Reviewed [nortido/NGage-MiSTer](https://github.com/nortido/NGage-MiSTer) at
`1be08b9bcf951a4523085747572ea102b96de65b` (2026-11-02). Read-only reference
checkout: `scratch/reference-nortido-ngage/`, obtained with `gh`. This review
does not run its binaries, build scripts or firmware. No production RTL changed.

The README describes a hybrid using the second HPS ARM for guest execution and
FPGA peripherals. It is a particularly relevant implementation reference for
our NEM-4 V4.03 work, but its boot/game claims were not independently reproduced.
It modifies the guest and replaces some drivers; distinguish peripheral register
leads from compatibility interventions below.

## LCD: concrete leads for milestone 7.5

Primary sources: [LCD RTL](https://github.com/nortido/NGage-MiSTer/blob/1be08b9bcf951a4523085747572ea102b96de65b/rtl/ngage_lcd.sv#L77),
[host screen-clear sequence](https://github.com/nortido/NGage-MiSTer/blob/1be08b9bcf951a4523085747572ea102b96de65b/hps/lib/ngl_lcd.c#L9).

| Operation | Reference interpretation |
| --- | --- |
| `+0=09200000`, `+8=opcode` | Select panel register/command |
| `+0=09240003`, `+8=payload` | Window parameters packed as `start | (end << 20)` |
| `75`, payload `0CF00000` | Rows 0..207, per its screen-clear helper |
| `15`, payload `0B100002` | Panel columns 2..177; panel column 2 maps to framebuffer column 0 |
| `5C`, then `+0=8924D67F` | RGB444 pixel burst, two pixels per word, bits 11:0 and 27:16 |
| `66`, data read | Synthetic panel ID `48`, once, then zero |

The RTL tests transport bits 18 and 31 for parameter/index/burst phases rather
than requiring every header to equal one magic constant. This is a useful
hypothesis for the transport decoder, not a complete wire-level specification.

**Independent local trace cross-check:** the retained
`build/checkpoints/adc-first-timer-write/firmware-amd16-latency0-ideal-clocks-lcd-probe-extension-boot-io-adc6-200/bus.tsv`
contains opcode `15`, header `09240003`, payload `0B100002`, then a zero word
(lines 229–232, cycles 74845105–74845571). It also contains opcode `75`, same
header, payload **`0D000000`**, then zero (lines 338–341, cycles
103735272–103735745). Small extracted evidence:
`scratch/nortido-review/lcd-window-evidence.json`.

Thus column packing has a matching local observation; row endpoint behavior is
still unresolved: the proposed end field is 208 in our trace versus 207 in its
helper. Establish inclusive/exclusive, clipping, and the second zero word from
firmware and reached traces before implementing end bounds. The old
`build/sim/lcd-baseline-summary.json` points to a run directory whose bus file is
currently absent; the permanent checkpoint above supplies the actual evidence.

**Stock firmware disassembly cross-check during the new HDL boot:** all retained
instructions in `build/sim/boot-analysis.json`'s LCD transport/packing ranges
match the current service core byte-for-byte (core SHA-256
`be8b2ecdf5ff81f424b58838a8b93a1d1f65c0ae74890d2b96df8d5a7189b524`).
`scratch/logo-bringup/firmware-lcd-packing.json` preserves that comparison.
At `6448–6458`, the clear passes start=0, length=208 to `6738`; that routine
passes start and start+length to the row setter at `6878`. At `6890–68A8`,
the setter masks both arguments to eight bits, emits `start | (end << 20)`
and a second zero word. The column setter at `68AC` similarly emits the
literal `0B100002` and zero. Thus the zero word is intentional firmware output,
not an accidentally duplicated bus transaction. This establishes the software
packing; it still does not prove the panel's endpoint/wrap convention.

`6D44–6D7C` constructs parameter headers from count-minus-one; the window setters
request four, giving `09240003`. The clear computes `208 * 264 = 54912` at
`6738–6758`; `6974–6998` constructs `8924D67F` from that count minus one.
The pixel loops at `6460–6480` independently write 208 rows of 88 pixel pairs.
This separates transfer length from the window end value: do not change the
firmware's 208 to 207 or infer a 209-row pixel transfer. A compact retained
command/header summary is in `scratch/logo-bringup/retained-lcd-commands.json`.

Limits of the reference LCD implementation:

- It uses only the low-byte start; **ignores end coordinates** and wraps at the
  entire 176x208 framebuffer, not the programmed rectangle.
- It explicitly does not support odd starting columns. Out-of-range starts and
  column offsets below two are handled permissively.
- Its busy/ready readbacks are forced ready; most panel reads are unmodeled.
- The host screen-clear helper injects black pixels. That output must not be
  counted as guest rendering or Nokia-logo boot evidence.
- Its split even/odd synchronous framebuffer banks offer a useful FPGA RAM
  inference pattern, independent of the incomplete panel protocol.

Our `rtl/ngage_lcd_display.v` still needs the reached window decoding investigation.
This reference narrows that work substantially; it does not resolve orientation,
all initialization opcodes, panel identity or physical timing.

## Keypad: matching rocker wiring, missing behavior in ours

Primary source: [keypad RTL](https://github.com/nortido/NGage-MiSTer/blob/1be08b9bcf951a4523085747572ea102b96de65b/rtl/ngage_keypad.sv#L20).
Normalize by phone key names: its 26-bit key numbering differs from ours.

- The direct rocker agrees with our active-low GENIO mapping: up=1,
  right=2, down=10, left=13, OK=11 (upper halfword at `0C150208`).
  Music is bit 12 at `0C15020C`.
- It propagates contact drive in both directions between row/column lines;
  this is more complete than our current one-way scanning approximation, but
  is still not a full electrical/ghosting model.
- `0C150400` and `0C15040C` implement per-bit set in byte lane 2 and clear in
  byte lane 3, preserving other drive bits. Our current `rows <= din[21:16]`
  replacement does not implement that behavior. It also drives the seventh
  line through `0C120C14` bit 19 and reads it at `0C120C04` bit 19.
- Press edges latch matrix status bit 2 at `0C150100`; rocker/music presses
  latch upper-byte status there (left=08, up=20, right=80, down=02,
  OK=04, music=40). Status is write-one-to-clear, with a new press winning
  a simultaneous clear. Releases do not create events in this implementation.
- The reference routes keypad IRQ to interrupt source **25**. Our source 25
  already aggregates NOS-related state in `ngage_upp_peripherals.v`; reconcile
  shared pending/ack semantics rather than replacing that source with keypad.

Our current keypad module has no interrupt output. This makes interrupt-driven
input a higher-priority follow-up than adding more host key bindings. Its own
host input mapping leaves some logical contacts unmapped; do not adopt it as a
complete phone keyboard specification.

## Other useful leads

| Area | Finding and practical use | Limit |
| --- | --- | --- |
| MMC/DMA | `rtl/ngage_mmc.sv`: MMC at `0C120600..63F`, seven DMA channels at `0C120300`, stride `40`; LCD counts words-minus-one, card path bytes. Command index `+1C`, argument `+20`, start `+04`; tracks fresh command versus continuation. Useful for investigating our unresolved EPBUS/card register interpretation. | Command subset with synthetic CID/CSD and ready state; validate traces and address aliases before assigning all accesses to MMC. |
| UEM battery | `rtl/ngage_soc.sv:491–504`: ADC select register `39`, result `3A`; channel 8 returns 480, described as normal-battery BSI class 1. | Another implementation's constant. Investigate our channel 6/13 assumptions against actual firmware; do not globally substitute 480. |
| Timers/interrupts | `rtl/ngage_soc.sv:507–555`: eight timers; 26 MHz enable from 50 MHz; modes, reload, flags, IRQ bank 0 and timer FIQ bank 3; lowest source index plus one. | Separate timing model with broad permissive registers. Its 50 MHz CPU / 100 MHz system is not our 104 MHz SDRAM validation. |
| NOR | `hps/mon/nor.c:94–101` programs `old & data`, preserving the NOR 1-to-0 restriction; explicit sector erase. | Supports reviewing our seeded-PMM discrepancy, not proof of phone timings. |
| C: save | `hps/lib/ngl_cdrv.c`: raw payload with magic/version/ROM identity/CRC, stable-generation snapshot and corruption/failed-mount guard. Useful robustness patterns. | Host file persistence with custom Main/monitor, not our chosen stock `hps_io` C:/PMM block format. No reason to replace our storage architecture. |

## What this does not establish about unresolved hardware

The service-ROM builder applies **589 overlay bytes in 111 runs** after assembling
service records (`hps/lib/ngl_svcrom.c:20,73,274`), in addition to the monitor's
patch machinery and `releases/ngage_patch.txt`. These are guest modifications;
the patch count is not a count of distinct hardware bypasses.

`hps/guest/nos_glue.S` replaces NOS export slots and object methods;
`nos_isi.c` synthesizes accessory/light replies and vibration state.
`bt_hci.c` supplies replacement Bluetooth behavior. The README explicitly says
SIM/calls/SMS are not emulated. This is not validation of our physical
SIMIF/ADSP/NOS exchange or evidence that it can be skipped in an unmodified boot.

Audio is captured at a patched PCM site (`hps/mon/main.c:1829–1831`) and forwarded
to a custom FPGA ring by `audio.c`; it does not demonstrate Nokia DSP emulation.
Backlight logic in `hps/mon/light.c` observes firmware kernel activity state;
vibration follows the replacement NOS driver's state. Both are useful user-facing
substitutes, not physical UEM/motor protocols. Cache cleaning/address translation
in monitor DMA code similarly belongs to its HPS execution architecture.

## Recommended next work, within existing milestone 7.5

1. Add the exact retained LCD transactions above to the reached-command table.
   Decode the transport independently; settle row 207/208 and the trailing word.
   Test nonzero starts, odd starts, subwindows, bounds/wrap and CPU/DMA arbitration
   before relying on a logo picture. Preserve unsupported-command diagnostics.
2. Investigate keypad drive set/clear and press/W1C interrupts against firmware.
   Add directed tests for lanes, scan direction, held keys, release/repress,
   simultaneous press/ack and shared source 25. Keep physical key numbering
   explicit and the keypad inside the existing chip boundaries.
3. Continue the unmodified HDL boot-to-logo task. Use this core to explain reached
   transactions, while retaining strict faults and independent checkpoints.
4. Investigate MMC and UEM/BSI only as the boot reaches them or evidence requires
   it. Keep the 104 MHz fitted-timing and real-board storage gates separate.

These are research-informed follow-ups, not claims that any new protocol has
been implemented or tested. No long simulation, synthesis, board run, save write
or firmware mutation was performed for this review.

## 2026-11-07 implementation follow-up

Translated the reference's keypad contact table into this project's public key numbering and implemented both drive banks, inverted KPC sixth-row drive, bidirectional one-hop contact scanning, press-edge/W1C status and independent keypad IRQ aggregated with NOS on source 25. Tests cover all 20 matrix contacts in each direction, all six direct events, held/release/repress and simultaneous press/clear, byte lanes, shared NOS acknowledgements and ICU masking. Reference reset drive state is now explicit. See `docs/live-controls.md`; physical timings/ghosting/UI verification remain open. No firmware or reference host patches were copied.

LCD parameter capture now recognizes the observed two-word full-panel 15/75 transactions and records command/header/data context for unsupported behavior. The actual cold HDL startup supplies a 125-write maintained test fixture. Stock `lcd.ldd` independently confirms CA/CC count and payload tables; generic Epson command sets disagree, so those init registers remain flagged. Odd/nonzero/partial windows are recorded and rejected for direct rendering while endpoint/wrap semantics remain unresolved. Full-frame scanout and DMA source-offset behavior remain separate from physical panel claims. Full evidence and remaining work: `docs/lcd-command-evidence.md`.
