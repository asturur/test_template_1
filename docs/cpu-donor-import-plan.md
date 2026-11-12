# CPU donor import plan: benchmarks before changes

2026-11-12. Scope: bring the donor CPU improvements into the original NEM-4
core, in measured increments. This is an execution plan, not an implementation
or a set of measured results. It follows [the source comparison](cpu-donor-comparison.md).

## Working agreement

For every import: **write its tests and benchmarks, run the original, change
one item, rerun unchanged benchmarks, record the result, then accept or reject.**
Do not import the whole donor CPU first and attempt to explain its gains later.
Every identified difference below receives a disposition and evidence. A donor
behavior specific to TI ARM925T must be adapted to ARM920T rather than silently
changing the original phone's architecture.

Work on the current branch. Do not create branches or switch the user's checkout.
Use isolated source snapshots under `scratch/cpu-donor-import/` for references
and experiments. Accepted production code replaces its predecessor; comparative
build selection belongs in the benchmark harness, not an OSD/production switch.
Do not commit, push, launch CI or deploy as part of this plan without a request.
Use the existing `jotego/simulator:arm64`, no image pull or Quartus download.
No baseline fit is a prerequisite for starting the benchmark work.

Retain the original ARM920 identity, architectural exceptions, banked registers,
SPSRs, CP15 maintenance and lockdown, permissions, timer rates, SWP exclusion,
accepted-transfer drain, LCD ordering and media persistence. Keep new maintained
HDL Verilog-2001 compatible; preserve imported-source style/attribution. Record
ZAP changes in its ordered patch provenance and verify reconstruction.

## Measurement protocol, fixed before the first import

### References and experiment isolation

Phase00 captures the actual working tree and complete compiled source closure,
including dirty files and dependencies outside `rtl/arm`. Git HEAD alone is not
the baseline. Pin source hashes, donor hashes, active patch list, QSF/SDC, image
ID, tools, compiler flags, test binaries, firmware, overlays, C:/PMM/MMC images
and all runtime parameters. Do not capture credentials or unrelated files.

The user pins the first two measurements to these exact adjacent commits:

| Reference | Exact source | Role |
| --- | --- | --- |
| H0 | `ce8d2c902724a59e7537b845bc841dbd82d5bbf7` | Original historical baseline |
| H1 | `3f5e8aeae3260562a814eacdd8d8aa505c044af8` | Next historical measurement: burst refill/short reads |
| B0 | Frozen current branch working tree, including explicitly inventoried pending memory-controller changes | Starting point for subsequent CPU imports |
| B0-old-sdram | Same B0 snapshot with only the pending native-controller series replaced by its saved predecessors | Matched control for uncommitted controller work |

H0 is H1's parent. Run the same newly written tests and binaries on H0 and
H1 first, then on the current work. Do not substitute HEAD/HEAD~1 for these
hashes or silently overlay current CPU RTL on a historical build. Historical
sources are read into scratch snapshots without checking out another branch.
Freeze any minimum harness adapters separately and report them.

Each accepted CPU import produces **B1, B2, ...**. Report H1/H0, B0/H1,
B0/B0-old-sdram, and each candidate against its immediate accepted predecessor,
B0 and H0. H1→B0 includes intervening work; it is not a controller-only delta.
Only the matched B0-old-sdram→B0 pair can isolate the pending controller series.
Do not sum isolated gains or count RF/SDRAM improvements already in B0 twice.

Keep CPU/cache/SDRAM/LCD/DDR configurations and inputs constant within each
controlled comparison. Where H0 lacks the line port, the harness uses its
original scalar interface and records that difference explicitly. Include real
memory-sensitive integration benchmarks; an idealized CPU responder alone cannot
measure controller timing. Settle and pin native-SDRAM validation before CPU
imports. If another chat changes a dependency, use the frozen source or create a
separately named baseline. Never overwrite their work.

No cross-RTL simulator checkpoint restores. Rebuild and cold-start each variant
from identical immutable guest images, or use a guest-level save/profile with
verified identical starting state. Existing long simulations and permanent
billion-cycle CPU/host checkpoints remain untouched.

