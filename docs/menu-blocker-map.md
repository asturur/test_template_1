# Menu bring-up: confirmed waits, deaths and remaining native work

Use this map before repeating the November12 investigation. Detailed traces,
receipts and qualified experiments remain in
[menu-bringup-2026-11-12.md](menu-bringup-2026-11-12.md) and
`scratch/menu-bringup-20261112/`. A kernel NULL/NOS idle PC does not identify
the blocked process; zero kernel panic_report does not exclude a thread panic.

| Stage | Confirmed observation | Meaning and next check |
| --- | --- | --- |
| Phone foreground death | ViewSrv reason11 targets `Phone[100058b3]0003::Phone`, proved by native FullName | View activation timeout killed Phone's main thread; shared panic-helper PC alone was insufficient |
| Phone pending request | Context72bytes: PC5032752C, LR503B2484, r5 points to pending status, request count0 | User::WaitForRequest; later scoped trace identifies synchronous IPC24(hex), RFile::Flush |
| File operation | RFile::Flush return503DF597; caller508B7E85 in EStor persistent-file-buffer synchronization | A real flush completion wait, not proof of a synchronous SIM wait or generic CPU-speed cause; initialized C alone did not fix it |
| Separate DSY panic | USER21 after failed TDesC8::AtC; descriptor caller50FC9A7B, index25,12-byte frame | Nokia.dsy50FC91C4/50FC9A70 reads byte25 despite an error reply with only12 total bytes |
| Native PMM request/reply | resource23/message04 asks group50/record1,offset0,length2; reply23/05/status11 with body00051100 | Original cPERM_Server intentionally returns storage error; DSY lacks a corresponding short/error check. This is not an invented RAM-pointer alias |
| Matched PMM comparison | Native69-record base d3559287... still panics; adding only50/1 payload0400 (77e0e240...) removes USER21 in matched capture | Isolates missing setting as the experimental difference. Byte0 is a synthetic DOS policy, not a recovered factory default. Do not ship an invented minimal PMM catalog: it failed native boot |
| Logical SIM readiness | Original SIM_Server state5/6 takes non-serving fallback; donor-ready getters differ. V2 query-triggered native SIM_IND8/no-PIN plus coherent getters advances startup | Physical absent card is not a ready logical SIM. Keep original NOS allocation, dispatch and queues; successful instrumentation experiment is not an implemented HDL fix |
| Startup rejection | Device startup failed/contact retailer; DOS event1 becomes2. Async original result array80024388 reports LPRF_IF15/1, CURRENT_CONS02/1, RF_CHIP_ID1E/0D, ADSP36/1 | RF/ADSP have fatal severity0C; BT/current severity0A. Passing first list response does not prove the later RUN tests pass |
| Menu success control | Excluding only RF/ADSP automatic applicability, ready-SIM service, valid PMM and BT experiment reaches Phone/Menu/Contacts | A combined software comparison, not a production fix. Original2s/20s deadlines also work with initialized images; no perpetual16s/160s extension is justified |

## Current original-firmware comparison

b656156/seed44 passes the prior UART drain and storage-reset point, reaches
SysAp, N-Gage logo and clock screensaver. Menu wakes the clock back to the logo
without CPU reset. Current live PMM SHA256 is
`c29cf6ddaf4b46f4a52fc67129731d1e1d254b9bd6923325f2a850f092a62057`,
**identical to yesterday's V10 failing PMM**, with67 decoded records and no
group50/record1. The new observation-only trace on this build confirms the
same USER21 descriptor failure and the same ViewSrv11 Phone death. Phone's
captured r7=20(hex) is a positional Write in the wait-logging run; r7=24 is
a Flush in the lighter exit-only control. Both have PC5032752C/LR503B2484
and zero request count. The lighter control omits the WaitForRequest hook,
so dense file-wait printing is not required to reproduce Phone's timeout.

There are successive Write/Flush calls in the detailed trace: do not label
this a permanently lost interrupt from a single pending request. The wait
operation and EStor caller are known; the exact file and storage completion
latency remain to be established. DSY's hosting thread name is not captured;
its failing component/caller is identified, whereas Phone's target FullName
is positively captured. No replacement boot recorder or new FPGA build was
needed to recover these observations.

Native RF version handling and internal MDI exist in the current HDL, and UART
TX can now drain. External D550 protocol/startup replies and SIM-ready still
need production completion. Do not copy the old software behavior changes into
an observer run or declare all four self-test failures fixed.

