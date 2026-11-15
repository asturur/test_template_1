# Recovered main-checkout investigation

Preserved from saved commit `d751692` during reconciliation into the original
`codex/ngage2-integration` branch. These are historical 2026-11-10/11 notes,
not a replacement for the latest [status](status.md). Original evidence and
checkpoint/memory documents are restored alongside this archive.

The old direct top-level `keys` C++ interface is superseded by the integration
branch's checkpoint-safe `ngage_sim_keys` command interface. Its implementation
remains recoverable from the merged commit; current host/testbench code is kept
byte-identical to `194b51d`. No running simulator or checkpoint is altered.

## Original saved status additions

## 2026-11-11: Stop requested; latest verified resume state is 10.5B

User requested stopping the long simulation for later resumption. Docker CLI
inventory and targeted SIGTERM both hung; direct local Docker API also failed
to respond. **Clean stop is unconfirmed; do not claim the container exited.**
Latest complete pair is
`build/sim/runs/latest-keypad-fast-12b/checkpoint-10500000000`:
CPU 42,317,877 bytes and host 230,416 bytes. Verified sizes and recorded SHA256
in `scratch/cleanup-20261111/resume-latest.json`. The 10.6B CPU `.partial` is
incomplete and must not be restored. Keep frozen executable/model
`6af112481fad51dd` and its manifest. Resume with `--use-saved-build`, normal
power-up, 78MHz, 26MHz timer clock, NOS64, 64-bit/1KiB ROM cache and line-refill;
canonical input paths/hashes are in the run manifest. Docker must respond again
before verifying container status or resuming. No firmware or C: changes.

## 2026-11-11: Second disk cleanup, lossless archives for retained history

Freed another 5.59 GiB: 5.26 GiB by verified lossless compression of old generated
simulator build sources/objects, large historical timing reports and retained
inactive checkpoint pairs; 0.33 GiB by deleting rebuildable unit-test object
directories. Binaries and manifests remain in place. The active 6af112481fad51dd
model and its run snapshots are uncompressed and untouched. Retained billion
states still exist, including compressed pairs supported by run-logo.py.
Before an old-model driver upgrade or schema comparison, expand that model's
`generated-build.tar.gz` into its containing directory. Historical `.rpt` paths
may now require `.rpt.gz`. Hashes, inventory and exact restore instructions:
`scratch/cleanup-20261111/{deep-archives.json,RESTORE.txt}`.

## 2026-11-11: Removed obsolete intermediate checkpoints and compiler caches

Freed 11.44 GiB (412 files): 7.18 GiB of intermediate checkpoint files and
4.26 GiB of rebuildable precompiled headers. Preserved every existing exact
billion-cycle checkpoint, the latest completed 10.5B pair, its 6,001,000,019
import source, and the 4.7B memory-benchmark replay source. Left partial writes,
executables, compiled source archives, logs, screenshots, firmware and C: alone.
Historical non-billion replay paths may now refer to deliberately removed files;
check existence before selecting a replay. Inventory and removal script:
`scratch/cleanup-20261111/{plan.json,removed-files.json,cleanup.py}`.
After cleanup: build 5.2 GiB, scratch 4.1 GiB (rounded disk usage).

## 2026-11-11: Saved old-core memory performance baseline

[Memory performance baseline](memory-performance-baseline.md) collects 72 metrics
and the nine ROM-buffer configurations for comparison with the replacement core.
The accompanying JSON keeps measurement boundaries, profiles, source identities
and evidence hashes. Historical fixtures and physical-controller measurements
remain distinct. Added an isolated production-TLB fixture: main-table hit takes
3 sampled edges, section walk 7 and small-page walk 10 with its registered
synthetic descriptor bus. The 64 entries compare in parallel; physical descriptor
fetches add backend latency. Raw output and the repeatable runner are retained.
No production RTL, firmware, C: image or running simulation was changed.

## 2026-11-11: Requested status at8.98B, new LCD activity, Nokia still visible

latest-keypad-fast-12b at8.98B/12B, overall92776cycles/s, data_errors0,
buserrors30923398 unchanged. LCDwordcount38104 versus36760 at7.74B.
Viewed latest8.9B framebuffer screenshot:still NOKIA white. Current workload
not sampled this turn. Roughly9hours to12B at current host rate. Main run
continues unchanged. Historical LCD console cycle fields are signed32bit and
wrap; use checkpoint/progress64bit counts for chronology.

## 2026-11-11: 7.7B workload shifts to file service and application startup

31 process entries versus 23 at 7.3B. New threads include Phone, ScreenSaver,
Autolock and MsvServer. EtelServer is in a request wait at the snapshot.
Separate 2M replay: EFile main 9,398 of 15,625 samples (60.1%), SystemAgent
1,019, Autolock 976, window server 618. Zero C: transactions or changes.
Autolock and ScreenSaver home stacks contain uikon_init path context.
Starter still queues on its owned request semaphore 8040f37c. The exact
request that will wake it and EFile's dominant operation are unidentified.
ScreenSaver thread presence alone does not establish a rendered screen.
Live run at 7.74B reported unchanged LCD word count and zero data errors.
Evidence: scratch/current-work/{state,profile}-7700.log.

