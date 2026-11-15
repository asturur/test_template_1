# MiSTer RTC integration contract — 2026-11-14

Official developer reference:
https://mister-devel.github.io/MkDocs_MiSTer/developer/hps_io/#rtc
Hardware-board reference:
https://mister-devel.github.io/MkDocs_MiSTer/advanced/rtc/

MiSTer already supplies the source of absolute time: HPS receives time from
its optional I2C RTC board, or network time without that board. Core HDL uses
hps_io outputs, rather than adding an I2C master for the physical RTC.
The documented contract sends time at core start; the core must continue
counting after that. Do not assume a new sample every second.

## Existing local transport

sys/hps_io.sv exposes RTC[64:0] and TIMESTAMP[32:0]. RTC has BCD seconds7:0,
minutes15:8, hours23:16, day31:24, month39:32, year47:40 and weekday55:48.
TIMESTAMP[31:0] is seconds since1970-01-01. The local implementation toggles
RTC[64] at the end of command22 and TIMESTAMP[32] after command24, so consume
complete updates on those toggles, not partially arriving words. These outputs
are in clk_sys; read them in that domain or use an explicit CDC handoff.
Before the2026-11-15 implementation, Template.sv connected neither output.

## Original integration requirements (2026-11-14)

The missing part is our UEM-facing clock backend, not the MiSTer physical RTC.
Feed the HPS time snapshot into a small time-of-day/day counter, run from the
actual78MHz clk_sys parameter (also support104MHz without editing the PLL),
and expose native UEM CBUS register semantics. Ordinary phone reset should not
discard an already valid clock sample, since HPS need not resend on warm reset.
Handle a later host update coherently; do not reinterpret unchanged snapshot
fields as a continuously running input. Avoid multiple wide epoch dividers in
combinational logic; only small counters/field conversion are needed for time
of day. Native day/base-date/calibration/PMM behavior must be recovered from
our original NOS before claiming the time/date prompt fixed. Donor full-date
HLE register0C1F0100 is not a physical UEM register and is not a solution for
native unmodified NOS. Preserve native guest time-setting behavior and define
whether/when host resynchronization can override guest changes.

Tests for implementation: staged HPS words and final toggle; no sample before
valid; second/minute/hour/day rollover;78/104MHz divider settings; phone-reset
retention; late host update; native CBUS read/write aliases; valid/lost-power
and saved PMM base-date behavior. Final board test uses original firmware,
autosave and a core reload, verifying correct date/time and no repeat prompt.
No RTL, clock constraints, firmware or board settings changed by this doc check.

## Implemented Unix-time backend — 2026-11-15

`Template.sv` now connects `hps_io.TIMESTAMP` to D190 through
`ngage_mister` → `ngage_board` → `ngage_uem`. `ngage_uem_clock`, in
`rtl/ngage_cbus_uem.v`, consumes the completed update toggle in the same clock
domain. No physical I2C master or optional RTC board is required: MiSTer's Unix
time is sufficient. Unix seconds are interpreted as UTC; the firmware's own
locale/timezone handling remains separate.

The adapter converts a sample serially, in at most 116 clocks, rather than using
wide combinational epoch dividers. It publishes binary second/minute/hour
counters together, then advances them at exactly `SYS_CLK_HZ` clocks per second.
The production PLL remains **78 MHz**, with **104 MHz** still the timing goal.
It adds no CPU handshake/stall, memory access, RAM or DSP multiplier. Physical
ALM cost and TimeQuest closure require the next Quartus build.

Native UEM read aliases in configuration7 are31/32/33 for second/minute/hour,
and21 for the8-bit day counter. Watchdog/vibrator writes to31–33 do not overwrite
clock reads. Guest writes to21 reset/set the day counter. The unmodified ecust
constructor reads calibration register24: zero means unset; a valid HPS clock
supplies a nonzero model default1 until an explicit guest calibration write.
This is an identified software acceptance condition, not measured UEM crystal
calibration. Without an HPS update, calibration remains unset. Phone reset/CPU
Hold does not discard or pause the clock; a new FPGA configuration starts a new
clock domain. A later complete host timestamp resynchronizes time and applies
the host day difference to the firmware's day counter. Guest day writes win if
simultaneous. Host resynchronization deliberately takes precedence over any
software offset in the physical time-of-day counters; OS timezone offsets are
outside this block.

### Native date storage and verification boundary

The physical interface exposes an8-bit elapsed-day counter, **not a full calendar**.
Original ecust builds a full date from its PMM calendar base plus this counter.
At FPGA configuration the counter starts at zero; ordinary phone resets retain
it. Consequently, this implementation does **not** reconstruct days spent with
the FPGA unloaded, repair a stale/empty PMM calendar base, or force a2003 PMM date
to2026. It intentionally does not add the donor's invented full-date MMIO register
or rewrite PMM/firmware. Correct absolute calendar restoration across core loads
is still an open integration issue. A valid counter sample alone is not proof
that Startup will omit every date/time prompt.

Qualified offline:

- 162 fixed/random Unix samples, including0, midnight, leap-day boundaries and
 `0xffffffff`, match Python arithmetic; partial data without a toggle is ignored.
- Native CBUS aliases, separate write meanings, calibration writes, phone-reset
 retention, guest day reset, midnight255/wrap and host resync pass.
- Actual78,000,000 and104,000,000-clock intervals each advance exactly one second.
- The original ROM's `5034F5F0` calibration reader, `5034F374` time/coherence loop,
 original CBUS/HAL and `5034E104..134` constructor validity decision execute on
 current CPU RTL. Four cases pass: timestamp absent/present × bus wait0/3.
 Supplied12:34:56 is read exactly; valid state is0 without a sample and1 with it.
 No original instruction is changed; allocation/full NOS boot is outside this
 focused test.
- Full top elaboration passes with the DDR debugger both removed and enabled.

Commands: `tests/phone/uem_clock/run.sh` and `run-rate.sh` inside the existing
`jotego/simulator:arm64` image; `run-native.sh` on the host (it invokes that image).
Evidence: [rtc-unix-20261115.json](evidence/rtc-unix-20261115.json).
Hardware verification is pending while the user runs SPMark04. On the next
requested deployment, inspect native time, date and Startup prompts without
manual confirmations or functional RAM patches, then reset/reload with autosave
and check persisted PMM date separately. Do not disturb the active benchmark.
