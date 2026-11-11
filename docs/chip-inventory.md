# NEM-4 chip and connection inventory

This inventory uses the local Nokia NEM-4 schematic
[`ser-no-n-gage-schematics.pdf`](ser-no-n-gage-schematics.pdf), issue 1,
09/2003. Page numbers below are the printed A-n page numbers, which match the
PDF pages. The separate `08-nem4-schematics.pdf` is another revision; do not
silently mix its parts or pin assignments with this revision. These are
schematic identifications, not evidence that our RTL implements each device.

| Component / sheet | Schematic identity and connections | Current implementation and limitations |
| --- | --- | --- |
| D100, A-3 | UPP_WD2: CPU/baseband processor. Its sheet exposes `CBUS(2:0)`, `UEM_INT`, `I_SIMIF(3:0)`, `LCD(9:0)`, `GENIO(28:0)`, `GPIO(37:0)`, `MEMADDA(22:0)`, `MEMCONT(9:0)`, SDRAM data/address/control and RF control. | `ngage_upp.v` contains the ARM (`ngage_cpu.sv`) and `ngage_upp_peripherals.v` in the MiSTer build. Its external connections are still transaction-level abstractions, **not a pin-level UPP implementation**. Several register ranges remain behavioral hypotheses. |
| D190, A-4/A-6 | UEM power/analog chip. Connected to `CBUS(2:0)` and `UEM_INT`, SIM interface signals, `PWRONX`, audio, charging, reset and RF-converter signals. | `ngage_uem.v` wraps `ngage_cbus_uem.v` and is instantiated by `ngage_board.v`. Its present UPP interface is a **parallel register-transaction shortcut**, not the serial CBUS pins. UEM_INT is a modeled interrupt level; exact electrical timing is unverified. |
| D310, D311, D313, A-10 | Three `AM29N643GT70MVAI` 4M×16 NOR devices, 64 Mbit each; the sheet shows shared `MEMADDA`/`MEMCONT` and separate chip-select wiring. Together these are 24 MiB of main flash. | `ngage_codeflash.sv` instantiates three independent `ngage_am29n643_state.v` command-state owners; `ngage_cflash.sv` and the shared controller retain the logical C:/PMM and DDR-backed behavior. These state modules are **not complete pin-level flash chips**, and the mapping from logical selects to D310/D311/D313 and image sections is not established. |
| D312, A-10 | `K4M28163PD-JG1L` 8M×16 SDRAM (128 Mbit, 16 MiB). `SDRAMDATA(15:0)`, `SDRAMADD(13:0)` and `SDRAMCTRL(7:0)` connect to UPP. | `ngage_sdram_adapter.v` / `ngage_sdram_arbiter.v` target the MiSTer board's SDRAM; their 32-bit request interface is a backing-memory adapter, **not** the phone SDRAM pin interface. |
| D550, A-8 | Separate `TMS320DA250GHH-144` **audio DSP**, with `AMA-WD2_BUS(4:0)` toward the phone, McBSP audio, MMC and USB connections. This is distinct from any baseband functionality inside the UPP. | `ngage_adsp.v` wraps the existing synthetic MDI register/ring hypothesis. It does not execute DSP instructions, model the physical AMA bus, or fabricate a successful self-test. |
| D551, A-8 | `M28W160BT100ZB6T` 1M×16 (16 Mbit, 2 MiB) flash attached to D550, with its own address/data/control and reset lines. | No distinct flash chip model or verified dump mapping. This device is **additional** to D310/D311/D313; do not equate its contents to the three main phone flash images. |
| N430, A-17 | Nokia `LRB2_0630271` Bluetooth module. GPP0/1 connect to UPP GENIO21/22 (`LPRFSync`/`LPRFInt`); GPP6/7 to GENIO19/20 (USART Rx/Tx); GPP10/11 and CENX to CBUS; RESETX, SLEEPX, SYSCLK and SLPCLK are also shown. See [bluetooth.md](bluetooth.md) for pin numbers and evidence. | `ngage_lrb2.v` is an explicitly unimplemented, non-driving component boundary, instantiated but disconnected/held in reset. Its bidirectional signals use input/output/output-enable form. Direction, reset sequencing and the wire protocol still need evidence; `ngage_bt_hci_stub.sv` remains isolated. |
| N601, A-22 | `MJOELNER_S2006F3A` GSM RF component. The schematic shows `RFBUSCLK`, `RFBUSENX`, `RFBUSDA`, reset and analog RF/I-Q connections to UPP/UEM and RF circuitry. | `ngage_mjoelner.v` is an explicitly unimplemented, non-driving digital control boundary, instantiated but disconnected/held in reset. It is not a GSM modem or working RF model. `ngage_modem.v` is an isolated high-level ISI/Phonet experiment, not this chip's pin protocol. |
| N801, A-21 | RF power-amplifier module in the GSM transmit path, with `TX_900`, `TX_1800`, `VPD_900`, `VPD_1800` and antenna-side connections. | No digital/audio/RF simulation or chip module. Do not assume it can supply network service. |
| N501, A-9 | `TLV320AIC23` audio codec, linked to the audio DSP via digital audio and codec I²C; analog audio connects to the headset/speaker circuits. | No codec module or audio path yet. |
| N500, A-9 | `TEA5767` FM radio, connected to GENIO control lines, audio codec inputs and antenna path. | No FM tuner module. |
| X470 / X553, A-14 | SIM and MMC connectors. SIM signals run through UEM; MMC signals route to the audio-DSP/card interface and support circuitry. | A diagnostic transaction-level SIM controller is inside UPP and a separate synthetic test card is connected at the board level. Physical UEM serial timing is unimplemented. `ngage_mmc_host.v` is inside UPP and `ngage_mmc_card.v` is at board level, with read-only slot-2 backing through `ngage_mmc_hps.v`. Direct CLK/CMD/DAT0 remains an explicit shortcut for the missing D550/AMA path; no electrical timing is verified. Connectors are not chips. |
| X133, A-11 | Display connector driven by the `LCD(9:0)` group; keypad/rocker lines are on GPIO/GENIO (A-11/A-13). | The board instantiates `ngage_lcd_display.v` with a provisional transaction-level controller and framebuffer. `ngage_dma_channels.v` owns DMA registers/IRQs and delegates eligible SDRAM transfers to `ngage_lcd_stream.v`; all paths use the ordered LCD queue/cursor. `ngage_lcd_dma.v` remains a legacy comparison path. `ngage_keypad.v` uses the existing experimental GPIO matrix. LCD electrical timing, display orientation and physical input behavior remain unverified. |

The sheet also contains power regulators, protection, switches, amplifiers,
filters and clocks. They are not all independent digital devices requiring an
FPGA behavioral model. Add a component module when its observable behavior is
needed, preserving its physical identity and known signals.

## Current architectural boundary

`ngage_board.v` now composes separate UPP (including CPU in the MiSTer build), UEM and audio-DSP model
modules. The radio component boundaries are present but deliberately inactive.
The main-flash controllers (including three separate logical die-state instances)
remain outside `ngage_board` in `ngage_mister.v`; UEM/DSP connections are
transaction-level shims. This is
an incremental separation, **not yet a complete pin-accurate phone board**.

Next: bring the individual main-flash and RAM-chip ownership under the board hierarchy without
changing bus semantics; derive real UPP-to-UEM serial CBUS timing and UPP-to-DSP
AMA signaling before replacing either shim; connect LRB-2, Mjoelner, SIM, LCD
and controls only when their interfaces and behavior have evidence. Keep the
original firmware, C images, and all paired billion-cycle checkpoints intact.
Any change to Verilated hierarchy invalidates old CPU snapshots: use a new
simulator/checkpoint lineage and never overwrite existing ones.
