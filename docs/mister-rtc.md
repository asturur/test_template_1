# MiSTer RTC integration contract — 2026-11-14

## 2026-11-16: User reports Unix-time boot without setup prompts

User reports the latest phone startup picked up the Unix timestamp and asked
for neither date nor time. No agent confirmation helper or key input was sent
for this reported boot. This is a successful user-observed prompt-free boot,
superseding the assumption that every startup necessarily asks. Exact loaded
RBF, save lineage and cold/warm reset type were not independently recaptured;
no new hardware access was performed. Repeated cold-boot reliability and the
cause of the difference from earlier prompted boots remain unverified. Keep
the working session intact and observe the next ordinary boot before injecting
any setup confirmations. No additional clock patch follows from this report.

## 2026-11-20: Alarm status acknowledgement

The fitted Bomberman crash image always reported UEM status `0x35` bit 3
high, including after acknowledgement. Stock ecust checks that bit before
doing its time-to-alarm calculation and requests NOS reset `0x15` during
power-off when it reads high. The local RTL now reports the latched bit and
honors its existing write-one-to-clear path. The staged boot alarm event
still uses the existing one-shot delay. [Board trace and controls](ddr-diagnostics.md#bomberman-binary-and-uem-alarm)

## 2026-11-15 follow-up: native calendar restore still rejects saved state

Read-only board inspection finds Linux UTC correctly at2026-11-15T21:23:17Z,
while the phone screensaver shows01/01/2003 10:44AM. This does not directly
observe HPS delivery or the FPGA's `rtc_valid`. No reload, key, firmware change,
save or disk write was performed. Background save isOff, with38queuedsectors.

Stable live PMM and saved boot1.vhd captures both have unique F4 candidate
records in active sector4000 for native calendar tableD4:

| Record | Live and saved value |
| --- | --- |
|0 |2003-01-01 08:55:00 |
|1 |2003-01-01 08:54:00 |
|2 |TTime(0) |

The native restore guard rejects records0and1 when unequal. The forwarding
chain is now executed and checked, correcting the old seed script's argument
order: NOS caller5159EC98 passes pointers(record2,record0,record1), but ARM
wrapper514A4D64 rotates them. ecust5034E444/5034E138 therefore receives
**(record0,record1,record2)**. Its comparison at5034E18C..1CC requires the first
two values equal and nonzero. Zero record2 is the optional third argument and
does not itself fail this guard.

Five unchanged-code Unicorn cases pass: live and saved pairs reject, an equal
nonzero pair accepts this guard, equal-zero rejects, and changing only the
third value cannot repair the mismatched pair. Rejection clears object+3C and
sets state9. The fixture models the unrelated service factory and stops before
accepted-path calendar conversion; it is not a full native boot or proof that
the captured records were the arguments consumed during this board boot.

The user authorized saving and a shutdown test. Manual Flush drains38sectors
to0, reports Saved with no slot/queue error or reset. Both synced files match
two stable live DDR reads byte for byte. Two3second Power presses wake the
screensaver but do not establish native shutdown. The user then explicitly
requests immediate reboot. Reloading the same RBF with those saved images
still asks for time (user confirmation). After startup the active calendar pair
is again08:55/08:54 with the same values, appended at new offsets. Saving alone
does not fix it. A clean native shutdown remains untested; do not confuse this
saved cold reload with that lifecycle. No replacement records were injected.

The original NEM-4 EUser TTime-to-calendar function also confirms the captured
values are2003-01-01 08:55/08:54. Its1970epoch is62168256000000000us; the legacy
seed script's numerical2000epoch is12daysearly. Historical generator output is
retained, marked superseded; it is not a current image-repair procedure.

### Current donor comparison

Donor checkout0fe531f uses `rtl/mister/rtc_wall.sv`: MiSTer BCD RTC seeds a
running clock with a full calendar and day counter. Its replacement NOS reads
an invented full-date register at0C1F0100, converts midnight to native TTime in
`nos_rtc_base`, and sends rtc.dll the same nonzero base twice, plus zero alarm.
This directly satisfies the comparison our captured PMM pair fails. With a
persisted FirstBoot.dat, later starts skip the first-boot questions; a fresh
formatted C: still asks once. See donor `docs/NOS_STANDIN.md` Clock section and
`firmware-patches/nos-stub/nos_isi.c`/`nos_stub.S`.

That calendar handoff is replacement-NOS behavior, not a native UEM interface.
Our existing Unix source is sufficient for time input, but the original NOS
still needs a coherent PMM/battery-clock lifecycle. Copying the invented date
register alone cannot supply it to unmodified NOS. The donor also avoids real
NOS startup work and uses a different CPU. No measured split of our reported
40second boot into CPU work, loading and protocol/timeouts exists yet; do not
attribute that entire delay to the clock or promise a donor-like boot time.

At the time of this capture, UEM status35 unconditionally reported alarm bit3,
and the alarm implementation used a one-shot delay rather than comparison
against the wall clock. These are established modeling limitations; their causal role in
the date prompt is unverified. The8-bit day counter also cannot reconstruct an
absolute calendar from a stale2003PMM base. The next functional correction must
follow observed native persistence/RTC behavior, not a forced-valid flag.

[Board captures and original-code controls](evidence/rtc-prompt-20261115.json).
Reproducer: `scratch/rtc-prompt-20261115/restore-oracle.py`.

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
