# Fresh integration startup: process and CPU inspection

Read at the frozen6B and7B checkpoints of model `8b92e8641d9c7365`.
At78MHz,7.24B clocks represent92.82 seconds of simulated CPU clock time.
Elapsed clocks alone do not establish a permanent wait, and this CPU's IPC
is not established equal to the original ARM920T. The missing usable UI still
requires investigation; these observations do not qualify boot as correct.

## Observed state

At7B there are32 process objects,31 with exit type pending and one retained
exited DBRECOVERY object. At6B there were also32; by7B SplashScreen has left
the list and FLogSvr has appeared. Both snapshots have zero FSR/FAR/ABT LR.
EikSrvs contains AppArcServerThread, EikAppUiServer, ViewServerThread,
BackupServerThread and KeySoundServerThread. AppRun instances host SysAp,
Phone, ScreenSaver, Autolock and Startup. Thread presence is not proof of a
rendered home screen or completed initialization.

Two independent2M-clock samples, one per checkpoint, sample the current-thread
pointer every128 clocks. This includes kernel work charged to that thread.
At6B EFile owns67.23%, WAP13.45%, Phone11.08%, Supervisor8.24%.
At7B Phone owns49.77%, EFile32.85%, WAP9.00%, NULL7.82%, Supervisor0.55%.
Neither sample spends its time in AppArc. IRQ/FIQ mode occupancy is7.43% at7B,
which does not support an interrupt storm in this sample.

At7B code-stall is58.21% and data-stall41.58%, with29.79% overlap. These
are CPU stall flags, not isolated memory-device latency. Modeled DDR transfer
delay occupies2.69% and C: bus activity0.55%; other queue/cache/CPU handoffs
are outside those narrow backend counters. Do not claim physical memory speed
from this testbench profile.

Canonical C: hash still matches the run input manifest. C: differing byte
positions versus that input rise340,904 ->409,514 between6B and7B; these are
net byte differences, not a transfer counter. The7B sample has428 C-bus read
ACKs and1092 write ACKs (including NOR commands), with541 byte positions
changed during2M clocks. The6B sample has no C-bus operations. Phone home-stack
strings change from resource paths at6B to profile/database-related text at7B;
stack strings may be stale, so they do not identify the current SQL request.

## Waits and remaining uncertainty

StarterServer remains blocked on its request semaphore. At7B AppArc is also
blocked in the standard wait path. EikAppUiServer and Startup save LR50916F7D:
original Cone.dll code at50916F78 calls import50919EEC -> pointer503CBE5C ->
EUser stub503B246C ->503AC664 (`svc #4D`, WaitForAnyRequest). This is an ordinary
request wait, not independent evidence of a missing readiness notification.
The original Thumb return is verified from retained firmware bytes. Resolving
which outstanding request should wake the UI still needs a request/completion
trace; a shared wait PC alone cannot establish that cause.

Current evidence supports ongoing Phone/file-server/database work rather than
the old fetch deadlock or an AppArc scan dominating the CPU. It does not yet
prove that work terminates or that all asynchronous completions are correct.
Next trace Phone's current initialization call and its EFile request/result,
checking for repeated operations, errors or a request that never completes.
Keep the long run, firmware and canonical C: untouched.

## Process inventory at7B

| Object | Firmware image | Exit type |
| --- | --- | --- |
| `80404cb0` | `Z:\System\Libs\EKern.EXE` | 3 |
| `80408db0` | `Z:\System\Libs\EFile.EXE` | 3 |
| `8040b3b8` | `Z:\System\Libs\EwSrv.exe` | 3 |
| `8040c364` | `z:\system\libs\FbServ.exe` | 3 |
| `8040ef80` | `Z:\SYSTEM\PROGRAMS\Starter.exe` | 3 |
| `8040b734` | `Z:\System\Programs\SharedDataServer.exe` | 3 |
| `8040f83c` | `Z:\System\Programs\DosServer.exe` | 3 |
| `80410634` | `Z:\System\programs\SelfTestServer.exe` | 3 |
| `8041102c` | `Z:\System\programs\EInfoServer.exe` | 3 |
| `80411754` | `Z:\System\Libs\randsvr.exe` | 3 |
| `8041236c` | `Z:\System\Programs\BTTestServer.exe` | 3 |
| `8041379c` | `Z:\System\Programs\Sysagx.exe` | 3 |
| `80413cd4` | `Z:\System\Programs\EikSrvs.exe` | 3 |
| `80417bac` | `z:\System\Libs\C32exe.exe` | 3 |
| `804183ec` | `Z:\System\Libs\Ealwls.exe` | 3 |
| `80419c80` | `Z:\System\Libs\MediaServerStub.exe` | 3 |
| `8041c738` | `Z:\System\Programs\PhoneServer.exe` | 3 |
| `804130c0` | `Z:\System\programs\DBRECOVERY.EXE` | 0 |
| `8041dd44` | `Z:\System\Programs\EDbsrv.exe` | 3 |
| `8041e430` | `Z:\System\programs\sae.exe` | 3 |
| `8041e774` | `Z:\SYSTEM\PROGRAMS\AppRun.exe` | 3 |
| `8041ed70` | `Z:\System\programs\adspserver.exe` | 3 |
| `80422010` | `Z:\SYSTEM\PROGRAMS\AppRun.exe` | 3 |
| `804225e0` | `Z:\System\programs\AudioServer.exe` | 3 |
| `80419364` | `Z:\System\Libs\watcher.exe` | 3 |
| `80422fa0` | `Z:\SYSTEM\PROGRAMS\AppRun.exe` | 3 |
| `80424b60` | `Z:\SYSTEM\PROGRAMS\AppRun.exe` | 3 |
| `804259a4` | `Z:\SYSTEM\PROGRAMS\AppRun.exe` | 3 |
| `80426084` | `Z:\System\Programs\LogServ.exe` | 3 |
| `8042f2c0` | `Z:\System\Libs\Loadersrv.exe` | 3 |
| `80424568` | `Z:\System\Libs\WAPSTKSRV.EXE` | 3 |
| `8043479c` | `Z:\System\Programs\FLogSvr.exe` | 3 |

Exit type3 is pending;0 is exited. Raw named threads, wait state words, CPU
sample counts and memory counters are retained in the [evidence JSON](evidence/ui-startup-processes-2026-11-12.json).
Full inspection/profile logs and exact observer sources are under
`scratch/ui-startup-20261112/`. These observers do not save or mutate the
main checkpoint and are linked to its exact frozen HDL archive. No key was sent.
