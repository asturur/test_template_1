# SPMark04 benchmark diagnosis — 2026-11-14

MMC mounting and application launch are qualified separately in
[mmc-spmark04.md](mmc-spmark04.md). There is still no numeric benchmark result.
A native FillRate failure now has a reproduced CPU cause and a minimal HDL fix.
The new RBF and numeric benchmark results remain unverified on hardware.

## Confirmed Thumb LDM cause and local correction

A fresh FillRate-only run records `dst=00819EEC len=00000040 caller=FFE0B3DD`.
The terminal kernel exception is kind12, PC503A6B78, FAR00819EEC/FSR05. Its
saved user stack identifies GLES scratch allocator object004048E4 and backing
buffer00415600. The original GLES instructions atFFE0B3C8/CA are C903/1845:
`ldmia r1,{r0,r1}` followed by `adds r5,r0,r1`. Thumb LDM must retain the value
loaded into its base register when that register is in the list. ZAP instead
unconditionally requested writeback, replacing R1 with the old base+8. The
result is exactly the observed bad destination:

`00415600 + (004048E4 + 8) = 00819EEC`.

Patch0059 suppresses writeback only for Thumb LDM with its base in the list.
Thumb STM and LDM without a loaded base retain writeback; ARM LDM is unchanged.
This is a combinational decoder correction: no state, RAM or pipeline stage
added; PLL stays78MHz, with104MHz the design objective. Fitted area/timing and
unmodified-firmware benchmark progression require the next RBF. The earlier
Game initialization failure is not yet proven to share this cause.

The production CPU regression executes those exact two opcodes. Old RTL fails
signature11, overwrites R1 with80000208 and computes R5=00001208. Fixed RTL
passes in332/552clocks at memory delays0/3, including base-first, base-absent
and STM controls. The independent Unicorn oracle passes3311 defined Thumb
LDM/STM cases, checking registers, flags, stores and writeback. Verilator
checks all4096 decoder encodings (including unchanged empty-list decode).
Existing ARM LDM base-in-list, cold-base-last, translated small-page and CPU
throughput tests also pass at both delays. No shared simulation output changed.

Decisive stack/frame evidence is retained in
[evidence/spmark04-ldm-cause-20261114.json](evidence/spmark04-ldm-cause-20261114.json).
Accepted observer sources and preservation tests are retained under
`scratch/spmark-exception-20261114`; reload removed all observation hooks.

## Established observations

- The original card contains `3DTEST.DLL` (965,584 bytes) and
  `libGLES_CM.dll` (106,480 bytes). A read-only FAT12 chain/LFN extraction
  preserves all12 file hashes. The renderer identifies itself as Hybrid Gerbera
  1.4.3 / OpenGL ES-CM1.0. File presence does not qualify native RAM contents.
- A narrowly filtered, observation-only native `RLibrary::Load` probe reports
  success (`0`, handle `402c0019`) for
  `E:\System\Apps\SPMark\3dtest.dll`, caller `FFF028D8`.
- The original test returns `R0=BFF00000,R1=00000000` at caller `FFF029FC`:
  **−1**, using this old ARM mixed-word double ABI. This is an explicit failure
  sentinel, not a measured zero frame rate or an invalid timing division.
- Executing the original DLL's Run method at code offset148 in Unicorn confirms
  that a null test object or its initialization-error byte at offset50 returns
  exactly that sentinel before entering the game/scheduler. Four original-code
  paths cover both error branches and the successful dispatch (external
  run/wait/result functions spied). This does **not** identify why initialization
  failed. The constructor's error flag can reflect scene setup/allocation or a
  graphics error; neither is yet established on hardware.
- Custom selection with only **3D FillRate** enabled closes SPMark; native Menu
  displays **“App. closed SPMark”**. The existing USER panic/exit hooks did not
  identify its reason. The app can be relaunched. No phone reset was observed.
- Run Set → System Tests renders the Futuremark 2D image workload, advances
  through image scaling and reaches JPEG Encoding. It then remains without
  visible progress for minutes and does not return to Cancel before reload.
  No numeric system score is qualified by that sequence.
- Native System Information reports11,032KiB free RAM, NokiaN-Gage/Symbian6.1,
  Series60v1.2, ARM4T,4096colours and176×208. Its104MHz CPU field is firmware
  metadata; the FPGA PLL remains78MHz. System-wide RAM exhaustion is not shown
  by this snapshot; private-heap exhaustion remains a separate possibility.
- A read-only stable C: DDR capture and native LFFS extraction found no
  `spmark_log.txt`. The release binary has log-path strings but no established
  useful runtime log. No Flush or disk replacement was used.

## Accepted probe and limits

`minimal-boot.jsonl` under `scratch/spmark-benchmark-20261114` captures the exact
loader/result pair without reset, sticky fault, panic record, reader gap or
producer drop in that capture. Instrumentation changes execution cost; the
unmodified-firmware result remains the earlier native “Test failed” observation.
The tracer provides a reason-boundary observation, not a performance score.