## Observation-only software tracing

Use the existing audited exit/wait payload c76a4d88... (2824bytes), whose actual
ZAP ARM/Thumb/ABI fixtures pass at wait0/3. Hooks: User::Exit503B4718,
User::Panic503B46E0, Kill503B7FB8, Terminate503B7FE4, RThread::Panic503B8010,
AtC bounds failure503A2B48 and scoped slow WaitForRequest503B247C. It captures
caller/arguments, known ViewSrv target/context, descriptor message and file waits.
RFile::Flush's actual Thumb entry is503DF58C;503DF597 is its odd return address.

Standalone tracing changes covered code. The old BT bundle disabled the first
boot-MD5 descriptor; **do not silently bring that behavior change back**. Compute
the CPU-view MD5 after applying only tracer hooks, descrambling A000..2B3000
with the existing rules. Verify original digest2c09c86f... first, then update only
the diagnostic expected digest words8F20..8F2C. Original range/check code remains.
With slow-wait logging, the diagnostic MD5 is919b5b7e63e1283b8d61a91aed2df2d4;
exit-only uses73a4140a3792d123420c7c22769ddbe5. First attempt
without digest accounting hit the checksum path; that is an instrumentation
setup failure, not a new phone/HDL blocker.

Apply only to fresh Hold: zero active CPU clocks, ACKs/errors and no prior hook
fetches; original full ROM hash and every old word must match. An observed
single reset-bookkeeping fetch at VA0 with zero clocks/ACKs is distinct from a
started CPU. Never patch a running/cached phone. Current scripts and receipts
are in `scratch/menu-native-retrace-20261113/`. Card firmware/images remain
unchanged. User's original16-byte settings are backed up; temporary Hold clears
bit16 and original Run is restored before the diagnostic boot. No new HDL
recorder is selected; its tested experiment is preserved under scratch only.

## Reproduce the standalone observer

```sh
python3 tools/build_exit_trace.py
python3 tools/prepare_native_observer.py --output scratch/native-observer
# Add --slow-wait only when investigating individual file waits.
# Generated observer.py defaults to read-only preflight.
```

Use the mister-control skill for reload/input/capture. Save the exact16-byte
`/media/fat/config/ngage1.CFG` before temporarily selecting Hold (bit16); save
bit21 remains Off. Reload, allow media loading, then run generated observer.py
on MiSTer with `python3 - --apply` through SSH stdin. Require successful JSON
`applied:true` and the expected full-image hash before starting. Restore the
original settings bytes. Current b656156 CONF_STR CPU mode is selectable row6
from the top; F12, six Down, `=` (Main plus), F12 starts Run. Confirm advancing
CPU clocks. This row count is profile-specific, not a general navigation rule.

The host generator only prepares files; no automatic connection/write occurs.
It requires the pinned2824-byte payload and exact original service backing,
verifies every original word, keeps checksum bounds/check code, and emits a
read-only-by-default script. Apply requires two advancing fresh-Hold snapshots
with saved Run disabled; warm Hold, previous bus activity, errors, reset, save
or incomplete restore are rejected. After apply, every word and full ROM hash
are verified. Reload restores the original ROM. No card images are patched.

Actual ZAP ARM/Thumb/argument/register/flags/SP fixtures pass at waits0/3.
The host-only DSY Unicorn test hit SIGILL on this Mac and is not counted as
passing. `tests/tools/test_prepare_native_observer.py` covers cold versus warm
Hold, auto-release, restore and save/error write guards.

[Current capture evidence](evidence/menu-native-retrace-2026-11-13.json); bounded
raw/text logs and apply receipts: `scratch/menu-native-retrace-20261113/`.

The completed240-second lighter control contains642 snapshots, no reset, no
queue fault and no text drops. Phone11/Flush recurs; USER21 is not captured in
that lighter run. The detailed run captures USER21, so do not claim every
instrumentation schedule produces an identical failure sequence. Original
RBF was reloaded after both captures to remove volatile instrumentation.

Rollback readback verifies original ROM88fd596a..., original16-byte saved Run
settings and unchanged boot0/boot1 VHD hashes. Automatic CPU clocks advance
with autosave Off. No diagnostic hooks remain on the board. The mister-control
skill now caches this standalone observer/checksum/settings procedure.
