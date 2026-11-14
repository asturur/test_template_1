## 2026-11-14: Single-write SIM FIFO correction ready for FPGA

Actual native inline RX records A4,00,16 where SELECT should return9F16.
Quartus43557629525 inferred the old multi-emit64×8 array as one8-bit write port
in one M10K. New RTL serializes through explicit ngage_bram, reuses that FIFO,
publishes only after all writes/read settle and holds busy until then. No new
packet buffer, profile/service, SIM-state or firmware substitution. At most
26system clocks per response;78MHz PLL/104MHz design objective unchanged.
This fixes the physical port contract; board causality/progress remain pending.

554-op unchanged C++ oracle,600-response FIFO/atomic-publication scoreboard,
overflow/mid-response reset/CEN32, all card/presence/controller/CTSI tests pass.
New original SIM RX ZAP fixture passes authored FIFO/production card, cache off/
on, waits0/3 (real-card17651/18145/18381/18969clocks). Full MiSTer CPU/LCD/DMA/
IRQ/FIQ/SDRAM, ownership,33 response cases and177-source/9QIP checks pass.
Details in docs/sim-fifo-single-write.md; fit/STA and new board behavior pending.

All observers removed and original88fd.../Run/saveOff/C4a75.../PMM71189... verified.
The byte-tap run later hit RF timeout/late-BT assertion; observer timing and the
current RBF's setup failure remain limitations, not a new untouched RF result.
No active capture, SD backup or other-thread simulation change. Next: commit,
push, build seed44 and schedule40-minute retrieval/deploy/debug continuation.

## 2026-11-14: SIM buffer discrepancy narrowed; exact byte tap active

Native SIM RX buffer later contains00 16 after SELECT, while the expected card
status is9F16. The sample occurs after callbacks, so post-processing is not yet
excluded. Original RX routine given9F16 in Unicorn stores9F16; production ZAP
with authored FIFO also passes cache-off/on + waits0/3 (982/1497/1708/2321clocks).
This excludes a basic byte-store/cache issue in that fixture, not the production
streaming memory path. Production card/controller CPU integration is compiling
under tests/phone/native_sim_rx; do not overstate its pending results.

Completed buffer observer removed; original88fd.../Run/saveOff/C4a75.../PMM71189...
verified. A decisive tap now preserves the exact original inline LDRH+LSLS pair
at51635C3C and logs returned bytes before the native store/parser.12 complete
RX-function differential cases match all registers/flags/SP, MMIO and RAM writes;
only debug output is added. Fresh-Hold454words/checksum verified; automatic
Run/saveOff restored.180s capture ACTIVE at scratch/sim-byte-20261114/running.jsonl.
Do not interrupt; reload/verify after capture. No functional or deadline patch,
no new production HDL, no SD backups or other simulation changes. Next fix must
follow the raw-byte evidence; current possible controller/CPU/post-processing
causes remain distinct. ADSP36=00 and native NORMAL/READY remain qualified as
above; Phone/Menu and native SIM readiness are still unresolved.

## 2026-11-14: Native SIM transfer stops early; buffer follow-up active

Direct native tracing proves SIM does receive its ATR and writes SELECT header
A0 A4 00 00 02, then DF-GSM selection7F20. Native status collector returns18
twice and RX callback runs twice; next transfer starts with one7F byte and
stops.720snapshots/no gaps; SIM stays1, no native assert, MTC NORMAL/READY and
ADSP36=00 repeat. The HAL-only trace was bypassed by inline MMIO; direct native
helpers/dispatch-table hooks work. Original IRQ handles both bits8 and10, so
combined18 alone is NOT proof of a phase/priority fault; do not add guessed delays.

Exact RX data is needed before choosing a controller/card fix. Same observer
plus two read-only native RAM buffer words passes84 differential/ABI cases.
Fresh-Hold416words verified; checksum retained, automatic Run/saveOff restored.
Capture ACTIVE at scratch/sim-buffer-20261114/running.jsonl (180s); do not
interrupt, then reload/verify original ROM/settings/disks. Previous direct trace
was removed by reload. Receipts/source/tests persist in scratch/sim-boundary-
20261114 and scratch/sim-buffer-20261114. No HDL change, no functional patches,
no SD backups, no changes to other simulations or78MHz PLL.

## 2026-11-14: Native ADSP36=00; MTC reaches NORMAL/READY

940c0f6's native test array now records RF1E=00 and ADSP36=00, with original
startup code/deadlines. MTC changes3→1/NORMAL and publishes C0/action4/READY;
Cm_commgr assertion is absent. BT15/CURRENT02 stay01 (severity0A), so these
failures do not prevent this native NORMAL/READY transition. No test results,
state or replies were injected. This is specific ADSP/startup progress, not a
Phone/Menu or timing-closure claim. Untouched control still has no usable UI.

