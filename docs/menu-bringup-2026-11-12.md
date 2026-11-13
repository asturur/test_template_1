# Hardware menu bring-up,2026-11-12

Goal: reach the usable N-Gage menu with original NEM-4 NOS startup retained.
Other chat's frozen simulations/checkpoints and pending memory-controller edits
are not modified, built as a full core, committed or deployed by this work.
No new Quartus build, PLL/constraint change or build monitoring.

User confirms Menu hides the screensaver and displays the N-Gage logo. This
wake action was consumed; the DDR key test showed no CPU reset or kernel panic.

## New live-C: capability and confirmed Phone exit

The C: flash backing is already in DDR at0x31400000,4 MiB. Linux read-only mmap
can capture it directly, without flush/autosave or an HDL change. `/dev/mem`
`pread` returns EFAULT on this installation; mmap is the verified method. This
reads committed flash backing, not file-server dirty RAM or arbitrary SDRAM.
Two equal images plus successful original-filesystem traversal provide a stable
readable capture, not a general atomic process-memory snapshot guarantee.

Baseline after restored working.nga: two complete C: reads both SHA256
`cacd9103b73df319378abcb5884d101f4370f92080f97c8cfc76120ff441a23f`.
Original guest LFFS reader lists102 entries/65 files,0 writes, with this newly
appended record absent from the original69-byte StarterMonLog:

```text
1.1.2003 10:11:29
Phone.app exit
d1=0,100,0,0
d2=3584286,13053952
```

Therefore Starter recorded a Phone application exit despite no kernel panic
and a responsive screensaver/key path. These `d1` fields are not yet decoded;
do not label the first0 a confirmed exception/exit reason. Profile database
changed2657->33547 bytes; Bookmarks/System.ini also changed and shared-data
100058c5.ini was removed. These are observations, not proof of corrupted data.
The original image remains unchanged on disk; live flash writes remain unsaved.

`tools/ngage_runtime_c.py` performs consecutive-equal read-only captures and emits
binary stdout plus size/SHA metadata on stderr. Example:

```sh
ssh root@192.168.1.176 'python3 -' < tools/ngage_runtime_c.py > scratch/live-c.vhd
python3 tools/ngage_lffs_extract.py scratch/live-c.vhd --out scratch/live-files --all-files
```

The extractor uses the original EFile filesystem under a private NGVM kernel;
its host execution is not a full original-kernel/RTL boot. Input writes are
explicitly denied. No persistent C: watcher or SD flush is required.

## Bluetooth comparison: verified improvement, not the menu fix

Physical LRB-2 model remains explicitly unimplemented/non-driving. Existing
`Bluetooth_Compatibility.ngo` is a NEM-4 BTLDD transmit/completion substitution
with local HCI initialization replies and no real radio/peer. Retains original
kernel ring/read/completion routines. It does not modify NOS or UI startup.
The compiled-in overlay loaders are disabled for fit; simply copying boot3.rom
would not enable it in the running build.

Prepared `tools/ngage_runtime_bt.py` to apply the pinned existing package to
**volatile DDR ROM only**, avoiding a new FPGA build or overlay-loader area.
Default is read-only. Writes require exact audited original ROM SHA, pinned
package SHA, every expected original word, two advancing valid DDR snapshots,
CPU held/reset, zero cycles/fetch/ACK/error history, reset generation0, images
restored, idle save state, no dirty pending work and autosave Off. Warm Hold
after running is insufficient due to backend and CPU caches. User must freshly
reload RBF in Hold and keep it held until confirmed. No firmware/disk file is
changed; RBF reload restores stock behavior. Offline tests cover rejection,
patch/readback, interrupted-write rollback, hook-last publication and torn seals.

User explicitly reloaded/held, guards passed,590 records applied/read back:

| Identity | SHA256 |
| --- | --- |
|Original assembled ROM|88fd596a23269ecb0d9f7544d540c59010d276574dbe3d0262c870c429e58329|
|Pinned BT package|12b078de67083dffe006be7b0102444c9f2d0e6a3660674ff3cb2449de2ec2aa|
|Patched volatile ROM|876f3f9004d9f244ead65d1a96c16cf103b42cb74cd571942258db9e0dd047d8|

Host HCI tests (ASan/UBSan, all opcode/parameter extremes) pass. User selected
Run. A bounded300 s SSH capture collected1171 snapshots (including initial
Hold), no panic and no `-33` text, reaching ADSP session/channel setup and
`CSysApAppUi::ConstructL: Start listening`/RTC Add5. Runtime hook/completion works
far enough to eliminate the formerly repeated Bluetooth errors at this stage.

Stable live C: SHA256
`6048178ad46f2726f6a94c192b1138dcbd299d8bb48b2292ef58b7d9bde37768`
also decodes102 entries/65 files/0 writes, but still appends:

```text
1.1.2003 10:11:28
Phone.app exit
d1=0,100,0,0
d2=3585664,13045760
```

Bluetooth timeout removal alone does not fix the Phone exit. No menu success
claimed. Bluetooth protocol/performance breadth beyond observed initialization
is unqualified; do not enable a physical wire stub as though implemented.

## Next prepared experiment: user exit/panic/caller trace

