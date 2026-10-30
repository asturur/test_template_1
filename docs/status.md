# Development checkpoint and resume guide

## 2026-10-30 ROOT CAUSE FIXED: CTR assoc=0 made EKA1's clean-cache loop endless (update made with Claude)

The post-EStart "idle" was the Supervisor stuck in EKA1's clean-D-cache-by-
index loop (0x50328408, MCR p15,0,R1,c7,c14,2). ZAP's cache type register
(0x03142142) reported assoc=0 (direct-mapped), so the loop's way increment
(1 ROR assoc) was literally +1 and its ADDS/BCC carry exit needed 2^32
iterations (~1.7e14 cycles; trace: outer counter at 0x17 after 18M idle
cycles; a 2.5e9 run confirmed true deadlock). All the while EStart-Main sat
READY in the queue (prio 350, FileSrv 760, resched flag set) - see the
correction entry below. Fix (patch 0009, commit 0164a87): report the real
ARM920T CTR 0x0D172172 (assoc=6, ctype=6) in zap_cp15_cb.sv; ZAP executes
any index clean/inv as a whole-cache op, so only the software-visible
geometry changed; the loop now terminates after 8 sets x 64 ways = 512 MCRs.
The only CTR read in the whole boot is the fatal one at cycle 1112551742,
so the timeline up to there is unchanged.

## 2026-10-30 TRUE FRONTIER: EStart mounts a filesystem, reads it fully, then blocks at ~1.5176e9 (update made with Claude)

Tracing the estartfinal window (from-reset, 1125M-1134M) showed EStart's last
code (PC 0x503eec28, cycle 1126179781) calls efsrv!RFs::MountFileSystem ->
RSessionBase::SendReceive to the file server, which runs CServer::RunL /
CFileSystem::SetLibrary / CMountCB and then does sustained medint +
TBusLocalDrive::Read - EStart is MOUNTING a second filesystem and reading it.
The longboot run (resumed, C:-byte-read fix active) confirms: C: flash is
accessed with ADVANCING addresses (134256 distinct) up to cycle 1517595533,
including the byte-read at 0x024214dc (be=0x2) which the fix serves correctly,
followed by a fresh command sequence (0x02400aa8<-0xaa). Then C: access STOPS
at 1517595533 and the system goes PURELY IDLE for the next 3.48e9 cycles
(timer/NOS-stub/keypad polling only, no C:, no 4th process) to the 5e9 budget.

So the real block is at ~1.5176e9, AFTER the mount+read: EStart issues one
last C: command then blocks, and no window server is ever launched. This is
well past every prior frontier. A windowed instruction run (boot-v15-mountend,
1515M-1521M from fresh-c1250) is in flight to capture the exact failing F32
operation at that point. NOTE the prior "idle at 2.2e9/3.5e9" checkpoints
(idle-c2200/c3500) and the whole "NOS waiter" investigation were looking at
this same post-mount idle from the wrong angle - ord252 idling is the SYMPTOM;
the cause is the F32/medint operation that completes its read then never
advances EStart. fresh-c1120 and fresh-c1250 are the clean resume bases.

## 2026-10-30 CORRECTION: ord252 is the NULL-thread IDLE loop, not a boot waiter; 0x800004ac is an idle CALLBACK pointer (update made with Claude)

Experiments falsified the "NOS readiness waiter" theory below. Three from-reset
probes that set *(0x800004ac) from a patched NOS stub all crashed the kernel:
the fault PC 0x50331b78 is the return of `MOV LR,PC; MOV PC,r3` at 0x50331b70
- the kernel CALLS *(0x800004ac) as a FUNCTION POINTER (fake value 1 = jump to
address 1 = prefetch abort -> kernel crash-dump handler ekern!ord470+0x298,
which records super-page fault state to debug registers 0x0c0047f0/f4/f8 then
self-loops - that is the 0x0c0047f4 "unmapped" stop). And the loop at
0x50331a60-0x50331bb0 ALWAYS branches back: it never exits. Reading EKA1
semantics: ord252 is the NULL/idle thread loop - each iteration invokes the
Variant's Idle method (vtable+0x48 with r1=0xd) and then any registered IDLE
CALLBACK in 0x800004ac. The "infinite spin" is NORMAL IDLING. The synthetic
NOS stub patch was reverted (pristine blob restored, rebuilt).

So the real frontier is back to: WHY does EStart's F32 request at ~1126.2M
never complete? EStart's last act (estartwin trace) is BL 0x503ef4d0 (an
efsrv import thunk) at 1126179781 after large C: reads; from then on the
system idles with EStart blocked (state 2), FileSrv parked in its CServer
loop, LoaderThread parked. A full-instruction window 1125M-1132M
(boot-v15-estartfinal, from fresh-c1250) is in flight to capture the exact
request and the file server's handling of it. The crash-dump debug registers
0x0c0047f0-f8 are a diagnostic gift: any future kernel fault writes the fault
state there (worth modeling as a latch to capture panics instead of stopping
on unmapped access).

## 2026-10-30 DEEP FRONTIER (fully characterized): kernel boot-waiter spins on NOS Variant iface #13 readiness (SUPERSEDED by the correction above - the "waiter" is the idle loop) (update made with Claude)

After the CTR + C:-byte-read fixes the boot runs to a kernel busy-wait that
never completes; at 3.5e9 cycles (idle-c3500 checkpoint) still only 3
processes (EKern/EFile/EStart), no window server, no logo. Mechanism, fully
disassembled:

- The hot loop (6.5M transitions in a 6M-cycle window at 2.84e9) is ekern
  ord252 at 0x50331a50-0x50331bd4 <-> the synthetic NOS stub at VA
  0x5149d18c. Each iteration: re-load the Variant singleton ([0x8000038c]),
  call its iface #13 method (r1=0xd, vtable+0x48 -> stub 0x5149d18c, a
  zero-fill-and-return-0), then check kernel global *(0x800004ac); if 0,
  BL 0x50323c74 (yield/reschedule) and B 0x50331a60 (loop). Cooperative
  busy-wait - that is why ReclaimThread also runs and the box looks "idle".
- Global 0x800004ac stays 0 at 1.25e9 AND 3.5e9. It is written only by ekern
  ord374 (trivial setter at 0x503452d8: STR r0,[0x800004ac]; BX LR), which
  is reached via a function pointer (no BL callers in ROM) - i.e. the real
  NOS/variant init calls it to publish readiness. The synthetic NOS stub
  (scratch/boot-v15-nosprobe/nos_stub_blob.h, 648B at PA 0x9d000) REGISTERS
  ifaces #3/#6/#13 with the Variant (calls vtable+0xfc three times, each with
  iface vtable 0x5149d180) but never drives the readiness, so ord374 is never
  called and the waiter never exits.
- The waiter's non-zero path (0x50331a98+) passes *(0x800004ac) to
  0x503222e0 as a meaningful pointer/handle, so a blind fake value risks a
  kernel fault; the correct value is whatever ord374 would publish.

This is the project's long-flagged "synthetic NOS is not authentic baseband"
wall, now reached at a concrete, named kernel waiter. Candidate approaches
(next session): (1) extend the NOS stub's registration code to call ord374
with a valid readiness object after registering iface #13 - needs the right
object/value, which means RE'ing what ord252's non-zero path consumes;
(2) model the NOS/variant readiness event at the board/channel boundary
(ngvm answers the analogous NOSDRIVER ISI energy-mgmt exchange in
sw/kernel/chan.c - charger 0x17/0x08, battery 0x17/0x0A, identity 0x1B -
which its notes say gate the first screens); (3) obtain real descrambled NOS
plaintext (exists in no available file). Resume base: build/sim/checkpoints/
idle-c3500 (post-fix model). ekern.def names ord252/ord374 as internal
(not SDK exports), so those names are positional, not from the import lib.

## 2026-10-30 NEXT FRONTIER: EStart runs then blocks in its process-launch loop (superseded by the NOS-waiter entry above) (update made with Claude)

After the CTR fix + C: byte-read fix, EStart EXECUTES (estartwin: first PC
0x503ee8c0 @1112783076, 26 module transitions through 0x503eec28 @1126179781)
and then BLOCKS. idle-c2200 checkpoint (cycle 2.2e9): still only 3 processes
(EKern/EFile/EStart) - EStart never spawns the window server. EStart-Main
NThread state byte went 4 (ready, @1.25e9) -> 2 (blocked/waiting, @2.2e9);
its saved-SP is 0 and its stack+code chunks (0x804099c8 home=0x00502000,
0x8040977c home=0) live in LOW process-relative VAs, so the kernel-home
checkpoint reader can't walk EStart's user stack. EStart's blocking site is
its startup loop at 0x503eec08-0x503eec3e: iterates a list (r7 += 0x10),
calls 0x503ef4c4 / 0x503ef4d0 / 0x503ef4dc per entry - this is EStart reading
its boot config and launching the next servers; it blocks in one of those
calls (likely a Rendezvous/logon on a child it launches, or an RProcess
create that needs a loader step). NEXT: trace EStart's process space across
0x503ef4c4-4dc (need an FCSE/PID-relative reader, or just a full-instruction
window 1126.0M-1130M filtered to EStart+loader+new-process execs); cross-ref
ngvm, whose EStart launches ~12 servers cleanly to the logos. The LLE is now
~1.0e9 cycles past where it stood at session start (767.8M crash -> EStart
executing + blocking deep in its launcher).

VERIFIED (2026-10-30 ~02:05): post-fix run boot-v15-ctrfix reached 1.5176e9
(267M past the old frontier). estartwin window trace shows EStart EXECUTING
from cycle 1112783076 (first PC 0x503ee8c0, 26 module transitions). At the
1.25e9 checkpoint (fresh-c1250): current thread = FileSrv Main running,
StartupThread exited+reaped, EStart-Main READY prio 350 - matches the ngvm
oracle. ctrfix then stopped on a NEW frontier: byte read (byte-enable 0x2)
of C: flash at PA 0x024214dc refused by the halfword-only model. Fixed in
boot_profile.cpp (array-mode reads of any width serve the aligned word;
writes keep the halfword command protocol; tests added). Resume boot-v15-
postbyte (fresh-c1250 -> 3e9, checkpoint at 2.2e9) is in flight.
TODO (queued to avoid touching inputs mid-run): load_state() re-applies the
pristine cdrive-image over the RESTORED overlay - harmless while
cdrive_writes=0 (true through 1.5176e9) but will corrupt post-first-write
checkpoints; apply image only when the checkpoint overlay is empty.

IN FLIGHT (2026-10-30 ~01:40, superseded by the entry above): (1) boot-v15-ctrfix - from-reset, budget 3e9,
checkpoint fresh-c1250 at 1.25e9, screen capture at end (run-fresh.py);
(2) boot-v15-estartwin - from-reset, budget 1.15e9, module-trace + full
window 1112.5M-1115M across the expected clean-loop exit -> reschedule ->
EStart first instructions (run-fresh-mt.py). Old checkpoints deleted (bound
to the pre-fix Verilated model). ekern.def (244 names, from the SDK WINS
import library, UNVERIFIED wins-vs-marm ordinal parity) added to
build/ngage-defs. SDK extracted at build/sdk-extract (Binaries armi/thumb
libs kept; regenerable: unshield x firmware/nS60_sdk_v1_2/data1.cab).

## 2026-10-30 CORRECTION + real frontier: EStart process+main-thread ARE created and RESUMED; the main thread never becomes READY (update made with Claude)

Checkpoint forensics (idle-c1130.host, cycle 1.13e9) OVERTURN the prior
"Resume never reached / LoaderThread never wakes" diagnosis below. Evidence:

- 7 real DThreads exist at idle (vtable 0x50347598): Supervisor, NULL,
  Main(FileSrv 0x804070bc), LoaderThread (0x804075dc), StartupThread
  (0x8040798c), ReclaimThread (0x80409238), and a SECOND "Main" at 0x8040983c.
  That second "Main" is EStart's main thread (every process main thread is
  named "Main"; ngvm shows it as "EStart:Main"). So the loader DID create
  EStart's process + main thread. Thread container array at VA 0x80405200.
- Full-instruction trace (frontier2) shows StartupThread run euser!RProcess::
  Create (returns OK at 1112396138 -> valid handle, no panic) then euser!
  RProcess::Resume at 1112396484 (SWI exec 0x1D). The kernel resume handler
  runs real scheduler code (ekern ord150/ord327 reschedule, CObjectIx::At,
  TDblQueBase::IsEmpty). So Create AND Resume both happen.
- Yet EStart user code (0x503ee8xx, XIP in ROM) is NEVER fetched, and at idle
  the current thread (kernel global 0x800003d0) = NULL (0x80406c48). So EStart's
  main thread is resumed but never scheduled. StartupThread even CONTINUES after
  the resume (would not, if a higher-prio EStart had been made ready+preempted).

So the real gap: RProcess::Resume does not make EStart's main thread READY.
Checkpoint field anomalies on EStart-Main (0x8040983c) vs healthy FileSrv-Main
(0x804070bc): +0x20 = 0x80000000 (vs 0x8000000c), stack/addr +0x30/0x34 =
0x00502000 (vs kernel-region 0x80602000), +0x38 = 0 (vs 0x80601ccc). EStart's
DProcess (0x80409614) has +0x20 = 0 where FileSrv's DProcess (0x80406eb8) has
0x100000bb (likely a code-seg/chunk pointer) - EStart's process load looks
incomplete. Working hypothesis: EStart-Main is left SUSPENDED (count not 0) or
WAITING on code-seg load completion that never fires, so Resume (clears suspend
only) doesn't ready it. EKA1 DThread field offsets are not from the SDK (public
headers omit the private layout); offsets above are empirical, not gospel.
NEXT: trace the loader's EStart process/chunk/main-thread CREATION window
(Loader active 1112244857-1112285321, inside frontier2) to find the incomplete
step; or decode the suspend-count/wait-state field. Tools: inspect_checkpoint.py
(now reads idle-c1130), run-resume-ckpt.py (resume+checkpoint), ngvm oracle.

## 2026-10-29 Frontier settled: pure kernel idle - no user thread becomes ready after the EStart launch (update made with Claude) [SUPERSEDED by the 2026-10-30 correction above: EStart IS created+resumed]

Extended trace past the launch (frontier3, 1112.5M-1114M): the system settles
into a PURE KERNEL idle - only ekern functions, woken every ~404K cycles by the
timer-tick IRQ (vector 0x18 at 1113732286; tick period 0x632ea), running the
null thread. NO user thread runs: LoaderThread (0x503d3539) and EStart
(0x503ee860) have ZERO hits across 1.5e9 cycles. So after StartupThread's init
completes and it launches EStart (User::StartThread + UserSvr::BlockThreads),
every user thread is blocked/suspended and none becomes READY - EStart is
created but never scheduled, and the LoaderThread never wakes to load it. The
scheduler ticks but has no ready user thread to run.

ngvm (oracle) does this correctly: its LoaderThread runs, loads EStart, EStart
runs and EXITS cleanly (it is the transient launcher), then ~12 servers start
(EwSrv window server, ViewServer, AppArc, EtelServer, Watcher...) -> UI/logo.
So the LLE gap is ONE kernel step: making the newly-launched EStart (and/or the
LoaderThread) READY so the scheduler runs it. This is EKA1 thread-resume/
scheduler behavior; the LLE kernel is unsymbolized (no ekern.idt), so pin it by
cross-referencing ngvm's thread-resume path and/or finding the missing kernel
event (a resume/IDFC the real kernel needs). That is the next and possibly
last major gap before the user-side cascade to the logo.

Progress recap: LLE went 767.8M (blank-C: crash) -> 1.11e9 (EStart launch) via
the ngvm 4 MiB formatted C: image; tooling = ngvm oracle, IDT symbols,
cdrive-image, symtrace. mount-c760 is the resume base (checkpoint-at from a
restore does not write - minor; resume+trace from mount-c760 works).

## 2026-10-29 Frontier pinned: EStart is LAUNCHED but never scheduled (update made with Claude)

Deep-dived the ~1.11e9 block with IDT symbols. Sequence: StartupThread's init
state machine (efile!ord3, 0x503d5290) COMPLETES successfully (returns R0=0 at
0x503d54fe, sets its done-flag), then StartupThread calls euser!User::StartThread
+ euser!UserSvr::BlockThreads - the EKA1 thread-launch of the next process
(EStart). The kernel does the creation work (CObjectCon/CObjectIx::At container
mgmt, CBitMapAllocator page alloc - normal, not an infinite spin; IsFree hit
only 10x on page 0x8a). But EStart's code (0x503ee860) NEVER executes and the
LoaderThread (entry 0x503d3539) never runs in-window: EStart is created and
never scheduled. So the frontier is now the EStart thread start/schedule, not
the C: mount (solved) or the state machine (done).

The remaining question is why the newly-started EStart thread doesn't get
scheduled (a kernel scheduler/thread-control step needing a modeled event, or
BlockThreads not followed by the unblock). The LLE runs the real EKA1 kernel
(unsymbolized - no ekern.idt); ngvm (HLE kernel) schedules EStart fine and
reaches both logos, so it is the comparison oracle. NEXT: cross-check the
StartThread/reschedule path against ngvm, or model the missing kernel event,
to get EStart running -> window server -> LCD -> logo in the LLE screen.png.

## 2026-10-29 New frontier: the LOADER is loading EStart (blocked mid-load ~1.11e9) (update made with Claude)

Symbolized the ~1.11e9 block (IDT names): the last F32 work is mount-control
(efile CMountCB/CFormatCB::CheckMount), and crucially the LOADER is active -
euser!TLoaderInfo runs at 1.1116e9/1.1121e9 and ROM-tail reads (process image
bytes, 0x04730xxx) run to 1.1115e9. So EFile::LoaderThread is mid-load of a
process (EStart, from ROM) and blocks before completing it; EStart code
(0x503ee860) NEVER executes. The block is the EStart LAUNCH - the loader waits
on an async op (WaitForAnyRequest) during the load. This is the gap between
F32-up and the user UI, the same spot that matters for the logo.

Progress this session is enormous: LLE went from crashing at 767.8M (blank-C:
KErrCorrupt) to loading EStart at 1.11e9 (+343M), via the ngvm-produced 4 MiB
formatted C: image. Checkpoint mount-c1111 being written for fast iteration on
this frontier. NEXT: pin the loader's exact wait (resume mount-c1111, trace the
TLoaderInfo load path, find the async completion it needs - a drive read DFC,
a memory op, or an IPC), model it, and EStart should launch -> window server ->
LCD -> logo. Validate against ngvm (which loads EStart and reaches both logos).

## 2026-10-29 LLE boots +343M past the C: crash to a new F32/LFFS frontier ~1.11e9 (update made with Claude)

With the 4 MiB formatted C: image the LLE runs from the old 767.8M crash to
~1,112,551,000 (+345M cycles). Module presence 760M-1.12e9: heavy medint
(299K insns, the flash-driver data loop 0x50386628.. hit 29867x) and ELocal
(121K, LFFS), plus EFile/EFSrv/EUser - i.e. the file server exercising the now-
valid C: volume. C: read activity runs to 1.108e9; last distinctive op a WRITE
0x0c120c14 at 1.1123e9; then the EUser(0x5039cb1c)<->ekern(0x503288d4) idle
loop. So a thread blocked AGAIN, still in the F32/LFFS phase - EStart and the
window server have NOT launched yet. Same discovery pattern as the earlier
frontiers, one big stage deeper. cdrive_writes=0 (the mount succeeded on the
valid volume; the firmware has not written C: yet).

The C: unblock is confirmed solid (ngvm HLE reference + 4 MiB formatted image).
NEXT: symbolize the ~1.11e9 block (what StartupThread/F32 waits on now - likely
the next LFFS/F32 step or the EStart launch), write a checkpoint near 1.11e9
for fast iteration, and continue. Cross-check against ngvm (which boots fully)
for what should happen next.

## 2026-10-29 *** LLE PAST THE C: CRASH: 4 MiB formatted LFFS image mounts *** (update made with Claude)

Got a VALID 4 MiB formatted LFFS image by temporarily enlarging ngvm's C:
(NGVM_SAVE_BASE 0x01C00000 / SIZE 0x400000 in ~/develop/n-gage sw/include/
ngvm_hw.h, rebuild kernel, run ngvm --save, revert) -> build/firmware/thc/
cdrive-formatted-4mib.img (64/64 blocks have LFFS_MAGIC 0x503B3B60). The LLE
model now loads it via opt-in cdrive-image= (boot_profile: image loaded in ctor
AND re-applied after load_state so it survives checkpoint restore - a 1 MiB
image failed because our LLE volume is 4 MiB; size MUST match medint's reported
size). Resume from mount-c760 with the 4 MiB image: StartupThread SURVIVES the
mount (cdrive_writes=0 = mount succeeded on the valid volume), boot runs PAST
the old 767.8M KErrCorrupt death, actively reading C: at 769.99M. The C: crash
is SOLVED for the LLE.

Mechanism: our LLE firmware's LFFS, unlike ngvm's formattable HLE drive, does
NOT auto-format a blank C: - it needs a pre-formatted volume. ngvm (fast HLE)
produces one by letting the firmware format its formattable drive; we feed that
formatted image to the LLE. run-resume-760.py / run-stub.py now carry
cdrive-image=.../cdrive-formatted-4mib.img.

