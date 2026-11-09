# Firmware-driven display bring-up

## 2026-11-09: post-logo instruction sampling

An isolated2B→2.05B replay of the same frozen model shows recurring NOS deferred
callbacks (514A18D4), mailbox scans (514A10CC,26objects ×3kinds) and NOS timers,
with normal returns and kernel/GENIO IRQ handling. This is real repeated service
work, not a single self-branch. No LCD polling is observed. Unique trace PCs still
increase through the50M sample; no permanent global deadlock is established.
MTC state3, SIM state1 and zero registered NOS channels persist in the cache-aware
view. These are leads for startup-readiness tracing, not a demonstrated cause.
The sample is only~0.64nominal phone seconds. See latest status and
[evidence](evidence/post-logo-execution-2026-11-09.json) for counts and limitations.

## 2026-11-09: current service-loader profile reaches Nokia at2B

Unmodified firmware from the actual service-loader DDR export, copied hardware
C: and erased PMM reaches Nokia before1.99B in the frozen dd61fbd8e9de2534 model.
The permanent2B pair in hardware-service-boot-12b is preserved; an exact-binary
zero-cycle restore produces byte-identical CPU/host files. Actual scanout was
visually inspected at build/sim/screens/hardware-service-post-checksum-2b/scanout.png.
At2B:36689LCDwords,display_on/frame_complete1,unsupported1,12knownfetch faults,
zero datafaults. This establishes post-checksum Nokia, not subsequent UI boot.
Original12B run continues independently; latest hardware failure at50300B06
has not been reproduced here. See status.md for request/error/MMU evidence.

2026-11-07: [reached-command evidence and decoder limits](lcd-command-evidence.md) now records the fresh 125-write HDL fixture, stock `lcd.ldd` CA/CC table verification, explicit full-window parameter capture and unknown context. Partial-window rendering remains unsupported; the frozen long run is unaffected by this new build.

## 2026-11-06: stock-firmware Nokia logo reached in cold HDL boot

**Observed success:** `logo-normal-2000m` completed from reset at 2,000,000,000 cycles, PC `514A112C`, in 1,945.12 seconds (~32.4 minutes). Fresh framebuffer and actual scanout both visibly show the blue **NOKIA** logo on white. This is executed stock firmware writing the modeled HDL display; no image was injected and no firmware/guest-RAM patches were used. The run has 36,689 LCD words, frame_complete=1, display_on=1, the same 18 known speculative fetch faults and **zero data faults**. Normal power-key reset profile, no SIM/ATR, erased PMM, existing C: source and modeled DDR/SDRAM backing are recorded in the run manifest. Original inputs passed the runner's post-run hash checks.

PNG evidence: `build/sim/screens/logo-normal-2000m/framebuffer.png` and `scanout.png`. Framebuffer binary SHA-256 `aa346d99a4db8515e4e7500c93d58ea329dee8c94cea543a26efed120b979737`; PNG `b15a3e464a03347bc02d591964dacce5b8ae0326b775f4b4c5fdd6fe0d1694ab`. Permanent paired 1B and 2B checkpoints retained. Strict same-model restore to 2,001,000,000 cycles (`logo-normal-resume-2001m`) passes, zero new faults, byte-identical framebuffer and scanout hashes. Checkpoint/provenance hashes recorded in `scratch/logo-bringup/nokia-logo-evidence.json`.

The logo objective is achieved under the staged model. **Milestone 7.5 remains open for LCD protocol/keypad work:** unsupported=1 persists and appears as the deliberate red top strip in scanout. Window endpoint/odd-start semantics and physical panel behavior are unverified; do not suppress diagnostics or claim full Symbian/board validation. Next: replay near display activity with bounded command diagnostics, resolve reached unsupported commands and window semantics against stock firmware and the pinned Nortido reference, then test keypad behavior. No long simulation is currently running; both runs completed successfully.


## 2026-11-06 reference update

