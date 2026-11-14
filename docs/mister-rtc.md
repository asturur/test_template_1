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
Template.sv currently connects neither output.

## Remaining N-Gage integration (unimplemented)

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
