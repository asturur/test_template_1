# Phone clocks and slower interfaces

## Verified Nokia documentation (2026-11-07)

Downloaded the **NEM-4** service chapters, Issue 2, September 2004. This is the
original phone, not the QD/RH-47. The baseband chapter resolves the previously
unknown memory rates:

| Circuit | Nokia specification | Page |
| --- | --- | --- |
| MCU startup | 26 MHz after reset | 7-9 |
| MCU normal ceiling | Up to 104 MHz | 7-10 |
| SDRAM interface | 104 MHz | 7-7 |
| Main flash interface | 104/3 MHz, approximately 34.667 MHz | 7-7 |
| MMC interface | 8.66 MHz | 7-13 |
| SIM | 3.25 MHz, followed by a baud-rate divider | 7-13 |
| Main reference / Bluetooth | 26 MHz | 7-9 |
| Sleep | 32.768 kHz from UEM | 7-9 |
| ADSP/audio reference | Separate external 12 MHz oscillator | 7-9 |
| Internal UPP DSP ceiling | 117 MHz; separate from the external audio ADSP | 7-10 |

UPP has three independently controlled DPLLs: MCU, DSP and accessory interfaces.
Their outputs feed interfaces directly or through dividers. Serial CBUS/DBUS,
LCD timing, internal bus frequency, divider register encodings and timer source
are **not established** by these pages.

