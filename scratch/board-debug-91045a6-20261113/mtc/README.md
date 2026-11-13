# Native MTC/SIM/DOS observation on91045a6

Read docs/board-boot-91045a6.md and docs/sim-adsp-native-progress.md first.
This is observation-only diagnostic code, never a production firmware fix.
Trace Thumb veneer at511BD000 saves original registers/flags/stack, prints
MTC arguments/caller/current native fields, then tails original5159A198.
Only ABI-scratch r12 changes on native entry.24 original direct BL sites in
51599000..5159AFFF are enumerated/guarded. Original encrypted words are decoded,
patched, inverse-encoded; expected diagnostic MD5 is recomputed, check retained.
SIM fallback/DOS observers are the existing separately qualified implementations.

prepare.py builds MTC+SIM+exit observer; prepare_dos.py also adds DOS event tracing.
Both generate guards requiring original full ROM, original words, physical fresh
Hold, saved Run off, restored media/save Off and two advancing snapshots. Never
apply warm. Copy complete source/helper to board only after ABI tests pass.
Use mister-control skill settings/input procedure; restore saved Run/save-Off.
Reload removes hooks; verify full original88fd596a... afterward.

Native result array80024388 is read only on MTC message64/argument6, in NOS
context after startup failure has been published. Do not move that direct read
or debug59 MMIO to the DOS user wrapper: its address-space permissions differ.
Intermediate failed-context experiment was discarded and removed by reload.

program.S/tb.v qualify original arguments, entry/returned flags, callee registers,
SP and ARM/Thumb return, exact7field log and24byte native result dump on actualZAP
at memory waits0/3. Mock native function intentionally supplies no device success.
Initial extended fixture lacked80020000 RAM decoding; fixed before board apply.
Build using run.sh and existing jotego/simulator:arm64 only. Generated ROM/data,
objects and logs remain ignored. Do not touch another thread's simulations.

560-snapshot board result/no reader gaps: DOS event1/value2, native array
03030000 00030000 03000000 030d0000 03030301 0401030d.
Fatal registry entries RF1E=0D, ADSP36=01; BT15=0D,current02=01 lower severity.
No serving SIM, Menu or HDL boot fix is claimed by this observer.