### Three benchmark levels

| Level | Purpose | Memory/clock control |
| --- | --- | --- |
| L1: CPU kernels | Instruction latency, initiation interval, forwarding, branch and uop costs | Same binaries, warm/cold markers, independent instruction/data wait schedules; cache-off and hot-cache runs reported separately |
| L2: production memory integration | Actual cache/TLB/refill/write-buffer and mixed CPU/LCD effects | Original production geometry and transports, controlled row/refresh/load cases, physical SDRAM model where relevant |
| L3: firmware and gameplay | Does the change help the phone and games? | Same firmware/media/overlay/profile, reference clock, input sequence and named workload endpoints |

Run L1 with fixed waits0/3/7/15/31 and deterministic seeded variable waits,
including independent I/D waits. Implement I/D profiles before using donor
labels such as `0:3` or `2:9`: the current `CPU_DELAYS` option is one scalar
latency, not that two-channel contract. Keep at least three fixed hold/interrupt
seeds, identical across variants. Isolate initialization, cache warm-up and the
measured body. Every cycle window has named ELF symbols, an edge convention,
an exact operation count and an independently checked final signature.

Compare architectural state/effects with an independent oracle or applicable
existing reference. Do not make the old CPU the correctness oracle for a known
bug. Adapt donor QEMU fixtures to ARM920 expectations; TI CP15 behavior is not
an ARM920 oracle. Distinguish instructions from internal uops and Thumb BL
halves consistently. Allow only the predeclared intended semantic differences
for a correctness fix; do not normalize away unexpected exceptions or writes.

### Required outputs

Record total/body cycles, architectural instructions, internal uops, instructions
by class, CPI, cycles per useful operation, dependency and independent issue
spacing, branch outcomes/penalties, I/D misses, walks, bus beats, write-buffer
occupancy and CPU/LCD wait distributions. Include raw overlapping stall flags
and a separately defined exclusive accounting view; stall percentages cannot
simply be added or treated as causal savings. Every counted cycle must reconcile.

For a routed build record source/constraint hashes, seed, ALMs/LABs, registers,
M10Ks/MLABs, DSPs, all setup/hold corners and worst1000 endpoints. Separate
CPU-only results from whole-core results. A simulator's faster cycles are not
104MHz closure. Simulating104MHz does not authorize changing the board PLL.

Use these per-case identities in JSON/CSV: phase, benchmark/version, reference
and candidate source IDs, binary/input hashes, cache/TLB settings, clock, I/D
wait profile, random seed, warm-up/body markers, operation count, correctness,
metrics, run/log paths and status. Status is PASS, FAIL, BLOCKED or NOT_RUN;
missing games/tools are never a pass. Store raw logs under
`build/sim/cpu-donor-import/<phase>/<source-id>/<case>/` and small maintained
summaries under `docs/evidence/cpu-donor-import/`.

Report **cycles saved = 1 - candidate/reference** and separately **throughput
gain = reference/candidate - 1**. Do not label either one as FPS. Report each
case and a geometric mean of cycle ratios with fixed benchmark-group weights;
freeze the groups/weights before imports so adding favorable cases cannot alter
the score. Correctness cases and idle/setup time do not inflate the speed score.

## Phase00 — freeze both historical references and current work

Inventory the current source/firmware state and read the latest SDRAM validation
checkpoint. Reuse completed matching tests; resolve pending relevant failures
before attribution. Inventory available game images and guest saves without
modifying them. Establish whether Call of Duty is available and runnable; a
missing title is an explicit gameplay gate, not grounds to invent an FPS result.

The first `tests/cpu/donor_import/` harness now exists with frozen source
variants, shared binaries, immutable numbered HDL attempts, JSON comparison and
host regression checks. See its [README](../tests/cpu/donor_import/README.md).
The first15 ARM kernels now have480 passing HDL observations across all four
variants, two transports/two wait profiles and exact deterministic repeats;
[measured results and remaining gates](cpu-donor-baseline-results.md).
Complete and qualify the remaining measurement/architectural coverage before
CPU imports; initial implementation does not mean phase00/01 has passed.
The current core runner's fixed `build/sim/unit-core` output and basename-only
`CPU_REFERENCE_DIR` substitution are useful starting points, but insufficient
for complete variant isolation, new/removed modules or concurrent runs.