The MTC-only720-snapshot run reaches NORMAL/READY. A second719-snapshot run
prints completed RESULTS words03030000 00030000 03000000 03010000 03030301
04000300 (decode each word little-endian), confirming ADSP36=00. Both have no
reader gaps. Native SIM is still1 at READY. SIM kernel-HAL probe produced no
lines because native SIM accesses MMIO inline, as proved by disassembly; do
not mistake that for absent transfers. Both observers removed by fresh reload.

Next frontier is native SIM initialization/serving. A direct-boundary observer
now covers original control/read/write helpers, original status/ack helper,
TX/RX and SIM_Server dispatch tables.84 mode/flags cases and actual original
status-helper differential checks pass; original MMIO/W1C/args/SP preserved.
406fresh-Hold words verified, checksum retained, saved Run/saveOff restored.
Capture ACTIVE: scratch/sim-boundary-20261114/running.jsonl (180s). Do not
interrupt. Must reload/verify original ROM/settings/disks afterward. No SIM,
state, deadline or functional substitutions; no new HDL since940c0f6. Failed
setup-0.386ns remains a limitation of this diagnostic RBF. No SD backups.

## 2026-11-14: Production synthetic-card selection for native initialization

Template now selects the existing separate ngage_test_sim card and asserts
physical-model presence; files.qip includes it. No-PIN test IMSI001010123456789
and existing GSM EF contents remain fabricated, not a physical card dump.
No native SIM state, indication, MTC state or firmware reply is substituted.
This reverses the temporary production card omission; no OSD control returns.
Serving/ready state and Menu remain hardware qualification gates. See newest
status.md and adsp-native-link.md for the observation-dependent ADSP result.

Card reference/FIFO/overflow/CEN and controller/CTSI/CPU integration pass. The
old card's440.7ALMs is a historical figure; new fit is pending. Passive DDR
status now exposes presence, overflow, busy/RX-valid plus D550 milestones.

## 2026-11-12: SIMIF W1C phase transition corrected

Zero or unrelated status acknowledgements formerly advanced TX-done to RX and
raised18 while8 remained unacknowledged. Reproduced in the board fixture; the
transition now requires din[3] as well as pending status[3]. All card/presence,
FIFO/overflow/stress/CEN and committed peripheral response tests pass. This
corrects the controller, not the unresolved native SIM-ready handshake. Strict
original-firmware/HDL-only boot remains the requirement; see
[native-startup-hdl.md](native-startup-hdl.md).

## 2026-11-06: diagnostic SIMIF HDL port

The staged card/controller behavior now has a Verilog-2001 UPP SIMIF and a separate bounded synthetic card module on the board. MiSTer offers reset-sampled No ATR and Test card profiles. C++/HDL card and controller tests, FIQ routing, and a CPU-executed SELECT fixture pass; see `docs/status.md` for commands and limits. Two 20M-cycle from-reset C++/HDL shadow runs passed, but they did not reach SIM initialization. This does not establish a functioning SIM, cellular modem or physical serial timing.

## EF 6FC6 interpretation