Source: Nokia **7 - Baseband**, pages 7-7, 7-9/10 and 7-13,
[document page](https://www.jabse.com/L05PS0lBL01vYmlsZSBQaG9uZS9OLUdhZ2UvMDctbmVtLTQtYmFzZWJhbmQucGRm).
Local PDF and extracted text:
`scratch/timing-closure/clock-research/07-nem-4-baseband.{pdf,txt}`.
PDF SHA-256: `15f80b3406b0a063ffe897a3b49f476dcc13f7112fe09668b4f0800869fbafaa`.
Relevant pages were rendered and visually checked, including the clock diagram.
The text contains a separate SDRAM capacity inconsistency (128 Mbit versus
4M x 16); the clock statement does not resolve chip density or organization.

Also downloaded Nokia **6 - Troubleshooting Instructions**, same issue:
[document page](https://www.jabse.com/L05PS0lBL01vYmlsZSBQaG9uZS9OLUdhZ2UvMDYtbmVtLTQtdHJvdWJsZXNob290aW5nLnBkZg),
local `scratch/timing-closure/clock-research/06-nem-4-troubleshooting.{pdf,txt}`.
Page 6-133 shows CBUS boot traffic and identifies channels: CH1 enable, CH2
data, CH3 clock. At the displayed 50 us/div scale CH3 is an unresolved dense
trace. **The displayed CH1 frequency is not the serial CBUS bit clock.** This
capture cannot establish CBUS frequency; a clearer/zoomed capture is needed.
Older Issue 1 troubleshooting pages additionally mention a ~1.083 MHz SIM mode.
Do not substitute the QD document's 40 MHz flash specification for NEM-4's /3.

## CPU versus bus clock capability

The local ARM920T reference, `docs/ARM920T_TRM1_S.pdf` (ARM DDI 0151C),
sections 5.1–5.4/table 2-11, separates BCLK (AMBA bus) and FCLK (fast CPU).
CP15 register 1 bits 31:30, iA:nF, select FastBus 00, synchronous 01 or
asynchronous 11; 10 is reserved. FastBus is the reset mode. This describes
ARM920T capability, not a Nokia-selected rate or verified phone clock mode.
ZAP currently uses one functional clock and does not implement this physical
clock-switching circuit. Decelerating all MMIO to 26 MHz is therefore still an
implementation experiment, not a documented phone requirement.

## Fresh unmodified-firmware probe

Reproduce from the repository root:

```sh
python3 tools/probe_phone_clocks.py
```

This uses the existing `jotego/simulator:arm64` image, adds only read-only taps
to a generated copy of the maintained hardware-boot bench, and cold-runs 5M
cycles. Generated source/runner/compact log stay under
`scratch/timing-closure/clock-research/`; binary/build log stay under
`build/sim/unit-clock-audit/`. It edits neither firmware nor maintained RTL and
loads no CPU checkpoint. It is a short bounded run, not a resumed logo run.

Recorded source **4040395**, stock assembled service firmware, no SIM, existing
ideal clock/peripheral model and backing memories. Evidence with image/PDF
hashes, RTL aggregate hash and every captured transition/write:
`docs/evidence/phone-clock-audit-2026-11-07.json`.

- 20 CP15 control transitions, values 00000078, 0000127A, 0000027A; bits
  31:30 remain **00** throughout this bounded run. This does not prove the
  physical phone clock mode or behavior after the 5M stopping point.
- Accepted early writes include `0c120004=0c`, then `0c120008=1,2`, later
  `0c149000=2210` followed by `0c120004=3`; and `0c120018=180f8000`,
  `0c120014=08018000`, `0c120038=0c`, `0c120034=8,3`. Their frequency/divider
  field meanings remain unknown. The current models echo/status-handshake
  these values; they do not change the simulation clock.
- Smoke result remains PC **00006178**, 377,714 accepted bus transactions,
  18 known speculative fetch faults, **zero data faults**, no LCD yet.

Static disassembly of the same stock core shows a routine at ROM VA
`50348e38` loading literal **15625** and returning it in r0; literal is at
`50348e40`. Its function identity is not yet established; its pointer appears in the
variant dispatch table at `5034a9cc`. Nearby kernel time
arithmetic uses the same constant at `50323cc4` and `50323dcc`. Timer reload
**406250** (0x632ea) is at `5032270c`, passed by code at `503226ec/f0` to the
timer routine at `503249d0`; another reload use is at `503227c8`.
Reproducible disassemblies are in the clock-research scratch directory.
This is firmware evidence supporting a 15.625 ms / 64 Hz hypothesis, not proof
of the timer source by itself.

## Timebase audit and concrete next work

1. **Confirm the timer frequency first.** Nortido's independent reference
   uses a 26 MHz timer enable and treats the guest tick as 64 Hz
   (`rtl/ngage_soc.sv:507–530`, `hps/mon/irq.c:259`). Our reload 406250 lasts
   15.625 ms at 26 MHz but only 3.90625 ms at 104 MHz. Identify the ROM routine
   returning 15625 and its HAL/tick callers, then compare timer IRQ counts and
   guest-reported time over one modeled RTC second. If confirmed, implement a
   separate 26 MHz timer enable (divide by four from 104), preserving register
   writes every host clock. Do not divide the entire peripheral model blindly.
2. **Separate elapsed time from CPU progress.** `ngage_timers.v` currently
   decrements model counters every system clock. UPP's free counter uses /3174
   and `ngage_cbus_uem.v` uses SECOND_TICKS=104000000. Keep actual seconds,
   32.768 kHz events, timer ticks, CPU clocks and polling delays distinct. Reset,
   compare/reload and simultaneous write/expiry need explicit regression cases.
3. **Audit real divider fields.** Follow the captured UPP clock/control writes
   and original firmware read-modify-write masks. Obtain register documentation
   or independent hardware measurements before naming bits. MCU starts at 26;
   implement a deterministic clock-enable startup model only after the PLL
   transition is identified, with fixed peripheral/RTC wall time.
4. **Model flash throughput separately from DDR.** Firmware remains in DDR as
   agreed. A 104/3 MHz physical flash bus is not a reason to slow DDR or every
   CPU transaction. Use a controller that distinguishes initial address/wait
   latency, burst halfwords and program/erase completion. Cross-check the exact
   AM29N643GT70 part's configuration against firmware before changing latency;
   the related local Am29BDS643G sheet is not proof of every installed grade.
5. **Register the MMIO transaction boundary.** Capture request/address/data/mask,
   decode from held registers, commit side effects once, then return registered
   data/ACK/error. Hold or handshake CPU requests until completion; preserve
   faults, reset cancellation and SWP lock across bubbles. A slower peripheral
   service enable may then be introduced per verified interface. Neither its
   frequency nor a wholesale 26 MHz MMIO domain is chosen yet.
6. **MMC/SIM/display:** use separate protocol enables (documented MMC/SIM rates
   above), honor firmware divisor/initialization changes when decoded, and keep
   display scanout distinct from LCD transfer timing. Synthetic SIM immediate
   packet replies and transaction-level LCD writes are not pin timing models.
   CBUS/DBUS/LCD rates still require better documentation/measurements.
7. **Timing remains honest.** Clock enables alone do not grant multicycle paths.
   Related slow clocks need defined phase/crossing constraints; independent
   domains need real CDC handshakes. Keep 104 MHz CPU/SDRAM constraints until
   the RTL implements the boundaries. No exceptions, PLL settings, timebases,
   firmware or production HDL changed in this investigation. A timebase change
   requires a fresh simulation/checkpoint lineage and separate board validation.
