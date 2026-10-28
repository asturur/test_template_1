# Development checkpoint and resume guide

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