NEXT: run the LLE long (2-3e9) to see how far it boots now (EStart, window
server, the LCD path -> Nokia/N-Gage logo in screen.png). Validate against the
ngvm reference frames (build/sim/screens/ngvm-milestone/).

## 2026-10-29 *** MILESTONE: HLE reference boots OUR firmware to NOKIA + N-GAGE logos; formatted C: extracted *** (update made with Claude)

Built and ran the Pocket core's ngvm (Unicorn ARMv4T HLE: NGVM C kernel +
our user firmware) on OUR SYM.ROM:
  python3 ~/develop/n-gage/tools/ngvm/ngvm.py --rom /tmp/ngage_sym.rom
    --kernel ~/develop/n-gage/build/kernel/kernel.elf --save <c.img>
    --seconds 12 [--frames-to DIR --frame-every 60]
Result: FULL boot. Dozens of servers up (EwSrv/EikSrvs window server, AppArc,
SystemAgent, Phone, C32 comms, Starter, FbServ, EFile...), and the captured
frames show the authentic NOKIA logo (~5 s) then the N-GAGE logo (~11 s) -
saved build/sim/screens/ngvm-milestone/{nokia-logo-5s,ngage-logo-11s}.png.
So OUR firmware + ROM are correct and boot to the logos; the block was never
the firmware.

KEY for the LLE: ngvm presents C: as FORMATTABLE flat memory, so the firmware
FORMATS the empty C: itself (3124 writes) and ngvm saved the resulting VALID
formatted LFFS (1 MiB, every 64 KiB block word[1]=0x503B3B60 LFFS_MAGIC) ->
build/firmware/thc/cdrive-formatted-1mib.img. This is exactly what our LLE
needs: our LLE crashes because its C: is blank/unformatted and (unlike ngvm)
not auto-formatted. Prebuilt tools now available: ngvm (bootable HLE
reference), romsyms+IDTs (names), the formatted C: image.

NEXT (LLE boot past the C: crash): either (a) pre-fill the LLE cdrive_ overlay
with a formatted LFFS image - but size must match what our medint reports to
LFFS (the LLE scan expected 0x400000=4 MiB; ngvm's image is 1 MiB, so rebuild
ngvm with NGVM_SAVE_SIZE=4 MiB, or match the LLE flash size to the image), or
(b) make the LLE C: FORMATTABLE like ngvm so the real firmware formats it
(exercises our flash program/erase model) - the more authentic fix. Validate
the LLE boot against ngvm's logo frames.

## 2026-10-29 ROOT CAUSE CONFIRMED: blank C: scans as invalid LFFS -> KErrCorrupt -> crash; C: must be pre-formatted (update made with Claude)

Decoded the exact failing check (trace decode, IDT-independent): ELocal's LFFS
mount runs a scan loop (0x5038fb80..0x5038fbd4) over the whole volume in 64 KiB
(erase-block) steps, R5 summing to the total size [R7+4]=0x00400000 (4 MiB);
it validates each block into R0, every block reads invalid on the erased flash
(R0==0), the scan reaches the end having found NO valid block, and returns
MOV R0,#20 / RSB R0,R0,#0 = -20 = KErrCorrupt. StartupThread then
User::LeaveIfError -> User::Leave -> RThread::Kill (dies). So the firmware does
NOT auto-format a blank volume - a real N-Gage C: is PRE-FORMATTED at the
factory. Our erased (all-0xFF) C: is an invalid LFFS -> crash.

RECONCILIATION (I flip-flopped earlier; this is the evidence-backed answer):
the user's C: content IS needed to boot - not as files the startup reads, but
because C: must be a VALID FORMATTED LFFS volume. The Pocket core's "erased C:
boots" note does not hold for THIS firmware build (our firmware crashes on a
blank C:, proven by the scan-loop decode). The user's C: dump
(firmware/disk_dump/C) is a real phone's formatted C: contents.