## 2026-11-11: 7.3B workload is telephony and the file server

At 7.43B the live run still reported 36,760 LCD words and zero data errors.
In the separate 2M replay from 7.3B, EtelServer took 9,035 of 15,625
current-thread samples (57.8%), EFile main 6,496 (41.6%), Supervisor 94.
ROM headers place the main telephony PC regions in phonetsy.tsy. There
were zero C: bus transactions and no change to C: within this sample.
PhoneServer, SysAp, and adspserver are present. Starter's wait object
is now 8040f37c, after its earlier wait on UI-start semaphore 8040cd8c.
The exact telephony operation and current Starter dependency remain unknown.
Evidence: scratch/current-work/{state,profile}.log. Long run left running.

## 2026-11-10: AppArc completion proven; user waits2hours, no monitoring

Investigation COMPLETE: AppArc is NOT stuck in its observed startup phase.
Targeted replay catches UI ApsExe two-status wait return at6,525,847,945:
statusA0(success),statusB80000001(pending). Initial recognizer pass finishes
17/17; later C:/D: Recogs scans return-12(path absent), Z: pass enumerates17
successfully and ends6,520,041,406. No more recognizer starts through6.55B.
Three starts/four returns include one pass started before6.5B. No patch warranted.

Starter's named UI-ready semaphore remains pending, but the old AppArc wait is
over; current UI proceeds through Bafl/Cone/avkon resource initialization.
Separate6.6B+3M:60bit-packed decoder calls return, all60output pointers advance,
no backward outputs. No missing mandatory component or lost AppArc completion
proved; later errors remain possible. Detailed evidence/corrections in
symbian-startup.md and scratch/latest-continuation/ logs (.full.log.gz retain
original console, filtered logs small). No new HDL/firmware/C change/build.

Main latest-keypad-fast-12b model6af112481fad51dd remains running untouched,
100M screenshots/checkpoints, permanent billion pairs. User says check back in
about2hours: STOP ACTIVE MONITORING, do not start another investigation or
schedule a reminder without request. Latest requested progress6.66B; errors
30923398 unchanged/data0.7B clocks at78MHz=89.7s (104MHz=67.3s).

## 2026-11-10:6.5B UI-start barrier identified; AppArc dominates

New6.5B screenshot viewed:still NOKIA white. Main latest-keypad-fast-12b
continues unchanged (6.54B last requested read), no new errors/data faults.
19process entries now (C32exe,Ealwls,MediaServerStub added since6.3B).
Separate exact-model3M: AppArcServerThread98.44% of current-thread samples,
Supervisor1.36%,Loader0.20%; no C transactions or C changes in sample. Prior
6.2B database attribution is no longer the dominant current workload.

StarterServer waits on EikAppUiServerStartSemaphore8040cd8c: countFFFFFFFF,
reciprocal queue links point to Starter wait link8040f20c. EikAppUiServer also
waits for an unidentified async completion on its owned semaphore80411b18.
AppArc saved/live stack context references rmrecog.mdl,MusicRec.mdl and
MediaServerStub.exe; selected request-status wrapper returns0 at observed
completions. This narrows persistent-logo explanation to UI startup readiness
while AppArc registry/recognizer work runs, not a demonstrated LCD hang or
failed loader. A completed pass/repeated rescan is NOT proven in3M clocks.
Next trace the AppArc completion and named UI-start semaphore signal. See
symbian-startup.md for exact objects/limits, scratch/latest-continuation/ logs.
6.5B checkpoint hashes and prior code dumps verified intact. No main-run key
injection, firmware/C modification, hardware build or donor-code porting here.

## 2026-11-10: Donor integration chat moved to its own worktree

Porting work and merge-plan.md moved to
/Users/andreabogazzi/.codex/worktrees/ngage2-integration/NGage_MiSTer,
on codex/ngage2-integration. This original checkout is back on master for
ongoing startup/simulation work. Its pre-existing dirty files, ignored data
and running simulations were preserved. No port implementation or build.

## 2026-11-10:6.3B screen still Nokia; startup advanced to16process entries

Requested new-screen/why-logo investigation COMPLETE for this sample. Main
latest-keypad-fast-12b left running unchanged. Newly generated6.3B framebuffer
viewed:still NOKIA white; latest checkpoints/screens every100M work normally.
Exact-model state readers:15process entries at6.1/6.2B (new EDbsrv,Sysagx),
16at6.3B (new EikSrvs). FSR/FAR/ABT LR0; data_errors0, errors30923398 unchanged.
Changed C positions vs original323489->336991->339353. This is startup progress,
not proof of filesystem correctness or completed UI; no fixed logo loop proven.

