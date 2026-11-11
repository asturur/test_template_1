# Symbian startup blockers

The immediate objective is a working phone. Performance work resumes only when
it is necessary to diagnose or remove a demonstrated startup blocker.

## Integration build hardware stop, 2026-11-11

The user reports that RBF `8ff8b11` reaches the logo and then shows fetch
addresses `0x50324294`, `0x503242a0`, a few other addresses, and `0x00000000`
before apparently restarting. `0x50324294` is the kernel panic handler's
final branch to itself. `0x503242a0` is the literal `0x000047f4` in the
adjacent panic-report address table. The debug raster samples the fetch bus,
so it can show nearby fetches that never retire. A zero fetch address alone
does not establish a restart or its cause.

`8ff8b11` already contains the passive panic recorder and the prior
request-privilege fix (`11dea96`). The same terminal PC occurred in several
earlier panics with different triggers. The mounted SD card's
`diagnostics.ngd` is an older export
without either the panic or save-error metadata. At inspection, `boot0.vhd`
was all `0xff` and `boot1.vhd` had non-erased bytes in six sectors. These
describe the files on disk at inspection, with no inference about pending
or committed writes during the reported boot.

Zaparoo capture at 01:45 CET shows `PANIC 503AD63C E59FF044 10000000 MASK 7`,
`CPSR 600000D7` (Abort mode), `BOOT FLAGS 0809019F`, `SAVE ERR 0`, and
`RESET 0`. The report is the exception-context form. The NEM-4 ROM maps
`503AD63C` to an `EUser.dll` load, `ldr r0, [r0]`. The reported fault address
is `E59FF044`. The capture establishes an invalid-looking load address and
leaves its pointer origin unresolved. It shows both overlays loaded with
their apply bits clear. The screenshot was captured while parked and does
not establish the reset history. PNG and capture metadata are under
`scratch/hardware-live/hardware-stop-2026-11-11T00-45-36-862Z.*`.

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


## Post-Nokia startup audit (2026-11-10)

Hardware user reports N-Gage logo with overlays/skips OFF. NOS ON did not
reach it in the next trial; unmodified hardware retry underway. Exact board
completion and overlay failure causes remain unverified. Do not reset hardware
or equate the simulator's Nokia image with the N-Gage animation/UI.

Read-only state inspection of fixed-model a6d40d0d5005ce63 checkpoints4.5/4.6/
4.7/4.8B finds13 processes, including RfsServer and BTTestServer. Latest observed
long progress4.81B; original12B run left running. Original firmware/core/extension
and C source hashes match its manifest, as do the4.7B CPU/host checkpoint hashes
recorded by its screenshot callback. No firmware patch or source C modification.

RfsServer stack contains factory-file paths: `\System\Data\CACerts.dat` at4.5B,
`Z:\Nokia\Images\Pictures\2.ota` at4.7B, and `\Nokia\Images\N-Gage5.jp...`
at4.8B (dump boundary truncates the last name). Simulated C differs from initial
input at25740/35775/39912/57887 byte positions respectively. These are differing
positions, NOT a byte-transfer counter. Combined with changing stacks and actual
programming, evidence supports ongoing first-boot factory-file population rather
than the old panic or a demonstrated permanent wait. It does not prove factory
initialization finishes or that files are correct.

Important observer pitfall: inactive moving user chunks must be inspected via
their saved home chunk_base (HOME_STACK). Reading VA00400000 through the current
mapping showed BTTestServer's btldd.LDD strings while labeling them RfsServer.
That apparent return to the same file is INVALID loop evidence. Correct home
stacks show the changing factory-file paths above.

Separate exact-HDL3M replay from4.7B: EFile main thread owns17320/23438 samples
(~73.9%, every128clocks; includes kernel work), RfsServer2560 (~10.9%), NULL2573
(~11.0%). IRQ77708 + FIQ131341 =6.97% of clocks, not an interrupt storm in this
window. Code-stall2257734/3M=75.26%; data-stall1076142/3M=35.87% overlaps it.
These flags do NOT independently attribute waits to DDR or justify removing
104MHz timing registers. Old scan-loop probe503909A0 never fires in this sample.
No increase in backing-bus errors30923398; data errors0.

