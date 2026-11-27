# Original NEM-4 keypad GPIO fixture

`run.sh /path/to/ngage-rom-0x50000000.dmp [repository-relative-output]`
extracts stock private original instructions, validates the ROM hash and executes
unmodified `ekeyb.dll` GPIO dispatcher `5041a3cc`, scan helper `5041aa0c` and
acknowledgement `5041ac84` on ZAP against the actual board/UPP/keypad modules.
The default output is `scratch/ngage2-integration/keypad-flow-2026-11-11/`.
The existing pinned simulator image runs with the network disabled.

The authored caller exercises data clear/set, input/output direction, per-pin
IRQ disable/enable, both scan directions, acknowledge while held, re-enable
while held, release/repress, GPIO30 data aliases, rocker Up and music. Runs use
78/104 MHz board parameters and zero/three memory waits. The fixture translates
the original mapped `581xxxxx` accesses to physical board `0c1xxxxx`, with MMU
disabled. Its mailbox changes public key levels; it cannot change peripheral
pending state. Program/object/stack RAM are bounded fixtures. No original
instruction, import or return is patched.

This executes the original GPIO operations and polling checks, not the complete
Symbian keypad DFC/timer/IRQ entry path. In particular, the original Down logical
mask additionally invokes the GPIO23Low callback object at `this+24`; the
zeroed fixture object has no initialized callback, so this test deliberately
uses Up/music for original direct-input coverage. All six direct keys remain
covered by the public board and protocol tests. Physical phone pin routing,
pullups, reset direction and multi-contact ghosting remain unverified.