Small912-byte payload in verified erased ROM pad511B6000 hooks original NEM-4
User::Exit503B4718, User::Panic503B46E0, RThread::Kill503B7FB8,
Terminate503B7FE4 and Panic503B8010. These entry words are all PUSH{lr}.
Each trampoline preserves r0-r3/r12/LR, SP and condition flags, logs original
arguments, LR, SP and CPSR through original RDebug::Print503B409C, replays the
stolen PUSH and continues at entry+4. It never dereferences arbitrary caller
stack/category pointers. NOS and startup semantics remain original. No FPGA
logic or normal-instruction path latency added; debug-print cost occurs at exits.
Kernel-internal deaths and direct process-kill interfaces may bypass these hooks.

Export-table discovery uses actual SYM.ROM anchors: Count ordinal265 at503AD63C
and WaitForAnyRequest ordinal1209 at503B246C imply EUser export base503CAB7C.
Older extracted EUser header points at a different table and is not a valid
address oracle for this ROM. Calls/entry words are checked against original ROM.

`tools/build_exit_trace.py` assembles maintained ARM source. Pinned payload SHA
`21536f61dbd1ec1e93d32110d7a4521ab89a978110eca776d7dd05b8e505db44`.
The optional `--exit-trace-b64` argument to the guarded runtime tool includes it
with Bluetooth. No arbitrary payload or generic patch application is accepted.
Tests on actual ZAP,0/3 waits, cover all five hooks, ARM and Thumb callers,
argument/volatile register/flags/SP preservation, reported caller LR/SP and valid
UTF-16 descriptor. Only RDebug's print leaf and the original nonreturning exit
continuations are fixture stand-ins: this does not execute the original
RDebug/kernel exit implementation or prove hardware mapping/ABI integration.

User performed the second fresh RBF load in Hold. All guards passed;823 total
BT+trace records applied/read back, volatile image SHA256
164c335174a34411dd634c4fdbce6e0b6364c8d96c17ea94b2cfa71eb6e41403.
Tracer v1 was installed; initial hardware observation below supersedes pending Run/actual Phone caller/exit
cause remain pending at this checkpoint. Do not patch an executed/cached core. If no trace
appears, do not infer no exit: the existing C: record and hook coverage matter.

Local inputs, original/live disk copies, byte checks and raw/decoded output:
`scratch/menu-bringup-20261112/`. Exact original restored disk pair/backups remain
as documented in `working-nga-restored-2026-11-12.json`. No save has been triggered.


## Hardware exit trace: ViewSrv panic captured

User selected Run. Actual firmware RDebug output confirms the ROM-pad hooks
execute on this hardware. Several thread-return paths exit with reason0 via
503ACDA8. That shared return wrapper does not identify Phone or its main thread.
A later record is:

```text
X THREAD_PANIC a0=0041cf54 a1=00701e78 lr=5064dd55 sp=00701e78 cpsr=00000010
```

Original ROM disassembly identifies5064DD38 as a ViewSrv panic helper: it
constructs the category descriptor from UTF16 literal5064F6D0 (`ViewSrv`), moves
its reason from r6 into r2, and calls RThread::Panic, returning to5064DD54.
Several distinct reason paths share this caller. In particular,11 is a static
candidate at5064CC7C/5064D560, but **the first tracer omitted r2**, so this is
not yet a confirmed ViewSrv11 timeout. Do not suppress the panic based on that
inference. Its target thread and causal relation to Phone also remain unproven.
Zero global/kernel panic masks in DDR do not exclude this captured user panic.

Read-only C: capture after this run: two equal4MiB copies, SHA256
`c1a896732eef7e855b8462c1c452411e2da0730fdd7d85f9c59cfa0a0606f5e6`.
Original filesystem traversal again gives102 entries/65 files,0 writes and a
new Phone exit10:11:28,d1=0,100,0,0,d2=3637004,12906496.
Maintained text evidence: `docs/evidence/menu-exit-trace-2026-11-12.txt`.

Expanded tracer v2 logs original r2 (panic reason) and r6 (thread entry at the
503ACDA8 return wrapper). It still never dereferences arbitrary caller memory.
1132 bytes; SHA256
`b30425a30d0ace76bdb6e55ae2b0a6b85822db1c69960c73f4d928f1dd7192fb`.
Five host safety tests and actual ZAP ARM/Thumb,0/3 wait ABI tests pass,
including the extra reported registers. User fresh-held reload requested;
v2 is not yet installed. Current hardware retains v1 until reloaded.

Next: capture the panic reason and map exiting thread entry points before
selecting any behavior-changing experiment. Menu remains unavailable.


## Expanded hardware trace confirms ViewSrv11

User freshly reloaded in Hold;878 BT+v2 records verified, volatile ROM SHA256
`f427324b8f1544828a10e2e4199e2fd7dee0e1e623a265b61dbc79db31245376`.
After Run,240s bounded capture records:

```text
X THREAD_PANIC a0=0041cf78 a1=00701e78 a2=0000000b lr=5064dd55 sp=00701e78 cpsr=00000010 r6=0000000b
```

Thus ViewSrv reason11 is now observed, superseding the v1 reason uncertainty.
Original callback paths5064CC3C/5064D538 issue11 when timeout phase2 occurs
with a pending client; both use the shared panic helper. Target client name is
still unproven. Several ordinary reason0 exits map to EStart,DBRECOVERY,
EDbsrv,Sysamob,MSexe,SplashScreen,FLogSvr,EikSrvUi and AppRun code, so these
must not all be labeled Phone. Actual serialized ROM headers located by UID
agree with these module ranges; extracted files' linked addresses differ.