Separate exact-model3M from6.2B: EFile46.10%,NULL42.06%,EDbsrv8.60%,Rfs2.55%
thread samples (includes kernel work). C bus active1.02%,DDR busy2.80%;1037C
positions changed. Correct Rfs home/stack references cdbv2.dat/.old and factory
ScriptInit; strings may be residual, not current-operation proof. Work is now
in filesystem/database startup, but single blocking IPC not identified. Next
trace Rfs/database/UI request completion as EikSrvs starts, rather than assume
LCD hang. No new HDL or image patch. Main6.2B checkpoint hashes verified intact.
Detailed evidence/limits added to symbian-startup.md; logs/readers under
scratch/latest-continuation/. No hardware build monitoring performed.

## 2026-11-10: Faster run6.21B; screensaver state not reached

User prioritizes possible key-press crash reproduction, references a working
core for later reuse (not yet identified). One requested status check:
latest-keypad-fast-12b at6.21B, ~93354cycles/s overall, errors30923398 unchanged,
data0. Latest6.2B CPU/host and screenshot exist; framebuffer visually verified
still NOKIA on white. No matching hardware clock-screensaver checkpoint yet;
key injection now supported, but testing it here would not reproduce the same
hardware starting state. Main simulation left running unchanged.

## 2026-11-10: Replaced old long run with latest keypad/fast continuation

ACTIVE run latest-keypad-fast-12b, session80718, model6af112481fad51dd,
container7f268c6ba36dc97d83345cb26a6d3e607253b145dc6c6c68730d26a7be49ffcb.
Target12B; starts6,001,000,019 from a verified separate1M accelerated replay.
Same78MHz phone/26MHz timers/NOS64Hz profile and unmodified original images;
LINE_REFILL1, ROM cache64bit/1KiB, stats enabled. New model has e4c897e keypad
W1C fix and controllable top-level keys (idle0), rather than previous constant0.
Phone/CPU source is current3f5e8ae memory implementation plus simulator-only
key input/pulse controls. Native scalar SDRAM backing remains fast harness;
physical short-read controller was separately verified, not instantiated here.
Logs scratch/latest-continuation/long-launch.log and run progress.log; automatic
100M checkpoint pairs/screens, every billion preserved. No hardware build or
source firmware/C edits in this turn.

Migration: preserved permanent old6B checkpoint, advanced19clocks using exact
olda6d4 archive to quiescent CPU/cache/TLB/write-buffer/bus/flash/DDR state.
Imported into current model by audited names (2254common values exact, memory
arrays included); newly active line state idle, preferred-data1, keys/history0.
Removed pc_nxt_tmp is a combinational next-PC temporary, verified in zap_writeback;
other removed fields are existing combinational aliases. Two combinational
readbacks normalize differently in zero-clock observation; no architectural
state loss. Refill-disabled latest33305fa2a1161a8d control after1000clocks matches
all2255 common named fields AND host bytes against exact old replay. Accelerated
1M completed with errors30923398 unchanged/data0; Nokia image remains. Not a
cold boot or generic checkpoint-format compatibility claim.

Full-phone disposable Menu input probe PASS: keys_d64->0, pending0->4. Existing
matrix/board/shared-W1C/protocol tests PASS. No key injected into main continuation.
Optional direct observer args +key-mask=<mask> +key-start=<absolute cycle>
+key-duration=<clocks> enable separate future replay pulses; keep stimulus in
replay provenance. Initial inactive key state0 is recorded in imported snapshot.

After replacement confirmed active, exact old container480727160d1a receivedTERM
and stopped cleanly at6,012,313,492 with final CPU/host pair/result/screens saved.
Old6B permanent and all earlier billion pairs retained. Original model/build
archives kept for rollback. No further monitoring requested. Evidence and
migration scripts/reports scratch/latest-continuation/; source old quiescent
quiet6000.cpu/.host and per-model manifests latest-{on,off}-source.

Hardware checkpoint review COMPLETE: current RBF has NO resumable CPU-state
export. Diagnostic captures512words; working save exports C:/PMM only; CPU Hold
asserts reset. Static interface review establishes absence, not a physical
capture experiment. New precise halt/quiesce, internal BRAM/register readout,
versioned state file and simulator importer are feasible but substantial work.
See hardware-checkpoints.md; implementation and board round-trip unverified.

## 2026-11-10: Long-run status check at5.96B; still Nokia image

User asks whether a screensaver checkpoint exists for keypad tracing. Current
panic-owner-fixed-12b progress5,960,000,000/12B, ~85,104cycles/s overall;
fetchPC50328478, LCDwords36760, data_errors0, buserrors30923398 unchanged.
Latest complete CPU/host pair checkpoint-5900000000 (40MiB/225KiB) exists.
Viewed its framebuffer screenshot: NOKIA on white, not N-Gage/clock screensaver.
No matching screensaver checkpoint established yet. Modela6d40d0d5005ce63,
78MHz phone parameter,26MHz timers,NOS64Hz; frozen run predates the new line
refills and keypad W1C fix. Do not claim current hardware reproduction or
apply current RTL to its checkpoint without an audited separate fork.
Screens build/sim/screens/panic-owner-fixed-12b-checkpoints/; main run untouched.
