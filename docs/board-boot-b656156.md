# b656156 original-firmware board capture — 2026-11-13

The installed RBF matches completed run43423483543, commit
b656156c0adc3cad4fdb17452b1994c5f5b6ed1f, **seed44** (not the suggested43).
SHA256 `048a35ba599abf46c21fb0c3750826a8742a6424f782dfd88e72879af1fb330b`.
Live original ROM SHA88fd596a23269ecb0d9f7544d540c59010d276574dbe3d0262c870c429e58329;
C:/PMM retain af5017dc... /71189f7f... known-good hashes. Reload through Zaparoo,
automatic CPU Run, Background save Off. No ROM/RAM patch, Flush or image replacement.

## Board observations

The prior~1.108B-cycle storage reset does not recur.1,979 current-generation
snapshots cover about56.0B unwrapped active CPU cycles (718s). Generation remains0,
CPU and bus activity advance, first sticky non-fetch fault fields remain zero,
and queue count rises0->1,118 then remains stable without overflow, invalid
sector, tracker error or slot error. No data fault, host-save request or media
write was observed. The containment path itself is **not exercised on this boot**;
the old queue trigger remains unresolved and may depend on implementation.

The old permanent UART drain is passed: kernel text advances through10 Bluetooth
error/retry groups, ADSP server session construction, then
`CSysApAppUi::ConstructL: Start listening` and `TRtcQueue::Add: 5`.
Display advances from Nokia to the N-Gage logo. This is real startup progress,
not a working Phone/Menu result.

After that, long windows sample only mode1B and kernel/NOS idle code, notably
516C7130/713C/7188/719C and514AF5C8..624, reading the six ICU current registers
0C120114/154/194/1D4/214/254 as0. Original disassembly confirms the NOS callback
polls those banks; prior investigation already identifies this as the ordinary
NULL/idle callback. Do not repeat the old false "NOS readiness waiter" theory.
It establishes no runnable foreground work, not the causal blocked request.

A one-second Menu hold reaches mask00000040; digit1 reaches00001000. Neither
changes the logo or resumes visible Phone activity. A quick preceding Menu tap
was not sampled; a missed tap alone was not interpreted as failed input.
Zero panic_report is only absence of the existing kernel report: it does **not**
exclude a user/thread panic or prove ViewSrv/Phone remains alive.

## Implementation qualification

All16 SDRAM data/input/OE registers still pack in IO cells. Fit needs37,271 ALMs,
43,054 registers,506 M10Ks,2,760,205 block bits and42 DSPs.
This seed fails constrained78MHz core setup: worst -0.932ns, TNS -5.228ns;
core hold +0.244ns. HDMI setup/hold +0.142/+0.254ns. Snapshot RAM inputs account
for the worst path, but functional DMA (-0.693ns), TLB (-0.163ns) and other
endpoints also fail. It is not safe to dismiss the failure as telemetry-only.
No104MHz or complete78MHz timing qualification is claimed. Completed artifacts
were downloaded once, without launching or monitoring builds.

## Next evidence gate

The next foreground blocker is not yet identified by these snapshots. Do not
apply the prior BT/SIM/deadline/self-test patch bundle or claim the idle callback
is the failing component. Resolve timing qualification and capture native thread
exit/panic/request ownership without modifying firmware. Existing global fault
fields do not provide thread arguments/caller or a process inventory.
A passive CPU retirement/exit observation is a possible next HDL addition;
it is not implemented by this capture and must fit area/104MHz constraints.

A later bounded skill validation sees the clock screensaver. Holding Menu with
`mister-control` wakes it back to the N-Gage logo: mask40 is sampled, CPU leaves
idle briefly (503B321C), reset generation stays0, first fault stays0 and queue
stays1,118/error-free. This directly demonstrates wake/input/display activity;
the apparent "back to logo" is not a CPU reboot in this run. It still does not
identify why the Phone/Menu foreground is unavailable.

Read-only capture was stopped; phone left running. No other thread simulations
or checkpoints were touched. Raw JSONL, decoded kernel text, original disassembly,
screenshots and completed reports are in `scratch/board-debug-b656156-20261113/`.
Compact identities/samples: [evidence](evidence/board-boot-b656156.json).

## Follow-up: native thread failures captured

The previously unidentified foreground failure is now observed with the reused
software tracer: Phone's named main thread is killed by ViewSrv11 while file
Write/Flush is pending. A separate native Nokia.dsy USER21 matches the short
PMM error from the prior investigation. The lighter exit-only control also
captures Phone11, so file-wait logging is not required for that failure. See
[the consolidated blocker map](menu-blocker-map.md). This updates the earlier
unknown frontier without claiming a lost IRQ, exact file or complete boot fix.