The [Nortido hybrid review](nortido-hybrid-reference.md#lcd-concrete-leads-for-milestone-75) supplies concrete `09240003` packing and column-offset leads. A retained local firmware trace matches `0B100002` for command `15`, but command `75` writes `0D000000` whereas its host clear helper uses `0CF00000`. Resolve endpoint and trailing-word semantics in milestone 7.5; its RTL ignores ends and odd starts, and its host-injected black frame is not guest rendering evidence.

**Historical early-2026-11-06 follow-up (superseded by the result above):** the older frontiers below are historical. Experimental HDL LCD/DMA/framebuffer and scanout now exist, but the latest full-core firmware smoke is only 5M cycles with no pixels. The next task is [milestone 7.5: new firmware-to-Nokia-logo run and unknown LCD command investigation](mister-implementation-plan.md#75-run-the-hdl-phone-to-the-nokia-logo-and-resolve-reached-lcd-commands). Resolve reached command/parameter framing using N-Gage traces and named references; distinguish fresh HDL output from retained-frame replay.

Goal: let original N-Gage firmware execute its startup path and write the LCD;
do not substitute a host-rendered logo for a firmware-driven boot. The historical sections below predate the experimental HDL LCD/video implementation.

2026-10-28 checkpoint continuations after explicit GPIO/PUP hypotheses reached
a `VARIANT` 0x00010013 diagnostic, not a logo. The only supported screen is
still the white clear: `build/sim/screens/boot-checkpoint-gpio206-extra/screen.png`.
The fixed-cache V15 comparison completed at cycle 725,795,188 on the same
VARIANT diagnostic and captured only the white clear at
`build/sim/screens/boot-v15-gpio-experiment/screen.png`. See `status.md` for
provenance and assumptions. The checkpoint continuation used the cache-disabled CPU.

The saved latency-0 firmware trace has an LCD `0x5c` command followed by header
`0x8924d67f` and 18,304 data writes of `0xffffffff` (36,608 16-bit values,
176 × 208), then command `0xaf`. This supports a full-screen white clear and
display-on interpretation; pixel packing, exact LCD semantics, color order and
timing need hardware evidence. The trace contains no firmware-drawn logo yet.
The NEM-4 `SplashScreen.mbm` occurs once in the original `SYM.ROM` at file offset
`0x9718d0`, also present in the unpacked Z: tree. Its presence does not establish
that the firmware has reached its splash application or displayed it.

A new bounded stage lives in `scratch/boot-display-stage/`. It uses the prior
explicit digest metadata probe (`both`), reconstructed extension, ADC 6=512,
assumed 18,200,000-cycle timer IRQ and explicit UEM 0x3f status value 0. This
status is a chosen experiment, not a measured phone value. Timer flag readback
and cleanup writes are assumptions based on the firmware IRQ handler. Unknowns
outside those narrow conditions remain unmodeled; board-model unit tests pass.

The active run is `build/sim/runs/boot-display-power0-timer18200000/`, with
source/image/binary/input hashes in `provenance.json`. Check `result.json` and
active simulator before duplicating. The raw command is in the thread; output
is a compact bus trace and retirement tail. **Known trace limitation:** the
current compact logger does not include `assumed_uem_power_status` and
`assumed_timer_status` device reads in `bus.tsv`; the explicit status appears
in result/provenance and the modeled state is covered by unit tests. Add those
log categories in a separately versioned build before a follow-up run; do not
edit sources while claiming the active binary has those changed hashes.

If the run reaches unknown access, identify the executing PC and corresponding
firmware routine, and model only explicit/reasoned hypotheses. Inspect all later
LCD writes and preserve raw bus trace. Before hardware display claims, implement
and test a simulated LCD decoder/framebuffer and actual MiSTer video path, and
verify that the non-white pixels were written by executed firmware.

`sim/analyze_lcd_trace.py BUS --output OUTPUT.json` groups observed LCD headers,
data words and command words without guessing their pixel format. Its baseline
summary is `build/sim/lcd-baseline-summary.json`; it verifies one 18,304-word
uniform transfer and a raw `0xaf` command. Use it on subsequent completed bus
traces to identify firmware-generated nonuniform transfers.

The first power-status-0 run completed at cycle 137,837,646 on the unmodeled
initial UEM `0x36` read (`0x0c150424`), after taking the timer IRQ and writing
its cleanup and acknowledgement sequence. The trace also shows firmware writes
UEM `0x35=0x0200` before the next read. It still has only the original LCD clear.
A second isolated stage `scratch/boot-display-stage-v2/` accepts an explicitly
supplied initial UEM `0x36` value, preserves later write/read behavior, and logs
both assumed status reads and timer status in compact traces. Its unit tests
pass. The follow-up experiment assumes initial `0x36=0` as well as status 0x3f=0;
these are hypotheses, not measurements. Its active output and provenance are in
`build/sim/runs/boot-display-power0-status36-0-timer18200000/`.

A local TriX routine for another Nokia LCD, `scratch/references/TriX/projects/
shared/lcd/lcd.c`, uses command `0x15` for columns, `0x75` for rows and `0x5c`
for memory write, then emits three bytes for two 12-bit pixels. The NEM-4 trace
uses those command numbers, and its clear has exactly 18,304 data writes for
36,608 pixels. The clear header's low value `0xd67f` is 54,911, one less than
18,304 × 3 bytes. These are consistent with two packed 12-bit pixels per data
word and a byte-count-minus-one header, but do not establish the N-Gage's byte
order, orientation, framing, controller identity or non-white color decoding.

The `status36=0` run completed at cycle 137,837,941 on physical halfword write
`0x0c150100=0x8000`, issued by ROM PC `0x2f44`. It also reveals a flaw in that
stage's UEM assumptions: firmware writes register `0x35=0x200`, then reads it as
status, and a blind write-echo gives 0x200; disassembly shows this leads to a
shutdown loop at `0x2f74` when no other condition intervenes. The actual read
semantics/value are not established. In `scratch/boot-display-stage-v3/`, the
exact IRQ halfword write is an opt-in sink, `0x35` read is a separate explicit
input (never an echo), and status values `0x3f=0`, `0x36=0`, `0x35=0x10` are
assumptions. Unit checks pass, including directional `0x35` read. The active run
is `build/sim/runs/boot-display-power0-status36-0-status35-10/` with complete
source, binary, input and container hashes in `provenance.json`.

The timer IRQ stage was integrated into maintained `sim/`, and `make sim-compat`
passed all diagnostics, including IRQ entry, acknowledgement, restored CPSR,
terminal value, and masked IRQ at latencies 0 and 3. Twenty-one oracle tests
pass; comparator rejects mismatched IRQ assumptions. Future maintained runs
record a build manifest and binary hash; a 1,000-cycle timeout verified that
metadata path. Staged UEM status hypotheses remain separate from maintained sim.

The v3 firmware run completed at cycle **423,877,595** after passing both digest
checks under the derived-image assumptions and entering Symbian kernel code. It
stopped on physical `0x0c0047f0` write `0x4e52454b` (`KERN` in little endian).
Kernel code at `0x50324240` writes words at offsets `0x47f0`, `0x47f4`, `0x47f8`
through a helper targeting `0x58000000`, and subsequently touches `0x428e`,
`0x120004` and `0x150000`. The backing of these locations is not verified;
currently only the earlier flash-routine scratch range is modeled. Do not model that write yet: it occurs during a kernel fault path, not
ordinary initialization. Diagnose the earlier data abort first. `lcd-summary.json` confirms only the
white clear; no splash has been sent. This is exploratory kernel entry, not a
full boot or validated phone hardware.

The retired trace reveals an earlier architectural data abort: at virtual
`0x503313c8`, `ldm r5, {r5, lr}` uses base `0x400000c4`; vector `0x10`
then leads to a `KERN-EXEC` fault with code 3. CP15 fault status is `0x5`
(section translation fault) and recorded fault address is `0xe59ff028`,
which does not equal the displayed base; the explanation is not established.
The local 6600 reference describes `0x400000c4/c8/cc/d0` as superpage handoff
pointers, but its assumptions are for another device and cannot establish this
N-Gage mapping. A focused `ldm r5,{r5,lr}` diagnostic with `0xe59ff028` as the
first loaded value passes on ZAP with and without MMU at latencies 0 and 3.
That rules out a simple base-in-list failure in these test configurations,
not all cache/MMU cases. Further investigate actual faulting effective address,
page-table state and firmware initialization before adding memory. The kernel's
later `KERN` write is diagnostic output. `make sim-compat` passes with both new
regressions; the native reference cannot inject the external IRQ yet.

The previously retained *pre-MMU* RAM snapshot shows L1 descriptor at
`0x0a075000 = 0x0a073431` and its first L2 entry at `0x0a073400 = 0x0a07055e`.
Under that snapshot, `0x400000c4` maps to `0x0a0700c4`, but the kernel may
change these tables later. A new `ldm_base_smallpage` diagnostic uses that same
small-page flag pattern with caches enabled and passes at memory latency 0 and
3; it does not reproduce the complete firmware state.

A single v4 reproduction is running in `build/sim/runs/boot-display-kernel-abort-trace/`
(session 59581 at launch). Its simulated hardware and explicit UEM/timer inputs
are unchanged from v3, but it retains 32,768 recent memory events, 8,192 recent
instructions and 4,096 branches. Source/binary/input hashes are in its
`provenance.json`. On completion, check for the same data abort and inspect
memory/page-table activity around cycle 423,873,737 before changing the board
model. Its limit is 450 million cycles; check process/result before rerunning.

A further `ldm_base_undmode` check adds the kernel's UND mode to the cacheable
small-page test and passes at both latencies. Its first test version incorrectly
checked LR after switching to SVC (LR is banked); the corrected test checks LR
before switching and the full compatibility suite passes. This narrows the
reproduction, but does not rule out firmware-specific page-table or pipeline
state.

A standalone unmapped `0xe59ff028` load reproducer correctly reports the fault
address. It returns fault status `0x2` where a section translation fault `0x5`
was expected; both single-register and multi-register loads show it at latencies
0 and 3. This status discrepancy needs independent investigation, including
fault timing and diagnostic setup, before attributing it to ZAP. Reproducers
`sim/programs/{ldr,ldm}_fault_status_probe.S` intentionally fail with code
`0x33`; their retained results are under `build/sim/runs/*_fault_status_probe-*`.
The passing `ldm_fault_far` regression checks only the fault address, not status.
The full `make sim-compat` suite passes after keeping the status probes separate.

Follow-up isolates the FSR result further: reading `c5` immediately on entry
returns the expected 0x5, as does reading FAR then FSR immediately; both pass
at latency 0 and 3. The original reproducer reads FAR, executes a literal load
and comparison, then reads FSR as 0x2. Thus the 0x2 is time/order dependent,
not evidence that the original abort initially generated the wrong status.
Determine why FSR changes (including speculative faults and harness behavior)
before attributing this to RTL; `ldm_fault_status_first` and
`ldm_fault_status_immediate` are passing checks, while `*_status_probe` preserve
the later-read observation.

### CPU fault-register fix (patch 0007)

The later-read discrepancy was isolated: in `zap_dcache_fsm.sv` state
`UNCACHEABLE`, every bus acknowledgement set `o_fsr` to `TERMINAL_EXCEPTION`
(2), even if `i_wb_err` was false. CP15 monitors nonzero FSR and therefore
replaced the real fault status with 2 and FAR with 0 after a successful
uncached data read. Local patch `0007-preserve-fault-status-on-ack.patch`
gates this internal status on an actual bus error. The unmodified vendored
source is untouched. The six-patch control fails the focused FAR/FSR persistence
check at latencies 0 and 3, retained under
`build/sim/runs/fault-status-six-patch-latency{0,3}/`; seven-patch checks pass
at both timings. Full `make sim-compat` passes, log
`build/sim/compat-fault-status-fix.log`. The long v4 firmware trace still runs
with the six-patch CPU, preserving its before-fix provenance; it cannot validate
patch 0007. The exact root of the original kernel abort is still unproven.
Rerun the relevant firmware scenario with patch 0007 only after the v4 run
finishes and after considering the retained fault trace.

Patch 0007 also passes `make sim-rtl-lint sim-upstream-patched`: synthesis-path
Verilator lint and upstream ARM32/Thumb seed-1 tests. Log:
`build/sim/fault-status-upstream-lint.log`.

The v4 enlarged trace completed at the same cycle and diagnostic write as v3.
At cycles 423,873,741/743 it reads page-table entries `0x0a073431` and
`0x0a07055e`, confirming that the live mapping of virtual `0x400000c4` still
points into physical `0x0a070000`. Its ensuing cache fill reads superpage words
`[c4]=4`, `[c8]=5`, `[cc]=0x05040001`; the next recorded ROM fill comes from
physical `0x00321000` with vector instruction `0xe59ff028`, followed by a page
walk at `0x0a077964` (the L1 slot for address `0xe59ff028`) returning zero.
This supports, but does not yet prove, an erroneous pointer through the low
vector area. The firmware trace reports the data-abort return PC as
`0x503313c8`; speculative memory transactions need to be distinguished from
retired accesses. A targeted UND-mode LDM test with first words 4 and 5 passes
at both latencies; do not conclude that LDM itself is broken.

A v5 run with patch 0007 is active in
`build/sim/runs/boot-display-kernel-fault-fix/` (session 66654 at launch).
It has the same UEM/ADC/IRQ and digest-probe assumptions as v4 and records
extended history. `provenance.json` includes hashes of all seven CPU patches,
patched RTL, model, binary, inputs and simulator image. Compare its result and
fault-register values with v4 before modifying the kernel handoff or memories.

### Cold-cache multi-register load reproducer

`sim/programs/ldm_base_coldcache.S` reproduces the kernel fault pattern in a
short standalone program. It writes superpage words 4 and 5 through an
uncached alias, then executes `ldm r5,{r5,lr}` through a **cold cacheable small
page** in UND mode. Both memory latencies fail with completion `0x21` under the
seven-patch CPU. The cache fill correctly fetches physical words 4 and 5, but
full simulator trace shows the LDM micro-ops restart: the first pass copies
`0x400000c4` as base and starts the load, then a second pass copies updated
`r5=4` as base and reads low virtual addresses 4 and 8. This matches the
firmware's superpage and low-vector accesses. Warm-cache, non-MMU and basic
small-page variants pass. Saved results:
`build/sim/runs/ldm_base_coldcache-latency{0,3}/`.

The cause appears to involve interaction between cache-miss replay and the
multi-op instruction; do not assume the exact fix yet. `zap_dcache_fsm.sv`
uses nonblocking loads and `o_err2` to replay accesses, while LDM is expanded
in `zap_predecode_uop_sequencer.sv`. An independent Sol review is worthwhile.
Any fix must cover abort semantics and other multi-register operations; do not
simply reorder registers without proving architectural behavior. The known
failing probe remains outside `make sim-compat` until fixed. A seven-patch
firmware run is already active, but patch 0007 does not address this distinct
cold-cache reproducer. Preserve it for comparison.

Control `ldm_cold_base_not_loaded.S` uses the same cold line but loads r4 and
LR instead of the base register r5; it passes at both latencies. Simulator log
for the failure shows the sequencer's initial `MOV DMY0,r5`, an LDR that misses,
and then a second `MOV DMY0,r5` after the asynchronous result changed r5 from
`0x400000c4` to 4. This strongly localizes the fault to restart of a partially
committed multi-op instruction; it does not establish a safe fix.

Isolated `scratch/blocking-cache-probe/` experiments with stalling the cache
miss instead of acknowledging/replaying it. The cold-cache LDM diagnostic passes
with latency 0, but at latency 3 it repeatedly fetches the same cache line and
times out at 500,000 cycles. The warm-cache and smoke controls pass both timings.
Do not use this prototype as a fix; its latency-dependent stall remains
unexplained. Results: `build/sim/runs/blocking-cache-*`.

A follow-up `scratch/blocking-cache-probe-v2/` allowed cache tag/data writes
while held. It still times out on cold LDM at latency 3 and additionally fails
`cache_load_widths` at both latencies. This rejects that simple cache-write-gate
hypothesis as a safe fix. Keep both prototypes out of maintained RTL.

Additional cold-cache control `ldm_cold_base_last.S` uses `{r4,r5}` with base
r5, so the base is loaded last; it passes both latencies. The failing case loads
base first and then LR. This supports the partial-commit/restart explanation.

The same cold-cache diagnostic fails with completion `0x21` on the pinned,
unmodified upstream ZAP CPU at both memory latencies. Saved controls:
`build/sim/runs/unmodified-ldm_base_coldcache-upstream-latency{0,3}/`.
This establishes the failure predates the seven local patches; it does not
establish how to fix it.

Exploratory bypass: `scratch/no-data-cache-probe/` forces the data-cache input
disabled in the simulation-only patched CPU, without changing CP15 readback.
This is an architectural/timing discrepancy, **not a cache fix or phone
simulation**. The cold LDM, cache-load-width, MMU/FCSE and smoke diagnostics
pass at latencies 0 and 3. A separate firmware run is active under
`build/sim/runs/boot-display-no-data-cache/` (session 79542 at launch), with
seven patches, the same explicit UEM/ADC/digest assumptions, one-billion-cycle
limit and complete source/ROM/image hashes in `provenance.json`. It can help
identify the next boot frontier while the real cache bug remains unresolved;
compare findings cautiously because the data cache is forced off. The v5 normal
cache run continues separately in `boot-display-kernel-fault-fix/`.

The seven-patch normal-cache v5 run completed at exactly the same cycle and
kernel diagnostic write as v4 (423,877,595, `0x0c0047f0`), with CP15 reporting
FAR `0xe59ff028`, FSR `0x5`. Thus patch 0007 fixes the independent fault-state
clobber but does not prevent the kernel failure, consistent with the separate
cold-cache LDM reproducer. LCD transport still has 75 headers and the same
18,353 data words; no new drawing. The forced-off-data-cache run remains active.

The forced-off D-cache firmware run completed at cycle 451,437,317, passing the
prior kernel fault and reaching a kernel read of timer control `0x0c120a04`
after writing 2 twice. LCD output remains the white clear. It stopped because
control readback was not modeled. `scratch/no-data-cache-stage-v2/` adds an
explicit, narrow hypothesis: after the startup IRQ, reading that exact word
returns 2 only if the last control write was 2. Its board tests pass. A new run
using this hypothesis is active in
`build/sim/runs/boot-display-no-data-cache-timer-readback/` (session 41019 at
launch). Provenance records the forced-off cache, timer hypothesis, inputs,
source hashes and simulator image. This remains exploratory, not verified phone
hardware; inspect results and next access before adding any further behavior.

Independent Sol review identified the cache `FETCH_SINGLE` retry path and
writeback pipeline clear as the likely restart mechanism. A bounded instrumented
run in `scratch/ldm-replay-cycle-trace/` confirms it at latency 0: t=173585
first load `0x400000c4` is acknowledged; t=173587 the second access
`0x400000c8` returns `err2` while r5 is locked; t=173589 writeback clears the
pipeline; t=173605 the background fill writes r5=4. Replay then uses r5=4.
Trace: `build/sim/runs/ldm-replay-cycle-trace/simulator.log`, `REPLAY` records.
The instrumented RTL is scratch-only. Sol recommends preserving instruction
commit/replay and abort semantics, not suppressing the clear or reordering
registers without proof. The blocking prototypes remain invalid.

## Screen captures and latest run

Completed run `boot-display-no-data-cache-timer-readback` stopped at cycle
451,437,796 on kernel timer reload write `0x0c120a18=0x000632ea`; this follows
successful assumed control readback. The LCD still emitted only the earlier
uniform clear. Its first trace-derived screen is
`build/sim/screens/boot-display-no-data-cache-timer-readback/screen.png`;
`screen.json` records trace, capture-tool hashes and assumptions. The 176×208
all-white rendering interprets all-ones data as white; controller inversion,
orientation, packing and the physical LCD are not verified. It is not a
firmware-generated logo, an emulator framebuffer or MiSTer video output.

Run `python3 sim/capture_lcd_screen.py <completed-run>/bus.tsv --output
build/sim/screens/<run-name>` to capture the currently recognized clear. The
capture refuses incomplete results, nonuniform/unknown memory transfers,
additional memory-write commands and later unknown commands; it does not decode
arbitrary LCD images. `python3 sim/test_capture_lcd_screen.py` covers these
boundaries. Do not use it to claim that a future unrecognized display is white.

The next run is `build/sim/runs/boot-display-no-data-cache-timer-reload/`
(session 30552 at launch). It captures the exact observed kernel reload
`0x632ea` after control=2 as a written latch only: no second timer event or
periodic IRQ is fabricated. The wrapper `scratch/no-data-cache-stage-v3/run.py`
automatically writes a screen capture under
`build/sim/screens/boot-display-no-data-cache-timer-reload/` after a completed
run, or explicitly reports that the later display is unknown. It does not create
live screenshots while running. Inspect `result.json`, `simulator.log`, and
screen JSON or capture failure before interpreting output. See [TODO.md](TODO.md)
for every unresolved shortcut.

## Resumable firmware experiment

`boot-display-no-data-cache-timer-reload` completed at cycle 452,153,686 on
CBUS write command `0x27` (physical `0x0c150420`, upper halfword), after
kernel timer setup. The screen capture remains the same white clear. Repeating
full startup for each newly observed access is expensive.

`scratch/checkpoint-probe/` adds experimental Verilator `--savable` snapshots
of CPU and context plus board RAM, timer, UEM/CBUS, flash, latches, and host bus
state. `test_checkpoint.py` verifies restored final state and ordered instruction,
bus and CP15 traces for smoke and IRQ tests at memory latency 0 and 3. An
additional CBUS fixture saves before unknown `0x27`, reproduces the unknown stop,
then resumes with that single explicit write allowed and reaches the intended
terminal write. Scenario input signature includes original ROM/extension,
profile, timer, ADC, UEM and latency; the new opt-in CBUS policy is the only
intentional change across restore. Checkpoints are local, binary-specific and
ABI-specific; keep source/binary hashes and never claim hardware save-state.

`scratch/checkpoint-probe/run_firmware.py` is active as session 56299. It will
run the same no-D-cache experiment, save at cycle 451,430,000 to
`build/sim/checkpoints/ngage-before-cbus27.{cpu,host}`, verify input hashes,
check it reaches the original `0x27` frontier, then resume with only UEM write
`0x27` explicitly allowed. It compares every resumed bus event with the baseline
up to that command; if any differs it reports an error rather than claiming
success. Result folders are `build/sim/runs/boot-checkpoint-initial/` and
`build/sim/runs/boot-checkpoint-cbus27/`. The latter combines the original LCD
prefix with resumed bus events and attempts a conservative screen capture under
`build/sim/screens/boot-checkpoint-cbus27/`. Unknown later display writes result
in no fabricated PNG. This remains an experimental forced-off-cache scenario.

Next: inspect the wrapper result, all provenance, checkpoint-prefix comparison
and any UEM/LCD frontier. If a new peripheral behavior is needed, resume the same
checkpoint with a separately documented, narrowly bounded rule. Verify that the
original prefix still matches and capture display data; do not repeat all
firmware hashing unless inputs, CPU state or pre-checkpoint model changes.

Checkpoint validation now includes 18 save points across smoke and IRQ tests,
at both latencies, including around the scheduled interrupt. Each restored
instruction/bus/CP15 suffix and final CPU/board report matches its uninterrupted
control. A changed firmware image is rejected. These focused tests do not yet
prove every possible asynchronous peripheral configuration.

`make sim-ldm-replay` runs the cold-cache CPU regression at both latencies and
returns nonzero while the bug remains. The current seven-patch core reports
`GAP` at both latencies. The checkpoint CBUS-write option separately passes
tests rejecting reads of register 0x27 and writes to neighboring registers.

A separate `scratch/checkpoint-probe-v2/` test rebuilt identical HDL with a
controlled board-model change (a second explicit CBUS-write option), then
restored the first binary's synthetic checkpoint. Result, cycle count and all
instruction, bus and CP15 suffixes matched the original continuation exactly.
This proves reuse across that particular compatible board-model change, not
arbitrary changes or CPU RTL changes; checkpoint format/version and scenario
signature must still match and CPU/source provenance must be audited.

## Checkpoint continuations after resume

The firmware checkpoint completed and its resumed bus trace matched the
baseline through UEM command 0x27. Allowing that exact write reached halfword
write `0x0c150012=0x8000` at cycle 452,212,093. The separately tested
`scratch/checkpoint-next/` models it only as a write sink after the observed
IRQ/UEM sequence. Its continuation matched the prior trace to the frontier and
reached interrupt-controller write `0x0c120108=0x02000000` at 452,212,394.
`scratch/checkpoint-next-v2/` accepts only that additional write after the UIF
write; it does not implement interrupt bit 25. The next continuation matched
its predecessor and requested the previously unknown lower halfword of
`0x0c150210` at 452,256,441. `scratch/checkpoint-next-v3/` assumes this one
reset value is zero and preserves write/read behavior; the run then requested
upper halfword `0x0c15021a`. `scratch/checkpoint-next-v4/` separately assumes
that value is zero and reached `0x0c150216` at 452,256,719. All new values and
writes are hypotheses, not verified hardware. The four board-model unit suites
pass and each continuation verifies the exact preceding bus prefix. Screen
captures under `build/sim/screens/boot-checkpoint-*` remain the assumed white
clear; no logo has been written.

Resumed outputs: `build/sim/runs/boot-checkpoint-{cbus27,uif8000,icu25,gpio-low,gpio21a}/`.
A first `icu25` comparison script accidentally referenced its own output and
failed after simulation; preserved as `boot-checkpoint-icu25-comparison-error`.
The path was corrected and the rerun matched. New stage-specific guard flags
are not serialized by the original snapshot version; later-stage code rejects
saving after the UIF event. The original pre-UEM checkpoint remains unchanged.

Further checkpoint continuations assumed GPIO `0x0c150216=0` and accepted only
`0x0c150102=0x0010` after the preceding IRQ/GPIO sequence; both have tests and
exact preceding-prefix comparisons. The next unknown CBUS command `0x82` is a
write to a different encoded device/register, not the earlier UEM `0x27`.
`scratch/checkpoint-next-v7/` permits this one command only, rejects a `0x182`
read command and other values, and preserves its provenance. Firmware writes
payload `0xffff`, then asks to read the same CBUS register with command `0x182`
at cycle 452,261,280. Its read semantics are unknown. All screen captures
remain the assumed white clear. The checkpoint allows each iteration to finish
in seconds. Next decision: separately test explicit readback of the previous
write, not a default device behavior; document any nonphysical assumption.

The explicit CBUS82 readback returned the earlier write `0xffff`; the next
unwritten device register `0x80` was probed with 0, leading to a `CBus` fault
(reason `0x10019`). Firmware checks `(value & 0xff00) == 0x0400`, so a separate
`0x0400` input hypothesis passed that check. With explicit initial zero and
readback for CBUS `0x8d`, firmware exercised its read/modify/write sequence and
reached ICU bank write `0x0c120148=0x4000` (interrupt 46). This is a write sink,
not an implemented interrupt source. It then read power-unit halfword
`0x0c14f00a`; a separate zero hypothesis allowed continuation to an unknown
word read `0x0c120c14` at cycle 452,338,785. Each stage was independently
unit-tested, restored from the original checkpoint, verified its entire prior
bus prefix, and captured only the white clear. Latest stage:
`scratch/checkpoint-next-v12/`, output
`build/sim/runs/boot-checkpoint-pupf00a/`, image
`build/sim/screens/boot-checkpoint-pupf00a/screen.png`.

These steps expose firmware dependencies; they do not validate any input or
prove working interrupts, video, or authentic boot. The constant 0x0400 is
inferred from firmware's check and is not a measured register value.

`scratch/checkpoint-next-v13/` separately assumes system-control word
`0x0c120c14` resets to zero; it supports only observed full-word RMW after the
prior setup and is tested. Continuation matches the prior prefix and reaches an
adjacent unknown word `0x0c120c10` at cycle 452,338,892. No nonwhite LCD pixels
were written. The growing list of reset hypotheses must be replaced with a real
hardware model; the separate normal-cache CPU replay defect remains unresolved.


### Checkpoint continuation: explicit register probes

`scratch/checkpoint-register-probe/` adds individually configured, exact-address
and exact-width experimental latches, with input values and unverified status in
`result.json` and `provenance.json`. It refuses modeled-latch overlaps and
post-probe snapshot creation; the original pre-CBUS checkpoint is unchanged.
Board profile tests passed for intel8, amd8 and amd16 plus boundary tests.

- `boot-checkpoint-sysc0c10`: permit full-word writes to `0x0c120c10`; firmware
  writes `0x00040000` then `0x00000002`, next writes `0x00040000` to
  `0x0c120c0c` at cycle 452,339,549.
- `boot-checkpoint-sysc0c0c`: permit that full-word register, next reads low
  halfword `0x0c14f000` at cycle 452,340,111.
- `boot-checkpoint-pupf000`: assume that halfword reads zero and latches writes;
  firmware writes `0x0040`, then requests upper-halfword write `0x0180` to
  `0x0c150206` at cycle 452,340,325. Existing bus latch at `0x0c150204` allows
  only the low halfword and correctly rejects this width. Determine GPIO register
  semantics and add a separate explicit, bounded hypothesis if continuing.

Each continuation replays from the preserved snapshot and verifies the preceding
bus prefix. Images under `build/sim/screens/boot-checkpoint-*` still show the
assumed white clear. The probe values, device side effects, synthetic firmware
tail, forced-off D-cache and other prior assumptions are not hardware evidence.


### GPIO 0x0c150206 continuation

The local emulator references do not identify the NEM-4 register function for
this access. `scratch/checkpoint-gpio206/` adds an explicit write sink for only
the observed high-halfword write `0x0180` (aligned address `0x0c150204`, byte
select `0xc`); reads and different values remain unknown, and the existing
low-halfword latch is preserved. Boundary tests pass.
`scratch/checkpoint-gpio206/resume-gpio206.py` restores the preserved checkpoint
and verifies the previous trace prefix. Firmware proceeds to a low-halfword read
of `0x0c150214` at cycle 452,340,421; the existing model permits only the
separately assumed upper halfword `0x0c150216`. Outputs and provenance are in
`build/sim/runs/boot-checkpoint-gpio206/`; the screen remains the assumed white
clear. This write sink does not establish GPIO side effects.

## 2026-11-09: first171M cycles attributed to inflated ROM busy wait

User challenged the pre-logo delay. Independent1M-cycle observer, built from
current HDL with same service-loader-derived backing and78M parameter, did not
stop/modify the long12B run. Result zero data faults/12known fetch faults.
At164125 retired PC63cc has r0=100000. Inner6150 entries164235,165948,167661,
169374,171087,172800,174513,176226: exactly1713 clocks apart, r0=8 and
r5=100000; r4 advances0..7. Profiles through900k confirm r5 stays100000 while
r4 rises20→429. This is forward progress through a counted delay, not polling.

ROM6150 resets r1, increments it eight times, with NOPs/compare/branch, then
returns;63cc repeats that call100000 times. Around79 architectural instructions
per outer iteration =>21.7 clocks/instruction measured,171.3M clocks total.
Long run's next LCD control writes171466289/171466893 and header171467529
land just after the predicted end. At78M171.3M represents2.20 seconds; host
simulation steps are still100MHz so recorded simulation timestamps differ.
This establishes inflated busy-wait cost, NOT a necessary two-second LCD delay.

Static reset-toggle helpers630c and62d0 write GPIO-related halfwords0c150204
and0c150202 and each tail-call63cc with100000 from literal186a0. Similar reset
sequences can therefore incur this cost more than once. Exact subsequent
caller/coverage beyond1M needs additional observation; don't claim all200M
are already individually traced. Boot-ROM slow uncached fetch/pipeline costs
are the next performance investigation; expected real-phone latency and exact
calibration units remain unverified. No firmware waits skipped or ROM patched.

Files: scratch/early-boot-delay/{boot-disassembly.txt,summary.json,run.log};
full observer run under build/sim/runs/early-boot-delay-trace-1m/. Testbench
NGAGE_EARLY_BOOT_TRACE prints bounded first8 inner entries and100k-cycle
profiles; runner --early-boot-trace builds a separate source identity.
Long run must continue with frozen executable via --use-saved-build if resumed.

## 2026-11-09: JTFRAME LARGE cache suitable for DDR — isolated proof

User requested JTFRAME reuse and low BRAM use, preserving live12B sim. Reviewed
jtframe_romrq_lcache (CACHE_LARGE branch), rom_2slots/ramslot_ctrl and RAMs.
LARGE lines are16/32/64 BITS, not bytes. Choose1KiB CACHE_SIZE(minimum),DW32,
BURSTLEN64,TAG_RAM1:128 direct-mapped8-byte lines,8192data bits+1920tag bits
at24-bit halfword address width; valid128FF and fill64FF. Expected few M10Ks;
actual primitive packing/resources must be measured. TAG_RAM avoids async tag
array. Existing generic Jotego RAMs need explicit CycloneV mapping review at
integration to preserve project's BRAM contract.

SDRAM wiring is req→slot arbitration/controller; slot_sel becomes we (not a
CPU write), dst marks first16-bit fill beat, din_ok/rdy marks final. A DDR shim
can issue ONE aligned64-bit request and serialize its response into four16-bit
fill beats with this exact handshake. Current DDRAM_BURSTCNT1 already returns
that8-byte line. No multi-beat DDR burst required and no need to discard the
other32-bit half. Cache max line is8bytes;32-byte lines would require modifying
the imported cache. Existing adapter currently truncates64→32 so integration
must expose the full beat, not put cache after the truncation. Preserve shared
DDR arbitration and held requests; latch CPU request through synchronous tag
lookup so stale prior data_ok cannot acknowledge a new address.

Unmodified LARGE and generic RAM copies tested in scratch/jtframe-ddr-cache/:
408 reads produce5 fills: two initial8-byte lines,100 loop repetitions all hits,
conflicting line/reload and clear/refill; DDR response delays1..7cycles; lane
order checked. Prototype uses abstract DDR response, not production adapter.
Only immutable ROM array reads may use it; status/ID/program commands bypass,
C:/PMM remain uncached; store raw bytes then existing address-specific decode.
Invalidate on firmware load/reload and drain/cancel late fills on reset/clear.
Full integration and reset/clear-in-flight tests remain next work, not claimed.
No phone RTL changed, no build/push; running frozen12B sim untouched. At310M
still12known fetch errors/zero data faults. Evidence/provenance/test.log beside
the scratch fixture. This proves interface feasibility, not speedup or104MHz.
