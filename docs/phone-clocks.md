# Phone clocks and slower interfaces

## Evidence and limits (2026-11-07)

104 MHz is the current **FPGA CPU/SDRAM target**, not a blanket frequency for
all phone chips, buses or peripherals. It is not yet proof of the phone's
original SDRAM frequency either.

The local ARM920T technical reference, `docs/ARM920T_TRM1_S.pdf` (ARM DDI
0151C), sections 5.1–5.4 and table 2-11, explicitly separates **BCLK (AMBA
bus)** from **FCLK (fast CPU)**. CP15 control bits 31:30 (`iA:nF`) select
FastBus (00), synchronous (01) or asynchronous (11) operation; 10 is reserved.
FastBus is the reset mode. Synchronous mode permits faster FCLK at an integer
multiple of BCLK, with phase requirements. This establishes that a slower
external bus is architecturally supported, **not the frequency or mode used by
this phone**. Our ZAP integration currently exposes one functional CPU clock;
it does not reproduce that physical clock-switching circuit. Extracted text
for follow-up: `scratch/timing-closure/clock-research/arm920t.txt`.

Nokia's NEM-4 service documentation, Issue 1, September 2003, section 6(a),
pages 19 and 27–29, describes:

| Circuit | Documented clock information |
| --- | --- |
| Main reference | 26 MHz oscillator B601 through Mjoelner to UPP_WD2 |
| Sleep | UEM supplies 32.768 kHz to UPP, Bluetooth and Zocus |
| Audio/DSP | Separate 12 MHz oscillator feeding ADSP/AIC; this is a reference, not a verified DSP instruction rate |
| SIM | UPP clock through UEM; approximately 1.083 or 3.25 MHz; serial baud rate depends on a further divider |
| Flash, SDRAM, CBUS, DBUS, MMC | Shown as distinct UPP-generated clocks; rates/dividers remain unverified |

Primary Nokia document mirrors:
[troubleshooting PDF](https://electronicsandbooks.com/edt/manual/Hardware/N/Nokia/Phone/NOKIA%20N-GAGE%20NEM-4/NOKIA%20N-GAGE%20NEM-4%206.pdf),
[indexed manual](https://www.manualslib.com/manual/2171687/Nokia-Nem-4-Series.html).
The search index exposes these sections; direct PDF download/page retrieval
failed in this session. A complete local copy is still needed before auditing
the remaining clock descriptions/waveforms. Local schematics are
`docs/08-nem4-schematics.pdf` and `docs/ser-no-n-gage-schematics.pdf`.

The Nortido reference uses a **26 MHz timer enable** in
`scratch/reference-nortido-ngage/rtl/ngage_soc.sv:507–530` (pinned reference in
`nortido-hybrid-reference.md`). That is another implementation's choice, not
phone measurements. Our `ngage_timers.v` currently decrements model counters
on every system clock; the UPP free counter uses a fixed divide-by-3174,
and `ngage_cbus_uem.v` assumes 104,000,000 clocks per second. Those are distinct
timebase assumptions to audit, not evidence all peripherals run at 104 MHz.

Firmware reload `0x632ea` is 406,250: at 26 MHz this is 15.625 ms; at 104 MHz,
3.90625 ms. This factor-of-four difference is a useful lead. It does not by
itself establish the real timer clock or OS tick rate. Do not silently change
the timer model or reuse old checkpoints with a different timebase.

## Implementation follow-up

1. Obtain the complete service clock chapters and check memory/LCD/CBUS/MMC
   waveforms and chip speed grades. Separate oscillator references, internal
   clocks, external pin clocks, serial baud rates and transaction wait states.
2. Audit the unmodified firmware's writes to UPP clock, memory-controller and
   peripheral divisor registers **and CP15 register 1 bits 31:30** through
   reset/PLL setup/normal boot. Current `cfg_clocks` logic is an idealized
   status/latch model; it does not implement the real clock tree. Reconcile
   observed values against documentation before decoding new behavior.
3. Make each device's elapsed-time source explicit and verify real-time timer,
   SIM, CBUS, MMC and display behavior independently of CPU frequency. The
   synthetic SIM presently returns a transaction-level response immediately;
   that is not physical SIM byte timing.
4. Prefer clock enables for related slower device activity where suitable,
   with a **registered request/response bridge** that holds the CPU bus until
   completion and commits side effects exactly once. If a separate slow PLL
   domain is needed, provide proper bundled-data/handshake crossings and reset
   handling. Preserve IRQ/fault delivery and locked SWP semantics.
5. A slow pin protocol does not make today's combinational address -> decode
   -> ACK -> next request path slower-clocked. A clock enable alone does not
   grant a whole path multiple cycles. Keep 104 MHz setup checks until actual
   registered boundaries or justified domain constraints exist. No clock,
   enable, exception or firmware behavior changed in this evidence pass.

Next timing build still measures structural optimization at the existing
104 MHz target. Introducing a verified slower peripheral bridge is separate
work requiring transaction/order and timebase regressions plus fresh firmware
simulation lineage. See `timing-closure.md` for fitted results.
