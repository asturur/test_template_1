# Symbian startup blockers

The immediate objective is a working phone. Performance work resumes only when
it is necessary to diagnose or remove a demonstrated startup blocker.

## Hardware panic, 2026-11-10

User identifies the running RBF as commit `40bfc11` (MMU handshake fix, before
ARM920T64-entry TLB replacement). NOS OFF and ON reach the same stop; Bluetooth
ON blocks before the logo. Those are distinct observations, not established
shared root causes. Use an unmodified-firmware baseline before testing overlays.

The live capture is retained in
`scratch/hardware-live/hardware-stop-2026-11-10T12-28-08-204Z.png`.
Fetch `50324294` is the firmware panic handler's final self-branch. Its three
report writes are at physical `0c0047f0/f4/f8`; the captured fetch `503245c0`
is the reporting STR helper, not evidence of the original faulting instruction.
The sticky board fault flags describe a read while that helper writes, so the
existing record alone cannot identify the original exception or explain the
transaction mismatch.

Independent ARM disassembly of pristine NEM-4 `SYM.ROM` proves:

- `50333e70` stores a reason at superpage `40000410`, then copies up to eight
  category bytes to `40000418/1c` and branches to `50324240`.
- Entry `50333e68` first adds `10000` to the supplied reason. Do not assume
  every reported reason has this bias or subtract it without identifying entry.
- `50324240` sends category words to `47f0/f4`, reason to `47f8`, signals the
  handoff/reset controls, then parks at `50324294`.
- Ordinary reports contain **category and reason**. Special reason `10000000`
  preserves the pre-filled context words instead: the observed exception
  packet holds PC and fault address. The decoder handles this special case. Example fixture
  `65637845 6f697470 00010003` means truncated category `Exceptio`, raw reason
  `00010003`. This fixture is not a captured hardware panic.

Evidence: `scratch/hardware-fault-47f0/{category-reason,ekern-abort}.txt`.
The original hardware report remains unknown. A later4.4B corrected-sim
checkpoint DOES reproduce the final panic: CPSR600000D7, FSR0000001D,
FAR59893FE0. Its superpage report is5038524C /59893FE0 /10000000. This special
packet preserves exception context rather than a category string. An exact
matching4.3B checkpoint is available to capture the first exception. Whether
the hardware has the same original exception is still unverified.

## Passive panic recorder

`ngage_trace_sink` now observes attempted writes to these three words without
claiming the addresses, acknowledging accesses, or modifying scratch validity.
Held requests produce one event; adjacent addresses remain observable without
requiring an idle cycle. Panic events take priority over coincident unknown-LCD
trace events; the existing dropped-event counter still reports the collision.

`ngage_diagnostics` retains the first full-word write to each address until cold
reset, independently of ring wrap/freeze. Partial writes stay in the ordinary
trace but do not mark a complete report word valid. Warm CPU reset preserves
these diagnostic latches. This captures reporting attempts, not proof of a
successful physical mailbox write or correctness of the peripheral model.

The new bottom `PANIC` row shows category word0, category word1, raw reason,
and a validity `MASK`. Mask7 means all three words were seen. The existing
fault rows keep their meanings. The report shares the screen's coherent4Hz
snapshot. A zero mask means no full report word has been observed.

The1024-byte NGD export keeps version1 and the existing ring layout. Optional
metadata halfwords396..403 contain magic504e, mask, and the six little-endian
payload halfwords. `tools/ngage_diagnostics.py decode` reports a `panic_report`
object, or null for an older export. Missing category/reason fields decode to
null rather than fabricated zero values. Export after the panic has parked.

## Corrected simulation

The compatible corrected-discard lineage e9861e744de45ca0 has no panic at4.2B:
CP15 FSR/FAR, ABT LR/SPSR, and superpage report words are all zero. Twelve
processes exist, including RfsServer, EInfoServer, SelfTestServer, SplashScreen,
window/font servers and Starter. Counts/objects come from the firmware-specific
container observer; a field named exit=3 is not proof those processes exited.
A separate1M-clock continuation had no new bus errors/data aborts and executed
window-server bitmap/pixel-conversion code. This is active work, not proof the
UI is operational or the model matches the board.

At4.3B the same12processes remain, active thread belongs to EwSrv, and bus
errors are still30923398 with data errors0. The32-bit cycle field wraps to
5032704; checkpoint ancestry/host ticks establish4.3B. No hardware panic was
reproduced.

Main continuation `build/sim/runs/icache-discard-recovery-12b/` preserves its
frozen executable/profile and100M checkpoints. It does not contain the newer
MMU/TLB changes. Current working-tree HDL edits cannot alter that running binary.
Never import a checkpoint into a different HDL model without an explicit audit.