Original ViewSrv constructor5064BF10 copies defaults from5064BF68 (1000000us)
and5064BF6C (10000000us) into object+80/+84. Timer setup5064C9C4 schedules
soft interval; callback5064CA2C schedules hard-minus-soft for phase2. This
provides a bounded comparison: increase defaults to10s/100s, keeping completion,
callback, cancellation and panic logic. Slow CPU work causing expiry is a
hypothesis, not established by the reason number alone. Runtime setter overrides
and a permanently unresponsive client remain possible.

`--view-timeout-scale10` adds exactly those two checked words to the existing
fresh-held/full-ROM-SHA guard and readback. Six host tests pass. The bounded
`tests/tools/test_view_timeout.py` executes original Thumb constructor/timer
code with stubbed external leaf calls: only the two expected constructor fields
change; scheduled intervals1s+9s become10s+90s. This does not qualify a full
original-kernel or hardware boot. No production firmware file changed.
Fresh-held reload requested for the comparison; not applied yet.


### Deadline comparison installed

User freshly reloaded in Hold and then selected Run after verification.
880 words verified; volatile ROM SHA256
`92afb368bf735c26c1d796d646d3ac71fe95a10714deeb0b5d6f08b745fdbade`.
Original card firmware/C:/PMM unchanged. Bounded600s diagnostic capture is
running. Baseline v2 capture first observed SysAp Start listening at37.5 sampled
CPU seconds and ViewSrv panic at70.75; these are approximate relative capture
positions, not precise event timestamps or absolute boot times.


### Defaults comparison failed; actual configuration found

Same ViewSrv11 recurs at78.0 sampled CPU seconds versus70.75 baseline; SysAp
Start listening shifts37.5->44.5. Panic relative to SysAp is33.5s versus33.25s:
no meaningful extension. Do not repeat constructor-only changes as a fix.

Original EikSrv5063EA26/5063EA38 calls EikResourceUtils::ReadResourceIntL
(EikCore export138) for resources19BD6012 and19BD6013, then calls ViewCli
SetServerEventTimeOut/SetClientRequestTimeOut (exports26/25) at5063EA2E/EA40.
The IPC handlers invoke the ViewSrv setters, replacing constructor defaults.

Decoded original EikPriv.RSC Calypso resources18/19 give20000000us and2000000us.
Resource1 signature040000000160BD19 agrees with their resource namespace;
the complete supplied resource file also occurs byte-for-byte in original ROM.
Decoder retained under scratch/menu-bringup-20261112/read-eikpriv.py, following
the existing reference parser's bitstream format. No resource file modified.

Corrected optional comparison `--view-config-scale8` changes exactly two aligned
words:5063EA28 1C01F8CB->00C1F8CB and5063EA3C 68281C01->682800C1. Only the two
`ADDS r1,r0,#0` become `LSLS r1,r0,#3`; adjoining BL/handle-load halfwords are
preserved. Both configured deadlines multiply by8 (20s/2s->160s/16s), safely
within signed32-bit range for these verified resources. All IPC/timeout/cancel
logic stays intact. This is a pinned firmware-specific experiment, not a generic
interval scaler. Constructor-only and configured options are mutually exclusive.

Seven host safety tests pass. `tests/tools/test_view_config.py` executes original
EikSrv Thumb configuration code with resource-reader/IPC leaves stubbed and
verifies original20s/2s versus160s/16s, both resource IDs and handle arguments.
Fresh-held reload requested; corrected configuration comparison not installed.
No claim that CPU slowness is the only cause or that the menu is fixed.


### Configured deadline comparison installed

Fresh-held guard and880word readback pass. Patched volatile ROM SHA256
`8bacba9c28f50ac1e2aab250cbe28b4c0055212b61a8d2793c986634f2f06fe8`.
User confirmed Run; bounded480s capture under
`scratch/menu-bringup-20261112/view-config-running.jsonl`. Original constructor
defaults retained; only EikSrv configured intervals are extended in this trial.
No card firmware/disk writes, new FPGA logic or other-chat simulation changes.


### Hardware result: responsive Phone view; menu still unavailable

User observes INSERT SIM CARD and confirms digit1 and multiple digits appear
responsively. Menu reaches the core (mask40,153.5->154.25 sampled seconds), but
does not change the view. No CPU reset or new panic follows that key.
No ViewSrv11 appears in the capture so far; this does not qualify all timeouts.
Read-only live C: SHA256
`de9723306d98354a18bea2739f5029cd92e53bc2705849b0616482e11edda7ff`,
105 entries/68 files/0 writes. StarterMonLog contains only the old2004 factory
record, no new2003 Phone exit. This is meaningful progress over all prior trials.

A different panic appears at82.5 sampled seconds, before Menu:
USER21, UserPanic caller503BF514. Original literal503CA6D4 is `USER`; original
EUser export98 TDesC8::AtC starts503A2B14, and its bounds failure at503A2B48
branches503B1B78, which supplies21 to the USER panic helper. This identifies a
byte-descriptor index failure, not its original calling component. Numeric
Phone input remains responsive despite this other thread panic. Do not blame
Menu or assume Phone itself is the thread that panicked.

Production Template explicitly selects TEST_SIM_ENABLE0 and sim_present0.
Thus no physical SIM card is presented; original logical NOS SIM services remain
in place. This is consistent with the notice, but does not independently prove
that a SIM alone resolves the unavailable menu. Do not reenable the previously
removed diagnostic card/display or replace original NOS wholesale on this evidence.