FIX PATHS: (fast) a RAW C: flash/partition image (the actual flash dump) drops
straight into the cdrive_ overlay via an opt-in cdrive-image= and boots; (slow)
build an LFFS on-media image from the extracted file tree, which needs the
LFFS format (block header with LFFS_MAGIC 0x503B3B60 at word[1] per Pocket
drive.c, plus the log/free structures the scan validates - the per-block
validator is a helper not yet fully RE'd). Minimal empty-but-formatted LFFS is
also possible once the block header is pinned. Secondary hypothesis to keep:
mediaatt FORMATTABLE (0x04) in the drive caps medint reports - if unset, F32
would not auto-format; Pocket sets it.

Tooling ready: build/ngage-defs (IDT ordinal names), symtrace.py. NEXT: obtain
a raw C: image if one exists (instant), else RE the LFFS block header to build
a valid image from the dump.

## 2026-10-29 KErrCorrupt likely a C: flash geometry/size mismatch (update made with Claude)

The erased C: mount returns KErrCorrupt without attempting format (208 pre-
crash C: reads all 0xFFFFFFFF; cdrive_writes=0). On the working Pocket core
the same real LFFS formats an erased C: on first mount. Difference must be the
flash geometry/caps medint derives from our flash model. Mismatches found:
- SIZE: our cdrive overlay = 4 MiB (0x02400000-0x027fffff); THC live map shows
  real C: = 6 MiB (0x02400000-0x029fffff); device ID 0x257e implies an AM29x643
  = 64 Mbit = 8 MiB part. So our size is likely wrong, and medint's caps
  (iSize/iEraseBlockSize) may not match what the ROM-built LFFS expects.
- GEOMETRY: our model has 16 KiB boot sectors at each 2 MiB die top
  (cdrive_sector); Pocket uses uniform 64 KiB. Non-uniform geometry can break
  LFFS structural math -> corrupt.
Diagnostic in flight: resume mount-c760, window-trace 760-764.2M with the
IDT symbols to catch the TBusLocalDrive::Caps query and the exact size/erase/
mediaatt medint reports, then correct the C: flash model (size + uniform
geometry + formattable) so LFFS formats-on-mount instead of KErrCorrupt.

## 2026-10-29 REFRAME: boot does not hang - StartupThread CRASHES on C: mount KErrCorrupt (update made with Claude)

Symbolized the block with the user-supplied IDA IDTs (firmware/IDA IDTs 1st
Edition/*.idt, ordinal->name; converted to build/ngage-defs/*.def for romsyms).
Alignment VERIFIED against the independent exec table (euser ord630 =
User::Leave <-> exec 0x73 = User::Leave; ord627 LeaveIfError, 621 RThread::Kill,
1208/1209 WaitForAnyRequest all coherent). The 767.8M "idle" is NOT a wait:
the sequence is elocal LFFS mount -> returns KErrCorrupt (-20, raw value, IDT-
independent) -> User::LeaveIfError -> User::Leave -> CCleanup::PopAndDestroyAll
-> RThread::Kill. StartupThread LEAVED on the corrupt C: and KILLED ITSELF; the
later WaitForAnyRequest loop is just the null/idle thread. So the thread that
would launch ESTART is DEAD - every earlier "waiting on X" analysis was the
aftermath, not the cause.

Root cause: our empty/erased C: (all 0xFF) makes the real LFFS mount return
KErrCorrupt (origin in ELocal LFFS code ~0x5038fbd4, elocal!<code>+0x7840).
cdrive_writes=0/cdrive_erases=0 => the mount scan rejected the volume as
corrupt BEFORE formatting. On the working Pocket core (drive.c) an erased C:
is fine because "LFFS formats on the first mount". Ours returns corrupt
instead of formatting. FIX options: (a) make format-on-mount work (find why
the erased-flash mount scan concludes corrupt - likely flash geometry/CFI or
a read value our model gets wrong - and fix the C: flash model); (b) pre-fill
C: with a minimal VALID formatted LFFS image (LFFS_MAGIC 0x503B3B60 per
Pocket + minimal log), far smaller than the 1.7MB file tree. The user's C:
file tree is NOT needed to boot (Pocket proves erased boots) but a VALID
empty LFFS is. NEXT: read Pocket drive.c format handling + find the exact
corrupt check.

Tooling: build/ngage-defs (IDT-derived ordinal names), scratch/tools/
symtrace.py --defs build/ngage-defs names any trace line.

## 2026-10-29 SYMBOLIZATION unblock: block = StartupThread User::WaitForRequest; SDK defs incoming (update made with Claude)

The Pocket core's tools/ngvm/romsyms.py symbolizes OUR SYM.ROM to
library!ordinal(+off) directly from the ROM export tables (works without the
SDK). New helper scratch/tools/symtrace.py annotates any sim trace with it.
Key corrections this gave:
- efile and elocal are the SAME thread (ELOCAL.FSY runs in the file-server
  process), so the elocal WaitForAnyRequest IS StartupThread blocking, not a
  separate idle FS thread. Earlier "it's a normal media-change idle" was the
  wrong read.
- The block is euser!ord621 = User::WaitForRequest(TRequestStatus&) (reads
  [R0]=status, waits via exec 0x4d) - StartupThread waits on ONE SPECIFIC
  async request from its LFFS-mount/startup path that never completes.
- StartupThread = efile!ord3 (entry 0x503d5290), a startup state machine of
  panic-guarded steps (efile!ord4 helpers). Last ops before the block:
  efile!ord20+0x744 (media-readiness 0x503cfa30), efile!ord16, efile!ord4,
  then elocal -> User::WaitForRequest.

USER is getting a Series 60 1st Ed SDK. romsyms needs its per-library ordinal
.def files (euser.def/efile.def/elocal.def/... lines "Name @ ord NONAME") at
NGAGE_DEFS. With them every trace line gets a real name and the exact pending
request/completer is pinned in minutes. Ordinals to resolve first: euser 621
(block), 627/630 (request issue around the 767799317 exec), 863/823/360/121/
178; efile ord3/4/16/20; elocal ord1. If the SDK ships only .lib import
libraries, extract ordinal->name from those (petran/def dump) into NGAGE_DEFS.

## 2026-10-29 ROOT CAUSE of the user-side block: missing ISI/Phonet baseband responder (update made with Claude)

Traced StartupThread's full exec set across the mount (reqtrace 764-767.82M):
WaitForAnyRequest(162), heap, trap, locked inc/dec, plus RFs::Connect
(RSessionBase::Attach 0xbf to the file server - normal), TFindLogicalChannel
(0xb7), UserHal::DriveInfo (0x83), CServer/RServer (0x2e). No flash/MMC/timer
wait, no C: content dependency. Then the Pocket core docs/hardware.md S8 named
it exactly: the firmware boot (Starter) opens channels to NOSDRIVER (the
baseband) and sends ISI/Phonet messages - energy management (resource 0x17:
charger msg 0x08->0x09 subblock 0x13 "not connected", battery 0x0A->0x0B
subblock 0x16 "full 7 bars"), phone identity/IMEI (0x1B), SIM/IMSI (0x09) -
and WAITS for replies. The Pocket core implements NOSDRIVER as an ISI/Phonet
ROUTER (sw/kernel/chan.c) answering these; the fallback for everything else is
"open and never complete, or complete with KErrNotSupported." Our synthetic
NOS stub provides only the entry code and does NOT route ISI, so StartupThread's
CActiveScheduler waits forever for a baseband reply. "Without the charger's
reply, Xanadu Next exits at start" - the charger/battery replies are needed
early.

So the real frontier is a minimal ISI/Phonet baseband responder (like Pocket's
chan.c) at our LLE hardware level: find how the firmware's NOSDRIVER exchanges
ISI messages with the baseband (shared memory + interrupt), and answer the
energy-management set (+ KErrNotSupported / never-complete for the rest). The
real THC NOS image is the authentic alternative but needs its import table
fixed; the minimal responder is the faster path and matches what the working
Pocket core does. NEXT: read chan.c's ISI router for the exact message/subblock
layouts and the hardware mailbox, then model the responder.

## 2026-10-29 COURSE CORRECTION: C: content NOT needed; block is medint async mount completion (update made with Claude)

The user supplied the real C: as a FILE TREE (firmware/disk_dump/C, 120 files,
1.7MB; also Z: 1566 files, D: empty) - no raw flash image. Before building an
LFFS on-media image (a big sub-project), the Pocket core (~/develop/n-gage
sw/kernel/drive.c) settled it: on that working HLE core C: starts ERASED (0xFF)
and "LFFS formats on the first mount" - it boots to the N-Gage with an EMPTY
C: and never populates it (LFFS_MAGIC 0x503B3B60 is written only when there's
a save to restore). So missing C: content is NOT the blocker; our empty C: is
authentic. Keep the disk_dump for later (game saves in C:\System\Apps), but
do NOT build an LFFS image to boot.

Real block: drive.c's drive_executor shows the local-media executor calls -
sub 0x38 connect, sub 0x3B MOUNT (completes a TRequestStatus via
request_complete), sub 0x3E MediaChangeNotify (stays pending forever by
design; not the block). On our LLE sim the REAL medint.pdd runs the mount and
must complete that TRequestStatus via a flash-hardware DFC/interrupt we don't
generate - so StartupThread's CActiveScheduler waits on a mount/media
TRequestStatus that never completes. This is a "model the completion event"
problem (like the UEM IRQ that unblocked epbus), NOT a content problem.

NEXT: find medint's async completion path - what flash-controller event
completes the mount request (the program-ISR unit 0x60 / IRQ source 3 is one
candidate; a flash read/ready DFC is another). Trace medint during the mount
(the medint 0x50386628 loop seen in smtrace) to see which status register it
polls / which interrupt it expects, then fire that completion and resume.

## 2026-10-29 StartupThread is a CActiveScheduler waiting on an async request; C: content is the next lever (update made with Claude)

Decoded StartupThread's final sequence before the block (idle2 trace): it
constructs active objects (0x50389xxx/0x50394xxx), dispatches through a global
callback (0x503957ac: LDR R3,[global]; BX R3), and enters EUser 0x503b7fb8 ->
exec 0x4d WaitForAnyRequest — i.e. a CActiveScheduler::Start wait loop. The
busy stretch before it (ELocal 0x5038b714 <-> EUser 0x503a6abc, ~675 iters)
is a Mem::Fill zeroing a large buffer (legit work), NOT a hardware poll. No C:
write (cdrive_writes=0), no flash/MMC hardware wait. So the F32 startup's
active scheduler is blocked waiting for an async request completion that never
arrives; EStart is not launched because the startup hasn't passed this wait.

Most promising next experiment: populate C: with real content. On N-Gage the
file-server startup reads system startup data from C:; our C: is an empty
(all-0xFF) LFFS, so first-boot/startup may wait on resources that a populated
C: provides. User offered the real C: content twice. Plan: add an opt-in
`cdrive-image=<raw LFFS partition image>` that pre-fills the cdrive_ overlay
(digest-neutral; C: is not in the boot digest), then resume from mount-c760
and see whether the startup's active scheduler completes and launches EStart.
If a populated C: does not unblock it, fall back to deeper RE of the pending
request (identify the active object and its async call).

## 2026-10-29 MILESTONE: boot reaches EKA1 user-side startup; StartupThread blocked mid-state-machine (update made with Claude)

Deep checkpoint+trace analysis of the 767.8M re-idle (tools: inspect_checkpoint
on mount-c768, idle-window trace idle2 from mount-c760). The boot is NOT stuck
on a device register — it reached the user-side startup:
- F32 (file server) is fully up: live DThread objects named Main, Loader,
  Supervisor, StartupThread, Startup exist in the kernel heap (found by RAM
  name-scan; StartupThread DThread at PA 0xafdf764, vtable 0x503a20e0, owns an
  RHeap). C: (LFFS) mounted EMPTY — ELocal did a full linear mount-scan of the
  erased volume (0x02400000+, all 0xFFFFFFFF, to ~offset 0xf0000) and finished.
- EStart was NEVER launched as a process ("EStart" in RAM is only the ROM
  file-table directory entry at 0xa0886b4 / 0x50317466, not a DProcess).
- The blocked actor is StartupThread: EFile.exe creates it (name literal
  0x503dc664, ENTRY 0x503d5290) and it runs a multi-step startup state machine
  (sequence of panic-guarded init calls, panic fn 0x503d8c14, codes 7/8/9/e/f).
  It is blocked in WaitForAnyRequest (exec 0x4d, confirmed via SWI 0xef00004d /
  exec-table 0x503ac664) after an ELocal/C: operation; an EFile op at 0x503cfa10
  returned KErrNotReady (-18, [req+0x18] null path) just before the block
  (767800239). All idle-window execs are benign (WaitForAnyRequest, heap, trap,
  locked inc/dec) — no device/semaphore wait pending.

Reframed problem: no longer device-register modeling. StartupThread's state
machine is waiting for an async request to complete that never does. Candidates:
(a) a driver request needing an interrupt/DFC completion we don't fire (like the
UEM IRQ that unblocked epbus one layer up); (b) a drive-readiness retry (the
KErrNotReady). NEXT: trace StartupThread's state machine (0x503d5290+) from
mount-c760 across 766.5M-767.82M to pinpoint the exact blocking request and
which drive/driver it targets; then model that completion. Fresh pinned
snapshots mount-c760/mount-c768 are the iteration base.

## 2026-10-29 fresh correct-path snapshot mount-c768; F32 idle wait is next (update made with Claude)

Consolidation after a long advancing session. Fresh pinned snapshot
mount-c768 written from reset on the current UEM path (cycle 768M, after F32's
C: filesystem batch, just before the re-idle); validated by the inspector
(L1 table + anchor resolve). Stale pre-UEM checkpoints c1300/c1307900000
RETIRED (wrong shorter-epbus path); pinned set is now mount-c760 + mount-c768
(see build/sim/checkpoints/README.txt). run-resume.py auto-latest now globs
mount-c*. build/sim trimmed 1.4G->88M (traces regenerable; results/provenance
and checkpoints kept).

The 767.8M re-idle: F32 is Thumb-compiled; the last executed frames are EFile
media-readiness logic (0x503cfa10: [req+0x18] null -> returns -18 KErrNotReady)
and ELocal. System reached the 1.32e9 budget with no crash and no wake for
550M cycles => event-blocked on a non-timer signal, same pattern that the UEM
IRQ resolved one layer up. EStart (first user process, 0x503ee860) has NOT
executed yet in any trace.

NEXT (precise): from mount-c768, Thumb-RE the blocked F32 thread's wait —
whether it is (a) a driver waiting on another hardware completion to model
(most likely, given the pattern), or (b) F32 legitimately idle awaiting an
EStart request, meaning the block is upstream in loader/EStart creation.
Decide by checking, from the c768 RAM image, whether a loader/EStart thread
exists and what it waits on (inspector + the DThread vtable), then model the
event or unblock EStart creation. Iterate via run-resume (minutes/attempt).

## 2026-10-29 epbus clock-block + C: word reads: F32 exercises C: filesystem, re-idles ~767.8M (update made with Claude)

Two model additions cleared the epbus/LFFS frontiers in single rebuilds:
(1) opt-in `epbus-clkblk` serves 0x0c120600..0x0c1206ff as RW word latches
(epbus swept 0x604/0x610/0x614=0x280/0x618/0x624 during peripheral init);
(2) C: flash array now serves word reads (select 0xf -> two cells, array-read
mode only; commands/status stay halfword) — LFFS reads its mounted volume as
words. Result: boot advanced to the 1.32e9 budget with NO crash; medint
(783), EFile (1503), ELocal (248) transitions show F32 did a full batch of C:
filesystem work (last C: read 0x024f003c at 767.1M), then the boot thread
re-idled at ~767.8M (last real frames: EFile 0x503cfa30/0x503d91d6, ELocal
0x5038925c, then pure tick to 1.32e9). Same event-blocked pattern as before,
now one mount deeper. Checkpoint v4 serializes the clock block.

NEXT: write a fresh correct-path checkpoint near 767.8M (the stale pre-UEM
c1300/c1307900000 are retired) and run inspect_checkpoint on it to name the
newly-blocked thread and its wait object, then model that event. Iterate via
run-resume from the fresh checkpoint.

## 2026-10-29 UEM IRQ unlocked more epbus init; checkpoints re-based on mount-c760 (update made with Claude)

Full-boot module-trace from reset shows the span is dominated by healthy
EUser/ekern/EFile/EFSrv file-server work (F32 running), with lcd.ldd and
nosstarter now appearing (1 and 4 transitions) — forward progress, not a
stall. The from-reset run stops at a NEW frontier: epbus WRITE 0x280 to
0x0c120614 at 764,607,560 (same 0x1206xx block as 0x604/0x618/0x624; added
as a probe). KEY: this is not a regression though 764.6M < the old 1.31e9
frontier — the older runs reached 1.31e9 by a SHORTER epbus path because the
first power instance never completed; now that uem-irq-source1 delivers that
completion, epbus proceeds further and needs 0x614. Consequence: the c1300
and c1307900000 checkpoints are from the PRE-UEM path and are now stale; the
freshly written pinned mount-c760 (from reset with the current binary) is the
canonical current-path snapshot. probe-register args do NOT enter the
checkpoint signature, so adding probes keeps mount-c760 resumable.
In flight: run-modtrace resumes mount-c760 with 0x614 probed to get the real
current-path timeline past this point.

## 2026-10-29 mount window traced: medmmc is a clean no-card no-op; module-trace tool (update made with Claude)

run-mount-window.py (from reset, win-trace 761.0M-761.45M) shows the span
after the C: mount: EFile/EFSrv work steadily, medmmc runs ONCE at
761.403M-761.411M purely in software (PDD factory create via ordinal lookup
0x50330960 -> entry 0x503feb44, 0x20-byte alloc, constructor 0x503fd858;
ZERO hardware accesses), then F32 continues (EFile/EFSrv active to the
window edge at 761.45M). USER INPUT (2026-10-29): the MMC card is optional
on real hardware — boot without a card is authentic; full MMC/D: support
is a later feature, not a logo-path requirement. So the no-card path is
correct and D: is NOT the blocker; the park happens somewhere in the
untraced 761.45M-1.31e9 span.

New instrument for exactly that: `module-trace` option in main.cpp logs one
line per PC transition between ROM binaries (tiny output over any span);
run-modtrace.py resumes the pinned mount-c760 snapshot and produces the
complete module timeline 760M-1.32e9. Pinned snapshot mount-c760.{cpu,host}
written by run-c760.py (excluded from rolling prune); run-resume-760.py
replays the mount span with optional win-trace in ~1 minute.

## 2026-10-29 checkpoint inspector built: blocked thread is the F32 mount in medmmc (update made with Claude)

New tool `scratch/tools/inspect_checkpoint.py` (offline, no simulation):
parses a .host checkpoint, locates the 16 MB SDRAM image (verified by finding
the kernel L1 page table via the 0x58000000->0x0c000000 I/O section
signature; L1 at PA 0xa074000 in c1307900000), walks sections + coarse L2 so
kernel VAs resolve, and supports --dump VA hexdumps plus vtable-clustered
object scans and stack discovery (RAM pages dense with ROM return
addresses). Findings on checkpoint c1307900000: kernel object names are not
ASCII-in-RAM on this build (only string: "INFO Server"), so identification
goes by stacks/vtables; 16 stack-like pages found and module-mapped.

CORRECTION (same day): the code-pointer-dense pages are the KERNEL HEAP,
not stacks — the 'return addresses' at 0x503fefxx/0x503fd854 disassemble as
medmmc import-table/vtable DATA. So the right reading of PA 0xafe4000 is
that medint/medmmc/ramdrive/ELocal driver OBJECTS exist (media drivers
instantiated, including medmmc's), and of 0xafe2000 that the three epbus
instance objects (vtables 0x50339c08/0x50339d5c/...) live at
0x804067xx/0x804068xx/0x804069xx. Which thread is blocked on what is NOT
yet proven; stack discovery needs SVC-frame signatures, not raw density.
In flight: from-reset run-mount-window.py (win-trace 761.0M-761.45M, the
span right after the C: mount where the mount thread last ran) to catch the
park in the instruction stream directly.

NEXT: RE medmmc's wait entry (around 0x503fef88/0x503fd854) to identify the
exact completion it needs (second UEM interrupt client? card-detect GPIO?
MMC controller registers — none modeled yet at any address), then model the
minimal "no card present" or "card ready" answer so the mount completes or
fails cleanly and boot proceeds to EStart. Iterate with run-resume from
c1307900000.

## 2026-10-29 unit-1 = ekeyb scan timer; system idles event-blocked; next: thread-state inspector (update made with Claude)

The unit-1 run (boot-v15-unit1, 3e9 budget, rolling checkpoint written at
1.3079e9 — checkpoints now c1300 + c1307900000) resolved the chain: timer
unit 1 is ekeyb's KEYPAD SCAN timer (5,561 expiries at ~3 ms cadence; each
scan: read 0x15020c=0x9090 / 0x150208-upper=0 (no keys), drive rows 0x1f/0x3f
via 0x150400-block, touch 0x14f018/0x120c14, re-arm). The post-wake activity
previously attributed to epbus was ekeyb powering up (keypad page writes
0x150100=0xc/0xee). The scanner and tick run healthily for 16+ simulated
seconds; the only ms-timer live is the scan period (diag2 window: countdown
3->0). No EStart/ELocal/medmmc code observed in any captured window; no new
debug59 output after "TRtcQueue::Add: 2". Conclusion: the boot-progress
thread is EVENT-blocked (not timed) on a signal the board never delivers,
and guess-and-rerun has hit diminishing returns.

NEXT (planned): build an offline EKA1 thread-state inspector that parses the
checkpoint .host RAM image (16 MB SDRAM at offset per save_host layout in
scratch/boot-v15-nosprobe/main.cpp) and walks the kernel thread list to name
each thread and its wait object (anchors from disassembly around the known
scheduler globals 0x80006xxx; ~/develop/n-gage docs/eka1_exec.md and
tools/ngvm symbol tooling as reference). That converts "who is blocked on
what" from guesswork into a lookup, using checkpoints as free RAM dumps.

## 2026-10-29 UEM IRQ WOKE EPBUS; next: unit-1 settle timer; rolling checkpoints (update made with Claude)

The uem-irq-source1 hypothesis run (boot-v15-uemirq, resumed from c1300)
WORKED: the injected source-1 IRQ after the UEM 0x30=0x40 write was dispatched
(0x114 read 2 at 1,307,939,636), the cbus ISR ran and the chain continued —
UEM power-status 0x13f read, new GPIO-block writes 0x0c150100=0xc/0xee
(accepted by the keypad-GPIO latch model), UEM 0x35/0x36 reads, ack 0x10c=2.
epbus's wait completed. The thread then programs TIMER UNIT 1 as a settle
delay: repeated control 0x0a24 stop/start, compare 0x0a30=0x7fffffff parked,
status 0x0a28 ack, ICU 0x108=2 re-enable, compare rewritten 0x6590 — i.e.
ICU source 1 is (also) unit 1's expiry line; the UEM-write trigger and the
unit-1 expiry share one pending bit in the model. Unit-1 model added (counts
CPU cycles to the compare latch; scale unverified; board tests cover it).

Infrastructure (user policy, saved to memory): default budgets are now 3e9
cycles everywhere (don't kill an unblocked run); run-resume.py auto-restores
from the LATEST build/sim/checkpoints/boot-v15-c*.{cpu,host}, takes
[budget] [name] [ckpt_at] and with ckpt_at writes a rolling checkpoint near
the frontier, then prunes to the newest 2 checkpoints. Board checkpoint
format v3 (0x4e470003) appends source-1/unit-1 state; v2 files still load
(fields default). main.cpp now allows restore+checkpoint in one run.
In flight: resume with unit-1 live, rolling checkpoint at 1.3079e9
(boot-v15-unit1, budget 3e9).

## 2026-10-29 epbus wait decoded: UEM interrupt client; source-1 model in test (update made with Claude)

RE of the park point: epbus does NOT wait on a GPIO edge — it registers with
cbus.dll's UEM-interrupt dispatcher (bind call 0x503f5ba8/0x503f5bf4 →
cbus.dll 0x503820c4 with r1=type 1, r2=client id 0xb, r3=bit 8). The client
table at 0x50383574 (20-byte rows) maps id 0xb → {type 1, group 2, bit 3};
ids 0x9..0x11 are the group-2 UEM interrupt clients with consecutive bits.
Around the bind, epbus writes 8 to 0x0c120c0c/0x0c120c10 and halfword 1 to
GPIO bytes 0x150206/0x150208 (pin arming for both instances, pools
0x503f5bc8-0x503f5c1c). Driver-init ICU enable 0x0c120108=2 (source 1) at
729.6M is the candidate UEM IRQ line; the tick-queue insert at 0x50343374
confirmed the thread sleeps on an event, not a timeout.

Model (opt-in `uem-irq-source1`, run scripts updated, assumption recorded):
kernel-phase CBUS write to UEM reg 0x30 (the epbus power-up tail 0x2b=0x81,
0x30=0x40) sets ICU source 1 pending; 0x0c120114 reads 2; bank0 +0x0c bit-1
write acks. Pending state is transient (not checkpoint state — c1300 precedes
any UEM write, so resumes are safe). Plan: resume-iterate (boot-v15-uemirq);
when the cbus ISR runs it will READ the UEM interrupt-status register over
CBUS — whichever register it reads, supply bit 3 (client 0xb) there next
iteration. If the ISR instead reads an unexpected ICU current value, source 1
is wrong — check bank2 candidates (the 0x12018c=0x800 clear at 729.6M).

C: drive status (user asked): the kernel never formatted or wrote C: — LFFS
mounted the erased volume read-only (cdrive_writes=0, cdrive_erases=0 in
every run; the unit-0x60 program ISR has never fired). The user HAS a real C:
content dump; when boot reaches file-server reads from C:, check its format
(raw LFFS partition image vs file tree) and add an opt-in `cdrive-image=`
overlay (digest-neutral; C: is not hashed by the boot digest).

## 2026-10-29 checkpoint/resume proven; frontier: epbus power-up completion event (update made with Claude)

Checkpoint at cycle 1.3e9 written (build/sim/checkpoints/boot-v15-c1300.{cpu
53 KB, host 25 MB}) by run-checkpoint.py, which from reset also advanced the
frontier past 0x0c120624 to 0x0c120618 (both now probe registers; epbus walks
its 0x0c1206xx block: 0x604 W, 0x624 R, 0x618 R). load_state now MERGES probe
values so a resume can add newly probed registers (the standard iteration).
First resume runs validated: run-resume.py restores at 1.3e9 and a windowed
run-diag.py (restore + 15k-cycle win-trace) answered a who-writes-what
question in ~2 minutes end-to-end. Resume runs cannot capture screens (LCD
init precedes the checkpoint; known cosmetic limitation).

Current frontier (from the diag window, boot-v15-diag): after 0x618 the chain
continues — CBUS writes UEM 0x2b=0x81 then 0x30=0x40 (cbus.dll 0x503833a4 on
behalf of epbus), GPIO-block write 0x0c150208=1 just before (likely arming a
power-good pin interrupt), probe 0x0c120c10=8 — then the epbus thread inserts
itself into a wait queue (TDblQue insert 0x503bb818 via EUser 0x503bbb5c; the
PSU vtable path at 0x503fbf68 was NOT taken) and the scheduler parks the
system: 4.6 simulated seconds of pure tick+idle to the 2.5e9 budget, no
timeout path fired, no new TRtcQueue entries. Reading: DPBusSocket-style
power-up wait whose completion on hardware is an interrupt (UEM power-good
or the GPIO pin enabled via 0x150208). NEXT: RE who signals that wait object
(find the TDblQue remove/signal call sites in epbus and the ISR behind them,
starting from the 0x150208 enable), then model the completion event behind an
opt-in flag and iterate via run-resume (minutes per attempt).

## 2026-10-29 1e9 was the wall: 2.5e9 run reaches 1.31e9; checkpoint/resume v2 (update made with Claude)

The 2.5e9-cycle run (boot-v15-long) CONFIRMED the 2-second-timer analysis: the
sleeping thread woke past the old budget and boot continued to 1,307,930,588
cycles (+546M past every previous run; 1,433 ticks = 5.6 s simulated). All
earlier "idle forever" results at exactly 1e9 were budget artifacts. New
frontier: epbus (0x503f41b8 path) writes 0x0c120604=0 then READS 0x0c120624 —
added probe-register=0x0c120624:0:15 (reset 0 hypothesis) to all run scripts.

Simulation economics (user asked): Verilator --threads is 11x SLOWER here (60M
cycles: 55 s single vs 626 s with 6 threads) — never thread this model. The
fix is checkpoint/resume: board checkpoint format v2 (0x4e470002) now
serializes ALL device-model state (probe regs, periodic timer, ICU banks +
Interrupt-API masks, timer units + unit60, keypad, block14d, C: overlay + FSM,
power model, stub/image counters, debug59 buffer) and the post-UIF guard is
gone; roundtrip covered in the board tests (25 sections). New scripts:
`run-checkpoint.py` = full 2.5e9 run writing
build/sim/checkpoints/boot-v15-c1300.{cpu,host} at cycle 1.3e9 (in flight);
`run-resume.py [budget] [name]` resumes there, so frontier iterations cost
minutes instead of ~40 (the ~30-sims/day ceiling is gone). Resumed results
carry checkpoint_restored=true and never count as from-reset evidence.

## 2026-10-29 stub pread zero-length bug was the real 0x47f0 frontier; NOS scout ran real code (update made with Claude)

CORRECTION to the previous two entries: the 0x0c0047f0/0x0c0047f4 scratch
writes are the kernel EXCEPTION path, not a Variant table — the strlen loop
before them walks the string "Exception" in ABT mode, and 0x50324240 is the
fault-dump/reboot handoff ({3 words to scratch 0x47f0/f4/f8 from the
superpage block at VA 0x40000400, halfword 0x1a to 0x0c00428e, 0x200 to SYSC
0x0c120004, doorbell halfword 4 to 0x0c150000, then a parked self-branch}).
Root cause found in the trace: a kernel query (0x50331a84) called the
synthetic stub's pread (0x5149d078) with byte length 0 and a non-writable r3;
the stub's "default to 4 bytes" path STRB'd into it and data-aborted at
0x5149d09c. Fixed in scratch/nos-stub-blob/nos_stub.S: zero length now writes
nothing (iface_vt pinned at VA 0x5149d0c0 with .org; blob regenerated, still
648 bytes; toolchain arm-none-eabi on host). The scratch-window growth to
0xac stays (harmless, covers the real fault path if it ever runs).

Follow-up: the first rerun with the edited blob FAILED the boot digest (halt
0x50003290) — SYM.ROM embeds the blob and power-model words at 0x9d000/0x9e000
and the derived digest hashes them, so overlay edits change digest input.
Fixed like the nos-image window: both synthetic windows now gate on the kernel
tick (periodic_period_); the digest hashes the ROM-embedded (old) bytes, the
kernel phase gets the edited blob. Any future blob edit stays digest-neutral.

Gated/fixed run result: TIMEOUT at 1e9 with a clean system — no crash, the
pread abort is gone. The windowed diagnostic (run-park-window.py, trace
761.29M-761.6M, output boot-v15-park-window) decoded the "idle": a kernel
boot waiter (0x50331a50) loops forever — each iteration calls the Variant
interface getter pread(iface, id=13, dest=NULL, len=0) and then tests a
kernel global ([pool 0x50331bb4] = 0x806028fc, dereferenced) against zero,
yielding via 0x50323c74 and retrying. The kernel is waiting for interface
id 13 to be REGISTERED (our stub registers only #3 via exec slot +0x128 and
#6 via +0xfc). Stub updated: nos_init now also registers iface 13 through
exec slot +0xfc before the #3 registration; ret0/pread moved after the
pinned vtable to fit (new VAs ret0 0x5149d184, pread 0x5149d18c; iface_vt
still 0x5149d0c0, iface 0x5149d180, blob still 648 bytes; digest-neutral via
the kernel-tick gate). Hypothesis: the poll's global is the iface-13 table
slot the registration exec writes.

REFRAME after the iface-13 run (still timeout at 1e9): 0x50331a50 is the
kernel IDLE THREAD, not a boot waiter — it polls pread(13) every iteration
and the global only selects the timed-idle branch (fn ptr [0x80006c1c],
time-adjust 0x503459e8, tick accumulator [0x80000488]). The iface-13
registration is kept (it matches what the idle loop expects to exist). The
REAL last actor: a user-side thread does 64-bit time math (EUser 0x503a3ad4),
blocks, and the scheduler (0x50327f48) finds an empty ready list. Combined
with the last debug line "TRtcQueue::Add: 2" this reads as a 2-SECOND timer
sleep. Arithmetic: tick reload 0x632ea = 406,250 cycles, 256 ticks/s (CPU
~104 MHz), so +2 s with up-to-1 s second-boundary slack lands at ~0.97-1.07e9
cycles — AT THE EDGE of the 1e9 budget. Decisive test in flight: run-long.py
(2.5e9 cycles, output boot-v15-long). If the thread wakes, the system was
never stuck and long budgets are the new normal for late boot.

Simulation speed (user asked): Verilator --threads 6 benchmarked 11x SLOWER
than single-threaded on this design (60M cycles: 55 s vs 626 s) — do not use
model threading; the design is too small to partition. Docker VM already has
all 14 host CPUs. Practical speedups: parallel independent runs (one core
each), and checkpoint restores for late-boot iteration (main.cpp already
supports checkpoint_at/restore; mark results checkpoint_restored=true, keep
authentic-path claims to full runs).

NOS scout result: with the kernel-tick gate the digest PASSED and nosstarter
EXECUTED the real THC NOS entry at 729,412,537 (B 0x514a6b48, stack setup,
R0=0x40 call). It died at an import thunk (0x516c7010): the pool slot at
0x516c7018 reads 0 — the THC gsm image's import table is UNFIXED (zero
slots), so the real module needs an E32 import fixup pass against the
same-build ROM's export tables before it can run further. Parked: the
~/develop/n-gage tools/ngvm ROM/symbol tools are the suggested starting
point. The synthetic-stub path remains the mainline toward the logo.

## 2026-10-29 digest/nosstarter timing corrected; scratch window grown (update made with Claude)

Second NOS scout halted identically — the one-shot gate was wrong because the
boot MD5 runs AFTER the one-shot: the bus trace's code/data column settles the
real timeline (compact trace does not log flash reads, which misled the first
diagnosis). Measured in the stub run: digest sweeps PA 0x9d000+ as DATA reads
at ~139.26M-139.4M; the kernel tick arms at ~452M; nosstarter EXECUTES the
entry (CODE fetches at 0x9d280/0x9d284) at 729,412,514. The image-run digest
computes until ~683.49M then enters the 0x50003290 halt (BNE at 0x500032e8).
nos-image gate changed to periodic_period_ != 0 (kernel tick armed).

C: chain advanced to 761,316,873 — nosstarter ran, and the kernel Variant
registration (0x50324248, pool 0x5032429c) stores the interface pointer
0x5149d09c at scratch 0x0c0047f0, one word past the modeled window: scratch
grown 0x9c -> 0xac bytes (0x0c004748..0x0c0047f3; gap bytes still stop on
unwritten reads; old board-checkpoint binary layout changed, prior checkpoints
already deleted in cleanup). Board tests pass (scratch end boundary moved to
0x47f4). Both runs relaunched.

## 2026-10-29 NOS scout diagnosed (digest reads raw bytes); epbus 0x120604 probe (update made with Claude)

First NOS-image scout halted at 0x50003290 (masked-IRQ dead loop) at ~137.85M
cycles: the 695,376 image reads were the boot-time MD5 digest sweeping PA
0x9d280+ — serving the live-dump bytes there changed the digest input and
validation halted right after the boot one-shot IRQ handler (UEM 0x35/0x36
reads + 0x150100=0x8000). This is the docs/discord.md descrambler warning in
board form: at digest time the raw window must present RAW flash bytes. Fix:
the nos-image window now activates only after the boot one-shot has fired
(timer_irq_cycle_ set, ~137.849M) — measured ordering: digest reads end
≤137.85M, nosstarter's entry call at 139.26M (synthetic-stub run evidence).
Descrambler-enable timing is a hypothesis.

C: chain meanwhile advanced to 761,291,676: epbus (delay loop 0x503f51b0,
after clock writes 0x120014=0x580/0x120018=0x200) writes 0x40 to NEW register
0x0c120604 — added as probe-register=0x0c120604:0:15 to both run scripts (no
code change). Board tests 24 sections pass; both runs relaunched.

## 2026-10-29 C: mounts without format; frontier moved to epbus; NOS scout queued (update made with Claude)

unit60 iteration 2 (control-register arming + ICU 0x10c acknowledge): the
first iteration's interrupt storm (738k dispatcher acks of source 3; "any
nonzero unit write arms" fired during medint setup while the unit was stopped)
is fixed — arming now follows a nonzero +0x04 control write (medint's setup
uses the kernel stop-and-settle helper 0x50324960: +0x04=0 five times,
compare 0x186 at +0x18, counter reset +0x10=0) and ICU 0x10c bit-3 writes
acknowledge pending. Result: medint init completes WITHOUT the program ISR
(unit60_irqs=0, cdrive 0 programs/0 erases — LFFS mounted the erased volume
as-is; formatting/writes will engage the ISR later), boot advanced to
761,278,878 (+218k past the pre-C: frontier), kernel debug prints
"TRtcQueue::Add: 2". New stop: epbus.dll init (0x503f5bbc) writing halfword 1
to GPIO byte 0x0c150206 — accepted into the gpio206-extra-write set (ekeyb
0x0006, epbus 0x0001). Board tests 24 sections pass.

In flight: (1) rerun of the authentic C: chain with the epbus value accepted;
(2) first NOS scout run (`run-nos-image.py`, output boot-v15-nos-image) with
the REAL THC NOS/GSM image served at PA 0x9d280+ via the new opt-in
`nos-image=` option replacing the synthetic stub (mutually exclusive;
writes into the window stop the run). Expect the scout to stop at the first
baseband/DSP access — that address is the deliverable.

## 2026-10-29 THC real-device dump verifies sim addresses; real NOS image recovered (update made with Claude)

User-supplied `firmware/THC N-Gage ROM Dump/` (see docs/references.md for the
full inventory) — same firmware build as our reconstruction (binaries byte-
identical from 0x317000). Verified against the live phone's page table: I/O
0x58000000->0x0c000000, debug sink 0x59000000->0x0de00000, raw CS0 window
0x51400000->0x0 (so the NOS entry PA 0x9d280 assumption holds), C: internal
flash 0x59200000..0x597fffff->0x02400000..0x029fffff — NOTE 6 MiB mapped
(cached+uncached aliases at 0x598xxxxx), vs the 4 MiB cdrive-flash model; if
LFFS walks past 0x027fffff the model must grow. Real header metadata recovered
(iTime 0x56F2F400 at 0x84, iCheckSum 0x4B0A78B0 at 0xA8) for two synthesized
fields; THC's ROM view must NOT be reused as digest-time MD5 input (+5 MiB
post-boot remap, per docs/discord.md). The gsmstuff dump is a 0x60-byte
TRomImageHeader copy + the REAL NOS/GSM module payload for PA 0x9d280+
(entry B-instruction at PA 0x9d284 confirmed); extracted to
`build/firmware/thc/nos-image.bin` (0x279680 bytes, sha256 72787f4aed7c48e6…).
Planned opt-in `nos-image=<path>` board option replacing the synthetic
nos-entry-stub for an authentic-NOS scouting run (edit deferred until the
in-flight unit60 rerun lands — run-stub.py hash-checks its sources).

## 2026-10-29 ICU mask banks + unit-0x60 IRQ-3 model implemented, run in flight (update made with Claude)

Kernel disassembly resolved the 0x0c1201cc blocker: InterruptEnable
(0x503248f0) / InterruptDisable (0x503248a4) are a three-bank Interrupt API
mask file — banks at 0x0c1201c0/0x200/0x240 for sources 0-31/32-63/64-95,
+0x0c enable-set, +0x08 enable-clear (pools 0x1201cc/0x12020c/0x12024c and
0x1201c8/0x120208/0x120248). The blocked write was InterruptEnable(3) = 1<<3
→ 0x1cc, and the known early 0x1c8=0x08000000 exact sink re-reads as
InterruptDisable(27), not a FIQ enable (prior note revised). medint's setup
(0x503872dc..): enable source 3, exec(unit 0x60, 0x186) (reload hypothesis),
two zero writes, then unit reg +0xc=0 via kernel helper 0x503249a8 (unit base
= 0x0c120a00 + unit id; the I/O write primitive 0x503245bc stores via VA
0x58000000 + offset). Import stubs resolve through a load-time table, so the
remaining register roles are left to dynamic discovery.

Model added in `scratch/boot-v15-nosprobe` (opt-in `timer-unit60-irq3`): the
six mask registers latch and read back; a nonzero unit-0x60 (0x0c120a60..7f)
register write while mask bank0 bit3 is set raises IRQ source 3 after an
ASSUMED fixed 20000-cycle delay; ICU current 0x0c120114 then reads 4
(source+1); any unit-0x60 write acknowledges; unit status +0x08 reads 1 while
pending. Delay and start/ack register roles are hypotheses, not silicon.
Board tests extended (all 23 sections pass); full from-reset run with the new
flag is in flight. Expected outcomes: medint's program ISR runs and LFFS
format proceeds (next frontier appears), or the ISR's real ack/status
accesses stop the run and refine the hypothesis.

## 2026-10-29 cdrive-flash run: LFFS format DOES need the program ISR (update made with Claude)

The first cdrive-flash run (started 09:49) was killed by a host power cut
~2.5 min in; rerun completed cleanly, no state lost. RESULT: unmapped_access at
761,118,521 cycles (+57,919 past the prior medint block at 761,060,602), blocked
on a WRITE of 0x8 to ICU 0x0c1201cc. The C: flash model was accepted end-to-end:
308 accesses at 0x024xxxxx — LFFS scanned the erased array (scattered reads, all
0xFF = unformatted volume), then medint began format work (autoselect 0x90 with
protect-verify reads 0, reset 0xf0, sector ops). It then configured hw timer
unit 0x60 (write 0x0c120a6c=0) and tried to enable an interrupt by writing 0x8
(bit 3 = IRQ source 3) to 0x0c1201cc — the exact multi-halfword-program
dependency predicted in the RE note below. So the open question is answered:
LFFS format does engage the program-ISR path; an empty C: cannot mount without
it. 0x0c1201cc is 4 above the known FIQ enable-set sink 0x0c1201c8, value bit 3
— plausibly IRQ enable-set for source 3, unverified. Screen still the white
clear. Next: RE-confirm 0x0c1201cc's role, then model it plus timer unit 0x60
raising IRQ source 3 so medint's program ISR can run, and rerun.

## 2026-10-29 C: drive (LFFS) flash model + parallel Thumb-decoder audit (update made with Claude)

C: drive modeled: `scratch/boot-v15-nosprobe` option `cdrive-flash` adds a 4 MiB
RAM-overlay AMD x16 flash at PA 0x02400000 (LFFS volume; medint.pdd checks no
IDs/CFI, only sector-protect==0). Minimal command FSM: reset 0xf0/0xff, blind
0x60 sector lock, autoselect (protect-verify reads 0, IDs don't-care), single-
halfword program into the overlay, sector erase with DQ poll (first poll returns
0x0008 = DQ7=0/DQ3=1, then the sector reads back 0xFF), 0xb0 suspend finishes
instantly; sector map = two 2 MiB dies, 64 KiB sectors + 4x16 KiB boot sectors
per die top. Reads serve the 0xFF-initialised overlay. Board tests cover
reset/lock/autoselect/program/erase (note: byte 0xaaa arrives as a high-halfword
store, select 12 at word 0xaa8 — same convention as the code flash). Known next
dependency (from the RE): multi-halfword program needs hw timer "unit 0x60"
(0x0c120a60) raising IRQ source 3; single-halfword + erase work without it, so
run first and see whether LFFS format needs the program ISR.

Thumb-decoder audit RESULT (clean): a full capstone-differential sweep of all 18
Thumb formats + SWI/BX/BLX/BKPT in zap_mode16_decoder.sv found NO siblings — the
format-11 SP-relative U-bit bug (patch 0008) is the only decode error. Every
positive-offset load/store (formats 6,9,10,13, both register-offset forms) emits
U=1 correctly; PUSH/POP and LDMIA/STMIA P/U/W directions, halfword SH/imm split,
branch sign-extension/scaling, and the BL half-pair join (−1 PC compensation,
LR|1 interworking) all verified. Harness: `scratch/thumb-decoder-audit/audit.py`
(bit-exact Python port + capstone ground truth), output audit-output.txt.
Minor non-functional deviations noted, none affecting compiler-generated code:
(D1) 0xDExx (cond=1110) decodes as unconditional branch instead of the ARMv4T
UNDEFINED trap — revisit only if a UDF-based mechanism surfaces; (Q2) BKPT drops
its immediate; (Q3) MOV/MVN set Rn=Rd instead of SBZ (harmless, mode32 ignores
Rn); (Q4) ADD Rd,SP force32-aligns the SP operand. Belt-and-braces items for a
future Verilator decode-differential: BL half-pair across pipeline stalls, and
bit-0 handling on PC writes for POP{PC}/MOV PC,LR (writeback path, not the
decoder). Note the vendored third_party/zap line 483 is still unpatched by
design (patch 0008 applies it in the maintained build; the experimental sim uses
the directly-fixed scratch/boot-v15-quiet-zap copy). Next CPU-correctness step
when useful: execution lockstep vs Unicorn (the ~/develop/n-gage Pocket core has
a full harness); the ARM920T TRM is the semantics reference per flagged case,
not a cover-to-cover read.

## 2026-10-29 CPU fix validated: +31M cycles, EFile runs F32, reaches C: drive mount (update made with Claude)

The Thumb SP-relative U-bit fix is validated: a full from-reset run advanced from
the old panic (729,986,403) by +31M cycles to 761,060,602 — EFile cleared the
KERN-EXEC 0, ran into real F32 init, and the boot now reaches the internal-media
/ C: drive mount: medint.pdd (VA 0x50384990) issues AMD flash commands to the
internal user flash at physical 0x02400000 (CS1 upper half) — reset 0xf0 then
0x60, which our flash command FSM doesn't model (it only knows the three
identified chips' identify/CFI/burst sequences). 86 ticks; still the white clear.
NOTE the zap pristine constraint is LIFTED (user, 2026-10-29): edit the CPU
freely; patches/zap/0008 kept only because the build's upstream-comparison uses
pristine zap as baseline. The Thumb fix is also live in the sim RTL copy
scratch/boot-v15-quiet-zap.

This is the "mount C: via medint.pdd" obstacle predicted from the 6600 analysis.
The C: region is internal user flash we have no content for; the plan is to model
CS1-upper (0x02400000..0x027fffff) as an erased AMD flash (array reads 0xFF so C:
is unformatted/empty) and accept medint's command set (reset/autoselect/CFI/
sector-lock/erase/program, program+erase sinking to a RAM overlay) so F32 mounts
an empty C: and proceeds — the splash lives on Z: (ROM) and does not need C:
content. A focused RE of medint's exact command set is in progress.

## 2026-10-29 ROOT CAUSE: ZAP Thumb SP-relative LDR/STR decoder bug (real CPU fix) (update made with Claude)

The EFile block is a genuine CPU RTL bug, NOT a synthetic-stub gap. ZAP's Thumb
decoder mis-decodes format 11 (LDR/STR Rd,[SP,#imm8*4]) with the ARM U bit = 0
(subtract) instead of 1 (add): `zap_mode16_decoder.sv` T_SP_REL_LDR_STR emits
`{3'b010, P=1, U=1'd0, B=0, W=0, L=bit11, ...}`. The two correct siblings in the
same file use U=1'd1 — T_PC_REL_LOAD (format 6) and T_LDR_STR_5BIT_OFF (format
9). Thumb SP-relative transfers are always positive-offset, so `str r1,[sp,#4]`
wrongly computed SP-4. EFile's E32Main (0x503d5838) did `str KCurrentThreadHandle
,[sp,#4]` then read the handle back from the correct SP+4 (still stale =
0x503cdbc5, EFile's own entry); exec 55 (ThreadSetPriority) got that bad handle,
DObjectIx::At returned NULL, and the kernel panicked the EFile thread with
KERN-EXEC 0 (EBadHandle) and killed it — after which only the idle thread runs.
F32 init 0x503d5554 (LoaderThread/ESTART) was never reached; "LoaderThread
created" in the prior note is wrong. Boot survived 730M cycles because the only
earlier Thumb SP-relative store used imm=0 (U irrelevant); EFile's E32Main is
the first nonzero-offset SP store.

Fix (verified by source + trace): set U=1 in T_SP_REL_LDR_STR. Production patch
`patches/zap/0008-thumb-sp-relative-ldr-str-add-offset.patch` added
(third_party/zap kept pristine); the sim RTL copy
`scratch/boot-v15-quiet-zap/src/rtl/zap_mode16_decoder.sv` is fixed and a
full from-reset validation run is in progress. This corrects ALL Thumb nonzero
SP-relative loads/stores — a broad correctness fix the real user side (all
Thumb: EFile, EStart, apps) depends on. Expected: EFile proceeds past 0x503d5862
into real F32 init. The synthetic power model / MMC questions only become
relevant after that. This should also be added to the maintained sim RTL and
validated with the ZAP Thumb benches (a `str/ldr [sp,#4]` round-trip).

## 2026-10-29 CORRECTION: EFile (file server) DID start and run; blocks in F32 init (update made with Claude)

The "EFile never started" reading below was a trace-window artifact. A windowed
trace (`win-trace=LO:HI` added to main.cpp; run `run-efile-window.py`, output
`build/sim/runs/boot-v15-efile-window/`, preserved as efile-window.tsv /
cp15-window.tsv) shows EFile.exe WAS created, resumed, and executed F32 init for
~23k cycles (cycles 730,502,230..730,525,057; its data region VA 0x80100000 is
page-mapped and still live at run end; two context switches into its process
domain, DACR 0x55555717, bracketed by the moving-model TLB/cache flush). It ran
its main 0x503d5838 (past the "FileServer" find-server gate 0x503d57e4, into
F32 init 0x503d5554 which creates LoaderThread), then blocked in the kernel
reschedule (WaitForAnyRequest, 0x50329cc8/0x5032a5a8) and never ran again — nor
did any EFile-process thread (LoaderThread) for the remaining ~270M cycles; the
idle thread spins. So the boot is NOT stuck at a kernel hand-off: EFile is
blocked on a request/event that is never completed, or waiting on LoaderThread
which never runs. Leading suspects (per investigation): the synthetic power
model's no-op vtable swallowing a request completion F32 waits on, a
LoaderThread scheduling issue, or local-media (medint.pdd/MMC) init waiting on a
media-ready event the board latch model never fires. A focused decode of the
exact blocking exec is in progress. This is tractable (not the 6600's hard
wall) and remains an authentic-boot inflection worth user input on HLE depth.

## 2026-10-29 (superseded by the correction above) EKA1 kernel idle; EFile not yet started

With the Variant interface param-read slots (+0x48/+0x50) upgraded from ret0 to
zero-fill (so product_info's identity method gets an in-range value instead of
uninitialized heap, clearing its reason-3 Kern::Fault), the authentic from-reset
V15 run NO LONGER FAULTS: it runs the full 1,000,000,000-cycle cap with 675
periodic ticks and no new unmodeled register. Preserved:
`build/sim/runs/boot-v15-kernel-idle-milestone/`.

This is the deepest milestone to date — the real NEM-4 EKA1 kernel boots from
reset through digest, VARIANT, scheduler, synthetic NOS (interfaces + power
model), product_info, full pin config (GPIO/PUP/ICU/timers), driver init (real
power handlers register) to the kernel IDLE state. The retirement tail is ~98%
the D-cache clean/invalidate loop at 0x50328408..0x50328414 (the idle thread
spinning, woken only by timer ticks). HOWEVER the first user process, EFile.exe
(the file server), never runs (grep of the trace: 0 hits on its entry
0x503cdb60), so the user-side boot chain EFile→EStart→EwSrv→Starter→SplashScreen
has not begun and the LCD is still the white clear (18353 words, 75 headers).

This is the same frontier the Nokia 6600 recompiler documented as unsolved
natively: "after Init2/Init3 the kernel idles by design; the kernel alone never
creates the first user process — the hand-off starts EFile." The open question
is whether EFile is (a) never created (a kernel boot step that spawns it did not
run or needs state a stub left out), (b) created but blocked on a resource our
model doesn't provide, or (c) started but needs far more than 1e9 cycles. A
focused investigation of the EKA1 kernel→EFile hand-off is in progress. This is
a real inflection worth the user's input on how far to push synthetic HLE vs.
awaiting real NOS content; flagged rather than burning many more blind
iterations. All board models and tests remain green; the NOS content gap is
unchanged.

## 2026-10-29 power model installed; kernel boot-complete; into next init phase (update made with Claude)

The null singleton at 0x80006bc4 was identified as the EKA1 kernel POWER MODEL,
installed only by ekern export ordinal 394 (0x5033c8f8) — which no ROM code
calls, so on real hardware the NOS/baseband installs it during nosstarter.
Our no-op stub skipped it. Fix: the synthetic NOS stub now installs a minimal
power model. `scratch/nos-stub-blob/nos_stub.S` calls ordinal 394 with a
board-backed RW object in the NOS window (PA 0x9e000 / VA 0x5149e000,
supervisor-RW mapped): vptr → the all-ret0 vtable, an empty self-linked
power-handler queue (+0x10/+0x14 → &self), iOffset 4, status 0. The object is
served RW by the board (`synthetic_nos_power_model`); the kernel writes its
fields and later drivers add handlers via ordinal 5. The digest-probe now
overlays the blob AND the power-object initial image. Board tests cover the
window; all pass.

Result: the boot vcall at 0x5033183c ran the no-op, the kernel-server boot
phase completed (boot-complete magic 0x55555517 written) and the boot jumped
~280,000 cycles to 729,884,779 — the largest single advance since the tick.
New frontier is the system-control block (0x0c120c18), modelled with the same
zero-reset RW latch treatment (block 0x0c120c00..0x0c120c20 added to the
board register-latch model). 10 periodic ticks now. Still the white clear;
chasing toward the server/UI startup where SplashScreen blits the logo.

## 2026-10-29 device-init tail walked; stop at uninitialized kernel singleton (update made with Claude)

After the synthetic NOS registration (below), the boot streamed through the
whole device-init tail with bounded, opt-in peripheral models added to
`scratch/boot-v15-nosprobe`:
- `keypad-gpio`: board GPIO/PUP pin-config as zero-reset RW latches over the
  whole UIF/GPIO page (0x0c150000..0x0c1504ff) and PUP page
  (0x0c14f000..0x0c14f0ff), plus a widen rule so a GPIO register latched at one
  width serves other widths with new bytes reading zero (idle input). Specific
  handlers (CBUS, UIF-protocol, ADC, timer) keep precedence by running earlier.
- `icu-banks`: IRQ-ICU enable-set/clear/pending banks (0,1,2); pending reads 0.
- `timer-units`: timer units 1..4 as RW latches (status reads not-expired).
- ICU enable writes to 0x0c120108/0x10c that are not the timer-0 values now
  defer to the ICU bank model (so enabling IrqTimer1 = value 2 is accepted).
All board tests pass (incl. new per-feature boundary tests); defaults unchanged.

The boot reached cycle 729,606,213 and faulted on a virtual call
`ldr pc,[r3,#0xc]` at VA 0x5033183c: the function loads a singleton pointer
from global [VA 0x80006bc4], takes its vtable and calls method +0xc. The
singleton at 0x80006bc4 is never initialized (no write in the captured memory
tail), so the vtable fetch/dispatch aborts; the fault handler records PC
0x5033183c and fault code 0x10000000. This is a kernel singleton left null by
incomplete init — not a missing MMIO register. Next: disassemble the owning
function and identify what populates [0x80006bc4] and whether a stub (NOS, a
driver modelled only as latches) prevented it; it may need another synthetic
interface registration or a fuller driver model. The NOS/baseband content gap
is unchanged. No pixels yet; LCD still the white clear.

## 2026-10-29 synthetic NOS registration clears product_info; into ekeyb keypad (update made with Claude)

Disassembly (recorded in the investigation) showed product_info faults only
because the real NOS, during its entry call, registers "interface #3/#6" with
the kernel Variant singleton ([0x8000038c]); it is NOT an ISI round-trip, and
product_info tolerates garbage parameter values gracefully. The no-op stub was
therefore upgraded to a minimal synthetic registration routine
(`scratch/nos-stub-blob/nos_stub.S`, built with arm-none-eabi, embedded as
`scratch/boot-v15-nosprobe/nos_stub_blob.h`): entry at VA 0x5149d284
trampolines into a routine that reads the Variant pointer, calls
RegisterInterface(variant,3,iface) and (…,6,…) and the readiness setter, with
an all-`MOV R0,#0; BX LR` interface vtable so every method returns without
writing. Served read-only for both code and data over PA 0x0009d000..0x0009d288
(VA 0x5149d000; the kernel maps VA 0x51400000→PA 0x0 per the dumped L1 in
`boot-v15-nosprobe/l1-final.tsv`). Because that window lies inside the core
digest range, the digest-probe was recomputed over the image AS SERVED
(factory + stub overlay): `build/firmware/nem4-factory/digest-probe-core-nosstub/`.
NOT authentic — placeholder for the hardware-descrambled baseband, swappable.

Result (`build/sim/runs/boot-v15-nos-stub/`): the digest passes, nosstarter's
call returns, product_info and the kernel interface-waiter are satisfied
(nos_stub_fetches 300 = kernel actively reading the registered objects), and
the boot advances past product_info/ekeyb-registration to cycle 729,585,848,
where ekeyb (the keypad driver, VA 0x5041a4xx) configures the keypad GPIO block:
halfword registers phys 0x0c150400/0402/0404/0408 via the 0x58000000-window
writer at 0x503245bc/0x50324608. Modeled with an opt-in `keypad-gpio` probe:
zero-reset RW halfword/word latches over 0x0c150400..0x0c15040f (config writes
read back; input reads are zero = idle, no keys) — a standard GPIO-bank model.
Rerunning with it; next frontier expected further into device init
(display/MMC/window-server), per the EFile→EStart→EwSrv→Starter→SplashScreen
chain. No pixels yet; LCD still the white clear.

## 2026-10-29 NOS entry stub passes nosstarter; new frontier product_info/ISI (update made with Claude)

Since the authentic NOS/baseband bytes exist in no available file, an explicit
opt-in SYNTHETIC stub was added (`scratch/boot-v15-nosprobe`, option
`nos-entry-stub`): code fetches at PA 0x0009d280..0x9d29f (the NOS entry line,
reached via the kernel's VA 0x51400000 raw-flash window — confirmed mapped:
L1[0x514..0x518]=0x00000..0x40000|0x43e, PA 0x02400000+, dumped in
`build/sim/runs/boot-v15-nosprobe/l1-final.tsv`) return `MOV R0,#0; BX LR`.
Data reads and writes are never served by the stub; board tests cover the
boundaries. This is NOT an authentic boot component — it is a placeholder for
unavailable hardware-descrambled baseband code, swappable for real NOS content.

Result (`build/sim/runs/boot-v15-nos-stub/`): nosstarter's call returns cleanly
and the kernel CONTINUES into the extension-init loop (0x50331680 walking the
kernel-extension directory: rtc, nosstarter, pnmsg, isimsg, phonet, cbus,
helper.ldd, medint.pdd, ELocal.fsy, EUser, Hal, EFile, EFSrv, EStart, EDISP,
btldd...). ~6,500 cycles later it faults with a kernel panic naming
product_info.DLL (diagnostic write 0x0c0047f0='prod', the fault path prints the
ROM banner "product_info.DLL V 4.03 26-11 NEM-4 (c) NMP. N-Gage"). No bus
access precedes the fault — it is a CPU/RAM panic during ISI/baseband extension
init, the expected consequence of a no-op NOS (the Pocket HLE core answers ISI
queries via a fake NOSDRIVER; see `docs/references.md` and
[[ngage-pocket-core-reference]]). The next frontier is therefore the ISI/Phonet
extension init path, not a new MMIO register. Investigate what pnmsg/isimsg/
phonet/product_info init require from the NOS (likely ISI message round-trips
the stub must answer, per the Pocket core's documented energy-mgmt/identity
replies) before extending the stub into a minimal ISI responder. This is the
first point where the missing baseband's behavior — not just its bytes —
matters.

## 2026-10-29 scramble closed: CMT-side hardware descramble; boot remap found (update made with Claude)

Cipher analysis (consolidated in `scratch/nem440-flash-extract/out/cipher-analysis.json`)
closed the encrypted-region question. The container's algorithm blob is a flash
program/erase driver + field-service loader (strings dev_flash.c, loc_task.c,
FLL_01_43_00; the only crypto inside is the Bluetooth SAFER+ suite, uncalled on
the write path) — it programs payloads verbatim. The opaque region is CS0 phys
0xA000..0x2B3000, scrambled for the DCT4 cellular-MCU (CMT) fetch path and
descrambled by UPP hardware on that side; the scramble is stateless, word-local
and position-keyed, and provably not any byte/word XOR, additive keystream,
GF(2)-affine map, or phosher/DCT4Crypter-style construction (2 MiB of exact
known plaintext exists because factory phys 0x50A000..0x700000 is the
plaintext twin of 0xA000..0x200000). Phys 0x200000..0x2B3000 (0xB3000 bytes)
has no plaintext twin and is unrecoverable from files. Public knowledge agrees
(DCT4Crypter/phosher cover classic DCT4 only; WD2/Symbian variant undocumented).

Newly discovered boot behavior that resolves the dump "artifacts": boot code at
phys 0x33E4..0x34C8 patches the page tables, adding +0x500000 to the physical
base of every page in [0xA000, 0x317000) — the ARM920 reads the plaintext twin
at 0x50A000+, the PPM bank, and the 8-MiB chip mirror, exactly reproducing the
phone dump's layout. The Symbian side never reads the scrambled window. The
supplied dump is therefore a faithful post-remap view, and identity-mapping the
dump in the simulator has been accidentally correct. Plaintext Nokia ENOS
CMT_SW Thumb code begins at phys 0x2B3000 (source paths at 0x2c7e3c).

The main digest stays unmatched and is provably unmatchable from the
containers: even the real phone's own content hashes to 1784c17a..., not the
embedded 2c09c86f... (90+ layouts tried, including the exact boot-remap view).
The expected value most plausibly covers golden pre-personalization content
(the 56-byte per-device hole sits inside the digest window via the 0x300000
mirror; EEPROM-emulation sectors at 0x7F0000/0x7FC000 mutate at runtime). The
digest-probe accommodation therefore stands, now with a precise justification.

The .326 extension at phys 0x4730000 (VA 0x51230000) begins with a valid
scanner-compatible EKA1 extension header: next-base 0x51230000, size 0x140000,
root list 0x51230080, version/time words matching the core's — and its content
digest passes. v4.17 extraction lives in `out-v417/` (extract_tolerant.py; the
original parser lost sync once on a checksum coincidence). Next: assemble the
factory-faithful flash image set (factory bytes, erased-FF gaps, real .326
extension in place of the synthetic reconstruction), regenerate the digest
probe over it, and run V15 from reset. The nosstarter NOS-image gap (CS1 upper
half / third CNT container) remains the open content question.

Done: `scratch/authentic-flash-image/assemble.py` builds
`build/firmware/nem4-factory/{core.bin,extension.bin,manifest.json}` (VA-linear
factory content, MCU+PPM flash-order overlay, per-device hole and unwritten
flash erased 0xFF) — the .326 extension descriptor verifies over the assembly
(0b1173ee..., PASS). `digest-probe-core/SYM.ROM` replaces only the 16-byte core
expected-digest field (new computed value ac2ac9c5...; manifest records
before/after). The V15 from-reset run on the factory inputs completed at cycle 729,407,390 on
the identical nosstarter frontier (diagnostic write 0x0c0047f0=0x5149d290):
the extension scanner handled the erased head, the firmware's own extension
digest check passed on authentic content, both digest gates cleared with only
the 16-byte core accommodation, 8 periodic ticks and the RTC/debug-console
sequence ran as before. Output `build/sim/runs/boot-v15-factory/`; screen is
the assumed white clear. This is the cleanest validated configuration to date;
`boot-v15-factory` supersedes `boot-v15-periodic` (dump-input lineage).

The sole remaining blocker to further boot progress is CONTENT, not modeling:
the extension head (VA 0x511c0000..0x5123e338, retail CNT container) and the
NOS image (CS1 upper half, PA 0x02400000+0x400000). Next development session:
obtain a NEM-4 CNT container or a hardware CS1 chip read; alternatively
investigate the QD images' equivalent modules (read-only, for identification
not substitution) to name the component that installs the 0x514xxxxx mapping.

## 2026-10-28 factory flash files extracted and validated (update made with Claude)

`scratch/nem440-flash-extract/` now holds a checksum-validated parser for the
Nokia "WD2 BT2" containers (record grammar documented in extract.py: data
records [0x14][phys addr:4 BE][ck1][len:3 BE][ck2][payload], both files parse
end-to-end with zero residue) and extracted images under out/ with full
per-record JSON maps. nem440.3c1 programs CS0 0x0..0x6FFFFF, CS1
0x2000000..0x23FFFFF, CS2 0x4000000..0x46B4FFF plus an embedded 0x2dd94-byte
flash algorithm blob; nem440.326 (PPM) programs the updated ROM header words,
CS0 0x700000..0x76BFFF and CS2 0x4730000..0x47FFFFF.

Verified: the .326 extension digest descriptor (VA 0x51230000..0x5136BFFF,
MD5 0b1173ee849db3045a8a0b78507bd96b) matches the extracted content exactly —
the factory extension is authentic, bit-validated, and supersedes the
synthetic reconstruction. The factory core matches the dump byte-exactly over
phys 0x317000..0x11B5000 (14.5 MiB); the dump's lower window is proven
artifact (2 MiB self-duplication, another build's PPM content, duplicated
header) — the dump fails its own digest for that reason. The main digest
(2c09c86f...) remains unreproducible because phys 0xA000..~0x2F0000 (~2.9 MiB)
in the factory file is ENCRYPTED (8.0 bits/byte, referenced by no ROMFS entry
or E32 header); its plaintext exists in no available file. That blob's size is
close to the expected NOS image (~3 MiB at CS1 0x2400000+, which neither file
programs), and the containers ship a flash algorithm that runs on the phone
during flashing — a plausible decrypt-and-place agent. Cipher analysis is in
progress. The ROOT dump's first ~0xC0000 bytes match neither factory file:
retail phones carried a third container (CNT/content pack) for the extension
head (VA 0x511C0000..0x5123E338). Unwritten factory gaps (erased 0xFF on a
fresh phone): phys 0x46B5000..0x472FFFF and the PPM-bank tail above 0x76C000.
Bank tables in factory and dump are identical (an earlier divergence note was
wrong). BOOT-101F8C19.dmp equals phys 0x321000 (kernel code start).

A second complete build arrived: `firmware/NEM-4 v4.17 EN/` (nem441.7d1 MCU +
nem441.738 PPM, extracted from the V4.17 RAR-SFX updater; source link in the
archive: gem-flash.com). The MCU file is byte-identical in size and format to
v4.03's; the encrypted CS0 region differs between builds in 320/371 records
(build-varying code — consistent with the NOS image), giving the cipher
analysis a second ciphertext at identical addresses.

Next: verify the .326 extension begins with a scanner-compatible image header
at phys 0x4730000, assemble an authentic flash-content set for the board model
(factory bytes, erased-FF gaps, no synthetic tail), identify the cipher of the
encrypted region via the flash-algorithm disassembly, and ask the user for
possible additional factory containers (CNT/content pack; ISA/NOS flash file)
from the same source.

## 2026-10-28 authentic run validated; frontier identified as the NOS entry; factory flash files arrived (update made with Claude)

The authentic from-reset run (`scratch/boot-v15-periodic/run.py`: V15 cache CPU,
all-0x257e flash, no RAM intervention, periodic tick, all current probes)
completed at cycle 728,190,258 on the identical frontier as the fast chain: the
kernel crash write 0x0c0047f0=0x5149d288 after calling VA 0x5149d284. It passed
VARIANT authentically, delivered 8 periodic ticks, completed the RTC read-out
and printed the same "TRtcQueue::Add: 2" debug line. Outputs
`build/sim/runs/boot-v15-periodic/`; screen remains the assumed white clear.

Instruction-level disassembly identified the frontier precisely: nosstarter.ext
(148 bytes at file 0x3504a0, entry 0x50350504) copies 0x5790 bytes of
initialized data from VA 0x51711138 to 0x80006ef0 (EUser Mem::Copy), zeroes
0xc27a8 bytes of BSS at 0x8000c680, and calls VA 0x5149d284 with r0=-1 — the
entry point of the separately linked NOS/baseband (ISA cellular) program that
lives in flash OUTSIDE the Symbian logical ROM. The core ROM references exactly
two addresses above the ROM window: 0x5149d284 and 0x51711138 (both nosstarter
literals; all other 0x51400000+ word hits are data noise/0x51EB851F constants).
All three firmware variants contain the same stub with per-build addresses
(RH-29: 0x5149e4c4/0x5170b054; RH-4: 0x5149f934/0x517050c4). The superpage
carries a type-3 bank window {PA 0x02400000, size 0x600000} (CS1 upper half) —
the evidence-consistent home of the NOS image, probably mapped at VA
0x51400000; kernel-side confirmation of the mapping code is in progress. The
NOS content exists in NO supplied dump (the in-phone dumper faulted at
0x51370000; signature/literal-density searches across all dumps are negative).
Do not stub the call: the goal is an authentic boot.

Kernel-side mapping disassembly settled the window question: bootstrap routine
0x1ff8 maps the type-3 banks unconditionally, pre-MMU, with a running VA cursor
from 0x58000000 — the NOS window PA 0x02400000 (+0x600000 declared) lands at
VA 0x59200000 (uncached, L1 entries 0x02400432..) and again at VA 0x59800000
(cached, 0x0240043a..), supervisor-only AP=01 (which is why the on-phone
user-mode dumper could never read it). No code in any supplied image writes an
L1 entry for VA 0x514xxxxx — ekern never walks bank types, and the exception
dispatcher reached the fatal mailbox path, so no runtime abort-fixup handler
was registered either. The variant ecust.dll geometry method (file 0x349c98,
the ROM's only 0x59200000 literal) reports the NOS/baseband flash as PA
0x02400000 size 0x400000 for our flash classes. Conclusion: the agent that
creates the real phone's 0x514xxxxx linear mapping (or abort fixup) must live
in the unrecovered extension head VA 0x511c0000..0x5123e338 — synthesized as
directories+FF in our reconstruction. The content gap is therefore twofold:
the real extension head AND the NOS image at PA 0x02400000..0x027fffff. Do
not hand-add a 0x514xxxxx mapping; without real NOS bytes it only moves the
frontier to an unbacked fetch at PA 0x0249d284.

The user supplied Nokia factory flash-programming files
`firmware/NEM-04 v.04.03 N-GAGE/nem440.3c1` (MCU, 18,777,938 bytes) and
`nem440.326` (PPM, 1,361,703 bytes), dated 27-11-2003 — DCT4 "WD2 BT2 /
STARSHIP & BT ALGORITHM" containers. Initial analysis: the core ROM image is
embedded from .3c1 offset 0x2defc with periodic block framing (~0x500 bytes
per MiB, grammar not yet derived) and differs from the dump in content
(header checksums at image +0x84/+0xa8, the bank-table region, and the digest
descriptor region ~0x8d06 where the factory bytes carry the expected MD5
2c09c86f... — the factory image may pass the digest check the dumps fail).
Container reverse-engineering and full extraction are in progress in
`scratch/nem440-flash-extract/`; if the files program CS1 0x02400000+ the
missing NOS image is recovered and the digest-probe input modification can be
retired. A Nokia 6600 factory file (`firmware/NHL-10 v.05.53 6600.rar`) is
also available for format cross-reference.

## 2026-10-28 kernel runs to the extension-VA frontier (update made with Claude)

With the tick, block-0x14d probe, debug sink, and explicit kernel-phase CBUS
inputs (new repeatable `cbus-input=REG=VALUE`, supplied zero for registers
0x20–0x34; observed reads so far 0x24, 0x31, 0x33, 0x21 — the RTC path), the
continuation `build/sim/runs/boot-variant-periodic-timer/` processes four
periodic ticks, completes the kernel RTC read-out and the "TRtcQueue::Add"
debug line, and runs to cycle 453,235,865. It then stops on the diagnostic
mailbox write 0x0c0047f0=0x5149d288 from the kernel crash path: the nosstarter
region code at VA 0x5035053c performs `MOV PC, R4` with R4=0x5149d284 (a core-
ROM literal at file offset 0x350548), and that VA takes an MMU translation
abort — no bus access is attempted, so the kernel simply never mapped it.
VA 0x5149d284 lies ~700 KiB beyond the reconstructed extension's end
(0x513f0000) and beyond bank table 0x830's 19.94 MiB span; this is the
predicted missing-ROM-content frontier (flash-layout.md's CS2 0x046c001c
question). Research is in progress to reconcile the extension descriptors,
the CS2 physical mapping, and whether any supplied dump contains the content.
Do not paper over this with a stub: the call is the NOS/baseband starter path
and the goal is an authentic boot.

The authentic from-reset run (`scratch/boot-v15-periodic/run.py`, V15 cache
CPU, all-0x257e flash, no RAM intervention, all current probes) was launched
and is expected to reach this same frontier in a few hours; output
`build/sim/runs/boot-v15-periodic/`, screen capture attempted on completion.

## 2026-10-28 periodic tick delivered; kernel debug console found (update made with Claude)

The corrected periodic-tick model (scratch/variant-periodic-timer, option
`timer-periodic`) now matches the kernel disassembly: the kernel reload write
0x632ea with control 2 arms a free-running tick; the stale early-boot enable is
treated as cleared until the kernel's own enable-set 0x0c120108=1; any status
write to 0x0c120a08 acknowledges; ICU current 0x0c120114 reads 1 (IrqTimer0)
while pending and 0 after acknowledgement; secondary banks 0x0c120154/0x194
read 0; the dispatcher-exit entropy read of 0x0c120a10 returns the compare
latch. The continuation `build/sim/runs/boot-variant-periodic-timer/` matched
all 241 predecessor bus rows, delivered the tick at cycle ~452,656,800, and the
authentic kernel IRQ path executed exactly as disassembled: vector 0x18 →
0x50327698 → dispatcher 0x5032287c → ICU current=1 → tick ISR 0x503225b0 →
status ack 0x0c120a08=0 → drain reads → wait flag 0x8000000c set → idle loop
woke. Full IRQ-path disassembly notes (dispatch table [0x800066e0] index
IRQ+0x5c, ID map "IrqTimer0"=0x5d, FIQ-ICU at 0x0c1201c0 — the 0x0c1201c8
write enables FiqAPIIOAbort and is unrelated to the tick) are recorded in
[uem-control-bus.md](uem-control-bus.md). The timer tick unit (one CPU cycle)
remains an unverified assumption.

After the tick, kernel routine 0x5032430c initialized an unidentified UPP
block (0x0c15053c=0xffff, 0x0c15053a=0x4c, 0x0c14d000=2/0x300, 0x0c14d004=
0x205, 0x0c14d008=0, reads of 0x0c14d00c/0x10), modeled by the explicit
zero-reset `block14d-probe`. The kernel then began writing characters through
routine 0x503243a8 (CR/LF handling, gated on a debug-enable flag) to a
byte-addressed window at VA 0x59000000 = physical 0x0de00000: the write-only
`debug59-sink` captured genuine Symbian kernel trace text, starting with
0xc0 then "TRtcQueue::Add: ". The device identity (debug console buffer) is
unverified; bytes are retained in the result JSON as `debug59_text`.

`scratch/boot-v15-periodic/` is the authentic-path configuration: V15
cache-enabled CPU, all-0x257e flash (no RAM intervention, counterfactual code
removed), the periodic tick and both new probes; its `sync-from-chain.py`
reapplies the deltas after chain updates, and `run.py` performs the from-reset
1e9-cycle run with capped logs and a screen-capture attempt. Board tests for
both directories pass. Launch the long run once the fast chain stops
discovering new registers at this cadence.

## 2026-10-28 flash identity resolved by disassembly (update made with Claude)

Full disassembly of the firmware's flash probes settles the VARIANT question.
The first probe (file offsets 0x95c–0xb34, chooser 0xb38) identifies only CS1
(and Intel-on-CS2): AMD mfr 0x0001 with first ID word 0x257e or 0x267e →
result 2 → bank table 0x830 (16 MiB RAM); 0x22d1 → table 0x744; nothing →
fallback 0x638 (8 MiB). 0x227e matches nothing there. The classifier at 0x5cc0
(helpers 0x598c/0x5a34/0x5ad8, pools listed in flash-layout.md) maps
0x257e/0x2502/0x2500 with handshake bit0=0 (0x42) → class 4, and
0x227e/0x2202/0x2200 with bit0=1 (0x43) → class 0. The config routine 0x5d74
gives classes 0/4/5/6 the same timing word 0x10202132, and class 2
(0x227e + 0x42) hangs on CS0/CS1. The validator at 0x34933c only requires the
middle chip's class to repeat an already-seen family (hence 0,4,0 faults and
homogeneous sets pass); classes 0/4/5 select the same AMD burst driver.

Therefore all three chips reporting 0x0001/0x257e/0x2502/0x2500 with handshake
0x0042 is the unique self-consistent configuration: table 0x830 (16 MiB SDRAM,
matching the NEM-4 schematic), classes 4,4,4, validator accepted, no RAM
intervention. Public Am29BDS643G parts return 0x227e/0x43 (datasheet in
`scratch/research/schematics/am29bds643g.txt`, autoselect table + note 10:
0x43 = handshaking enabled), and no public AMD part returns 0x257e — the
schematic's AM29N643GT70MVAI has no public datasheet and is evidently a
Nokia-custom part the firmware was built for. Unverified remainder: the real
chip's autoselect words (inference from firmware expectations), burst/CFI
protocol details, dump-tail coverage of table 0x830's 19.94 MiB spans versus
the 17.75 MiB image, and chip-select assignment. The flash-class RAM
counterfactual is fully explained and permanently retired. The authentic
configuration equals the existing `flash-all-257e-probe` model; the completed
`boot-v15-all-257e` run (cycle 725,805,161, past VARIANT, stopped at the
0x0c120074 frontier) is the from-reset baseline to extend.

## 2026-10-28 periodic timer: kernel IRQ dispatch reached (update made with Claude)

Goal restated by the user: an authentic boot to the Nokia logo — the firmware
must execute its real path. The flash-class RAM counterfactual is therefore not
an acceptable final path; it remains only a discovery tool on the fast
cache-off checkpoint chain. The authentic target configuration is the V15
cache-enabled CPU with defensible flash IDs, run from reset.

`scratch/variant-periodic-timer/` adds the explicit opt-in `timer-periodic`
hypothesis modeled on the Nokia 6600 recompiler `nk_bus_tick`: the observed ICU
`0x0c1201c8=0x08000000` write arms a periodic IRQ with the latched compare
period `0x632ea` (406,250 cycles); expiry presents timer status bit 0 at
`0x0c120a08`, and the observed write-1 acknowledgement clears it. Board tests
cover arming order (requires SYSC74 and the compare write), early-fire, ack,
re-fire, and constructor rejection; defaults are unchanged and
`test_default` passes. The timer tick unit (one CPU cycle) is an unverified
assumption.

The checkpoint continuation `build/sim/runs/boot-variant-periodic-timer/`
matched all 241 predecessor bus rows, took the periodic IRQ at cycle
~452,847,900 (one IRQ delivered), and executed authentic firmware IRQ entry:
vector 0x18 → handler 0x50327698 (SUB LR,LR,4; stack setup; a zero check at
0x80005e78) → dispatch at 0x5032287c, which loads literal 0x58120114 and reads
physical `0x0c120114` — the UPP ICU current-IRQ register predicted by the 6600
model. The run stops there: the register value (the IRQ number the kernel
dispatches on) is unknown. Disassembly of the dispatch table is in progress to
determine which value routes to the tick handler (0x503225b0..0x50322610) that
sets the kernel wait flag 0x8000000c. Do not guess this value; a wrong number
dispatches to the wrong kernel handler.

Separately verified by firmware/bitmap analysis: the first drawn logo on this
platform is Symbian `SplashScreen.exe` blitting `SPLASHSCREEN.MBM` (ROM-format
MBM at SYM.ROM offset 0x9718d0; bitmap 0 is 176×208 8bpp EByteRLE, ~1,463
non-white pixels — the embossed NOKIA logo; a 20-frame 176×208 12bpp startup
animation lives at offset 0xbc3140). The boot chain to it is
EFile→EStart→EwSrv(+scdv/lcd.ldd/FbServ)→Starter→SplashScreen, all XIP from the
mapped ROM; no extension-image bitmaps are involved. Success signature in a
trace: ROM reads near offset 0x97191c followed by non-uniform LCD data words.
Expected later obstacles (from the 6600 bring-up): a second timer/IRQ source,
Init3 HAL/UEM requests, C:-drive mount through medint.pdd (flash write/erase),
and Starter's baseband/NOS synchronization.

The earlier `boot-variant-wait-trace` result was reproduced bit-identically
before new work (all six output files; log differed only in one interleaved
startup line).

## Cache-off GPIO continuation and V15 run

The verified cache-disabled checkpoint continuation with opt-in
`gpio214-low-zero` matched the previously recorded bus prefix and executed
GPIO 0x0c150214 low read=0 and write=0x0180. It next stopped on a read of
PUP high halfword 0x0c14f006 at cycle 452,340,540.
`scratch/gpio214-probe/resume.py` and
`build/sim/runs/boot-checkpoint-gpio214/` retain the run.

Two further explicitly speculative zero-reset probes (PUP 0x0c14f006 and
0x0c14f004 low) and the separate exact write sink GPIO 0x0c150206=0x0006
passed board-model tests, including disabled/default and independent-halfword
checks. Each checkpoint continuation matched its predecessor's bus prefix.
The last continuation `build/sim/runs/boot-checkpoint-gpio206-extra/`
reached an unmapped diagnostic write at cycle 452,422,362, physical
0x0c0047f0=0x49524156, ASCII `VARI`; firmware copied `VARIANT` to diagnostic
RAM and stored code 0x00010013. Tracing shows a comparison at PC 0x503494fc
of index 1 against 2 (the table length 3 minus 1), followed by the variant
fault branch at 0x50349658. Before that, at PC 0x5034931c, firmware copied
values 0,4,0 from virtual 0x5a00f00c (physical 0x0a01200c) into its table.
A focused write trace from the retained checkpoint captured no writes to
physical 0x0a012000–0x0a01201c until firmware cleared it later; those values
were already present at the checkpoint. Evidence:
`build/sim/runs/boot-variant-table-trace/variant-table-writes.log`.
A longer bounded trace shows PC 0x503490b0 mapping physical 0x0a012000
(length 0x4f000, flags 0xe) to virtual 0x5a00f000. A short cache-off run
from reset `build/sim/runs/variant-early-trace/` captured the table source:
firmware probes the three modeled flash devices at PC 0x5cc0, classifies CS0
as 0, CS1 as 4, CS2 as 0 and writes 0,4,0 at cycles 33,842–33,846; it
then stores constant 2 at cycle 40,553. The flash model supplies 227e/2202/
2200 and handshake 0x43 for CS0/CS2 but speculative 257e/2502/2500 and
handshake 0x42 for CS1; its assumed CS1 classification is 4. The original
firmware routine at PC 0x5034933c was independently executed in Unicorn with
controlled class tables: 0,4,0 reaches VARIANT fault 19; 0,0,0 and 4,4,4
are accepted, as is 0,0,4. The test stops before later side effects and uses
synthetic RAM; source/results `scratch/variant-class-test/`. Thus the classes
deterministically cause this validation failure in the exercised routine, but
correct physical IDs remain unresolved. The Nokia NEM-4
schematic labels all three flash chips AM29N643GT70MVAI, so this asymmetry
needs investigation. The original firmware's first probe recognizes 0x257e
and selects table 0x830 (16 MiB RAM), while 0x227e does not match its AMD
first-probe comparisons and leads toward fallback table 0x638 (8 MiB RAM).
Do not simply change IDs or bank mappings: reconcile schematic, datasheet,
firmware selection logic, dump layout and SDRAM first. The separate long
cache-off origin trace was stopped after the short run captured the relevant
early writes; no final result is expected from it. Do not assume these device values are correct or
treat this diagnostic write as ordinary startup. Its origin remains open; this
cache-disabled run does not establish the V15 outcome.

LCD-only capture, based on the original pre-checkpoint trace plus resumed LCD
writes: `build/sim/screens/boot-checkpoint-gpio206-extra/screen.png` (assumed
white clear, no logo), provenance `build/sim/runs/lcd-gpio206-extra/sources.json`.

The fixed-cache V15 firmware run completed via
`scratch/boot-v15-gpio-experiment/run.py` at cycle 725,795,188: it passed the
earlier cache abort and reached the same VARIANT fault 19 / diagnostic write
0x0c0047f0=0x49524156. The trace records the branch at 0x50349500 and code
0x00010013 stored at 0x40000410. Its trace independently shows table entries
0 and 4 at 0x804040c0/c4 and the same modeled identify responses as the
cache-off trace. Outputs/provenance:
`build/sim/runs/boot-v15-gpio-experiment/`; screen
`build/sim/screens/boot-v15-gpio-experiment/screen.png` is the interpreted
white clear, not a Nokia logo. It used the explicit GPIO/PUP and mixed flash
ID assumptions, modified digest-probe ROM and reconstructed tail; these are
not verified physical devices. No simulation is running.

## Synthetic continuation after the VARIANT diagnostic

Only in the explicitly artificial class-0 counterfactual, the firmware reaches
word write 0x0c120074=3. `scratch/variant-sysc74/` accepts that exact write
without side effects; `scratch/variant-gpio24/` accepts only the following
low-halfword GPIO 0x0c150024=1 and 0x0c150028=1 writes, after that setup.
`scratch/variant-timercompare/` accepts the exact timer compare write
0x0c120a10=0x632ea as a latch without scheduling another interrupt. A Nokia
6600 recompiler also calls offset 0x10 compare, but its behavior is not
proof of N-Gage hardware. `scratch/variant-sysc50/` accepts the subsequent
exact writes 0x0c120050=7 and 0x0c120044=2. These are opt-in probes, not
implemented hardware; enabled/default and width/value boundaries were tested.
The generated comparison scripts initially contained a self-comparison bug;
they have been corrected. Independent post-run comparisons against the actual
predecessors confirmed matching bus prefixes for all ten continuation steps.

The bounded run `build/sim/runs/boot-variant-sysc50/` stopped at cycle
452,441,592 on 0x0c1201c8=0x08000000. The opt-in write-only sink in
`scratch/variant-icu1c8/` lets the synthetic run proceed to its 455,000,000
cycle limit, where it repeatedly polls 0x8000000c=0 at PC 0x50322674. It
models no interrupt side effect; timer pending=false and remaining=0. Output
`build/sim/runs/boot-variant-icu1c8/`. Its original prefix-check wrapper
incorrectly compared against itself; independent comparison verified 238 rows
against the preceding run, and the wrapper has been fixed. Investigate the
expected writer and timer/IRQ semantics before declaring a real hang. This
is in the synthetic flash-class path and must not be reported as authentic
boot. Full comparison with all-hypothetical 0x257e IDs completed; see the following section.

## Fixed-cache all-0x257e flash hypothesis

A bounded 100,000-cycle V15 diagnostic with all three modeled flash devices
reporting 0001/257e/2502/2500 and handshake 0x42 generated classes 4,4,4
and selected the 0x830 bank table with 16 MiB RAM. Output/provenance:
`build/sim/runs/flash-all-257e-probe/`. Those IDs are a hypothesis; the
schematic labels AM29N643 chips and a candidate Am29BDS643G datasheet lists
different IDs, so this is not verified hardware.

A separate full V15 run with the same hypothetical IDs and explicit GPIO/PUP
assumptions completed at cycle 725,805,161 on unmodeled write 0x0c120074, via
`scratch/flash-all-257e-probe/run-long.py`. It reuses the short-test simulator
only after verifying the binary and source hashes, caps its log, and writes to
`build/sim/runs/boot-v15-all-257e/`; on completion a screen capture is attempted
at `build/sim/screens/boot-v15-all-257e/`. It has no RAM-class intervention.
This is a diagnostic comparison, not a claim about physical chips or boot.
Inspect the saved result before duplicating.

## All-equal flash-ID short diagnostic

`scratch/flash-all-equal-probe/run.py` uses the cache-disabled CPU, all three
flash IDs 0001/227e/2202/2200 with handshake 0043 and fallback bank table 0x638.
It stopped at cycle 554 on a CS2 array read at 0x04000000: that bank table
does not describe the third chip's ROM contents, and the physical dump
placement is unknown. Do not substitute data silently.

`scratch/flash-all-equal-erased/run.py` is a separate counterfactual that
returns all-ones only for the two observed CS2 probe halfwords; this value is
not verified. It completed its bounded 50,000 cycles and firmware wrote flash
classes 0,0,0 and the following constant 2 to RAM. Its resulting 0x638 table
exposes only 8 MiB RAM, whereas the NEM-4 schematic describes 16 MiB SDRAM;
its logical ROM mapping is also unverified. Outputs/provenance are
`build/sim/runs/flash-all-equal-{probe,erased}/`. This is not an authentic
phone configuration and does not prove a boot or fix. A separately bounded
continuation `build/sim/runs/flash-all-equal-erased-2m/` reached its 2,000,000-
cycle limit without another unmodeled access; this does not test full boot or
resolve missing flash data. Reconcile the real
flash identities, CS2 contents and board/ROM configuration before using it.

## Flash-class counterfactual

`scratch/variant-counterfactual/` is an explicitly synthetic diagnostic, not
a board model: after restoring the cache-disabled checkpoint it verifies the
RAM words 0,4,0,2 at physical 0x0a01200c and changes only 0x0a012010 from 4
to 0. With the same explicit GPIO/PUP probes, the firmware passes the prior
VARIANT diagnostic and stops at cycle 452,428,883 on an unmodeled word write
0x0c120074=3 from PC 0x50322728. The preceding bus prefix matched the saved
PUP continuation. Output/provenance: `build/sim/runs/boot-variant-counterfactual/`;
the log records the intervention. The LCD transport count remains 18,353 data
words, consistent with the earlier clear; no new logo is established. This
proves only a counterfactual dependency, not the correct flash IDs, physical
memory layout or an authentic boot. A second intervention in
`scratch/variant-all-four/` changed the first and third saved classes to 4,
yielding 4,4,4; it also reached 0x0c120074=3 at cycle 452,428,883. The
trace confirms both tables were actually read as intended. Output:
`build/sim/runs/boot-variant-all-four/`. These alternatives do not determine
which hardware configuration is correct. Do not promote either intervention.

## GPIO 0x0c150214 investigation

The completed V15 boot passed the prior abort and stopped at cycle
725,682,218 on a low-halfword read from physical 0x0c150214. The firmware
helper at PC 0x50324614 reads that halfword, clears the mask in R2 (0), ORs
the mask in R1 (0x0180), and writes it back. Thus bits 7 and 8 become one,
but the other reset bits remain unknown. The previously modeled upper halfword
is separately assumed zero. The schematic gives physical wiring but no
verified register/reset value for this access.

Local EKA2L1 reimplements the Symbian kernel and servers and has no N-Gage
physical GPIO register model; local rengage merely maps a generic MMIO buffer
and its checked-in code has no GPIO device model. Neither supplies a verified
value for 0x0c150214. See `scratch/references/EKA2L1/README.md` and
`scratch/references/rengage/src/main.cpp`.

`scratch/gpio214-probe/` is a separate experimental board model with explicit
`gpio214-low-zero` option: only after the existing IRQ/upper-halfword sequence
it assumes the low halfword starts at zero, permits read/modify/write, and
preserves the high halfword. This is a test hypothesis, not hardware fact.
Both the new hypothesis tests and the unchanged default-boundary tests pass;
without the option the low read remains unknown. The model has not yet been
used in a firmware simulation. The next step is build a compatible simulator
using `scratch/no-data-cache-probe/zap/src/rtl`, `rtl/ngage_cpu.sv`,
`scratch/checkpoint-probe/ngage_cpu_sim.sv`, and `scratch/gpio214-probe/{main.cpp,boot_profile.cpp}`
with `--savable`, then adapt `scratch/checkpoint-gpio206/resume-gpio206.py`
to use the new binary and `gpio214-low-zero`. Restore the verified existing
`build/sim/checkpoints/ngage-before-cbus27.*` checkpoint, compare its prior
bus prefix and inspect the next unknown access. That checkpoint is from the
cache-forced-off experiment; it cannot prove V15 behavior. If useful, run a
separate V15 boot with this explicit hypothesis and capped logs.

## V15 premature acknowledgement fix

The short V14 PUSH/literal reproducer proved the background store completion
at `UNLOCK_REG` asserted `o_ack` for an unrelated pending load, even when
translation was still waiting. At t=172629 the waiting load of 0x5032192c
was acknowledged with zero before its ROM line had been fetched. Signal trace:
`build/sim/runs/literal-cache-trace/simulator.log`.

Scratch `scratch/ldm-identity-v15-zap/` removes the unconditional acknowledgement
of the completed background store. It passes the two short PUSH/firmware
reproducers at latencies 0/3/7/15/31, all 70 existing directed checks,
both stack words across same-line and
cross-line PUSH cases at five latencies, and IRQ/FIQ/refill-reset injection
checks at latencies 0/3/7;
V14 fails both reproducers while baseline passes. This proves the short
regression, not yet that it caused the long firmware abort. The compact 2 MiB MD5 regression passed at cycle 59,883,404 and the 4 MiB
case passed at 116,785,492; see the `results-v15-2m.json` and `results-v15-4m.json` files in
`scratch/cache-md5-length-sweep/`. The 8 MiB test passed at cycle 242,489,099; result
`scratch/cache-md5-length-sweep/results-v15-8m.json`. The first full V15 firmware run reached cycle 724,300,000, but its checkpoint
request stopped it with `post-UIF snapshots unsupported by this state version`.
It produced no final result; the incomplete snapshot was deleted.
`scratch/firmware-cache-candidate/run-v15-retry.py` completed at cycle
725,682,218, beyond the previous V14 abort. It stopped on an unmodeled
low-halfword read of GPIO address 0x0c150214; output is
`build/sim/runs/boot-v15-retry/`. The captured screen is an assumed white clear,
`build/sim/screens/boot-v15-retry/screen.png`. No Nokia logo was observed.
`scratch/firmware-cache-candidate/run-v15-manual.py` repeats the same setup in
a separate output directory; expect it to stop at the same unknown read until
the GPIO behavior is investigated. The old prepared checkpoint
replay tools use incompatible version-1 board snapshots and cannot restore
the aborted run.

Experimental checkpoint version 2 in `scratch/boot-v15-checkpoint/` saves
UIF/ICU flags and configured probe-register values. A native state round trip
with post-UIF flags passes and rejects mismatched probe configuration and
truncated input. A short actual firmware save/restore with all board options
matched status, counters and board report at cycle 2000. An invalid checkpoint
destination logged CHECKPOINT_FAILED and continued to a passing CPU result.
These do not yet verify a live late-boot checkpoint. The current retry does
not use this version; use a separate future build if needed.
Test results are retained,
bulky reproducible traces and compiler caches removed. Production RTL unchanged.


## Earlier V13 checkpoint and stopped boot

V13 is an experimental scratch-only candidate in
`scratch/ldm-identity-v13-zap/`; production RTL remains unchanged. The prior V7
1 MiB checksum failed because a correct request identity was associated with an
old TLB physical address. V13 requires a matching request to remain valid for a
second cycle while pending and clears that history on acknowledgement. It passed
all 70 directed tests (14 cases at five latencies) and the previously failing
1 MiB MD5 test in 29,784,745 cycles. These tests do not establish correctness
for all translations or the full firmware. See `ldm-replay-investigation.md`.

A provisional-device firmware boot from reset using
`scratch/firmware-cache-candidate/run-v13-long.py` was stopped before completion:
repeating TLB format warnings grew its log beyond 1 GiB despite compact trace.
The simulator container was stopped and the log deleted, retaining only its tail
in `build/sim/runs/boot-cache-identity-v13/simulator-tail.txt`. There is no boot
result or new screen capture. Latest observed bus activity reached cycle
119,630,394.

The 2 MiB digest test failed V13 (completion 0x31, cycle 58,453,970);
`scratch/cache-md5-length-sweep/results-v13-2m.json` holds its provenance.
The seven-patch baseline passes the same 2 MiB test at cycle 31,491,248;
results: `scratch/cache-md5-length-sweep/results-baseline-2m.json`. Therefore
V13 still has a cache/translation defect. A bounded state comparison found
the first mismatch in the state entering block 16577 (input 0x10c040), so
the first bad calculation occurs in block 16576 (input 0x10c000). Results:
`scratch/md5-block-trace/blockstate-2m-results.json`. The bounded instruction and bus comparison shows first wrong ADD at PC
0x3eb0: candidate reads PA 0x0000c020 instead of 0x0010c020. Two page-table
walks immediately precede it. Outputs: `build/sim/runs/md5-window-2m-*`.
The focused translation signal trace completed in
`build/sim/runs/cache-divergence-2m/`. Before any future full run, prevent
unbounded Verilator diagnostic output and verify assumptions in provenance.
The short-test result JSONs are retained; bulky regenerable traces and build
caches created during this investigation were deleted.

## New short V14 cache regression

`scratch/literal-cache-probe/dependent-push.S` is a short reproducible CPU
failure: cache-enabled PUSH {r4,lr}, a PC-relative literal load into r4,
then a dependent MOV. Baseline passes at latencies 0/3/7; V14 fails 0x63 at
all three. Replacing PUSH with a plain stack adjustment passes both at 0/3.
An original-firmware routine harness `firmware.S` also fails V14 and passes
baseline at 0/3/7, but its first failure is the earlier R4 literal, not the
firmware boot's later R1 literal. Relation to the long-run abort is plausible
but not proven. Tests use `build/sim/obj-{ngage,ldm-identity-v14}`.
Investigate why the candidate acknowledges the first literal before the
correct load reaches its dependent MOV; use a small signal trace.

## 2026-10-28 V14 TLB lookup identity

V13's first 2 MiB mismatch was traced to block 16576, input 0x10c000.
At the first bad ADD, the cache fetched PA 0x0000c020 instead of 0x0010c020.
The TLB tag excludes the indexed bits; the registered translation was allowed
to match the current request while its RAM output still belonged to a prior
index. See `build/sim/runs/cache-divergence-2m/simulator.log`.

Experimental `scratch/ldm-identity-v14-zap/` pipelines the TLB lookup address
alongside the RAM and requires it to match the request before accepting the
translation. It passes 70 directed tests and the previously failing 2 MiB MD5
workload at cycle 59,883,380. Results and hashes are in
`scratch/cache-md5-length-sweep/results-v14-2m.json`. The 4 MiB checksum also passed at cycle 116,785,468; see
`scratch/cache-md5-length-sweep/results-v14-4m.json`. A full provisional firmware run completed at the 1 billion-cycle timeout.
The last bus activity was at cycle 724,132,872; the final retirement tail
repeated the data-abort vector 0x10 and handler address 0x503280e4, suggesting
it was trapped rather than progressing. The first abort cause is unconfirmed;
54 fetch bus faults were reported. Outputs are in
`build/sim/runs/boot-cache-identity-v14/`. The screen capture
`build/sim/screens/boot-cache-identity-v14/screen.png` is an assumed white
clear, not the logo. The 1 MiB log cap omitted about 7.97 GB of messages.
The targeted replay completed at cycle 724,314,325 with data abort at
PC 0x503a2760. The preceding literal load at 0x503218e4 requests VA
0x50321938; both original and derived firmware contain 0x50346070 there,
and the bus previously fetched that value from PA 0x00321938. Yet the later
function receives R1=0xffff0031 and dereferences it, causing an L1 lookup
of zero at 0x0a077ffc. This is distinct from the earlier 0x503313c8 abort;
the cause of the wrong R1 (including cache data/tag and register timing) is
not yet proven. Bounded evidence in `build/sim/runs/boot-cache-abort-probe/`;
source/provenance `scratch/abort-probe/run.py`. Three noisy informational
TLB messages were suppressed only in the debug RTL, with fatal assertions kept.
Next build a short literal-load/cache conflict reproducer and compare the
load's actual data and completion timing against baseline. V14 has not been promoted or verified with an
authentic full firmware run, resets/interrupts under
all transitions, or FPGA synthesis. Keep runs compact and cap simulator logs.

## Cleanup and resume notes

2026-10-28 cleanup removed obsolete compressed simulation traces/logs and
synthetic test snapshots at the user's request, in addition to verified duplicate
build copies and regenerable compiler caches. Historical raw traces listed in
older sections may no longer exist; their result summaries and experiment source
are retained, so rerun a test when its old trace is needed. The manifest of
removed traces is `build/sim/cleanup-trashed-old-traces.json`.

The current `md5-window-*` and `md5-blockstate-*` traces, screenshots,
`build/sim/checkpoints/ngage-before-cbus27.*` and its baseline bus trace remain
available. Simulator executables and build sources are retained. Removed compiler
caches regenerate during a build. Cleanup manifests and the cache regeneration
proof remain under `build/sim/cleanup-*`.

## Current saved checkpoint: digest first wrong operation

No simulation is active. The first divergent MD5 block is index 15812, input
address 0x100100. The bounded baseline and V7 traces are complete in
`build/sim/runs/md5-window-{ngage,identity-v7}/`; source and binary hashes are
in `scratch/md5-block-trace/window-results.json`. At baseline cycle 15,237,251
and V7 cycle 28,287,493, instruction 0x3eb0 (`ADD r6,r4,r5`) first yields
0x59824165 versus 0x4f1fa934. The preceding instructions include loads from
VA 0x00100120 and 0x0000475c. Their retirement display can show stale values
for asynchronous cache loads, so determine the actual final operands and
physical translations before attributing the fault. The previous block's
incoming state matches exactly. See [ldm-replay-investigation.md](ldm-replay-investigation.md).
No production RTL was changed.

## Historical first-divergent-block trace

The digest block-state comparison found the first state difference after block
index 15812, beginning at ROM offset 0x100100. The first 15,812 completed
blocks agree with baseline. A detailed bounded trace of that block is running
in session 78324; outputs go to `build/sim/runs/md5-window-{ngage,identity-v7}/`.
The short alternating-section test `scratch/cache-alternating-sections/test.S`
passes both V7/V8 and baseline at 0/3; alternating section loads alone do not
reproduce the bug. The length-boundary tests passed through 0xf7040 bytes;
the 0xf8000-byte case stopped on an unmapped read after mismatched sequential
translations, so the exact first bad length remains unproven. See
[ldm-replay-investigation.md](ldm-replay-investigation.md).

## Latest targeted digest result

The digest-length sweep completed: V7 passes 64, 128, 256 and 512 KiB but
fails 1 MiB (completion 0x31); seven-patch baseline passes 1 MiB and V8 fails
it. The failing input crosses a 1 MiB translation-section boundary. A small
cached-versus-uncached byte test across that boundary passes baseline, V7 and
V8 at 0/3, so crossing alone is not sufficient to reproduce the failure. A
512 KiB test at the firmware virtual ROM address also passes V7. No simulation
is active. Details and next steps: [ldm-replay-investigation.md](ldm-replay-investigation.md).

## Latest long cache-enabled firmware result

The V7 run from reset with a 1,000,000,000-cycle limit completed at cycle
666,454,237 in firmware digest failure loop `0x50003290`. Its calculated digest
was `2d41ef51bb1576cdb457d0212f8330dd`, not the expected
`1784c17a6fd17b0841226546434db048`. The candidate passes short firmware MD5
and cold-LDM tests but is not correct for the complete workload. No simulator
is active. Output/provenance: `build/sim/runs/boot-cache-identity-v7-long/`;
`build/sim/screens/boot-cache-identity-v7-long/screen.png` is the interpreted
white clear, not the Nokia logo. Do not promote the cache prototype. Next
isolate the first digest divergence with progressively larger short inputs and
an independent reference. See [ldm-replay-investigation.md](ldm-replay-investigation.md).

## Cache strategy decision

Sol reviewed the ARM920T/ARM9TDMI manuals, ZAP and prior tests. Repair the
request/completion protocol first; retain inferred RAM until actual Cyclone V
synthesis can measure mapping; defer a 64-way rewrite. The ordered implementation
and validation plan is in [cache-implementation-decision.md](cache-implementation-decision.md).
Nokia cache geometry and the current M10K/MLAB mapping remain unverified.

## Latest lookup resynchronization experiment

V4 also fails the short firmware MD5 and following-load reproducers at both
latencies. A separate scratch v5 resynchronizes the next lookup after a pending
request: 60 directed cases pass, including the following-load reproducer at
latencies 0/3/7/15/31, but the 64- and 1024-byte firmware MD5 tests still fail
at all five timings (10 failures). V5 is not a fix. A focused trace is saved in
`build/sim/runs/ldm-md5-v5-trace-latency0/`. No simulator is running; production
RTL remains unchanged. See [ldm-replay-investigation.md](ldm-replay-investigation.md).

## Earlier isolated digest regression result

The v3 bad digest exactly matches independent MD5 with A/B/C/D initialized to
zero. A 64/1024-byte unchanged firmware MD5 harness fails v3 and passes the
seven-patch CPU at latency 0/3. A firmware-independent following-literal-load
case also fails v3, while eight NOPs or an immediate comparison makes it pass.
The next focus is cache/TLB lookup alignment when pending request ACK restores
lookahead. See [ldm-replay-investigation.md](ldm-replay-investigation.md), latest
section, and `scratch/md5-short-probe/`. No production change or long boot rerun.

## Latest focused LDM investigation

A new isolated wait/forward probe passes cold-cache LDM and load widths at both
latencies, with 18 focused passes overall, but **fails a cache-line-crossing
LDM control at both latencies** (wrong LR, completion 0x22). It remains rejected;
production CPU and vendor sources are unchanged. Later review corrected the earlier stall hypothesis: data-cache `i_stall`
is tied to zero in this project. Blocking changes must still coordinate
cache/TLB pipeline advancement. Exact results, retained candidate and next seam:
[ldm-replay-investigation.md](ldm-replay-investigation.md). No simulation running.

## Latest cache-enabled firmware result

The full v3 experimental cache-enabled firmware run completed at cycle
398,990,758 in the digest-check failure loop `0x50003290`. It reached the LCD
clear; `build/sim/screens/boot-cache-candidate-v3/screen.png` is the assumed
white clear, not a logo. Firmware computed digest
`f92e2e386422faea eedde006063cd464` (remove the space), while the deliberately
modified expected digest is `1784c17a6fd17b0841226546434db048`. Earlier
cache-disabled FPGA and Python both computed the latter. This shows a
firmware-level discrepancy; do not infer its exact source or promote v3/v4.
Traces, input hashes and screenshot metadata are under
`build/sim/runs/boot-cache-candidate-v3/` and
`build/sim/screens/boot-cache-candidate-v3/`. No simulation is running.

V3 passed 55 small directed checks, upstream benches and lint; V4 adds request
stability assertions and enabled-cycle counting, with directed, fault and
synthetic IRQ/FIQ tests. Neither has a proven TLB validity handshake. Investigate
the firmware digest discrepancy before any CPU patch. See
[ldm-replay-investigation.md](ldm-replay-investigation.md) and [TODO.md](TODO.md).

## Historical TLB handshake experiment

The isolated `scratch/ldm-tlb-handshake-v2-zap/` candidate passes original
cold LDM, cache-line crossing, cold and warm noncontiguous page crossing,
cross-page data-abort FAR, cross-page STM, dirty eviction and load-width
checks at latencies 0/3; selected cases also pass 7/15/31. Nineteen additional
existing diagnostics pass at 0/3. Original ZAP ARM/Thumb regressions were
started separately; verify their results before claiming they pass. It retains
a provisional four-cycle timing assumption and has not been promoted. Review
remaining gaps in [ldm-replay-investigation.md](ldm-replay-investigation.md)
and [TODO.md](TODO.md).

## Previous cache investigation

The isolated lookup-alignment prototype passes cold LDM, cache-line crossing,
dirty victim writeback, load widths, and existing MMU/alignment/fault tests at
latency 0/3. A new noncontiguous cold-page crossing fails at both: it treats an
untranslated virtual address as physical. A warm-page control passes. This is
not a production fix. [ldm-replay-investigation.md](ldm-replay-investigation.md)
records the trace, corrects the previous cache-stall hypothesis, and lists the
remaining TLB handshake work. No simulation is running.

## Previous GPIO and cache checkpoint

The experimental exact write sink for GPIO upper halfword `0x0c150206=0x0180`
passes boundary tests and advances the saved firmware continuation to an unknown
low-halfword GPIO read at `0x0c150214`, cycle 452,340,421. The captured image
`build/sim/screens/boot-checkpoint-gpio206/screen.png` remains the assumed white
clear. The GPIO semantics are still unknown. See [display-bringup.md](display-bringup.md).

A third isolated blocking-cache experiment, `scratch/blocking-cache-probe-v3/`,
held the cache RAM/TLB pipeline during refill and unlock. Smoke and small-page LDM
pass at latencies 0 and 3; cold-cache LDM passes at 0 but times out at 3, and
load-width diagnostics fail at both. It is rejected; no production CPU source or
patch changed. A careful CPU pipeline/replay design review (a good candidate for
the previously discussed Sol debugging session) remains necessary. See
[TODO.md](TODO.md). No simulation is running.

## Previous checkpoint frontier

The continuation in `build/sim/runs/boot-checkpoint-pupf000/` stops at cycle
452,340,325 on upper-halfword GPIO write `0x0c150206 = 0x0180` (bus address
`0x0c150204`, select `0xc`), currently rejected by the existing low-halfword
latch. It matched the previous trace prefix. No run is active. The latest
screen is `build/sim/screens/boot-checkpoint-pupf000/screen.png`: an assumed
white clear, not a logo. Continue from the original pre-CBUS checkpoint using
`scratch/checkpoint-register-probe/resume-pupf000.py`; its hypotheses and
remaining CPU/peripheral defects are in the topic docs. Do not infer actual
GPIO semantics from the observed write.

## Earlier system-control frontier

Checkpoint continuation reaches unknown word `0x0c120c10` at cycle 452,338,892
under explicit CBUS/GPIO/system-control assumptions; trace prefix matched and
board tests passed. Latest assumed screen remains white. See
[display-bringup.md](display-bringup.md) and [TODO.md](TODO.md). No normal-cache
CPU fix or authentic boot is claimed.

## Latest power-unit/timer frontier

Latest checkpoint continuation reached unknown word read `0x0c120c14` at cycle
452,338,785. Earlier CBUS zero hypothesis triggered a `CBus` fault; value 0x0400
satisfies the firmware's observed status check but is unverified. Additional
explicit CBUS8d reset/readback, IRQ46 write-sink and PUP 0x0c14f00a zero
hypotheses are tested and recorded in [display-bringup.md](display-bringup.md).
Latest image remains the assumed white clear; no logo or full boot. No long
simulation is active. Continue from the saved pre-CBUS checkpoint, not reset.

## Latest checkpoint continuation

The latest test reached CBUS read command `0x182` at cycle 452,261,280, after
writing `0xffff` through command `0x82`. No new image beyond the white clear.
Checkpoint continuations are fast and each validates its previous trace prefix.
The write was explicitly allowed; read behavior is unknown and must be a separate
hypothesis. See [display-bringup.md](display-bringup.md) and [TODO.md](TODO.md).

## Latest resumed result

The firmware checkpoint succeeded and its continuation matched the baseline.
Four small, separately tested and explicitly assumed UEM/IRQ/GPIO behaviors
advanced boot to a read of physical `0x0c150216` at cycle 452,256,719. No run
is active at this checkpoint; the image remains the assumed white LCD clear.
See [display-bringup.md](display-bringup.md) for every assumption, output and
reproducer. The CPU replay bug and all nonphysical shortcuts remain in
[TODO.md](TODO.md); no authentic full boot or logo has been demonstrated.

## Historical checkpoint at 3% allowance

The resumable firmware experiment is still running in session 56299. At this
checkpoint `build/sim/runs/boot-checkpoint-initial/result.json` was empty and
`build/sim/checkpoints/ngage-before-cbus27.{cpu,host}` did not yet exist; the
run must reach cycle 451,430,000 before saving them. The last buffered simulator
log timestamp was 382,882,225 (roughly half as many simulated CPU cycles; logs
can remain buffered), so do not interpret an unchanged log as completion. Leave
the process running; inspect Docker, the result and wrapper output before any
restart. `scratch/checkpoint-probe/run_firmware.py` automatically verifies the
baseline, resumes the saved snapshot with explicit CBUS 0x27 write, compares
its trace prefix, and attempts screen capture. Check `boot-checkpoint-cbus27`
result and screens after completion. **Do not modify the wrapper, CPU/board
source, simulator binary, ROMs, extension or capture tools while it runs:**
its manifest checks source/input hashes before continuation. If it fails, save
the error and see [display-bringup.md](display-bringup.md) before rerunning.

Checkpoint tests passed at 18 boundaries across both memory latencies; the
CBUS probe rejects unrelated writes/reads; modified firmware is rejected; a
controlled alternate board binary restored an older synthetic checkpoint with
identical traces. Firmware checkpoint is not yet validated. Full task scope and
unverified shortcuts remain in [TODO.md](TODO.md). White-clear image exists at
`build/sim/screens/boot-display-no-data-cache-timer-readback/screen.png`; this
is an interpretation of firmware writes, not a logo or live framebuffer.

## Historical resumable boot experiment

The prior timer-reload run reached new UEM command `0x27` at cycle 452,153,686
and stopped. A checkpoint-capable no-D-cache simulation is now active (session
56299), saving at cycle 451,430,000 and then automatically resuming with the
single observed UEM write allowed. It compares the post-checkpoint prefix with
the unmodified run and attempts a conservative screen capture. Outputs:
`build/sim/runs/boot-checkpoint-{initial,cbus27}/`, snapshots under
`build/sim/checkpoints/`, screen under `build/sim/screens/boot-checkpoint-cbus27/`.
CPU/board checkpoint tests and explicit UEM resume passed at both memory
latencies. Full scenario details and caveats are in
[display-bringup.md](display-bringup.md); incomplete work is in [TODO.md](TODO.md).
Check the running process and result before rerunning.

## Latest checkpoint: screen capture and timer reload

A trace-derived 176×208 white-clear PNG is available at
`build/sim/screens/boot-display-no-data-cache-timer-readback/screen.png`, with
its evidence and unverified color interpretation in `screen.json`. It is not
live video or a logo; capture currently refuses unknown drawing. See
[display-bringup.md](display-bringup.md) for the capture command and tests.
The prior no-cache boot stopped at cycle 451,437,796 on timer reload 0x632ea.
A new bounded reload experiment is running in
`build/sim/runs/boot-display-no-data-cache-timer-reload/` (session 30552 at
launch); its wrapper captures a screen automatically after completion if the
trace remains within the understood clear-only subset. Check process/result
before restarting. All skipped components and required fixes are recorded in
[TODO.md](TODO.md).

## Open assumptions and required fixes

See [TODO.md](TODO.md) for a prioritized account of boot probes, forced-off
cache, digest changes, UEM, timers, flash, clocks, LCD and verification.

## Latest cache-disabled boot

With data cache forced off, firmware passed the earlier kernel fault and stopped
at cycle 451,437,317 reading timer control `0x0c120a04`, after writing 2. It has
not drawn a logo. A new bounded timer-readback experiment is active at
`build/sim/runs/boot-display-no-data-cache-timer-readback/` (session 41019).
See [display-bringup.md](display-bringup.md); all inputs are explicit hypotheses.

## Latest normal-cache comparison

The seven-patch firmware comparison completed at exactly the same kernel fault
as before (cycle 423,877,595). Patch 0007 corrects fault-register preservation,
not the independent cold-cache LDM restart defect. The cache-disabled diagnostic
run remains active; see [display-bringup.md](display-bringup.md).

## Active exploratory boot bypass

A simulation-only forced-off data-cache run is active in
`build/sim/runs/boot-display-no-data-cache/` (session 79542 at launch), after the normal-cache seven-patch comparison
`build/sim/runs/boot-display-kernel-fault-fix/` completed at the same fault. The no-cache
mode passes focused replay, load-width and MMU tests at both memory latencies;
it is an explicit nonphysical diagnostic, not a fix. See
[display-bringup.md](display-bringup.md), and check each result/process before
restarting. Preserve original firmware and both runs' provenance.

## Current blocker: reproducible CPU replay failure

A cold-cache `ldm r5,{r5,lr}` with base in the register list fails at both
memory latencies, matching the kernel's superpage/vector access sequence. The
cache fill is correct; the LDM restarts after r5 changed to the loaded value 4,
so subsequent accesses use low addresses. Warm-cache variants pass. See
[display-bringup.md](display-bringup.md) and
`sim/programs/ldm_base_coldcache.S`. Investigate replay and exception semantics;
Sol reviewed this and a focused cycle trace confirmed second-load err2,
pipeline clear, and subsequent asynchronous base-register write. A scratch
blocking-cache prototype passes
at latency 0 but repeatedly refills and times out at latency 3; it is not a fix.
The separate seven-patch firmware run
remains active; patch 0007 fixes fault-register clobber, not this replay bug.

## Latest firmware trace

The v4 trace completed and confirms the live `0x400000c4` mapping and words
4, 5, `0x05040001`; it then accessed low vector data and attempted
`0xe59ff028`. Cause remains unproven; detailed evidence in
[display-bringup.md](display-bringup.md). A seven-patch v5 comparison is now
running under `build/sim/runs/boot-display-kernel-fault-fix/` (session 66654).
Check its result and container before repeating. The full compatibility suite,
upstream ARM/Thumb tests and synthesis-path lint pass with patch 0007.

## CPU fault-register correction

Patch 0007 fixes successful uncached reads/writes incorrectly replacing CP15
fault status/address. A six-patch control fails and seven-patch tests pass at
both latencies; full compatibility suite passes. See
[display-bringup.md](display-bringup.md). The active v4 firmware trace still
uses six patches and is a before-fix run; the original kernel abort remains
unexplained and must be retested under patch 0007.

## Active kernel fault trace

A focused v4 firmware reproduction is running in
`build/sim/runs/boot-display-kernel-abort-trace/` with enlarged memory and
instruction histories; see [display-bringup.md](display-bringup.md) before
rerunning. Basic, translated and cacheable-small-page LDM diagnostics all pass
at latencies 0 and 3. The actual firmware abort and fault address remain
unexplained; an independent synthetic unmapped-load probe reports expected FAR
and initially expected FSR 0x5; a later read returns 0x2 for both LDR and LDM. See the topic doc; its original
inputs and stage-v3 evidence are unchanged.

## Latest result: kernel entry

The v3 boot-display run completed: firmware entered Symbian kernel code and
took a data abort at `0x503313c8`, entered a `KERN-EXEC` fault path, and
stopped at cycle 423,877,595 on diagnostic write `0x0c0047f0=0x4e52454b`.
The fault address reported is `0xe59ff028` (translation fault); its source
is unresolved. Focused LDM tests pass with and without MMU at both latencies.
LCD trace still contains only the white clear. See [display-bringup.md](display-bringup.md)
for evidence, assumptions and next work. The earlier checkpoint below describes
what was active before this result; do not restart that run.

## Checkpoint at user request

Resume the firmware-driven boot and display work, not a pre-rendered splash.
At checkpoint the background simulator session `28777` was running the v3
experiment; its output directory is
`build/sim/runs/boot-display-power0-status36-0-status35-10/`. `result.json` was
empty at checkpoint (written at process end); `provenance.json` records all
source, binary, input and image hashes. Check the container/process and result
before repeating the run. It may finish while this chat is idle. The run has a
550,000,000-cycle cap, memory latency 0, and uses `jotego/simulator:arm64`.
When finished, inspect `result.json`, the tail of `instructions.tsv` and
`bus.tsv`, then run `python3 sim/analyze_lcd_trace.py <bus.tsv> --output
<output.json>` to see if firmware writes nonuniform LCD data. The v3 scenario
assumes UEM 0x3f=0, 0x36=0, 0x35=0x10, ADC 6=512 and a timer delay of
18,200,000 cycles, and uses a derived digest-probe image and synthetic tail.
These are experimental hypotheses, not authentic phone behavior. The underlying
firmware inputs are untouched. Further UEM, timer and LCD semantics, MiSTer
integration, and the real firmware integrity discrepancy remain unresolved.

Timer IRQ was integrated into `sim/`, with `make sim-compat` passing, including
IRQ entry/ack/return and masked IRQ cases at both latencies. Twenty-one native
oracle tests passed. The maintained runner now records a build manifest and a
short timeout run verified its metadata; no full firmware run has used the new
maintained timer model yet. The separate v3 board tests passed. See
[display-bringup.md](display-bringup.md) for all frontiers, assumptions,
previous results and display-packing evidence. Treat scratch as persistent
local work and build as generated evidence. Do not download Quartus.

## Current display objective

Firmware-driven Nokia startup display is the current goal; see
[display-bringup.md](display-bringup.md). The maintained timer IRQ experiment
passes compatibility checks. A separate assumed UEM status run is active under
`build/sim/runs/boot-display-power0-status36-0-status35-10/`; the previous run
reached an unknown IRQ halfword write after UEM reads. The firmware has so far
sent a white screen clear, not a Nokia logo. No MiSTer video output exists yet.

## Resumed development, 2026-10-27

Actual project: `/Users/andreabogazzi/develop/NGage_MiSTer`.
This section supersedes the historical five-patch checkpoint below.

**Current finding:** the supplied NEM-4 core rejects its own embedded MD5.
The FPGA-computed full digest matches Python hashlib over the original file,
and the independent native CPU reaches the same rejection loop. The checked
range precedes the reconstructed extension, so changing that extension cannot
resolve this failure. Read [firmware-integrity.md](firmware-integrity.md) first.

Completed since resuming:

- Explicit `--uem-adc CHANNEL=VALUE` with no default sample. Scenario `6=512`
  passes the battery-identification branch. Unknown channels and directional
  ADC/watchdog behavior stay bounded; scenarios are recorded and compared.
- `--mmu-reference` runs native Unicorn translation, with physical data hooks
  and checked virtual code addresses. The separate `--fast-rom-reference` mode
  executes the original ROM hash with immutable-block/read fast paths and full
  MMIO/write/hole checks; see [mmu-reference.md](mmu-reference.md).
- Five exact timer/ICU setup writes are captured without invented readback,
  counting or IRQs. The prior spurious read at `0x0c120100` was isolated to a
  CPU BTB collision and fixed by patch 0006, not acknowledged as a peripheral.
- All acceptance/board checks, original ARM32/Thumb seed-1 tests and synthesis-
  path lint pass with **six patches**. Nineteen oracle checks pass. The pinned
  83 upstream files and the verified 1,524-file extension are intact.
- The self-contained `btb_return` fails before the fix with both timings, then
  reaches its intended terminal write after it. Cold controls and before-fix
  traces are retained; see [branch-prediction.md](branch-prediction.md).

**New resumed results:** the delayed-memory original-input run also reaches the
same rejection loop; both FPGA traces match the native reference across all
36,982 device accesses. All three distinct supplied core images have a similar
embedded range/digest mismatch. NEM-4 also has a second descriptor for the
reconstructed extension, whose synthesized bytes do not match its stored digest.
`make inspect-digest-variants` and `build/firmware/digest-variants.json` preserve
the per-image evidence. QD static references are not a QD boot result.

An opt-in derived-image experiment is now available through `--digest-probe
core` or `--digest-probe both`; only 16 / 31 metadata bytes change, with a manifest
and pinned original/derived hashes. No original input is modified and authenticity
is explicitly false. Native `core` reaches the second digest rejection; native
`both` passes both and stops on timer-status read `0x0c120a08`. FPGA verification
of `both` completed with immediate and delayed memory. Both reach the same
timer frontier and pass the cache-aware comparison described below.

**Timer IRQ stage:** a separate scratch-only one-shot timer experiment now
passes its model checks and an independent ARM IRQ entry/acknowledge/return
diagnostic, with both memory timings. The no-event control stops as quiescent;
a pending scheduled event prevents premature quiescence. Its configurable
cycle delay and acknowledgement are unverified assumptions. A real-firmware
stage run with delay 18,200,000 cycles completed at
`build/sim/runs/timer-irq-stage-firmware-delay18200000-latency0/`. The previously
started non-IRQ `digest-both` immediate/delayed runs have also completed.
Preserve the old runs and their recorded provenance when updating board sources.
The stage source and test are in `scratch/timer-irq-stage/`; details are in
[uem-control-bus.md](uem-control-bus.md). Native software does not inject IRQ.

The IRQ vector and early handler now identify the likely next hardware work:
IRQ handler `0x3090` reads UEM `0x3f` and writes timer flag `0x58120a08 = 1`.
The current timer has no events and IRQ remains tied low. An explicit timer/IRQ
experiment and independent exception test are needed; do not merely return ready.
See [uem-control-bus.md](uem-control-bus.md). This is a suitable independent Sol
review target, as requested by the user, while development continues locally.

Simulator quiescence handling now stops a repeated unmasked self-branch after 32
retirements only because no asynchronous IRQ/FIQ source is wired. It labels the
result `quiescent_loop`, not success or masked failure. When adding scheduled
interrupts, prevent this shortcut from stopping a loop that an event can wake.
Focused IRQ-enabled and masked-loop diagnostics and the full compatibility suite
pass. There are now 20 oracle checks and 3 digest-probe safety checks.

The immediate HDL run reached a stable unmasked self-branch at `0x50003290`
within its 1,000,000,000-cycle limit. Native software independently stops at the
same PC, LR=`0x500032ec`; all **36,982 device events match**. The comparator
labels this **through quiescent self-branch at HDL cycle limit**, not boot or a
first-unknown-register frontier. The hash output was written near cycle
403,058,539 and is preserved in the final memory tail.

The native fast-path instruction count is an upper bound, 206,962,190, not an
exact retirement/timing metric. Its digest comparison is `0x17` versus expected
`0x2c` at the first byte. Descriptor `0x8f18` checks virtual
`0x50009000..0x511b4fff` inclusive. Supplied/FPGA MD5 is
`1784c17a6fd17b0841226546434db048`; embedded expected is
`2c09c86ff047484fdcc0e226f49c44a9`.

The original-input latency3 run completed at its cycle limit; both saved traces
match the independent reference and both MD5 outputs match Python hashlib. Both
`*-digest-both` FPGA timings and the two native probe results are complete:

- `build/oracle/amd16-ideal-clocks-lcd-probe-extension-boot-io-adc6-200-digest-core-mmu-fast/result.json`
- `build/oracle/amd16-ideal-clocks-lcd-probe-extension-boot-io-adc6-200-digest-both-mmu-fast/result.json`
- `build/sim/runs/firmware-amd16-latency{0,3}-ideal-clocks-lcd-probe-extension-boot-io-adc6-200-digest-both/`
- `build/sim/firmware-digest-analysis.json` includes both original FPGA traces.

The strict saved comparison for latency 0 reports a mismatch beginning at event
36,998 in extension reads, although the final unknown timer frontier matches.
Investigation found software logs 1,306,638 extension reads, whereas FPGA logs
350,350; both contain the same **326,670 distinct (address, byte-enable) pairs**
with identical values and no conflicting repeated values. FPGA trace shows
sequential eight-word cache fills; software logs architectural reads, including
repeats. This explains why strict bus-event equality is inappropriate for this
range, but does not prove equal CPU execution. The 36,968 non-extension
device events match in order; the FPGA trace additionally records the final
unmodeled timer read, which the software trace omits. The reproducible cache-aware diagnostic is `scratch/timer-irq-stage/compare_extension.py`
(software bus path followed by FPGA bus path). The 16 bytes written by FPGA
firmware for the extension digest are
`30f998ac14c9a77fad5eb0c74a4cccbd`, matching hashlib for the synthetic tail.
Do not weaken the existing strict comparison or claim full trace agreement.

The strict saved comparator detects the expected cache-traffic mismatch; the
separate cache-aware diagnostic checks the coverage and non-extension event
order for both timings. The stop is an unknown timer read, not a Symbian boot.

The saved-trace comparator rejects mismatched timer IRQ assumptions; its 21
software-reference tests pass. The native reference does not inject IRQs.

Independent Sol review identified an IRQ-masked/FIQ-unmasked idle-loop guard
bug and missing diagnostic/provenance assertions. The guard is fixed and tested
in the separate v2 stage, with isolated build provenance saved. See
[uem-control-bus.md](uem-control-bus.md); integrate the checks and provenance
in the maintained harness now that the older run has finished.

**Next work:** validate both derived-image FPGA runs and integrate the staged,
explicitly assumed timer/IRQ experiment after the older runs finish. Preserve
unknown UEM status, and do not let the quiescence shortcut preempt scheduled
interrupts. Continue researching why the three original logical dumps disagree
with their stored core digests; the probe does not explain or authenticate them.

Symbian boot, actual MiSTer memory/video integration and 104 MHz timing remain
unimplemented. Keep using `jotego/simulator:arm64`; no Quartus download.

---

# Previous saved checkpoint (historical five-patch measurements)

Last verified: 2026-10-27. **Start here when resuming.**
Saved at the user's request when credits ran out. No further development should
be inferred from older pending notes: both final firmware runs and saved-prefix
comparisons completed. Resume with the UEM ADC input slice below.
Actual project: `/Users/andreabogazzi/develop/NGage_MiSTer`.
The chat may still start in `Template_MiSTer`; develop in this project instead.

The reconstructed extension gets past the missing-flash boundary, and firmware
now enables the MMU and caches and executes virtual startup code. A real CPU
cache-miss completion bug was isolated and fixed by patch 0005. Both HDL memory
timings get past the former lookup loop and reach a **UEM ADC channel-6/BSI read**
whose analog input is not yet supplied. This is simulation progress, not a boot
of Symbian or a working MiSTer core.

Start with [extension-reconstruction.md](extension-reconstruction.md) and
[uem-control-bus.md](uem-control-bus.md) for this milestone and the next slice.

## Goal and retained decisions

Build a stock MiSTer-style N-Gage core using hardware ARM RTL and the Nokia
firmware, eventually running J2ME games. The chosen route is ZAP plus firmware;
there is no game/JAR loader yet. GBA_MiSTer is a possible loader/SDRAM reference,
not a CPU-architecture source. Do not restart CPU/JVM selection on resume.

- Keep experiments/references/staging in project `scratch/`, generated output in
  `build/`. Both are ignored; neither is a remote backup.
- Use the existing `jotego/simulator:arm64` image, explicitly Linux ARM64.
  Do not download Quartus. No Quartus build has been performed.
- GitHub work uses `gh` CLI. Preserve user firmware/manuals and upstream hashes.
- Work is local and uncommitted; many implementation files remain untracked.

## Implemented and checked

| Area | Current state |
| --- | --- |
| CPU | Pinned, unchanged ZAP in `third_party/zap/`; five patches applied only to generated build copies. Shared wrapper `rtl/ngage_cpu.sv`. |
| Configuration | ARMv4T Thumb behavior, MMU, 16 KiB I/D caches and 32-byte lines. Full ARM920T equivalence and original timing are unproven. |
| CPU fixes | Cache-disabled physical translation, ARM920T alignment aborts, uncached flash-return ordering, optional quiet logging, correct byte/halfword/rotated background load completion. |
| Board experiment | Bounded ROM/RAM, independent flash command state, narrow initialized scratch/shadow storage, exact observed register latches. Unknown data operations stop before ACK. |
| Optional assumptions | Ideal clocks, selected LCD reset/status/transport behavior, separately reconstructed extension, and narrow boot-I/O/CBUS hypotheses. |
| Firmware inventory | Three distinct ROMs; all 3,241 core files checked. NEM-4's 507 extra files are intact in ROOT. QD developer tree and 18 IDA databases retained separately. |
| Extension | Separate validated tail preserves ROOT, reconstructs missing metadata, and verifies all 1,524 merged files. Input images remain unchanged. |
| Software reference | Unicorn 2.1.4 TI925T ARMv4T executes physical startup against the shared C++ board. It intentionally stops immediately after MMU enable. |
| Tests | CPU acceptance/board boundaries pass; cache diagnostic passes both timings; original ARM32 and Thumb regressions pass with all five patches, seed 1; synthesis-path Verilator lint passes. Six extension and twelve oracle checks pass. |

The CPU exposed the cache bug at virtual `0x500034f0`: a miss supplied full word
`0x0026003b` instead of byte `0x3b`, causing the permanent loop at `0x50003524`.
`cache_load_widths` reproduces this without Nokia firmware and verifies the fix
with immediate/delayed memory, including the adjacent-load dependency pattern.
See [cpu-patches.md](cpu-patches.md). Vendor sources remain unchanged.

## Exact measured boundaries

Input: NEM-4 4.03 `firmware/SYM.ROM`, 18,612,224 bytes.
SHA-256: `afc1cc8b693f2b68d23ca203aa4d4eb4266baad4ab718f013a33b915d39574ef`.
The executable profile rejects other ROMs because its table offsets are fixed.

| Experiment | Software instructions | Compared I/O | HDL cycles, immediate / delayed | Boundary |
| --- | ---: | ---: | --- | --- |
| amd16 | 5,506 | 59 | 32,068 / 41,858 | Unknown clock status `0x0c120020` |
| + ideal clocks | 6,320 | 123 | 37,492 / 48,923 | Unknown halfword `0x0c14f008` |
| + LCD | 22,458,929 | 36,905 | 111,002,311 / 154,357,177 | Missing flash `0x046c001c` |
| + extension + boot I/O | 23,103,894 | 36,944 pre-MMU | MMU event 115,508,331 / 160,257,860 | Software scope limit at PC `0x2e6c`, c1=`0x127f` |
| Same, HDL continues | Outside software scope | No post-MMU reference claim | 115,513,670 / 160,264,088 | ADC read, aligned physical `0x0c150424`, upper halfword |

Delayed means deterministic 0–3-cycle response delays. Cycle counts are simulator
measurements, not Nokia timing. Retirements can represent micro-operations.
TTBR is `0x0a074000`, DACR `0x55555557` at MMU enable. The comparator explicitly
labels the matched segment **pre-MMU prefix** and rejects changed model/input
hashes. Software/HDL share peripheral code, so agreement is not independent
verification of the Nokia hardware model.

Latest outputs:

- `build/oracle/amd16-ideal-clocks-lcd-probe-extension-boot-io/result.json`
- `build/sim/firmware-amd16-latency{0,3}-ideal-clocks-lcd-probe-extension-boot-io-results.json`
- Per-case bus/CP15/instruction logs and bounded post-MMU `memory-tail.tsv` under
  the corresponding `build/sim/runs/` folders.
- `build/sim/results.json`, `upstream-ngage-results.json`, `rtl-lint-results.json`.
- `build/firmware/inventory.json`, `build/firmware/nem4-extension/extension.json`.
- `build/sim/boot-analysis.json` includes the current ADC/CBUS routines.

The optional LCD stage emits 75 headers, 18,353 data writes and 18,334 status
reads, including the full 176 x 208 clear and display-on command. This is a
captured transfer, not a verified rendered image.

## Assumptions and absent implementation

The three 64-Mbit flash chips give 24 MiB physical capacity. The supplied core
is 17.75 MiB; selected type-1 banks total 19.9375 MiB. Their consecutive logical
mapping, reset alias and chip identities remain provisional. The recovered ROOT
is genuine supplied content; the extension header/directories are synthetic,
with uncovered selected-ROM tail bytes explicitly assumed erased. User/type-3
windows do not acquire backing. See [flash-layout.md](flash-layout.md).

Ideal RAM reset, selected GPIO/cold-start reset values, immediate clock/LCD/CBUS
status and hypothetical register latches are separate recorded assumptions.
UEM ADC read semantics differ from watchdog writes at the same register number;
the model does not echo those writes as an analog reading. No ADC sample has
been selected. TLB warnings about ignored section bits 4 and 15:12 still need an
ARM920T-specific audit; do not silence or change them from warning text alone.

Not implemented: full UPP_WD2 peripherals, interrupt/timer behavior, Symbian
kernel/OS boot, MiSTer loader/SDRAM/video integration, keypad/audio/storage,
game/JAR selection, synthesis/resource fit/104 MHz timing, or hardware testing.
The C++ board model is not synthesized RTL.

## Next work in order

1. Follow [uem-control-bus.md](uem-control-bus.md). Inspect the BSI caller's
   sample-range branches, then add explicit simulated analog inputs as a named
   assumption while retaining the default unknown-input stop. Do not guess a
   universal UEM reset value or copy TriX's other-phone defaults as measurements.
2. Follow the next actual HDL request after that experiment. Keep new peripheral
   behavior bounded and shared, test unknown/directional cases, and record the
   exact scenario/input in reports. Post-MMU execution needs an MMU-aware
   independent reference or focused CPU checks; the current Unicorn prefix
   cannot validate it.
3. Continue the ARM920T CP15/TLB audit and physical-bank/layout verification when
   those affect actual execution. Existing scanner/table evidence is already
   retained; do not repeat the payload search to resume.
4. Develop MiSTer loader/SDRAM/video as a separate measurable slice. Simulator
   RAM is not an SDRAM controller; a simulated clear is not visible FPGA output.

## What to rerun, and when

Read existing reports first. Documentation changes need no long simulation.
After functional CPU changes run focused acceptance, original regressions and
synthesis-path lint. After board changes rerun affected firmware paths and the
software prefix with matching source hashes. Never compare stale model versions.

```sh
make sim-compat
make sim-upstream-patched
make sim-rtl-lint
make check-rom-extension
make sim-oracle-check
make sim-oracle-extension
make sim-firmware-extension FIRMWARE=firmware/SYM.ROM
python3 sim/run.py --firmware firmware/SYM.ROM --boot-profile amd16 \
  --ideal-clocks --lcd-probe --rom-extension --boot-io-probe --compact-trace \
  --latency 3 --max-cycles 165000000
python3 sim/compare_saved_oracle.py \
  --oracle build/oracle/amd16-ideal-clocks-lcd-probe-extension-boot-io/result.json \
  --hdl build/sim/runs/firmware-amd16-latency0-ideal-clocks-lcd-probe-extension-boot-io/bus.tsv \
  --hdl build/sim/runs/firmware-amd16-latency3-ideal-clocks-lcd-probe-extension-boot-io/bus.tsv
```

Use `make oracle-setup` only if its local environment is missing. `make
firmware-inventory`, `make inspect-flash-scan`, and `make inspect-boot` reproduce
existing audits without rerunning the long firmware delays; the latter requires
host Capstone. A two-million-cycle timeout during the LCD waits is not a deadlock.

## Do not rediscover

- ARM920T implements ARMv4T; ARM9 family and instruction set are not alternatives.
- Disabling branch prediction did not fix flash-return ordering; patch 0003 did.
  The rejected experiment remains in `scratch/boot-stage3/`.
- The post-MMU register lookup loop was a lost load-width transform, not a missing
  low-address ROM map. Recovered page tables map both `0x6d80` and `0x50006d80`
  to the correct table. The RAM reconstruction is `build/sim/pre-mmu-ram-words.json`.
- Runtime plusargs must only run in benches that initialize Verilator arguments.
  Patch 0004 uses `NGAGE_RUNTIME_TRACE`; original benches keep default printing.
- A failed container output-file creation is a harness failure, not firmware
  evidence. The runner truncates a host-created result inode and rejects empty
  output to avoid stale reports and an intermittent Docker bind-mount ENOENT.
- BOOT is a running-phone snapshot, ROOT is not a raw partition, and the published
  phone memory map is virtual. Do not concatenate dumps or mix NEM-4/RH-29 images.
- The 3.4-MB user capacity is not a physical offset. The type-3 map still needs
  reconciliation with three 8-MiB chips.
- Both retail ROOT dumps contain all their additional unpacked files. Developer
  ROOT is instead a suffix of its own ROM; its IDA databases are separate artifacts.
- EKA2L1 supplies host kernel/thread/services; rengage supplies synthetic maps.
  Neither supplies this phone's cold-reset registers or BSI sample. TriX is a
  useful UEM sequence reference, not a verified NEM-4 map or ADC capture.
- Unknown data operations stop before ACK. Speculative unknown fetches can fault
  and be discarded; a fetch abort reaching architectural execution stops the run.

## Sources already present

[README.md](README.md) indexes the topic docs. References remain in project
`scratch/references/`; prior findings are in `scratch/research/`. The user-saved
`docs/ser-no-n-gage-schematics.pdf` matches the retained NEM-4 PDF. ARM manuals
`ARM920T_TRM1_S.pdf`, `DDI01001.pdf`, and `ddi0180a_9tdmi_trm.pdf` are local; they
document ARM CPU behavior, not Nokia peripherals. Update the relevant topic doc
and this checkpoint before ending later development passes.

### Resume checkpoint: GPIO continuation and timer hypothesis

The counterfactual continuation in `scratch/variant-icu1c8` gets past the observed GPIO writes using explicit diagnostic reset-value and write-sink assumptions; this does not establish real GPIO behavior. It then waits on `0x8000000c` in the loop at `0x50322674`. The wait trace in `build/sim/runs/boot-variant-wait-trace` shows the flag cleared at first entry (cycle 452,457,263); firmware code at `0x503225b0..0x50322610` can set it to 1. No second timer interrupt was scheduled in the current model.

A useful next experiment is an opt-in periodic timer modeled on `scratch/references/nokia_6600_recomp/runtime/src/nokia_rt.c` (`nk_bus_tick`) and its README current-frontier discussion. That separate Nokia 6600 emulator models timer control 2, reload `0x632ea`, periodic expiry, IRQ 1, and an interrupt handler setting the same RAM flag. This is a hypothesis, not proof of N-Gage hardware. In this run the firmware writes reload `0x632ea` at cycle 451,437,796, compare `0x632ea` at 452,429,024, and interrupt enable at 452,429,369. Preserve the existing first boot IRQ and test any periodic behavior only behind an explicit experimental option, with a focused regression. The ICU write at `0x0c1201c8` is currently an exact write sink and may also matter.

The continuation alters the firmware-generated flash-class RAM table and makes other explicit peripheral assumptions, so success would not constitute a verified boot. `scratch/variant-icu1c8/verify-prefixes.py` independently checked the saved traces after fixing a self-comparison mistake in wrapper scripts. The all-`0x257e` V15 flash-ID experiment in `scratch/flash-all-257e-probe/run-long.py` was launched separately, without the RAM-table override; its IDs are hypothetical. Check its process and `build/sim/runs/boot-v15-all-257e/` before restarting. Keep output compact.

The all-`0x257e` V15 long run finished at cycle 725,805,161 on the unmodeled write to `0x0c120074`, after passing the prior VARIANT panic. It uses hypothetical flash IDs, so it is a diagnostic result, not a validated hardware configuration. Its screen capture is an assumed white clear, not a Nokia logo.