Diagnostic observer `scratch/hardware-fault-47f0/watch.cpp` is linked to exactly
that frozen model. On a separate fork it stops at a new bus/data error, entry
into ABT mode, or the final panic PC and saves a CPU/host pair plus register,
FSR/FAR, superpage and recent writeback-PC observations. Its scanout is not
updated: these are forensic checkpoints, not normal screen/checkpoint lineage.

## Next evidence

Test the latest TLB plus passive recorder on hardware, initially NOS/BT OFF.
If it panics, obtain the PANIC row or export: identify the category/reason before
changing peripheral behavior. The old FIQ/store-return regression now passes
with the new TLB, but its D1 result was a test failure marker, not itself proof
of the hardware exception. Do not claim the TLB fixes this panic until measured.

If the long sim encounters a new fault, inspect the nearest100M checkpoint with
the matching observer and capture the first exception. If it remains fault-free,
track actual process/request completion rather than treating unchanged logo
pixels or an idle thread as a deadlock. Firmware and C: inputs remain unchanged.


## First exception and request-owner fix

The frozen e986 replay captures its first ABT entry at cycle4,372,559,219.
`LR_abt=50385254` identifies the precise faulting instruction5038524C (STRH),
`SPSR_abt=400000D1` establishes privileged FIQ mode, FSR1D/FAR59893FE0 report a
section permission fault. The page-table descriptor0240043A maps that access to
C: flash02493FE0, AP1/domain1; DACR selects client access. That store is permitted
in FIQ. It is not evidence of a missing disk file or required firmware patch.

At the actual request, P1mode=10(user), P2mode=11(FIQ), P1force-user=0. The CPU
exported P1's mode with P2's address/data, wrongly presenting this protected
write as user access. The following exception return had restored user mode in
P1 before the older store completed. Patch0054 exports BOTH mode and force-user
from P2. This retains the existing registers and MMU permission rules.

A strict close source at4,372,558,010 has no CPU memory request, cache/translation
transaction, CP15 operation or buffered store outstanding. The old control
aborts1209clocks later, with a CPU checkpoint byte-identical to the first replay.
The audited fixed fork preserves17067 common fields, all RAM/DDR/CPU/cache
state; it imports20D/19I mappings into new TLBs, invalidates new permission
tokens, and seeds only the new inactive P2 force-user bit and passive panic
observations. Typed table import plus field whitelist/hash report lives in
`scratch/hardware-fault-47f0/close-owner-fixed.migration.json`. This is explicitly
a diagnostic fork, not arbitrary saved-state compatibility or a cold boot proof.

The initial4.3B TLB-only exploratory import used an insufficient quiescence
check: P2 could have just admitted a request despite idle external/cache paths.
Do not use that import as the final proof. The close fork adds explicit P2,
CP15 and both write-buffer checks. It also replays the old exception exactly.

After10,000 fixed clocks, FSR/FAR and ABT LR remain zero, no panic words were
seen, and the target simulated C: word changes fromFFFFFFFF to00000001 followed
by further firmware writes. CPU has returned to startup. The source firmware
and C: files retain their hashes; the firmware is writing only its simulated
working flash, as a real boot would.

The focused regression's privileged stores before exception return and forced
user LDRT cover both sides of the bug. Original wiring wrongly grants the LDRT
inside SVC and failsD2; fixed wiring correctly raises FSR1D/FAR59800100 and
recovers, passing0/3. Before/after program binary hashes are identical. A first
isolated baseline attempt read the shared suite's hardcoded program path and
failedD6; it is INVALID evidence. The final reference testbench uses its own
program path and the logged D2 LDRT failure is the valid comparison.

Full CPU suite180PASS, patch0054 reconstruction and source preflight pass;
separate fixed cold50M completes normally with12known initial bus faults/data0.
The fixed post-failure phone continuation COMPLETED50M additional clocks at
4422568010: FSR/FAR/ABT LR/panicmask remain zero; bus errors unchanged/data0.
BTTestServer starts, increasing the process count from12 to13. Nokia remains
on screen; this is startup progress, not a demonstrated working UI. A strict
fixed-model continuation toward12B is running with100M screenshots. The old
confirmed panic-loop run was gracefully stopped and all checkpoints retained.

Bluetooth overlay ON's separate pre-logo failure remains OPEN. This verification
uses NOS/BT overlays OFF. Do not claim that the P2 fix repairs the overlay;
load/hook compatibility needs its own investigation and boot validation. Hardware has not yet validated this fix; the old board screenshot alone
does not prove the same original exception, though the terminal panic matches.
