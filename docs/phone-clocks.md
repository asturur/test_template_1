## Current clock policy — 2026-11-11

The actual PLL and production SYS_CLK_HZ remain78 MHz. Design RTL stage depth
and fanout toward104 MHz (9.615 ns) and keep104 MHz logical/SDRAM tests, but do
not change the operating PLL without explicit user authorization. This policy
was clarified during [LCD/DMA timing recovery](lcd-dma-timing-recovery.md).

# Phone clocks and slower interfaces

## Requested26MHz/64Hz spin (2026-11-09)

Implemented parameterized general-timer enables, divider3 at78MHz and4 at104MHz,
with CPU-speed register/ACK handling. Template selects this plus experimental
NOS_TICK_HZ64. A NOS tick advances the counter; firmware still controls compare
interrupts, so not every tick must raise an IRQ. Calibration counter stays~32kHz;
ADSP's staged tick is tied to NOS and is also slowed. Generic module defaults
retain legacy timing for regression fixtures. The older cycle-based sections
below describe prior builds; NOS64 remains an explicitly requested hypothesis.

A separate cold run passed50.35M cycles with12known fetch faults and zero data
faults, saved paired state, and continues toward12B as timing26-nos64-resume-12b.
This is still early startup, not a new logo/UI claim. The original12B run is
untouched. See latest status and
[evidence](evidence/timing26-nos64-experiment-2026-11-09.json) for lineage/tests.
Runner accepts --timer-clock 26mhz and --nos-tick-hz 64; changing either across a
checkpoint is rejected. New timer divider state required this cold lineage.


## 2026-11-09: post-logo timer/IRQ audit

**Two different counters must stay distinct.** The1kHz NOS compare counter at
0C150114/118 is not the eight general timers at0C120A00+20*k, and neither is
Nortido's host monitor1ms scheduling quantum.

Nokia NEM-4 baseband pages7-9/10 document26MHz reference and32.768kHz sleep
clocks, but provide no register-level frequency, prescaler or W1C specification
for the NOS comparator. Searches of the available local service text and public
primary Nokia material found no1kHz confirmation. It remains an assumption.
Firmware514AE058 reads16-bit current count at58150116 and programs current+
requested_delta at58150118; this establishes software deadline ownership, not Hz.

Nortido latest HEAD4b8480148db15d432e2abf6a6956832c91d9cf55 was checked via gh.
Its rtl/ngage_soc.sv:507–555 decrements the eight general timers on26MHz enable,
reloads periodically and latches an expired flag until the guest writes+08.
Its hps/mon/irq.c:259 explicitly identifies guest timer0 ACK as64Hz/15.625ms.
Stock firmware reload406250 and time constant15625 support that interpretation:
26000000/406250=64. Current ngage_timers decrements its periodic timer once per
CPU clock, so the same reload produces192Hz at78MHz (256Hz at104MHz). This is a
concrete mismatch against the independent reference and stock timing arithmetic;
the service document alone does not prove this register's clock source.

Nortido hps/guest/nos_glue.S replaces original NOS driver export pointers with
nos_attach/nos_ctor and its own channel vtable. Thus its working UI does not
validate our original NOS comparator frequency or IRQ25 timer path. Do not infer
1kHz correctness from its unrelated host1ms quantum or copy firmware patches.
Pinned files are saved under scratch/timer-irq-audit/nortido-4b848014/.

### Measured occupancy and acknowledge behavior

Read-only isolated replay of permanent2B→2.05B,50M clocks at nominal78MHz:

| Observed context | Clocks | Window share |
|---|---:|---:|
|CPSR IRQ mode|8,313,929|16.63%|
|Inside NOS deferred callback, excluding IRQ mode|28,266,186|56.53%|
|Outside those windows|13,419,885|26.84%|
|Mailbox pump alone, subset of callback|6,045,158|12.09%|

IRQ occupancy is actual CPSR mode12. Callback windows bracket514A18D4 entry
and its saved return PC; non-IRQ thread preemptions are not independently
accounted. The bounded instruction trace shows no user-mode preemption in its
first complete callback. Treat56.53% as an approximate callback-window share,
not a formal per-thread CPU profile. Callbacks execute genuine NOS startup work
as well as repeated service scans. These numbers support heavy IRQ-driven load,
not proof that all73.16% is wasted or that reducing interrupts fixes the UI.

Timer0 pending rises123times, consistent with192Hz over0.641nominal seconds.
NOS counter advances641ticks. NOS bit7 has340assertions and339clears; one is
pending at the end inside an IRQ handler. This shows repeated acknowledged events,
not a permanently stuck source. Source classification at IRQ-mode entry observes
107timer-only,333NOS-only,1both and3other; pending-at-entry is not a complete
interrupt-handler-source trace. Original12B run and firmware remain untouched;
50M trace/PC totals match the earlier observer and no new faults occur.