Prepared1376-byte v3 tracer adds only503A2B48 failure-path hook. It logs original
AtC LR, index r1 and descriptor header r2 before the shared USER panic wrapper
loses the caller; successful descriptor accesses incur no new hook latency.
Displaced B resumes503B1B78 directly without a synthetic PUSH. SHA256
`185654cc5676dab6df24fdc576ac113b721353d6c841fc0a4a8655a22d109bbe`.
Seven host safety tests and actual ZAP six-hook ARM/Thumb0/3wait fixture pass,
including the different bounds-hook continuation. Fresh-held reload requested;
v3 not installed. Keep configured deadline extension for this next comparison.
Goal remains a usable menu, not merely the cardless view.


## Descriptor caller identified; autonomous hardware loop

V3 applied942words after fresh-held reload; volatile ROM SHA256
`e496f76691744f7a8f15d4495e65657531f95cd47969f4e57c3d6364f736a040`.
Run captures:

```text
X DESCRIPTOR_BOUNDS a0=00403418 a1=00000019 a2=6000000a lr=50fc9a7b sp=00401e04 cpsr=80000010 r6=004030ac
```

Actual serialized module header maps50FC9A7A to Nokia.dsy, code50FC54B4+6D54.
Helper50FC9A70 pushesLR, adjusts object+4, requests byte25 through original
AtC, then reads it. Its input descriptor has length12. Note r2 at this late
failure branch is **header XOR(header>>1)** from original AtC flags handling;
inverting6000000A gives4000000C, not an invalid type6 descriptor. This is a
short-message parser failure, not yet evidence of arbitrary memory corruption.
The message type/content and the helper's calling method remain unknown.

V4 logs exactly12 data bytes and the saved caller LR only for that exact helper
return address, length12 and data/SP in00400000..00FF0000. Saved LR dereference
is grounded in verified50FC9A70 PUSH, not guessed arbitrary stack walking.
Other descriptor failures keep numeric-only logging. No successful descriptor
path overhead.1588bytes, SHA256
`647aa94ca457608f83acde4eb68f7d7fd8fd3eb12d23600c913774e2ac29d929`.
`tests/tools/test_dsy_trace.py` verifies exact read scope, expected message words/
savedLR, mismatch guards, preserved registers/SP/flags and original continuation;
ZAP six-hook ARM/Thumb0/3wait and seven host guards also pass.

User authorized autonomous reload/start through Zaparoo. Same-core launch alone
left existing execution/patches intact: full-ROM identity guard refused all
writes. Returning to menu then launching `_Console/ngage1`, waiting30s, passes
fresh-held/original-image guards.995words applied/read back (BT+v4+config8), ROM
SHA2566B76F8549862D27A6F32C5404C8A28691F2F4C29C783EDAE5B3B0726CFF02140.
Zaparoo keyboard F12,7Down,Enter,F12 starts CPU; DDR cycles/fetches advance and
autosave remainsOff.180s read-only capture now running. Card files untouched.

