# N-Gage boot: assumptions to replace

These are explicit diagnostic shortcuts, not verified phone behavior. Keep them
separately configurable; never describe a probe as authentic boot. See
[display-bringup.md](display-bringup.md), [firmware-integrity.md](firmware-integrity.md),
[flash-layout.md](flash-layout.md), and [uem-control-bus.md](uem-control-bus.md)
for evidence and reproducible traces.

## Fit and storage priorities (2026-11-11)

Keep the diagnostic screen, monitor, recorder and export until Symbian boots.
Actual PLL stays78 MHz; optimize RTL toward104 MHz without changing clocks.
See [ranked candidates](donor-resource-comparison.md#next-optimization-priorities).

- [x] Prototype donor-style MLAB ZAP register storage (0057); independent RF,
  operand and CP15 oracles pass. Preserve five read operands, banked registers,
  held/committed bypass, writer priority and collision ownership. Measure LABs
  and timing in the requested build; the old RF's~2,008 ALMs are a block cost,
  not promised savings. Functional tests pass; physical fit is still open.
- [ ] Compact DMA queue/worker BRAM. The four8x32 queued-payload banks are mostly
  empty; investigate narrow multiword rows and shared storage for suitable
  worker fields. Keep eight immutable channel snapshots, two workers and fast
  LCD; worker execution state is still mostly live registers, not these banks.
  Test start/program/stop/restart ordering, fetch collisions, busy peers,
  accepted-owner drain, reset, all channels/IRQs and native MMC lengths. Measure
  added launch clocks, FF staging, total LABs/M10Ks and setup/hold; preserve the
  130,685-clock LCD frame and avoid adding latency to every transfer beat.
- [ ] Investigate DMA's remaining768 live programming mirror bits. A RAM change
  must capture the original start-edge descriptor despite immediate rewrites,
  cancellation and other channels; measure launch latency before adoption.

## CPU and cache

- [ ] Fix ZAP cold-cache `LDM` replay when the base register is loaded before
  another register. `sim/programs/ldm_base_coldcache.S` fails on upstream and
  seven-patch CPU at memory latencies 0 and 3. A cache miss is acknowledged,
  the next LDM micro-op raises `err2`, writeback clears the pipeline, and the
  asynchronous fill writes the old base register before replay. Replayed LDM
  therefore uses the loaded value as its address. Sol review and signal trace:
  `build/sim/runs/ldm-replay-cycle-trace/simulator.log` (`REPLAY` lines).
  Design an instruction-level solution that preserves original base, partial
  completion and abort semantics; test LDM/STM, register list/base ordering,
  cache misses and hits, interrupts, aborts, and memory latency. The scratch
  blocking-cache prototypes are rejected: latency 3 repeatedly refills, and
  v2 also breaks load-width tests.
- [ ] Remove forced-off D-cache in `scratch/no-data-cache-probe/` after the
  CPU fix. It bypasses the bug for exploration while CP15 still reports cache
  enabled, so timing and architectural behavior differ from a phone. Validate
  real cache-enabled firmware against independent ARM/software reference.
- [ ] Verify patch 0007 on real firmware and hardware tests. Successful uncached
  ACK previously overwrote CP15 FSR/FAR with internal terminal status 2/0;
  the patch gates it on bus error and passes focused tests, upstream ARM/Thumb
  and lint. It does not fix the separate replay failure. Check real bus-error
  and abort paths, not just successful loads.

## Firmware and flash integrity

- [ ] Explain NEM-4 embedded core MD5 mismatch. Original core range hashes to
  `1784c17a6fd17b0841226546434db048`, stored digest is
  `2c09c86ff047484fdcc0e226f49c44a9`. FPGA and hashlib agree. Investigate dump
  format, extraction, runtime modifications, and obtain a verifiable original
  physical dump if possible; do not assume corruption. Two QD images also
  have static mismatches. Remove the `--digest-probe both` metadata rewrite
  once authentic inputs or verified transformations are available.
- [ ] Recover authentic extension bytes and layout. Current separate extension
  preserves 1,524 extracted file payloads but synthesizes metadata and padding;
  its own MD5 differs from embedded expectation. Reconcile with three 8-MiB
  chips, sector/bank mapping, commands, IDs and timing; verify device-specific
  bank addresses and flash contents rather than relying on emulator snapshots.
- [ ] Reconcile all three schematic AM29N643GT70MVAI chips with modeled
  CS1 0x257e versus CS0/CS2 0x227e, the boot-selected 16 MiB bank table,
  and the `VARIANT` 0x00010013 failure after flash classes 0,4,0. See
  `flash-layout.md` and the early trace in `variant-early-trace/`.
- [ ] Replace assumed flash IDs and narrow command/identify model with measured
  NEM-4 chip protocol, write/erase/status semantics, and proper persistent
  storage. The 3.4-MiB user allocation is not a raw physical flash offset.

## Timer, interrupt and phone inputs

- [ ] Replace one-shot timer assumption: current IRQ occurs 18,200,000 simulated
  CPU cycles after a startup reload, with one tick per CPU cycle. Real clock,
  prescaler, reload/count, IRQ mask/routing, acknowledgements, periodic events,
  and IRQ/FIQ priority remain unverified. Cross-check real phone/manuals or
  authoritative reference, test exception entry/return and interrupt races.
- [ ] Replace assumed timer status and control readbacks: after IRQ, model
  `0x0c120a08=1` and the stage-v2 `0x0c120a04=2` as observed-latch hypotheses.
  Latest kernel writes `0x000632ea` to `0x0c120a18`; the current
  diagnostic captures that write but does not rearm a timer or generate periodic
  interrupts. Implement actual counter,
  reload and read semantics rather than blindly accepting values. Keep unknowns
  bounded and compare kernel traces, including delayed memory.
- [ ] Replace UEM input guesses: ADC channel 6=512, register `0x3f=0`, initial
  `0x36=0`, and read status `0x35=0x10` are explicit unmeasured values.
  Respect read/write direction (0x35 writes do not imply readback); map battery,
  charger, power key, ADC conversion and status behavior from real evidence.
  Verify CBUS configuration, device/register encoding, completion and timing;
  current transport completes immediately. An opt-in `0x27` CBUS write is
  used only on the checkpoint continuation and its hardware meaning is unknown.
  Later checkpoint probes also accept `0x0c150012=0x8000` and ICU bit 25
  as write sinks, and assume GPIO halfwords `0x0c150210` and `0x0c15021a`
  initially zero; subsequent probes additionally assume `0x0c150216=0`,
  sink `0x0c150102=0x0010`, and permit CBUS write command 0x82 with payload
  0xffff. Later stages explicitly assume CBUS 0x82 readback, CBUS 0x80
  status 0x0400 (only inferred from firmware), CBUS 0x8d initial zero and
  readback, UIF 0x0c150102=0x10 as a sink, IRQ 46 enable as a sink, and
  PUP 0x0c14f00a=0 and system-control 0x0c120c14=0. These are not modeled
  devices; IRQ25/46 remain unimplemented.
  The IRQ-path halfword write
  `0x0c150100=0x8000` is an unexplained write-only sink.
- [ ] Replace inferred GPIO/reset latches, initial zero assumptions, and ideal
  PLL/clock acknowledgements with hardware-appropriate reset values, clock
  handshakes and actual 104-MHz timing. Current executable scratch and software
  shadow memory ranges are narrow assumptions with unknown physical backing.

## Display and MiSTer

- [ ] Build a faithful LCD transfer/controller model from firmware traffic and
  hardware evidence. Current probe accepts specific headers, assumes immediate
  FIFO/transfer completion, counts writes and does not model display RAM.
  Confirm controller, command arguments, 12-bit pixel packing, byte ordering,
  orientation, inversion, windowing, partial updates, and display timing.
- [ ] Extend `sim/capture_lcd_screen.py` to produce images from firmware writes
  as LCD behavior becomes verified. Current capture recognizes only the observed
  uniform all-ones full-screen clear and interprets it as white; it refuses
  unrecognized pixel transfers and requires a completed trace. Implement safe
  nonuniform captures, ordered updates, display on/off, and automated tests.
  Before reusing a screen output directory for a different run, ensure old images
  cannot be mistaken for a new capture when unknown commands make capture fail.
- [ ] Integrate ARM, flash, SDRAM arbitration, phone peripherals and video into
  an actual stock MiSTer core. The template video is not N-Gage output; no RBF,
  hardware timing closure, usable ROM loading, controls, sound or game boot has
  been demonstrated. Use firmware-driven display writes, not a pre-rendered logo.

## Validation

- [ ] Validate checkpointing against full firmware and all peripheral state,
  maintain explicit scenario/input hashes and reject stale/incompatible snapshots.
  Current smoke/IRQ tests verify exact post-restore traces at both latencies; the
  firmware checkpoint is experimental and ABI-specific. A synthetic checkpoint
  survived one controlled board-model rebuild with identical HDL and traces;
  arbitrary RTL, state-layout or configuration changes remain unvalidated.

- [ ] Add independently verified CPU/board oracle for external IRQ injection and
  compare post-IRQ execution. Unicorn currently shares the provisional board
  model and has no IRQ injection; agreement is not hardware proof. The strict
  bus comparator cannot directly equate cache-line fills and architectural reads;
  retain cache-aware comparison without claiming identical execution.
- [ ] Audit earlier assumed inputs and timing after each change. Keep original
  firmware untouched; save scenario, hashes, completed result, traces and images
  under `build/`, experiments in `scratch/`, and update status on every frontier.


## Latest checkpoint assumptions to replace

- [ ] Determine hardware semantics for system-control word writes at
  `0x0c120c10` and `0x0c120c0c`; the generic probe merely retains writes and
  makes no claim about side effects.
- [ ] Establish actual reset value and behavior of PUP low halfword
  `0x0c14f000`; the experimental continuation assumes zero and readback.
- [ ] Investigate the upper-halfword write `0x0c150206 = 0x0180`, blocked at
  cycle 452,340,325 because the existing `0x0c150204` latch only allows the
  low halfword. Do not widen it silently; implement or test a separate explicit
  assumption and preserve unknown-read protection.
- [ ] Replace all explicit register probes with documented or experimentally
  verified device models, and rerun with real CPU D-cache once the LDM replay
  bug is fixed. Provisional runs do not establish authentic firmware boot.


## GPIO and cache experiment, latest

- [ ] Determine the electrical effect of `0x0c150206=0x0180`. The opt-in
  exact write sink in `scratch/checkpoint-gpio206/` has no side effects and
  rejects other values and reads; it is not a hardware model.
- [ ] Verify physical GPIO/PUP behavior against hardware or primary manuals:
  checkpoint experiments in `scratch/gpio214-probe/` and
  `scratch/gpio206-extra-probe/` are provisional. The cache-off continuation
  reached a `VARIANT` code 0x00010013 diagnostic after independent explicit
  zero-reset assumptions and the exact GPIO206=0x0006 write sink. Investigate
  table initialization at PC 0x5034933c and await the V15 comparison. The
  values 0,4,0 were copied from virtual 0x5a00f00c (physical 0x0a01200c);
  a targeted write trace found they predate the 451,430,000-cycle checkpoint.
- [x] Test `scratch/gpio214-probe/` using the preserved cache-off checkpoint:
  the opt-in low-halfword zero hypothesis is unit-tested, while real reset value
  and pin functions are unverified. Firmware sets bits 0x0180 using read-modify-
  write. Compare the checkpoint bus prefix and document the next frontier;
  EKA2L1 and rengage do not implement the N-Gage GPIO register.
- [ ] Cache experiment `scratch/blocking-cache-probe-v3/` holds the cache RAM/TLB
  during refill and unlock; it still times out on cold-cache LDM at latency 3
  (500,000 cycles) and fails load-width diagnostics at both 0 and 3. Smoke and
  small-page LDM pass at both, and cold-cache LDM passes at 0. Do not use this
  prototype as a fix. Diagnose instruction-level replay/partial completion and
  cache-fill timing; review with Sol as previously discussed when available.
  Logs/results are in `build/sim/runs/blocking-cache-v3-*/`.

## Focused replay investigation follow-up

- [ ] Resolve the cross-line control in `scratch/ldm-wait-probe/crossline.S`.
  The wait/forward candidate passes 18 focused cases, including original cold
  LDM and load-widths at 0/3, but cross-line LDM fails 0x22 at both. Do not
  promote it. Separate CPU backpressure from refill RAM writes and preserve
  cache/TLB pipeline alignment, or implement an instruction replay checkpoint
  with abort/interrupt semantics. See [ldm-replay-investigation.md](ldm-replay-investigation.md)
  for exact cycles, source provenance and remaining validation.


- [ ] Cache/TLB cross-page replay: candidate `scratch/ldm-lookup-align-zap/`
  passes dirty eviction and cache-line crossing but fails cold noncontiguous
  page crossing (`scratch/ldm-page-crossline/test.S`) at latencies 0/3 by
  issuing untranslated physical address `0x40001000`. Busy=0 is not translation
  valid during another refill, because TLB walk is gated by cache idle. Retain
  the pending request and coordinate TLB lookup/walk and completion; test
  warm/cold pages, missing/permission-fault page, abort/IRQ cancellation,
  load/store widths, dirty victim and timing. See `ldm-replay-investigation.md`.


- [ ] Review and replace/justify the provisional four-cycle TLB lookup settling
  heuristic in `scratch/ldm-tlb-handshake-v2-zap/` with a genuine validity
  handshake; verify reset, cancellation, IRQ/FIQ, CP15 invalidation, privilege
  changes, fault permissions and alternative TLB/cache configurations. The
  prototype passes cold cross-page load, abort, STM, dirty eviction and slower
  memory timings but is not a production fix. Run independent ARM oracle,
  original CPU regressions and synthesis lint before considering promotion.


- [ ] V2 scratch forwarding bypasses permission and alignment checks; do not
  use it. V3 gates forwarding and passes directed reproducers, 55 latency tests,
  upstream ARM/Thumb and synthesis lint. Before production, replace/prove its
  four-cycle TLB settling counter and ensure pending request address, operation,
  translation context and cancellation remain stable; test cache/TLB parameter
  variations, independent oracle, eviction, IRQ/FIQ and real fault side effects.
  `scratch/ldm-irq-refill/` tests a level IRQ asserted during refill at 0/3/7,
  accepted after LDM; does not establish general asynchronous cancellation.


- [ ] V4 (`scratch/ldm-tlb-handshake-v4-zap/`) adds stalled-VA/direction/mode
  assertions and advances its wait counter only on enabled lookup cycles;
  it passes directed, ARM/MMU/fault, upstream and synthetic IRQ/FIQ tests.
  It still needs an explicit validity/request-identity design (including CP15
  context, invalidation and flush cancellation), not just a counter. Do not
  overwrite the v3 source currently used by the firmware run.


- [ ] Cache-enabled v3 firmware computes digest
  `f92e2e386422faeaeedde006063cd464` instead of the independent/reference
  `1784c17a6fd17b0841226546434db048`, then stops at `0x50003290`. Isolate
  first CPU/cache or memory divergence in the digest workload; compare seven-
  patch normal-cache and cache-disabled traces, and create a short independent
  reproducer. Do not replace the expected digest with the wrong value. See
  `build/sim/runs/boot-cache-candidate-v3/` and `ldm-replay-investigation.md`.

## Digest regression directed case

- [ ] Resolve v3 failure in `scratch/md5-short-probe/next-load.S`: a following
  PC-relative constant load returns zero after a cached load/store sequence.
  Eight NOPs or an immediate comparison passes; seven-patch passes all controls
  at 0/3. The real firmware bad digest exactly equals zero-IV MD5, and short
  unchanged MD5 code confirms zero initialization constants. Trace lookup
  pipeline restoration after pending ACK; see latest investigation section.
  Do not rerun long boot or promote v3/v4 before this directed case is fixed.


- [ ] V5 (`scratch/ldm-tlb-resync-v5-zap/`) fixes the short following-load
  repro at five timings, but both short firmware MD5 tests fail at all five.
  Inspect repeated resynchronization and cache/TLB pipeline identity in
  `build/sim/runs/ldm-md5-v5-trace-latency0/`; do not promote v5.


- [ ] Identity-based scratch v7 passes 70 directed timing cases, short firmware
  MD5 and cold LDM together, extra CPU fault tests and IRQ/FIQ controls. Full
  firmware run is active. Audit cache/TLB result identity after invalidate,
  reset, flush/cancellation, overlapping accesses, context changes, full
  maintenance and interrupt entry; add independent oracle and FPGA synthesis.
  Its conservative validation path stays enabled after a held request, so
  measure throughput and verify it cannot stick across relevant cancellation.
  Do not promote without full review and passing firmware integrity.


- [ ] Audit CP15/write-buffer semantics from observed firmware;
  [cache-maintenance-audit.md](cache-maintenance-audit.md) records that ZAP
  treats firmware `c7,c10,0` as clean-all and has no explicit `c7,c10,4`
  drain decode. Directed clean/invalidate checks pass, including after
  overlapping refills, but do not prove drain or ARM920T equivalence.


- [ ] Scratch V8 adds reset-aware lookup-valid bits; 70 directed tests pass.
  Broader CPU and IRQ/FIQ controls and synthesis-path lint pass; actual
  synthesis, firmware, invalidation and cancellation tests remain before promotion. The active firmware run uses V7, not V8.


- [ ] V9 adds ACK-edge request-identity assertions and passes 70 cases; run
  interrupt, actual FPGA synthesis and firmware checks before promotion;
  broader CPU tests, original benches and synthesis-path lint now pass.
  It remains distinct from the active V7 boot.


- [ ] Reduce conservative identity-path overhead after correctness. The 32 KiB
  firmware digest test uses 1,038,626 cycles on V7/V8 versus 780,269 on
  baseline (~33% more); this is a single simulator workload, not FPGA timing.
  Preserve request/translation identity and repeat all regression gates.


- [ ] Performance experiment V10 is rejected: the nonsticky validation
  shortcut passes next-load but fails short firmware MD5. Optimize only after
  proving request-stage identity and rerunning mandatory digest/LDM gates.


- [ ] V7's full cache-enabled firmware run fails integrity at cycle 666,454,237:
  computed `2d41ef51bb1576cdb457d0212f8330dd` versus expected
  `1784c17a6fd17b0841226546434db048`. Short 32 KiB firmware MD5 passes.
  Isolate first failing length/address or cache/TLB eviction with the short
  harness and compare independent results. Do not promote V7.


- [ ] V7/V8 fail the unchanged firmware MD5 at 1 MiB while baseline passes;
  V7 passes through 512 KiB. A direct byte loop across the section boundary
  passes all three, so isolate digest state and first divergent block. See
  `scratch/cache-md5-length-sweep/` and `ldm-replay-investigation.md`.


- [ ] First V7 digest divergence is at PC 0x3eb0 after adjacent loads from
  0x00100120 and 0x475c; inspect actual asynchronous completion and
  translation signals in bounded `md5-window-*` traces, then reduce to a
  short reproducer. The naive alternating-section test passes.

- [ ] Replace the counterfactual-only exact-write probes in
  `scratch/variant-{sysc74,gpio24,timercompare,sysc50}/` with evidence-based
  system/interrupt/timer behavior. Current synthetic run stops at
  0x0c1201c8=0x08000000; timer 0x0c120a10=0x632ea is accepted as a latch
  only and does not create a new IRQ.