Existing NOS wrap/compare/W1C/same-edge-event, staged timer and ICU mask/priority
checks pass in Jotego Docker. These establish current implementation consistency,
not physical-phone correctness. Audit also identifies ICU differences from
Nortido: our raw IRQ status exposes only DMA bit7, our priority encoder is a
selected-source subset, timer0 reload can implicitly mask IRQ0, and masking
selected sources also requests device acknowledgment. Keep those as explicit
staged hypotheses until firmware access traces justify replacing them.

Next implementation experiment: give the general periodic timer a26MHz clock
enable (divide3 at78MHz,divide4 at104MHz), keep bus accesses at CPU speed, then
verify64Hz plus expiry/ACK coincidence and compare boot/CPU budgets. Audit the
bootstrap BOOT_DELAY/UNIT60_DELAY hypotheses separately rather than blindly
rescaling every legacy counter. Leave the NOS1kHz rate unchanged pending stronger
evidence. New divider state requires a cold run or an explicitly reviewed state
migration; never silently load the frozen checkpoint into changed HDL.

Evidence: [compact audit](evidence/timer-irq-audit-2026-11-09.json),
scratch/timer-irq-audit/{duty_profiler.cpp,duty-50m.log,trace-50m.log,
directed-checks.log,nos-time-code.txt}. No HDL change, commit, push or build.


## Selected hardware bring-up clock:78MHz (2026-11-09)

The user selected78MHz after the104MHz timing campaign. `Template.sv` sets
SYS_CLK_HZ=78000000 and the actual PLL parameters request78MHz from50MHz.
The second output is still unused, with its nominal−90° phase updated to−3205ps.
SDRAM uses inverted DDIO from clk_sys, HF=1 and both falling capture/rising transfer
registers. No timing exception is added; TimeQuest derives the new PLL clocks.
This underclock is a bring-up setting, not a claim about Nokia's clock programming
or verified FPGA timing closure. The earlier52MHz suggestion was not implemented.

SYS_CLK_HZ propagates through MiSTer→board→UPP/peripherals and UEM. Module defaults
remain104MHz for historical tests/checkpoint lineage. Known wall-time rates are:

| Model/interface |104MHz defaults|78MHz hardware|
|---|---:|---:|
|LCD scan pixel enable (6.5MHz)|/16|/12|
|Diagnostic SIM service enable (3.25MHz)|/32|/24|
|NOS millisecond tick|104000clocks|78000clocks|
|UPP/NOS approximate32.768kHz counter|/3174|/2380|
|UEM RTC second|104000000clocks|78000000clocks|
|UEM model alarm delay/check interval|7995392/65536clocks|5996544/49152clocks|
|Save/diagnostic SD timeout (1second)|104000000clocks|78000000clocks|
|SDRAM refresh trigger|6800clocks|5100clocks|

The fast-counter divisor rounds to the nearest system clock: nominal rates are
32766.226Hz and32773.109Hz respectively, not exact32.768kHz. Refresh retains its
65.3846us trigger interval; controller refresh-command count remains unchanged.
HF1 timing and11000-clock initialization are retained, giving approximately141us
initial wait at78MHz (longer than the previous105.8us). Full scrub/reset and
transaction handshakes remain cycle-based. Audio is still tied to zero; activity
LED blink timing is cosmetic and remains cycle-derived. No new clock domain.

**Unresolved timer models stay cycle-based.** `ngage_timers` boot/unit/periodic
counters retain all existing register and decrement semantics. Their wall-time
periods increase by4/3 when CPU frequency changes: e.g.406250ticks are5.2083ms at
78MHz instead of3.90625ms at104MHz. This deliberately does not introduce the
unverified26MHz timer-enable hypothesis. Polling delays and bus transaction cycles
also scale with CPU progress; they are not RTC seconds.

Dual-rate tests verify propagation, pixel/SIM enables, NOS/fcnt periods, RTC/alarm
parameters, refresh cadence and unchanged timer constants. Native176×208 scanout
passes at both divisors. Four-state Micron tests use the actual78MHz period and
all0/.25/.5/1ns clock-pin delays, preserving the104MHz wrong-edge negative control.
Source preflight and stubbed top lint pass. Fresh boot results and physical timing
limits are in status; no old CPU checkpoint is restored into this clock lineage.
Reproduce: `tests/phone/clock_rates/run.sh` and `tests/phone/sdram/run-ddio.sh` inside
the existing simulator image; `PHONE_SYS_CLK_HZ=78000000 sh tests/phone/hardware_boot/run-real-sdram.sh`.

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

## Implemented SIM enable follow-up (2026-11-07)

The diagnostic card is now serviced on a divide-by-32 enable at the unchanged
104 MHz system clock, nominally 3.25 MHz. Events are captured at system speed,
then cross a CEN-only work register before processing. SIMIF ready stalls the
next access until pending work finishes, including FIFO pops. This models a
slower internal transaction service budget; SIM bit edges, baud-rate divisors
and physical UPP/UEM signaling remain unimplemented. Do not equate one byte
event per service opportunity with a real serial byte duration. The normal
no-ATR selection remains unchanged. No general MMIO or RTC/timer-rate change.

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
