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
Tracer is installed; CPU Run confirmation/output and actual Phone caller/exit
cause remain pending at this checkpoint. Do not patch an executed/cached core. If no trace
appears, do not infer no exit: the existing C: record and hook coverage matter.

Local inputs, original/live disk copies, byte checks and raw/decoded output:
`scratch/menu-bringup-20261112/`. Exact original restored disk pair/backups remain
as documented in `working-nga-restored-2026-11-12.json`. No save has been triggered.