Before CPU edits, prove counter/marker accuracy using small programs with known
iteration/retirement counts, missing-marker failures, duplicate completion,
random holds and reset. Compare instrumented and uninstrumented effects/cycles.
Snapshot H0, H1, B0 and its matched old-controller control. Run each baseline
twice; deterministic cases must reproduce exact results. Keep simulation-only observers out of the synthesis source graph.

**Exit:** frozen H0/H1/B0/control and donor provenance; validated metrics; dependency/tool/game
availability recorded. No CPU import yet.

## Phase01 — write tests and run H0 → H1 → current work

Create all shared benchmark families below before importing CPU RTL. Add each
phase's remaining corner cases before that phase's first edit. Import donor
tests with attribution and adapt their harness/architectural expectations first.

| ID | Benchmarks to write before imports | Existing material to reuse |
| --- | --- | --- |
| A: architectural decode | ARM/Thumb condition matrix; supported/undefined encodings; User/SVC coprocessors; flags/modes; SWI/UND links; interworking; independently interrupted BL halves and lone suffix | Donor `v5und.S`, `tbl_irq.S`, `thumb.S`, `exc.S`, `psrflow.S`; our CP15/IRQ/alignment fixtures |
| B: branch/frontend | Taken/not-taken loops, cold/warm direct/indirect branches, ARM/Thumb calls, nested/recursive returns, RAS overflow/underflow, same-index aliases, failed conditions, wrong-path faults, cross-word Thumb, queue backpressure | `btb_return.S`, `thumb_return_dependency.S`; donor `arm9_predict.S`, `arm9_branch_slots.S`, `btb_early.S`, `arm9_queue.S` |
| C: arithmetic/shift | Independent and dependent ADD/ADC/SBC/logical sequences; full NZCV reference checks; immediate/register shifts with0/1/31/32/>32 counts; RRX; early versus late operands | `cpu_timing.S`, `operand_timing.S`, operand scoreboard; donor `alu.S`, `shift.S`, `arm9_dep_waw_rtl.S` |
| D: multiply | MUL/MLA/UMULL/SMULL/UMLAL/SMLAL, flags, signed extremes, dependent factors/accumulators, paired writes, back-to-back operations, failed condition, held completion, interrupt/flush | Donor `mul.S`, cycle/execute fixtures; independent64-bit arithmetic oracle |
| E: load/store pipeline | Hot independent loads/stores; LDR→ADD versus LDR→base/index/shift; byte/signed/halfword/unaligned formatting; loads to PC; WAW/RAW; store→reload; precise permission/alignment/external aborts | Our load-width, completion/formatter, privilege, SWP and operand tests; donor `loadpipe.S`, `loaduse.S`, `loadchain.S`, `arm9_short_format_rtl.S` |
| F: block/serialization | LDM/STM counts1..16, all address modes, base/list combinations, user banks, PC/SPSR, abort at every beat; memcpy/stack bodies; SWP; flags-only MSR/MRS and CP15 reads versus ordered changes | Our LDM/SWP/WFI/CP15 tests; donor `ldm.S`, `arm9_tail.S`, `arm9_state.S`, `arm9_msr_lock_rtl.S` |
| G: memory system | Clean/dirty misses, critical word at every line position, fill error/reset, independent hit during miss, same-set conflicts, posted stores/drains, page sizes/AP/domain/FCSE, real lockdown and maintenance | Existing cache/TLB/write-buffer suites and native SDRAM latency bench; donor fill/HUM/store/alias fixtures |
| H: compiled work | Fixed ARM and Thumb C kernels: integer math, pointer chasing, memcpy/memmove/memset, stack/call-heavy and branch-heavy code; fixed pseudo-random programs with equal useful work | Adapt donor compiled-random/cache/gba fixtures where available; pin compiler, seeds, binaries and initialization |
| I: phone/game | Named firmware/application tasks, Call of Duty named active scene, plus a second contrasting game if available; CPU + sustained LCD/MMC controls | Existing bounded boot/production board/DMA fixtures; adapt donor profile/input tools, without executing their hardware reload scripts blindly |