Independent1M storage probe: C-bus pending5186clocks (0.52%),146 acknowledged
reads/576 writes (includes NOR command writes); DDR modeled delay44973clocks
(4.50%, all clients),127 C bytes changed during the interval. C bus/DDR busy
counters overlap other work; they are not end-to-end operation latency. Thus
raw C backing-store waiting is not the dominant observed cost in this sample;
firmware/filesystem/CPU work between transactions matters. Existing model
C-NOR semantics remain experimental, not certified against the physical phone.

Evidence and passive profilers: scratch/post-nokia-startup/{evidence.json,
state-4500m.log,state-4600m.log,state-4800m.log,profile*-4700m.log,profile*.cpp};
4.7B full state scratch/hardware-fault-47f0/state-owner-4700m.log. Profilers link
only the frozen archive/runtime objects, do not modify source checkpoints, and
run no host input injection. They do not maintain the scanout buffer or create
resumable pairs; use the normal runner for future saved continuations.

Next: follow actual factory-copy completions and startup-server progress at later
100M checkpoints; if progress stops, trace the pending request from its correctly
mapped client stack. Do not implement another firmware/peripheral stub based on
an unchanged logo alone. Once initialization succeeds, export a NEW populated
C image (and consistent PMM where needed) for hardware comparison, retaining
original inputs. Export is proposed, not yet performed or hardware-verified.


### Code-stall decomposition (2026-11-10)

Same exact-model4.7B->4.703B3M replay; observer reconstructs code_stall every
clock and aborts on mismatch. PASS, matching previous endpoint/cost counters.
Code_stall is an OR of FIFO full, uncached-store ordering and fetch response wait;
it must NOT be described as75% lost instruction-memory clocks.

Mutually exclusive reason masks (bit0FIFO full, bit1uncached store, bit2fetchwait):
0=742266;1=566028;4=1679680;5=12026;others0. Thus FIFO-only18.87%, fetch-only
55.99%, both0.40%, no code stall24.74%. No uncached-store guard clocks. FIFO
backpressure reflects downstream throughput, not necessarily lost CPU cycles.
Fetch waits total1691706 (56.39% all clocks), of which cache WAIT_REFILL1351156
(45.04% all clocks). Remaining I-cache states: IDLE131257,LOOKUP57265,
READ_LINE47381,LOOKUP_WAIT57265,LOOKUP_CAPTURE47382. TLB busy overlaps83875
fetch-wait clocks (2.80% of all clocks); data_stall overlaps461557. These
are overlapping observations, not additive percentages. See exact raw counters
scratch/post-nokia-startup/stalls-4700m.log and matching passive stalls.cpp.

Refill implementation fetches eight32-bit words serially for a32-byte ARM920
line, publishing after full refill. This is different from the separate1KiB
DDR instruction buffer's64-bit lines. Dominant WAIT_REFILL still needs attribution
between transfer beats, outer arbitration, DDR/controller waits and setup.
scratch/post-nokia-startup/refills.cpp and linked refills executable are prepared
against a6d40d0d5005ce63 but NOT RUN. Resume with separate3M observation of
build/sim/runs/panic-owner-fixed-12b/checkpoint-4700000000, retain output separately.
No CPU/cache timing register removed or performance change made.


### Completed refill drill-down (2026-11-10)

refills.cpp and refill-reuse.cpp now COMPLETED the same3M interval. Identical
endpoint and stall totals, no new bus/data errors.9884 instruction line fills,
79072 acknowledged words (exactly8per fill),3303distinct physical32byte lines
(105696bytes touched, not necessarily simultaneously live). No I-cache disable
clock or global invalidation observed. Maximum listed single-line repeat19;
this evidence does not prove a replacement-policy defect or ideal miss rate.

