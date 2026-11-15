# SPMark04 JPEG encoding wait — 2026-11-15

## Hardware-confirmed cause

The user authorized a fresh traced repeat. **The JPEG test waits forever after
its input image decodes successfully beyond SPMark's10-second deadline.** The
actual compression loop has not started. No changed deadline, result or
functional firmware substitution was used.

| Event | Time after timer request | Native observation |
| --- | ---: | --- |
| Arm input open/decode timer |0s |10,000,000microseconds, callerFFF02CAC |
| Timer RunL dispatch |11.4371s |CActive::Cancel with iActive0, callerFFF02C00 |
| RunL closes timer |11.4376s |Close callerFFF02C08; no Scheduler::Stop |
| Successful decode callback |11.9841s |Cancel with iActive0, success-path callerFFF02FF4 |

No JPEG-encoder timer (FFF02DA8) is reached. There is no Scheduler::Stop after
this callback for at least14.86seconds within the same complete capture. The
same observer records60normal stops during the preceding image/scaling work.
The accepted180-second capture has247JPEG-helper events, zero reader gaps or
producer drops, generation0, unchanged13bus errors, no sticky first fault or
recorded panic, and save Off. Follow-up monitoring retains the wait.
[Exact ordering](evidence/spmark-jpeg-confirmed-ordering-20261115.json).

This confirms the original application's timeout/recovery defect under this
measured workload. It is **not a stuck JPEG instruction, missing successful
codec callback, or a new persistent bus stall** in this reproduction. It does
not prove all CPU/peripheral behavior correct or attribute decode cost to a
particular RTL block. The timer is dispatched late rather than before its
requested10seconds; slowing the phone's timers would change phone behavior.

The under10-second requirement needs about20%greater end-to-end throughput
relative to this11.984-second instrumented request, plus operating margin.
That request includes input loading, decoder/server scheduling and observer
cost; it is not a standalone JPEG throughput measurement. Next diagnosis is
to separate those costs and profile/reproduce this actual path before selecting
another CPU/cache improvement. Existing six-kernel SPMark tests do not cover
JPEG. Compression performance/results remain unqualified.

![Traced JPEG wait](evidence/spmark-jpeg-traced-wait-20261115.png)

Optimization work is paused for this blocking investigation. The user runs the
system tests and retains hardware/input control. The installed RBF file hash,
open SPMark MMC and raw capture summaries are in the [hardware evidence](evidence/spmark-jpeg-monitor-20261115.json).
Initial monitoring used no keys, reload, save or patch. The later authorized
repeat reloaded the same RBF with the same SPMark MMC and added only the observer. The user reports the latest clock-enabled build still requested
the date; that is recorded separately in TODO.md. Build-date telemetry alone
does not identify an exact source commit.

## Observed on hardware

Image rendering and scaling progress. JPEG encoding executes original
MediaServerJpeg code, then the screen remains on JPEG Encoding Test with an
empty progress bar. Subsequent samples mostly show scheduler and background
code, not a single JPEG arithmetic loop or persistent memory-bus wait.
Captures02/03 retain generation1, bus-error count25, no sticky first fault,
no recorded panic, no save-queue fault and Background save Off. The initial
capture was generation0 before the user's test boot; this is not evidence that
JPEG itself reset the phone. Counters wrap and screenshots/text are sampled.
A later screenshot shows the clock screensaver without agent input; this does
not establish SPMark completion or exit.
The existing DDR monitor cannot identify every thread's wait object or recover
its full SDRAM register/stack state.

![Observed JPEG wait](evidence/spmark-jpeg-wait-20261115.png)

An older2026-11-14 run already exhibited this JPEG wait, as recorded in
[the earlier benchmark](spmark04-benchmark.md). The newest CPU changes are not
established as its origin.

## Original-code timeout candidate

The original SPMark app's JPEG driver is10004c3c at its preferred base
(runtime app previously identified atfff00000). It first opens `test.jpg`
relative to its application path. JPEG **output goes to a128KiB memory
descriptor**, via CMdaImageBitmapToDescUtility::CreateL; this is not a JPEG
output-file write to C: or the read-only MMC. A stable read-only C: capture was
obtained before this distinction was established; no disk extraction or repair
is justified by the output-file hypothesis.

The first/last sampled JPEG-library PCs span11seconds, compatible with exceeding
the app's10second deadline; these samples do not establish timer/callback order
or continuous JPEG execution.

The app arms an RTimer for10,000,000microseconds before starting the nested
active scheduler. Its active-object vtable maps DoCancel to10002c10 and RunL
to10002bf4. DoCancel cancels/closes the timer and calls Scheduler::Stop. RunL
calls CActive::Cancel, then closes the handle; after normal scheduler dispatch
has cleared iActive, Cancel skips DoCancel. A later ConvertComplete10002fcc
also calls Cancel on the inactive object and cannot stop that scheduler.

Eight local cases execute original app RunL/ConvertComplete and original
EUSER CActive::Cancel50399b90. Callback before expiry invokes Stop once;
modeled timeout dispatch before callback invokes it zero times, for results
0/-1/-4/-33. Callee-saved registers, stack and stored result are checked.
RTimer Cancel/Close, Stop and WaitForRequest are spies; the dispatch inactive
state is modeled. This proves that code path under the stated ordering,
**not that the board took it or that HDL is faulty**.
[Original-code results](evidence/spmark-jpeg-timeout-reproduction-20261115.json).
An initial fixture incorrectly treated caller-saved r12 as callee-saved;
corrected ABI checks pass. No production RTL was changed.

## Prepared hardware discriminator

A narrow observer filters only SPMark JPEG call sites at native RTimer::After,
CActive::Cancel, RHandleBase::Close and CActiveScheduler::Stop. It records timer
interval, object, active flag/handle and caller. A RunL-origin Close followed
by ConvertComplete Cancel with iActive0 and no Stop would distinguish the
candidate from a missing completion or active CPU loop.

216exact GPR/CPSR/SP/LR/live-stack/object/log/filter/displaced-instruction cases
pass; RDebug's ABI is spied, not its full firmware service.223guarded writes
retain checksum validation, with no modified deadlines/results. It requires
a fresh held boot and is removed by reload. Applied after user approval, fresh-Hold preflight and full223-word/image
verification. It captured the ordering above. A stock reload then removed it; the complete original-ROM hash, same RBF/MMC
and saved RunOn/saveOff are [verified](evidence/spmark-jpeg-restored-stock-20261115.json).
Post-reload CPU clocks advance with generation0 and no sticky fault; the final
screenshot shows responsive Phone home. Hardware control is returned to the user. No new RBF build
is needed. See [observer manifest](evidence/spmark-jpeg-observer-manifest-20261115.json)
and [observer tests](evidence/spmark-jpeg-observer-test-result-20261115.json).

Sources, exact images and raw logs stay under
`scratch/spmark-jpeg-debug-20261115/`. Original firmware/game bytes are local only.

Reproducer sources are retained explicitly under that scratch directory:
`build-observer.py`, `test-observer.py`, `test-timeout.py` and `parse-events.py`.
The builder uses the original local ROM/service files and cached extracted
SPMark app; it prepares the guarded remote script but never connects/applies it.
Unicorn tests require native JIT execution outside the macOS sandbox. Do not
reuse the transient applied image as production firmware.