Run identical benchmark binaries on H0 and H1, then B0 and B0-old-sdram, for every applicable case. Preserve known architectural failures as
named failing cases with expected architectural outcomes; later fixes must turn
those cases green. Verify the relevant test actually distinguishes the candidate
property using a controlled negative variant in scratch where practical.

**Exit:** versioned H0/H1/current/control tables with raw evidence and workload weights;
correctness oracle and measurement edge contracts reviewed. The first import
starts only after its relevant baseline results exist.

## Ordered imports and their decisions

Each row is a separate measured change; lettered substeps stay separate too.
Use the benchmark IDs above plus the explicit cases listed. A coupled change
must be declared as such before editing, with its interaction test, rather than
bundled retrospectively when results are difficult to explain.

| Order | Difference/import | Benchmark and acceptance focus |
| --- | --- | --- |
| 02a | Audit/port donor upstream correctness fixes not already present: Thumb exception links, invalid memory encodings, long-multiply flags, bank/base restoration and instruction/data privilege | A/D/E/F; first reproduce each actual gap. Mark already-fixed or inapplicable items individually with test evidence |
| 02b | Strict guest ARMv4T classification, PSR masks and BX-only interworking | A+C; correct conditional UND and no unexpected side effects. Preserve internal ZAP uops even when their bit patterns resemble excluded guest encodings |
| 02c | Architectural Thumb BL prefix/suffix and interrupt boundary behavior | A+B; LR after prefix, lone suffix, IRQ/FIQ at each halfword/hold and exception return, same/cross-word pair. Record normal BL/call and IRQ latency costs |
| 03 | Correct MOV pc,lr RAS recognition, then any directly associated return metadata fix | B; nested ARM/Thumb call loops, alias/stale-target cases. Measure predictions, lost fetch slots and call/return clocks; ordinary program effects unchanged |
| 04a | DSP product implementation and flag logic within the existing multiply contract | D+C; exact results/flags and held completion; initially isolate mapping/timing from scheduling |
| 04b | Shorter multiply/accumulate schedule and safe full-product reuse | D+H; measure latency and initiation interval separately, low/high result ownership and all dependencies. No assumed speedup from DSP count alone |
| 05a | ARMv4T ALU/flag organization, including carry-independent Z | C+D+H; no added ALU issue bubble; independent NZCV oracle and same effects at all waits |
| 05b | Common rotate/mask/carry network and predecoded shift controls | C+H; corner shift semantics and RRX, shifted dependency spacing; measured timing/area benefit if cycles remain identical |
| 06 | Staged decode metadata, physical source classes and registered match/grant controls | A/B/C/E; maintain operand freshness on held queue entries and current/previous commits. Keep warmed dependent unshifted ADD interval1; record any first-instruction/redirect cost |
| 07 | Registered short D-cache hit response and completion classes | E+G; preserve checked owner, byte formatting and precise fault context. Separate hit latency from hit throughput and avoid replay of acknowledged stores |
| 08 | Early/late operand availability, producer selection and load-consumer bypass | C/E+H; distinguish LDR→ADD from LDR→shift/address, failed younger writer versus older load, stalled producers, WAW and flags. Reuse our RF/operand oracle |
| 09a | Precomputed block-transfer list/count/offsets and streaming sequencing | F+G+H; memcpy/stack cycles per word and initiation overhead; abort/base restoration, user-bank/PC and IRQ boundaries all preserved |
| 09b | Paired long-result completion and optimized final LDM word/PC pickup | D/F/B; both destination lanes, last-word consumers and PC returns, no lost writes or imprecise exceptions |
| 09c | Avoid needless global flush for ordinary PSR operations and safe CP15 reads | F+A+B; preserve fences for mode/MMU/cache changes, SWP and older fault-capable work; measure reads versus serial changes separately |
| 10a | Fetch/decode separation and earlier direct-branch handling | B+H; cold/hot redirects, fault/cancel epochs and backpressure, with predictor capacity held equal |
| 10b | Donor predictor/return-stack recovery and registered feedback | B+H; wrong-path nesting, rollback, alias/collision and clear-under-hold. Compare against the already-fixed phase03, not the old matcher |
| 11a | Critical-word-first refill and qualified early load return | G+E; requested word at every offset, line/error/reset ownership and cached byte formatting. Do not expose a partial line as complete or adopt donor error suppression |
| 11b | Hit-under-fill/background miss ownership | G+E+H+I; independent address versus same set/line, second miss, WAW, IRQ/CP15 and simultaneous LCD. Bound outstanding work; no second miss engine assumed necessary |
| 12a | Donor store-queue/deferred-writeback ideas beyond our existing posted buffer | G+F+I; preserve drain/order/forwarding and dirty data; distinguish buffer organization from depth. Do not shrink our capacity simply to match donor |
| 12b | Faster translation/permission reuse and cache lookup organization | G+E; mixed directions/context, AP subpages, all page sizes, FCSE, invalidation and lockdown. Adapt useful donor lookup ideas while retaining the architectural TLB contract |
| 12c | Cache capacity/associativity/line-size experiments | G+H+I; one dimension at a time, separate matched-geometry and larger-capacity comparisons, all ARM920 index/MVA/lockdown/coherency tests. Record ALM/RAM and DMA costs |
| 13 | Import/adapt the full eight-stage ARM9V2 execution pipeline | Entire suite; compare latest cumulative original against execution-only replacement using the same original memory system, then optionally against independently measured geometry candidates |
| 14 | Validate cumulative phone/game benefit and select production result | I plus all correctness/regression gates; report same-clock cycles, actual routed timing, resources and active gameplay/frame cadence |