RPC helper under scratch/menu-bringup-20261112/zaparoo-rpc.py uses the local
API through SSH. Screenshot works; core screenshot omits OSD composition.
Command syntax checked against official [input](https://zaparoo.org/docs/zapscript/input/)
and [MiSTer](https://zaparoo.org/docs/zapscript/mister/) documentation. No source
changes to Zaparoo or installation/deployment of other components.


## V4 result: native permanent-record error reaches unchecked DSY parser

Captured message words23000000,1D530006,00110500 correspond to bytes
`00 00 00 23 06 00 53 1d 00 05 11 00`; saved helper caller50FC91FD.
Original UTF16 diagnostics identify CPermRecordReadReq/CPermRecordReadResp.
The request builder50FC97B8 writes resource23 and body:
`utid,04,0032,0001,00000000,00000002` (multibyte request fields big-endian).
This asks group50/record1,offset0,length2. The response is a4-byte error body
`00 05 11 00`, not a success response with two data bytes at full-frame24/25.
Nokia.dsy50FC91C4 unconditionally calls50FC9A70 to read full-frame byte25,
which explains USER21. Do not replace an error with guessed successful data.

Original NOS class cPERM_Server descriptor516DFD6C dispatches2304 at51597F40
through51598380 to51598794. The handler calls original storage reader5152BA5C
at51598886. On nonzero status,515988C2..CC shrinks body to4 through514B9B3C.
Storage error11 converges at5152BC9A from several lookup/header/state integrity
checks; **the exact branch is not yet observed**. Thus the12-byte error is an
intentional native NOS reply, while DSY lacks the corresponding status/length
handling. Original NOS and all message/completion owners remain intact.

Read-only PMM capture at31800000:65536bytes, two equal reads, SHA256
`d355928744c3f4ba634c044fd7346367e750154e845756822fef08465747afef`.
1395 non-FF bytes; sectors0/8000 have PMMCAT headers and linked catalog chains
66/3 records, alternates4000/C000 are inactive. Therefore native NOS formats
and programs the initially erased backing; this is not proof that record50/1
exists or has valid data. Do not identify encoded catalog IDs solely by a raw
byte scan. Exact lookup/error and record semantics remain to be derived.

Read-only previous card backup boot1 is65536bytes, SHA256
`0d4fd8e6611265fbce34b4757c309ae7d7d71bb4e29d32fa12c15299c54fe9cf`.
It is formatted, but has not been substituted or qualified as a remedy.
Original restored disk files remain untouched. No PMM data was invented/seeded.

Next: resolve group50/record1's original defaults and error11 lookup path,
then test native initialization or proper DSY error handling. Keep the verified
configured deadline extension. Physical SIM is still absent; responsive cardless
Phone UI does not by itself establish a usable menu or complete NOS/SIM support.


## Volatile PMM candidate comparison

Public newer Symbian DOS definitions were inspected via authenticated gh CLI;
legacy ordinal50 does not match their reordered ABI and must not be assigned
a name from it. The missing doshelperbase.h path404 was resolved by listing the
actual API directory; CLI access remains working. No unsupported name inferred.
References retained under scratch/menu-bringup-20261112/symbian-dos.

Prepared candidate from the captured live PMM, preserving69 records and appending
50/1 at sector0 offset726, payload0400. Original DSY writer50FC9A80 writes
prefix04 plus its byte value; **zero is an experimental choice, factory semantics
unverified**. Native header decoder515CA380 (supplied group-map fixture) and
state decoder515CA3E4 accept header/group translation/state8. Candidate SHA256
`77e0e24008ecc2b828ac45c7d7bcefc151037f24fe89cff28f2f6cceaf564dfd`.

Autonomous cold load, exact working ROM SHA6B76F854..., fresh-held advancing
snapshots, mounted/verified inputs, autosaveOff and erased PMM guards pass.
Only volatile PMM31800000..3180FFFF replaced/read back. No card image write.
Rollback is RBF reload. Host helper in scratch/apply-pmm-test.py; native decode
fixture and candidate manifest retained with it under this experiment folder.

At the observed~180s window there is no USER panic, descriptor failure or
ViewSrv11; Phone screenshot still shows INSERT SIM CARD. This candidate is
promising for USER21, but it changes preexisting PMM records as well as adding
50/1 relative to erased baseline. A matched formatted-source-without-new-record
control is required before attributing removal specifically to50/1. Do not
promote payload0400 to a factory/default image on this evidence.

Our Phone-display selection overlapped the user's manual selection and toggled
back to Diagnostic. Corrected immediately and screenshot verified Phone. Avoid
blind display toggles while the user is changing OSD. Leave Phone selected.

Original Nokia2003 guide documents an Offline profile disabling GSM for games;
it does not by itself prove cardless startup. SIM absence is **not yet proven**
to be the remaining menu cause. Do not equate offline/no radio with SIM-ready.


## Active deadline investigation: Phone target proven

User explicitly directs investigating the timeout now, not deferring it.
V5 returns to original configured2s/20s deadlines, normal mounted/erased PMM,
BT responder retained, and calls original RHandleBase::FullName only for the
known ViewSrv panic caller. Actual hardware prints:

```text
X VIEW_TARGET Phone[100058b3]0003::Phone
```

This proves Phone's main thread is the target; the previous shared panic helper
alone could not identify it. V5 is1728bytes SHA256
432EDF1C145713053AE2E4079BF175E63C9A995A40A7508ED6358F0626096DB2,
1028words applied, ROM B3A7733D6AD8536E2C022745DE8E016FC46972E4A6B7E044CD0B0D5CC57CFD07.
The original FullName constructor/memcpy execute in the bounded test, only its
exec/print leaves stubbed. Actual ZAP0/3wait and host safety tests pass.
Periodic PC samples contain substantial EUser/kernel/file-system/library work;
these are aggregate4Hz samples and do not establish which thread owns time,
exact syscall waits or memory-controller bottlenecks. Do not call fetch counter
an instruction-retirement/MIPS counter.

V6 additionally balances RThread::Suspend/Context/Resume at the already-expired
ViewSrv panic point and records request count, context result/length and first
17 raw context words when at least68bytes are returned. Uses original exported
wrappers227/928/954/1122, validated against actual EUser table and code. Resume
always precedes printing/status branching; no ongoing suspension remains. Hook
occurs only for ViewSrv's known target panic. Context layout must be checked
against actual response length/values before naming saved registers.
2400bytes SHA256 EBD081885D9D148E84EA57589AD04A869B7BBB3138C8DE844EF2972EDC9CF7C7;
1196words verified, ROM96EC08FCED415318B033124EEB0E239F2B4785FB39DA0C375ADFC6A6E511404C.
Host context fixture checks actual EUser wrappers, exec leaf ABI, balanced
suspension on success/error/short reply and GPR/flags/SP/displacedPUSH. ZAP0/3wait,
seven host guards and DSY read-scope test pass. Hardware150s capture in progress.
No production RTL, card images, PLL or other-chat simulations changed.

## Ready SIM and synthetic network target; v7 wait context

User requests an inserted, ready SIM, fictional carrier and signal as the final
service state. Preserve the semi-real NOS architecture: establish coherent SIM
initialization/security, identity/service queries and modem registration/operator/
signal replies, rather than changing only UI indicators. These states are a
synthetic local service, not proof of an RF connection. Production remains
TEST_SIM_ENABLE=0 / sim_present=0 pending a validated change. Existing
ngage_test_sim is an APDU test-card model, not a complete network model.

V7 hardware capture `scratch/menu-bringup-20261112/view-context-v7-running.jsonl`
again identifies Phone as ViewSrv11 target with original 2s/20s deadlines.
The corrected Context trace records 72 bytes, r4=20, r5=00403F0C,
SP=00403F00, LR=503B2484, PC=5032752C, CPSR=60000010 and request count0.
Original EUser disassembly places LR in User::WaitForRequest: r5 points to
the awaited status; r4 counts consumed unrelated notifications. This establishes
a pending completion, not the specific request or a generic CPU-speed cause.
The eighteenth captured word is not assigned a register meaning. Cross-thread
stack reads must respect EKA1 moving memory; canonical00403F00 cannot simply
be dereferenced from ViewSrv. Context returns an output descriptor pointer,
not a TInt status; v6 incorrectly skipped valid context and v7 fixes that guard.

Read-only donor history investigation found commit
b7380967c18f77675bc6402d0f608800382039df fixes Phone synchronous SIM reads
causing ViewSrv11 and makes Menu open. Relevant requests are09/60 ciphering,
09/21 provider display,09/33 network provider,09/13 SIM service table,09/31 ALS/CSP,
and1B/02 product profile. Commit f156ae6ac1e230bb1ddbe7e1a542750137e3d004
reports ready SIM state8 and security startup complete. Despite its stale
no-SIM comment, the donor actually models a logically inserted ready SIM.
It does not establish a registered network or fake carrier. QD payloads and
addresses need verification against our NEM-4 clients before reuse.

Native NEM-4 already contains09/60 serviceFA handler516621EC via method3504.
It dispatches an asynchronous operation via515FE084; completion51662240
translates status0/1/2 to24/30/31. Handler presence does not prove that its
operation completes on the board. Native SIM server gate5159B050 only routes
ordinary requests to their real handlers in serving state8; non-serving
states use fallback responses. Next identify Phone's actual pending request
and distinguish blocked native operation from rejected non-ready SIM queries.
No production RTL, ROM files, disk images or other chat simulations changed.

## Slow-wait trace follow-up (active)

V8 entry logging at one exact status address was too broad across processes
and became stale when Phone's stack layout shifted. V9 instead traces waits
on their twentieth unrelated notification, preserving the original ADD flags.
It captures RSessionBase::SendReceive -> RSubSessionBase::SendReceive with
IPC20/24 (hex). Original EFSrv confirms RFile::Write emits20 and RFile::Flush
emits24. This is a concrete alternative to the donor's TSY wait mechanism;
no particular file or ownership is established until the API caller is decoded.
The timing run is instrumented: repeated RDebug output adds overhead and cannot
measure uninstrumented latency. A context suspended in WaitForRequest alone
does not prove a permanently unanswered SIM query. V10 narrows to those two
IPCs and logs the RFile API and its caller using verified fixed wrapper frames.
Bounded CPU/ABI tests check matching, rejected scopes and original instruction.

V10 flush API503DF597 and caller508B7E85 identify EStor persistent-file-buffer
synchronization. Write API503DF417 is RFile::Write(offset,descriptor), whose
32byte local frame differs from the20byte non-positional variant: V10's write
caller field is invalid and must not be symbolized. Resident C:e588a32d...,
PMM:c29cf6dd... both captured with two equal reads. C extraction reads105entries,
68files and modifies no source bytes. Relative to restored working C, Contacts.cdb
and CntModel.ini are newly initialized and several settings files differ.

A subsequent guarded volatile initialized-C trial uses the same failure hooks
without the slow-wait hook, normal deadlines, original erased PMM and unchanged
card media. It still captures Phone ViewSrv11 in synchronous IPC24(hex),
RFile::Flush, status00403F54/SP00403F48. This rejects initialized-C alone as a
fix; it does not exclude storage latency as a contributor. Capture is
`scratch/menu-bringup-20261112/initialized-c-running.jsonl`; receipt and exact
ROM/C identities are next to it. Next matched PMM control uses identical ROM,
C and deadlines for both images; candidate differs only at11bytes within
record1830..1843, adding50/1 payload0400. No factory value claim.

Matched PMM control d3559287... (same six-hook ROM b74f13c5..., configured
16s/160s, original C, no slow-wait logging) reproduces native response23/05/11,
12byte frame, Nokia.dsy byte25 bounds failure and USER21. Thus simply loading
the formatted69record source does not remove the failure. Candidate comparison
is next. Original NOS state decoder accepts observed F4 as state8 and A4 as
state40; unusual raw bits alone are not evidence of a NOR programming defect.
Control capture/receipt: pmm-control-running.jsonl / pmm-control-applied.json.

Matched candidate completed150s/582snapshots without descriptor bounds/USER21
or ViewSrv panic under extended deadlines. The same base without50/1 reproducibly
panics, isolating the record's presence as the effective experimental difference.
Generated minimal PMM headers plus only50/1 failed early: debug stops after
TRtcQueue::Add2, CPU loops50324294..9C, first data fault VA00000AA8 at5167ED00.
Do not ship/repeat that minimal layout. Exact missing metadata/format dependency
is unproven. tools/ngage_pmm_profile.py instead requires the exact validated
native base d3559287..., preserves every existing byte and appends50/1; output
77e0e240... matches the successful trial exactly. DOS byte0 remains synthetic
policy, not a recovered factory default. Card save/reload still unverified.

V11 corrects the positional Write trace frame and restricts output to verified
EFSrv return sites; matching/nonmatching/flags/register tests and ZAP0/3wait
checks pass. Slow-wait hook is now separate and omitted by default. New340byte
native-SIM fallback tracer714ebf60... replaces only method pointers2FA978/
2FA958 and tails to their original Thumb methods with arguments/state intact.
It emits compact debug59 bytes through the existing kernel VA59000000 mapping;
board privilege/mapping remains experimental. Host instruction tests verify raw
method identities, bounded request-byte reads, both methods/states and ABI.
No SIM state or synthetic reply changes are part of this observer.

Native SIM observer is board-proven: Y SIM N052F1901 captures utid1,
request19/service2F in physical state5 at the non-serving fallback. This is
SIM Network method3360 (5166058C), which builds an8byte response1A with
3network bytes from515FCC68 and status mapping, not a naked UI state flag.
Existing fake IMSI001010123456789 supplies the matching test PLMN00F110.
No USER21 observed with the repaired native PMM. Direct debug59 VA writes
from this native path work on board.

Prepared848byte native virtual-SIM experiment137bf0b5... at audited zero
pad physical316A00 before ROM directory317000. It overrides only SIM's
non-serving method pointer2FA978 and the two native SIM_IND broadcast call
sites25EDC0/26196A. Original NOS owns all allocation/envelopes, response-id
lookup, send/receive queues and every other resource. Physical state5/6 is
retained; the selected logical profile publishes ready/no-PIN state8 and
answers IMSI, home PLMN, ciphering, identity comparison, SIM flags, optional
provider/service-table/ALS getters. Unknown getters return serving-unknownFA,
not no-card. No fake carrier/network registration/signal is implemented yet.
Host tests execute original response table, original send helper and both
original indication builders, with allocation/queue leaf spies;11 query cases
in states5/6, original nonselected-state fallback, request/envelope ownership,
callee-saved registers/SP pass. Raw encrypted call patches are re-encoded by
GF(2) inversion of the maintained descrambler, checked against original native
call targets, and decoded before executing the original producers in tests.
Full NEM-4 client acceptance and hardware behavior still require a run.

First848byte virtual-SIM hardware experiment8ac8cd63... answers home-PLMN
query with success (V R05012F19), with no first data fault or panic in the
bounded run; Insert SIM card persists. Neither intercepted indication builder
published a matching absent-state indication. Rewriting existing indications
alone is insufficient for readiness here. V2 explicitly publishes a native
SIM_IND8/no-PIN transition on first supported absent-state query, writes
SIM_Server state8, and overrides the11 audited native getter methods so the
serving gate continues to use the virtual backend. Physical SIMIF stays
absent; this selected logical profile now owns native server readiness.
Subsequent state8 queries do not generate another ready indication. Native
queue/envelope/allocation/send still run; all other methods/services retain
native code. V2 payload1056bytes8bc68a19...; host tests execute original send,
response table, and both original producers, verify states5/6->8, state8 replies
without duplicate indication and original nonselected-state fallback. Pending
hardware qualification; carrier/signal and normal deadlines remain unresolved.

V2 hardware publishes V I080B0DEF and then replies in serving8: IMSI
08012D1D, identity082AFA3B (twice), flags08013A2D/08013A2B and home
PLMN08012F19. User reports Device startup failed / contact retailer;
no first data fault, descriptor bounds or application/thread panic in capture.
This is progress past the absent-SIM gate, not a usable handset. Donor
PROGRESS-LOG around1057 documents exact note from self-test reply status12;
not proof that our native self-test has that result. Native DOS ordinal24
50FC16B4 publishes event1 via50FC16C0; ordinal50 50FC1950 publishes event100
(hex) via50FC195E. Prepared132byte observer7545714b... tails to original
event publication with unchanged id/value. Actual-wrapper baseline/patched
fixtures pass for both events, values0/1/2/3/12/255, aligned and unaligned
Thumb call patches, argument/flags/SP/return preservation. Pending board
result distinguishes self-test failure from other Startup rejection and
positively observes PMM read completion.

Native resource35 first reply is36bytes: body00030008 plus eight
subblocks0104{id}00, IDs13/2E/03/11/0C/0D/08/14. All list results and
header status are0; this is not evidence that these eight tests failed.
DOS event1 still becomes2 afterward. Native Nokia.dsy routes03 to50FC8A6C
(status0 requests next RUN phase),01 to50FC8B24 (status12 fails),59/02
to50FC8BDC. The asynchronous35/00 reply uses a separate send at51591A60,
not the observed first receiver send515919B6. V4 now observes both and
reads the original24byte St_func result array80024388 directly in CPU
context. Registry516F785C has16byte entries with test ID at+10 and
name pointer at+4; decoded map saved in selftest-registry.json. Actual
async callback, all five arguments, unchanged packet/results, pending
request/envelope cleanup and native producer tests pass. Pending board
capture distinguishes later API/status/test failures. No success substitution.

V4 captures the asynchronous RUN result: body00010C04 with four failure
subblocks: ID15/status1 LPRF_IF, ID02/status1 CURRENT_CONS, ID1E/status0D
RF_CHIP_ID, ID36/status1 ADSP. Registry IDs1E and36 have fatal severity0C;
Bluetooth/current entries have severity0A. Keyboard/LCD result array entries
are0. DOS event1 becomes2. These results are CPU-visible reads of original
array80024388, not stale host SDRAM. No failure value has been overwritten.

V5 adapts applicability to the selected virtual handset: only RF1E and ADSP36
startup-group bytes change2->0 at2F79A7/2F79C7. Their functions, IDs, severity
and explicit diagnostics remain. No physical RF/ADSP is provided by this
profile; native automatic tests should not require those absent components.
Actual native enumerator5164AD14 proves group1 stays13/2E/03/11/0C/0D/08/14;
group2 changes07/2B/15/02/1E/36 ->07/2B/15/02. Optional Bluetooth/current
failures are retained. Hardware outcome pending. Payload remains1348bytes
BAC0B4DC...; new record-manifest SHA A6228E2E... distinguishes the two-byte
registry policy from V4. All native SIM/send/indication, async callback,
ownership/result-array and applicability fixtures pass.


### V5 hardware result: usable Menu and Contacts

Native asynchronous response now contains body00010A02 with the retained
Bluetooth/current failures, while RF/ADSP remain unperformed. DOS event1/value3
confirms native startup acceptance. The startup animation finishes; F1 accepts
default time/date, Phone idle appears, Tab opens the real Menu grid, Right moves
to Contacts and Enter opens its empty contacts view. Screen evidence:
`scratch/menu-bringup-20261112/menu-first-working.png` and
`menu-contacts-working.png`.941 startup snapshots and352 interaction snapshots
have panic mask0/reset generation0; successful process exits are not panics.

Two identical read-only DDR captures each preserve booted C and PMM:
C SHA4a75e4cb75d5fb25c4148f888e3e4858e37841f97834df7a002d6f38ca15b329;
PMM SHA44679faaa2289cf4011eda0aea7ec763bc9be983047fe04331712c982da79826.
C extraction lists118 entries/79 files including system/bootdata/FirstBoot.dat.
Against repaired seed77e0e240..., PMM has326 changed bytes and zero0->1 bit
changes. Native date records D4/0,1,2 and group50/0 are appended, older records
retired and50/1 payload0400 retained. This positively verifies native programming
and record retirement; OSD/host persistence remains a separate unverified step.

This success uses16s/160s ViewSrv settings and synthetic ready SIM, with native
NOS serving/queues retained. It does not prove normal2s/20s deadlines or carrier
registration/signal. The guarded next experiment restores these booted images
only to volatile DDR after a fresh Hold load, keeps original deadlines and
omits the optional slow-wait tracer. No card image or source firmware is changed.


### Original-deadline restart: Menu confirmed

A fresh core Hold load receives captured initialized C4a75e4cb... and
PMM44679faa... only in volatile DDR. Ready-SIM V5, BT and six failure hooks
are applied with full-original-word/freshness/autosave-Off/image-hash checks;
no deadline edits and no slow-wait hook. ROM SHA:
0a847054e0498a6e9ef61bb12b140345b6d1b3296ed93dd4f92442c7f254f7c7.
Receipt: scratch/menu-bringup-20261112/menu-restart-normal-applied.json.
Native DOS startup passes; time/date prompts still appear despite FirstBoot.dat
(presence alone is not sufficient). Accepting both reaches responsive Phone idle;
Tab opens real Menu. Screenshot menu-original-deadlines.png. Bounded startup
and Phone captures have zero panic masks/reset generation and no PANIC or
DESCRIPTOR_BOUNDS at confirmation; exact sample counts in evidence JSON.

This is a combined ready-profile+initialized-disk successful restart with
original2s/20s. It does not isolate which difference eliminates the earlier
Phone ViewSrv11, nor qualify a clean/erased first boot with normal deadlines.
No perpetual timeout extension is needed for this tested path. Card files
remain unchanged; current running experiment is volatile. Native PMM programming
is verified separately from still-open host persistence/carrier/default packaging.

Builder now reconstructs backing from the original audited service containers
through service_firmware.parse/apply and checks the native NOS dump SHA. It
produces the identical A6228E2E... record manifest and passes all native ARM
SIM/send/indication/async-selftest/applicability fixtures after rebuilding.


### No-manual-patching production gate

The hardware success above is not a pure HDL fix: BT/SIM changes were injected
into volatile guest ROM and repaired/initialized disks restored before execution.
Original deadlines succeed, but automatic repeatability is not yet implemented.
User now requests normal boot without startup intervention. Automatic firmware
compatibility and strictly unmodified-firmware HDL are different designs;
clarification pending before choosing the production integration boundary.

`build_virtual_sim.py --production` creates a separate932byte payload, SHA
248f671cb93db2ec1b13aa8c1bf0bd1380dd689f0e92ccdd5bb4b00537c3da56,
record manifest5beb3351f92eccea06e996f87867f8851d1faa2ecb02bcf7ce2e1684017c660d.
It omits diagnostic MMIO and both self-test observer call patches. Readiness,
audited SIM replies and absent-RF/ADSP applicability policy remain. Native ARM
fixtures pass for both production and diagnostic variants; production async
fixture additionally asserts no debug writes and original send sites retained.
This variant is not yet board-tested or wired into default HDL startup.

Production SIM249 + BT590 records total839, exceeding one legacy640-record
staging table. Existing optional dual loader removal saved677.7 attributed
ALMs/14 M10Ks. A default solution must account for area and source identity,
block CPU release until complete, reject mismatched firmware, preserve existing
PMM/user data and pass cold boot without SSH/failure tracers/deadline edits.
A pure unmodified-firmware solution instead requires native SIMIF/RF/DSP/BT
behavior; moving ROM modifications into HDL would still be a firmware patch.
No such physical-peripheral qualification is implied by these service fixtures.