WAIT_REFILL1351156clocks /9884 =136.70clocks per fill. Transfer phases:
- WAIT_TRANSFER/REFILL, bus_valid and inflight, no ack:1049651clocks.
- Same with bus_valid but not inflight:133477clocks.
- Acknowledged word:79072clocks.
- Remaining coordinator states:9884clocks each for IDLE,TAG_WAIT,COMPARE_WAIT,
  SELECT_VICTIM,READ_VICTIM,START_TRANSFER,INSTALL,COMMIT and WAIT_TRANSFER tail.

Transfer averages15.96clocks per32bit word:13.28inflight waiting,1.69before
inflight,1ack. Coordinator overhead averages9clocks per line beyond transfers.
About90% of WAIT_REFILL clocks target physical003xxxxx main ROM (1216686);
raw modeled DDR busy across ALL clients145533clocks (4.85% of all clocks).
Backing-memory activity overlaps other stages and does not by itself yield an
exact removable-wait count. Dominant cost is many serialized line beats through
the registered return path, rather than global I-cache invalidation or page
walks. It remains necessary to isolate outer ROM/controller stages before
removing any register;104MHz intent still applies.

Next performance candidate: retain registered ownership/timing boundaries but
carry a whole32byte instruction refill through the outer memory path, with
burst/line response assembly, instead of eight fully separate request round
trips. Critical-word-first/early restart can be considered separately with
redirect/discard/error correctness tests. This is a measured direction, NOT
an implemented change or speedup claim. Do not enlarge caches or bypass MMU
permissions based solely on this sample. Logs and sources live under
scratch/post-nokia-startup/{refills,refill-reuse}*; aggregate evidence.json.


### Hardware screensaver wakes to N-Gage image (2026-11-10)

User observes a clock screensaver; a key wakes it to the N-Gage logo, then the
clock screensaver returns after roughly one minute. This establishes visible
key-dependent behavior, not functional menu navigation. Current hardware commit,
named key and overlay settings were not identified in this report. A reboot,
normal screensaver wake exposing a stalled startup image, and a stalled UI/key
event consumer remain distinct hypotheses. An image alone cannot identify one.

Investigation sequence, without firmware/C modifications:

1. Wake using Menu (Tab), then press/release Menu again and left softkey (F1)
   separately with OSD closed. First input may only dismiss the screensaver.
   Avoid Power/End as the initial comparison; they have different semantics.
2. Obtain diagnostic screen/export before waking, immediately after, and after
   returning to screensaver. Compare fetch-PC samples, CPSR, fault/error growth
   and PANIC fields. Existing KEYS HELD confirms delivery only to the phone
   input boundary. It does not prove firmware consumed a key event.
3. Existing CYCLES/fault history survive warm reset, so monotonic CYCLES cannot
   rule out a restart. If captures remain ambiguous, add a passive reset-edge
   counter and short retired-PC/reset-vector history in a separate change;
   record clock-wrap limitations and keep registered capture boundaries.
4. Replay a separate compatible checkpoint with one named key pulse, tracing
   held mask -> GPIO drive/sense -> edge latch -> ICU25 pending/mask -> IRQ
   acceptance -> firmware W1C acknowledgement -> key-release/repress. Direct
   and matrix keys need separate checks. Existing W1C fix is e4c897e; user now
   observes wake behavior, but no firmware-consumption trace exists yet.
5. If firmware acknowledges the event but navigation does not draw, inspect
   scheduler/process state and window/input server startup from the replay.
   Attribute waits to a concrete server/request rather than changing the LCD
   or interpreting an N-Gage image as a reset. The long simulator has not been
   demonstrated to reach this same screensaver state; do not call a replay
   reproduction until that observable state matches.

This is a documented next investigation, not a new keypad/UI fix. Main frozen
long run and source images remain untouched. Memory build requested separately.