The dependency chain is00→01→02→03→04→05→06→07→08→09→10→11→12→13→14.
Substeps are serial experiments. Phase03's benchmarks can already be written
in01, but do not run parallel RTL imports that invalidate each other's baseline.
If07/08 require one new load/forwarding contract, implement them as a declared
joint candidate after separately measuring cache response and operand wait costs;
keep attribution limited to the joint candidate.

Phase13 is explicitly included, not silently deferred out of scope. First build
an isolated execution adapter for the original cache/MMU/CP15/writeback and
architectural diagnostics. Benchmark that adapter with unchanged ZAP execution
before swapping the integer pipeline, so wrapper cost is visible. Preserve
ARM920 IRQ/abort/exception-return semantics and registered request ownership.
Test the exact generated/source form that the production build will consume.
Retain a smaller import if V2 fails to improve the cumulative implementation;
rejected experiments remain evidence, not dormant production cores.

## Complete difference coverage and architectural limits

The rows above cover execution stages, decode, Thumb, arithmetic, shifts,
multiplication, forwarding, loads/stores, LDM/STM/SWP, PSR/CP15 serialization,
prediction/redirects, caches, TLBs, buffering and early returns. Phase02a must
turn every documented donor correctness fix into an individual ledger entry,
with source/test references and one of: imported, already present, or not
applicable with a stated reason. New differences discovered during import are
added before editing and assigned a preceding benchmark.

The following do not become blind RTL imports:

| Difference | Disposition and required evidence |
| --- | --- |
| Latest-writer MLAB RF | Already imported as0057. Run existing RF/CP15/stalled-operand suites and include current B0 area; compare only subsequent measured refinements |
| Registered ownership, formatting, separate completion, line streaming and posted writes | Partly already present. Map donor behavior against current contracts in06–12; do not reintroduce a second implementation to claim the same gain |
| TI ARM925T CP15 ID/control/index encodings | Keep ARM920 identity/operations. Port relevant serialization/tests, not a QD identity into NEM-4 |
| Direct-mapped donor TLB versus our associative64-entry tables | Benchmark lookup ideas in12b; no-op lockdown is not acceptable. A front-end lookup cache must still validate context and fall back correctly |
| Donor two-way caches, larger capacities and16-byte lines | Explicit12c experiments; software-visible ARM920 maintenance/lockdown semantics remain acceptance tests. Reject a geometry that cannot preserve them |
| Ignoring cacheable-fill errors | Retain existing original error/installation contract. Early return requires a proven no-later-error guarantee or an architecture-correct deferred-fault mechanism; otherwise it remains blocked |
| Removal of donor automatic I-cache prefetch | Distinguish speculative sequential prefetch from architectural CP15 prefetch. Benchmark usefulness in12c, retain required CP15 behavior; no assumption that donor's board result applies here |
| Frequency, external SDRAM mapping and phone peripherals | Fixed controls for CPU imports. Separate experiments and evidence; no clock bump, timer change or transport change hidden in a CPU speed claim |

## Keep/reject rules

Correctness fixes are accepted for their architectural result even if neutral
or slower; report the cost openly. A baseline that fails such a case cannot be
credited as the faster implementation of that behavior. Run all unaffected
correctness fixtures unchanged; unrelated differences are regressions.

For performance changes, pin the objective before running. Initial promotion
priority targets are: at least2% fewer body clocks on the fixed representative
aggregate, or at least10% in the intended kernel class with no representative
slowdown over1%. Smaller repeatable gains can also be accepted when their exact
benefit and implementation cost justify them; do not discard an exact useful
one-clock saving merely for missing a percentage target. A cycle-neutral
mapping/timing change can qualify with a clear resource or routed-path improvement,
reported as that benefit, not CPU speed. These are prioritization targets, not
promised gains. Revise them prospectively
in the ledger if a justified workload need differs; never after selecting only
favorable results. Report every case and absolute clock delta even below threshold.

Performance-only changes must retain warmed unshifted dependent ADD interval1,
correct byte/half/word operations and all ownership/fault checks. Track LCD/MMC
service and starvation as guard workloads. If a faster average introduces a
material tail-latency regression, the candidate is not promoted silently.

Functional simulation is the first gate. Fit meaningful candidates after their
cycle results justify it; reuse matching existing reports when available. Small
source changes do not each require a fresh full baseline fit. Before production
promotion, obtain comparable parent/candidate routed evidence for changes whose
benefit or risk is physical. Use matching seed/constraints; use three fixed
seeds for major finalists so placement luck is visible. Do not hide failures by
seed hunting, relaxing constraints, false paths or lower clocks. Keep within
device capacity; report any resource increase and gain together. Target104MHz,
retain actual78MHz operation until independently qualified otherwise.

Reject or retain as experimental any performance import with no demonstrated
benefit, correctness/ordering loss, unbounded resource cost or unacceptable
routed timing. Preserve the experiment, failure and measurements in scratch and
the ledger, then continue the ordered plan from the last accepted implementation.

## Firmware and Call of Duty benchmark contract

Write this contract and capture the original run during01, not after the last
CPU change. Freeze game/version hash, level/save, difficulty, camera/start
position, input script, firmware, guest disks, overlay and phone clocks. Use
user-provided/local game data; do not assume a runnable Call of Duty image or
checkpoint exists. Record the first successful repeatable active scene.

Use guest-time/input events and verified scene boundaries, not instruction-count
timestamps that drift when instruction implementation changes. Exclude loading,
menus, pause and idle from the active score but report their times separately.
Run at least five paired reference/candidate active windows of30s or an equally
long fixed task; report per-run results, median and spread, and alternate A/B
order on hardware. Verify the same scene/work actually ran.

Measure cycles per game-produced frame/task, useful retired work, input-to-frame
latency, frame-time median/p95/p99, misses/walks, load/issue/branch/multiply waits,
memory bandwidth and LCD service. Establish a real game-frame marker: MiSTer
scanout refreshes and LCD strip writes are not automatically new game frames.
Validate the marker against visible updates and the game's render cadence before
publishing FPS. Report caps/idle explicitly; a capped FPS can hide CPU headroom.