The minimal probe only activates for the two known SPMark callers above. Its240
Unicorn cases check complete GPR/CPSR/SP/LR and live stack at the exact displaced
instruction continuation, exact output and bypass filters. RDebug's ABI is
spied; its full native service is not executed in that fixture. It is installed
only on guarded fresh CPU Hold, with the original image verified, original
checksum bounds/check retained and diagnostic MD5 recomputed. Reload removes
it. No SIM/BT/graphics response or deadline is substituted.

A broader earlier observer is **rejected evidence**: its initial address filter
missed EKA1's high DLL mappings, and a widened filter also logged unrelated NOS
comparisons. That instrumented boot showed CbsServer panic−4 and repeated44-byte
null allocations. Observer cost/reentrancy was not qualified; this does not
establish an uninstrumented CbsServer defect. Do not reuse the broad allocation,
null or comparison hooks. Failed sources remain in scratch with `-broad` names.
The minimal replacement boot reached responsive Phone/Menu without those logs
or a recorded panic.

## Earlier exception-capture approach (historical)

The kernel's unhandled user-exception terminal path at5032CD20 retains exception
kind inR4, saved17-word register frame inR5 and fault details inR7. A passive
observer at that terminal branch captures fault PC/CPSR/registers only after
ordinary exception handlers decline it. Kernel output uses the privileged byte
port, never the USER RDebug service. A separate SPMark-only ordinal-lookup probe
records the loaded3D factory and GLES entry addresses for symbolizing RAM code.

Sources/tests are in `scratch/spmark-exception-20261114`:240 USER probe cases
and20 kernel/lookup cases pass, preserving all registers/flags/SPSR/stack and
read-only frame/IAT contents at native continuation. Full exception-policy
execution is not simulated. This capture subsequently established the loaded-base failure above.

The RBF is stillcd46abe/run43609237775/seed44, source78bf39d. Its78MHz setup
slack is−0.270ns, so timing-clean qualification remains necessary. This fact
alone does not explain the repeatable failure. No PLL change, added FPGA debug
logic, other-thread simulation change or SD-card backup is part of this work.

## First fatal frame captured

The fatal-only kernel probe reproduces the isolated FillRate closure without
reset or trace loss. Exception kind12, fault PC503A6B78, FAR00819DBC, FSR05,
USR CPSR40000010; saved LR503A31F0 and SP0040480C. The PC is an EQ-conditioned
STM inside native Mem::Fill. **R1=40000000 is not the original length**: this
routine shifts its remaining byte count left24 and uses MSR NZCV as a bitmask;
it represents a64-byte tail. The original generic oversized-fill interpretation
was rejected after disassembly. The unmapped destination and its caller remain
the useful boundary. The later stack capture above established the CPU cause; this first frame alone did not.

The lookup probe identifies3DTEST atFFD00000 (factoryFFD00074) and libGLES_CM
atFFE00000 (glGetErrorFFE15367). The subsequent bounded fatal probe read the known
mapped user-stack page and CP15 PID/TTBR/domain state to recover the calling
renderer routine and distinguish a bad pointer from mapping/CPU state.
Evidence: scratch/spmark-exception-20261114/boot.summary.json and raw capture.

## Date/time and saving follow-up

User requests persistent normal boots. Production UEM/CBUS currently forces
cfg7/register31..33 reads to zero, clears its written/state bits on reset and
has no HPS RTC/TIMESTAMP input. hps_io already provides both RTC65 and
TIMESTAMP33; Template does not consume them. This is an established missing
clock backend, not proof that it alone controls the Startup prompt. C:/PMM are
also restored from the same seed while Background save is Off.

Donor rtc_wall supplies binary seconds/minutes/hours and an8-bit day counter,
but its full-date register at0C1F0100 is explicitly an HLE invention consumed by
its substituted NOS. It cannot be copied as a solution for our original native
NOS. Native calibration/day-base/PMM handling must be verified. Autosave is a
separate current hardware gate: earlier write-back and queue failures prompted
save Off; local fixes/tests are documented in background-save.md and
save-blockers-2026-11-12.md, but current normal-boot draining is unqualified.
No autosave enable, Flush, image backup or disk mutation was performed during
this fault capture. Validate saves with DDR queue/LBA/error evidence and then
reboot/read back actual C:/PMM contents, rather than infer success from the OSD.

Autosave follow-up: the later uninstrumented normal boot successfully drains42
sectors and both files match stable live DDR after host sync; see
[background-save.md](background-save.md). Clock semantics and cold reload are
still separate. The CPU fix has no memory/state/pipeline addition. Patch chain
verification fetches pristine upstream via gh into isolated output; all58 active
patches apply and RTL lexical tokens match. Existing unrelated whitespace drift
in the maintained ZAP tree prevents the old byte-identical provenance check;
this was not repaired by reformatting the imported CPU.