The last file selected by the current synthetic-card initialization is 6FC6. [3GPP TS 51.011 v4.3.0 §10.3.42](https://www.etsi.org/deliver/etsi_ts/151000_151099/151011/04.03.00_60/ts_151011v040300p.pdf) identifies it as optional EF-OPL (operator PLMN list) and says it must be absent when EF-PNN is absent. The diagnostic card currently does not implement EF-PNN (6FC5), so its file-not-found response for 6FC6 is consistent with that condition. This does not prove the whole SIM service table or controller timing is correct, nor that the missing initialization completion is caused by EF-OPL. Preserve the standard's exact profile dependency if implementing these files later.

## Controlled comparison still needed

The staged `scratch/simif-board/board/boot_profile.cpp` unconditionally injects the diagnostic card ATR after the first RX setup; it currently has no runtime card-present switch. Consequently the old `current-tlbhold` cardless checkpoint is a historical comparison, not a controlled test against the same board and build. Once active runs finish, add a tested runtime card-present option to the staged model, preserve checkpoint compatibility, and compare otherwise identical from-reset boots with live screens and matched probes. Do not change hashed sources during active replays.

## 2026-11-05: observed modem indication is not SIM-ready

In a fresh card-present boot, firmware constructs MTC request 0x1511 carrying state 3 at 955.726M. MTC publishes 0x15c0 with action 0x0c, and SIM_Server receives it at 955.837M. Full instruction traces show SIM_Server rejecting it for its action-4 ready and action-3 branches; it does not trigger the known ready queue-drain path. The sender copied state 3 from 0x8001095c through 0x8001095b. This does not establish why state 3 was chosen or whether it is wrong; a separate earlier-startup trace is running. The later SIM-notification queue and any subsequent ready event must be observed independently; do not force either. Details and checkpoint paths are in `docs/status.md`.

## Post-initialization notification (2026-11-05)

In the checkpoint-restored diagnostic-card run, the firmware posts internal event 0x1280 and SIM_Server stays in state 1. A resource-0x53 notification is queued; checkpoint RAM suggests it remains queued at 2B, subject to dirty-cache uncertainty. Static N-Gage ROM code shows one route to drain the queue: an MTC state indication 0x15c0 with action READY (4) and state NORMAL (1) or TEST (4). The phone's own MTC server can build that indication in response to startup synchronization request 0x150b; Nokia oFono definitions corroborate the names and values for its later ISI implementation. A second candidate release path involves internal event 0x0a33 and ATKinf, with possible SMS task producers, but its sender and timing are not established. None of these links proves which event is missing in this run or that a SIM is serving. Track the from-reset present-card run and MTC request/indication probes in `docs/status.md`; do not force firmware messages or bypass timeouts.

## Diagnostic card progress (2026-11-05)

The isolated SIMIF replay now supplies synthetic DF metadata (22 bytes, including voltage and PIN status), ICCID, EF_ECC, EF_LP, EF_PHASE, EF_SST, EF_LOCI, EF_AD, a fabricated test-network EF_IMSI, EF_ACC and TERMINAL PROFILE. These are test values, not a physical-card dump; optional 6f14 and 6fc6 still return file-not-found. Directed test-card tests pass. In the original cardless baseline SIM_Server entered state 5 at about 1.14B; with this test card, firmware instead remains in initialization state 1 through 1.5B, after receiving internal event 0x1280. This is a controlled comparison from the same original 1B checkpoint, but it does not show that the card is serving and does not establish why the ready event is missing. `simif-acc-2100m` is running with live LCD updates and a 2B checkpoint; see `docs/status.md` for exact output paths and active status. Compare any later SIM state and on-screen result, then investigate the missing transition; do not patch or suppress firmware timeouts. Hardware transport timing is still an experimental hypothesis and all changes remain isolated from the maintained phone model.

# Diagnostic present-SIM work

## Current SIMIF investigation (2026-11-04)

Firmware traces and related TriX register maps point to the hardware SIM interface at physical 0x0c150800, rather than the previously hypothesized UART path. An isolated model delivered a synthetic 3b 00 reset response via FIQ source 26. Follow-up callbacks required the modeled 0x2000 NOS software interrupt; a separate ICU fast-status priority bug was also fixed in the maintained simulation board. With an unverified isolated control-register completion hypothesis, the firmware then emitted `a0 a4 00 00 02`, consistent with a SELECT FILE command header. The card response, file identifier, timing and complete protocol still need implementation and verification; this is not a working SIM. See the newest entries in status.md for run names, caveats and next steps.


The 11.928B `current-tlbhold-20b` run displayed “Insert SIM card” and later stopped after a ViewSrv 11 timeout. A ViewSrv object has UID 0x100058b3, matching the Phone application. The relationship between these observations and the earlier “App. closed” dialog is not established.

## What exists

`scratch/modem/ngage_modem.c` has an ISI SIM responder, with an unregistered/cardless default and an existing successful IMSI read (`0x09/0x1d/0x2d`) when registered, state 8 and the IMSI cache is valid. The C and HDL modem responder models were cross-checked previously, but this does not prove the boot routes its SIM requests through either model. The software emulator's `sw/kernel/chan.c` serves a made-up test-network IMSI directly at the NOSDRIVER channel interface. Its HLE is a useful behavior reference, not proof of hardware wiring.

`tests/phone/sim_present/profile.c` is a standalone diagnostic profile using the same fabricated IMSI `001010123456789` (test network MCC 001/MNC 01). `tests/phone/sim_present/test.c` checks the returned frame and confirms cardless defaults remain unchanged. It also documents an important gap: request 0x64/0x61 still returns status 0xfc (not serving) even in serving state. NOS disassembly sends this request to the SIM subsystem asynchronously; the 0x65 response copies its status and four data bytes from the eventual completion. The actual successful completion values and indication sequence remain to be established. The profile is not connected to the firmware simulation and is not a complete simulated SIM.

## Transport and next tests

The phone's NOS/gsmstuff service runs on the same ARM core: see `docs/modem-model.md` section 1.5. The current board's responder is invoked from the hypothesized euart1 data register `0x0c150500`, but the 11.928B run's compact bus trace contains no accesses to that data register; it does contain 16 nearby UART status/configuration accesses. Because accesses in this register range are labeled `assumed_keypad_gpio` and are included in compact logging, there is no observed modem-frame transfer in that run. The claimed UART path and RX interrupt remain hypotheses, not verified phone behavior. Check the current runner inputs, actual call sites and hardware documentation before treating it as the SIM interface.

1. Let `tlbhold-viewmodules` finish before changing the source or binary it hashes. Identify when Phone requests SIM status and which path enters `nosdriver.ldd` / gsmstuff or the missing hardware SIM interface. Trace both successful and failed request completions with a bounded replay; compare NGVM's request/reply contract, lengths and asynchronous completion.
2. Establish the serving-card success bytes for SIM 0x64 and required presence/ready indications using firmware handlers and available references. Unit-test card present, no card, initialisation and invalid requests; use an explicitly fake IMSI. Do not change the default or present this profile as a real card.
3. Connect the diagnostic present-SIM responder at the proven simulation boundary, including request queueing and interrupt/completion semantics. Keep the option off by default and report its use in provenance. Preserve old checkpoints and validate any checkpoint compatibility before restoring them across model changes.
4. Run a controlled cardless/present comparison from a suitable compatible checkpoint. Capture requests, replies and live LCD images; separately investigate whether “App. closed” or ViewSrv timeout persists. An IMSI response alone does not establish successful boot or solve the app crash. Port validated behavior to HDL when the interface is understood.

## Captured real in-process request

A bounded replay `sim-nosdriver-call` traced NOSDRIVER control 4 constructing a 10-byte Phonet/ISI request at VA 0x85c1510c. The frame's resource is 0x1c and message is 0x10; the real gsmstuff router and accessory handler consumed key 0x1c10. This shows that the in-process channel is active in the current boot. It is not a SIM request, and it does not prove that the separate UART responder receives OS messages. The next instrumentation should log resource 0x09 only, at the router boundary, with compact request and response payloads.

## Firmware state observed in checkpoints

The ROM's own SIM_Server singleton at VA `0x800ca784` has the expected class and service table pointers. The +8 state byte is 1 (starting) in the 1B checkpoint and 5 (non-serving) in the 2B, 3B, 5B, 8B and 11B checkpoints. Checkpoint RAM may lag dirty cache, but these observations narrow the transition to the 1B–2B interval. The transition table includes three ways to enter state 5: internal event `0x70d`/parameter `0x74`, or event `0x70e`/parameter `0xfe` or `0xff`. This is a static enumeration, not a claim about which event occurred. Events `0x70d`, `0x710` and `0x70e` dispatch through the SIM server table to 0x5159b7d5 (Thumb). `sim-init-state` is tracing the real transition and `sim-router` is tracing later requests.

## SIM startup response consumer

Static Thumb disassembly of the 0x0965 startup-manager response handler at 0x515042d8 checks response body byte 3 for status 1. On success it passes body+4 to 0x515e916c; other values call 0x515e91b4. This confirms the success-status branch but does not establish valid values for the four following bytes. The test profile must not invent those bytes as verified hardware behavior.

The success helper at `0x515e916c` allocates an eight-byte internal message and copies **six** bytes from the supplied body+4 pointer before queueing it to task 0x14. The previously inspected 0x65 builder allocates an eight-byte body and writes four data bytes at offsets 4–7, so the copy can extend two bytes beyond that nominal body. Heap layout or a different 0x65 producer may matter; verify before choosing a synthetic payload or claiming a faithful response.

## Failure-event source

The producer of event `0x70d/0x74` is a firmware chain whose diagnostic filename literal at 0x516d3400 is `SIM_SUBSYSTEM/Sim_l2.c`; the `0x25d` dispatch refers to `SIM_SUBSYSTEM/Sim_upl.c`. These firmware-supplied labels place the observed path in the SIM subsystem/link-layer implementation, but do not establish which physical pin, register, missing response or timer caused the failure. The isolated from-zero `sim-flag-origin` trace is watching writes near VA 0x800092e6.

The firmware's own initialized-data image contains byte `1` for the flag at 0x800092e6: nosstarter copies 0x51711138 to 0x80006ef0, making source byte 0x5171352e (factory core offset 0x31352e). The separate THC NOS image agrees. The runtime copy and any subsequent changes remain to be validated by the ongoing trace.