Where simulation cannot yet boot the game, report L3 as BLOCKED and continue
L1/L2. A self-contained representative kernel can explain a CPU cost but cannot
stand in for a measured Call of Duty FPS improvement. Do not use cross-RTL
checkpoint migration to manufacture comparable gameplay starts.

After substantial phases, run fresh bounded firmware regressions and named
application work as well as the hot kernels. The latest menu success is a
useful new milestone, but a different overlay/media state cannot be compared
with the older failing startup and credited to the CPU. Never use only the
initial uncached delay loop as the firmware performance score.

## Execution artifacts and existing commands

Maintain `docs/evidence/cpu-donor-import/index.json` with one record per candidate
and a result table in this document or a linked results document: source IDs,
benchmark version, intended benefit, before/after cycles, aggregate and worst
regression, architectural differences, physical results, decision and reason.
Save significant source snapshots/logs in repo scratch, short reports in docs,
generated executables in build. Accepted ZAP edits require the next available
patch number and `patches/zap/verify.sh` against the existing pinned upstream.

Existing entry points to extend/reuse (the first new harness and its commands
are documented in [tests/cpu/donor_import/README.md](../tests/cpu/donor_import/README.md)):

```sh
sh tests/cpu/run.sh
CPU_PROGRAM=operand_timing CPU_DELAYS='0 3 7 15 31' sh tests/cpu/core/sim.sh
CPU_PROGRAM=cpu_timing CPU_DELAYS='0 3 7 15 31' sh tests/cpu/core/sim.sh
sh tests/cpu/rf_mlab/run.sh
sh tests/cpu/operand_edges/sim.sh
sh tests/phone/sdram/run-native.sh
sh tests/phone/dma_channels/run-concurrency.sh
sh tests/phone/dma_handover/run.sh
```

These scripts have different host/container conventions and some reuse output
paths. The new harness must run them serially or isolate their directories and
archive each result before reuse. Use production-top lint, relevant chip/board
integration and the bounded real-SDRAM boot runner for major boundary changes.
Do not start every long regression for every comment-only or test-only edit.

Update this plan's result links, `docs/cpu-donor-comparison.md` and
`docs/status.md` at each accepted/rejected stopping point. The next executable
task is **00 and01 only: freeze the current implementation, build/validate the
benchmark harness, write tests and measure the two pinned commits before current
work and its matched controller control. No CPU import precedes it.**


## First implementation checkpoint — 2026-11-12

The user pinned H0 toce8d2c902724a59e7537b845bc841dbd82d5bbf7 and H1 to its
child3f5e8aeae3260562a814eacdd8d8aa505c044af8, and authorized writing tests.
The first harness snapshots both commits and current working/control sources,
assembles15 shared ARM kernels with guest checks and emits strict per-case
comparison records. No CPU RTL changed or imports begun. Pending native-SDRAM
work remains uncommitted and explicitly identified in the working/control pair.

Prepared experiment: `cpu-donor-baselines-20261112-b`. All15 programs assemble;
23 host tests pass for source isolation, drift detection, counters and comparison.
HDL execution is BLOCKED by Docker socket access. Optional installed Unicorn
initialization terminates with SIGILL; its child-process preflight records
BLOCKED. Local Icarus cannot elaborate the historical production RTL unchanged.
No CPU timing/correctness benchmark has passed and no speedup is available.
The earlier-a experiment contained a testbench syntax issue and is superseded,
with its failure retained. Do not treat program assembly or host checks as HDL
qualification. Evidence: [first batch](evidence/cpu-donor-import/first-batch-2026-11-12.json).

Remaining before importing: HDL smoke/counter qualification on H0/H1, repeated
baseline runs and full phase01 coverage, including Thumb/IRQ/fault fixtures,
compiled C, actual controller integration and runnable game scenes. The current
synthetic memory bench intentionally does not instantiate SDRAM RTL; its matched
controller pair is a negative control, not a memory-controller speed result.
