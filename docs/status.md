## 2026-11-11: All-enabled integration hardware build configured

Commit `027aa18` records the locally verified D2, D3 and S3 implementation.
The integration build selects `D1_STREAM_TRANSPORT=1`,
`D2_FLASH_CACHE_BYTES=8192` and `D3_BULK_PERSISTENCE=1`. Background save starts
Off and is available in the OSD. Use writable copies of the raw C: and PMM
images for the first hardware test.

The DDR adapter, arbiter and save sector bridge compile as Verilog-2001 `.v`
files. `Template.sv` uses the stock MiSTer HPS disk-array interface. DDR cache,
bulk ownership, sector bridge, ordered HPS and combined NOR/HPS tests passed
in the integration worktree. Both top configurations elaborated and the
Quartus source graph passed. FPGA fit and hardware testing remain open.

## 2026-11-11: S3 ordered background saving locally verified

The D3 bulk build now uses one 8,320-sector dirty queue across C: and PMM.
Background save defaults Off in the OSD. When enabled, a pass is eligible
after one second quiet or five seconds pending. Automatic passes save up to
16 sectors and let pending warm resets run between passes. Manual Save drains
both slots. Re-dirty after dequeue queues a new generation. Transfer or queue
failure stops saving, preserves unsaved DDR contents and exports C:/PMM error
bits in the slot 3 diagnostic image.

Queue, reset, actual HPS, bulk NOR, full-size reload, diagnostic export and
structural checks passed. Original-firmware filesystem interruption/remount,
MiSTer Main durability and fitted timing are open. See
[background-save.md](background-save.md) and [merge-plan.md](../merge-plan.md).

## 2026-11-10: D3 bulk persistence locally verified

D3 uses the D1 stream engine for 64-beat C:/PMM snapshots and wider restore
writes. Sector grants serialize mutations, preserve SWP and survive reset
until the physical tail drains. Restore invalidates sixteen D2 indices.
`D3_BULK_PERSISTENCE` defaults to zero. D2 and D3 changes are uncommitted
on the integration worktree, based on D1 commit `386f576`.

Scalar, bulk and bulk+D2 actual HPS/NOR tests passed. Full-size scalar and
bulk restore/reload matched every word and both last-sector saves. Two
full-image restores issued 2,129,920 scalar DDR writes or 1,064,960 bulk DDR
writes. Ownership/reset, scalar bridge, four-slot HPS, six D2 configurations,
formatter, source graph and both top elaborations passed. The 4 KiB host
assessment is in [ddr-bulk-persistence.md](ddr-bulk-persistence.md).

Evidence and remaining gates are in [merge-plan.md](../merge-plan.md) and
`docs/evidence/ddr-bulk-persistence-2026-11-10.json`. Integration logs live in
`scratch/ngage2-integration/d3/`. Physical fit and timing remain open.

## 2026-11-10: D1 committed and D2 cache candidate locally verified

D1 is committed as `386f576` on `codex/ngage2-integration`. D2 adds the
optional shared raw flash cache after DDR arbitration. `D2_FLASH_CACHE_BYTES`
defaults to zero. Matching tags invalidate before ordered DDR writes. Scalar
misses return the requested beat early and hold their fill until it completes.
The full contract is in [ddr-flash-cache.md](ddr-flash-cache.md).

Six cache/transport byte-oracle configurations passed. Actual HPS/NOR checks
passed changed C:/PMM restore, descramble boundaries, C: ID/erase and PMM
status. NOS/BT overlay HPS tests passed all four views and exact undo.
Default and D1+D2 top elaboration, Verilog-2001, formatter and source graph
checks passed. The restore fixture needed a clean flush scan before replacing
warm media because the existing manager marks NOR activity conservatively.
The overlay runner needed explicit D1 module dependencies for Verilator's
hierarchical references. Source-graph preflight ran on the host Tcl runtime.

Matched synthetic D1 reuse probe with D2. 256 to 16 DDR reads and 1,920 to
1,280 elapsed clocks. Scalar hit one clock, cold first-word miss six clocks
versus four uncached. The 24 KiB scan was slower with D2 at each capacity.
Representative firmware performance and Quartus fit/timing remain open.
D2 work is uncommitted. Results in [merge-plan.md](../merge-plan.md) and
`docs/evidence/ddr-flash-cache-2026-11-10.json`. Integration logs and fixture
hashes live under `scratch/ngage2-integration/d2/`.

## 2026-11-10: D1 overlapping read refinement locally accepted

D1 now returns registered prefix beats as DDR arrives, keeping reserved512B
BRAM for full client stalls. First copy precedes delayed physical tail;
ownership/completion/cache validity wait for the full fill. Busy/reset/drain
contracts retained; delivered prefixes are provisional on cancellation.
Adapter no longer adds a redundant beat register. Default remains disabled;
D1 uncommitted, P0/S1/S2 commit b232f1e unchanged.

Matched synthetic first-beat clocks vs initial full-buffer D1: continuous4/64
5/65→1/1, delayed4/64 25/85→1/1. Final delivery8/128→4/64 and28/148→24/84.
Actual adapter delayed4beat first copy1clock for both retained legacy and
refined D1. No CPU early restart, phone speed or physical timing claim.

Final overlap/full-stall/catch-up/gap/prefix-cancel and adapter staging PASS;
483descriptor oracle,355equivalence,6cache configs, arbiter31/28 and rawNOR/HPS
8/8 PASS. Both new modules Verilog2001, formatter, default/opt-in top and173/9
source graph PASS. Previous9default passes retained. Results in merge-plan.md,
docs/ddr-stream-transport.md and docs/evidence/ddr-stream-2026-11-10.json;
logs scratch/ngage2-integration/d1/overlap/. No other checkout/simulation/
checkpoint operation, commit/push/CI, Quartus build or deployment.

## 2026-11-10: D1 overlap refinement in progress

User requests latency-oriented streaming: return registered prefix beats while
physical DDR tail arrives, retain reserved512B BRAM for arbitrary stalls and
hold descriptor ownership until physical drain plus final logical consumption.
Baseline full-buffer source/evidence snapshotted under
scratch/ngage2-integration/d1/fullbuffer-baseline/. D1 remains uncommitted and
defaultoff; no other checkout/run/checkpoint operations. New latency tests and
updated evidence follow; no early CPU cache-line publication is implied.

## 2026-11-10: D1 transport candidate locally accepted; default disabled

P0/S1/S2 committed b232f1e. D1 implementation remains uncommitted on the isolated
integration branch. New stream transport and legacy adapter provide captured
scalar/line/512B snapshot descriptors,512B synchronous BRAM read buffering and
independent64-bit masked streaming writes. Template leaves D1_STREAM_TRANSPORT=0;
default scalar/ROM cache behavior remains selected. No D2/D3/S3/CPU/NOS ports.

Final PASS: independent483descriptor byte/request oracle (209reads/330writes/
5501beats);355cache-disabled old/new transactions;6ROM cache configurations;
real arbiter31grants/28completions incl24alternating grants/SWP/line/scalar/reset;
opt-in actual raw NOR+DDR+four-slotHPS8reads/8writes, immutable firmware unchanged.
Default9relevant regression entrypoints PASS including full-size C:/PMM reload.
Both new modules Verilog2001,173-file/9-QIP source graph, pinned formatter,
whitespace and default/opt-in structural top checks PASS. CPU180PASS baseline
retained; no new full-phone execution/performance or hardware fit claim.

Busy-held commands survive reset until acceptance; canceled reads drain and
partial writes retain their committed prefix. Loader readback completes while
phone held. Fairness assumes finite locks/producer and DDR/client progress.
No fabricated drain timeout. Wrapper hierarchy changes require fresh simulation
lineages; existing checkpoints/running simulations remain untouched.

See [ddr-stream-transport.md](ddr-stream-transport.md), updated
[merge-plan.md](../merge-plan.md), and docs/evidence/ddr-stream-2026-11-10.json.
Logs/provenance: scratch/ngage2-integration/d1/. No D1 commit/push/CI,
Quartus download/build or deployment. Future default enablement, D2 coherent
cache/D3 bulk consumers and physical timing/persistence require separate work.

## 2026-11-10: P0/S1/S2 committed; D1 implementation authorized

P0/S1/S2 committed on codex/ngage2-integration as b232f1e
(`feat(storage): add raw C and PMM persistence`). No push/CI/deployment.
D1 ownership/stream transport is now in progress in this isolated worktree;
retain the default ROM cache/legacy path, independent buffer/owner descriptors,
scalar equivalence and all raw-save contracts. D2/D3/S3/CPU/NOS/peripheral ports
remain outside this stage. Original checkout, running simulations and permanent
checkpoints remain untouched. D1 source/logs: scratch/ngage2-integration/d1/.

## 2026-11-10: Integration P0/S1/S2 locally accepted

Worktree `codex/ngage2-integration` only, base7f55e939. No commit/push/CI,
Quartus build or deployment. Original checkout, simulations and all checkpoints
untouched. Original NEM-4 firmware/ARM920/timers/NOR and scalar DDR retained.
[merge-plan.md](../merge-plan.md) records results after each authorized stage;
[raw-persistence.md](raw-persistence.md) gives conversion/operator policies;
[integration-baseline.md](integration-baseline.md) records contracts/provenance.

P0: fullCPU180PASS;13/13selected phone suite entry points PASS after stale
fixture repairs (sync-BRAM sample, existing line-interface CPU stubs); missing
immutable core/extension/Micron fixtures copied locally with hashes. Existing
cold/cache-active measurements retained as historical evidence, no new
whole-phone performance claim. Simulator image df6f55924d5f, no network.

S1: lossless NGA split to exact4MiB boot0.vhd/64KiB boot1.vhd plus original
header/hash manifest; join supports unchanged byte-identical rollback and
modified raw payloads with valid original metadata.7/7synthetic conversion
checks and legacy create/inspect compatibility PASS; no source overwrite.

S2: serialized raw manager, independent per-slot mount/rejection state before
verified firmware, both-image CPU gate, raw LBA0, manual Save and dirty-media
protection. TemplateVDNUM4: S0C:,S1PMM,S2reserved,S3diagnostics. Firmware .rom
namespace/overlays unchanged. Actual four-slot HPS28checks/39reads/11writesPASS;
raw NOR+scalarDDR8reads/8writesPASS, immutable firmware20,905,984bytes unchanged;
full-size all1,064,960words restore/reloadPASS. Warm/cold reset, arrival order,
ACK fall, mutation, timeout and live replacement exercised. No autosave/cache.

Next: review these local stages; installed Main automatic mounting, FPGA
fit/timing and physical Save/power-cycle remain unverified. No later integration
stage is implicitly authorized. Logs/evidence: scratch/ngage2-integration/,
build/sim/unit-raw-save-{hps,nor,full}/. No checkpoint migration performed.

## 2026-11-10: Integration work isolated in a dedicated worktree

This chat now uses codex/ngage2-integration in
/Users/andreabogazzi/.codex/worktrees/ngage2-integration/NGage_MiSTer.
The complete [merge-plan.md](../merge-plan.md) and only this chat's plan
notes were moved here. Original checkout returned to master; its dirty
hardware-boot/startup documentation and active simulation remain untouched.
Existing ignored firmware/scratch/checkpoints were not copied. Future builds
and edits use this worktree with separate outputs and recorded source hashes.
No implementation, build, push or commit performed during this move.

## 2026-11-10: Complete donor porting plan; integration branch prepared

User requests one saved plan including semi-real NOS/SIM, all peripheral work,
raw C:/PMM VHD images, DDR/SDRAM and useful CPU ports, with branch-based CPU
comparisons. See [merge-plan.md](../merge-plan.md). Created local
codex/ngage2-baseline at7f55e93982219b8ad5315b785e63be4d4532a756 and switched to
codex/ngage2-integration from that commit; master unchanged. Existing dirty
docs/hardware-boot work preserved, not staged/stashed/committed. Baseline ref
captures committed source only. Before ARM9V2 work, retain another common
integration checkpoint with new peripherals and old ZAP for fair branch A/B.
Final semi-real NOS must retain original startup and meaningful runtime, with
audited selective service substitutes; fully synthetic bootstrap is diagnostic
only. Plan written; no port implementation, tests/builds, push/CI dispatch,
firmware/save changes or running-simulator intervention in this turn.

## 2026-11-10: Memory changes authorized for commit/build; screensaver wake report

Committed/pushed3f5e8ae (line refills, short reads, tests and investigation
notes); exactly one CI build dispatched:
https://github.com/asturur/test_template_1/actions/runs/42880915185
Queued at dispatch; do not monitor unless requested. Worktree was clean. Precommit source graph, imported CPU patch reproduction,
format/whitespace checks pass; full previous CPU180PASS and separate50M runs
recorded below. Simulator harness includes earlier optional Bluetooth diagnostic
controls; no Bluetooth overlay package or hardware boot fix is claimed.

New hardware observation: key wakes clock screensaver to N-Gage image; after
roughly one minute screensaver returns. This confirms some input-dependent
behavior, not menu operation or a reboot. Investigation sequence appended to
symbian-startup.md: second named Menu/softkey after wake, diagnostic captures,
then separate key->matrix/direct latch->ICU25->IRQ/W1C replay and UI/server wait
inspection. Existing cycle counter persists across warm resets, so it cannot
alone disprove reboot. No speculative UI/firmware/C change bundled in build.

## 2026-11-10: Short SDRAM reads complete; actual-controller cold50M PASS

TASK COMPLETE locally. No hardware build, commit or push. Long frozen12B run
container480727160d1a remains untouched; original core/extension/C hashes match.
Existing line-refill work and this extension remain uncommitted.

Template enables SHORT_READS1 with DYNAMIC_LINE1. The bank FSM reserves a BST
command after READ+2 pin clocks, stops chip output after2halfwords, and ends
busy/DQM/dok and bank state early. Writes/full-line reads unchanged. Arbiter
reserves BST so another bank cannot advance on that command slot. All original
register/DDIO boundaries retained; no fitted104MHz timing/resource claim.

PASS existing Docker image: original Micron timing-model short/line/write/mask/
reset/DMA/SWP/refresh tests at78/104MHz and104MHz+0.6ns modeled pin delay.
113 ordinary reads:904->226halfwords (8->2/read). Concurrent mixed-bank600READs:
4800->3000halfwords;8920->8173clocks (~8.4% fewer, synthetic workload only).
Old scalar controller, line transfer/owner/DDR stream tests PASS. CPU imported
patch verification PASS (no new CPU edits since previous180PASS full suite).
Quartus source graph170files/9QIPs, Template format and diff whitespace PASS.

Independent full-phone original-timing-model cold50M COMPLETED:
cycles50000000, bus4851552, errors12 (known startup instruction probes),
data_errors0, lcd_words0, DDR_writes0, fetchPC00006160, busPC00006164,
last_fetch_age9. Cold early cache-off delay loop; this is startup compatibility,
not logo/UI completion or cache-active speed evidence. SDRAM samples verify
firmware RAM pattern writes/readbacks. No ERROR/FATAL/FAIL model messages.
Runtime610.827s. Uses final dok fix, LINE_REFILL1/SHORT_READS1/ROM_CACHE1,
SYS_CLK_HZ104000000. Inputs read from original scratch/hardware-live/ files.

Evidence docs/evidence/sdram-short-reads-2026-11-10.json;
logs scratch/short-reads/{regression,phone-50m,phone-build}.log and generated
build/sim/unit-hardware-boot-real-sdram/. Timed Micron model has only pre-existing
two-state X/Z adaptation; --timing cannot combine with Verilator --savable,
so no new resumable checkpoint was promised/produced for this bounded run.
Main long run retains exact model and checkpoint pairs; fast resumable backing
array harness would not exercise this controller, so was not used as proof.

JTFRAME docs under ~/develop/jtpublicfork/modules/jtframe/doc/ confirm different
per-bank service lengths, global-per-chip physical mode and separate variable-
length burst controller. AW22=8MiB physical bank on32MiB module; AW23=16MiB bank
on64MiB chip. Both logical ports already span same16MiB across two physical
banks; no duplicate RAM. Two-chip128MiB module has shared16bit DQ bus, distinct
per-chip burst modes but no simultaneous independent data streams. References,
measured limits and failed97clock refresh-stress trial in cache-line-refill.md.

## 2026-11-10: Burst/line refills implemented; final50M comparison PASS

TASK COMPLETE locally; NO hardware build, commit or push for this experiment.
User allowance reserve20% remains. Main long panic-owner-fixed-12b confirmed
running; firmware/core/extension/C source hashes unchanged. Every old billion
checkpoint preserved. New code/tests/docs remain uncommitted alongside prior
Bluetooth harness work; no Bluetooth package/overlay fix claimed.

Final line model5271ec5bedfe81c5 (line-refill-on-final-active-50m) and scalar
baseline5a5a4f90dd9ece26 (line-refill-off-active-50m) each COMPLETED exactly50M
additional clocks from4700000002 to4750000002. Both FSR/FAR/ABT LR(RF32)/panic
mask=0, no new bus errors30923398/data0; Nokia image remains.13processes; RfsServer
stack on final contains Nokia/Images/N-Gage5.jp...; no full UI or total boot-time
claim. Raw average I-refill137.37->22.87 clocks (~6x), D-refill136.84->39.92.
Trace micro-op observations4,119,132->5,824,305 (+41.4%); DDR commands722967->252294,
returned64bit beats722967->981072 (more firmware work). Changed C positions during
segment1462->5947; not copied-byte throughput. CPU host simulation rate is NOT
phone speed. Main boot baseline unchanged, no state moved into its directory.

PASS full tests/cpu/run.sh:180PASS total(158CPU cases+22other benches), no XFAIL.
PASS stream/owner/DDR directed tests; actual Micron/controller78/104MHz inverted
clock/capture tests on bothbanks and final32byte boundaries, queued normal read
across mid-line reset, refresh/DMA/word reads/writes. NOR/transport/cache reset/
reload/mask suites PASS, ROM buffer64/128/256bit configs with LINE_REFILL on,
normal hit1clock. Reproducible0055CPU patch verified; Quartus source graph PASS.
No resource/Fmax/timing-closure claim without later Quartus build.

Cache-active snapshot audit and observer1000-clock controls described below;
zero-clock named-state preservation plus exact disabled replay prove migration
for this diagnostic fork only. Cold initial candidate50M completedPC6154/errors12/
data0; early cache-off loop did not test line speed. Superseded first ON candidate
was gracefully stopped alone and retained after late-write admission guard fix.
Final helper formatting after simulation: explicit-port token equivalence and
owner tests PASS; no logic edit after benchmark. SDRAM contract assertions added
only in physical test/backend and verified independently.

Post-change independent3M: FIFO-only26.08%, fetch-only27.84%, both0.38%; actual
WAIT_REFILL8.12% (previous45.04%). Further cache-hit/MMU/LSU/short-read scheduling
work may matter, but current goal remains working phone. User's proposed two
16MiB overlapping logical views already correspond to new line/word interfaces;
physical two8MiB banks remain. Short reads still reserve physical BL8 bandwidth.
Next controller choice: better termination/pipelined long columns or nativeBL2
with pipelined logical256bit line. Plan/limits docs/cache-line-refill.md;
machine evidence docs/evidence/line-refill-2026-11-10.json and scratch/line-refill/.

## 2026-11-10: Final guarded burst model in cache-active50M comparison

Continue current task; reserve20% user allowance, no hardware build. Implementation
still UNCOMMITTED. Final guarded model5271ec5bedfe81c5 (stats included) running
line-refill-on-final-active-50m, session20787, target4750000002 from4700000002.
Baseline off model5a5a4f90dd9ece26 in line-refill-off-active-50m, session80766,
same start/target. Both are audited diagnostic forks, NOT generic checkpoint
compatibility or cold-boot proof. Long panic-owner-fixed-12b remains untouched.

Cold50M COMPLETED initial model12fd8767b26b04d3, PC6154/errors12/data0;
I-cache-off early loop doesn't test refill speed. Current final model fixes
late descriptor-admission ordering beyond that initial cold model.
Superseded ON candidate21f1f6b3aec89215 (line-refill-on-active-50m) was gracefully
TERM'd ONLY by exact Docker command path match. Its state/results retained.
Reason: final owner now rechecks ordinary-bus/write-buffer blockage at acceptance,
not only initial capture. This prevents a newly queued older write being passed.
New owner regression verifies this; no actual guest fault claimed for v1.

Snapshot audit complete: olda6d4 advances2clocks from4.7B to memory/cache/TLB/
writebuffer/CP15 idle. Named state import preserves2255/2256 common fields,
including complete CPU/RAM/DDR/cache/TLB payload. New idle owner/provider/raw
reader regs initialized; only combinational old aliases removed/renamed. Exact
zero-clock read matches ALL common named fields; disabled path matches original
1000clock control (all2256 fields AND host bytes). Added passive stats observer
matches prior disabled CPU AND host files byte-for-byte after1000clocks.
Generated evaluator temporaries are not copied; this proof checks trajectory,
not just serializer layout. Reports/scripts scratch/line-refill/{schema-*,
migrate.py,compare-fields.py,quiesce.cpp,profiles.json,final-profiles.json}.

PASS final directed engine/owner/DDR tests; physical SDRAM line reads bothbanks
and their last32byte boundaries, queued normal read across mid-line warm reset,
normal32bit reads/writes/DMA/refresh at78/104MHz inverted pin/DDIO capture.
DDR ROM cache reset/reload suite PASS with LINE_REFILL0 and1, hit latency1.
Original reset-stage suite caught wrapper wrongly rejecting normal queued
requests while old reads drain: fixed normal cache admission; raw-line admission
still waits for ordinary backend drain. Existing transfer/refill/access and
NOR/transport suites PASS. Full tests/cpu/run.sh still running session35578,
log scratch/line-refill/cpu-suite.log; don't assume complete until exit.
Patch0055 reproduces all imported CPU wrappers/top changes; verify.sh PASS.
Quartus source graph PASS (170files/9QIPs). No Quartus build/timing claim.

Implementation contracts and logical16MiB overlapping-port follow-up in new
docs/cache-line-refill.md. Current two physical8MiB banks retained; two logical
interfaces cover same16MiB. BL8 short reads still consume unused physical beats;
further pipelining/termination or BL2 streaming is follow-up, not completed.
Next finish final50M A/B metrics/stopping-point inspection, final format/lint/
regression checks. Do not accidentally commit prior Bluetooth observer/menu
harness work as a Bluetooth fix. Source firmware/C input hashes must remain same.

## 2026-11-10: Burst refill implementation IN PROGRESS — no hardware build

User requests line/burst refills,104MHz-conscious registers, tests and separate
50M speed comparison; long sim and firmware/C source inputs untouched. Reserve
20% remains current. No commit/push or hardware build for this experiment.

New optional LINE_REFILL channel after ARM920 MMU/cache ownership: registered
I/D line arbiter, streams16/64bit beats into EXISTING cache_transfer refill_line.
DDR raw four64bit burst beats bypass tiny instruction buffer; flash array-mode
probe preserves NOR/status fallback, per-address decode still applied. SDRAM
adapter streams raw16bit DQ directly, avoiding its32bit word assembly. Jotego
controller extended for legal128bit BL8, two reads per32byte line; normal32bit
requests retain short rdy plus full physical DQ reservation. Default feature0;
Template selects1, full-phone runner opt-in --line-refill. New tests and many
interface updates UNCOMMITTED. Prior Bluetooth harness changes still pending.

PASS new stream engine, DDR line burst/reset-drain/normalcache test; existing
cache transfer/refill/access tests; legacy physical SDRAM/NOR; physical line
reads bothbanks incl shortread/write/DMA/refresh at78/104MHz inverted DDIO capture.
Sources/logs scratch/line-refill and tests/phone/line_refill. DDR ROM cache suite
currently investigating blank run log, don't mark it passed. Need full CPU tests,
source graph/patch reproduction and top lint still. No FPGA timing closure claim.

Cold50M initial transport model12fd8767b26b04d3 running separately as
line-refill-cold-50m (session84751), current30M no faultincrease; early uncached
ROM loop doesn't meaningfully test new refill speed. Source formats/harness
have since changed, so keep exact model identity and don't silently resume as
current. Cache-active quiescent source from4.7B saved scratch/line-refill/
quiet-4700m.{cpu,host}: +2clocks, all CPU requests/cache/TLB/writebuffer/DDR/flash
paths idle, old frozena6d4. quiesce.cpp/log retained. Must audit named-field
migration and original-model equality before using it for current50M A/B runs.
Migration NOT implemented yet; don't claim upgraded checkpoint compatibility.

Next user steering AFTER current burst tests/measurement: investigate two
logical SDRAM request ports over SAME16MiB (256bit refill vs32/64bit shortread),
distinct from physical SDRAM bank mapping. Do not silently remap physical banks.

## 2026-11-10: Keypad fix pushed/built; refill audit complete; limit updated

User explicitly changes allowance reserve to20% for tomorrow; prior35% pause
was overnight-only and is REVOKED. Continue authorized work, no passive polling.

Keypad commit e4c897e PUSHED. Single hardware build DISPATCHED:
https://github.com/asturur/test_template_1/actions/runs/42854188526
No build monitoring. scratch/post-nokia-startup/keypad-build.json. Real ARM/UPP
regression now includes matrix/direct key injection through a test-only SDRAM
mailbox, status/ICU source25 checks, low/upper-byte W1C and IRQ deassertion:
PASS alongside existing LCD/DMA/IRQ/FIQ/diagnostics tests. Host/matrix/board,
NOS/peripheral-response PASS; pinned formatter/source graph/diff checks PASS.
Hardware fix still unverified; KEYS HELD changing was confirmed by user.
No source firmware/C edits. Long baseline12B remains running, latest one-time
progress5.12B, errors30923398 unchanged/data0. No state migration/restart.

Separate frozen3M refill audit COMPLETED:9884fills,79072words,3303distinct32byte
lines (~103KiB touched),0global I-cache invalidation/disable clocks. Fill136.70
clocks average:8serialized words at15.96clocks each plus9coordinator clocks.
Per word13.28inflight waiting,1.69before inflight,1ack. About90% refill waits
physical003xxxxx ROM. Raw modeled DDR delay all clients only4.85% of clocks.
Working-set churn and eight registered transactions per line dominate measured
fetch wait; no claim of an ideal miss rate or proven replacement-policy defect.
Next candidate is line/burst transaction assembly preserving104MHz registers;
NOT implemented yet. Detailed limits docs/symbian-startup.md; scratch/
post-nokia-startup/{evidence.json,refills-4700m.log,refill-reuse-4700m.log}.

Pending uncommitted hardware_boot runner/tb/observer files are prior Bluetooth
matrix work. Do NOT bundle them into keypad fix or pretend they fix Bluetooth.

## 2026-11-10: Keypad IRQ acknowledgement defect fixed locally; stalls decomposed

USER LIMIT reached: account65% used/35% remaining. Pause active investigation
per standing user limit; keep long sim running. No new simulation/build/commit
started after detecting limit. Resume state recorded below.

Hardware now reaches Nokia screensaver/clock band, no controls work. User
confirms KEYS HELD changes with OSD closed. Input wires/enables intact. Actual
board regression FAIL reproduced: keypad W1C at0C150100 never committed because
gpio_access excludes NOS owner. Keys latch shared source25 forever after press.
Fixed LOCAL rtl/ngage_upp_peripherals.v keypad_access: accepted valid NOS-owned
status writes also acknowledge keypad. No NOS storage/IRQ masking bypass.
New tests/phone/keypad/board_tb.v checks all6direct keys, byte lanes, held level
and IRQ clear. Full host/matrix/board tests PASS; NOS and peripheral-response
regressions PASS. Before/after/final logs scratch/post-nokia-startup/keypad*.log.
NO hardware response claim, full boot replay, commit, push or build yet.
Existing uncommitted hardware_boot runner/tb/observer edits are separate prior
Bluetooth work; do NOT accidentally include them in the keypad fix commit.

Separate exact frozen3M from4.7B decomposes code_stall with runtime equality
assertion: FIFO-only566028 (18.87% all clocks), fetch-only1679680(55.99%),
both12026(0.40%), neither742266; uncached-store guard0. I-cache WAIT_REFILL
1351156clocks(45.04% all clocks), biggest fetch contributor. TLB busy overlaps
83875clocks; data stalls overlap461557. Full FIFO is downstream backpressure,
not slow ROM. Eight32-bit serial transfers refill each ARM92032byte line;
not the same as DDR ROM buffer64bit lines. No performance HDL changed.
Detailed raw scratch/post-nokia-startup/stalls-4700m.log, source stalls.cpp.
Next refills.cpp/executable PREPARED but NOT RUN, to count transfer phases,
physical regions and ACKs from the SAME4.7B checkpoint for3M. Use Docker existing
image/exact frozen a6d40d0d5005ce63. No source/checkpoint rewriting or long-run
restart. Topic docs live-controls.md and symbian-startup.md updated.

## 2026-11-10: Post-Nokia audit: factory files advancing, no new panic

User hardware reaches N-Gage with skips/overlays OFF; next NOS-ON trial failed
before it, now retrying OFF. No exact overlay cause or completed UI claim.
Fixed12B sim remains untouched/running, latest checked progress4.81B, latest
complete pair4.8B. Screen remains Nokia. Original firmware/C source hashes and
4.7B checkpoint hashes verified unchanged.

Independent frozen-HDL3M replay from4.7B plus zero-cycle4.5/4.6/4.8B reads:
RfsServer factory paths advance CACerts.dat -> Pictures/2.ota -> N-Gage5.jp...
(dump boundary truncation); simulated C differing-byte positions25740 ->35775
->39912 ->57887. Not a demonstrated stuck scan: old scan-loop probe never fires.
EFile main owns~74% sampled clocks; IRQ/FIQ~7%, code-side stall75.3%. Separate
1M probe has only0.52% C-bus pending,4.50% modeled DDR delay,127 bytes changed.
Observed cost is predominantly firmware/CPU/filesystem work rather than raw
C backend waits in that sample; no speculative performance/HDL change made.
Bus errors30923398 unchanged/data0. Working UI not reached in this evidence.

Critical pitfall: inspect inactive user stacks via home chunk_base/HOME_STACK;
VA00400000 through current mapping can show another process (btldd.LDD) and
falsely suggest repetition. Details/limits docs/symbian-startup.md, evidence
scratch/post-nokia-startup/evidence.json and passive profiler sources/logs.
Next track real copy completions/server progression; if it stops, trace pending
request. Later export populated C as NEW image for hardware, preserve original
and consistent PMM; no export performed yet.

Previous Bluetooth matrix remains separate, original packages untouched;
private observer-watch profiles recorded scratch/bluetooth-boot/active-runs.json.
Uncommitted hardware_boot runner/tb/observer work predates this audit and enables
actual BT loader/full-phone comparisons and auto-stop probes; NOT a BT fix.
Hardware Bluetooth question deferred by user while watching unmodified boot.

## 2026-11-10: Panic fix pushed; hardware build dispatched

Code fix11dea96 pushed. User-authorized single hardware build started:
https://github.com/asturur/test_template_1/actions/runs/42831052811
No build monitoring. Firmware/C inputs unchanged; fixed continuation toward12B
active with100M screenshots. Bluetooth overlay pre-logo regression remains OPEN;
keep BT OFF for initial validation. Detailed evidence and completed verification
follow below. Dispatch record scratch/hardware-fault-47f0/hardware-build.json.

## 2026-11-10: First phone panic fixed and verified; push/build authorized

User explicitly requests commit/push and ONE build when sure, no confirmation.
Functional fix VERIFIED; dispatch ci_build.yml after this commit. Do not monitor
GitHub build. Build reference goes in scratch/hardware-fault-47f0/hardware-build.json.
Main objective remains working phone; no full UI or hardware-fix claim yet.

OPEN SEPARATE REGRESSION: Bluetooth overlay ON blocks before Nokia logo (user
reconfirmed). NOS/BT both OFF in verified baseline. This P2 fix does not establish
that the Bluetooth overlay works. Investigate overlay loading/hooks next; keep
BT OFF for initial hardware test. C: and UI stubs are not authorized substitutes.

First e986 ABT at4372559219: STRH5038524C -> VA59893FE0, FSR1D,
LR_abt50385254/SPSR_abt400000D1. Descriptor0240043A AP1/domain1 grants FIQ
write. Close replay captures P1mode10/P2mode11/P1force0: CPU wrongly exported
P1 privilege with P2 address/data. A following exception return restored user
mode in the younger stage before the privileged store. Fix BOTH o_data_cpsr
and o_mem_translate to existing P2 registered fields. No added waits, removed
register, permission-rule change, firmware/C input rewrite or peripheral stub.

Proof: close source4372558010, old abort1209clocks later, CPU state BYTE IDENTICAL
to original first-abort capture. Fixed10k completes the write (simulated C: word
FFFFFFFF->00000001 plus subsequent data), returns to startup, FSR/FAR/ABT LR/
panicmask0. Fixed additional50M COMPLETED4422568010, PC503A2310, same zero
exception/panic state, old bus counter30923398 stable/data0.13processes now,
new BTTestServer after RfsServer, versus12before failure. Nokia still displayed;
no working UI claim. Original firmware/core/extension/C source hashes unchanged;
only firmware-directed writes to the simulated working flash.

Verification COMPLETE: full CPU suite180PASS/no XFAIL; final targeted0/3.
New data_privilege_owner.S warms protected stores before SVC return and requires
LDRT inside SVC to fault as USER. Original wiring wrongly grants that LDRT ->D2;
identical assembled program bytes pass fixed0/3, recovering from expected
FSR1D/FAR59800100. Initial isolated reference mistakenly read shared ROM and
failedD6: INVALID. Final isolated TB/program paths fixed, D2 is valid evidence.
Patch0054 reconstruction/source preflight PASS. Separate cold50M modela6d4
completes normally, PC6154,12known initial bus faults/data0. Registers/timing
boundaries retained; hardware closure still requires the build's measurement.

Audited close migration scratch/hardware-fault-47f0/migrate-owner.py:
quiesce-close explicitly requires P2request0, CP15idle, both write buffers empty,
caches/TLB/walks/external buses idle; +10clocks from old4372558000. Whitelist
preserves17067 common fields/all CPU/RAM/DDR/cache state;20D/19I typed mapping
imports, new permission tokens invalid. New P2 force-user bit0 only while owning
memory request inactive; new panic diagnostics invalid0. Source roundtrip/hash
and old control replay exact. Initial4.3B TLB-only exploratory import was NOT
fully quiet (missed a new P2request); don't use as final proof. No original
checkpoint overwritten; diagnostic migration is not arbitrary compatibility.

Fixed strict continuation RUNNING: build/sim/runs/panic-owner-fixed-12b/,
from panic-owner-fixed-50m/checkpoint-4422568010, target12B, session82873.
Exact frozen model a6d40d0d5005ce63; automatic100M checkpoints/screens under
build/sim/screens/panic-owner-fixed-12b-checkpoints/. Launch log
scratch/hardware-fault-47f0/owner-fixed-12b-launch.log. Old e986 panic-loop run
received graceful TERM after proof; its checkpoints retained, screenshot sidecar
exits on result.json. Old retry-loop65ea run/checkpoints also retained unchanged.

Evidence docs/evidence/phone-panic-owner-2026-11-10.json; detailed contracts and
limits docs/{symbian-startup,cpu-patches,arm920-tlb}.md. No hardware build started
as of this entry; user authorization explicit and pending dispatch after commit.
One pre-dispatch check of completed build42820357005: synthesis succeeded,
CPU78MHz setup+0.364ns; ONLY failing summary is stock HDMI scaler -0.151ns.
No unrelated scaler/clock change made; next build measures this code's fit.

## 2026-11-10:100M screenshots enabled; corrected sim panic at4.4B

User requested100M screenshots and a latest-checkpoint image without stopping
the long sim. Added tools/capture_sim_checkpoint.py plus a zero-clock C++ reader
linked to each checkpoint's exact frozen HDL archive. Existing binary/container
identity checked, source CPU/host hashes verified unchanged. No HDL, serial
layout, firmware or C: change. Native176x208 framebuffer+scanout PNGs and JSON in
build/sim/screens/<run>-checkpoints/. Separate folder avoids colliding with a
legacy runner's terminal-directory creation. No raw PPMs retained.

Future run-logo.py CHECKPOINT callbacks invoke the reader; failures do not kill
phone simulation. Existing long run remains unchanged; independent --watch
renderer session35936 creates screenshots for each completed pair, no agent/log
polling. Its log scratch/hardware-fault-47f0/checkpoint-screens.log. It exits on
run result.json.4.3B and4.4B screenshots saved, both still Nokia logo.

Verification: separate checkpoint-screenshot-zero strict4.2B continuation with
zero cycles matches original CPU AND host byte-for-byte; both checkpoint PNGs
match original4.2B terminal PNG SHA256. Runner callback/end processing passes.
Python syntax/diff checks PASS. No hardware build launched.

NEW BOOT EVIDENCE:4.4B e986 corrected lineage is now at50324294/CPSR600000D7,
the SAME final panic loop observed on hardware. Exact original hardware cause
not yet established. Zero-clock read of4.4B shows CP15 FSR1D/FAR59893FE0;
superpage40000418=5038524C,1C=59893FE0,10=10000000. No new backing-bus errors
(30923398)/data bus errors0: architectural MMU fault is distinct from bus errors.
Special reason10000000 at50333e88 skips category copy, preserving exception
context PC/address in the report words. Previous blanket "not PC" prose was
incomplete; decoder and docs now distinguish this special packet. A synthetic
NGD packet matching these values decodes PC/address correctly.

Separate exact frozen observer from4.3B is running with100M cap, stopping on
first ABT entry/new bus error/panic and preserving forensic CPU/host pair;
session91737, scratch/hardware-fault-47f0/first-abort-from-4300m.log. Original
long run, source checkpoints, firmware and C: inputs remain untouched. Next
inspect the first architectural fault and decide whether current64-entry TLB
fixes that ownership/permission failure; do not silently migrate old state.

## 2026-11-10: Working-phone priority; hardware panic recorder verified

User confirms hardware RBF40bfc11, before64-entry TLB replacement. Main goal
is Symbian startup, not speculative performance changes. Current original
hardware exception is UNKNOWN; Bluetooth pre-logo failure is separate evidence.

Pristine firmware ARM disassembly refines the panic report:50333e70 copies
up to8category bytes into40000418/1c and reason into40000410;50324240 sends
category to0C0047F0/F4 and reason toF8, then parks at50324294. Entry50333e68
adds10000 to reason. The words are NOT the original PC. Trace evidence under
scratch/hardware-fault-47f0/{category-reason,ekern-abort}.txt.

Added passive panic-write observation in trace_sink, no ownership/ACK/validity
change. Dedicated first-word latches in diagnostics survive ring wrap/freeze and
warm reset; partial writes do not become complete words. Cold reset clears.
Screen bottom PANIC row shows three words+valid mask, coherent4Hz snapshot.
Optional backward-compatible NGD metadata396..403 + Python decoder return
category/reason; missing fields remain null. Panic wins simultaneous unknown
LCD event; collision still counted as dropped. No firmware/C/overlay changes.

PASS trace sink (uncommitted reporting attempts, held suppression, adjacent
words, read rejection), diagnostic validity/first-word/freeze/clear, pixel-exact
raster and snapshot isolation, decoder/export ring and real hps_io virtual-disk
protocol. Actual HDL ARM/UPP/board integration PASS including report stores and
readback, display/DMA, IRQ/FIQ and waited SDRAM. Pinned formatter and source
preflight PASS. Host export recipe's final Verilator step was run inside existing
Docker because local Verilator is unavailable; same HPS test passed. No hardware
build or physical104MHz timing claim.

Read-only corrected4.2B state has12processes incl RfsServer, CP15 FSR/FAR and
ABT LR/SPSR zero, report words zero. Separate matching1M continuation has no
new errors/aborts and active bitmap/pixel code; forensic watch.cpp can stop/save
on first new error, ABT entry or final panic PC. Observer not normal scanout
lineage. Long corrected run remains active, latest4.3B checkpoint checked (12processes, active EwSrv), errors30923398
unchanged/data0. Original inputs/checkpoints untouched. No claim of working UI.

Next board test latest TLB+recorder with NOS/BT OFF; obtain PANIC category/reason
before implementing speculative peripheral behavior. Old FIQ/store-return test
D1 was a FAIL marker, not independently proof of an architectural abort or the
same board cause. See docs/symbian-startup.md for current evidence and limits.

## 2026-11-10: Source-check fix; corrected4.2B continuation running

GitHub42815908409 fails BEFORE synthesis: tools/check_quartus_sources.tcl
reuses required (file dictionary) as foreach loop variable for the three new
cache/TLB sources. Final dict size then errors "missing value to go with key".
Renamed loop variable required_source; tclsh preflight including --list PASS.
No local Quartus installation/download, no new hardware build launched.

At user's request stopped ONLY old Docker3e48c44d/fervent_golick. Existing
billion CPU/host checkpoint pairs remain intact; SHA256 inventory saved under
scratch/hardware-live/stopped-old-sim-checkpoints.json.
Started icache-discard-recovery-12b from corrected4200000000 paired checkpoint,
strict --use-saved-build e9861e744de45ca0, matching inputs/profile, target12B,
100M checkpoint cadence. No latest MMU/TLB changes silently applied; this is the
compatible diagnostic-fork continuation. Original firmware/C inputs untouched.
Launch log scratch/hardware-live/recovery-12b-launch.log.

Hardware investigation: independent ARM disassembly of pristine NEM-4 SYM.ROM
confirms50324240 reads superpage40000400+18/+1c/+10 and sends those three words
through503245bc (STR r0,[58000000+r1]) to offsets47f0/47f4/47f8; then reset/
doorbell writes and final B50324294. Screenshot fetch50324294 is therefore a
firmware panic terminal loop, not merely slow startup. Captured fault-fetch
503245c0 is exactly the STR in that reporting helper. Original exception cause
is still UNKNOWN; diagnostic screen's DATA FAULT may be a secondary reporting
failure. Evidence scratch/hardware-fault-47f0/ekern-abort.txt. Source scratch
has45words, final word47f8, final byte47fb;
old boot-model prose ending47e3 was stale. Strict unknown-byte rejection remains.
Screenshot FAULT FLAGS visually rechecked as00011234 (not earlier transcription
00011624): read/code0, boardclaim/ready/unmodeled and memreq set. This disagrees
with the helper's STR; current hardware RBF identity and original saved crash
words are needed before attributing the mismatch to a specific RTL stage.

## 2026-11-10: Long-run6B audit and live hardware stop

Read-only inspection of the frozen65ea long-run checkpoint6000000000 confirms
PC50300B06, CPSR08000030, data_errors0. Host ticks6000016390; observer cycle
1705032704 is the wrapped32-bit counter, not current total progress. It remains
in the known discarded-I-refill retry deadlock first observed around3.57B.
This frozen executable does not contain the subsequent discard/MMU/TLB fixes;
waiting for12B cannot test those fixes. Long run and checkpoints left untouched.
Evidence scratch/hardware-live/long-sim-6b-status.log.

The separate corrected-discard fork icache-discard-recovery-4200m completed4.2B,
passed the old deadlock and launched additional startup servers; Nokia frame,
no demonstrated Symbian UI. It does not include the latest MMU/TLB improvements.

Read-only live Zaparoo screenshot captured at12:28UTC:
scratch/hardware-live/hardware-stop-2026-11-10T12-28-08-204Z.png (+JSON).
Current RBF revision/overlay selection not independently established. Screen:
fetch50324294, CPSR600000D7, sticky DATA FAULT0C0047F0, captured fetch503245C0,
reason1, flags00011234, bus errors127. Captured fetch is not a precise fault PC;
sticky fault may predate current activity. This differs from frozen sim50300B06.
User reports NOS OFF/ON both reach this hardware stop; Bluetooth ON blocks before
logo. These are board observations, not yet reproduced in the latest model.

## 2026-11-10: ARM920T64-entry TLBs verified; production cache only

LATEST TASK COMPLETE; user now requests commit/push and will launch the build.
User requested64-entry mixed-size fully-associative I/D TLBs,104MHz-conscious
stages, remove old cache, full tests+separate50M boot/scan comparison, preserve
long sims and no hardware build. Final phone model27535b46216966c0.

New rtl/arm920/{tlb.sv,tlb_bank.sv}: separate64-slot I/D pools, all page sizes,
grouped8x8 staged CAM selection and explicit64x38bit BRAM payload (pads40bits),
1KiB checked permission token, full direction/context ownership. CP15c8 all/
MVA invalidation and c10 independent I/D base/victim/P/readback implemented,
with preserve separate from replacement lockdown. Correct coarse/fine indexing,
AP/SR/domain/CB, no negative descriptor caching, proper table external aborts,
cancelled-walk draining. Whole-page masks prevent duplicate/overlapping hits.

Old cache FSM/tag storage, split TLB/walker/checker and their unused RAM helpers
DELETED from rtl/arm and QIP. CPU branch-predictor RAM helper remains needed.
Production adapter/file/instance names arm920_cache_adapter/cache_adapter;
all NGAGE_ASSOC_EXPERIMENT and CPU_ASSOC_EXPERIMENT toggles removed. No legacy
cache is compiled or available as a normal build choice. ZAP wrappers remain
CPU integration glue. Patch0053 records imported-source changes/deletions;
verify.sh now uses patch -E to actually remove empty deleted files. Pinned
upstream+0001–0048,0050–0053 reproduces rtl/arm byte-for-byte (PASS).

Verification COMPLETE:
- tests/cpu/run.sh EXIT0,177 PASS lines, no XFAIL. Former fiq_store_return D1
  now passes0/3. Warm cached ADD remains1clock. Tests cover SWP/LDM, FCSE,
  alignment, permissions/aborts, prefetch, locks, buffer ordering, maintenance.
- Enhanced CPU tlb_lockdown program verifies independent BOTH I/D c10 writes/
  readback plus D preserved-entry/MVA invalidation; targeted0/3 PASS after suite.
- Directed bank all64 mixed entries/65th victim/base/P/all/MVA/cancellation,
  controller four sizes/CB/fine index, permission truth table, table aborts and
  request/AP1KiB ownership tests PASS.
- Whole-top structural elaboration and Intel SYNTHESIS BRAM primitive-path lint
  PASS; QIP paths/Python syntax valid. No Quartus fit/Fmax claim or hardware build.

Final cold run build/sim/runs/tlb64-final-cold-50m/ COMPLETED50M,00006154,
12known initial bus faults/data0. Still early pre-LCD; no full UI boot claim.
Normal CPU/host checkpoint50000000 and screens under matching build/sim/screens.
Matched scan from quiescent2,000,000,027 +50M:
- prior8877 handshake-only:3748reads, median11430clocks,8block exits;
- final2753:4484reads, median9512clocks,9block exits;
- throughput+19.64%, median latency-16.78%. Both0repeats/backwards,12errors
  unchanged, data0. First56 C-bus address/data pairs match.
- final main lookup/walk counts: D1,225,255/33; I769,505/24. Real table conflicts
  effectively removed in this window; local token/context and cache/CPU cost remain.
- terminal fetch0 was inactive (instr_valid0), last trace503393F8. Diagnostic
  terminal pair scratch/tlb64/scan-final-50m.cpu/.host resumes100k normally,
  7more reads/no new faults; fetch50329D28 afterward. No stuck-zero-PC problem.

Final scan uses AUDITED diagnostic migration, not arbitrary compatibility:
quiesce.cpp advances27clocks from previous audited2B/8877 copy until caches,
TLB/walker/external bus/pending/CP15 idle. migrate-final.py preserves17068
common fields with explicit experimental_cache -> cache_adapter name mapping,
recomputes generated comb scratch, imports20D/19I valid mappings incl AP/domain/
CB into new pools, asserts no overlap. New permission tokens invalid; RR after
imported entries; source CP15r10=0. Whitelist/hashes/import records in
scratch/tlb64/{schema-final-diff.json,scan-final.migration.json}. Original2B,
firmware and C input hashes reverified unchanged. Shared profile78MHz CPU,
26MHz timers/NOS64(experimental), ROM64bit1KiB/directSDRAM, no overlays.
Observer scanout not collected; diagnostic pair is not a maintained runner lineage.

Initial model0238 exposed a real CPU prefetch-restore regression after77passes:
P_RESTORE waited for removed lookahead/check-stage addresses. It now restores
from the current request token. Final source was rebuilt and fresh cold50M/
scan50M rerun (no relabeling initial result). Failed logs retained to avoid repeat.
All task workers/event wait g3:310 completed; no monitoring process left. Original
long run65ea executable/checkpoints untouched. No GitHub action/build launched.

Report docs/arm920-tlb.md + docs/mmcstore-scan.md;
measured evidence docs/evidence/tlb64-2026-11-10.json;
logs/artifacts scratch/tlb64/. Future performance notes in
cpu-performance-redesign-notes.md: direction-aware permission grants/token churn
and old D-wrapper pending_translation/lookup_resync sequencing, not implemented.
Next: user builds the pushed changes; collect hardware/timing evidence when supplied.

## 2026-11-10: MMU ownership fix verified;50M scan throughput +42.73%

User requested fix with104MHz-conscious registers, tests+boot>=50M, matched
C-scan comparison; long sims untouched, no hardware build. Implemented in
zap_tlb plus I/D wrappers. Lookup/check ownership includes minimum1KiB permission
granule, read/write direction, mode/SR/DAC/MMU/TTBR context. Current low10bits
supply physical offset; MMU-off identity. Recovery clocks existing lookup stages
while stalled; three post-fill/invalidate clocks prevent stale miss reuse.
In-flight invalidation/TTBR cancellation drains without stale installation.
Instruction lookup wait is distinct from err2 retry; treating both as retry
caused permanent fetch redirects at000000FC. No RAM/check register removed.

PASS focused ownership test: exact2beat warm/miss, stale lookups, adjacent fetch,
1KiB permission boundary, held fill, in-flight invalidate/TTBR, direction/mode,
MMU-off. Original policy FAILS same test (warm4beats). CPU timing0/3 PASS, warm
ADD1clock. Broad suite38 PASS lines then same known fiq_store_return D1; separate
suffix132 PASS lines and expected legacy associativity XFAIL, completed normally.
Do not claim full suite passing. All evidence in scratch/mmu-handshake/.

Three isolated experiments COMPLETED normally:
- Frozen65ea checkpoint2B+50M:2626reads, median16165clocks,6block exits.
- Corrected8877b43014f2eba6 same state+50M:3748reads, median11430clocks,8exits.
  Both0repeats/backwards, errors12unchanged, datafaults0. Throughput+42.73%,
  median latency-29.29%. Additional first40 C-bus address/data pairs match.
- Maintained cold50M: build/sim/runs/mmu-owner-cold-50m/, checkpoint50000000 pair,
  PC00006154, known12earlybusfaults/data0, pre-LCD loop. Not a full UI boot proof.
  Screens build/sim/screens/mmu-owner-cold-50m/.

Additional fixed2M probe:151reads;7006 D walks,1resident inherited old in-flight
walk conservatively discarded;5936 I walks,0resident. Real direct-map conflicts
remain. Profile unchanged78MHz CPU/26MHz timers/NOS64/ROM64bit1KiB/directSDRAM,
stock firmware and C sources (hashes reverified). No overlays in these runs.

Fixed scan is an AUDITED diagnostic COPY of old2B, not arbitrary checkpoint
compatibility. Named-field migration preserves17709common fields/all original
architectural/cache/TLB/memory state and identical host. New recovery state
initialized conservatively;4 newly materialized I-TLB forwarding buffers recover
old *_wdata aliases; generated combinational scratch recalculated. Exact whitelist
and SHA in scratch/mmu-handshake/{schema-final-diff.json,migrate-scan.py,
scan-2b.migration.json}. Source2B CPU hash rechecked unchanged. Observer scan run
has no terminal maintained checkpoint; cold run does. Event wait g3:234 completed
all3 experiments and CPU suffix. No monitoring loop left for this task.

Patch0051 captures already-committed abandoned-refill fix6a52522 omitted from
prior series;0052 captures MMU change. patches/zap/verify.sh PASS from cached
pinned upstream. No new timing closure claim:104MHz needs future Quartus reports.
User now requests commit, push and one hardware build. Original long sims untouched.
Report docs/mmcstore-scan.md; docs/evidence/mmu-handshake-2026-11-10.json.
Next: collect the requested hardware build timing; address real TLB conflicts or
remaining firmware startup blockers separately. Prior build42781963807 user monitored.

## 2026-11-10: C: scan cost traced to redundant MMU walks

Isolated exact frozen65ea checkpoint2B->2.002B observer replay:105 complete
one-byte reads, median16165clocks,105 unique records/no repeats. C: bus pending
only8832/1724159 read-call clocks (0.51%). D-cache accepted47087requests,
448.45/read. No maintenance, TLB invalidations or TTBR changes.

Actual TLB RAM valid+tag at walker start:31696/36627 D walks already resident
(86.54%);10682/16002 I walks resident (66.75%). Redundant-resident walk intervals
occupy624262/1724159 complete-read clocks (36.21%, I/D union). This is occupied
time, NOT a measured optimization gain. D refill-write suppression by hold was
checked:0 blocked; reject that hypothesis. Existing direct-map conflicts cannot
explain refetches of currently resident entries.

Mechanism: zap_tlb checker uses i_address_check and registered RAM lookup of
an earlier i_address_nxt, but FSM starts from idle+walk and captures current
i_address without matching lookup ownership. At2B, current80601868 is resident,
lookup/check00010000, stale walk=1. Data request admission has ownership checks,
walker admission does not. Small standalone full-TLB HDL reproducer confirms
redundant reads with no Nokia firmware (scratch/startup-fault-audit/
tlb-stale-lookup.sv, tlb-stale-test.log). Scratch-only address qualification plus3 enabled post-fill settle clocks passes
local stale-lookup/no-extra-reads and genuine-new-miss2beat control. This is NOT
a full CPU fix: caller fault/completion ownership, held pipeline, context and
CP15 prefetch remain unverified. Maintained HDL untouched in this investigation.

Next: qualify walker admission and fault/completion ownership coherently;
retain registers, real misses, permissions, context/TTBR invalidation and CP15
prefetch. Instruction/data wrappers differ: do not blindly gate both or allow
stale physical data to complete while a walk is suppressed. Directed regression
plus isolated>=50M firmware benchmark required before adoption. Firmware/C input
and long sims untouched; no extra hardware build. Full report docs/mmcstore-scan.md,
evidence/drive-scan-tlb-2026-11-10.json. Observer sources/results in
scratch/startup-fault-audit/scan-tlb-{writes,resident,cost}.{cpp,log}.

Hardware deadlock fix already committed/pushed6a52522 (observer cadence44f72c8).
One build launched: actions/runs/42781963807. Leave build monitoring to user.
Corrected replay reached4.1B with SplashScreen, SelfTestServer and EInfoServer;
no new bus/data faults, Nokia image still last observed. UI not verified.

## 2026-11-10: confirmed speculative-fetch deadlock; corrected HDL recovers

Read4B writeback pending redirect: shelve_ff=1,pc_shelve_ff=503EF43F.
Thus BX return has resolved CORRECTLY; bad50300B06 is a wrong-path fetch, not
proof of an architecturally executed literal or corrupted return. Existing
cacheable refill policy retries every bus error indefinitely, so code_stall
never clears and writeback cannot apply its pending correct return. ARM920T
DDI0151C3.8 only allows external aborts for noncached reads/unbuffered writes/
noncacheable SWP; preserve live cached demand/data retry policy.

Fix: expose already-registered writeback shelve to instruction cache only,
excluding explicit CP15 prefetch. On a failed AND discarded refill, return a
completion without installing any line. CPU instr_valid already masks shelve,
so discarded data is never accepted. No new architectural abort, data-cache
policy change, ROM/C bypass, timing-chain removal or firmware patch.

Full corrected HDL e9861e744de45ca0 resumed from an explicitly migrated COPY
of4B stuck state. After1000clocks PC503276C0; bus errors increased only once,
30,923,397 ->30,923,398, data faults0. Extended strict new-lineage50M replay
build/sim/runs/icache-discard-recovery-4050m/ is running; at4.03B different
kernel/user PCs, same bus-error count, no data faults. Full UI not yet claimed.

Migration audit: scratch/startup-fault-audit/migrate-snapshot.py preserves
17844 named fields, zero-initializes only the newly observable I-refill-error
register, removes6 unused NBA RAM temporary fields optimized out by current
bench. Original CPU/host files untouched. Decode/re-encode roundtrip matches
source bytes. Separate clean pre-failure1000-cycle old-vs-new continuation is
BYTE IDENTICAL after the same schema conversion for CPU and host (zero differing
bytes): migration-clean-proof.json. This is a reviewed diagnostic fork, not
permission to load arbitrary old checkpoints into changed HDL. Source/target
hashes and field whitelist stored in each migration report.

Focused adapter/cache test tests/cpu/icache_discard proves live permanent errors
still retry, queued-discard completion arrives without err, and failed data is
not installed (next live read performs all8beats). Original retry policy FAILS
same test; fix PASS. Existing cache access, buffer integration, demand completion
PASS. Full tests/cpu/run.sh passed38 checks then stopped at fiq_store_return (D1 abort).
That SAME case fails with the original retry policy; it is an existing separate
FIQ/data-translation issue, not a passing full regression. fiq_privileged_ldrt
control passes0/3 with original policy. Retain the limitation for hardware testing. CPU-only speculative-branch fixtures did
NOT independently reproduce this exact pending-redirect case; retained locally
and excluded as failure proofs. Healthy Pop/BX/literal experiment remains local; it is not a failure reproducer.

Original reduced long run and separate3B->3.56B forensic replay stay untouched.
The latter has saved3.1B and3.2B at100M cadence; event-wait g3:61 automatically
starts20M first-fault capture when3.56B terminal checkpoint is ready. No log
poll loop. Corrected50M replay completed: no further bus errors/data faults; SharedDataServer
and DosServer launched (EStart exited). Nokia framebuffer unchanged so far.
Strict continuation icache-discard-recovery-4200m targets another150M clocks,
saving4.1/4.2B. Diagnostic-fork provenance now propagates through normal restores.
Next inspect its startup wait and screen, then address measured C-scan cost. No hardware build/push.

## 2026-11-10: fault replay and 100M checkpoint observer

User requests continue3B failure investigation, then C-scan cost; also restore
100M snapshot cadence. logo_main.cpp now saves every100M, preserving all1B
milestones. Added --use-saved-build + --driver-upgrade observer-only relink
against exact frozen HDL archive (workspace tb.v differs, so DO NOT recompile
current HDL and claim old-checkpoint compatibility). Saved original HDL hashes,
container/binary validation and serializer schema check retained. Zero-cycle
and1000-cycle CPU+host byte equality pass: scratch/startup-fault-audit/
driver-equality.json. No production HDL/firmware/C input changes.

New isolated replay initially resumed3B, saved gracefully at3,017,023,825 for
observer upgrade, then resumed that exact state with100M cadence in
build/sim/runs/startup-fault-100m-to-3560m/, target3.56B. Original reduced12B
run untouched. New run should retain3.1/3.2/.../3.5B and terminal3.56B pairs.
Do not overwrite existing checkpoints. Final first-fault observer prepared as
scratch/startup-fault-audit/first-fault; plan run20M from3.56B, ring512 trace
changes and stop/save at first new bus error. Its host scanout is not updated;
any pair it produces is an observer diagnostic, not a maintained screenshot run.

Both3B and4B page tables map unused virtual50300000 page to physical00800000
(PTE0080000e). Valid kernel page50320000 maps00320000;503ef400 maps003ef400.
Thus mapping did NOT first change at fault. Missing00800B00 ROM mapping alone
is not a demonstrated loader bug. Four-billion issue/shifter PC503EEF4C,
ALU PC+4=503EEF50, branch offsetFFF11BB6 sum50300B06. This corresponds to
executing literal wordFFFFFDDC immediately after BX R1 at503EEF4A. R1 at fault
is503EF43F, a plausible intended return. I-cache line words503EEF40..5C match
original backing bytes, including4708BC02 (POP R1; BX R1). Stream slots are
invalid at4B, remaining data match backing. Control-flow/flush/prediction is a
hypothesis requiring the BEFORE trace; do not claim a proven BX bug yet.

Cache failure repeats because existing cacheable-refill policy retries external
bus errors without architectural abort. No prefetch abort/CP15 fault is delivered
in this frozen failure state. This retry policy is documented in the104MHz plan;
do not change it speculatively to hide the original wrong control flow.

Local isolated CPU program scratch/startup-fault-audit/thumb_pop_bx_literal.S exercises POP/BX
followed by the same literal pattern. Cold and alternating/nested call sites,
high50000000 virtual alias, user mode pass with memory delays0/3/9. It does not
reproduce the full firmware failure; no CPU fix made. Logs pop-bx-test.log and
pop-bx-alias-user.log under scratch/startup-fault-audit/.

Inspector failure found/fixed locally: old vw tested pa+3 bounds; unmapped
ffffffff wraps and indexes plain ROM out of bounds. Use pa<=limit-4 before
reference indexing. This can explain old bounded observer termination when
startup changed mappings; not yet independently reproduced as its exact exit.
Current state/probe helpers guard this. Production simulator was unaffected.

## 2026-11-10: overnight result reproduces hardware fault loop

Read-only user-requested status check: only reduced long simulator is running.
Permanent4B pair exists and was inspected with its frozen model. PC50300B06,
CPSR08000030, bus errors30,923,397, data errors0. Prior last progress log at
3.58B already had same PC and rapidly growing instruction bus faults at
physical00800B00. Progress log stops updating there, but the executable is
still running and saved4B afterward; do not report3.58B as current live cycle.
This matches the PC the user previously reported on hardware, not a proof of
identical root cause. Preserve3B (before observed fault storm) and4B pairs.

The4B process container now has EKern, EFile, EStart, EwSrv, FbServ and Starter.
Thus the mmcstore/mount stage is no longer the final startup blocker. The
bounded observer showed StartupThread changing state around2.320B and third
process appearing by2.330B. It is no longer running, but its log ends abruptly
at2.331966138B without final SNAP: it did NOT prove completion of its2.45B cap.
Cause of observer termination unverified; do not call it a successful replay.
Its fixed startup-thread object is also obsolete after later thread creation.

Counter1000 bounded replay completed20M normally:458 scan-loop observations,
1block exit,91IRQ entries versus1050/2/lowIRQ at64Hz; no new faults (12known
fetch faults/datafaults0). Counts of printed DEADLINE lines are duplicated trace
observations, not unique calls. Counter cadence experiment is not frequency
validation or production HDL. Firmware and C source files untouched.

Evidence: scratch/nos-deadline-audit/state-4b.log, startup.log, counter1000.log.
Next meaningful investigation: strict restore3B and capture the first transition
into physical00800B00 instruction fault storm / PC50300B06, including active
process, MMU mappings, exception state and preceding branch. Do not spend more
cycles merely extending the confirmed error loop. Long run left untouched per
user instruction; no new simulation/build/monitor started in this check.

## 2026-11-10: overnight handoff; user requests no active monitoring

User asked to stop monitoring until tomorrow to preserve allowance. No Terra
agent or periodic monitor started. Last usage check: 58% used / 42% remaining;
requested cutoff is 35% remaining. Existing reduced long run untouched.
Two finite diagnostic replays were launched and may finish unattended:

- Docker ngage-nos-startup-audit: exact reduced 2B checkpoint, 450M-clock cap
  (terminal 2.45B), scratch/nos-deadline-audit/startup.log. Watches block exits,
  startup status and process count. Last observed block31 after crossing34/33/32;
  at2.025B StartupThread still pending, two processes, no NOS call observed yet.
- Docker ngage-nos-counter1000-audit: same checkpoint, 20M-clock cap, separate
  counter-rate HYPOTHESIS ONLY. Host forces NOS divider to produce1kHz ticks;
  frozen RTL otherwise unchanged. This also affects any consumers of nos_tick.
  No firmware/C source edits, no saved-state lineage or production fix claim.
  Log scratch/nos-deadline-audit/counter1000.log (sed output may be buffered).

At reduced2B: NOS counter1641, compare1688, remaining47ticks, comparevalid1,
status00ee0200, enable8584. Firmware timer queue head8000d1f0 has delta50;
subsequent relative deltas77,374,160,491. Compare is ahead and armed, not stuck
behind current count. Remaining47ticks means734ms at64Hz versus47ms at1kHz.
Native NOS frequency still unproven. General OS64Hz is a separate timer.

Firmware514AE058 normalizes zero delta to1 and writes count+delta;514AE188
subtracts elapsed count from software timer;514A949C drains expired timer nodes.
Thus slowing counter really stretches original NOS scheduler deadlines. Static
paths also request65535ticks, which becomes~1024seconds at64Hz; NOT observed
as the current2B deadline. Do not claim this hypothetical fallback caused the
hour-long hardware failure.

Startup stack confirms call return503D535A follows mmcstore RFile::Open;
subsequent read occurs only on successful open. It has not returned in the
observed window. Extra tracing needed after the remaining mount scan completes.
Exact firmware disassembly saved under scratch/nos-deadline-audit/. Initial
VA-minus50300000 extraction for NOS was wrong and overwritten; correct dump
uses checkpoint page tables (NOS514AD800 -> PA000AD800; ELocal50390700 ->
PA00390700), verified instruction514AE058=e92d4010.

Observer caveat: trace-valid can be held across cycles; DEADLINE lines currently
repeat the same entry and their count is NOT a unique call count. Printed LR
uses user bank, not necessarily current-mode LR. Use MMIO compare writes for
actual programming and deduplicate trace events before any call-frequency claim.
No RTL changes, no firmware/C changes, no hardware build. Tomorrow read final
bounded logs first, inspect whether mmcstore returned/process creation advanced,
and then choose further work. Do not poll these runs overnight.

## 2026-11-10: bounded mmcstore scan progresses; hardware boot still fails

Acceptance target from user: reach phone UI within 20 seconds on hardware
(1.56B CPU clocks at 78MHz). An hour without UI is a boot failure. The bounded
scan measurements below do not explain it and are not a successful boot claim.

Original long run stopped gracefully at 4,433,931,411 cycles with final paired
checkpoint in build/sim/runs/hardware-service-boot-12b/. Its exact frozen binary
restored that pair for zero cycles; resulting CPU and host files were byte
identical. Preserve this pair and permanent 1B/2B/3B/4B pairs. No 5B checkpoint.
It is reusable with its frozen simulator, not arbitrary newer RTL.
Only reduced long run remains: timing26-nos64-after-snapshot-12b, resumed with
strict identity checks from 1,911,412,026; permanent 2B pair retained there.

Read-only bounded replay from reduced 2B through 2.02B observed 1050 unique
(block, metadata-offset) scan steps, zero repeats/backwards, and two block exits
34 -> 33 -> 32. Node addresses can be reused across blocks; include physical
block number in the uniqueness key. This proves local progress only, not that
the entire search cannot restart later. StartupThread remains pending in
RFile::Open(c:\system\mmcstore); no later UI process was observed in snapshots.

Median synchronous one-byte read: original 174936 clocks (19 complete samples),
reduced 16165 (1050 samples). Original complete-read windows spent about 71%
in IRQ/NOS code; reduced about 0.45%. Raw C backing bus occupied only 0.033%
and 0.494% respectively. Reduced remaining cost is mostly kernel/EUser work and
CPU stalls. Both builds differ in ROM/SDRAM paths as well as clocks: not a
frequency-only comparison. Both C backing snapshots match the original input;
no firmware or C input changed. Reduced long run still performs stock checksums,
so its absolute cycle count is not a matched fast-boot hardware benchmark.

NOS64 changes the actual deadline counter, not just interrupt delivery. Firmware
programs count+delta; slowing counter can stretch deadlines by 1000/64 relative
to the older hypothesis. Native frequency remains unverified. Do not infer
correctness merely from reduced IRQ overhead. Next isolate whole-open return/
restart and subsequent startup waits, and establish NOS deadline units before
calling the timer experiment a fix. Hardware/simulator divergence remains open.
Read-only Zaparoo screenshot attempt timed out; no fresh hardware fault snapshot.

Evidence: docs/mmcstore-scan.md and scratch/metadata-scan-audit/. Discard
reduced-invalid-overlapping-output.log: two disposable observers shared output
because SIGTERM to shell PID1 did not stop children. Both observers were killed;
independently linked reduced-final completed once with a fresh output log.
No hardware build or RTL change in this investigation.

## 2026-11-09: original/reduced simulations waiting on C:\system\mmcstore open

User requests actual boot-blocker investigation, then comparison with reduced
NOS frequency. Original observed past4.29B; permanent4B inspected read-only.
Reduced run checkpointed gracefully at1,911,412,026 and immediately resumed
its exact frozen executable/source/input identity in
build/sim/runs/timing26-nos64-after-snapshot-12b/, target12B. Keep prior1B and
new1.911B CPU/host pairs. Original live run was not stopped or modified. There
are still TWO long runs; old NOS-overlay simulation remains stopped.

Both process containers have exactly EKern.EXE and EFile.EXE, no later startup/
UI processes. EFile StartupThread object80409884 has pending RFile::Open for
literal c:\system\mmcstore (F32 function27). Saved stack80D01AF8 has pending
80000001; LR503B76B0 maps to RSession send path via CreateSubSession. ROM export
and IDA names independently identify RFile::Open. FileServer Main is processing
ELocal/RBusLocalDrive metadata reads; original3B/4B and reduced snapshot show
changing logical read positions. Do not reuse historical function23/SetEntry
write-completion claims from other C++ lineages as the current root cause.

Equal5M-cycle C: read probes: original4B→4.005B152word reads/152unique addresses;
reduced1.911412026B→1.916412026B1600reads/1600unique. Zero mismatches against
backing data and zero writes in both windows. Both snapshot C: DDR arrays are
byte-identical to initial4MiB C input. Thus there is active metadata scanning,
not a proven permanent loop, stuck bus, or missing flash-write completion.
The reduced/performance build samples10.53x more C reads per clock. It also
has ROM-buffer/direct-SDRAM improvements; cannot attribute gain solely to64Hz.

Original10M profile at4B has498046trace packets/3161PCs (not retired instruction
counts),86actual IRQ entries,62mailbox pump/63NOS DFC visits, no LCD update or
new data fault. Repeated NOS background work is real but not by itself the
startup gate. Nokia already drawn; higher user/UI startup awaits filesystem
request completion. Exact cause of expensive scan/termination not yet known.
Next profile one metadata-cell lookup and its exit/bounds, separating CPU/cache/
bus/IRQ cost. No C: format bypass, UI/NOS stub patch, HDL fix or build in this
audit. Preserve current evidence before further assumptions.

Evidence docs/evidence/boot-startup-compare-2026-11-09.json; observer sources/
logs scratch/post-logo-4b/ and scratch/timing26-compare/. Frozen model inspector
uses D-cache-aware reads and firmware-specific process offsets from Nortido.
Failed probe used wrong02000000 C bounds; discarded. Correct C physical window
is02400000..027FFFFF. No extra long simulation was started; bounded replays ended.

## 2026-11-09: HARDWARE bootstrap-only fails; production NOS keeps original startup

User confirms TEST_NOS_Bootstrap_Only.ngo gives no logo. Hardware matrix now:
checksum-only YES (fast), driver-only YES, fake-bootstrap-only NO, full fake
bootstrap+driver NO. Fake NOS startup/service-table replacement itself is the
failing component; exact firmware stop/call remains unknown. Earlier no-op
callback fix repaired a real porting error but did not resolve this failure.

Production tools/nos_overlay.py now excludes fake bootstrap by default. It
retains original nosstarter/service-table initialization and replaces only NOS
driver/export/allocation code plus primary checksum descriptor. This retains
original NOS runtime; do not call it a complete NOS/baseband replacement.
Runtime NOS_Compatibility.ngo and boot2.rom are byte-identical to the actual
hardware-tested driver-only file:389records/4732bytes,SHA256
b31873932d9ada7c5b5d6f0fab54d447dcfa0aaf1a7549cbf1d8544095307698.
Existing NOS-only RBF accepts it; an RBF rebuild is unnecessary. Local files
updated, no SD writes in this default-selection step.

Fake bootstrap retained only with explicit --experimental-bootstrap and TEST
output filename (production names rejected). Prior full447-record file is
runtime/overlays/TEST_NOS_Full_Experimental.ngo. New package audit rejects fake
bootstrap addresses in production. Default build byte equality, scope check,
all-target validation/undo/reload and actual HPS NOS/BT combinations pass.
Full UI/services remain unverified. Evidence
 docs/evidence/nos-bootstrap-hardware-isolation-2026-11-09.json.

Permanent ready-to-copy folder is runtime/overlays/, private generated files
ignored; maintained README/builders committed with diagnostic subset helper.
Intermediate compiler files belong to build/firmware-overlays/. No original
service file, C:/PMM or UI edits, no simulator monitoring/new long run or hardware
build. Original and timer-only sims remain unpolled; old NOS sim remains stopped.

## 2026-11-09: HARDWARE driver-only overlay reaches Nokia

User confirms Nokia logo with TEST_NOS_Driver_Only.ngo as well as checksum-only.
Thus replacement driver/export/allocation changes can reach logo when original
NOS bootstrap is retained. Full NOS replacement still fails: remaining suspect
is replacement startup/service-table path or its interaction with replacement
driver, not driver alone. Do not present full NOS compatibility as working.

Next existing artifact is runtime/overlays/TEST_NOS_Bootstrap_Only.ngo using
same Off→manual Load NOS Compatibility→On procedure. A failure here would
implicate bootstrap path without replacement driver; a success would point to
combined initialization/driver dependency. Hardware outcome pending. Keep
TEST_NOS_Driver_Only.ngo as the observed working diagnostic variant. No default
boot2 replacement, SD writes, RBF build, new sim or simulation polling.

## 2026-11-09: HARDWARE checksum-only reaches Nokia quickly; isolate NOS components

User tested TEST_Checksum_Only.ngo on the NOS-only-toggle RBF: Nokia logo
appeared "super fast". This establishes primary checksum bypass alone works
on that hardware/firmware configuration. Full NOS overlay still loses the logo;
remaining fault lies in replacement bootstrap/driver behavior or interactions,
not64Hz alone or checksum skip by itself. No loader-held-CPU assumption.

Prepared TEST_NOS_Driver_Only.ngo (389records: original NOS startup, replacement
driver) and TEST_NOS_Bootstrap_Only.ngo (60records: fake startup/service table,
original driver), both in runtime/overlays/ and both include primary skip.
Use existing NOS picker/toggle: Off→manual file→On, BT Off if present. Driver-
only recommended first. Actual HPS loader/byte-exact apply/undo passes for both.
Host assert confirms subset union equals full447-record NOS pack, with only
2checksum records shared. Normal boot2/full NOS package and SD untouched.
These are diagnostic subsets, not guaranteed internally compatible backends;
neither has yet been tested on hardware. No new RBF or long sim, no polling.
Build using tools/checksum_only_overlay.py --variant driver-only|bootstrap-only.
Logs scratch/nos-component-isolation/loader-tests.log. Instructions and hashes
runtime/overlays/{README.md,SHA256SUMS}.

## 2026-11-09: NOS hardware A/B, CPU active; checksum-only isolation prepared

User reiterates same hardware shows Nokia with NOS OFF, no logo with NOS ON,
and reports CPU numbers moving. Treat this as executed firmware-path failure,
not assume loader hold; actual stop PC still unknown.64Hz alone is not the
A/B differentiator. Callback correction did not establish restored logo.

Prepared runtime/overlays/TEST_Checksum_Only.ngo (88bytes, ID1): only8F18/8F1C
primary descriptors becomeFFFFFFFF, all NOS code/bootstrap/export hooks stay
stock. New tools/checksum_only_overlay.py derives audited undo words from the
full private NOS package, regenerates CRC/length, refuses to overwrite input.
Actual HPS loader/application/undo checks pass with the2-record pack. No C:/UI
patches. Existing boot2/full NOS file, SD card and both long runs untouched;
no simulator polling/new long run or RBF build.

Hardware test on existing RBF: BT Off, NOS Off, manual Load NOS Compatibility
select TEST_Checksum_Only.ngo, then NOS On. This deliberately reuses NOS selector
for checksum-only payload. Logo would isolate failure to NOS replacement changes;
no logo would implicate checksum bypass/interactions even with stock NOS code.
Restore full NOS manual package or cold-boot normal boot2 afterward. This test
has not yet been run on hardware. Instructions runtime/overlays/README.md.

## 2026-11-09: corrected NOS overlay still reported without logo

After receiving the corrected runtime/overlays/boot2.rom path, user reports
no logo with NOS enabled. The callback fix must not be presented as restoring
hardware boot. Hardware A/B already shows logo without NOS, so64Hz alone is
not the differentiator. Next distinguish overlay loader hold/error from actual
firmware stop using current diagnostic FETCH PC/BOOT flags or a new NGD export,
with Bluetooth OFF. Existing SD diagnostics.ngd still has16:15 timestamp and
is not evidence for this attempt. No further speculative firmware patch or
new long run; original/timer runs left unpolled. If CPU is running, isolate the
checksum-only change from NOS bootstrap/driver next rather than bundling fixes.

## 2026-11-09: permanent runtime overlay folder; hardware A/B confirmation

Prepared overlay files moved from scratch/mister-overlays into runtime/overlays/:
boot2.rom/NOS_Compatibility.ngo (corrected callback) and
boot3.rom/Bluetooth_Compatibility.ngo. SHA256 verified across the move and
recorded in runtime/overlays/SHA256SUMS. Generated private files stay gitignored;
README is maintained. Builders now keep intermediate objects under
build/firmware-overlays/{nos,bluetooth}; docs use the permanent runtime folder.
Historical scratch references remain evidence, not the delivery location.
No SD-card access, simulation polling or changes to running inputs in this step.

User hardware A/B confirms Nokia logo without NOS patch, no logo with NOS;
64Hz change is therefore not the differentiator in that report. Whether the
corrected boot2 had actually been installed for that A/B remains unverified.
The bootstrap porting defect is proven, but restoration of the hardware logo
with the corrected overlay is still pending.

## 2026-11-09: fix NOS initialization callback; stop old NOS long run

Hardware user reports NOS ON no longer reaches Nokia logo; exact hardware PC/
loader state not yet captured. Audit found a concrete porting error: reference
bootstrap installs a no-op at RAM global800004AC, but ours installed a binder
that writes80006F64 to[r0+4]. Reproduced on actual ZAP with r0=0: invalid write
to00000004. Corrected callback is a no-op; independent NOS constructor/clear
helper remain intact. Pinned reference and fixed assembly pass actual ZAP tests
(null/object argument, caller state/table, clear word/halfword, repeated init).
This fixes a proven defect, not yet a proven hardware missing-logo root cause.

Fixed private NOS package447records/5428bytes, SHA256
992c8a0837dea0135943f28d4bc28332922a3ee14f463f85c3912197832d5c69.
New package passes backend validation/undo and actual HPS all NOS/BT views,
shared checksum and C:/PMM preservation. Updated SD boot2.rom and named NOS
file with verified bytes; old copies in scratch/nos-bootstrap-fix/sd-backup/.
Original boot/boot1, Bluetooth boot3 and working save remain unchanged. This is
a guest payload fix: existing overlay RBF works, an RBF rebuild alone would
continue loading an old boot2. Source fix committed/pushed for continuity.

At explicit user request SIGTERM stopped only nos-compatibility-resume-12b at
519,606,938cycles. Its final checkpoint-519606938.cpu/.host pair is present;
result interrupted=true. Earlier50M and all existing checkpoints retained.
Original and timer-only simulations left running without polling/interference.
Do not resume old NOS run as verification of the fixed payload. No replacement
long run or hardware build launched. Host Python Unicorn crashed SIGILL during
initial test attempt; use tests/phone/overlay_bootstrap/run.sh (actual ZAP in
existing Docker image). Evidence docs/evidence/nos-bootstrap-callback-fix-2026-11-09.json.

## 2026-11-09: Bluetooth hardware-test candidate and SD autoload file

User requests commit/push of the directed-tested Bluetooth addition and copy
of boot3.rom to the mounted SD card. Copied7144bytes to
/Volumes/sdcard/games/NGage/boot3.rom; SHA256 matches
12b078de67083dffe006be7b0102444c9f2d0e6a3660674ff3cb2449de2ec2aa.
Existing boot.rom/boot1.rom/boot2.rom/working.nga hashes remain unchanged.
Install the newly built RBF, select Firmware → Bluetooth Compatibility On and
save MiSTer configuration for persistent auto-application. NOS remains an
independent selector. No action/build or long-simulation polling in this step.
Guest BTLDD startup and actual board behavior still need verification.

## 2026-11-09: independent Bluetooth overlay implemented and directed-tested

Firmware now has Bluetooth Compatibility Off/On (status20, defaultOff) and
Load Bluetooth Compatibility (F4). Private file Bluetooth_Compatibility.ngo,
identical boot3.rom alias (C0) for automatic loading. Pin4b848014 GPL BTLDD
write/completion glue plus no-peer HCI responder; linked ARMv4T, original kernel
ring/completion calls, no NOS dependency. No C: routing/formatting, UI/startup
patches, cellular/SIM or physical Bluetooth radio. Separate BTLDD delay-literal
shortcuts from the reference are excluded.

Parameterized existing loader with componentID2 and shared checksum selection;
two independent8KiB BRAM undo tables and a DDR component arbiter. Either option
ON retains primary descriptor bypass; turning either OFF restores only its own
bytes until both OFF restore original descriptor. Each pass latches selection
and reconciles against current selectors before CPU release. Valid shared-mode
packs must contain both audited descriptor undo records, not merely valid CRC.
NOS ID1 files remain unchanged/compatible. Auto-load may arrive before firmware;
CPU held for missing/bad requested pack. Manual pickers disabled while active/
busy. Diagnostic BT flags25..28, error source29; screen layout unchanged.

PASS actual hps_io boot3/F4 + boot2/F3 transport, deferred firmware gating,
all four independent NOS/BT views, shared checksum retention in either OFF
order, mid-pass toggles, exact original/C:/PMM byte preservation, missing BT
without forcing NOS, wrong-component rejection/recovery and CRC-valid pack
missing checksum records rejected before writes. Standalone tests exercise
both actual packages, reset/reload/partial reload, all-target preflight, CRC,
profile/type/length/bounds/order checks. Top elaboration and NOS regression pass.
Host HCI tests with address/undefined-behavior sanitizers cover reset/name,
settings/no-peer inquiry/connection+name timeouts, vendor/unknown commands,
malformed/ACL handling and all65536opcodes with zero/max-length framing.

BT pack590records/7144bytes, SHA12b078de67083dffe006be7b0102444c9f2d0e6a3660674ff3cb2449de2ec2aa.
Only overlaps NOS at8F18/8F1C with identical undo/new values. Original service
files SHA-verified unchanged. Prepared scratch/mister-overlays/{Bluetooth_Compatibility.ngo,
boot3.rom}; not copied to SD in this step. Docs firmware-overlays.md and
 evidence/bluetooth-overlay-2026-11-09.json. Not yet a BTLDD guest ABI/startup/UI,
installed Main, resource fit or timing verification. No fourth full-core run.

All three existing long simulations and their inputs/checkpoints were left
running, without polling their status/logs. Their frozen executables do not
include Bluetooth; future builds/runs must use a new lineage. No commit, push
or hardware build for this Bluetooth step.

## 2026-11-09: hardware-test candidate prepared; overlay copied to SD

User requests commit/push and will run the hardware build/test. All maintained
NOS loader/menu changes and their tested26MHz/NOS64 timer configuration are
included. NOS_Compatibility.ngo and its identical boot2.rom autoload alias were
copied to /Volumes/sdcard/games/NGage and SHA-verified; existing boot.rom,
boot1.rom and working.nga remain byte-identical. Enable Firmware → NOS
Compatibility after installing the new RBF. Primary checksum skips only when
NOS is ON. No C: bypass/UI edits. Existing simulations remain independent.
No GitHub action dispatched by this step. Full NOS startup remains unverified.

## 2026-11-09: compatibility scope narrowed to NOS, Bluetooth and SIM

User prioritizes NOS, then wants Bluetooth and SIM compatibility. Current NOS
replacement does NOT implement cellular/SIM or BT: only bootstrap and narrow
accessory/light/vibration messages. BT is a separate reference HCI responder to
adapt; full SIM startup service is absent from this NOS stub and needs further
investigation. Exclude C: drive bypasses, formatting changes and UI/startup
stubs from the overlay scope. Do not expose nonworking BT/SIM toggles; finish
NOS loader validation first. Preserve original files and existing long runs.

## 2026-11-09: NOS overlay loader implemented; 50M boot and checkpoint checks pass

User explicitly changes checksum policy: enabling NOS Compatibility also skips
primary firmware verification, using Nortido's absent-descriptor early return
(8F18/8F1C=FFFFFFFF), not a derived expected digest. Off restores all original
words and checksum behavior. Secondary verification and package CRC remain on.
Original service files/C:/PMM and both pre-existing long runs are untouched.

Template Firmware now has NOS Compatibility Off/On (status19, defaultOff) and
Load NOS Compatibility (F3). Human filename NOS_Compatibility.ngo, identical
boot2.rom alias for stock Main index80; staged before/after service files, applied
only after both validate. Explicit8KiB BRAM; bounded profile/CRC validation and
all-target preflight precede writes through the normal DDR invalidation path.
CPU held across apply/undo, reload reconciliation and missing/invalid requested
payload. No nonworking Bluetooth/audio entries. Details docs/firmware-overlays.md.

PASS synthetic and actual450-record/5464-byte packages: early staging, exact
ON/OFF, rejected bodyCRC/profile/truncation, late target mismatch with zero
partial writes, firmware/partial reload reconciliation, active replacement
drain, mid-pass selection changes, bounds/alignment/order protection. Host guest
payload tests pass attach/RX/queue/cancel/overflow/vibration/unsupported resource.
Actual hps_io boot2/F3 transfer, deferred apply, service-index isolation, DDR
backpressure and byte-exact ON/OFF/C:/PMM preservation pass. Stock Main menu
parser supports D0P1 disable/page order. Top elaboration passes with stubbed
HPS/PLL. This does not verify physical Main,
FPGA timing/resource fit, full NOS guest ABI or UI progress. No hardware build.

Separate actual-HDL cold run nos-compatibility-cold-50m targets50M, uses real
NOS staging engine/DDR adapter before CPU release, stock exported service DDR
inputs, disposable C: copy,78MHz/26MHz timers/NOS64 and64-bit1KiB ROM buffer.
Manifest includes package SHA bfbef95b677ea1966de3e25278e9582f7aea563e49c336a1e558356e0caf51e6.
Do not import stock checkpoints. Separate run completed50M cycles,12known fetch faults,zero datafaults; loader
applied the actual pack/checksum bypass through DDR before CPU release. Still
in early delay (PC6154),zero LCDwords; no claim of Nokia/UI, NOS ABI startup or
observed firmware checksum return yet. Exact frozen-build zero-cycle restore
produced byte-identical50M CPU/host checkpoints. Evidence
docs/evidence/nos-overlay-2026-11-09.json. Test logs scratch/nos-overlay/;
prepared SD package copies scratch/mister-overlays/ (not copied to the card).
Stock-mode restore of the NOS checkpoint is explicitly rejected. Frozen NOS
executable strict-resumed50M→12B in nos-compatibility-resume-12b/, retaining
paired billion checkpoints; this is the pending NOS startup/ABI verification,
not a proven UI boot. Both older runs remain untouched. No commit/push/build.

## 2026-11-09: timer audit and independent26MHz/NOS64 experiment

General timers now have a registered CPU clock enable: /3 at78MHz, /4 at104MHz,
so periodic406250 yields64Hz as in the Nortido reference. Writes and IRQ ACK
remain atCPU speed. Template selects this26MHz experiment and NOS_TICK_HZ=64;
NOS IRQ deadlines remain firmware controlled, not forced IRQ-per-tick. FAST
counter remains~32768Hz. Legacy module defaults remain available to fixtures.
These are exploratory peripheral assumptions, not phone-verified NOS timing.

PASS timer/rate/IRQ tests at78/104MHz, CPU-board integration, clock propagation
and top elaboration. Cold timing26-nos64 run saved50,347,830 clocks and strictly
resumed to12B using frozen identity65ea564947bfe4e45ee4d2fa95cd23fc232a5b50fd694004edb0677cb6d9b0c2.
Both CPU/host files stay together; no imported stock checkpoint for this model.
Evidence docs/evidence/timing26-nos64-experiment-2026-11-09.json.

Separate frozen post-logo50M audit found16.63% IRQ and~56.53% NOS callback
windows (including useful startup), with no stuck-level NOS IRQ:340assertions,
339clears,1pending. Original stock run reached Nokia before1.99B and has
permanent1B/2B checkpoints; post-checksum2B exact restore is byte-identical.
No permanent post-logo deadlock established. MTC3/SIM1 and unregistered NOS
channels are probes, not proven causes. Firmware chooses recurring deadlines.
Thumb textual trace PCs need+4 for disassembly; live fetch PC is unaffected.
Evidence docs/evidence/{post-logo-execution,timer-irq-audit}-2026-11-09.json.
More details docs/phone-clocks.md, docs/display-bringup.md and
 docs/nortido-compatibility-inventory.md. Preserve every billion checkpoint.

## 2026-11-09: performance subset prepared for user-triggered hardware build

Saved future redesign options in docs/cpu-performance-redesign-notes.md. This
build candidate contains only the implemented ROM buffer/uncached-path/fetch
handoff/direct-SDRAM changes and their tests. No whole-cache/CPU redesign or
clock change is included. Current production defaults:78MHz,64-bit/1KiB DDR ROM
instruction buffer,dedicated SDRAM route,existing CPU/LCD arbitration.
Final50M stockboot and directed/real-controller checks are recorded below.
Formatting check passes; final assertion-whitespace change is Verible token-
equivalent to the50M-tested source. Compact baseline in
docs/evidence/performance-subset-2026-11-09.json.
User requested commit/push and will trigger the hardware action. No action is
dispatched by this step. Original12B simulation and billion checkpoints remain
independent; use its frozen executable if resumed.

## 2026-11-09: direct SDRAM route complete;50M boot and cache-miss profiling verified

Production DIRECT_SDRAM=1 routes physical0x0a000000..0x0affffff from registered
ZAPmerger directly to existingCPU/LCD SDRAMarbiter. Bypasses peripheralbridge
and sharedmemory_owner; RAM bit explicitlyzero in directmode so SDRAMreturns
are excluded from genericperipheralACK/data mux. Merger/cachecompletion/SDRAM
arbiter/adapter/controller registers retained. Existinggrant sidebandcpu_accept
captures route token on sameedge as arbiter's packet; no extraadmissionstage.
Acceptedcancel drains/discards beforeanother target; unacceptedcancel doesn't
issue. Flash/MMIO,clocks,controllerprotocol and64-bit/1KiBROMbufferunchanged.
Diagnosticgrant drivesoneeventFF;widepacket observation separatelypipelined.

Final exact-source stockfirmware run direct-sdram-final2-50m completed50000000
cycles in518.566s,normalpowerup,78MHzphoneparameter,erasedPMM,same service-loader
bytes/C: snapshot. Zero datafaults,exactsame12knownfetchfault records. Retired
3869533instructions,index48900/100000. Paired50MCPU/host files hashed/retained.
ROM warmloop unchanged1020clocks; firstdelayentry124470→121266 (3204clocks saved).
NoLCDpixelsyet/full-logo claim; first50M primarily exercises uncachedflashloop.
Original12B manifesthashunchanged,frozenexecutable/checkpointsuntouched.

NativeMMU/Dcache A/B workload:65clean32Bmisses median159→143 (range159..167→
143..151),dirtyvictimcase108→90,warmserializedDcachehit5→5. Programchecks dirty
victimvisibility viauncachedalias,bytes/SWP andDMAvisibility before/afterclean.
Numbers are end-to-end workload costs withmodeledmemorywaits,notchip latency.
New profiler: directdirty90 has60RAMbackend-active clocks,9instruction-port
clocks; cleancase143 has48RAMbackend-active and85instruction-port clocks. These
portcounters are observational; dirty/clean examples have different contention.
Five sampled hitclocks correspond to4clocks untilresponsevisible pluscalleredge;
serializedownership/tagread/compare/dataread/completion,not1KiBROMbuffer hit.
Our added ARM920cache is one-request-at-a-time. User agrees substantiallongterm
redesign maybewarranted; nextdesign should address pipelinedhits,wholeline
transport andCPUload/stall coupling,notdelete104MHz stage registers or assume
wholeupstreamZAP mustbereplaced. Details docs/direct-sdram-path.md.

Checks pass: route range/lanes/admission/cancel/drain/reset;bothbridgemodes;
legacyflashreset/owner;actualSDRAMrefresh/mask/reset andSWPlockarbitration;
actualARM/boardIRQ/FIQ/fault/SIMIF/LCDDMA/SDRAMwaits;correctedLCDcachecoherence;
topelaboration;176file/9QIPpreflight. ActualJTFRAME+device-model5Mboot at78MHz
passes483906bus/12fetchfaults/zero datafaults; final104MHzmodel5Mpasses483905bus/
12fetchfaults/zero datafaults. These are protocol tests,notFPGA104MHzclosure.

Fixed testbug: inheritedlcd_cache omitted0x0c1DMA/IRQ MMUsection and $finish
failures couldstillprintPASS. Map0x0c100c02 atTTBR+0x304;failuresfatal inthat,
newbenchmark andboardCPUfixtures. HistoricalPASSstringsalone aren'tevidence.
Correctednativeprograms genuinelypass (collector rejectsanyFAIL). Focusedlegacy
memoryowner/flashfixtures explicitlyDIRECT0;nativeARMtests exercisenewroute.
A/Bflag --legacy-sdram-route is part ofidentity/restoreguard. Neverrestore old
RTLstates into newroute. Earlierdirect-sdram-50m anddirect-sdram-final-50m were
superseded observer/explicitowner-prune runs,notfinalverification.

Evidence scratch/direct-sdram/{comparison.json,collect.py,benchmark-profile.log,
real-sdram-final104.log,final-regression.log}; maintaineddirectedtests under
 tests/phone/direct_sdram/. No hardwarebuild,push/deploy or clockchange. Later
CPU/LCD admissionfusion/linebursts/slowperipheralclock are NOTimplemented.

## 2026-11-09: CPU fetch issue4→3clocks; registered returns retained;50M passed

cpu-hit-registered-master-50m completed50000000cycles from reset in544.604s,
64-bit/1KiB,78MHz phone timebase,normalpowerup,erasedPMM,same stockservice-loader
firmware/C: snapshot. Zero data faults and exactsame12known earlyfetchfault
records as instrumentedbaseline. Retired3869284instructions; firstdelay index
48897/100000 versus44561 at previous50M. Both50M CPU/host checkpoints retained.
Firstdelay stillrunning; completefirstdelay/logo NOT claimed by this endpoint.

Warm1119→1020clocks (8.847% fewer);79retirements/99fetchcompletions/zeroDDRreads
unchanged. Chain4+5+2→3+5+2. CPUcode_stall990→891;buswait495 andlookup99unchanged.
Delayentry135417→124470. Full100000iterationbody projects102Mvs111.9Mcycles.
ColdDDRcommands1231vs1225; do NOT claimfullbussequenceidentity.

RemovedonlyUPP's duplicate requestcopy for itsknownregistered/heldZAPmerger:
REGISTERED_MASTER=1 reusesmergerFFfields. Cacheowner,merger,boardmemoryowner,
bridge{data,error,completion} andcachecompletion registers allremain. Thetwo
returnclocks deliberatelyretained as timingboundaries. NoCPU/TLB/arbitration
logic joined withboarddecode. SourceFFfanout/placement needsfuturefit;no104MHz
closureclaim or timingexception. Genericbridge default0 preservescapture.
Specializedsource holdsfieldsuntilresponse,then withdrawsorreplaces itscompleted
offer. RESPONSE keepsdownstreamlow;assertion verifiesheldpacketstability.

Bothbridge modes pass200waitedread/write/errorbeats,exactonceeffects,cancel/reset;
mode1alsofirstedgeACK/ACK+ERR andcontinuousownerhandoff. Flashreset/program/erase,
memoryownership,DDRcache/arbiter,topelaboration,176file/9QIPpreflightpass. Actual
ARM/board IRQ/FIQ,precisefaults,SIMIF,LCDDMA,SDRAMwaitfixturepasses. Sourcecompare
betweeninstrumentedbaselineand50M differsONLY rtl/ngage_upp.v; inputhashesmatch.
Evidence scratch/cpu-fetch-handshake/{comparison.json,compare.py,regression.log,
bridge-unit.log,board-cpu.log}; docs/uncached-fetch.md hasexactstages/contracts.
Original12B manifesthashunchanged,frozenbinaryuntouched,at1.01B withzero data
faults onverification. No hardwarebuild,push/deploy. Furtherissue/returnlatency
work needsownedprefetch/overlap or measuredretiming,not deleting the remaining
registers that protecttranslation/arbitration/CPUstall paths.

## 2026-11-09: resident instruction-hit latency reduced; separate50M verified

64-bit/1KiB retained. hit-pipeline-fast-50m completed50000000cycles from reset,
normalpowerup,78MHz phone timebase,unchanged production-service-loader-derived
firmware/C: snapshot,erasedPMM,modeledDDR/SDRAM. Zero data faults; exact same12
known early fetch-fault records as isolatedbaseline. Retired3526752instructions;
first delay index44561/100000 versus37852 in previous64/1KiB50M run. NoLCDpixels
yet; complete firstdelay/logo NOT verified. Paired50M.cpu/.host retained.

Warm iteration1317→1119clocks (15.03% fewer),79retired/99fetchcompletions unchanged;
buswait693→495,code_stall1188→990,lookup297→99,zeroDDRreads/backendclocks.
Sequential fetch chain4+7+2→4+5+2clocks. Detailed bus trace confirms original7:
1ownership +1flashlaunch +3lookup +2response. Newlookup takes1clock. Wrapper
presents accepted address to synchronous BRAM on acceptance,then holds its
captured request. Opt-in HELD_ADDRESS removes redundant imported hit_l history
while retaining pipelined valid/index/tag matching. Streaming default unchanged.
All responses stay registered; no CPU,flashcommand,owner,arbiter,descrambler or
inter-chip boundary bypassed. Added input-address mux timing needs futurefit;
no104MHz/Fmax claim. Firstdelayentry147802→135417; body projects111.9Mvs131.7M.
ColdDDR commands1225vs1208; don't claim entireboot bus-sequence equality.

Nine width/capacity unit modes pass1clock hits,immediate producer-pin changes,
tight alternating/conflicting tags,maskedreload,reset stages/stale burstdrain.
LegacyDDR/arbitration,flashreset/coldreset/program/erase,memoryownership,codeflash,
topelaboration and176file/9QIP preflight pass. Evidence/counter/stagecomparison:
scratch/instruction-hit-latency/{comparison.json,compare.py,regression.log};
docs/uncached-fetch.md contains exact7→5clock trace and remainingCPUoverhead.
Original12B run untouched: manifest hash equals prior matrix baselinecheck,
stillfrozen dd61fbd8/source3adc98c7binary,target12B;840M withzero data faults at
verification. No hardwarebuild,push or deployment. Furtherlatency work should
measure the remaining4clock issue/2clock CPUreturn paths before changing them.

## 2026-11-09: all nine DDR instruction-buffer benchmarks complete (50M each)

64/128/256-bit lines ×1/2/4KiB each completed50000000cycles from reset with
matching RTL/input hashes,78MHz phone timebase and the uncached CPU bypass.
All9 have zero data faults and12known early fetch faults. Paired50M CPU/host
checkpoints retained; no hardware build. Each covers37.85% of the first100000
count delay, about3M retired instructions, no LCD pixels yet. Warm iteration
is1317clocks/79retirements/99fetch completions/zeroDDR reads in EVERY variant.
Outer index at50M ranges37852..37856. Default64-bit/1KiB delay entry147802;
best256-bit/4KiB143566,4236clocks(~54us at78MHz) earlier. Larger capacity and
lines do not materially shorten this resident delay; retain64-bit/1KiB default.
Full9-row table/counter interpretation: docs/ddr-rom-cache.md;
scratch/ddr-cache-matrix/{results.json,results.md,collect.py}. Exact DDR model:
3clocks first beat,consecutive following beats; not board DDR timing/BRAMfit.

All9unit modes plus legacyDDR/top elaboration passed. Collector verifies all
final endpoints, source/input lineage, paired checkpoints and warm counters.
Orchestrator's in-memory old copy hit a duplicate-name result-bookkeeping error
AFTER launching all9; children continued independently and collector succeeded.
On-disk orchestrator fixed. Do not mistake this for a hardware/simulation error.
Original12B run remains on frozen source dd61fbd8/executable3adc98c7,target12B;
continues beyond700M with12fetch faults/zero data faults. No reset/rebuild or
checkpoint changes there. Future useful work: reduce resident instruction hit
handshake latency (currently4+7+2clocks per sequential fetch), preserving timing,
transaction ownership, reset/reload and fault alignment. Full new-cache logo
boot not verified by these50M comparisons; do not claim it.

## 2026-11-09: nine-way instruction-cache benchmark running (50M each)

User explicitly requested64/128/256-bit lines at1/2/4KiB and at least50M cycles
per case, keeping the12B run untouched and no hardware build. The DDR backend
now collects1/2/4returned64-bit beats per cache miss and drains the whole burst
on reset; bypass reads/writes remain single-beat. DDRAM_BURSTCNT comes from the
backend instead of a constant. Defaults remain64-bit/1KiB pending results.
LARGE fill assembly generalized using sysfl's128-bit reference as a guide;
cache still DW32/TAG_RAM1 with explicit M10K wrappers. Wider imports require
DW32. Actual hps_io/service-loader export remains the source of all boot bytes.

Nine unit cases pass lane selection,conflicts,data bypass,masked reload,reset
stages and cancellation after the first beat of a wider burst. Legacy DDR and
top elaboration pass. New benchmark outputs include final outer-loop index,
retirement count and DDR command/beat counts. Same78MHz timebase,normal powerup,
C: snapshot and CPU uncached bypass in all cases. First-beat modeled latency3
cycles,consecutive later beats; comparison is simulated cycles,not walltime or
physical DDR/Fmax/resource proof. Full first100000-count wait may exceed50M;
measure loop progress and warm cost rather than claim a complete logo boot.

Orchestrator: scratch/ddr-cache-matrix/run-matrix.py; log/status files beside it.
Cases build in two workers with2compile jobs each; each starts its50M run when
linked. Compiler intermediates in ONLY these new build folders are removed
after linking; executables/checkpoints retained. Results under build/sim/runs/
rom-matrix-{bits}-{bytes}-50m/. Do not modify RTL/runner while variants build.
Original12B container698bcf6c1c74 and its frozen executable are untouched.

## 2026-11-09: uncached fetch waits removed — separate boot verified

The running hardware-service-boot-12b executable/checkpoints remain untouched.
Shared arm920_cache_access now admits uncached reads directly to registered
BYPASS when older stores are drained, otherwise WAIT_DRAIN; its uncached drain
exit bypasses tag lookup too. Cached accesses,writes and maintenance retain
original state transitions. No imported ZAP file changed. ROM instruction-only
LARGE buffer is enabled in Template; data/file reads bypass. Small guard change
permits earlier miss dispatch but adds no measured warm-hit gain.

Warm boot-delay iteration:1713(no DDR ROM buffer)→1515(buffer)→1317(new bypass).
13.07% fewer clocks than buffer-only;23.12% fewer than original. New separate1M
cold run has79retirements,99fetch completions per warm outer iteration,zero DDR
reads,693 bus wait clocks and1188 CPU code_stall clocks (old1386). Sequential
CORE_ACK→nextBUS_REQ→BUS_ACK→CORE_ACK reduces6+7+2 to4+7+2 clocks. Exact code,
loop tally,remaining latency and Nortido comparison: docs/uncached-fetch.md.
Wider64/128/256-bit and1/2/4KiB matrix remains pending; no warm DDR misses here.

Tests: cache_access and cache_buffer integration pass; uncached unit response
latency now1clock on immediate bus fixture, cached read4/cleanmiss23 unchanged.
24 CPU cases pass: load widths,disable/reenable,prefetch-uncached,buffer ordering,
FIQ flash sequence,SWP basic/read-abort/write-abort each at0/3/11wait settings.
Production ROM-cache tests pass including lane/conflict,data bypass,full/masked
reload and reset at lookup/issue/wait/select/fill with stale-response draining.
Source graph176files/9QIPs,top structural lint pass.

Separate78MHz real-SDRAM5M boot passes374848bus transfers,12known fetch faults,
zero data faults,acceptedPC00006154,last accepted fetch9clocks before endpoint.
All121writes and12fault records equal previous cached5M snapshot excluding
cycle stamps; more polling reads give965boardevents vs848,so don't claim whole
trace equality. Evidence: scratch/uncached-fetch/{measurement.json,
boot-comparison.json,real-sdram-boot.log} and CPU/unit logs. Simulations use
service-loader-derived stock bytes for the1M measurement; real-SDRAM fixture
uses the independently verified identical assembled firmware. Full logo with
new optimization is not yet verified. No hardware build,push or deployment.

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

## 2026-11-09: service12B run100M progress — counted boot delay

At100M cycles in1036.86s (~96.4k/s),PC00006160,12 fetch errors stable,
zero data faults,no LCD words. Container698bcf6c1c74 active. Disassembly of
production-loader core output at6150..6178: r1=0; increment r1; compare r0/r1;
BNE6154; return via LR. Sampled6158/6168/6170 PCs are a counted delay loop,
not an unconditional terminal spin. Occasional617c/63ec shows other boot code
also executes. No register capture yet to establish current requested delay
length. Keep running to12B; no reset,patch or new hardware build.

## 2026-11-09: service-loader-backed12B run active; cleanup

Superseded assembled-input12B run stopped cleanly before further investment.
Actual hps_io boot1→boot transfers through production ngage_service_loader,
DDR adapter and decoder passed full20905984-byte equality and C:/PMM guard.
Added test.cpp --export-boot output, after validity/readback checks, producing
scratch/hardware-live/service-loaded-boot/{core,extension}.bin. This is staged
loader execution followed by boot simulation, not one continuous full MiSTer
HPS/controller simulation. Sources are original audited service containers;
old assembled binaries are equality oracles only. Loader test log retained.

Fresh run hardware-service-boot-12b started from reset, target12000000000,
78M phone timebase parameter,normal powerup,actual copied C:,erased PMM.
Runner uses exported production-loader DDR bytes; modeled backing-memory and
100MHz host-step caveats remain. Every billion CPU/host pair is permanently
saved. Existing scanout/RTL includes requested pixel swap. At previous96k
cycles/s,12B takes about35h; do not confuse ten-million progress reports with
caps. Main log: scratch/hardware-live/hardware-service-boot-12b.log.

User requested old checkpoint/generated-file cleanup. Automatic approval review
rejected deleting protected billion-cycle checkpoints. Safer cleanup removed
1779 sub-billion checkpoint/compiler-intermediate files,4.04GB, preserving all
billion pairs,firmware,user saves,screenshots,logs and executables. build/sim
6.6GB→2.6GB. Manifest: scratch/cleanup-20261109/removed-files.json. Older docs'
sub-billion checkpoint paths may now be historical; retained billion checkpoints
remain available. No new hardware build or deployment in this step.

## 2026-11-09: hardware-save Verilator investigation20M checkpoint

Fresh run hardware-logo-investigation-20m completed20M cycles in207.474s,
about96.4k cycles/s. SYS_CLK_HZ phone parameter78M,normal powerup,actual SD-card
C: copied read-only to scratch/hardware-live/hardware-cdrive.img; PMM verified
allFF. HDL peripherals with modeled backing memory, not full HPS/physicalSDRAM.
Host driver retains10ns discrete clock steps;78M parameter changes cycle-based
timebases, not host timestamps. Checkpoint pair retained in run directory.
Result PC00006158,zero LCD pixels/display off,12 known fetch errors,zero data
faults. This is early startup, NOT reproduction of the hardware logo wait.
Continued frozen executable to100M in hardware-logo-investigation-100m, restoring
checkpoint20000000 with --use-saved-build and --sys-clk-hz78000000. Runner now
accepts clock parameter, includes it in nondefault build identity/manifest and
rejects checkpoint clock mismatch. At measured speed80M additional cycles take
about14 minutes. Logs under scratch/hardware-live/verilator-investigation*.log.

## 2026-11-09: diagnostic export recovered; OSD/pixel corrections ready

SD-card diagnostics.ngd updated09:31:59 local; copied to
scratch/hardware-live/diagnostics-20261109.ngd and decoded JSON beside it.
Valid wrapped64-entry ring,zero dropped events,no data fault. Historical fetch
fault0c0047e4/reason1 matches known early scratch-fetch class. Trace contains
TRtcQueue::Add: 4 and repeated byte61 debug markers plus LCD unknown-command
records. This short mixed ring is insufficient to identify the logo wait.
User may have activated Export via shifted Reset row; export itself succeeded.

Requested panel pixel swap now implemented: high16 pixel first, low16 second
for both direct and DMA frames. Native coordinate/replay and partial-frame
expectations updated to test that order. Full LCD suite,native raster/replay,
and top lint pass; source preflight174files/9QIPs passes. OSD metadata moved
after actionable rows and F1/F2 grouped under Firmware. Native32-bit SDRAM
changes previously tested are included in the upcoming single build. Current
board remains old RBF until user installs a replacement.

## 2026-11-09: live hardware diagnostics after Nokia logo

Two Zaparoo screenshots saved under scratch/hardware-live/diagnostic-first.png
and diagnostic.png (device timestamps082934/083012). Fetch PCs5159EFA8 then
514AE280; user observes503xxxxx–515xxxxx recurring. Fetch/bus counters advance,
IRQ sampled low then high, waits13→0 clocks; BUS_ERRORS stable0x18 and all
captured DATA_FAULT/FAULT_PC/DATA/FLAGS/REASON zero. LCD/ERR stays1 (combined
export debug_error OR lcd_unsupported, not sufficient to identify LCD failure).
Firmware/SDRAM/board/save ready; no claim of progress beyond logo from these
snapshots. Next useful evidence: exported diagnostics trace, map recurring PCs
and identify peripheral/startup waits before promising later UI boot.

## 2026-11-09: hardware Nokia pixel order matches clean simulator lohi

Compared scratch/hardware-live/nokia-logo.png (1056x1248, exact6x scale) with
retained build/sim/screens/boot-v15-simif-fresh-gss-8b-frames/
frame01_c27463_24d67f-{lohi,hilo}.png. Nearest-neighbor reduction to176x208
produces zero differing RGB pixels against lohi;548 against hilo. Viewed both:
lohi is clean, hilo has adjacent-pixel comb artifacts. Current LCD scanout uses
low halfword first for even x, matching lohi. No LCD pixel-order change needed
for this captured frame. User-reported line artifact may occur in another frame;
this exact comparison does not explain an artifact absent from the capture.

## 2026-11-09: Nokia logo observed on physical MiSTer

User installed the current RBF and original service boot.rom/boot1.rom, then
reported Nokia logo. Zaparoo screenshot at192.168.1.176 confirms blue NOKIA on
white, near bottom of176x208 phone image (captured PNG1056x1248). Saved at
scratch/hardware-live/nokia-logo.png; device copy
/media/fat/screenshots/NGage/20261109_082156-screen.png. Earlier screenshot was
white because user was switching display. Exact running RBF SHA unverified;
do not attribute this board result to uncommitted32-bit burst RTL. User also
reports a mixed line; precise artifact/cause not yet identified. Logo alone
does not establish later phone UI boot, persistence or SDRAM timing sign-off.

User reports OSD selects actionN from highlighted rowN+1. Local Main source
menu.cpp renders only supported rows but activation counts uppercase J metadata.
Moved J1 metadata after all actionable options; grouped manual F1/F2 loaders
under P1 Firmware, keeping explicit file indices and boot auto-load unchanged.
Changes are local for a future RBF; running hardware menu has not changed.

## 2026-11-09: native32-bit SDRAM reads implemented and verified

BA0_LEN/BA1_LEN32 now fetch both halfwords with one READ command. Adapter
captures low16 on selected dst and high16 on selected rdy, then returns one
32-bit response. No persistent cache, invalidation, extra state or second read
request. Masked writes and cold scrub retain two single-halfword operations.
PLL stays78MHz and explicit input-DDIO capture is unchanged. All named and
positional adapter consumers updated, including the CPU ideal burst responder.

Four-state real-controller tests pass at78/104MHz and0/.25/.5/1ns pin delay;
wrong-edge negative control still detects invalid data (now zzzz0000, reflecting
the burst). Every normal read checks exactly one physical READ command. Masks,
row/bank/end boundaries, reset discard, refresh and CPU/DMA lock pass. Top lint
and174-source/9-QIP preflight pass. CPU cache_load_widths via adapter passes at
0/3/11 wait settings. Fresh78MHz5M boot passes:289690 transfers,12 known fetch
faults,zero data faults,acceptedPC00006178. All848 semantic events match prior
78MHz boot; timestamps change due to reduced read latency. Logs and summary:
scratch/sdram-burst32/. No Quartus build launched; routed timing remains pending.

## 2026-11-09: JTFRAME native32-bit reads confirmed (review only)

User requested checking Jotego configuration before building. Existing controller
supports BA_LEN32 two-beat reads; romrq bcache (CACHE_SIZE=0) stores two32-bit
blocks, while xscache caches requested results. Linked cninja wrapper demonstrates
DW32. Prefer existing controller plus32-bit read assembly over replacement.
Writable RAM needs invalidation if retaining ROM-request cache entries; writes
remain masked16-bit operations. Detailed findings: docs/sdram-104mhz-ddio.md.
No RTL change, simulation, commit or build launched for this review.

## 2026-11-09: Model2 reference reviewed

Reviewed alphanu1/sega-model2-mister PLL/controller, integration, SDC and device
model. Useful pin-constraint/self-test/grouped-read ideas; no demonstrated reason
to replace our current controller before the pending input-DDIO fit. Reference
uses100 MHz dedicated180-degree PLL pin output and posedge DQ capture,13 clients,
and broad IO multicycle exceptions requiring independent validation. Its model
omits physical clock phase. Our16 MB logical RAM spans two8 MB physical banks.
Detailed findings in docs/sdram-104mhz-ddio.md; local reference files under
scratch/model2-sdram-review/. No RTL change, build or board claim in this review.

## 2026-11-09: input DDIO handoff — ready for physical fit

Replaced the discrete falling→rising SDRAM register pair with Cyclone V
ALTDDIO_IN dataout_l. This requests the dedicated input DDR resynchronization
hardware, eliminating the intended fabric half-cycle route without adding a
cycle or changing ready/destination timing. PLL remains78 MHz; intent is to
buy104 MHz margin, not just erase the78 MHz violation. Added targeted internal
capture and capture→adapter timing reports. No timing exceptions changed.

Both test-only and existing Altera vendor models pass eight78/104 MHz pin-delay
cases each, plus wrong-edge negative control. SDRAM/arbitration tests, top lint
and174-source/9-QIP preflight pass. Fresh78 MHz5M-cycle real-SDRAM boot passes
with zero data faults;848 events are byte-identical, including timestamps, to
prior78 MHz baseline. Evidence: scratch/clock-78/ddio-input-summary.json and
associated logs. Physical packing/slack and external pin timing remain unproven;
next step is one78 MHz fit, inspect new DDIO reports and global timing before
hardware sign-off. Details: docs/sdram-104mhz-ddio.md.

## 2026-11-09: 78 MHz fit42553413796 — two SDRAM half-cycle violations

Run42553413796, SHA9e354a4, compiles/fits but fails the timing gate; no RBF
artifact was published. Core Fmax74.54 MHz, setup WNS−0.298 ns, TNS−0.301 ns.
Exactly two reported setup failures: read_falling.dq_in[8]→dout[8] (−0.298)
and bit11 (−0.003). These are falling→rising transfers with6.410 ns available,
zero logic levels; worst data delay5.109 ns includes4.400 ns routing, with
−1.299 ns clock skew. Lower frequency changed placement/routing: prior104-fit
Fmax83.28 MHz did not guarantee78 MHz closure. CPU/cache paths pass; worst
reported CPU path+0.927 ns, other phone logic minimum+0.728 ns. HDMI+0.112 ns.
Slow hold minimum+0.178 ns, fast hold+0.056 ns, recovery+3.207 ns,
removal+0.986 ns and pulse width+0.641 ns all pass.
ALMs32644/41910, registers42945, M10Ks465/553, DSP38.

Next recommendation: focus only on SDRAM capture-to-transfer placement/retiming,
preserving the falling input sample and rdy/data alignment; validate and refit.
Do not restart CPU/cache optimization or waive the half-cycle violation.
Alternative lower-clock candidate72 MHz stays HF=1 but requires a fresh fit
and timebase review;74.54 MHz is this placement's limit, not a guarantee.
External SDRAM DQ input/output timing remains unconstrained: internal closure
alone cannot sign off the physical interface. Board validation remains pending.
Evidence: scratch/timing-closure/clock78-fit-42553413796/output_files/timing/.
No HDL changes, simulation reruns, push or build launched during this analysis.

## 2026-11-09: selected 78 MHz hardware clock — verified build candidate

User selected 78 MHz, superseding the earlier 52 MHz proposal below. Both PLL
outputs now request 78 MHz; unused output1 has −3205 ps phase. The physical
SDRAM clock remains inverted DDIO from clk_sys, with HF=1 and negative-edge read
capture unchanged. SDC still derives the actual PLL clocks; no timing exceptions
or artificial clock periods were added. A routed 78 MHz fit remains pending.

Hardware propagates SYS_CLK_HZ=78000000; module/simulation defaults remain104 MHz.
Known wall-time rates are preserved: LCD divider16→12 (6.5 MHz), SIM32→24,
NOS tick104000→78000, UEM RTC/alarm dividers, transport one-second timeouts and
SDRAM refresh6800→5100 (65.3846 us). The rounded fast counter is3174→2380.
Existing unresolved UPP timer/boot-delay cycle semantics remain unchanged and
therefore take4/3 as much wall time; no speculative26 MHz timer model was added.
Details and remaining hardware assumptions: [phone clocks](phone-clocks.md).

Validation: dual104/78 MHz rate checks pass; native video passes at divisors16/12;
four-state SDRAM passes both actual clock periods at0/.25/.5/1 ns output delays,
with the104 MHz wrong-edge negative control still failing as expected. Source
preflight174files/9QIPs and top structural lint pass (PLL/HPS remain stubbed there).
Fresh78 MHz real-SDRAM boot passes5M clocks:289108 transfers,12 known fetch faults,
zero data faults, accepted fetch PC00006178, last accepted fetch20 clocks before
endpoint. All848 ordered semantic board events,121 writes and12 fault records
match the104 MHz WB baseline. Timestamps differ as expected after scaling refresh;
last write190170→190272 cycles. Five million clocks represent64.103 ms instead of
48.077 ms, excluding initialization/reset. No full CPU suite rerun was needed for
this clock/parameter-only change; prior WB functional evidence remains below.

The first78 MHz test exposed a testbench endpoint assumption: an idle fetch bus
address can be zero while execution is progressing. The final guard checks a
recent genuinely accepted F-stage packet (valid, unstalled, awake and uncleared),
retaining all transaction/fault assertions. The final accepted-fetch age20 passes
the10000-clock bound. Failed diagnostic logs and final reproducible source hashes,
rate/SDRAM/boot logs and event comparison are in scratch/clock-78/, with summary
validation-summary.json. This establishes simulation behavior, not routed timing
closure or physical phone/SDRAM stability. Next: one78 MHz fit, then board tests.

## 2026-11-09: WB fit42548353482 — stop104MHz loop; lower-clock bring-up next

Run42548353482 SHA c14eac3 compiles/fits; core setup fails. Compare retained
pre-WB cache baseline6adaf61/run42527340861 (admission refinement reverted):
Fmax85.68→83.28MHz; WNS−2.056→−2.393ns; TNS−2920.769→−2390.386ns
(18.16% smaller magnitude). ALMs32794→32489 (−305), registers43569→43407(−162),
M10Ks465/DSP38 unchanged. Versus rejected admission fitFmax72.40→83.28,
TNS−5857.134→−2390.386; do not attribute combined revert+WB gain solely toWB.
HDMI+.266; hold/recovery/removal/pulse minima+.214/+2.304/+1.079/+.961 pass.
Worst full-cycle reset_drain→NOS status−2.393ns,11.274nsdata/7levels. Reported
Fmax matches that full-cycle requirement. Functional172PASS, ordered effects and
848-event timestamp-identical boot remain valid; no new tests in analysis.

WB targeted results: reservation−.743, payloadcapture+2.619, localcommit+3.791,
reservationfeedback−1.178, downstreambus−1.323. Intended live merge→widepayload
cone successfully broken; allocation/drain control remains. Cache requestowner
−.702, owner→tags+1.829,pipeline+1.507,response+1.426. No104MHz closure claim.
Top1000 endpoints include sparse146,WB123,issue90,fetch88,LCDframebuffer73,
cacheaccess61,tags56,R55,predecode44,MDI33,maintenance31; others200.
Full groups scratch/timing-closure/wb-fit-42548353482/endpoint-groups.json.

User checkpoint decision applies: improvement insufficient for continued open-ended
104MHz optimization. Retain WB change (lower area, healthy commit seams, explicit
small cycle cost); next target52MHz CPU/cache/SDRAM for functional board bring-up.
52 is a conservative proposed bring-up point, not measured/stable hardware yet.
Do a fresh52MHz fit and all timing checks; audit every timebase, SDRAM refresh/init/
HF parameters, inverted DDIO/read-capture relationship, video/audio derivation and
cross-domain assumptions. PLL Fmax extrapolation alone cannot establish stability.
Do not simply change SDC or slow peripherals unintentionally. Preserve interface
edge contracts and verify fresh SDRAM simulation, then board diagnostics/firmware
boot towards working phone. Defer further CPU/cache optimization until hardware
correctness evidence justifies it. This turn only records analysis/recommendation;
no clock edits, commit, push or new build launched.

## 2026-11-09: pipelined write-buffer reservation — validated fit candidate

After isolated revert62c3707 restored original cache L0/Quartus guards, only the
write-buffer implementation changes. Acceptance immediately reserves group/word
capacity and line hazards; a registered local commit writes captured payload one
clock later. Tail slot/length/next-address summary removes dynamic last-slot merge
reads. Per-slot/per-word enables replace the live new_group path that drove432
loads in fit42542334870 (worst sampled buffer−1.536ns). Four groups/sixteen words
remain the complete capacity; the pending packet is already counted, not an extra
queue entry. Committed prefix gates bus issue; reserved length gates retirement.
Reset, errors/retry, held bus beats and same-edge merge/pop/reuse remain precise.
Contract: [write-buffer reservation](write-buffer-stage-contract.md).

Frozen-reference local latency: accept→issuable0→1clock, sustained enqueue interval1
unchanged. Four/eight-word streams take4/8→5/9clocks from first acceptance to last
ACK, only+1startup rather than a per-word throttle. Independent logical FIFO/byte/
hazard oracle passes12,021clocks:1347 groups,328merges,496crossings,160wraps,
1989errors. Coverage includes24 pending words killed by reset,1038full retire/new
reservations,1021ACK+error cases and4head-merge+ACK cases. Directed capacity,
commit/append, reset/reuse, held-beat and immediate-hazard checks pass. Cache
lookup latencies,384stream requests and24cancellation tests remain unchanged.

Full regression172PASS+1expected legacy XFAIL, all152CPU cases including44SWP
IRQ/FIQ edge×wait tests. Main mixed0/3/7/15/31 timing/phases/counters are identical:
243457/333957/408273/634683/1095735clocks, cached bodies1464/1720/2067/2791/4243;
warm ADD1, load-use minimum20, branch minimum14. All21,118 architectural effects
match byte-for-byte. Fixed four-program/two-wait total1729858→1729866 (+8,
+0.0004625%), from cache_drain+4 at each wait; legacy135782/234446 unchanged.
Other diagnostic absolute counts are retained in JSON, not assumed identical.

The512-WT-halfword-store FIQ fixture exposes the cost:0wait260172→260305 (+133,
+0.05112% of total),3wait360910→361421 (+511,+0.14159%). These setup-heavy totals
do not imply negligible handler-body cost; isolated serialized writes can expose
the extra bus-issuable clock through drain/fetch ordering. Targeted frozen-source
comparison confirms all22,339 ordered architectural effects and issue/retirement
counts match at each wait. No claim that the boundary is free in every workload.

Fresh5M real-SDRAM boot is byte-identical including all848 event timestamps,
121writes,12known fetch faults/no data faults,PC00006168/289114transfers,last write
190170. Phone integration,174sources/9QIPs,ONLY_CORE/legacy/assoc elaboration,
top lint and33targeted timing-query mocks pass. All49 active ARM patches reproduce;
no ARM import/source graph changes. Final RTL hashes match frozen sources.
Reproducible evidence: scratch/timing-closure/write-buffer-reservation/
{validation-summary.json,analyze.py}; prior checkpoints and failed-fit evidence
remain untouched.

Ready for one isolated routed fit. Measure reservation control, unconditional
payload capture, local commit, feedback and bus-owner paths separately. The
remaining narrow allocation/retirement and committed-length bus gating can still
be critical; routed resource and fanout effects are unmeasured. Original cache
admission, CPU forwarding, SDRAM and peripheral timing remain separate open work.
No104MHz closure claim, timing exception or clock change.

## 2026-11-09: rejected admission refinement reverted; write-buffer slice begins

Restored cache_access.sv byte-for-byte to6adaf61: original L0 from97daa8a plus
Quartus17 synthesis assertion guards. No history reset or source outside the
admission refinement reverted. Useful cache-owner, idle-drain, denied-offer and
maintenance-priority tests remain and pass11,029edges plus384stream requests/
24cancellation races with unchanged latency counts. Active49 ARM patches reproduce
exactly. The failed admission fit and functional evidence remain documented below.
Revert proof: scratch/timing-closure/write-buffer-reservation/revert/.

Next implementation is write-buffer reservation/local commit. Immediate reservation
must count toward4groups/16words, empty and alias hazards; payload becomes issuable
one clock later. Pipeline reservation for one enqueue/clock rather than accepting
an avoidable throughput throttle. Preserve ordered held bus beats and exact error/
retry behavior. No CPU/cache lookup/SDRAM redesign in this slice.

## 2026-11-09: admission fit42542334870 — reject refinement, keep original L0

Run42542334870 SHA f99ae23 compiles/fits; timing fails. Versus6adaf61:
Fmax85.68→72.40MHz; core WNS−2.056→−2.409ns; TNS−2920.769→−5857.134ns
(100.53% larger magnitude). ALMs32794→33166 (+372), registers43569→43641(+72);
M10Ks465/DSP38 unchanged. HDMI setup+.163→−.003ns(TNS−.012), now also fails.
Minimum hold/recovery/removal/pulse+.212/+1.275/+1.001/+.961 all pass.
Fmax limiter is falling SDRAM DQ[8]→rising dout[8], slack−2.099/data5.285ns on
half-cycle; global worst is LCD y[4]→framebuffer BRAM clock-enable−2.409ns.
Do not attribute unrelated placement movements directly to admission logic alone.

Targeted cache capture+0.859 passes; admission control−1.629 worsens from−1.140:
writeback pc_del3[29]→stream_hit→fast_lookup_valid→qualification→owner_kind[0].
The critical hit-dependent admission decision still exists. Owner→tags+1.328→+.004:
owner_kind[1]→selected segment(fanout192)→flag reduction. Splitting snapshots adds
a register-selection mux on the previously healthy lookup seam. Pipeline+1.259,
response+1.667 remain positive.30queries:29ok,CP15→R no_paths; admission control
has9paths, all others10. Retained completion capture+2.026/advance+1.918,
format+2.734/formattedM→issue+.603,journal+.825/+2.871 all pass.
Operand residuals pointer→issue−1.219, allR→ALU−1.721, M→issue−1.417,
execute→issue−.761, queuefeedback−.115, pointerqueue−.018, D→R−.725.
CP15 read+.564, RF→R+.440. No CPU operand closure claim.

Top1000 endpoints: LCD framebuffer296,timers209,writebuffer123,extraICU51,
cache access40,BTB35,fetch31,bootregs31,maintenance26,LCD DMA24,tags17,
issue15,other102. Sources include LCDy296,reset_drain240,cache state_ff99,
writebackPC90,prefetch-state56. Full grouping saved alongside downloaded artifacts
in scratch/timing-closure/admission-fit-42542334870/endpoint-groups.json.
Counts are bounded worst-per-endpoint samples, not exhaustive failure counts.

Recommendation: revert ONLY admission refinement3e344cc in a separate commit,
retaining original registeredL0 cache stage97daa8a and Quartusguard6adaf61.
Preserve experiment evidence and useful tests. Stop iterating on wide capture:
root control is hit-dependent acceptance; narrowing its endpoint did not shorten
that decision. Continue planned write-buffer reservation/local-enable redesign,
then address instruction fast-hit/admission ownership as its own bounded protocol
change if still critical. Stabilize SDRAM transfer/address timing separately; its
large fit-to-fit movement obscures domain frequency comparisons. Do not call the
current refinement a win merely because capture is positive. Functional tests
remain172PASS/identical cycles/effects/848-event boot; no functional regression
observed. This report makes no RTL edits/revert/commit/push/new build.

## 2026-11-09: cache admission refinement — validated fit candidate

The remaining request→owner−1.140ns cone now terminates at a narrow registered
one-hot owner selector. Three independent address/segment candidate records sample
without live hit/ACK/admission control; demand and maintenance hold throughout busy
ownership. Their existing address storage is reused, and selection occurs before
the existing tag-read edge. No new stage or acceptance rule. Epoch cancellation,
maintenance priority, serial response ownership and stream throughput are retained.
Quartus17 translate_off/on guards are preserved; no ARM import changes, so49
active patches through0050 remain the exact provenance baseline.

Directed cache tests and frozen-source comparison pass with identical isolated
latencies: read hit4 visible/5 sampled, clean miss23, WB store5, uncached3,
MVA clean12, indexed invalidate5, all512 invalidate1538. The logical-owner oracle
checks11,029edges;384 sequential resident requests,24 cancellation races,24 changing
idle candidates during stalled buffered write drain,8denied offers and maintenance-
versus-store priority pass. Unaccepted virtual snapshots cannot affect background
FIFO bus records or the retained accepted physical-address hazard query.

Full regression172PASS+1expected legacy XFAIL. All152 CPU absolute cycle counts
and reported counters/phases match6adaf61's functional baseline, including44 SWP
IRQ/FIQ edge×wait cases. All five0/3/7/15/31wait results are identical: totals
243457/333957/408273/634683/1095735, body1464/1720/2067/2791/4243, warmed ADD1,
load-use minimum20 and branch minimum14. All21,118 architectural effects match
byte-for-byte. Fixed four-program/two-wait mix remains1729858; legacy0/3 smoke
remains135782/234446. Fresh5M real-SDRAM matches all848 events and timestamps
exactly (121writes,12 known fetch faults/no data faults,PC00006168,289114transfers,
last write190170). No performance cost was added by this admission refinement.

Phone integration,174sources/9QIPs, provenance, ONLY_CORE/legacy/assoc elaboration,
top lint and30 targeted timing-query mocks pass. Final RTL hashes match the frozen
sources. Evidence and reproducible comparisons:
scratch/timing-closure/cache-admission/{validation-summary.json,analyze.py}.
Contract: [cache lookup ownership](cache-lookup-stage-contract.md).

Ready for one isolated routed fit. Actual snapshot FFs are lookup_demand_mva,
lookup_maint_mva, lookup_ahead_mva and their segment_select companions; the one-hot
lookup_owner_kind is registered. lookup_owner_mva/segment_select are now selected
combinational aliases. Separate capture/control probes prevent a moved path from
being hidden. The post-register selector consumes some previous owner→tags margin;
that fit's+1.328ns does not establish this candidate's timing. Narrow admission,
lookup selection, resources and other known CPU/cache/SDRAM/peripheral paths still
need routed evidence. No104MHz closure claim, new timing exception or clock change.

## 2026-11-09: cache fit42527340861 — registered lookup passes, admission remains

Run42527340861 SHA6adaf61 compiles/fits; only passing-timing gate fails.
Correct comparison is restored pre-cache71b8940/run42516106759, not rejected0049:
Fmax86.15→85.68MHz, WNS−1.928→−2.056ns, TNS−2079.311→−2920.769ns
(40.47% larger magnitude). ALMs32992→32794 (−198), registers43338→43569 (+231),
M10Ks465/DSP38 unchanged; memory bits2482539. Relative to rejected forwarding fit,
Fmax77.97→85.68 and TNS−4933.783→−2920.769, but that bundles revert and cache change.
HDMI+.163; hold/recovery/removal/pulse minima+.237/+1.462/+1.120/+.961 all pass.
Global worst is SDRAM wr_l[1]→sdram_a[12] duplicate,12.073ns data/7logic levels,
−2.056ns. Fmax is consistent with that full-cycle path, not the earlier DQ half-cycle.

28 targeted queries:27ok,10paths each; CP15→R no_paths as intended.
Cache owner→tags+1.328, lookup pipeline+1.829, response+1.129 demonstrate that
registered address/segment removed the former live-request→metadata-read cone.
But request→owner−1.140 remains: writeback pc_del3[5]→stream_hit→adapter/state
qualification→lookup_owner_mva[11]. The register has localized the slow admission
cone, not eliminated it. Do not mark complete104MHz cache closure.
Residual metadata−1.457 is commit_mva→victim selection/range compare→victim update,
separate from owner→lookup snapshot. Positive completion capture+1.389,
completion→R+.803, formatter+3.432, formattedM→issue+1.577, journal+1.343/+3.159.
Operand residuals: D→R−1.028, pointer→issue−1.726, pointer→queue−1.083,
M→issue−1.585, execute→issue−.869, CP15 response−.002. Pointer queue loop is
selected control→shift_lock/load lock→read_slot; no wide promotion copy returned.

Top1000 endpoint groups: writebuffer222, ICU175, LCD framebuffer93, LCD DMA65,
predecode59, cache transfer57, issue47, MDI39, BTB33, cache bank32, fetch22,
timers19, bridge15, busmerger11, cache tags10, DDR10, other91. Full groups in
scratch/timing-closure/cache-fit-42527340861/endpoint-groups.json.
352 launch reset_drain,177 bus_address[7],94 Equal8 marker,93 LCD y[3],41 read_slot.
Worst writebuffer−1.420 follows reset-qualified request→word index→merge_single→
entry-data enables; reservation/merge ownership remains relevant. Counts are
bounded worst-per-endpoint samples, not an exhaustive failing-path inventory.

Decision: retain cache owner because its intended downstream seams pass with
margin and no ALM increase versus pre-cache. Next finish request admission:
separate resident lookahead address capture from serialized demand ownership so
live stream-hit/ACK selection does not control the wide owner address capture;
preserve exact acceptance, cancellation and response matching without another
blind pipeline stage. Then original write-buffer reservation/local-enable slice
(222paths) and victim-update locality. CPU pointer/hazard/forwarding and SDRAM
address output remain explicit unresolved parallel closure topics. Cache stage
cost remains +1 hot demand (19→20 issue gap); no frequency win proven yet.
No RTL edits/tests/commit/push/build in this analysis-only turn. Prior172PASS,
21118 effects and848-event byte-identical boot remain functional evidence.

## 2026-11-08: Quartus assertion elaboration guard

Run42526326199 stopped in Analysis/Synthesis with Error10207 at
cache_access.sv:483: hierarchical simulation assertion bank.lookup_address could
not resolve. No fit/timing measurements exist for the cache stage yet. The local
SYNTHESIS preprocessor guard alone did not exclude this code in Quartus17.
Added explicit synthesis translate_off/on around the simulation assertion block;
functional RTL and simulation assertions are unchanged. Source preflight passes
174files/9QIPs; directed cache regression passes, including384 streaming requests and24
cancellation races, with unchanged latency metrics.
Replacement build required; previous functional/boot evidence remains applicable.

## 2026-11-08: cache lookup ownership — validated fit candidate

After reverting failed forwarding patch0049 in57bf13d, slice2 captures accepted
cache address/kind/epoch and an eight-bit segment select before tag/flag reads.
Only this registered owner drives the bank; it holds through store/refill/retry/
drain/maintenance. Existing64-way metadata and two stream lines remain. Registered
lookahead tokens retain address/epoch, and acceptance, mutation or context changes
cancel every speculative stage. I lookahead is ACK-independent PC+16. No new QIP,
write-buffer redesign, translation redesign, clock change or timing exception.
Contract and exact stage boundaries: [cache lookup ownership](cache-lookup-stage-contract.md).

Frozen-source differential: cached hit3→4 visible-response clocks (caller samples
4→5), clean miss22→23, WB store4→5, MVA clean11→12. Uncached3, indexed invalidate5
and all512 invalidate1538 are unchanged.384 resident ARM/Thumb requests cross16
lines at one per clock with no speculative bus transfers;24 stage×cause cancel
races and poisoned-after-accept inputs pass. Warm CPU load gap19→20 decomposes as
11pre-accept +4→5cache service +1owned completion +3dependent release. The11
pre-accept clocks remain a separate future latency target, not cache-hit service.

Full suite172PASS+1expected legacy XFAIL,152 CPU cases including44 SWP IRQ/FIQ
edge×wait cases. Independent operand oracle56,251clocks; frozen reference17,160.
Mixed waits0/3/7/15/31 totals243457/333957/408273/634683/1095735 are baseline
+52/+54/+51/+51/+51; setup+2 each. Cached bodies1414/1668/2018/2742/4194 become
1464/1720/2067/2791/4243. Warm ADD stays1clock, load-use minimum20, branch minimum14;
accepted-fetch/issue/retirement counts match. All21,118 architectural effects match
byte-for-byte. Fixed four-program/two-wait mix1729724→1729858 (+134,+0.00775%);
its setup-heavy total does not hide the separately reported cached-body cost.
Legacy0/3 smoke remains135782/234446. Full diagnostic case cycles are retained in
the JSON; interrupt/phase-sensitive diagnostics are correctness tests, not a
single comparable throughput benchmark.

Fresh5M real-SDRAM boot is byte-identical including timestamps:848 events,121
ordered writes,12 known fetch faults/no data faults,PC00006168/289114transfers;
last write190170. Phone integration, top lint,174sources/9QIPs, ONLY_CORE/legacy/
assoc elaboration and28 targeted timing-query mocks pass. Active49 provenance
patches (0001–0048 plus0050) reproduce all ARM sources;0049 remains archived.
Frozen RTL hashes match final validation. Evidence and reproducible analysis:
scratch/timing-closure/cache-lookup-owner/{validation-summary.json,analyze.py}.

Ready for one isolated fit. The new owner stage targets the measured late request
qualification→bank address→metadata route (−1.819ns in42520603079). Request→owner,
owner→tags, lookup stages and cache→response must all be measured. Fanout/resource/
placement effects remain unmeasured; CPU forwarding, SDRAM and other independent
paths remain open. This is a verified candidate, not104MHz timing closure.

## 2026-11-08: failed forwarding experiment reverted; cache slice starts

Active `rtl/arm` including UPSTREAM.json is byte-identical to71b8940/patch0048;
all48 active provenance patches reproduce exactly. Patch0049 is archived under
patches/zap/rejected/ and retained in Git history/evidence. No history reset.
The independent oracle retains the new directed producer/current-write collision
sequences and passes56,251clocks; only removed-internal mask observers are gone.
Revert evidence: scratch/timing-closure/cache-lookup-owner/revert/ (zero-byte
arm-baseline.diff and passing provenance/oracle logs). No new routed claim.
Proceed with original cache lookup request/address ownership slice; do not bundle
write-buffer redesign or retry the failed forwarding tree by default.

## 2026-11-08: late-owner fit42520603079 rejected; proceed with cache ownership

Measured a1bd4a8 /run42520603079 compiles/fits but fails timing. Versus42516106759:
Fmax86.15→77.97MHz, WNS−1.928→−2.111ns, TNS−2079.311→−4933.783ns.
ALMs32992→32527, registers43338→43232; M10Ks465/DSP38 unchanged. HDMI+.244;
minimum hold/recovery/removal/pulse+.246/+1.715/+.894/+.961 all pass.
Targeted pointer→issue worsens−1.438→−1.607; execute→issue−.776→−1.872;
M→issue−1.054→−1.765. RF→R becomes−.212, D→R−1.403, queue feedback−.289,
completion→R−.675. Captured completion payload/format remain positive:
backend→completion+1.734, format→M+2.905, formattedM→issue+1.149;
commit journal+.143/fold+2.405. CP15→R remains absent, CP15 response+.172.

Full pointer route traverses several operand_select LUTs before data reduction;
parallel source-level grants did not preserve the intended shallow routed seam.
ALU flags→condition qualification→dav→grant is now worst execute route. M SWI→
effective write qualification→owner match→grant is worst M route. Reduced ALMs
and these routes are consistent with logic factoring, not proof of independent
physical priority trees. Reject patch0049 as a timing experiment; retain evidence
and revert its implementation separately before cache work. No claim of slice1
closure. Successful completion, CP15 and stationary ownership remain baseline.

Top1000: timers483, LCD framebuffer BRAM74, writebuffer93, MDI56, RF55, issue45,
decode30, cache transfer24, cache tags21, DDR19, cache maintenance13, BTB12,
other75. Worst is LCD address→framebuffer clock-enable−2.111; SDRAM half-cycle
slack−1.606 accounts for77.97MHz. Broad placement changes remain separate from
functional behavior. All prior172PASS and848-event exact boot still stand.

Next: original cache lookup request/address-owner slice. Localize bank address
selection behind accepted ownership and preserve tagged lookahead/mutation epochs.
Do not combine write-buffer redesign. Verify cache transactions, CPU effects and
fresh boot; publish added demand cycles and warm sequential throughput. Record
revert and cache implementation separately; one combined fit after validation.
Artifacts: scratch/timing-closure/late-owner-fit-42520603079/.

## 2026-11-08: late forwarding owner selection — validated fit candidate

Patch0049 computes each stationary owner's source-match and full17-bit priority
grant before selecting the active owner. The RF fallback is resolved before the
pointer mux; wide producer/commit words remain shared. No new state, stage, cycle,
write priority, hazard, queue/kill rule or empty-PC behavior changes. This targets
the measured read_slot→early index select→match/priority→issue−1.438ns route.

Independent oracle56,251clocks passes, checking224,948/224,944 owner-port masks
against captured test packets and previous/current write events; all17 grants win
in both owners.0/3 timing243405/333903 and all phases/counters match baseline;
the1415-clock warmed schedule and21,118 effects at0wait are byte-identical.
Fresh5M real-SDRAM boot is byte-identical across all848 board events including
timestamps: PC00006168/289114transfers,12known fetch faults/0data faults.
Phone integration,49patch reproduction,174sources/9QIPs, ONLY_CORE/legacy/assoc
elaboration, top lint and unchanged24 timing-query mocks pass. Full regression
172PASS+1expectedXFAIL; all152 CPU absolute cycle counts are identical, including
44 SWP IRQ/FIQ edge×wait cases. Mixed0/3/7/15/31 setup/body/metrics/counters match
exactly; warm ADD stays1, load-use min19, branch-target min14. All21,118 effects
match at3wait. Fixed mix stays1729724; legacy0/3 stays135782/234446. No measured
cycle cost from this change. Last board write remains190170; all121writes and
all reads/faults match with their timestamps. This remains early boot, not a
physical-phone/full-OS result.

No routed result exists for patch0049. Duplicated narrow logic increases producer
address/enable fanout and may cost ALMs; pointer→immediate/PC/base selection and
hazard context remain. Queue margin was only+.023ns. Do not claim104MHz closure;
cache, SDRAM, BTB and peripheral work stay separate. Evidence is recorded
in scratch/timing-closure/late-owner-forward/validation-summary.json with frozen
source hashes and reproducible analyze.py. Earlier checkpoints/reference logs
are preserved. Implementation is ready for review and one isolated routed build;
no push/build performed by the implementation agent.

## 2026-11-08: stationary fit42516106759 — acquisition fixed, pointer issue debt

Run42516106759 SHA71b8940, implementation3b37383. Compile/fitter succeed; only
Require passing timing fails. Against42500046692: Fmax77.99→86.15MHz;
setup−1.770→−1.928ns; TNS−2998.328→−2079.311ns (30.65% smaller magnitude).
ALMs32181→32992 (+811,79%), registers43408→43338 (−70), M10Ks465/DSP38 unchanged.
HDMI+.336ns; minimum hold/recovery/removal/pulse+.165/+1.275/+1.091/+.961ns.
Fmax is consistent with falling SDRAM DQ→rising dout slack−.997ns; the worst
full-cycle path is reset_drain→MDI frame0[15]−1.928ns,9logic levels.
Separate SDRAM bank prechd→address path−1.413ns also remains.

Targeted24 queries:23ok(10paths each), CP15→R no_paths as intended, not an error.
Dedicated CP15 response+1.061ns. D→R data−1.273→−.213; RF→R+.031→+.487;
commit-source→R−.624→+.457; queue feedback−1.085→+.023 (very thin margin).
Journal capture/fold+1.678/+2.868. Completion capture/advance+2.188/+.262;
completion format→M+2.465 and formattedM→issue+1.425 all pass.
However read_slot→issue−1.438: pointer selects source index/control, then dynamic
match_source→priority select_source→data mux. This is the predicted downstream
selection risk, not a new memory latency or stale-value problem. R→ALU/source/
length/memory worst−.991/−1.211/−1.019/−1.438, all worse. Broad M→issue−1.054
is IRQ→effective write address/enable→match priority (not load formatting).
Execute→issue−.776; issue→shifter+.168; shifter recurrence−.269;
R stop→frontend+1.222; D→R context+1.862. Pointer→queue+.023.

Top1000 endpoint groups: CBUS310 (−1.567), BTB287 (−1.051), cache transfer75
(−1.253), MDI61 (−1.928), write buffer56 (−1.191), issue50 (−1.438), sparse47
(−1.198), codeflash28 (−.964), LCD DMA22 (−.874), cache tags17 (−1.080),
other47. Full endpoint grouping saved in endpoint-groups.json beside artifacts.
37 start at read_slot; 287 start at decode stall and end in BTB dav flags through
clear_btb(fanout513);310 start bus_data[2] and end CBUS written flags via
command validation→command_write(fanout297). These are bounded worst-per-endpoint
counts, not exhaustive coverage or proof that omitted blocks pass.

Decision: keep dedicated CP15 port. Stationary ownership removed wide promotion,
but slice1 is NOT timing-closed: do not count pointer→issue as a solved path.
Recommended small follow-up before broad cache edits: compute narrow source-match/
priority controls for both physical owners in parallel, then use registered owner
selection late; retain shared wide datapath where possible. Measure area tradeoff
against current+811ALMs and preserve current-edge forwarding/kill/invalid-PC behavior.
Alternative hybrid narrow selected context needs explicit cycle/ownership proof;
do not insert another pipeline stage by default. Then proceed with original cache
request/address ownership slice; request attribution should distinguish cache-hit
latency from the19-clock mixed issue gap. BTB clear fanout is a separate CPU item;
CBUS/MDI and SDRAM remain independent system closure work. No RTL edits, new tests,
commit/push/build in this report-only turn. Prior172PASS/fresh848-event byte-identical
validation remains the functional evidence. Reports:
scratch/timing-closure/stationary-fit-42516106759/output_files/timing/.

## 2026-11-08: CP15 read separation and stationary queue — validated fit candidate

Patch0048 candidate separates CP15's RF address from normal operandport0 while
preserving the existing registered response, and replaces wide head promotion
with stationary slot0/slot1 payload/context/journal owners plus narrow pointers.
Capacity-only upstream stop, immediate kill, current writes and forwarding
priority remain unchanged. Last-pop/clear hold the exposed head selector because
the existing BTB observes bubble PCs; ordinary FIFO empty-pointer toggling was
rejected (+53/+77 mixed-body clocks at0/3wait). The corrected candidate exactly
matches baseline0/3 phases/counters and the1415-clock warmed schedule, with all
21,118 ordered architectural effects identical at0wait. No extra stage/cycle.

Independent operand oracle50,491clocks and dedicated real-writeback CP15/RF
oracle13,841clocks pass. All48 upstream patches reproduce exactly;174sources/
9QIPs, ONLY_CORE/legacy/ONLY_CORE-assoc elaboration, top lint and24 targeted timing
mocks pass. Full suite172PASS+1expectedXFAIL; all152 CPU absolute cycle counts
match patch0047, including44 SWP IRQ/FIQ edge×wait cases. Mixed0/3/7/15/31
setup/body/load-use/branch/counters match exactly; warm ADD stays1, load-use min19,
branch-target min14. All21,118 effects match at3wait. Fixed mix stays1729724;
legacy0/3 stays135782/234446. No added stage or cycle penalty in these workloads.

Fresh5M real-SDRAM boot reaches PC00006168/289114transfers,12 known fetch faults,
zero data faults. All848 board events (121writes and all reads/faults) are byte
identical to patch0047, INCLUDING timestamps; last board write remains190170.
Phone integration passes. This remains an early boot checkpoint, not physical
phone/full OS validation. Evidence and frozen source hashes are in
scratch/timing-closure/cp15-stationary/validation-summary.json. Existing paired
checkpoints and earlier reference evidence are preserved. Ready for one isolated
routed build after review; no push/build performed by implementation agent.

Fit intent: remove measured CP15-address→R−1.357ns and hazard/pop→wide promotion
−1.085ns. New risks are pointer→issue mux depth/fanout and fifth-port RF read
fanout/area (previous RFstorage→R only+.031ns). Direct decode read depth and
late producer selection remain measured follow-ups. No routed104MHz claim;
completion/format seams stay unchanged. Cache/SDRAM/clock changes are out of scope.

## 2026-11-08: completion fit42500046692 — new seams pass; SDRAM limits Fmax

SHA7185914, implementation53eac60. Fitter succeeds; only Require passing timing
fails. Versus42492307815: Fmax86.61→77.99MHz; setup−1.931→−1.770ns;
TNS−2673.594→−2998.328ns. ALMs32121→32181, registers43391→43408,
M10Ks465 unchanged, DSP38 unchanged, memory bits2482536. HDMI+.140ns;
minimum hold/recovery/removal/pulse +.194/+1.149/+.894/+.961ns all pass.
Fmax regression is consistent with SDRAM falling-edge dq_in[8]→rising dout[8],
slack−1.604ns on a half cycle, data4.790ns/one logic level. This is a physical
transfer/locality bottleneck, not evidence that the new completion seam failed.

All21 targeted queries return10paths. New seams: backend→completion+1.434,
completion-valid→R+.358, completion/P2 format→M+1.144, formattedM→issue+.688ns.
Broad memory→issue improves−1.291→−.559 (remaining source is instruction-abort
control into effective writeback selection); execute→issue−.983→−.144.
Commit→journal+1.765, journal→queue+2.515, RF storage→R+.031,
decode→R context+2.224. Shifter recurrence now+.137; R stop→frontend+1.744.
Remaining: decode→R data−1.273, CP15 address→R−1.357, R queue feedback−1.085,
commit sources→R−.624, R→ALU/shift-source/shift-length/memory
−.324/−.535/−.548/−.464, issue→shifter−.240ns. RF storage margin is very thin.

Global top1000 endpoint families: cache tags160, write buffer176, LCD DMA155,
DDR adapter67, ICU66, operand queue55, MDI51, extra-register banks51, CBUS47,
CPU decode20, timers19, cache access17, other116. Exact full paths remain in
scratch/timing-closure/completion-fit-42500046692/output_files/timing/.
233 launch from reset_drain (previous768); zero from o_fsr (previous128).
The worst path−1.770 is M destination index→writeback clear→cache request→
bank_mva selection (fanout463)→read_valid_bits, not cache data RAM itself.
Write-buffer worst−1.395 is tail→merge_single→byte enables→entry data.
CP15 address→RF retains fanout194. Queue feedback follows load-lock/hazard→
promote_head(fanout171)→head data; completion_valid itself now passes.

Decision: preserve completion/registered formatting; intended seams pass and
functional validation remains as recorded. Slice1 overall timing remains OPEN.
Next focused operand change: separate CP15 RF read-address ownership from normal
port0, then localize queue hazard/pop selection without delaying hazards or adding
another stage. Check area and preserve current writes/youngest producer/CP15 drain.
Then original cache lookup-owner/address slice (160 tag endpoints), followed by
write-buffer reservation/local enables (176). SDRAM half-cycle routing needs an
isolated physical sign-off pass: otherwise whole-core Fmax can obscure CPU gains.
Do not claim cache-hit latency fixed:19-clock issue-gap benchmark still needs a
hit/TLB/phase breakdown before designing a latency improvement. No new RTL,
commit, push or build from this analysis. No clock/constraint relaxation.

## 2026-11-08: owned completion and registered forwarding validated; fit next

Patch0047 implements the measured completion/stall boundary before the remaining
operand forwarding work. Selected associative P2 requests hold until ACK captures
an owned data/abort/retry/FSR/FAR record. Registered validity releases CPU advance
one edge later; offers are suppressed while completed, and reset/WB-clear gates
new offers and kills the record. No live D-fault/ACK drives global data stall.
P2/M advance solely from that stall; the tested late-WB-kill invariant prevents
revoking an already-waiting owner. CP15 receives matching fault context and drain
counts completion. Legacy autonomous background completion remains unchanged.

Then load formatting moved before M's existing result register, and static
immediate/RAZ/PC/CPSR source classification moved into owned R context. No further
pipeline stage or priority/hazard/current-write relaxation was introduced.
The contract details ownership/kill/SWP semantics and new timing seams.

Validation:171PASS+1expectedXFAIL,152 CPU outcomes including44 SWP IRQ/FIQ arrival
cases (both new completion edges); completion oracle5546clocks, formatter8192,
operand50491 and frozen reference17160. All21,118 ordered architectural effects
match at3waits. Phone integration, ONLY_CORE/legacy elaboration, top lint,
174-source/9-QIP preflight and all47patches pass. Existing bus_access warning stays.

Cost is explicit: warm ADD1 stays; load-use minimum18→19 at0/3/7/15/31waits.
Mixed body1397/1651/2001/2725/4177→1414/1668/2018/2742/4194 (+17each), branch min14
unchanged. Setup241990/332246/406201/631890/1091490→241991/332235/406204/631890/1091490.
Fixed mix1729872→1729724 (−.0086%, phase effects); identical issue/retirement counts.
This is still+11.9075% versus pre-R, not a universal performance win. Legacy smoke
remains135782/234446 at0/3. Full absolute tables are in the operand contract.

Fresh5M real-SDRAM:PC00006168,289114transfers,12known fetchfaults/0datafaults.
All848 board events including121writes/all reads and12fault records match in order
apart from timestamps; final write189507→190170 reaches the same checkpoint.
No LCD/DDR writes, no full Symbian/hardware proof. Saved checkpoints/frozen binaries
and board/effect/reference evidence untouched. Two old elaboration text logs were
accidentally overwritten; original PASS is retained in the prior validation JSON
and the files explicitly point to new logs. Evidence/tested-source hashes:
`scratch/timing-closure/completion-forward/validation-summary.json`.

Ready for parent review, push and ONE isolated fit. Baseline remains42492307815:
86.61MHz/setup−1.931ns/TNS−2673.594ns,32121ALMs/465M10Ks. New completion→advance,
completion/P2→M formatter and formatted-M→issue seams must be measured. RF address
select/read locality and dynamic postALU matching are explicitly unchanged;
static-class capture does not fix them. Shifter, cache/bus, reset-qualified
peripheral and SDRAM paths remain separate residuals. No clock/SDC change or
104MHz closure claim; implementation agent performed no push/build dispatch.

## 2026-11-08: journal fit improves RF/resources; slice1 timing remains open

Run42492307815 /738e6a7 compiles/fits; only Require passing timing fails.
Core Fmax86.61MHz versus83.89 (+2.72); setup−1.931ns versus−1.634
(worse.297); TNS−2673.594ns versus−2680.821 (essentially unchanged).
ALMs32121 (−1035), registers43391 (−159), M10Ks465 (+1), DSP38 unchanged.
All global hold/recovery/removal/pulse checks pass. Full metrics, targeted groups,
source counts and route interpretation are in timing-closure.md below this date.

All17 targeted queries return10 real paths. Indexed RF→R now passes+.495ns,
commit→journal+.659ns, journal→queue+3.540ns. The journal has removed its intended
wide formatted-write→queue payload problem. Remaining failures include decode/CP15
select→R, late memory/execute forwarding→issue, R source selection and queue
advance/control. Broad commit_sources_to_r−.798ns is a control path through
alignment fault→request_ack→data_stall→stall→capture_head, not a surviving live
commit payload route. Global D-TLB FSR→same stop/capture chain drives128 R
endpoints, worst−1.298ns. Global reset_drain launches768/1000 paths through bus
qualification across many chips; this is synchronous functional fanout, not evidence
for false-pathing reset. The global worst moves to I-cache WRITEBACK→bus merger
address−1.931ns (21 endpoints), separate from the R acquisition boundary.

Decision: keep the validated RF/journal implementation, but slice1 is NOT104MHz
closed. Functional baseline remains161PASS+1expectedXFAIL and fresh5M848-event
cycle-identical trace; this report-only analysis does not rerun or extend boot.
Next isolate completion/stall ownership before another wide queue mux change
(promote the plan's measured-only slice5 where required by R), then resolve actual
late forwarding/source selection and RF address-decode locality. Preserve precise
faults, current-edge writes and kill/drain semantics; never simply delay global
stall. Report-only follow-up, no RTL change, commit, push or build requested.
Evidence: scratch/timing-closure/slice1-finish-42492307815/.

## 2026-11-08: slice1 read/refresh/forward follow-up validated; routed fit next

Patch0046 completes the selected operand follow-up implementation without another
pipeline edge. Compact indexed FF reads replace the forced masked tree. Exact
selected A/B/C commit words register once in a shared journal; each R owner holds
its pending C>B>A selectors, folds the previous edge on every hold/promotion, and
keeps same-edge current-write visibility through the flattened issue selection.
The queue's base registers no longer receive live load-formatted write data.
Head/reserve ownership, capacity-only upstream stop, kill/drain and late execution
hazards are unchanged. Speculative payload capture into an invalid reserve removes
pop/load-lock from its wide data enables; reserve validity still prevents replay.
The contract records transitions, age/priority and an inductive freshness proof.
No cache/TLB/buffer/SDRAM/peripheral/clock/SDC change accompanies this slice.

The RF-only indexed experiment first passed the unchanged27,451-clock oracle;
its physical comparison remains unmeasured. Final extended oracle passes50,491
clocks,29,485 captures,24,017 pops,7,670 full-pop and5,379 kills, including every
pair of consecutive A/B/C masks at all40physical indices and independent both-slot
base+journal checks. Full CPU161PASS+1expected direct-mapXFAIL,36SWP IRQ/FIQ
edge/wait cases, phone CPU integration, ONLY_CORE/legacy elaboration, top structural
lint,173-source/9-QIP preflight and exact46-patch reproduction pass.

All144 CPU fixture outcomes have identical absolute cycle counts to patch0045.
Mixed0/3/7/15/31 timing, setup/body, load-use and branch-target measurements are
unchanged; warmed dependent ADD remains1clock. All21,118 ordered effective RF/
retirement PC/CPSR effects at3waits match the saved baseline. Separate legacy
smoke remains135782/234446cycles at0/3waits. The prior stage's11.917% fixed-mix
increase remains an explicit tradeoff; this follow-up neither worsens nor repairs
that scheduling cost.

Fresh real-SDRAM5M is byte-identical to patch0045's complete848-event board trace,
including cycles,121writes,12known fetchfaults and all reads. PC00006154,
289152transfers,0datafaults,0LCD/DDRwrites unchanged. This is a bounded early-boot
regression, not Symbian/logo or real-phone proof. Historical checkpoints/frozen
executables remain untouched. Evidence/source hashes:
`scratch/timing-closure/slice1-finish/validation-summary.json`, full-cpu.log,
journal-oracle.log, timing-effects.log, effects-comparison.json and board.tsv.

Next: parent review, push and ONE isolated whole-project fit. The measured baseline
is still run42482648381:83.89MHz/setup−1.634ns/TNS−2680.821ns,33156ALMs/464M10Ks.
Check indexedRF D→R, backend→commit journal, pending selector ownership, journal→R,
R/currentW/execute→issue, remaining head pop/control, shifter recurrence and the
separate SDRAM half-cycle path. The current formatted-write→issue bypass remains;
its wider unified priority reduction and routing/fanout are physical risks, not
proven104MHz closure. No timing exception, relaxed clock or extra stage was added.
Implementation agent performed no push or FPGA build dispatch.

## 2026-11-08: operand slice1 fit: WNS improves, acquisition/refresh still fail104MHz

Run42482648381 /709f812006a5d432656d918faa390926f239cf57 compiles/fits;
only Require passing timing fails. RTL=c4cb73d, measurement=648b6be,
documentation=709f812. Core reported Fmax83.89MHz versus83.52 (+.37MHz),
setup-1.634ns versus-2.358 (+.724ns). TNS-2680.821ns versus-2151 (24.63% worse).
HDMI setup+.494ns. All global hold/recovery/removal/pulse checks pass, minima
+.231,+1.545,+.778,+.961ns. Overall Fmax is again consistent with a half-cycle
SDRAM transfer: relationship4.808ns/slack-1.153 (previous-.891), while CPU's worst
full-cycle path is-1.634. Do not interpret the small Fmax movement as absence of
operand-stage improvement or as proof of104MHz closure.

ALMs33,156/41,910 (79%,+150), registers43,550 (+677), M10Ks464/553 (84%,-1),
logical memory bits2,482,411 (-128). Resource increase is modest and within the
proposed36000ALM/480M10K stop budgets; it does not yet justify the measured CPI
cost. Current tiny reported clock gain does not establish a real-time performance
win over the previous design. Fixed-mix cycles+11.917% and warmed-body+0.2–1%
remain explicit tradeoffs until the whole target clock closes.
Artifacts/reproducible audit:
`scratch/timing-closure/slice1-42482648381/analysis/`.

All12 targeted reports return real paths/status=ok,10 paths each. Values below
are worst slack in the named source/destination sample, NOT whole-stage sign-off
or family TNS. In particular R→I excludes non-R late backend forwarding sources.

| Targeted group | Worst slack ns |
| --- | ---: |
| Decode→R data | -1.634 |
| Decode→R control/index | +1.744 |
| RF storage→R data | -.723 |
| Backend commit sources→R data | -1.213 |
| R→ALU operand | -.708 |
| R→shift-source operand | -.401 |
| R→shift-length operand | -.284 |
| R→memory operand | -.476 |
| R queue feedback | -.674 |
| Issue→shifter | -.251 |
| Shifter/registered-ALU recurrence→shifter | -.459 |
| R occupancy stop→frontend | +1.702 |

The architectural partition materially improves all four whole issue-output
families too (including non-R sources): ALU-1.974→-1.146, shift length-1.773→-1.217,
shift source-1.881→-1.389, memory operand-2.358→-1.343. The old live issue-stall/skid
selection before the RF is gone. Remaining forwarding and backend paths still
fail; the positive capacity-stop/control samples do not imply all CPU control
paths are closed.

The new worst path is decode.o_shift_source_ff[1] ->RF port-B equality decode
(two cells) ->masked RF read reduction(four cells) ->capture_data committed-write
bypass ->head capture/refresh/promotion select ->R.head_data[60]. Eight levels,
10.436ns data. New R data endpoints148 (head76,tail72), worst-1.634/-1.509.
Backend refresh starts at M.mem_load_ff2 ->load formatting ->writeback.wdata2 ->
committed-base override ->head_data(-1.213). RF storage itself→R is-.723.
Queue feedback is held-index→load-lock checks→pop/enable→tail_data (fanout128),
not a reintroduced combinational upstream-ready chain. This is a specific read/
commit/queue data-path problem; adding another frontend stage blindly is not
supported by the reports.

Worst1000 endpoint groups sum1000; cutoff-.739ns:

| Area | Paths | Worst slack ns |
| --- | ---: | ---: |
| Other CPU frontend/execute/register file |449|-1.528|
| Cache metadata |154|-1.428|
| Operand acquisition/held bases |148|-1.634|
| Write buffer |76|-1.088|
| Peripheral response |35|-1.457|
| UEM CBUS |28|-1.229|
| MDI hypothesis |24|-1.364|
| Sparse CAM |21|-1.142|
| LCD framebuffer readout |16|-1.132|
| Diagnostics |11|-.892|
| Test SIM |10|-1.128|
| Peripheral staging RAM |10|-.976|
| NOS I/O |5|-1.556|
| CPU bus response/fault |3|-1.107|
| NOR |3|-.993|
| ICU |3|-.739|
| SDRAM |2|-1.153|
| Timers |1|-.974|
| Other cache controller/refill |1|-.943|

CPU597/cache231=828/1000. BTB valid flags alone account for297 CPU endpoints,
previously0 in the top1000: predecode.skid[0] ->uop/control selection ->o_clear_btb
(fanout513) ->dav[]. This newly prominent family and added R endpoints help
explain why improved worst slack does not imply better aggregate TNS; do not
attribute all529.821ns TNS delta to these samples without complete endpoint data.
Cache metadata includes93 reset-driven dirty flags; its worst is D-TLB busy ->
bank_mva selection(fanout463) ->flag snapshot. These are not new cache RTL changes.
Ranked subsets and placement change; absence is not timing closure.

Decision/recommendation: retain the owned R architecture as a measured candidate,
but finish slice1 before starting cache/translation slice2. First do the compact
original indexed FF RF-read A/B experiment permitted by the architecture plan,
with identical R/forward/hold/write-refresh contracts and zero additional latency.
The current D→R route spends six cells in decode/read reduction before commit and
queue selects; establish which RF mapping best meets both timing and area, rather
than retaining the masked tree on principle. Use the oracle/CPU/boot checks and
an isolated fit. Compact RF alone is not guaranteed to fix refresh or late forward
paths: next inspect same-edge write capture/refresh and redundant priority/data
mux reconvergence with a precise ownership/proof contract. If necessary evaluate
registered read-select context at D, quantifying any new decode-stage debt.
Keep immediate write visibility and long-stall freshness; no extra stage, stale
snapshot, delayed stall or timing exception to make the report green.

Before claiming slice1 complete require its data/refresh/forward/queue paths to
meet104MHz within budget, then review CPU frontend BTB clear and later cache lookup
ownership as separately measured work. SDRAM half-cycle physical closure remains
mandatory for whole-domain Fmax. This review made no RTL edits, new functional
runs, commit, push or new build dispatch; measurement exporter works in real STA.

## 2026-11-08: owned operand acquisition slice1 validated; fit pending

Parent reviewed implementation c4cb73d and the validated-source hashes. Proceed
with one isolated fit; no cache/translation/SDRAM slice starts before its result.
The timing export additionally records12 targeted stage families (worst10 each)
under operand-stages/, including missing/error query status; global timing checks
are unchanged. Host exporter mocks pass, but real STA coverage remains unmeasured.


Patch0045 implements the first architecture slice only. A two-entry owned R packet
separates D's direct RF reads from late issue forwarding and replaces the old skid.
Capacity-only upstream stop does not depend on current hazard/forwarding; both
slots refresh committed bases every hold/capture/issue edge with actual RF C>B>A
write priority. CP15 drain includes R occupancy, redirects cancel younger packets,
and issue supplies its own bubbles. FF RF storage/banks and the ALU-to-shifter late
bypass remain. No cache, MMU/TLB, peripherals, firmware/storage, clock or SDC change.
Exact contract and full absolute cycle tables: [cpu-operand-stage-contract.md](cpu-operand-stage-contract.md).

Validation:161 PASS+1 expected legacy direct-map XFAIL, including36 new IRQ/FIQ
SWP arrival cases across D/R/I/S/A/P0/P1/P2/write-half at0/3 waits. The independent
operand/queue oracle passes27451 clocks, including5088 full-pop events, unique
packet identity, live CPSR, long stalls, same-edge writes, all40indices/4ports,
all producer priority masks, C/B/A collisions, clears and NV-tagged exceptions.
Frozen baseline oracle passes17160. CP15 stolen-port and drain assertions pass.
The mixed diagnostic matches21118 ordered effective RF/retirement PC/CPSR effects
against the baseline at3 waits. Actual CPU phone integration, top structural lint,
ONLY_CORE/legacy elaboration,173sourcefiles/9QIPs and all45patch reproduction pass.
Separate legacy direct-map CPU smoke passes at0/3waits (135782/234446cycles).
Preexisting board bus_access lint warning remains; no new operand loop is reported.

Warm dependent ADD remains1clock at0/3/7/15/31 waits. Warm load-use min18 unchanged;
branch-to-target min13→14. Mixed cached-body clocks1387→1397,1643→1651,1993→2001,
2698→2725,4169→4177 (+0.2–1%). The uncached4096-iteration setup materially regresses:
0wait setup209230→241990 is explained by4095 branch→store gaps27→35;3wait setup
303604→332246 is dominated by store→SUBS summed gaps110592→139251. Fetch-response
observations increase4088 at3 waits; final observer distinguishes actual F accepts.
Fixed four-program×two-wait mix1545673→1729872cycles (+11.917%); memory subset+11.905%.
This exceeds proposed review triggers. Parent accepts a fit candidate with this
explicit uncached-workload tradeoff, NOT final performance acceptance or a real-time
speedup claim. No unrelated optimization was made to hide the regression.

Fresh real-SDRAM5M passes PC00006154/289152transfers,12known fetch faults/0datafaults.
All121ordered board writes and12fault records match the saved baseline.848vs881
board events differ only in executable UPP RAM reads0c004750–0c0047cc; no changed
side-effect MMIO reads. Same final architectural board write at189507vs189735
establishes the bounded semantic checkpoint despite the fixed-cycle PC phase shift.
No LCD or DDR writes: still early boot, not Symbian/logo proof. No frozen executable
or historical checkpoint was modified or restored into the changed model.
Evidence: `scratch/timing-closure/slice1-operand/` (full-cpu.log, operand/reference
logs, effects.diff, phone-cpu.log, boot-comparison.json, board.tsv and read diffs).

Routed timing/resources remain unmeasured; baseline still83.52MHz/setup−2.358ns,
33006ALMs/465M10Ks. Next: parent review then one isolated slice1 fit, measuring
D→R RF/CP15 selection+commit bypass, W→R refresh, R→I forwarding, queue control,
A→S recurrence and frontend stop. Do not start slice2 before that attributable
result. No push or build dispatch was performed by the implementation agent.

## 2026-11-08: whole CPU/cache/SDRAM architecture review and 104 MHz plan

Plan only: [cpu-cache-sdram-104mhz-plan.md](cpu-cache-sdram-104mhz-plan.md)
reviews the actual ef9b762 CPU pipeline, all four RF reads/forwarding and stalls,
MMU/TLB/cache/maintenance/order, UPP captured requests, NOR-backed DDR versus
physical SDRAM, DMA/SWP reservations and reset/drain boundaries. It supersedes
the narrow "more operand mux edits" next-step recommendation with an ordered
architectural proposal; it does not change the measured pass16 result below.

Recommended first slice: a registered RF-read packet before issue, replacing
old skid ownership, with every held operand base refreshed from effective RF
writes (including same-edge collision priority) and late issue/shifter forwarding.
Retain FF register storage and the adjacent-ADD ALU bypass; budget one extra
frontend edge and measure branch/load-use penalties explicitly. Compare the old
compact indexed read with the balanced tree once read and forwarding are separate;
do not assume pass16's area increase must be retained. Then register cache lookup
owner/address before fanout, stage write-buffer allocation with capacity reservation,
and replace translation/recovery glue with request-owned responses in separate fits.

The plan quantifies full-cycle and SDRAM half-cycle budgets from full-path reports,
retains the proven DDIO/falling+rising capture design, and requires physical closure
of the still-negative zero-logic DQ transfer plus real external I/O constraints.
It sets proposed resource/CPI stop limits, differential and integration gates,
and identifies the retained warmed no-NOP table-walk ordering reproducer as an open
question. Nokia assumptions, validated simulation and FPGA/board proof stay separate.

Only the plan, README index and this continuity entry changed. No RTL/test/build/
clock/SDC/firmware/storage edits, new simulation, commit, push or build dispatch.
Existing pass16 analysis and all frozen checkpoints are preserved. Implementation
has not started; review the plan before choosing its first slice.

## 2026-11-08: pass16 CPU fit83.52MHz; TNS improves55.64%, memory operand becomes worst

Run42471100156 /ef9b7621fa2ca90af250ce8d988260ebbc5e59d6 compiles/fits
successfully; only Require passing timing fails. Quartus inline-genvar fix works.
Core reported Fmax83.52MHz versus79.42 (+4.10MHz/+5.16%); worst setup-2.358ns
versus-2.111 (-.247ns). TNS-2151.000ns versus-4848.875 (55.64% less negative).
HDMI setup+.182ns; hold/recovery/removal/pulse global minima+.249,+1.544,+1.000,
+.961ns, all pass. ALMs33,006/41,910 (79%,+1515), registers42,873 (+54),
M10Ks465/553 (84%,unchanged), logical memory bits2,482,539 unchanged.
Artifacts/reproducible audit:
`scratch/timing-closure/pass16-42471100156/analysis/`.

Important explanation of differing Fmax/slack directions: previous Fmax79.42
was consistent with the half-cycle SDRAM dout path (setup relationship4.808ns,
slack-1.489ns, despite less-negative absolute slack than the CPU full-cycle path).
That half-cycle SDRAM path now has slack-.891ns. The new worst CPU path has
full-cycle relationship9.615ns and slack-2.358ns, consistent with the reported
83.52MHz limit. Full-path reports verify both relationships. Do not compare
absolute slack across half/full-cycle paths as though the clock scaling were
identical, or treat reported Fmax as104MHz sign-off. Earlier summaries correctly
quoted separate metrics but did not identify this limiting half-cycle family.

Worst1000 endpoint groups, sum1000; current cutoff-.697ns:

| Area | Paths | Worst slack ns |
| --- | ---: | ---: |
| ARM CPU decode/issue/register file |292|-2.358|
| Cache write-buffer enqueue/storage |208|-1.426|
| Cache metadata/tag flags |160|-2.143|
| LCD framebuffer readout |94|-1.335|
| Sparse CAM |94|-1.299|
| Other cache controller/refill |73|-1.728|
| DSP mailbox hypothesis/MDI |47|-1.360|
| UPP timers |12|-.703|
| Diagnostic observation |9|-1.121|
| Test SIM/card model |4|-.995|
| SDRAM transport |3|-.891|
| NOS I/O model |3|-1.059|
| Other platform/control |1|-.699|

CPU+cache account for733/1000 endpoints. The162 old direct active_maint sources
are now0; shared named ACK/unmodeled routes27→0 in this subset. CPU bus-response
and CBUS destinations29/137→0; timers253→12. Those peripheral RTL blocks were
not reworked in this pass, so credit placement/routing/subset changes rather
than inventing local architectural fixes. Their disappearance does not prove
all meet104MHz. Global stall distribution itself still exists.

Operand port families show mixed outcomes:

| Issue destination | Previous worst ns | Current worst ns |
| --- | ---: | ---: |
| ALU source | -2.111 | -1.974 |
| Shift length | -2.032 | -1.773 |
| Shift source | -1.685 | -1.881 |
| Memory source/destination | -1.481 | -2.358 |

Worst path now decode.o_mem_srcdest_index_ff[1] ->issue skid/read-index selection
(o_rd_index_3) ->register-file port-D address decode ->masked read reduction ->
issue memory-operand forwarding/result FF. Seven levels,11.109ns data delay.
Another near-worst route starts at o_stall_from_issue (-2.292ns) and traverses
that same live read-index/read/forward path. Balanced operand rewrite helps ALU
and shift length but has not solved the full operand boundary; no extra cycle
was introduced. The roughly1515-ALM cost is significant and should be tracked.

I-cache lookup context is another independent CPU/cache limit: cache control/
stream_hit ->bank_mva selection ->tag flag snapshots. bank_mva[6] has fanout471;
81 read_dirty_bits and55 read_valid_bits endpoints appear. All160 metadata
paths have worst-2.143, not the old reset-driven dirty-write family. The dominant
I-cache comb-control source reaches165 endpoints across cache groups.
Write-buffer paths mainly start at tail (200 total sources), selecting the last
slot ->merge eligibility ->new_group (fanout404) ->word/data enables. The earlier
stored-address->physical-hazard->refill->enqueue family remains absent; current
buffer worst-1.426 versus-1.307, so do not claim all buffer timing improved.
LCD94 are framebuffer read/forward-enable paths, not unknown panel commands.

Recommended CPU-first next step: isolate and restructure port-D skid/read-index
selection plus register-file read/forwarding; preserve held operands, older-stage
write visibility, PC/banked modes, SWP and one-cycle warm ADD. Predecoded/captured
read context may help but must not make a stalled operand stale or silently add
a pipeline cycle. Separately localize I-cache bank-MVA/lookup context before its
large flag-read fanout. Keep these separate from further buffer/peripheral work
and measure each contribution where practical. No blanket register-file BRAM
conversion, stall delay or timing exception is justified by these reports.
Analysis only: no new RTL edit, test run, commit, push or build in this review.

## 2026-11-08: fix pass16 Quartus inline-genvar parser failure

Run42468961226 /e6d146b stops in Analysis/Synthesis, before a fit: Quartus17
reports10170 on the three inline `for (genvar ...)` declarations in the new
zap_register_file read tree (lines95,98,110). The parser restriction previously
encountered in cache metadata was missed during review. This run provides no
new Fmax, slack or area result; baseline remains79.42MHz/-2.111ns.

Declare port_no/reg_no/node_no at module scope and reuse them in generate loops.
No read-tree geometry, logic, ports, latency, forwarding or stall change.
Patch0044 records the compatibility-only edit; all44 patches reproduce exactly.
The source preflight now rejects inline-genvar loops in the compiled HDL graph,
ignoring comments. It rejects the failing source before the fix and passes after;
focused guard cases include comments, external declarations and multiline loops.
This guard is not a substitute for Quartus elaboration/synthesis.

Operand oracle passes17160 cycles; top-level structural lint and source graph
pass172 required files/9 QIPs. No expensive full CPU/boot rerun for a declaration-
only elaboration fix: the previous122 PASS+1 expected XFAIL and byte-identical
fresh5M boot remain the functional evidence for the CPU changes. Evidence:
`scratch/timing-closure/pass16-42468961226/`. Commit/push this fix and dispatch
one replacement build; do not automatically monitor it. No savestate restored.

## 2026-11-08: CPU demand completion separated from maintenance-idle ACK (pass16 step2)

The measured D-cache active_maint->ACK->CPU global-stall path came from an idle
housekeeping ACK term. D-cache rd|wr is exactly CPU data strobe; core qualifies
data_stall with that same strobe, so this idle term cannot authorize execution.
A separate request_ack now carries same-cycle demand/fault/TLB-retry completion
to the core's stall input. The original shared ACK is unchanged for translation
retention, lookup recovery and instruction/prefetch consumers. CP15 maintenance
done, bus handoff, data/fault payloads, SWP locks and all pipeline clocks/controls
are unchanged. Legacy cache and ONLY_CORE retain the original ACK. There is no
stall delay, additional completion register or extra CPU cycle. D-cache fast-hit
is tied off, removing active_maint from its combinational demand-completion cone.
The high-fanout global stall distribution remains; routed timing is unmeasured.

Focused demand/housekeeping tests pass4741 clocks plus a64-case fault/walk matrix:
waited reads/writes, exact-once clean/invalidate, lockdown and reset cancellation.
The fixture retains/checks the original ACK equation. CPU regression additionally
compares the new completion with original ACK on every strobed transfer and
checks original-vs-new global stall each clock. A2048-case Boolean enumeration
also proves strobed stall equality. Initial fixture ACK-from-STB feedback caused
a simulation convergence loop; using the real enclosing bus mux's accepted-request
boundary fixes the fixture. No RTL workaround was added for that test error.

Actual CPU phone integration passes SIM/DMA/queued LCD/local faults/diagnostics,
IRQ/FIQ and waited SDRAM. Fresh real-SDRAM5M boot passes PC00006178,
289197 transfers,12 known fetch faults and zero data faults. All881 board events,
including timestamps, are byte-identical to permanent pass15 final-board.tsv;
all121 ordered writes and12 fault records match. This early bound has no LCD
or DDR writes; the directed actual CPU fixture covers LCD and later accesses.
No historical savestate or frozen executable/checkpoint was touched.

Top-level synthesis-path lint, ONLY_CORE elaboration and source graph pass
(172 required files,9 QIPs). Patch0043 reproduces the imported tree exactly;
UPSTREAM.json lists the complete ordered series. Full CPU regression completes
122 PASS (the prior120 plus two new fixtures) and1 expected legacy direct-map
XFAIL, with no completion/stall equivalence failures. Warm ARM ADD remains
one clock at0/3 waits (120 warmed samples each). The suite covers SWP read/write
aborts and IRQ/FIQ, banked execution, load widths/alignment, LDM/PC dependencies,
cache maintenance/lockdown, MMU/TLB ordering and instruction/data timing.
Evidence: scratch/timing-closure/pass16-cpu/{full-cpu.log,phone-cpu.log,
boot-real-sdram.log,boot-comparison.json,final-board.tsv,patch43-verify.log}.
Step1 commit7e6c73b; step2 is a separate validated completion-boundary change.
No peripheral, firmware, clock/SDC, reset-distribution or memory-owner changes.
Latest measured fit remains pass15/run42464280647:79.42MHz,setup-2.111ns,
TNS-4848.875ns. Neither CPU change has a new Quartus timing/area result.
No push or GitHub build was launched; parent reviews the two commits next.

## 2026-11-08: CPU operand selection preserves pipeline latency (pass16 step1)

The40-entry/four-read ZAP register file now decodes each physical read address
locally and reduces masked words through an explicit balanced tree. Issue resolves
forwarding priority on narrow match controls before a masked word reduction.
Priority remains immediate,RAZ,PC,CPSR,combinational ALU,registered ALU,
postALU0,postALU1,postALU,memory,register file. PC alignment remains qualified
by the original load/store controls. All writes, bank mappings, skid buffering,
reset/clear/stall controls and pipeline boundaries are unchanged; no read clock
or extra pipeline stage was added.

A new independent scoreboard/priority-oracle fixture passes17160 cycles against
both the original and changed source: all40 physical registers (banked/SPSR
included), all64 forwarding-valid masks, special-register/immediate collisions,
random independent read ports, all three write-port collisions, stalls and clears.
It runs from tests/cpu/run.sh. Warm dependent ARM ADD remains one clock at0/3
memory waits (120 warmed samples each). Patch0042 reproduces tracked imported
source byte-for-byte; UPSTREAM.json's modification list is reconciled through0042.
Source graph passes. Evidence: scratch/timing-closure/pass16-cpu/.

Full CPU/phone integration, bounded fresh real-SDRAM boot and synthesis lint
will run once with the separate demand-completion/stall change. This step targets
the measured decode->register-read->issue cone; improvement in routed timing,
area and fanout remains unmeasured. Latest fit is79.42MHz/setup-2.111ns.
No clocks, exceptions, peripherals, firmware or saved checkpoints changed.

## 2026-11-08: pass15 targets shrink, overall fit79.42MHz; CPU/peripheral command paths dominate

Run42464280647 /9d37d3345ac8e9107e55d89d37295dedd46da19c compiles/fits
successfully; only Require passing timing fails. Core reported Fmax79.42MHz
(previous80.17,-.75MHz); setup-2.111ns (previous-1.945,-.166ns), TNS-4848.875ns
(previous-4732.980,2.45% worse). HDMI setup+.454ns. All hold/recovery/removal/
pulse checks pass: global minima+.180,+1.093,+.857,+.961ns respectively.
Core hold+.247ns; the new reset-driver recovery/removal are positive. No timing
exception was added. ALMs31,491/41,910 (75%,+698), registers42,819 (+1390),
M10Ks465/553 (84%,+3); logical block-memory bits remain2,482,539. Resource delta
includes replication/fit effects; do not attribute every extra register or M10K
to the4x32 merge metadata alone. Artifacts and reproducible endpoint audit:
`scratch/timing-closure/pass15-42464280647/analysis/`.

Worst1000 endpoint groups, sum1000 (all exported paths violate setup):

| Area | Paths | Worst slack ns |
| --- | ---: | ---: |
| ARM CPU decode/issue/ALU |261|-2.111|
| UPP timers |253|-1.501|
| Sparse CAM |144|-1.611|
| UEM CBUS |137|-1.784|
| Cache write-buffer enqueue/storage |92|-1.307|
| DSP mailbox hypothesis/MDI |32|-1.669|
| CPU bus response/fault |29|-1.554|
| Cache metadata/tag flags |22|-1.573|
| SDRAM transport |9|-1.489|
| NOR flash |8|-1.355|
| Other cache controller/refill |5|-1.589|
| Diagnostic observation |4|-1.680|
| NOS I/O model |3|-1.630|
| Test SIM/card model |1|-1.347|

CPU+timers+sparse+CBUS account for795/1000 endpoints. Distinguish two CPU cones:
1. Worst path: decode.o_alu_source_ff[2] ->writeback/register-file Mux3 read
   tree ->issue forwarding/operand mux ->o_alu_source_value_ff[28],7 levels,
   10.874ns data,-2.111ns slack. Shift-length register reads follow at-2.032ns.
   This is operand selection/read/forwarding, not a cache victim lookup.
2.162 paths originate from D-cache adapter.active_maint ->ack ->global
   data_stall (fanout679) ->pipeline controls. Destinations: predecode110,
   Thumb decoder31,uop sequencer14,ALU7. Registered/local maintenance completion
   and coherent pipeline-stall architecture need a separate examination; simply
   delaying stall would permit incorrect execution.

Timer253 endpoints are unit_regs (40x32 resettable latches), sourced from bridge
bus_data[6] (191) orbus_data[9] (62): literal write validation ->bad ->bank write
enables. Separate ordinary unit-bank acceptance from timer0 control validation;
BRAM/synchronous read/reset scrub for pure latches is the analogous storage
opportunity to ICU-extra, retaining real control/status state separately.
CBUS137 start at bus_sel[2] and traverse value extraction ->extra/whitelist ->bad
->command_write (fanout134). Destinations include written79,alarm_left41 and
command13. Stage coherent local command/validation, rather than fanning late
acceptance across all storage/counter operations.
Sparse144 includes tags105 and matched/vacant39. Live bridge address ->wide
same_request identity comparison ->global phase/cancel guards ->tag enables
or comparison snapshots. The compare/free tree itself is not the current cause;
move cancellation/commit qualification out of bulk storage paths while preserving
held-request identity, cancellation and warm-reset retention contracts.

The prior three targets improve locally despite the slight aggregate regression:
- loader.slot_valid setup sources284→0; remaining registered reset sources39
  (22 tag flag snapshots plus17 other endpoints), with SynDup drivers visible.
  Old277 reset-driven dirty-flag endpoints are absent from this subset.
- NOR86→8, worst-1.887→-1.355; old mem_wdata launch endpoints→0.
- buffer250→92, worst-1.412→-1.307; old stored-address sources222→0.
  Current buffer routes start mainly at tail (83), through last-slot selection,
  next-address merge eligibility and per-word enables, rather than the old
  physical-line hazard ->refill ->enqueue loop.
Metadata284→22 and diagnostics8→4 also shrink. Shared named ACK/unmodeled union
3→27 now reaches the bridge return family; it is not proof of shared peripheral
write authorization. Counts refer to different ranked subsets: removed paths
may still fail below the1000th cutoff (-1.046ns). Unchanged blocks can worsen
with a different placement; no broad104MHz improvement is established.

Recommended next work: CPU register-file read/forwarding and maintenance/stall
cones are now the Fmax priority; timer-bank local command/storage, CBUS local
command staging and sparse identity/commit separation are the high-count parallel
areas. Preserve tests/boot/forwarding and reset semantics, rather than adding clock
exceptions or another unmeasured cache-lookup stage. This is analysis only:
no RTL edit, new test run, commit, push or new build from this review.

## 2026-11-08: reset, memory-owner and refill-control changes verified

Cache refill arbitration now consumes a registered physical-line hazard snapshot,
rather than chaining the buffer's address comparisons through choose_refill and
back into enqueue enables. Every offered enqueue conservatively marks that
snapshot hazardous, so an alias newly entering the buffer cannot slip through an
old empty snapshot. Hazard release after retirement may gain one clock; request
ownership/backpressure stay held until bus termination. FIFO ready/capacity,
lookup/hit stages, ordered merging and abort/retry rules are unchanged.

Each buffer slot also captures its next adjacent byte address at allocation or
merge. Merge eligibility compares that record instead of recomputing base+length
on the ready/write-enable path. This adds4x32 metadata bits; 32-bit wrap and the
four-group/sixteen-word limits remain exact. The independent FIFO oracle passes
12021 cycles with the same1343 enqueues,329 merges,497 line crossings,163 wraps
and1998 errors. Focused buffer/cache integration passes. The associative access
fixture additionally tests dirty-victim replacement where a different virtual
line maps to that same physical line, with writes stalled and reads available;
refill must wait and return the newly written-back value.

Final CPU-board integration, memory/reset/ownership/queued-LCD/diagnostic-export
and raster checks, source graph, formatting and top-level structural lint pass.
Fresh real-SDRAM5M boot passes PC00006178/289197 transfers/12 known fetch faults/
zero data faults; all121 writes and12 fault records match9e80d10 in order.
The full board trace and timestamps are byte-identical to the owner-only boot,
showing no extra change in this early bound from step3 (which is exercised by
the directed cache tests). Full CPU/cache regression finishes120 PASS plus1
expected legacy direct-map XFAIL; warm ARM ADD stays1 cycle at0/3 waits.
Evidence is under
`scratch/timing-closure/pass15-reset-owner-buffer/`. No source/SDC clocks or
firmware changes; no historical checkpoint restored. Step1=c8a851f,step2=acbaf22;
step3 is ready to commit, then push all three and dispatch exactly one
authorized GitHub build, with no automatic monitoring. Latest measured fit
remains80.17MHz/-1.945ns; fanout replication, reset recovery/removal and actual
setup improvement require that new fit.

## 2026-11-08: captured NOR/SDRAM owner (step2)

ngage_mister now captures the disjoint {PMM,C:,code NOR,SDRAM} region once per
stable UPP bridge request. Memory launch/response muxes use that register,
without aggregate board/DMA claims or their validation tree. The bridge retains
address/data/lanes until termination and guarantees a request-low gap; the owner
clears on that gap/reset. Existing ROM/C:/PMM map and priority are unchanged.
This adds one request-capture clock to memory accesses; no firmware, media,
command/erase behavior, SWP reservation or physical memory clock changes.
Unknown non-memory accesses retain local peripheral ownership and decode faults.

A focused14-region-endpoint test poisons unrelated claims/data/errors after
capture: memory launch and held return remain correct, gaps drop ownership,
and unknown10000000 still reports reason2. It isolates NOR return records;
separate flash reset fixtures verify actual accepted DDR/drain/program/erase.
Board CPU integration and a fresh5M real-SDRAM boot pass. The latter reaches
PC00006178 with289197 transfers,12 known fetch faults and zero data faults;
all121 ordered writes and12 fault records match9e80d10 (timestamps and read
repetitions differ with the added capture clock). Evidence
`scratch/timing-closure/pass15-reset-owner-buffer/owner-*` and `boot-owner.log`.
Step3 and final combined checks/build remain; no old checkpoint restored.

## 2026-11-08: registered reset distribution (step1)

The existing flash-drain latch is now the sole phone reset driver: immediate
asynchronous assertion from the reset/readiness request, synchronous release only
when both flash engines are idle. Removing the parallel combinational OR keeps
loader flags out of every destination's reset/data-enable cone. The register uses
Quartus17-supported maxfan128/preserve so synthesis can replicate its driver
near chip/cache consumers. All replicas have identical assertion/release semantics;
no per-chip release skew, timing exception or slower clock is introduced. This
changes the reset driver's asynchronous control implementation; recovery/removal,
replication and physical fanout require the next fit, not simulation sign-off.
Attribute reference: https://resources.altera.com/quartushelp/17.0/hdl/vlog/vlog_file_dir.htm

Flash reset tests pass outstanding code/C:/PMM reads, response coincidence, cold
DDR drain, accepted programming/erase and dirty tracking; a new sub-clock warm
reset pulse must assert immediately and remain held until a release clock.
Updated stale fixture CPU observation ports and replaced ignored local .f
prerequisites with a source list generated from maintained files.qip.
Fresh real-SDRAM5M boot remains PC0000615c/306850 transfers/12 known fetch faults/
zero data faults. Entire board trace and cycle stamps are byte-identical to
9e80d10. Evidence `scratch/timing-closure/pass15-reset-owner-buffer/`.
Steps2/3 and one combined GitHub build remain; no historical state restored.

## 2026-11-08: pass14 improves to80.17MHz; reset distribution becomes visible

Run42439233437 /9e80d10148fcc18fcdf889935bc323291706d142 compiles/fits
successfully, then fails only the timing gate. Reported core Fmax80.17MHz
(previous68.31,+11.86/+17.36%); core setup-1.945ns (previous-4.622,+2.677ns).
TNS-4732.980ns versus-35764.692:86.77% less negative. Quote reported Fmax
and setup separately; neither establishes104MHz sign-off. HDMI setup+.607ns;
all reported hold/recovery/removal/pulse checks pass (global minima+.245,
+3.820,+1.118,+.961ns). ALMs30,793/41,910 (73%, down2076), registers41,429
(down4432), M10Ks462/553 (84%, up4). Fitter confirms each ICU bank is one
2048-bit M10K; low48 pads to64. Artifacts/reproducible endpoint audit:
`scratch/timing-closure/pass14-42439233437/analysis/`.

Worst1000 functional endpoint groups, sum1000:

| Area | Paths | Worst slack ns |
| --- | ---: | ---: |
| Cache metadata/tag flags |284|-1.789|
| Cache write-buffer enqueue/storage |250|-1.412|
| ARM CPU decode/issue |136|-1.538|
| NOR flash |86|-1.887|
| Sparse CAM |70|-1.399|
| DDR transport |43|-1.328|
| DSP mailbox hypothesis/MDI |39|-1.576|
| UEM CBUS |22|-1.379|
| UPP timers |17|-1.482|
| SDRAM transport |13|-1.430|
| LCD framebuffer readout |10|-1.457|
| Diagnostic observation |8|-1.334|
| Other cache controller/refill |7|-1.132|
| Test SIM/card model |5|-1.945|
| NOS I/O model |3|-1.629|
| UPP interrupt controller |3|-1.626|
| CPU bus response/fault |2|-1.470|
| Peripheral response boundary |2|-1.305|

Important source-versus-destination distinction: **all277 cache dirty-flag
endpoints start at loader.slot_valid[0]**, not the cache hit/victim lookup.
284 total paths start there (277 dirty flags,5 test-SIM,2 peripheral response).
The first two LUTs form the top-level reset/readiness cone (Template.sv reset
includes !loader_valid); its factored net has14,547 fanout. The worst path
continues through combinational test-card response construction,10 levels,
10.634ns data delay. The fitted net happens to inherit a sparse d_regs name;
it is not evidence that the sparse CAM owns the reset distribution.

The next independent worst family is flash (-1.887): bridge address decode
traverses ICU/owner priority and brd_claim exclusion into flash_start, then
NOR command/data enables. Source logic confirms mem_req excludes the aggregate
board/DMA claim even for disjoint NOR addresses. This is ownership routing,
not actual NOR chip speed. The write-buffer routes include stored-address
comparisons ->choose_refill ->new_group (fanout398) ->entry data/enables;
221 paths start at two buffer-address registers. ARM decode paths frequently
start at post-ALU signed-halfword control (160 total endpoints across groups).

The four prior targets worked: ICU-extra483→0 endpoints, CPU response/fault
35→2, diagnostics59→8 (no trace-readout /6 family), old read_victim_valid/dirty
snapshot endpoints→0. Current cache dirty writes are a different reset-driven
family. Shared named ACK/unmodeled route union38→3; absence in this ranked
subset does not prove a family meets104MHz. Sparse51→70 and buffer83→250
counts rose as more severe paths disappeared; their worst slacks improved
(-2.743→-1.399 and-3.320→-1.412 respectively), so counts alone imply no regression.

Recommended next sequence: (1) register/localize the reset/readiness release
with coherent per-chip cancellation and preserved warm/cold semantics; do not
mask reset paths with timing exceptions. This covers the shared284-path source
and worst SIM path, but SIM response construction may still need its own stage.
(2) Give NOR/SDRAM a captured regional owner so disjoint memory launch does not
traverse all peripheral claims; preserve actual overlap and unsupported-access
fault rules. (3) Rework buffer hazard/refill/enqueue control boundaries, then
review remaining CPU halfword-to-decode paths. Avoid rewriting cache tag lookup
again based solely on dirty-flag destination counts. No RTL edits, tests, commit,
push or new FPGA build were initiated by this timing review.

## 2026-11-08: four timing refactors verified; ready for next Quartus fit

All four changes from the68.31MHz review are implemented. Astra completed the
local peripheral-response boundary and three explicit ICU BRAM banks; parent
integration retains unconditional diagnostic sampling (the existing delayed event
qualifiers select completed responses), and uses separate local payload/owner/error
registers plus a balanced masked-OR return tree. A packed-register implementation
hit a Verilator V3Gate internal error in the top-level linter; separate local
registers avoid it without changing transaction timing. No aggregate ACK/error
write authorization or diagnostic payload enable was reintroduced.

Cache victim valid/dirty now select from the already captured segment flags and
victim index in the existing second lookup stage. No extra lookup clock, storage
geometry or replacement-policy change. The tag fixture checks pre-edge victim
snapshots throughout allocation, dirty replacement, invalidation, lockdown and
512 consecutive requests changing all eight segments. The full CPU regression
passes120 checks plus1 expected legacy direct-map XFAIL; warm ADD remains
1 cycle at0/3 memory waits.

Diagnostic readout replaces /6 and %6 with parallel constant halfword matches
and balanced reductions. The existing one-clock read contract, screen and NGD
layout stay unchanged; all2048 external word addresses are checked against an
independent arithmetic oracle, including metadata/out-of-range selection.
Diagnostic ring/export through actual hps_io and raster/monitor tests pass.
The unit runner's obsolete PASS-prefix check is corrected.

Combined validation evidence: `scratch/timing-closure/pass14-combined/`.
Final actual HDL CPU-board integration passes (SIM/DMA/queued LCD/local faults,
IRQ/FIQ/diagnostics/waited SDRAM). Fresh real-SDRAM5M boot passes at PC0000615c,
306850 transfers,12 known fetch faults and zero data faults. All121 ordered
writes and12 fault records are identical to6f34b89 after excluding timestamps;
board-event count changes845→881 due to read repetitions with the extra response
clock. `compare-boot.py` and `boot-comparison.json` preserve that comparison.
No LCD/DDR writes occur in this early bound; directed integration covers LCD.
Final full CPU/cache regression passes120 checks plus1 expected direct-map
XFAIL. Top-level structural lint, source graph, formatting and whitespace
checks pass. The unrelated pre-existing keypad W1C regression remains documented
below. No historical checkpoint was restored. Next action: commit/push these
four verified changes and dispatch one authorized GitHub Quartus build; do not
monitor it automatically. The last measured fit remains68.31MHz,
setup-4.622ns,458M10Ks; this work is not yet a measured104MHz result.

## 2026-11-08: local peripheral response registers and ICU BRAMs ready for integration

Points1/2 from the68.31MHz timing review are implemented. Internal CPU peripheral
returns snapshot independent local data/error cones plus one-hot ownership;
registered results feed a masked OR instead of the old live global priority
mux. The existing bridge request stays paired with the response. One added
peripheral response clock; accepted effects occur at capture and pending state
blocks repeats, including CBUS/MDI. Diagnostics now capture completed response
payload/context. External fixture response timing and LCD CPU/DMA ordering stay
unchanged. ICU low48/DMA64/epbus64 latches use three explicit BRAMs, synchronous
reads and64-edge warm-reset zero scrub independent of global cold init_done.
LCD shadow/collision exclusions now apply only to their overlapping owners.
Contract, tests and known baseline failures: `docs/peripheral-ownership.md`.

Focused ICU,33-transaction differential, actual CPU board integration, regional
ownership, SIM present/absent, LCD queue/mixed419checks, board wrapper/inventory,
fixtures, monitor/raster, bridge/reset, sourcegraph and formatter checks pass.
Evidence `scratch/timing-closure/pass14-peripheral-response/`. The pre-existing
keypad board W1C failure reproduces with pristine6f34b89 sources and is unchanged;
the diagnostic runner also has an obsolete PASS-prefix check. No fresh5M boot or
full CPU regression has yet been run for this combined change: parent integration
will do those after cache-victim and /6 diagnostic work. No checkpoint restored,
commit, push or FPGA build from this subtask; timing/resource effects unmeasured.

## 2026-11-08: fit68.31 MHz after regional/CAM/LCD/write-buffer work; choose next boundary

Reviewed42433854189 /6f34b89. Artifacts and reproducible endpoint audit:
`scratch/timing-closure/pass13-42433854189/analysis/`. Relative to d3364ea,
reported core Fmax **68.31MHz** versus69.19 (-.88), setup **-4.622ns** versus
-4.837 (+.215ns), TNS **-35764.692ns** versus-48910.486 (26.88% better).
ALMs32,869 (-576,78%), registers45,861 (+692), M10Ks458 unchanged (83%).
HDMI setup+.324ns; global hold+.244ns, recovery+3.544ns, removal+1.052ns,
pulse+.961ns. Compilation succeeds; timing gate fails. Quote the separately
reported Fmax and slack as-is; do not derive a new clock guarantee from either.

Target groups improved despite the small worst-path movement: upload RAM120
->2 endpoints, sparse CAM286 ->51 (worst now-2.743), LCD framebuffer103 ->0,
and old write-buffer pending-word/query arithmetic has no named routes in the
export. Counts refer to different ranked subsets, not proof that removed paths
meet104MHz. No new LCD or cache-pipeline rewrite is justified by this report.

Current functional endpoint counts (sum1000): ICU-extra banks483 (-3.601),
cache write-buffer enqueue/storage83 (-3.320), UEM/CBUS58 (-4.208), diagnostic
observation/readout59 (-4.622), NOR flash55 (-3.385), MDI51 (-3.483), sparse
CAM51 (-2.743), regional staging RAM40 (-3.411), timers37 (-3.269), CPU bus
response/fault35 (-4.437), remaining cache victim/tag/controller7 (-4.552),
other CPU/platform/control41 (-4.030). Shared error/ACK named-route union38
(33 ACK,6 unmodeled,1 overlap):bridge30,monitor4,diagnostics1,video3; no device
write destinations. Synthesized wb_dat_i-named LUTs also appear in address-
decode write paths; their names alone do not establish read-data feedback.

Recommended decision: next major refactor is **peripheral register/read-response
architecture**, with small independent victim-selection and diagnostic-readout
fixes. Keep coherent request/destination/data/error records and local effects;
registering a giant global mux again would just move its unchanged depth.

1. **Local read responses.** Worst path is address ->SIMIF selection ->large
   wb_dat_i mux ->monitor.sample_data,13.531ns/10 levels. Bridge master_read_data
   has another long boot/timer/board mux path at-4.437ns. Decode destination once
   and return a coherent local ready/data/error result through a registered
   owner/response boundary. Diagnostics should observe that registered response,
   with matching request/fault context, instead of adding their own always-live
   read-mux sampling burden. Optional diagnostic removal alone won't fix the
   real CPU return path. Preserve state-dependent claims, masks and read effects.
2. **ICU-extra register-bank storage/command ports.**483 paths target low_regs,
   dma_regs and epbus_regs. Their176x32 stored words are currently resettable FF
   arrays with variable reads/writes. Move memory-like latches to explicit BRAM
   with synchronous ready/readback and a reset-scrub protocol; keep true control
   flags/small probe state as registers. Preserve warm-reset zero semantics and
   avoid init_done/core_reset/scrub deadlocks. There is also a remaining global
   !lcd_dma_claim/direct-collision gate on the entire peripherals.commit in UPP;
   scope those exclusions only to their actual overlapping shadow-DMA/LCD owner.
   Do not reintroduce aggregate fault/ACK write gating. Use fitted-route and
   ownership tests to distinguish shared decoder LUTs from actual dependencies.
3. **Cache victim context: small, latency-preserving opportunity.**3 paths run
   CP15 alignment/ack/request selection ->bank_mva ->nested segment/victim/flag
   mux ->read_victim_dirty/valid (-4.552ns). Existing read_valid_bits,
   read_dirty_bits and read_victim_way already snapshot the same source edge.
   Evaluate selecting compare_victim_valid/dirty from those captured arrays in
   the second stage instead of selecting both segment and victim flags on the
   live-MVA edge. This can split the mux without another cache lookup cycle;
   verify snapshot/collision/maintenance equivalence and warm ADD throughput.
4. **Diagnostic /6 mapping.**4 routes, worst-4.188ns, still traverse a full
   divider into trace read addresses/selection. Replace with bounded decode or
   a staged table; preserve NGD layout and explicitly retime the export read
   contract if needed. This is readout, not the completed fault-capture work.

After those, CBUS accepted-write validation feeding alarm decrement/start and
MDI forwarded-pointer/tick logic remain independent limits. Do not assign
physical slower clocks or add timing exceptions to conceal these model paths.
BRAM bank conversion could improve both timing and FF/LUT area; resource use
and all clock domains must be checked in the next authorized full fit.
No RTL changes, tests, commit, push or FPGA build were initiated by this review.

## 2026-11-08: precompute write-buffer cache-line membership

Point4 is separate from LCD712c811 and its ordering correctiondb992b9.
Each1..4-word contiguous buffer group spans at most2 cache lines, including
32-bit address wrap. Its first tag is already stored in the base address;
new `last_line` metadata captures the final word's27-bit line tag at allocation
and the incoming word's tag on a validated adjacent merge. Hazard queries now
compare these two tags per active physical slot, without per-word address
addition or length selection. Query/response latency, FIFO size, merging,
byte-enable/data ordering, errors/retries and conservative retired-word hazards
are unchanged. No new cache stage, allocation policy or timing exception.
The only new metadata is4x27 bits; no inferred memory or storage migration.

Independent logical FIFO/per-word hazard scoreboard first passes the old RTL,
then the new RTL with identical coverage:12021 cycles,1343 new groups,329
merges,497 crossings,163 wraps and1998 bus errors. It checks FIFO bus beats,
readiness and exact line membership before/after updates, unrelated lines,
simultaneous merge/retire/enqueue, backpressure, zero/partial masks and reset.
Existing directed16-word-buffer tests also pass. Full CPU/cache regression with
UPP bridge finishes **120 PASS +1 expected direct-map XFAIL** (one new hazard
scoreboard beyond the previous119); warm ADD remains1 cycle at0/3 waits.

Combined final-hardware CPU integration and real-SDRAM5M boot pass, including
LCD queued commands/local faults and completion-after-pixel assertion. Early
boot remains PC00006170,306874 transfers,12 known fetch faults,zero data faults;
all845 board events/cycle stamps match the baseline. Combined result logs were
produced with this write-buffer source and the corrected LCD/DMA hardware,
then preserved from `pass12-lcd-queue/{boot,board}-order-final.log` under
`scratch/timing-closure/pass13-write-buffer-lines/`. The write buffer was briefly
restored to its previous version to separately boot-verify the LCD-only follow-up,
then restored byte-for-byte (source SHA256
`11b703464faf739b6524dc35b1114b97cb24a75a00cf3e85eca0f74882acfd85`).
Final buffer/integration/top checks reuse the same implementation. No old long
checkpoint was loaded; no new logo claim. Last measured fit remains69.19MHz/
-4.837ns; this targets the87 write-buffer-query routes from that subset, not a
claim of87 passing paths. No FPGA build dispatched or monitored.

## 2026-11-08: align LCD CPU and DMA streams across the command pipeline

Follow-up to712c811: the first queue held CPU commands behind raw DMA, which
could let a later DMA pixel overtake an accepted CPU packet. That approach is
superseded. CPU commands and DMA valid/address/data/full-frame now cross the
same one-clock boundary, preserving their original relative order (including
header+DMA on the same edge). Existing input-side direct-data/DMA collision
suppression remains. The live panel consumes one stage every clock; the generic
queue's hold/backpressure contract is retained and tested with a synthetic
consumer hold, not driven by raw DMA. DMA completion to the ICU gains the same
one-clock delay when the panel pipeline is enabled. Non-display mode retains
the original completion timing. Reset flushes pending CPU/DMA records together;
as already documented, it may cancel unconsumed work while retaining old GRAM.

A differential mixed-stream fixture compares the whole panel control state,
first32 pixels and each DMA target (covering the full18304-word address range)
against the original unqueued display with exactly one-cycle delay.419 checks
cover direct pixels followed by DMA to the same word, simultaneous header/DMA,
commands, window state, full pulses and drained warm reset. Pending-reset
cancellation is separately tested. This fixture catches the initial ordering
mistake; merely checking that queued commands were not lost did not.
Actual CPU integration additionally asserts DMA IRQ cannot precede committed
pixel data. Queue, connected board, mixed-stream and isolated CPU tests pass.
The isolated real-SDRAM5M boot also passes unchanged PC00006170,306874 transfers,
12 known fetch faults and zero data faults; all845 board events/cycle stamps
remain byte-identical. Logs `scratch/timing-closure/pass12-lcd-queue/`.
No FPGA build. This correction was boot-tested with the previous write buffer;
point4's separate source is restored only after committing this LCD fix.

## 2026-11-08: validated LCD commands cross a local board queue

Point3 implemented independently after Astra's5ac507e sparse CAM. The board
contains a one-entry `ngage_lcd_bus_queue`: late transport validation qualifies
only the pending bit; address/data are sampled independently and panel decoding
and framebuffer writes consume registered fields one clock later. DMA-valid
holds a pending command. The queue can drain/replace on the same edge; a full
queue backpressures only selected LCD writes. Controller state changes only on
acceptance. Existing direct-data/DMA collision suppression remains conservative.
Warm reset clears pending work and panel/transport state together. No added
panel frequency, unknown-command success, firmware or memory-layout change.
Standalone boards without a display retain the prior unqueued transport contract.

Random queue tests pass4000 cycles (874 commands applied,23 reset cancellations),
including held/replaced packets and changing unrelated bus payloads. A connected
board test checks full-queue waits, immediate unrelated upload writes, exact
header/data ordering, DMA hold, local invalid-header suppression and pending
warm reset. Actual CPU integration checks rejected header isolation and a valid
queued display-on command, plus SIM/DMA/IRQ/FIQ/CAM-overflow/SDRAM waits.
Known LCD transport agrees with both C++ fixtures; full18304-word DMA passes.
Retained firmware-DMA replay is explicitly SKIP (fixture unavailable).

Fresh real-SDRAM5M boot passes unchanged PC00006170,306874 transfers,12 known
fetch faults and zero data faults. All845 board events and cycle stamps match
Astra's baseline byte-for-byte; trace SHA256
`ea4112346d90486e45bca592800959d43d83b1252e8ee8d1c245a9b19ecf7ecd`.
Early boot has no LCD traffic; queued LCD behavior is established by the directed
board/CPU tests, not a new cold-logo claim. Permanent checkpoints untouched.
Regional ownership sweep, SIM present/absent, warm/cold RAM, diagnostic monitor/
raster, top elaboration and source graph pass. Full CPU/cache suite finishes
119 PASS plus one expected legacy direct-map XFAIL; warm ADD stays1 cycle at0/3 waits. Evidence `scratch/timing-closure/pass12-lcd-queue/`.
No FPGA build or timing claim. Point4 write-buffer metadata is the next separate
commit; last measured fit remains69.19MHz/-4.837ns.

## 2026-11-08: staged sparse CAM with selected-device waits

Following regional commitd329a1d, the sparse model now captures request fields,
registers parallel match/free bits, registers the priority-selected slot/result,
then reads payload BRAM before ready. Stable requests reach ready after4 rising
edges; authorized writes publish tag, valid and payload together on the next
edge. Lookup works with commit low. A terminal held request cannot execute twice;
identity changes/withdrawal cancel pending work. Warm reset retains the table
but quarantines a canceled held request; cold reset clears validity. Only the
selected non-trace0d device waits. Exact contract: `docs/peripheral-ownership.md`.

Full-address matching, lowest-index priority, capacities1/2/3/5/64, byte merges,
zeroed allocation bytes, read misses and full-table faults are preserved. Unit
scoreboards test4000 randomized requests per capacity, sustained authorization,
arbitrary commit waits, same-address dependencies, exact write counts, and
reset/cancel/replacement at each occupied stage. Board tests verify trace
exclusion under full CAM and immediate unrelated upload access after cancel.

Peripheral/fixture/diagnostic units, actual CPU SIM/DMA/IRQ/FIQ/CAM-overflow and
sticky-fault integration, top elaboration, source graph and formatter pass.
Fresh real-SDRAM5M boot: PC00006170,306874 transfers,12 known fetch faults,
zero data faults; all845 board events/121 writes and cycle stamps exactly match
regional baseline. This early boot contains no0d accesses: CAM coverage comes
from the directed/CPU integration tests, not a new cold-logo claim. Evidence:
`scratch/timing-closure/pass11-sparse-cam/`.

Full CPU/cache suite:119 PASS plus one expected legacy direct-map XFAIL;
warm ADD remains1 cycle at0/3 waits. Both restructures are verified separately.

No FPGA build or timing claim. Last fit remains69.19MHz/-4.837ns; area and timing
of both restructures need the user's next fitted reports. Cache, firmware,
storage, clocks/constraints and permanent checkpoint pairs remain unchanged.

## 2026-11-08: regional peripheral RAM ownership decoding

Replaced the shared dedicated-claim exclusion on staging-RAM writes with
regional qualifiers. Upload0c03 and aux0c06ff no longer depend on boot/scratch
comparisons. NOS0c10 excludes only MDI; GPIO15 excludes actual SIM/NOS/loopback
claims; aux12/14 retain only boot/MDI overlaps; NOS4K excludes its45 boot latches.
The ownership map is in `docs/peripheral-ownership.md`. Dedicated response
priority, SIM injection snoops, keypad overlays, LCD DMA exclusion, byte-lane
rules, read readiness and warm/cold behavior remain unchanged. No latency added.

The connected-child ownership sweep covers131072 word addresses plus896
operation/lane/config overlap cases. Peripheral units, fixtures, board CPU
SIM/DMA/IRQ/FIQ/fault tests, top elaboration, source graph and formatting pass.
Fresh real-SDRAM5M boot: PC00006170,306874 transfers,12 known fetch faults,
zero data faults. All845 board events (including121 writes and cycle stamps)
are byte-identical to the new-cache baseline. Evidence and reproducible source
cone/trace checks: `scratch/timing-closure/pass10-regional/`.

Full CPU/cache suite:119 PASS plus one expected legacy direct-map XFAIL.
Warm ADD remains1 cycle with0/3 memory waits.

No FPGA build dispatched. Timing/resource effect is unmeasured; the last fit
remains69.19MHz/-4.837ns. Cache, firmware, storage and permanent checkpoints are
untouched. Sparse CAM remains the next separate change.

## 2026-11-08: Astra High handoff for regional ownership and sparse CAM

User authorized the next agent to implement regional ownership first, staged
sparse CAM second, **in separate commits**, with tests/fresh boot for each,
then commit and push both. **Do not launch an FPGA build.** Persistent brief:
`scratch/handoff-regional-decoder-sparse-cam-astra-high.md`.
The brief references the current d3364ea/cache-pipeline baseline and latest
42417251076 timing evidence, preserves existing uncommitted review docs and
keeps other timing targets out of scope. No implementation started here.

## 2026-11-07: cache-pipeline fit69.19 MHz; peripheral decode and CAM now dominate

Reviewed42417251076 /d3364ea (fcb7dc2 cache pipeline +110b22d fixture refinement).
Reports under `scratch/timing-closure/pass9-42417251076/`; exact grouped counts
and reproducible script in `analysis/`. Core Fmax **69.19MHz** versus68.32;
setup **-4.837ns** versus-5.021 (+.184ns), TNS **-48910.486ns** versus
-56669.384 (13.69% improvement). ALMs33,445 (+1,176,80%), registers45,169
(+1,841), M10Ks458 (+2,83%). HDMI setup+.026ns; global hold+.199ns,
recovery+3.417ns, removal+1.320ns, pulse+.961ns. Compilation succeeds;
timing gate fails. Small full-core Fmax gain does not mean cache rewrite failed.

Old cache line/dirty/valid commit-path destinations are **absent** from top1000.
Direct cache destinations798 ->**74**:64 refill-data capture paths,7 write-buffer
payload/enables,3 victim valid/dirty snapshot paths. This subset does not prove
cache104MHz closure. Another23 cache-origin paths end in CPU bus merger.
All64 refill and23 merger paths traverse write-buffer `pending_words` hazard
logic. The new compare/commit boundaries exposed previously hidden limits.

Functional destination grouping (sum1000): sparse CAM286 (-4.465ns), peripheral
staging RAM166 (-4.837;upload120/NOS41/aux3/GPIO2), ICU/config106 (-3.899),
LCD framebuffer/forward104 (-4.223), timer/NOS78 (-4.093), cache74 (-4.688),
flash50 (-3.977), CPU bridge response32 (-4.695), diagnostics29 (-4.738),
MDI25 (-4.028), CPU bus merger23 (-4.444), keypad18 (-3.972), SDRAM arbiter7
(-3.930), CPU fetch/issue2 (-3.874). Named error/ACK union25, all `unmodeled`
(no named wb_ack); sparse CAM logic occurs on311 routes. Counts overlap with
destination groups and are not a claim of that many independent bugs.

Recommended next restructures, in order:

1. **Regional peripheral ownership/write commands.** Worst route: captured
   bus_address[3] fanout1245 ->boot scratch-claim exclusion ->generic GPIO write
   ->upload BRAM WE (14.612ns data,10 levels). Upload0c03xxxx cannot overlap
   the boot-register/scratch windows. Replace the global `dedicated_claim`
   exclusion with per-region ownership: upload,0c10 NOS/MDI, GPIO15, aux,
   0c004 scratch, etc. Keep only real overlaps local. Stage a coherent regional
   command/address/data/mask if needed, with exactly-once commit/response;
   don't rebuild a global ACK->all-side-effects chain.
2. **Stage the temporary sparse-register lookup/allocation.**286 destination
   paths are CAM comparison ->miss/capacity decision ->allocation/tag write.
   Capture request and matched/free-slot decisions before updating tag/payload.
   Selected-device waits only; retain full-table fault, existing-address writes,
   byte masks and cancellation semantics. Do not replace it with aliasing RAM
   or pretend it is verified phone hardware. Address nets also feed over1000
   loads; regional capture can reduce that physical fanout.
3. **Local LCD transaction queue.**103 framebuffer RAM endpoints plus1 forward
   register. Local transport `lcd_bad` decoding still feeds panel command/
   direct_pixel decode ->BRAM WE in one cycle. Capture the validated LCD
   transaction payload, qualify DMA/direct collisions and apply it next cycle.
   Preserve command ordering and partial display; don't guess a panel clock.
4. **Cache write-buffer hazard metadata.**All87 refill/merger routes compute
   queued-address+word-offset ->line compare ->issue/ACK ->refill capture.
   Precompute line membership when enqueueing/merging groups, not on every query.
   Each contiguous1..4-word group spans at most2 32-byte lines; stored first/last
   line tags plus valid membership can replace16 runtime address additions.
   Preserve simultaneous enqueue/merge/retire/error behavior, cross-line groups,
   and no false-negative hazard. Existing conservative retired-word stalls can
   remain. Don't redo the successful tag/data pipeline for this separate issue.
5. **Diagnostic readout arithmetic.**The second-worst overall path is now
   `read_word` offset ->combinational `/6` divider ->trace RAM address (-4.738).
   This is export/readout, not the already pipelined fault capture. Replace
   arithmetic with a bounded decode/table or staged mapping and explicitly
   preserve/retime the diagnostic-export read contract and unchanged file format.

Timer same-cycle write/clear/rearm plus counter updates (77 main timers),
MDI forwarded-pointer comparisons (25), and reset/error/access-window fanout
(62 ICU destinations on a reset-origin route) are later local targets. Do not
infer that all need slower physical clocks or add broad false/multicycle paths.
Maintain tests, source/QIP correctness, state coherence and cold boot evidence;
future fits must validate both improved target groups and other newly exposed
limits. No RTL edits, commit/push or build dispatched by this analysis request.

## 2026-11-07: cache lookup/commit redesign implemented; fitted timing pending

Shared I/D cache geometry and ARM920 policies are preserved. Tag RAM reads now
snapshot segment flags/victim context, parallel tag comparisons are registered,
and bank data plus tag/dirty/replacement changes use coherent captured commit
records. Payload selection uses refill/store intent rather than late permission.
Data and metadata publish on the same edge; reset/invalidation/maintenance cancel
pending mutations together. Storage primitives, firmware and peripherals remain
unchanged. Details and latency contract: `docs/timing-closure.md`, ninth implementation.

Serialized lookup and MVA maintenance gain a compare wait; stores and refills
complete after the commit edge. Fast lookup address/valid context follows the
extra stage. ZAP patch0041 extends resident lookahead from8 to12 bytes. Leaving
it at8 failed warm ADD throughput (five-cycle boundary stalls); corrected
lookahead passes the original one-cycle assertion at0/3 memory waits. The
adapter's completion, MMU/abort and SWP handshakes remain intact.

Fresh real-SDRAM5M boot passes PC00006170,306874 transfers,12 known speculative
fetch faults,zero data faults. Compared to the earlier baseline, all121 board
writes match in order/value;845 events equal the baseline962-event sequence
with117 repeated instruction-word reads at0c004778 removed (ignoring cycle
stamps). This is consistent with changed speculative fetch timing, not an
identical trace or new cold-logo result. Existing checkpoint pairs/executables
remain untouched and must not be restored into changed HDL.

Evidence: `scratch/timing-closure/pass9-cache-pipeline/`; includes failed first
throughput attempt, corrected timing results, boot trace/comparison script/JSON,
source hashes and regression logs. CPU/cache coverage completes with **119 PASS
and one expected legacy direct-map XFAIL**:100 passes in the main run, then the
corrected instruction-walk fixture plus18 remaining cases in `cpu-tail.log`.
Warm ADD remains1 cycle at0/3 waits. Board SIM/DMA/IRQ/FIQ/local-fault integration,
real-SDRAM early boot, structural top elaboration, source graph, formatter and
ZAP patch-series verification pass. The fixture retains its20-wait overlap
assertion; warming four sequential lines and four NOPs remove cold-fetch timing
dependence. A warmed no-NOP table-update case also aborts with baseline603fd8b;
its reproducer is retained for a separate synchronization/CPU-ordering audit.
Implementation commitfcb7dc2; fixture adjustment110b22d; prior fit review603fd8b.

No FPGA build or dispatch. Last measured fit remains8395967:68.32MHz,
setup-5.021ns. Added registers, remaining selection logic and full-design
resource use require a newly authorized fit. The independent peripheral
staging-RAM ownership path (-4.903ns) is unchanged. **104MHz is unproven.**
Next: review both cache instances/all top1000 families and full timing/resource
checks when the user supplies a completed fit; no automatic build authorization.

## 2026-11-07: fit68.32 MHz exposes structural cache/refill bottleneck; rewrite handoff

Reviewed completed42411324930 /8395967. Fmax **68.32MHz** versus65.40;
setup **-5.021ns** versus-5.378 (+.357ns), TNS **-56669.384ns** versus
-54599.524 (3.79% worse magnitude). ALMs32,269 (+220), registers43,328 (+121),
M10Ks456 unchanged. HDMI setup+.042ns. Still fails104MHz; Quartus compilation
succeeds and timing gate fails. Reports, classification script and exact counts
under `scratch/timing-closure/pass8-8395967/analysis/`.

Shared error/ACK union is now **11/1000**, all bridge `master_read_data`.
Diagnostic capture endpoints drop315 ->18 (+1 separate video path). No named
`store_commit` routes remain in this top1000; the small edit did remove that
chain, without solving the cache's overall same-cycle scheduling.

**798 cache destinations**: data RAM183 (ICache47, DCache136), valid/dirty
flags546 (dirty396+valid150), tag RAM16, controller53. Other groups: peripheral
staging RAM97, sparse CAM7, bridge26, diagnostic observers18+video1, MMU/
predecode21, memory merger11, instruction FIFO2, CP15/maintenance5, SDRAM
arbiter12, LCD scanout2. All1000 are violated. Subset counts do not establish
whole-design timing or compare identical paths across fits.

Worst route is ICache tag M10K ->64-way match/selection -> bank `fill_commit`
(fanout313) ->256-bit write-data selection -> line M10K data input. Data delay
13.708ns,9 levels. `write_data` and `write_way` incorrectly depend on the late
permission rather than the known operation type; their invalid-cycle values
could be preselected independently. But changing those muxes alone just
exposes the -4.903ns peripheral RAM and -4.827ns metadata paths. A controlled
rewrite of the cache bank/controller transaction pipeline is recommended,
not replacing the whole CPU or changing64-way ARM920 geometry.

Proposed direction: explicit tag/metadata read, registered match/selection,
and registered operation/commit records; choose payload early, publish data
and metadata coherently. Maintain read/store/refill/maintenance hazards and
fast-line streaming throughput. Metadata in BRAM or an early registered
segment snapshot is a design option to investigate, not an implemented fix.
Peripheral RAM has a separate broad ownership-decode bottleneck: address ->
boot claim exclusions -> GPIO write -> BRAM WE; localize ownership by coarse
address region later. Cache-only work cannot certify the complete core104MHz.

User requested a new-cache handoff. Persistent brief:
`scratch/handoff-cache-104mhz.md`. No HDL changes, commit, push or new build in
this review. The prior explicit **no-build** preference remains in force;
user triggers fits and supplies completed links. No104MHz claim without STA.

## 2026-11-07: remove redundant global-hit qualification from cache metadata stores

Cache follow-up is separate from pushed diagnostic commit46a113c. Routed-path
inspection of ef6511b found631 metadata endpoints (534 dirty/97 valid);492
routes include named `store_commit` logic. Worst-4.973ns path is tag M10K ->
global hit reduction -> bank store qualifier -> high-fanout dirty-flag enable.
Evidence `scratch/timing-closure/pass8-cache-local-store/baseline-paths.json`.

`cache_access` now sends a store request without a redundant live-hit term in
the write-through path. `cache_bank` separates store intent from actual data
write: encoded RAM writes still require global hit, while metadata receives
intent and uses its existing per-way priority-selected tag match. Therefore
miss stores neither allocate, dirty nor overwrite the encoded default way.
Reset/refill/invalidate/lock suppression, dirty halves, duplicate-tag priority,
writeback, memory primitives and request/response latency are unchanged. No
new cache stage, extra hit cycle or timing exception. Refill miss validation
is genuine cache behavior and remains; this edit does not promise all631
metadata routes or all492 targeted routes now meet104MHz.

Expanded bank test passes miss-store preservation of every one of64 ways and
empty-mask suppression, alongside tags/dirty-halves/victim/lock tests. Actual
CPU SIM/DMA/IRQ/FIQ/local-fault integration passes. Fresh real-SDRAM5M cold boot
passes unchanged PC00006160,326761 transfers,12 known fetch faults and zero
data faults; all963 board-trace lines match the pre-diagnostic baseline.
Top elaboration and source preflight pass. Full CPU/cache suite with the UPP
bridge enabled finishes **119 PASS +1 expected legacy direct-map XFAIL**. Warm
ADD stays1 cycle at0/3 memory waits. Logs `scratch/timing-closure/pass8-cache-local-store/`.

User requested **no FPGA build**. No Quartus dispatch or timing claim for these
changes; next fitted baseline remains65.40MHz/-5.378ns until measured later.
Do not restore long-run states into this changed executable.

## 2026-11-07: pipeline diagnostic observations, preserve screen and coherent records

`ngage_debug_monitor` now samples an unconditional PC/instruction/bus payload
record plus event/reset bits before counters and sticky history. ACK/error/
fault qualifiers no longer directly enable the wide context registers.
PC/address/read-or-write-data/flags/reason are all taken from the same sampled
edge; back-to-back events cannot mix requests. Hold preserves an already
sampled event; cold reset flushes pending history. `ngage_diagnostics` uses the
same one-stage fault/payload discipline for independent first fetch/data faults.
Trace-ring timing, readout latency, file format and text screen layout stay
unchanged; history is visible one clock later. Live CPU response/error logic
and peripheral behavior are untouched. No clock/timing exceptions added.

Directed tests pass write/read payload alignment, different consecutive fault
contexts, consecutive fetch/data kinds, sticky first event, warm Hold and cold
flush. Diagnostic text/font/raster, ring export/decoded NGD and actual hps_io
export pass. CPU integration including CAM overflow, rejected LCD header,
SIM/DMA/IRQ/FIQ and sticky first fault passes. Fresh real-SDRAM cold5M boot:
PC00006160,326761 transfers,12 known fetch faults, zero data faults. All963
board-trace lines byte-identical (SHA256
`07f2b1710e027039be4743eccc0226caa992935e13197026015aad15af51a398`).
Top elaboration/format/source checks pass. No new cold-logo claim; old long
checkpoints remain bound to their saved executable and are untouched.
Evidence `scratch/timing-closure/pass7-diagnostic-pipeline/`.

This is bring-up instrumentation, removable/disableable for a final core;
real CPU abort/completion handling is separate and remains required. Commit
and push diagnostic work first, **no Quartus build**, then address cache in a
separate change. Baseline remains ef6511b/65.40MHz/-5.378ns until a future fit.

## 2026-11-07: local-validation fit65.40 MHz; shared paths991 ->347

Reviewed completed **42405201963 / ef6511b** (includes service loader9d87477
and separate local-validation change). Core worst setup **-5.378ns**, slow
Fmax **65.40MHz**, versus-6.633ns/61.55MHz: +1.255ns/+3.85MHz (+6.26%).
Core TNS **-54599.524ns** versus-94439.842ns,42.19% smaller magnitude.
ALMs32,049 (76%) versus32,507 (-458), registers43,207 versus43,949 (-742),
M10Ks456 versus457 (-1). HDMI setup+.360ns; global hold+.250ns,
recovery+3.373ns, removal+1.348ns and pulse+.961ns remain positive.
Quartus compilation succeeds; timing gate fails. Still not104MHz closure.
Because loader first enters this fit, do not attribute every placement/resource
change exclusively to the local-validation source edit.

Full-route audit of all1000 setup paths (-5.378..-4.226ns), same named-node
method as preceding fit:

| Route marker | Previous | Current |
| --- | ---: | ---: |
| Peripheral `unmodeled` | 991 | 347 |
| Named `wb_ack` | 721 | 210 |
| Either error/ACK marker (union) | 991 | 347 |
| Sparse `d_regs` CAM logic | 801 | 0 |

The210 ACK paths overlap the347 error paths; do not sum them. Remaining shared
paths end **only** in debug monitor280, diagnostic export/capture35 and UPP
bridge response32. **Zero exported shared paths feed peripheral writes**
(LCD/framebuffer/DMA, timers, MDI, staging RAM). Route-name auditing is a
repeatable subset measurement, not a proof about all fitted paths or semantic
logic renamed by optimization.

Worst path now: registered bridge address -> UEM CBUS selected-access bad
checks -> peripheral `unmodeled` -> diagnostic fault qualifier ->
`diagnostics.first_fetch_address` (10 levels,14.294ns data delay). This is a
fault-context capture bottleneck, not a peripheral write enable. The original
cross-device write fanout has been removed from this exported set.
Remaining top1000: shared response/diagnostic347; cache metadata631
(dirty534+valid97, worst-4.973ns); cache bank17 (-4.871); cache-access/merger3;
instruction-cache/fetch2. Cache-family total651; fetch2; sum1000.

Next candidates: pipeline coherent fault/transaction capture in diagnostics
without changing screen contents, simplify selected response/error capture,
and further shorten cache flag enables. Keep PC/address/data/reason from the
same transaction when adding observer latency. No new RTL, commit, push or
build started by this review. Reports and reproducible audit script/JSON:
`scratch/timing-closure/pass6-ef6511b/analysis/`.

## 2026-11-07: local device validation replaces shared ACK-gated writes

Separate timing commit after loader9d87477. UPP now distributes `bus_access`
from the active captured request (reset/init/error qualified), without using
combinational CPU ACK or aggregate `unmodeled` as a global side-effect enable.
CPU ACK/error/data response and registered invalid-access faults are unchanged.
Each child retains claim/bad checks; SIM alone checks its busy/overflow, GPIO
checks supported lanes and dedicated ownership, LCD exports its locally
validated write strobe. Clock writes no longer consult unrelated validators.
Sparse CAM capacity/lookup affects only that device's state and selected CPU
fault response, not LCD/timer/MDI/RAM write enables. No new clock, exception,
extra bus pipeline stage, firmware patch or default-success response.

Actual LCD DMA owns its registers exclusively, rather than also changing the
legacy ICU-extra DMA shadow. DMA/direct-LCD collision suppresses only that
access until accepted; synchronous GPIO read validity clears at its own ready
edge, and SIM pops cannot repeat while the service pipeline is busy.

Verification passes: actual CPU program fills all64 sparse slots, faults on
new allocation, preserves existing data, then writes/reads a timer while the
table remains full; invalid LCD header faults without changing transport or
panel header. IRQ/FIQ, SIMIF, DMA pixel, SDRAM waits and sticky first-fault
context still pass. LCD transport tests offer invalid operations with the
access window asserted and confirm local suppression against both C++ models.
Full18304-word DMA, board ownership132 pairs, unimplemented chip boundaries,
SIM present/absent, transaction fixtures and warm/cold RAM tests pass. Retained
firmware-DMA trace replay is explicitly SKIP (fixture unavailable), not passed.

Fresh **real-SDRAM5M cold boot**: PC00006160,326761 transfers,12 known fetch
faults, zero data faults. All963 recorded board-trace lines are byte-identical
to the prior run; SHA256
`07f2b1710e027039be4743eccc0226caa992935e13197026015aad15af51a398`.
This verifies the existing bounded stopping point, not a new cold Nokia-logo
run. Frozen billion-cycle states remain untouched and are not restored into
this changed HDL. Logs `scratch/timing-closure/pass6-local-validation/`.

**Diagnostic screen needs no redesign:** PC/opcode/CPSR, completed bus
transactions, wait counts, sticky fault PC/address/reason and text raster remain
observers of the existing response signals. Their directed monitor/raster tests
pass unchanged. They do not authorize device writes. Top elaboration, source
preflight and formatting pass. Next build includes separate loader commit plus
this timing change; measure new slack/Fmax and paths against61.55MHz/-6.633ns.
User monitors CI; no automatic monitoring requested.

## 2026-11-07: SIM/LCD/cache fit improves to61.55 MHz; shared commit path exposed

Completed build42400361438 is **7d80fc6**, excluding the later local service
loader commit9d87477. Quartus compilation/source preflight succeed; action
fails only the timing gate. Reports retained at
`scratch/timing-closure/pass5-7d80fc6/`, functional classification and script
under `analysis/`. Core setup **-6.633ns**, Fmax **61.55MHz**, versus
-9.070ns/53.52MHz: +2.437ns/+8.03MHz (~15%). ALMs32,507 (78%), down1,421;
registers43,949, down1,240; M10Ks457 unchanged (83%). Core setup TNS regresses
from-89226.544 to **-94439.842ns** (~5.84% larger magnitude). Improving the
single worst path does not mean overall timing closure. PLL remains104MHz.
Core hold+.255ns, recovery+6.919ns, removal+1.754ns; global fast hold+.072ns,
recovery+3.409ns, minimum pulse+.961ns, global removal+.980ns; HDMI setup+.087ns.

All1000 exported setup paths still violate (-6.633..-4.959ns), one worst per
endpoint. **11 chosen functional groups /18 destination instance hierarchies**:
MDI/DSP-mailbox hypothesis131 (-6.633); LCD framebuffer/command diagnostics410
(-5.859;408 BRAM pins+2 diagnostic regs); peripheral upload/NOS/aux staging
RAM94 (-5.718;54+31+9); UPP ICU/config74 (-5.592;72 extra+2 ICU); ARM920
D-cache bank6 (-5.538); UPP/NOS timers200 (-5.496;199+1); FPGA debug/trace7
(-5.486;6+1); boot/control17 (-5.448); LCD DMA41 (-5.410); unidentified0x0d
sparse-register model19 (-5.235); bridge response1 (-5.013). Sum1000.
These are destination groups, not11 independent root causes or proven phone
chip timing domains. Staging RAM, MDI and unidentified registers remain models.

**994 launch at UPP bridge address registers; only6 launch at cache tags.**
Full-route substring audit:801 include sparse `d_regs` CAM logic,991 include
peripheral `unmodeled` logic,721 include named `wb_ack` logic. Counts overlap;
optimization can rename equivalent logic. Worst route is bridge address ->
sparse hit/full decode -> unmodeled -> ACK/commit -> MDI forwarded ring/pointer
logic -> pointer register (11 levels,15.465ns data delay). LCD BRAM endpoints
are predominantly write address/data/enable controls on that shared commit
route, not the removed divider or a measured panel serial-clock failure.
Old SIM FIFO, LCD /88/%88 and cache dirty/valid metadata destinations are
absent from this subset; this does not prove their full-design timing passes.

Next recommended target: separate address/error validation from peripheral
commit/write enables with a registered boundary, preserving exactly-once
commit, bus-error suppression and read/IRQ behavior. Diagnose shared fault/CAM
fanout before independently patching all destination modules. MDI additionally
has same-cycle forwarded ring comparisons worth splitting once the common
path is cut. Cache-bank write/merge remains a separate6-path group. No RTL
change, push or new build initiated by this timing-analysis request.

## 2026-11-07: original boot/boot1 firmware loader, existing NGA retained

Firmware-only slice of7.6: `rtl/ngage_service_loader.v` is connected in
`Template.sv`/QIP. Original audited4.03 `nem440.3c1` -> `boot.rom`,
`nem440.326` -> `boot1.rom`, unchanged bytes. Automatic indices00/40 and
manual F1 MCU/F2 PPM; no top-level NGB load. Both slots must validate after
all DDR acknowledgements before CPU release. Fixed-profile bounded prefix
skip + full-container CRC/length, per-record checksums/range checks, byte
unpacker and registered DDR writes. First load clears firmware backing only;
reload clears selected ownership and preserves the other slot. Failure holds
CPU until valid reload, with no rollback claim. Live read descrambler unchanged.

C:/PMM **still use the existing NGA on S0**, diagnostics S1; no raw storage
migration. Loader cannot write either user region. Existing reload protection
blocks mounted/busy/error saves. Save header service profile0 accepts seed IDs
1/2 only with the same exact hash fields, size, CRC and reserved padding;
legacy profile checks retain exact ID matching. Mount after both files load.

Maintained host oracle `tools/service_firmware.py` verifies all2435 records and
all20,905,984 raw backing bytes against current core.bin + extension.bin for
both orders and same-slot reloads. Combined SHA-256:
`88fd596a23269ecb0d9f7544d540c59010d276574dbe3d0262c870c429e58329`.
Initial actual-hps_io/DDR test passes both automatic numbered-first and manual
opposite orders, full backing/decoded-read comparisons, reload/error recovery,
odd EOF, malformed records, abort/reset, stalls and C:/PMM/guard preservation.
Final run also passes EOF before final DDR acknowledgement:580,149,346 clocks,
90,689,248 accepted DDR writes. Save header IDs1/2 and rejection of unknown ID3
pass. Actual hps_io + NOR/DDR persistence passes restore/flush/remount with
concurrent S1 (22 reads/9 writes), and full4MiB C:/64KiB PMM last-sector/reload
checks pass with service profile0. Legacy loader/DDR tests still pass.
Top structural elaboration and Quartus source preflight pass; RTL uses
Verilog-2001 constructs and formatter checks pass.

Evidence: `scratch/service-rom-loader/validation/`, generated tests
`build/sim/service-loader/`. Independent firmware-only commit; timing build
42400361438 remains at7d80fc6 and is not monitored or replaced. Raw independent
C.img/PMM.img work7.6c onward is deferred. Real Main/board acceptance and new
loader STA remain unverified; no new cold logo/long-checkpoint claim.

## 2026-11-07: implement paced SIM, minimal LCD and cache metadata fix

User selected slower SIM enable/registers and full-speed cache repair; then
explicitly requested keeping only necessary LCD behavior. Production card now
uses **104 MHz /32 =3.25 MHz** service CEN, system-speed event holding plus
CEN-only work registers. Busy stalls subsequent SIMIF access until state/data
is current. This is a byte-transaction service budget, not physical SIM baud.
No clock/PLL, firmware, loader, general MMIO/timer/RTC or SDC change.

Reviewed Nortido's pinned LCD: linear burst pointer, no runtime division.
Removed our speculative row bitmap/counters and /88/%88 entirely, plus the
full-frame scanout gate. Partial pixels display immediately when panel is on;
existing BRAM starts black on FPGA load, warm reset retains stored pixels.
Kept framebuffer/native176x208 raster, known panel commands/on-off, bounds and
explicit full-transfer diagnostic flags. No new unknown panel frequency or
protocol behavior. A prototype row-start lookup was unnecessary once the user
removed coverage tracking and is not retained.

Cache flags now have fixed per-way/segment enables from priority-masked tag
matches, avoiding hit-way binary encode/decode on metadata writes. Synchronous
M10Ks, latency, replacement/scan/lock/reset priorities and dirty halves remain.
Full CPU suite with bridge enabled: **119 PASS +1 expected direct-mapped XFAIL**;
expanded per-way dirty/clean test passes; warm ADD remains1 clock at0/3 waits.
C++ card/FIFO and new160-response32-CEN pipeline equivalence tests pass;
SIMIF absent/present31/194 comparisons pass with backpressure. Fixed benches'
same-delta ready sampling so they actually wait after asserting requests.
LCD tests pass for immediate partial pixels, untouched black, out-of-order
bands, known commands and explicit completion. Native176x208 raster and saved
firmware-frame replay match pixel-for-pixel. Board SIMIF/LCD DMA/fault/IRQ/FIQ
integration, structural top elaboration and synthesis-mode RTL lint pass.
Fresh real-SDRAM cold boot passes5M cycles: PC00006160,326761 transfers,
12 known speculative fetch faults, zero data faults and no LCD traffic yet.
This bounded boot is not a new cold-boot logo result.

Logs `scratch/timing-closure/pass5-sim-lcd-cache/`. Next physical measurement
baseline **53.52MHz /-9.070ns**, 33,928 ALMs,457 M10Ks. No global false/multicycle
exception added for CEN; fast ready/status/readout boundaries still matter.
User monitors builds; no CI polling. Frozen long-run checkpoints untouched.

## 2026-11-07: bus bridge fit 53.52 MHz; choose next timing targets

Reviewed completed **42383337100 / c08939d**. Reports under
`scratch/timing-closure/pass4-c08939d/`. Core setup **-9.070 ns**, Fmax
**53.52 MHz**, TNS **-89226.544 ns** versus -10.644 /49.36 /-123805.311.
TNS magnitude improves27.93%; fitter **33,928 ALMs (81%)**, 45,189 registers,
**457 M10Ks (83%)**. Hold/recovery/removal/pulse remain positive. Compilation
succeeds; action fails only required timing gate. Still fails104 MHz.

**0 of the new top1000 paths retain the old fault/ACK -> CPU next-request
combinational traversal** (previous912). Chain was structurally cut; this
is not a claim that912 former endpoints now pass. Newly exposed groups:
**28 SIM FIFO paths** worst-9.070ns; **18 LCD divider/modulo paths**
worst-7.937ns; **816 cache metadata endpoints** (649tags->tags,167access->tags),
worst-7.765ns. Others138 include cache outputs, response capture, diagnostics.
Cache example: tag RAM -> match -> priority hit-way encode -> way decoder ->
dirty-bit register. New SIM worst still crosses shared ACK into multiwrite
occupancy/address logic. LCD /88,%88 are row-completeness metadata, not pixels.

User requested analysis and choice before more RTL. Recommendation in
`docs/timing-closure.md`: a bounded three-target pass for SIM event/FIFO
boundary, LCD row-divider pipeline/replacement, and one-hot cache flag updates
that avoid encode/decode. Separate reference/CPU/video regressions per target;
preserve warm cache throughput. SIM-only fix would likely expose~57MHz LCD/
cache limit at current placement; all3 exceed the104MHz period. No claims of
predicted closure. Keep loader/storage and clock-rate work separate.

No RTL/test change or new build in this review turn. Evidence/status docs only;
await user's selection. Do not monitor existing/new CI runs.

## 2026-11-07: plan original service-file loading and raw C:/PMM

User requested a plan/difficulty assessment while the timing build runs.
Added `docs/service-firmware-loader-plan.md`, linked from milestone7.6 and
README, with work packages7.6a–e. No production RTL/OSD/storage change.
Official MCU/PPM contain **2268 +167 addressed records**, not two flat ROM
halves. Rechecked all2435 checksums and a software fixed-profile ownership
mapping: both input orders and same-file reloads exactly match all20,905,984
audited backing bytes. Evidence `docs/evidence/service-rom-mapping-check-
2026-11-07.json`; script under `scratch/service-rom-loader/`.

Important discovery from official Main at cc47bad62f4c9b6edea55aee3de12bf90855667c:
numbered boot files are tried before legacy boot.rom fallback, so **boot1 can
arrive first**. Plan fixed 4.03 PPM-owned ranges to preserve its overlay priority
regardless of arrival, no extra container staging required. The 1,361,703-byte
PPM is odd-sized; WIDE16 emits a final zero high transport byte. Byte unpacking
and profile-bound EOF handling are required, not word-aligned flat copying.
Installed board Main revision remains unverified. Official sources retained
read-only under `scratch/service-rom-loader/`; no Main fork changes needed.

End state: unchanged nem440.3c1 as boot.rom and nem440.326 as boot1.rom,
firmware stays scrambled in DDR with existing live descrambler; S0 raw4MiB C:,
S1 raw64KiB PMM, diagnostics moves to S2. Parser/checksums/DDR ownership and
storage reset/dirty/media protections are the real work; address shifts are
straightforward. Suggested next implementation7.6a host oracle, then streaming
HDL loader, raw persistence/top gates and separate hardware acceptance. Keep
this separate from option2 timing build. No build launched or monitored here.

## 2026-11-07: CAM fit 49.36 MHz; registered UPP bus boundary

Reviewed **42379146118 / cc89013**: core **49.36 MHz**, setup **-10.644 ns**,
TNS -123805.311 ns. Previous 52.09 MHz / -9.582 ns, so timing worsened;
area improved to **33,589 ALMs (80%)**, 45,643 registers, **457 M10Ks (83%)**.
Reports `scratch/timing-closure/pass3-cc89013/`. CAM change retained for the
next structural measurement. Actual path count: **912/1,000** traverse shared
fault/ACK then CPU/cache next-request logic; **946** touch shared fault/ACK;
**36** involve SIM FIFO, including the worst path. Groups overlap. The bridge
cuts the 912 feedback structures; it does not promise 912 timing passes or
remove the entire worst ACK -> SIM FIFO multiwrite path.

User authorized option 2. Added transaction-level `ngage_upp_bus_bridge` leaf
inside existing `rtl/ngage_upp.v`; internal CPU requests and responses cross
registers. Captures one beat, holds fields through waits, commits downstream
once on successful completion, latches read/error and returns completion to
CPU with downstream request inactive. ERR wins; reset and CYC cancellation
covered. LOCK stays directly CPU-driven across pipeline bubbles. External
master test mode unchanged. Existing QIP includes the containing file.
No CPU core, PLL, SDC, firmware, timer rate or SIM protocol change. External
memory accesses as well as MMIO gain latency; fresh simulation lineage needed.

Passes: 200-beat bridge wait/response/side-effect/cancel/reset tests; opt-in
`CPU_BUS_BRIDGE=1` CPU warm ADD timing (one clock at delays0/3), SWP cached/
uncached/bufferable/DMA/SDRAM, IRQ/FIQ, read/write/IRQ aborts, alignment, cache
refill/writeback IRQ and external abort. Integrated ARM/SIMIF/LCD DMA/fault/
IRQ/FIQ/SDRAM-wait board test, shared synthesis and top structural lint pass.
Fresh cold 5M modeled-memory smoke PC **00006164**, 328479 transfers, 12
speculative fetch faults, zero data faults; real-controller/Micron smoke PC
**00006160**, 326761 transfers, 12 fetch faults, zero data faults. No LCD yet.
PC/counts differ from the old fixed-cycle smoke due to latency; do not call
this trace equivalence. Logs `scratch/timing-closure/pass4-bridge/`.

Commit/push and launch one timing build. Compare against **49.36 MHz /
-10.644 ns**, then inspect remaining SIM queue/response paths. User monitors;
do not watch/poll. No additional timing cleanup mixed into this measurement.

## 2026-11-07: sparse CAM timing iteration selected

User authorized **candidate 1 only**, commit/push and one build, then measure
before trying **candidate 2** (registered bus boundary). Implemented direct
any-match/all-valid full detection and balanced lowest-hit/lowest-free slot
trees in `ngage_sparse_regs.v`. Fixed per-slot tag writes preserve allocation
order; padding cannot be allocated. Same byte-enabled M10K and read latency,
full-table update/refusal, masks and reset semantics. No clock/PLL, SDC,
timebase, firmware, bus-pipeline or other production RTL change.

Original sparse test plus a new independent scoreboard pass for capacities
**1/2/3/5/64**, each with directed fill/full update/refusal/read and 4,000
random cycles. Covers full byte addresses, masks/zeroing, lowest-free order,
reset, missing request/commit and synchronous read latency. Mixed-port
same-address collision data stays unspecified and is verified on later reads.
Integrated ARM/SIMIF/LCD DMA/fault/IRQ/FIQ/SDRAM-wait checks, absent/present
SIMIF reference comparison and shared RTL synthesis lint pass. Fresh cold
5M-cycle smoke matches PC **00006178**, 377714 accepted transfers, 18 known
speculative fetch faults and **zero data faults**; no LCD yet. Formatting and
whitespace checks pass. Commit/push and launch one timing measurement build.
Logs: `scratch/timing-closure/pass3-cam/`.

Measurement baseline is run42375426237 / 4040395: **52.09 MHz**, setup
**-9.582 ns**, 33,857 ALMs, 457 M10Ks. New fitted improvement is unverified.
User monitors the next action; do not watch/poll it. Wait for measurement before
implementing option 2.

## 2026-11-07: second timing result 52.09 MHz; awaiting next target choice

Reviewed completed **42375426237 / 4040395** at user request. Artifact under
`scratch/timing-closure/pass2-4040395/`. Core setup **-9.582 ns** (previous
-10.023); slow-model Fmax **52.09 MHz** (50.92); TNS **-117903.504 ns**
(-138677.094). Fitter: **33,857 ALMs / 81%**, 45,783 registers, **457 M10Ks /
83%**. Saves 357 ALMs; adds 437 registers. Hold +0.184 ns and other reported
metrics positive; HDMI setup only +0.079 ns. Fails the intended timing gate,
not compilation. Still invalid at 104 MHz; no board timing sign-off.

**929/1,000** newly exported paths traverse sparse CAM and shared unmodeled
logic. Worst path: shared WB address -> sparse full/lookup -> unmodeled/ACK ->
SIM FIFO occupancy/address. Other long paths continue from ACK into CPU/cache
next-request generation and back into peripheral decode. Prior 969 paths were
*touched*, not promised timing passes; improvement is modest because the
critical predicate shifted to another device on the shared response path.

User explicitly wants to **decide the next target before implementation**.
Recorded options in `docs/timing-closure.md`: (1) derive sparse full directly
from any-match/all-valid and balance indices without added latency; (2) proper
registered request/response boundary to cut decode/ACK/next-request feedback,
with exact-once commit and SWP/reset/fault handling; (3) stage/bank SIM response
FIFO writes if still limiting. Recommend the small CAM/full split first, then
bus pipelining if feedback remains. Slower phone interfaces/timebase research
is separate; do not add false/multicycle exceptions to these CPU paths.

No RTL changes, tests, commit/push or new build in this decision/review turn.
Only evidence/status docs updated. User continues to monitor builds.

## 2026-11-07: Nokia clock rates recovered; read-only firmware audit

Downloaded original **NEM-4**, Issue 2 Sep 2004, service chapters 6 and 7 via
Jabse's normal document viewer/download links. PDFs/text/checked page renders
live in `scratch/timing-closure/clock-research/`. **Chapter 7 resolves the bus
rates**: SDRAM **104 MHz**, main burst flash **104/3 MHz (~34.667 MHz)**, MMC
**8.66 MHz**; MCU starts at **26 MHz**, ceiling 104 MHz; three independent
DPLLs for MCU, internal DSP, accessory interfaces. Internal DSP ceiling 117 MHz
is distinct from the separate ADSP/audio 12 MHz oscillator. This supersedes
our earlier unknown-memory-clock statement. QD/RH-47's 40 MHz flash rate must
not be copied onto NEM-4. Exact CBUS/DBUS/LCD/internal MMIO rates remain unknown.

Visually inspected CBUS page 6-133: CH1 is enable, CH3 bit clock; CH3 is dense
at 50 us/div. CH1's displayed frequency is not CBUS bit frequency. Do not
infer a divider from that capture. Primary pages and findings are documented
in `docs/phone-clocks.md`, with a concrete ordered clock/timebase/bridge plan.

Added read-only `tools/probe_phone_clocks.py`, generating a tapped copy of the
maintained 5M cold boot bench; it does not edit production HDL/firmware or load
CPU checkpoints. Probe passes under jotego/simulator:arm64: PC 00006178,
377714 accepted bus transfers, 18 known speculative fetch faults, zero data
faults, no LCD. 20 observed CP15 control transitions use 00000078/0000127A/
0000027A; bits31:30 remain **00** within this bounded run. Captured 54 accepted
early clock/control writes including 0c120004=0c then =3, 0c120008=1,2,
0c149000=2210, 0c120018=180f8000, 0c120014=08018000, 0c120038=0c,
0c120034=8,3. Bit-field/divider meanings and physical clock modes are not proven.
Source 4040395, hashes and full compact evidence are tracked in
`docs/evidence/phone-clock-audit-2026-11-07.json`.

Stock ROM routine VA50348e38 returns literal 15625; variant dispatch table
contains its pointer at 5034a9cc. Kernel time arithmetic also uses 15625;
reload 406250 is at 5032270c and 503227c8. Together with Nortido's 26 MHz
timer model/64 Hz guest tick this strengthens a **26 MHz timer hypothesis**,
but the ROM callback's precise identity and timer source remain to verify.
Do not silently change all timer/RTC counters. Next identify tick/HAL callers,
compare guest time and IRQ counts over one RTC second, then make a separately
verified timer-enable experiment with fresh simulation lineage.

This turn changes documentation/observation tooling only. No production RTL,
firmware, PLL, SDC, timebase or timing exceptions changed. No CI build started
or monitored; the existing timing iteration remains the user's build to watch.

## 2026-11-07: first timing result 50.92 MHz; boot-decode follow-up

Completed **42372012944 / 2bcac9d**: core setup improves **-43.702 ->
-10.023 ns**, slow-model Fmax **18.76 -> 50.92 MHz**. Setup TNS
-138677.094 ns; 34,214 ALMs (82%), 45,346 registers, 457 M10Ks (83%).
Summary permissions now work; action correctly fails the timing gate. Still
not valid at 104 MHz. Reports `scratch/timing-closure/pass1-2bcac9d/`.

**969 of the new 1,000 paths** traverse boot-register encoded validity muxing
before shared unmodeled/ACK and downstream CPU/peripheral logic. Replaced
encoded boot/scratch indices with constant per-latch selects, parallel missing-
byte checks, fixed writes and balanced read-data OR tree. No address, read-fault,
byte mask, reset, commit, latency, firmware, PLL/SDC or timer behavior change.
Original tests plus independent 12,000-cycle boot-latch conformance pass;
integrated ARM/SIMIF/LCD DMA/IRQ/FIQ/SDRAM-wait board test, cold hardware-bound
5M smoke (PC 00006178, 18 known fetch faults, zero data faults) and RTL lint pass.
Commit/push and start next measurement build; user monitors it.

**New user steering: investigate slower phone buses.** Local ARM920T TRM
chapter 5 confirms separate FCLK/BCLK and CP15 bits 31:30 clock modes. Nokia
service clock diagram documents 26 MHz main reference, 12 MHz ADSP/audio
reference, 32.768 kHz sleep, and ~1.083/3.25 MHz SIM clocks. Original external
memory/MMIO bus rates remain unverified. Hybrid reference uses 26 MHz timer
enable; ours currently counts system clocks. These are distinct evidence
levels, not authorization to guess divisors or mask timing failures. Added
`docs/phone-clocks.md` with register/timebase/bridge follow-up. Actual slower
MMIO bridge or new domains are not implemented. Preserve cold boot/checkpoint
lineage when eventually changing timebases.

## 2026-11-07: first fixes from the actual 1,000 timing paths

Downloaded completed run **42368700686 / 697f598** to
`scratch/timing-closure/baseline-697f598/`. Real Quartus timing export succeeds;
all 1,000 setup paths fail, worst **-43.702 ns / 52.857 ns data / 37 levels**.
Host Markdown summary failed because Docker owned its output directory; CI
now creates that directory as the runner before Quartus. Timing gate retained.

Detailed worst path: LCD DMA source -> DMA validation -> shared WB ACK -> SIM
FIFO pop -> up to 25 serial conditional response-byte increments -> FIFO address.
Reworked SIM enqueue into parallel original-tail offsets/room checks and one
capped count update, preserving immediate bytes/pop/overflow behavior. Cache
metadata forms 464 paths: replaced serial lowest-way selection with a balanced
six-level priority tree, preserving tag RAM latency. Rank 113 identifies write-
buffer head -> rotating address/length lookup -> line hazard -> cache bus
eligibility -> Wishbone merger -> sparse CAM. Hazard comparisons now use fixed
physical slots in parallel, qualified by ring distance from head.

104 MHz PLL, timing constraints, timer/SDRAM configuration and firmware remain
unchanged. Physical improvement/resource cost requires the next GitHub fit;
no claim of closure or hardware fix yet. See `docs/timing-closure.md` for path
groups and remaining candidates. Local checks pass: C++ SIM byte reference (554 operations), FIFO overflow/reset
and 600-response wrap/saturation/concurrent-pop scoreboard; SIMIF reference and
board checks with card absent/present; 64-way tags, bank replacement and cache
access/writeback/maintenance; write-buffer stalls/retry/merge and hazards across
all ring head positions/address wrap; CPU timing with memory delays 0/3 still
one clock per warm ADD; integrated ARM/SIMIF/LCD DMA/fault/IRQ/FIQ/SDRAM-wait
board test. Fresh cold hardware-bound 5M smoke matches PC **00006178**, known
18 speculative fetch faults, **zero data faults**, no LCD yet. Shared RTL lint
and seven timing-tool tests pass. No new FPGA result yet.

Commit/push and start one measurement build. User monitors builds; do not
watch/poll new CI runs.

## 2026-11-07: keep 104 MHz; export worst 1,000 timing paths

User superseded the 50 MHz proposal: **retain the existing 104 MHz configuration**
and collect the worst **1,000** paths before RTL optimization. No clock/PLL,
timer, memory mode, RTL or SDC changes were made. Existing downloaded reports
have summary data only; no detailed launch/capture nodes/routing or fitted DB
is available there to re-analyze locally.

Added `tools/report_quartus_timing.tcl` and action steps to reopen the post-fit
DB on the runner and export 1,000 slow setup paths (one per endpoint), full
clock/cell/routing detail, CSV fields and grouped Markdown summary, plus slow/
fast hold, recovery/removal, clock/Fmax and unconstrained-path reports. All are
saved under `output_files/timing/` in the always-uploaded `quartus-logs` artifact.
A gate after report extraction rejects negative/missing constrained timing,
so the current design is expected to fail the job while retaining diagnostics;
normal RBF upload requires a passing gate. See `docs/timing-closure.md`.

Seven local tests pass for gate behavior, the actual failed board report,
CSV sorting/grouping/quoted node names and mocked Tcl export flow. Command
options were checked against Quartus 17 references; the mock does not validate
real Quartus API execution. No local Quartus download/run, resimulation or FPGA
deployment. Commit/push and start the baseline report build; user monitors it.
Next inspect its actual critical paths, then implement targeted timing fixes.

## 2026-11-07: board screenshot captured; severe setup timing failure found

Captured the live board via Zaparoo **WebSocket** JSON-RPC `screenshot` at
`ws://192.168.1.176:7497/api/v0.1`. HTTP POST is remote-disabled; configured SSH
authentication failed. WebSocket works directly, with no credentials/config
changes required on this device. Reuse
`scratch/hardware-bringup/capture_zaparoo_ws.mjs`; do not ask for SSH credentials
or change API settings for screenshots. PNG and decoded observation JSON:
`scratch/hardware-bringup/board-diagnostics-zaparoo.{png,json}`. Remote image:
`/media/fat/screenshots/NGage/20261107_111823-NEM4-4.03.png`.

Screen/user confirm CPSR **400000D7** (Abort mode 0x17), data fault **08000010**,
fault-time fetch PC **B7C**, data **7037F800**, flags **12111**, reason **2**.
Flags mean write=1, ready=1, memory-request=1, board claim=0; RAM/flash claims
are also zero. BOOT FLAGS **1013F**: required gates and Run are set, known
firmware, first data fault; RESET=0 and no load/save error. BUS ERRORS=1.
The running PC is the previously identified 0x60C stop loop. Low-ROM bytes at
0xB6C..0xB80 set up early 0x080000xx control writes; the fault-time fetch PC is
not a precise executing/faulting instruction PC, and no firmware patch is justified.

**Completed build reports downloaded once (not monitored):** run 42365167112 /
`d068883`, under `scratch/hardware-bringup/build-d068883/`. Fitter succeeds:
**33,832/41,910 ALMs (81%), 457/553 M10Ks (83%), 44,523 registers, 43% logical
RAM bits**. But STA explicitly fails the core clock: **setup slack -43.702 ns,
TNS -215405.214 ns, Fmax 18.76 MHz**, while the PLL still clocks it at 104 MHz.
This is not a timing-valid build. It is a strong candidate for the hardware/
simulation discrepancy, not proof of the particular failing signal/path.

Next obtain detailed failing timing paths, repair/pipeline the responsible
logic and require a passing timing gate before publishing a test RBF. Do not
paper over an unclaimed boot-register fault with an alias or change firmware.
Current CI can upload RBFs despite Timing requirements not met; fitting and
artifact generation alone are insufficient. No RTL/build change was made in
this observation turn. User continues to monitor new builds.

## 2026-11-07: live board PC matches firmware stop loop

User reports fetch PC/last-fetch PC alternating around **0x60C/0x610/0x614**,
and last fetch op **EAFFFFFE / 00001018** on the new diagnostic page. Direct
inspection/disassembly of the audited raw core confirms 0x60C=EAFFFFFE
(`B 0x60C`), 0x610=00001018 (following literal), 0x614=580047E8. This is
consistent with the firmware's early stop loop plus speculative fetch ahead;
these fetch observations do not prove execution of literal-pool words or boot
progress. Some ROM fetches clearly match expected bytes; this is not full DDR
or firmware integrity validation.

The earlier board export recorded an unmapped non-fetch fault at 0x08000000.
That may explain reaching this stop loop, but obtain CPSR and the new sticky
fault address/fetch-PC/data/flags/reason before attributing a cause. First-fault
fetch PC is contemporaneous fetch state, not a precise faulting-instruction PC.
Evidence/disassembly under `scratch/hardware-bringup/`, live report JSON under
`first-black-screen/`. No HDL changes, simulation or build monitoring performed.

## 2026-11-07: diagnostic font single-port clock fix

Run 42363543248 (`99c2aef`) failed in elaboration: Error 272006 says clock1
is unused for the font's SINGLE_PORT altsyncram configuration. The ROM had
clock1 tied low; removed that connection so only clock0 drives its registered
read. Font image, M10K geometry, text/video latency, CPU taps and keys are
unchanged. The clear-box error is reported after the invalid connection.
No new resource/fit/timing or board-display result is available.

Font/raster/monitor checks, formatting and source preflight pass. Commit,
push and start the replacement action. User monitors it; do not watch/poll.

## 2026-11-07: live diagnostic text and named Nokia bindings

Implemented the user's requested **live 320x240 diagnostic text page** in
`ngage_mister`, outside the phone LCD model. The 40x30 character renderer uses
one explicit 1024x8 M10K font ROM, initialized from tracked MIF; matching HEX
and generator are tracked. No runtime font download is needed. A frame-driven
blink remains alive in CPU Hold; a coherent field snapshot refreshes every
16 frames (~4 Hz). RGB and CE/sync/blanking share one added system-clock delay
in both display modes; Phone mode retains its exact pixels/rectangle.

Explicit read-only ZAP core/top -> CPU -> UPP -> board ports expose fetch VA,
ALU-stage CPSR, raw accepted fetch word and acceptance pulse (patch 0040).
Screen includes current fetch PC, paired last fetch PC/op, CPSR, active cycles,
fetch count, current/last Wishbone address/data, ACK/error totals, current/max
wait, first non-fetch fault address/fetch-PC/data/reason/decode flags, named
loader/reset/save/CPU gate bits and Nokia held-key mask. These observations
are not a retired-instruction trace. The first fault survives warm reset/Hold
and clears on cold reset. The existing exported NGD layout is unchanged.
The screen does not fix or explain away the board's 0x08000000 failure.

MiSTer controller definition now supplies 23 Nokia action names (Main's
existing interface supports 28), replacing generic A/B/X/Y prompts. Standard
D-pad bits are retained; existing primary bit mappings are retained, except
old duplicate End bit 11 is now Power. Music/radio/Shift/star/hash/digits are
also assignable. Re-define core buttons after installing the new RBF; Space
skips optional prompts on small controllers. Keyboard mappings remain.
Complete map, snapshot/counter semantics and bit legends: `docs/live-controls.md`.

**Local verification passes:** diagnostic counter/wait/first-fault/history
checks; native Quartus macro selects initialized font primitive; every rendered
pixel matches an independent font/text reference; frame snapshot/refresh,
blanking and registered Phone RGB/control bypass; all 27 one-hot controller
inputs, keyboard/OSD release, matrix/shared IRQ/press tests; ARM board/SIMIF/LCD
DMA/fault/IRQ/FIQ/SDRAM-wait integration; CPU observation-port wiring and warm
ADD timing remain one cycle in both memory-delay profiles. Fresh 5M-cycle
hardware-bound cold smoke passes at PC 00006178, known 18 speculative fetch
faults and zero data faults. Native 176x208 framebuffer replay still matches.
Patch reproduction, 55-file formatting, source graph (172 required files/nine
QIPs), structural top and actual vendor/native-macro top/CPU lint pass.

Simulated layout preview (dummy register values, not a hardware capture):
`build/sim/unit-debug-video/screen.png`. Logs/source references are under
`scratch/diagnostic-osd/`. Font assets enter the resumable runner's build hash;
old 1B..12B checkpoints stay with their saved executable and are untouched.
Commit/push and start one GitHub build for board testing; **the user monitors
builds, do not poll/watch it**. M10K initialization, final resource cost, fit,
timing and actual on-board text/key behavior remain pending Quartus/hardware.

## 2026-11-07: first board diagnostic export; early address fault

User reports Phone display black, **Diagnostic display shows colored bars**.
Read `/Volumes/sdcard/games/NGage/diagnostics.ngd`; valid 1024-byte v1 snapshot,
SHA-256 `6fd7a84acbff1b640c7acae7d742b65c322cc5813dbf77d541fa36b9977eff3c`.
First sticky non-fetch fault: **reason 2 / address 0x08000000**. Fetch-fault
flag is clear, trace count zero, no wrap/dropped events. This proves export and
basic diagnostic video operate; it does not prove phone startup or CPU timing.
No PC, data value, access direction, loader status or RBF revision is encoded
in the current snapshot. Do not infer the precise instruction or stopping PC.

`ngage_boot_regs` explicitly claims this address and accepts writes; an
unwritten read should be a board-model error (reason 1), not an unmapped
memory error (reason 2). Current 5M simulated cold boot has zero data faults.
Investigate actual build/source identity, boot-register claim/decode and
hardware timing; do not paper over it with a RAM alias or firmware patch.
Trace ring is the explicit trace sink/unsupported-LCD stream, not a complete
CPU instruction or peripheral bus history. Zero entries alone cannot establish
that no other peripheral accesses occurred or that the CPU stopped permanently.

Preserved snapshot, decoded JSON and observations under
`scratch/hardware-bringup/first-black-screen/`. No RTL changes or GitHub build
monitoring performed. The user monitors builds. Waiting for the logo is not a
substitute for investigating the captured early fault.

## 2026-11-07: user requires original service files and standalone C:

The current user-supplied RBF/ignored kit may be tried for the first hardware
smoke test, but the four-section NGB firmware/user seed and combined NGA save
are **not** accepted as the final user workflow. Added milestone **7.6** in
`docs/mister-implementation-plan.md`: original MCU/PPM service containers as
`boot.rom`/`boot1.rom`, independently mountable raw C: at file offset zero,
separate PMM persistence, no firmware repack when changing C:. Service-file
parsing/loading is not implemented in the current RBF. No loader RTL changed
in this clarification, and no build or simulation was started.

Verified in maintained RTL that raw scrambled firmware remains in DDR and
`ngage_codeflash` routes normal array data through `ngage_flash_read_decode`;
two address-dependent halfword transforms apply only to physical
`[0x0000a000,0x002b3000)`. C:, PMM and flash status/commands bypass the cipher.
The current assembled core/extension are derived from service records with
PPM overlays; the new loader must reproduce those bytes without pre-decoding
or modifying firmware. Service **PPM** is distinct from writable **PMM**.
User retains responsibility for monitoring GitHub builds.

## 2026-11-07: native BRAM lanes corrected; user monitors builds

Run 42358035176 (`87dea06`) rejected automatic byte_size=0: Quartus derived
16-bit byte lanes, while its supported sizes are 5/8/9/10. This invalidates the
previous default-sizing approach below. Whole-word memories now use explicit
8-bit native lanes with constant asserted byte enables; scalar write enables
control wren. Payload widths are padded internally (1->8, 27->32, 84->88), and
padding is discarded on read. Logical interfaces, latency and behavioral model
are unchanged. 32-bit/four-byte-enabled cache/UPP memories remain 32 bits.
Physical RAM allocation can increase with padding and remains unverified.

Behavioral and Intel-model width/byte/port tests pass; Intel-model cache access,
writeback/maintenance and source preflight pass too. Commit/push and start a new build. User explicitly takes over monitoring:
**do not poll/watch the replacement action.** Inspect only when requested.
No fitter/timing result exists from these parameter-rejected builds.

## 2026-11-07: Quartus whole-word byte-enable parameter corrected

Run 42357641897 (`a9aa052`) selects `altsyncram` correctly, then fails during
primitive parameter checking: a 16-bit sector RAM has one whole-word enable,
but the wrapper explicitly set byte_size=8, which requires two enables.
Set byte_size=0 (Intel's automatic/default mode) for single-enable memories,
matching the JTFRAME wizard pattern that omits byte_size for whole-word writes.
Multi-lane cache/UPP RAM retains explicit 8-bit lanes/four enables. Widths
1/16/24/27/84 keep their full-word interface without padding or storage changes.
The reported clear-box error follows the rejected parameters; check the next
Quartus run for any independent remaining issue. No new resource/fit result.

The behavioral/vendor BRAM suite and source preflight pass. Commit/push and
start another GitHub build. Earlier CPU/board behavior remains unchanged;
only the primitive's whole-word byte-size parameter changes.

## 2026-11-07: Quartus RAM branch selection corrected

GitHub run 42357152231 (`b4ec63a`) failed in synthesis with multiple constant
drivers on `ngage_bram.memory`; no new fitter/resource result exists. The
wrapper incorrectly assumed this Quartus 17 project defined `SYNTHESIS`.
Quartus selected the dual-writer behavioral simulator branch. Added explicit
`ALTERA_RESERVED_QIS` selection using the native macro found in the JTFRAME
Pocket reference. `SYNTHESIS` still selects the same primitive for vendor-model
simulation/lint. The temporary wrapper macro is undefined at the end of the
file; other RTL guards are unchanged.

The BRAM regression passes preprocessing with **only** `ALTERA_RESERVED_QIS`,
asserting that `altsyncram` is present and the behavioral array absent. Both
behavioral and Intel primitive-model tests pass, as do source preflight and
formatting. Commit/push and dispatch the replacement build. Original CPU/board tests
below remain behaviorally applicable; this fix changes Quartus branch selection.
Fit, M10K allocation and timing are still pending actual compilation.

## 2026-11-07: explicit M10K conversion verified locally; Quartus next

At the user's direction replaced the large register arrays with explicit
Cyclone V `altsyncram` M10K instances using the JTFRAME Pocket primitive pattern.
`ngage_bram.v` supports true/simple dual ports, byte enables and bounded depth;
its inferred-looking array exists only in the non-synthesis simulator branch.
Converted dirty bitmap, all HPS sector/snapshot/trace storage, cache data,
virtual/physical cache metadata, UPP RAM, UEM values, sparse payload and packed
RGB444 LCD framebuffer. Cache geometry remains 16 KiB / 64 ways. Small control,
CAM, valid/dirty and streaming pipeline registers remain. Details, source pin,
latencies and pending hardware gates: `docs/quartus-memory-audit.md`.

**Observed local validation:** complete `tests/cpu/run.sh` passes (119 PASS
records, one expected legacy direct-mapped associativity XFAIL), including
MMU, IRQ/FIQ, SWP, lockdown, maintenance and instruction prefetch. The first tag
pipeline failed the warm ADD timing check (four cycles instead of one); a
two-line streaming buffer and two-instruction lookahead (ZAP patch 0039) restore
exactly one cycle per warm ADD in both memory-delay profiles. Intel's actual
primitive model passes BRAM widths/ports/byte masks/depth, cache tags, complete
cache access/writeback/maintenance and dirty collision/boundary tests.

Full 4 MiB C:/64 KiB PMM restore/reload and actual `hps_io` save/NOR/DDR transfers
pass. Diagnostic export through actual HPS, decoded capture and trace ring pass.
UEM/reference timing, sparse CAM/payload, board ownership and warm/cold reset,
ARM IRQ/FIQ/data-abort board integration, cache-clean/LCD DMA visibility and
MiSTer-bound ARM/SIMIF/LCD DMA/diagnostic fault/SDRAM-with-waits checks pass.
The 176x208 scanout matches the saved firmware image pixel-for-pixel; LCD DMA,
line bands, full frame and protocol fixtures pass. Optional old retained-DMA
trace replay is skipped because that old local trace is absent. A fresh bounded
**5,000,000-cycle** HDL cold boot passes at PC `00006178`, 18 known fetch faults,
**zero data faults**, before logo/LCD traffic. This is not a new Nokia-logo run.

Source graph: **168 files/nine QIPs**. Explicit synthesis-path vendor-model lint,
structural top elaboration, formatter and ZAP patch reproduction pass. Logs are
under `build/sim/` (`cpu-bram-suite.log`, `primitive-cache-current.log`,
`dirty-bram-current.log`, `hardware-bram-current.log`, and the named chip/unit
directories). No local Quartus resource/fit/timing result is claimed.

Old 1B..12B checkpoints remain untouched and require their frozen executable;
new RAM state/layout must start cold. User authorized commit, push and starting
the GitHub build after verification. Next inspect its RAM summary/M10K packing,
ALMs, fit and 104 MHz timing before claiming hardware readiness.

## 2026-11-07: fitter failure and memory inference audited; 12B boot completed

The user supplied the failed Quartus 17 reports for 506f9ea. Synthesis completed; fitting fails at **101,673/41,910 ALMs (243%)**, including the combinational-node limit 106,367/83,820. Block memory is 2,367,592/5,662,720 bits (42%). Audited the actual synthesis RAM/entity tables before changing RTL, at the user's direction. Framebuffer, both cache data arrays and UPP RAM windows **do infer RAM**. The dirty tracker instead costs **26,523 ALUTs/8,360 registers**, cache metadata totals **15,655 ALUTs/40,652 registers**, and snapshots/sector buffers/trace also stay in flip-flops and muxes. Parent totals include children and must not be added. The failed fitter's zero RAM-block count is incomplete physical allocation, not absence of inferred RAM.

Full grouped memory table and repair priorities: `docs/quartus-memory-audit.md`. Parsed source hashes/entity counts and reproducer: `scratch/quartus-memory-audit/`. Primary candidate is a synchronous RAM-based dirty bitmap with explicit collision handling; next are pipelined snapshot/sector buffers, then cache metadata banking while preserving 64-way geometry/CPU behavior. No RTL or cache geometry was changed in this audit, and no resource-reduction/fitting success is claimed. The four-bit scaler mode/five-bit VHDL port mismatch is a separate critical warning. Run kit RBF remains unavailable because the action failed fitting.

The frozen normal-power-key simulation **completed 12,000,000,000 cycles**, PC `5152B480`, 18 known fetch faults and **zero data faults**, without interruption. Its framebuffer/scanout hashes are unchanged from the verified 2B Nokia image; no N-Gage logo or screensaver was reached. All permanent **1B through 12B CPU/host pairs** were checked present (1B/2B in `logo-normal-2000m`, 3B..12B in `logo-normal-12000m`). Source firmware hashes passed at run exit. No simulation is currently running. Next boot diagnosis must use saved-build replay; later LCD/keypad/video/source edits have not been spliced into this lineage.

## 2026-11-07: ignored MiSTer run kit prepared

At the user's request prepared `scratch/mister-run/`, entirely ignored by Git. Its SD-card layout contains `games/NGage/NEM4-4.03.ngb` (audited stock core/extension and initial C:/erased PMM), writable `working.nga`, optional empty `diagnostics.ngd`, setup README, checksums and preparation manifest. Bundle CRCs, save header/profile/core/extension identity and byte-for-byte C:/PMM payloads were verified; PMM is erased and original sources unchanged. This is the same firmware/C: profile as the normal Nokia-logo simulation, not a simulator checkpoint or modified firmware.

`_Console/NGage.rbf` is still pending the GitHub action (run 42318379943, commit 506f9ea, building when checked). The kit's `fetch-rbf.sh` downloads only a successful run's Template-rbf artifact, refuses to overwrite an existing core, renames it and records revision/hash. The README covers SD paths, bundle/save loading, CPU Hold -> Run, No ATR, Phone/Original video, flush and diagnostics. Hardware boot/persistence remain unverified. No firmware or working data was staged for Git.

## 2026-11-07: Quartus cache-line generate syntax fix

User's GitHub Quartus build reports Error 10170 at `rtl/arm920/cache_lines.sv:18`, rejecting the inline `genvar` declaration and then ignoring the module. Moved `genvar lane;` to module scope and kept the generate loop's initializer as `lane=0`. Byte-lane count, indices, storage, read/write behavior and the `lanes` generate hierarchy are unchanged. Cache-line byte-mask/way/segment-isolation and associative-bank dirty-victim/refill regressions pass. Actual Quartus retry remains the manual GitHub action; local Verilator is not a Quartus syntax result. The fix is a separate commit following the verified RTL-formatting commit.

Also inspected the Pocket CPU design at local `~/develop/n-gage`: it is a custom eight-stage ARMv4T pipeline with caches and an NGVM-specific MMU, not a tiny interpreter. Its smaller compatibility target comes from replacing the Nokia kernel/drivers and omitting full ARM CP15/MMU behavior. Its docs report ZAP/Quartus difficulties; our maintained ZAP already has several Quartus-17 compatibility edits. Replacing our CPU with the Pocket design would require ARM MMU/CP15/original-kernel integration work, not a drop-in swap. See its `docs/core-design.md` section 5 and `docs/hardware.md` section 2. No CPU redesign was made.

## 2026-11-07: phone RTL readability pass

At the user's direction reformatted all 51 maintained phone RTL/top-level files (`Template.sv`, `rtl/ngage*.v`/`*.sv`) toward the pinned Nortido reference's readable layout: explicit ANSI ports, aligned connections/declarations, separated statements and four-space blocks. No identifiers, values, comments, port order or logic changed. Shared ANSI declarations were expanded to explicit direction/type per port. Imported ZAP, JTFRAME/SDRAM, PLL and framework formatting was retained.

Added reproducible `tools/format_phone_rtl.py`, `.rules.verible_format`, scoped `.editorconfig` and `docs/rtl-style.md`. Verible version is pinned in the documentation. Its temporary equal-width workaround for the legal Verilog-2001 identifier `units` does not rename the source signal. The formatter's read-only check passes with no further edits. All 51 files pass token comparison against originals after only the documented explicit-port normalization. Before/after hashes and original copies remain under `scratch/rtl-format/`; the downloaded tool archive was removed after its hash was recorded.

Source/QIP graph, structural top elaboration, board CPU/SIMIF/LCD DMA/IRQ/FIQ, keypad protocol/shared-source tests, LCD fixture/frame/line-band tests and every-pixel native scanout/replay pass after formatting. This is a readability-only follow-up to the previous hardware-build snapshot. The 12B simulation remains on its frozen executable (past 10.3B, zero data faults when checked); source formatting does not affect it or prove further boot progress. Restore with `--use-saved-build` for that original lineage.

## 2026-11-07: native HDMI rectangle and GitHub-build preparation

At the user's request, HDMI/scaler phone mode now exposes exactly **176x208** active pixels with Original aspect **11:13**. The phone remains centered at (72,16) inside the existing 400x262 timing raster, black outside the picture; DE excludes that surrounding padding. This follows the MiSTer Game Boy separation between centered game image and larger analog timing raster (reference commit `f6796f3a021db61f804c3151678941ce4d74a3b9`). Diagnostic mode stays 320x240/4:3. Actual CRT timing tolerance remains unverified. Phone RGB contains only guest pixels; unknown/incomplete flags remain in diagnostics/log/export instead of a colored top stripe. New-build scanout captures use CE+DE and normalize to a borderless 176x208 PNG. Frozen old builds retain their original raster/output format.

Native raster tests pass every pixel of two coordinate-coded patterns, exact active/sync counts, diagnostic sizing and black analog padding. A separately labeled display-only replay of the observed stock-firmware Nokia framebuffer produces a native scanout PNG byte-identical to the original framebuffer PNG (`b15a3e46...`). This verifies the new video path, not a new cold phone boot or board output. Focused LCD protocol, full-frame and line-band regressions and structural top elaboration pass.

User clarified Quartus is available **only through GitHub Actions**, and requested commit/push for a manual action build. Audited the selected QIP graph: added explicit ARM header search path, removed duplicate core PLL inclusion from framework Q17 selector, replaced stale generated core PLL metadata with a source-only manifest pointing to the existing two-104-MHz-output HDL. No PLL/SDRAM behavior changed. Added an executable source-graph preflight to the action; local Tcl verifies 167 required files/includes and nine unique QIPs. Two missing optional HDMI/audio component-symbol files remain non-synthesis metadata. Actual Quartus compile/fit/timing is pending the manual action; no RBF success claim. See `docs/mister-port.md`.

Additional validation: the new native-video HDL build passes a fresh 5M-cycle cold smoke (18 known fetch faults, zero data faults); board CPU/SIMIF/LCD DMA/IRQ/FIQ, keypad, LCD DMA/arbitration and 104-MHz DDIO/falling-capture regressions pass. Recreated all 167 required build inputs plus the project/preflight script from the staged Git index under `scratch/ci-source-preflight/`; source-graph validation passes there with no ignored local source dependency. The RBF build remains manual and unverified until the action runs.

The ongoing 12B simulation remains on its original frozen executable, independent of all these edits. Check its live progress/result before reporting completion or starting a replacement.

## 2026-11-07: Pocket-core LCD reference checked

At the user's direction inspected local `~/develop/n-gage` commit `755ad13b0b5d3f01d228558f29acd0ec1c2007c2`. It replaces the Nokia kernel/LCD LDD with NGVM's whole-frame `IO_LCD_SHOW`, so it cannot explain physical CA/CC init or 15/75 endpoint/wrap behavior. Useful independent leads are RGB444/176x208 layout, cache-clean-before-copy sequencing, a separate frame store and coordinate-coded scanout tests. The channel's observed `{0xA,0,0xD0}` update argument is logical LDD evidence, not panel end-coordinate proof. Full details and pinned source hashes: `docs/lcd-command-evidence.md` and `scratch/logo-bringup/pocket-lcd-review.json`. No Pocket source, firmware, HDL or active simulator was changed. Frozen long run was still active past 7.77B, zero data faults; inspect current progress before further execution.

## 2026-11-07: reference-derived keypad and LCD framing verified separately from long run

**Long-run observation:** the frozen `logo-normal-12000m` run remains active toward 12B. At this update it has passed 7.5B with 18 known speculative fetch faults and zero data faults. A zero-cycle exact-build observation of its saved **7B** CPU/host pair (`logo-normal-observe-7000m`) confirms the framebuffer and scanout are still **the Nokia logo**, with hashes identical to the 2B image. This screen was actually inspected; the direct LCD-write counter alone would not exclude DMA changes. Duplicate observation checkpoint files were removed only after both proved byte-identical to the permanent parent pair; `observation.json` records hashes. The permanent billion pairs are preserved. Read current progress/result before launching a replacement.

**New keypad implementation, separate model:** translated the pinned Nortido contact map by key name; both drive banks and byte-lane set/clear, reference reset drive state, alternate sixth-row drive, bidirectional one-hop digital contact scanning, matrix/direct press-edge latches, byte-enabled W1C and press-over-clear priority now exist. Keypad status overlays only its owned bits; IRQ ORs with NOS on ICU source 25. Tests cover all 20 contacts in both directions, six direct events, held/release/repress, commit/lanes, shared-source independent acknowledgements, ICU masking/re-enable and the routed GENIO1 startup-test merge. No change to the NOS event mask, forced startup success or firmware bytes. Physical timings, higher-order ghost contacts and phone UI response remain unverified. See `docs/live-controls.md`.

**New LCD decode/evidence:** the actual cold HDL boot supplies a 125-write maintained fixture. Added explicit two-word full-panel 15/75 parameter capture, stored start/end fields, interrupted/malformed payload diagnostics, and header/command/data context for unknowns. Nonzero/odd/partial windows are recorded and rejected for direct rendering rather than silently drawn at zero. The reference ignores ends; no unsupported wrap convention or synthetic init success was copied. Init operations remain flagged. Stock `lcd.ldd` independently selects CA/CC counts 11/15 and emits tables exactly matching the captured payloads; generic Epson tables disagree and do not identify this panel. Detailed table, source links, offsets, confidence and unresolved behavior: `docs/lcd-command-evidence.md`; proof JSON/disassembly under `scratch/logo-bringup/`. New logo logs retain non-pixel command traffic after the first clear and sample 32 unknown contexts.

**Verification:** standalone/board keypad and new protocol tests, NOS events/timer, LCD full frame/line bands/fixture/protocol, DMA/SDRAM arbitration, ARM board SIMIF/LCD/IRQ/FIQ, shadow/exclusive ownership and structural top elaboration pass. New cold run `lcd-keypad-cold-500m` completed **500,000,000** cycles in 409.548 seconds with zero data faults, unchanged known 18 fetch faults, complete initial white clear, display on and intentional unsupported flag. All 125 ordered startup address/data writes match the old cold boot exactly; framebuffer hash matches the old initial clear (`6b676b6e...`). Source firmware input hashes pass. This is a bounded early boot, **before NOS startup self-tests and the Nokia splash**; the new input model has not yet been validated through those firmware stages. Evidence JSON: `scratch/logo-bringup/lcd-keypad-validation.json`.

The 12B lineage still uses the frozen pre-change executable. New state layout/register behavior requires a separate cold lineage or an explicitly proven migration; do not inject these changes into old snapshots. Next: continue the new 500M checkpoint through startup/self-tests/logo on its matching build; inspect later partial LCD updates and `lcd.ldd`/`LcdPartialMode.dll` before implementing endpoint/wrap or init bits. Milestone 7.5 remains open for those LCD/UI/physical uncertainties.

## 2026-11-06: frozen normal boot extended to 12B; separate keypad drive fix

User authorized the long run toward 12B while doing HDL work. Cleanly saved the former 3B-target continuation early at **2,095,820,248** cycles, then strict-restored the same executable into `build/sim/runs/logo-normal-12000m/`, target 12,000,000,000. Current execution is the original Nokia-logo model, not the keypad change below. Source snapshot verified against every manifest hash and archived at `scratch/logo-bringup/frozen-normal-12b/compiled-sources.tar.gz`, alongside its original manifest; cached binary identity `b84e5c91b524d278`, SHA-256 `e633b0dd6900bf9f7e2fe2f71cf5b70033ff3c977630b801580e750bf2dc289b`. Check live progress/result before launching another long run. Permanent billion CPU/host pairs remain enabled. At 2.21B the display word count is unchanged and data faults remain zero; no new screen claim. At roughly 1.2M cycles/s, the remaining ~9.8B costs roughly 2.3 hours, subject to simulated workload.

Separately changed `ngage_keypad.v`'s existing 0C15040C drive bank from replacement to byte-lane-2 bit-set / byte-lane-3 bit-clear masks, clear winning overlap, using the pinned Nortido register lead translated onto the current six-bit scan state. Preserves untouched lines and zero masks, respects commit/byte enables. New directed cases fail the original HDL and pass the fix; standalone/board keypad, routed GENIO self-tests and ARM board CPU/SIMIF/LCD DMA/IRQ/FIQ integration pass. This narrow staged correction does not implement the other drive bank, alternate seventh-line control, bidirectional contacts or keypad edge IRQs; physical wiring/direction remains unverified. It has **not** been applied to the active 12B lineage.

Added explicit runner `--use-saved-build` for resume after workspace HDL edits: requires a restore, forbids upgrade/fork flags, verifies the exact saved executable and container hashes, keeps the original compiled-source manifest and checks inputs/reset cause. It never rebuilds or applies new HDL. A 2B -> 2.002B frozen replay after the keypad edit passes with the same framebuffer and scanout hashes. Default runner restores remain strict. For testing new keypad behavior in a phone boot, use a separate from-reset lineage; do not silently insert it into the 12B run.

## 2026-11-06: continuation toward N-Gage startup screen

At user follow-up resumed the verified normal-power-key 2B state with strict same-model restore as `build/sim/runs/logo-normal-3000m/`, target 3B. Initial continuation passes 2.04B with zero data faults and unchanged 36,689 LCD words. Check live progress/result before another run. Next expected visual target is N-Gage startup, supported by historical software/HLE evidence, not yet observed in this HDL lineage. Screensaver/idle requires later startup completion and may be blocked by incomplete device/service modeling or absent SIM; do not claim it follows automatically from Nokia-logo success. Firmware remains unchanged.

## 2026-11-06: stock-firmware Nokia logo reached in cold HDL boot

**Observed success:** `logo-normal-2000m` completed from reset at 2,000,000,000 cycles, PC `514A112C`, in 1,945.12 seconds (~32.4 minutes). Fresh framebuffer and actual scanout both visibly show the blue **NOKIA** logo on white. This is executed stock firmware writing the modeled HDL display; no image was injected and no firmware/guest-RAM patches were used. The run has 36,689 LCD words, frame_complete=1, display_on=1, the same 18 known speculative fetch faults and **zero data faults**. Normal power-key reset profile, no SIM/ATR, erased PMM, existing C: source and modeled DDR/SDRAM backing are recorded in the run manifest. Original inputs passed the runner's post-run hash checks.

PNG evidence: `build/sim/screens/logo-normal-2000m/framebuffer.png` and `scanout.png`. Framebuffer binary SHA-256 `aa346d99a4db8515e4e7500c93d58ea329dee8c94cea543a26efed120b979737`; PNG `b15a3e464a03347bc02d591964dacce5b8ae0326b775f4b4c5fdd6fe0d1694ab`. Permanent paired 1B and 2B checkpoints retained. Strict same-model restore to 2,001,000,000 cycles (`logo-normal-resume-2001m`) passes, zero new faults, byte-identical framebuffer and scanout hashes. Checkpoint/provenance hashes recorded in `scratch/logo-bringup/nokia-logo-evidence.json`.

The logo objective is achieved under the staged model. **Milestone 7.5 remains open for LCD protocol/keypad work:** unsupported=1 persists and appears as the deliberate red top strip in scanout. Window endpoint/odd-start semantics and physical panel behavior are unverified; do not suppress diagnostics or claim full Symbian/board validation. Next: replay near display activity with bounded command diagnostics, resolve reached unsupported commands and window semantics against stock firmware and the pinned Nortido reference, then test keypad behavior. No long simulation is currently running; both runs completed successfully.

## 2026-11-06: 6B alarm run finished; normal power-key cold boot selected

`logo-bounded-6000m` finished at 6,000,000,000 cycles, PC `504195A0`, 18 known speculative fetch faults, zero data faults. Framebuffer/scanout remain white; 18,353 LCD words are the initial clear/parameters, not logo evidence. All reached billion-cycle pairs remain preserved.

Read-only inspection and stock firmware disassembly identified a reset-profile issue: hardcoded UEM register 3F=1 selects the alarm startup path. The startup conversion distinguishes NORMAL/ALARM/CHARGING; the observed MTC mode 3 is alarm mode. Earlier suggestions that mode 3 proved pending COMMGR activation were incorrect: inspected groups have their active flag set, and member status 4 also occurs on commit. This does not prove that alarm mode alone explains the missing logo.

Added staged `POWERUP_STATUS` through UEM/board, with MiSTer default 2 for power-key startup. Register 3F clears bit 1 after the existing modeled key-release event, matching the software reference; silicon reset-cause behavior remains unverified. Direct UEM/board default stays 1 for historical comparisons. CBUS regressions cover both status values before/after release; standalone and board keypad regressions pass. Firmware and guest RAM are untouched.

Logo runner now records `--powerup normal|alarm`, defaults normal, includes it in build identity, and rejects cross-profile restores (legacy manifests mean alarm). The historical bounded harness explicitly retains alarm mode. A clean normal-profile run is being built/launched as `build/sim/runs/logo-normal-2000m/`, target 2B; no old alarm checkpoint is used. Check its manifest/progress or Docker state before claiming it is running. Next evidence: boot mode, startup self-tests, actual new LCD transfers and saved screenshots. No logo claim.

## 2026-11-06: deeper storage cleanup and transparent archived-state restore

User requested further reduction. Project now measures about **3.5 GB**, down from the reported 15.6 GB. Removed 27 redundant test-state files and verified duplicate per-run C: input copies. Losslessly compressed 103 inactive CPU/host pairs, preserving all real billion-cycle history and pairing/hash metadata; current resume states and canonical pre-self-test points remain ready. Smaller historical logs/traces were compacted too. Generated Windows SDK extraction was archived and every regular file checked against the tar member before removing the extracted tree. Source firmware, saves, screenshots and required model binaries/source libraries remain preserved.

Detailed inventories: `scratch/cleanup-deep-2026-11-06/manifest.json` and `sdk-archive.json`; earlier trace/cache cleanup inventory remains separate. New RTL runner transparently expands archived checkpoint pairs, verifies hashes, restores and removes the temporary expansion. Archived versus plain 6M -> 7M continuations produced byte-identical CPU/host states; the redundant comparison state files were then removed, with hashes recorded. Legacy tools may `gzip -dk` first. SDK recovery: `tar -xzf build/sdk-extract.tar.gz -C build`.

An unexpectedly verbose live decoder-warning log was found. To cap ongoing growth, the core was cleanly stopped/saved at **4,934,111,672** cycles in `logo-gpio-fixed-6000m`; it remained white, with no data faults. Same-model strict restore is now running as **`build/sim/runs/logo-bounded-6000m/`**, target 6B. Its complete console is streamed losslessly to `run.log.gz`, bounded live head/tail to `run.log` (~512 KiB), and progress/owner/fault milestones to `progress.log`. No model/firmware change accompanied this logging restart. The executable hash remains identical across orchestration edits; compiler caches are automatically discarded. Observe this active run before starting another. The prior `logo-gpio-fixed-6000m` name is now a completed, interrupted parent, not the active process.

## 2026-11-06: storage cleanup complete; checkpoint history retained

At the user's request removed 42 rebuildable compiler `.gch` files and losslessly archived 151 finished `.tsv`/`.log` traces after verifying decompressed SHA-256. Freed about 7.7 GB (7.19 GiB); project measured about 7.4 GB afterward. No firmware, saves, CPU/host checkpoints, screenshots, executables or generated model sources/libraries were removed. Exact archive mapping and original hashes: `scratch/cleanup-2026-11-06/manifest.json`; recovery instructions: `RESTORE.txt` there. Old readers can restore a trace with `gzip -dk path.tsv.gz`, which refuses to overwrite an existing file.

The logo runner now deletes its large precompiled-header caches after a successful build. Default restore compares the exact executable hash, compiled HDL/C++/include hashes, image and inputs; orchestration-only `.py` edits no longer invalidate an identical executable. A 5M -> 6M restore after this change passes with the same executable hash and zero remaining `.gch` files in its build folder.

GPIO-corrected boot `logo-gpio-fixed-3000m` completed at 3B: still white, 18 known speculative fetch faults, zero data faults. MMU-translated MTC state remains 3; the inspected global lines were not resident in D-cache, so the reported words are current backing data for those lines. The earlier fatal state 8 is no longer observed. Active continuation: `build/sim/runs/logo-gpio-fixed-6000m/`, target 6B, same model and normal strict restore, headless Verilator in Jotego Docker; permanent 4B/5B/6B pairs will be retained if reached. This still has the explicitly migrated pre-test ancestry, not a clean final-model cold boot. No logo or full milestone-7.5 completion claim.

## 2026-11-06: GPIO-corrected boot passes the former fatal-state frontier

`logo-gpio-fixed-1800m` completed at 1.8B with 18 known speculative fetch faults, zero data faults and a white framebuffer. Its translated raw MTC state word is now **3**, versus **8** on both IRQ-only lineages at/after the same startup region. This supports the GPIO self-test correction; raw RAM does not overlay dirty cache. No firmware/MTC RAM values were changed. Active continuation: `build/sim/runs/logo-gpio-fixed-2200m/`, 1.8B -> 2.2B, same executable/inputs and normal strict restore. Retain the migrated pre-test ancestry in all reports.

## 2026-11-06: keypad/GPIO startup-test collision fixed; pre-test state migration verified

Both IRQ-only continuations remained white (late fork through 3.8B and earlier fork through 1.7B). MMU-translated raw RAM at `800107E0` held `8`, consistent with the documented MTC fatal self-test state; this observation does not overlay dirty CPU cache. A separate concrete defect was reproduced: with KEYPAD_ENABLE=1, the idle rocker forced GENIO1 high even when the existing UEM-routed loopback drove it low. This breaks the modeled I/O self-test. The new board-keypad regression fails before the fix (`0C150208` routed-low phase returns `2C060000`) and passes afterward, including routed high/low, held rocker grounding high and idle after disconnect.

`ngage_keypad.v` now takes explicit staged `genio1_driven`, wired from existing `route2a[3]` in UPP, and merges its open-switch pullup with the driven base level. No self-test result or firmware byte was patched. Full physical direction/pullup/pin behavior remains unverified. The separate GPIO loopback and chip boundaries remain intact.

The additional combinational `route2a` wire changes Verilator's saved-state schema. The strict restore guard correctly rejected it. Added narrow `tests/phone/hardware_boot/migrate-gpio-state.py`: checks all existing generated state declarations/types unchanged, checks complete serialization code differs only by guards and one derived 16-bit route wire, adds that wire from saved UEM written/value state, and reverse-converts to require **byte-identical original CPU/device/guest-memory serialization**. Host state is copied unchanged. It does not execute the guest or edit guest RAM. All original checkpoints remain intact. Current verified migration is `build/sim/checkpoints/gpio-pretests-1500m-v3/`; v2 CPU/host bytes are identical and its original migration script is preserved in `scratch/logo-bringup/state-migration/`.

Source checkpoint `logo-baseline-1500m/checkpoint-1500000000` is before the self-tests: translated MTC word=0, ecust flag=0, CPSR `600000D3` (IRQ/FIQ masked). Active corrected continuation: **`build/sim/runs/logo-gpio-fixed-1800m/`**, restoring the equivalent v2 migrated pair at 1.5B, target 1.8B. It descends from the original from-reset HDL boot and uses both reviewed corrections plus the 64-bit observer. This is an explicitly migrated experimental lineage, not a clean cold boot with the final source. Latest observed progress 1.66B: zero data faults, 18 known speculative fetch faults, no new display transfer yet. Screens are saved under `build/sim/screens/<run>/` on completion; white frames are not logo evidence. Old IRQ-only lineages are complete, not running.

## 2026-11-06: saved-state driver upgraded to 64-bit budgets without changing HDL state

The new driver derives absolute cycles from the already serialized 64-bit host tick count, preserving the existing CPU/host file format and avoiding a 32-bit testbench counter change that would invalidate checkpoints. `--driver-upgrade` checks unchanged HDL/container/inputs and identical generated serialization schema. A 5M -> 6M continuation produces **byte-identical CPU and host files** to the old executable. Synthetic observer-counter rollover and subsequent restore pass at 4,294,967,312 and 4,294,967,344; these are explicitly test-only counter fixtures, not firmware boot progress. Permanent billion pairs are never overwritten at a terminal boundary. Default exact-build restores remain strict.

The late IRQ-corrected lineage reached 3B with zero data faults and a white frame, not a Nokia logo; CPU progresses through kernel/NOS/user-module code. Active continuation is `build/sim/runs/logo-irq-fix-3800m/` (3B -> 3.8B, observer upgrade only). A separate earlier diagnostic fork `build/sim/runs/logo-irq-fix-from-700m/` restores the pre-kernel 700M pair across the same reviewed IRQ-mask fix, target 1.7B, avoiding the later fork's long interrupt-storm history. It uses the previous driver executable and remains resumable with the observer upgrade. Preserve both lineages and all 1B/2B/3B pairs. No logo claim, firmware patch or physical hardware claim. Run logs are bounded; narrow forensic tools and old-model negative control are under `scratch/logo-bringup/`.

## 2026-11-06: long HDL boot found/fixed phantom source-25 IRQ; resumable continuation

The unmodified-firmware fast-memory HDL boot reached 2.1B with only the 18 known speculative fetch faults and zero data faults, but stayed white. A 200K-cycle replay from the permanent 2B pair (`scratch/logo-bringup/replay-2000m.log`) revealed repeated IRQ index 26, GPIO status `8000` and UEM reads, starving startup. `ngage_nos_io.v` incorrectly let every stored status bit generate IRQ. The staged C++ reference explicitly derives `nos_upp_status_` using mask `3680`; bit 15 is a generic latch, not a generated event in this profile. Firmware writes `80008000` during initialization, which therefore created a permanent false IRQ only in the HDL migration.

Corrected only the IRQ expression to the existing modeled event mask `3680`; no new physical GPIO behavior, firmware patch or forced device success. Added the exact bit-15 case, retained readback and real timer IRQ/ack regression to `tests/phone/nos_io/tb.sv`: old RTL fails the new case, corrected RTL passes. Board CPU IRQ/FIQ/data-abort and shadow/exclusive ownership tests pass, and the fixed runner's 5M boot passes. The first attempts to invoke the board scripts inside the simulator container failed because ARM assembly tools are host-side; rerunning those host scripts uses their existing Docker simulation step and passes.

User explicitly requested using save states. The runner already has verified complete CPU/host serialization and permanent 1B/2B pairs; latest old-profile terminal pair is `logo-baseline-2100m/checkpoint-2100000000`. Added narrowly scoped `--diagnostic-irq-fork`: permits only this NOS RTL change with unchanged C++ driver, identical container/inputs and exact generated serialization schema/check values. It accepted the unchanged state layout (`4805514d02843ff7` root signature). This verifies format compatibility, **not** equivalence to a cold boot of the corrected model. All previous pairs remain intact; use a distinct diagnostic lineage.

The diagnostic continuation `logo-irq-fix-resume-2200m` progressed into extension/user startup, first SIMIF/MDI accesses and 267 DDR writes, still zero data faults; no logo yet. Active continuation: `build/sim/runs/logo-irq-fix-2400m/`, restoring its 2.2B pair, target 2.4B. This ancestry includes a runtime model correction; do not describe it as a clean final-model boot or close milestone 7.5. A clean reset run remains a separate acceptance check. Firmware input files are unchanged and SHA-256 checked after each completed run. Default restores still require exact executable/source/image/input lineage. The current runner now hashes HDL include headers and rejects budgets >=2^32.

## 2026-11-06: milestone 7.5 active — resumable HDL boot runner

At the user's request the active lead is pursuing a fresh unmodified-firmware logo run today. Added explicit pinned Nortido LCD/keypad instructions to milestone 7.5, including the ban on its guest patches/driver replacements. New `tests/phone/hardware_boot/run-logo.py` and `logo_main.cpp` extend the maintained testbench with a clock-driven, savable Verilator build, bounded logs, consistent CPU/host pairs, phone video, framebuffer/scanout export and input/source provenance. The fast backing-memory path is explicitly 100MHz with modeled delays and preloaded DDR, no HPS mount or physical SDRAM claim. See `docs/bringup.md` for the command and current <2^32-cycle budget limit.

Runner verification: 1M save -> 5M continuation and uninterrupted 5M produced identical CPU checkpoint SHA-256 `83e1a79c1c39f7248b406d226262e1f70b145f6e1dbc56828c077bd8b93114a9` and host SHA-256 `bca1d841618f38de417e600a559fee6d3b6260d9b9d1fdd7076fad4e6bc109c3`. These initial verification runs had instruction logging enabled; `logo-quiet-5m` repeats the compact-log profile at ~1.5M cycles/s. Existing bounded boot, actual-controller 104MHz SDRAM boot and LCD/raster/line-band tests pass after the testbench changes. Prior bounded logs copied to `scratch/logo-bringup/prior-bounded-logs/`.

First extended run `build/sim/runs/logo-baseline-700m/` completed at 700M, descended from `logo-quiet-5m/checkpoint-5000000`; CPU/host pair and actual framebuffer/scanout PNGs saved. Full white clear complete and display on, 18 known speculative fetch faults, zero data faults; still in stock MD5 code at PC `50003E14`, no logo claim. Active continuation: `build/sim/runs/logo-baseline-1500m/`, target 1.5B, restoring the 700M pair. A read-only inspector linked against the identical generated model/library is under `scratch/logo-bringup/`; no hierarchy or machine state changed. Startup LCD command traffic begins near 263.5M, later than the staged memory model. Preserve this run/checkpoint lineage and inspect progress before starting another run. Retained firmware disassembly was checked byte-for-byte against current stock core LCD routines: `scratch/logo-bringup/firmware-lcd-packing.json`; it confirms start/end packing, explicit row value 208 for the clear, and transfer byte count in the header. End-of-window panel semantics remain unresolved.

## 2026-11-06: Nortido hybrid-core peripheral reference reviewed

See [nortido-hybrid-reference.md](nortido-hybrid-reference.md), pinned to `nortido/NGage-MiSTer` commit `1be08b9bcf951a4523085747572ea102b96de65b`; checkout under `scratch/reference-nortido-ngage/`. High-value leads: LCD `09240003` parameter packing, panel column offset 2, keypad set/clear drive registers and press/W1C interrupts on source 25, MMC/DMA register meanings and UEM channel-8 BSI. Retained local checkpoint trace independently matches column payload `0B100002`, but row payload is `0D000000` versus its host screen-clear helper's `0CF00000`; inclusive/exclusive/clipping semantics remain unresolved. Its LCD ignores end bounds and odd starts, so do not copy it as complete. Small extracted trace evidence is in `scratch/nortido-review/lcd-window-evidence.json`.

Use these leads in milestone 7.5: settle window framing/endpoints, then keypad interrupt/drive behavior with directed tests and shared-source-25 review. Its patched ROM, replacement NOS/Bluetooth drivers, PCM interception and host-observed backlight do not verify our unmodified SIM/ADSP path or physical UEM protocol. This was source research and a read-only retained-trace comparison: no production RTL, firmware, save or checkpoints changed; no simulation, board test or synthesis performed.

## 2026-11-06: 104 MHz DDIO SDRAM read capture fixed in simulation

Investigated the latest inverted-clock failure; see [sdram-104mhz-ddio.md](sdram-104mhz-ddio.md). With the unchanged Micron model (tAC=5.4ns, tOH=3ns), raw DQ is valid between the two rising system edges but at the intervening falling edge. Added default-off `READ_CAPTURE_NEGEDGE` to the controller: falling-edge DQ input register followed by the existing rising-edge data register preserves the adapter's rdy alignment. A falling-edge output register alone is insufficient. The top now uses the existing 104 MHz PLL system output through `ngage_sdram_clock.v`/altddio_out, leaving the old -90-degree PLL output unused; no PLL frequency or memory timing parameter was weakened. Requested fast input-register packing in files.qip, pending actual Fitter proof.

Four-state tests pass for the new inverted path at modeled clock-pin delays 0/0.25/0.5/1ns, all masks/banks/reset/lock/refresh; the wrong-edge negative control reproduces Z failure. Old -90-degree regression, Verilator controller/model test, stubbed top and real-controller 5M boot pass. The boot now models nominal104MHz DDIO instead of 100MHz/-90deg and still matches the staged 102 compact events/1016 claims (375773 bus transactions, 18 known speculative fetch faults, zero data faults/pixels). New script: tests/phone/sdram/run-ddio.sh inside jotego/simulator:arm64. Small diagnostics: scratch/sdram104-review/. No Quartus, synthesis or hardware test; IO packing, half-cycle/internal and board setup/hold constraints, actual PLL reports and multi-write-bank placement remain gates. No long boot, image write or checkpoint deletion. New simulator builds need their own checkpoint lineage.

## 2026-11-06: JTFRAME CPS3 SDRAM clock review

Checked local `~/develop/jtpublicfork` CPS3 and JTFRAME. The relevant macros are `JTFRAME_SDRAM96` and `JTFRAME_180SHIFT`. CPS3's `jtframe_pll7000` configuration names 28/56/112 MHz (the SDRAM96 macro selects the fast clock path; the name does not imply a 96 MHz CPS3 clock). MiSTer `jtframe_emu.sv` uses `altddio_out`, with high data 0 and low data 1, to generate the inverted SDRAM clock when 180SHIFT is enabled. `jtframe_board_sdram.v` sets `HF=1` under SDRAM96 and forces `SHIFTED=0` for that path, irrespective of 180SHIFT. The latter is also our current controller default. For other speed paths, SHIFTED changes `DST` by one clock in the bank state machine; do not assume 180SHIFT automatically means `SHIFTED=1`.

JTFRAME memory requesters capture read data at `dst` and signal completion on `rdy`; in our 16-bit bank configuration `DST` and `RDY` have the same underlying bank state, and our adapter uses registered `rdy`. This needs a controlled signal-level comparison rather than assuming either strobe is earlier. The Verilator SDRAM C++ model updates on SDRAM_CLK falling edges and retains the previously driven data when the model is not driving in its normal mode. The four-state Micron model can release DQ to Z, so a two-state JTFRAME simulation pass would not by itself explain or rule out the 104 MHz inverted-clock discrepancy. The previous note's half-period/tAC observation was an incomplete explanation: the trace also showed data present at an earlier controller sample but Z at `rdy`; quantify both phase and data-strobe alignment. JTFRAME warns that enabling writes on multiple banks may prevent I/O pad placement and cause high-frequency transfer failures; our design enables BA0 and BA1 writes, so this is a real later Quartus fit/timing item. No production RTL changed in this review.

## 2026-11-06: 104 MHz single-PLL / inverted SDRAM clock experiment

At the user's request, made a candidate using the Night Slashers single-output PLL Verilog with 96 changed to 104 MHz and the same `altddio_out` inverted SDRAM clock. The 104 MHz Micron-model SDRAM integration test at 180-degree phase failed in four-state Icarus: the registered controller data is high impedance by the time the adapter sees `rdy`; the model specifies tAC=5.4 ns while half a 104 MHz period is 4.8077 ns. The two-state Verilator version passed but cannot detect high impedance reliably, so it is not evidence that the pin timing works. Capturing the preceding controller sample and reducing the model's tAC to 4.5 ns passed a diagnostic; neither change validates actual hardware or the 5.4 ns model. Do not adopt the earlier sample or reduced timing as a proven fix.

Candidate source copies and diagnostic testbench are preserved in `scratch/milestone8-clock/`; production RTL and the four-state test were restored to the previously passing two-output/-90-degree arrangement. The real-controller SDRAM and lock/arbitration tests passed after restoration. Investigate a valid read sampling/timing strategy against SDRAM specifications and actual fitted board timing before changing the default. No Quartus or physical-board timing was run.

## 2026-11-06: Night Slashers PLL and SDRAM reference

Compared MiSTer-devel/Arcade-NightSlashers_MiSTer commit c75532f (local reference `scratch/reference-nightslashers`). Its single-output PLL Verilog requests 96 MHz from 50 MHz. Its system clock also drives the jtframe SDRAM controller (`HF=1`, `SHIFTED=0`); `altddio_out` sends an inverted, nominal 180-degree clock to the SDRAM pin. Our PLL requests two 104 MHz outputs and drives the SDRAM pin from a nominal -90-degree PLL output. The reference README reports real MiSTer operation, but this comparison does not verify the exact released bitstream's source revision or guarantee our timing. Its 96 MHz PLL QIP metadata ALSO retains the original 20 MHz, one-output values: this is evidence such stale metadata can coexist with a reported working core, not proof it is ignored in our build. Previous wording that the metadata mismatch itself prevents synthesis was too strong; actual Quartus behavior remains untested. The reference uses related but not byte-identical jtframe controller sources: notably it has a timing optimization for SDRAM address/control, while our init waits 11,000 cycles instead of 10,000 to meet 100 us at 104 MHz. Its controller refresh comes from video blanking; ours uses a dedicated refresh scheduler.

A 96 MHz single-PLL-output plus DDIO clock path is a useful concrete alternative, but its 180-degree SDRAM phase does not match our currently tested -90-degree test clock. Do not swap it in without a matched 96 MHz/-180-degree memory-model regression, timer/refresh review and actual Quartus timing/hardware verification. At 104 MHz, copying the 96 MHz generated files alone does not establish a valid 104 MHz PLL or timing closure. No production PLL or SDRAM RTL was changed during this comparison.

## 2026-11-06: assigned milestone 7.5 — HDL Nokia-logo boot and LCD protocol

The user requested adding the actual extended Verilator boot and unknown-LCD investigation to Terra's next milestone. Added [milestone 7.5](mister-implementation-plan.md#75-run-the-hdl-phone-to-the-nokia-logo-and-resolve-reached-lcd-commands) after completed 6/6.5A/bounded-7 work and before full synthesis. Extend existing hardware-bound runners with configurable budgets, complete tested save/restore and permanent billion-cycle pairs, bounded diagnostics and framebuffer/scanout PNG capture; then execute from reset through the Nokia logo, diagnosing real divergences. Investigate reached LCD command/parameter framing, specifically 0x09240003, against N-Gage firmware/traces and explicitly identified Nokia-family emulator/controller references. No fabricated frames, timeout/assertion bypass or forced SIM/ADSP successes. Existing 5M smoke and retained-logo replay are not completion; preserve their evidence and all inputs/checkpoints. Milestone 8 lint preparation remains useful but Quartus availability and real-board storage are not prerequisites for 7.5. This turn changed instructions only; no firmware run, RTL change, synthesis or hardware operation was performed.

## 2026-11-06: milestone 8 Jotego lint and build preparation

The existing `jotego/linter:arm64` image runs the reproducible `sh tests/phone/mister_transport/lint-jotego.sh`. This is structural elaboration with HPS and PLL stubs, not a Quartus compile, physical timing, CDC or FPGA fit result. Reviewed and corrected seven truncation warnings: explicit ROM mapping arithmetic widths, SIM header index, video aspect-ratio port widths, and dirty-tracker sector constant; made the SDRAM bank-response indexing explicit. The Jotego report now has no WIDTHTRUNC warnings (previously seven); remaining warnings include 85 width expansions, legacy case warnings and six missing ports, including simulation-only/trace ports. Full warning log: `build/sim/unit/mister-lint-stubs.log`. DDR/loader/map, actual SDRAM controller, dirty tracker, SIM/card, CPU/board and the bounded 5M staged-vs-real-controller comparison passed after the edits.

The locally available `mister-build:local` image has no `quartus_sh` or `quartus_map`; the Jotego simulator and linter provide simulation/lint, not Quartus. No software was downloaded or synthesis attempted. `sys/sys.tcl` specifies Cyclone V `5CSEBA6U23I7`. The project framework's `sys/pll_q17.qip` and `files.qip` both reference `rtl/pll.qip`; its metadata still says one 20 MHz clock while generated Verilog requests two 104 MHz clocks. The optional `.cmp` metadata references for core, HDMI and audio are absent; determine their significance with actual Quartus rather than creating guessed files. Before FPGA compilation, obtain/use an already installed compatible Quartus, regenerate/reconcile the PLL, elaborate the actual framework/IP, and address remaining width warnings and physical timing/CDC/inference. The user's previous long-run validation requirement also remains distinct from the short test.

## 2026-11-06: milestone 7 bounded integration checks complete

See [milestone 7 verification](mister-milestone7.md) for commands, coverage and remaining hardware risks. The SDRAM discrepancy was traced to high-impedance assignments on a temporary in the Verilator-only Micron reference adaptation; masked read lanes are now represented as zero in that generated test copy. The unchanged production controller passes both Icarus and Verilator directed SDRAM tests, and a real-controller five-million-cycle HDL phone boot passes. `sh tests/phone/hardware_boot/compare-run.sh` compares 102 ordered compact events against a staged run with 1,016 HDL shadow claims; timer IRQ logical-edge and SIMIF staged comparisons pass independently. CPU regression, stock digest, storage, controls, video, reset and diagnostics tests pass. The 18 observed boot scratch instruction-fetch faults are explicitly matched to the staged run, with no data faults. This is a bounded startup check, not proof of full boot or physical SDRAM timing.

Before milestone 8 synthesis, resolve the PLL QIP metadata mismatch with the compatible IP tooling, elaborate actual framework/PLL sources, and address physical I/O constraints, timing, CDC and inference reports. Milestone 6.5 phase B remains pending real Main/storage hardware. No original firmware, save images or checkpoints were changed.

## 2026-11-06: milestone 6.5 phase A complete; phase B pending

The updated storage plan was checked and phase A was executed before milestone 7. Stock core/extension remain NGB/ioctl-loaded in DDR; C:/PMM remain on separately mounted S0 NGA, and S1 NGD is reserved for diagnostics. No guest FAT drive, on-demand firmware block reads, autosave or power-loss journal was added.

The first actual-`hps_io` save test found that `img_mounted` stays high for several clocks: the old save manager treated the same mount as a second media change and stopped. The save manager and diagnostic exporter now edge-detect mount events. A clean zero-size unmount also no longer reports an error; removing or replacing a dirty/in-flight medium still stops safely and preserves working DDR. The bundle-load gate was isolated and tested: a mounted, busy or failed save blocks a bundle attempt, leaves the prior loader-valid state intact and reports the block. A mounted save overwrites deliberately stale C:/PMM DDR on restore. Diagnostic colors now distinguish **unmounted gray, dirty amber, saving cyan, saved green and error red**; this is explicit Flush, not automatic persistence.

`tests/phone/save_hps/run.sh` uses local `sys/hps_io.sv` (test-only PS/2 generate-scope adjustment; SD logic unchanged), real sector/header/save/dirty components and concurrent S1 diagnostics. A second fixture adds real C:/PMM NOR controllers, two DDR arbiters and the DDR adapter. Tests cover first/last sectors in a small 2+2-sector image, successive halfwords across a 512-byte boundary, per-device LBA/ack routing, stable requests and buffer until ack release, 256 ordered 16-bit words at fixed four-clock host strobes without per-word backpressure, simultaneous guest mutation during a save with old snapshot and final rescan, remount, readonly/zero-size mounts, bad header, incomplete read, timeout and medium replacement. C:/PMM first/last writes survive restore and all untouched synthetic disk words are compared; S1 data is checked separately. The tests deliberately inject an incomplete header read, so the logged 128-word header error is expected. A real NAND/phone UI is not involved.

The NOR/DDR/real-HPS fixture also loads the **actual** stock core and extension into test DDR, compares every one of their 20,905,984 bytes after guest-style NOR programming, HPS flush, reset and remount, and finds no changes. Full-size independent tests passed for all 25,165,952 bundle input bytes (12,582,912 writes), complete 4 MiB C:/64 KiB PMM restore/flush/reload and save-image no-overwrite/validation. The full-size peer is modeled; the smaller suite exercises actual `hps_io`. Existing flash reset/erase/dirty, loader/DDR, header, sector, S1 diagnostics, source-hash, CPU/board and top-elaboration tests pass. Original host inputs were SHA-256 checked before and after; hashes and tested source hashes are in `build/sim/unit-save-hps/provenance.json`, and full-size results in `build/sim/unit-save-hps/full-tests.log`. The seeded-PMM first-program discrepancy with the staged C++ overlay remains explicit; the initial parity profile uses erased PMM.

Run from the project root: `docker run --rm --network none --platform linux/arm64 -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 tests/phone/save_hps/run.sh`; full-size checks use `tests/phone/mister_transport/run-full.sh` and `tests/phone/save_manager/run-full.sh` inside the same image. Other focused commands are in the scripts and prior checkpoints. Phase A is simulation-tested and **phase B is pending**: after the existing build/hardware gates, use disposable media on real Main, flush, remount and verify a controlled power cycle. HPS ack alone is not media durability; unsaved DDR can be lost on cold reset or power loss. No actual board, synthesis, long firmware run or hardware persistence claim was made.

## 2026-11-06: milestone 6 final directed checks

The requested milestone 6 implementation and focused test coverage are in place for the documented experimental model. The LCD DMA now lives inside UPP, the display controller remains a separate board module, and PWRONX is a separate UEM input. The LCD tracks coverage from complete line bands, warns visibly on unsupported commands and logs their command values to the diagnostic ring. The saved Nokia-family reference supports commands 0x15/0x75 as column/row operations, but the N-Gage's observed `0x09240003` payload framing is not established; do not infer window parameters or claim those commands are implemented. Firmware/physical orientation and other command behavior remain future investigation.

A new bounded 5,000,000-cycle startup uses the actual HDL CPU, board, flash, ROM map, DDR arbiter/adapter and SDRAM arbiter; only backing DDR/SDRAM are test memory models, with no C++ phone-device fallback. It reads the stock core/extension and existing 11B C: image without modifying them; PMM starts erased. It reached PC `0x000063ec` with 377,752 acknowledged bus transactions, no data-bus faults and no LCD words or DDR writes. Its 18 instruction-fetch bus faults are at `0x0c0047e4..ec`, matching the previously observed early scratch-fetch fault category; a fetch is not necessarily architecturally executed. This is a short startup check, not a completed boot or evidence of visible output. `build/sim/unit-hardware-boot/run.log` is about 1.2 KB; rerun using `sh tests/phone/hardware_boot/run.sh`.

Diagnostics now record first instruction-fetch and first data fault separately, so the startup fetches do not mask a later data fault. The fetch/data owner is exposed as an explicit synthesizable CPU/merger port and is recorded in `patches/zap/0038-bus-owner-diagnostics.patch`; `patches/zap/verify.sh` passes. The debug snapshot counts both trace collisions and events dropped while it is frozen. Standard MiSTer `OSD_STATUS` suppresses controls and clears held keyboard state while open; Shift+3/Shift+8 and keypad slash/multiply preserve independently held hash/star sources. A USB keyboard disconnect without key-up remains unobservable on the exposed PS/2 event interface; opening the OSD clears stuck keyboard state.

Final focused suite passed: reset/read/program/erase and dirty tracking through DDR; diagnostic disk snapshot/decode and actual `hps_io` protocol simulation; LCD full/partial/line-band and real retained-frame framebuffer checks; IRQ, CPU arbitration and cache-clean visibility; all keypad contacts, OSD inhibition and PWRONX status; SIM, CBUS, board, LCD-transport and existing save tests. CPU and 5M firmware smoke tests also pass, and the stubbed top structurally elaborates. A real MiSTer/Main upload and saved-media cycle, LCD window parameters, GPIO/key interrupt behavior, FPGA resource/timing closure and interactive UI are not established; those require later hardware/firmware work. Never interpret the retained-frame logo as output from the 5M run.

## 2026-11-06: added storage milestone 6.5 for Terra

At the user's direction, fixed the architecture decision in [mister-implementation-plan.md](mister-implementation-plan.md#65-verify-firmware-in-ddr-and-writable-cpmm-persistence): immutable firmware via ioctl into DDR; C:/PMM in a separate writable S0 block image, with DDR as working storage and S1 kept for diagnostics. Terra should finish current milestone 6, then complete new milestone 6.5 phase A: actual-hps_io C:/PMM read/write/remount and multi-device tests, full-size/flash/reset/dirty integration, saved-image authority over bundle seeds and explicit Flush status. Phase B requires real Main/storage verification after the build gate, during milestone 9, including controlled power-cycle recovery. Track simulation and hardware completion separately; no autosave or journal is implied. This turn changed instructions only; no RTL, image, checkpoint, simulation or hardware operation was performed.

## 2026-11-06: C: persistence checked against MiSTer block-device guide

Compared the supplied MiSTer hps_io block-device guide with current C:/PMM save wiring and local WIDE=1 sector engine. The architecture already uses standard S0/LBA/sd_rd/sd_wr/sd_ack and a complete buffered 512-byte sector, not ioctl upload. Sector/save-manager and actual-hps_io diagnostic export tests pass again (`scratch/mister-block-device-audit/tests.log`). Added the explicit C:-specific actual-hps_io read/write/remount and real Main/storage acceptance gate to `docs/mister-flash-save.md`; the existing diagnostic test alone does not establish C: persistence. Writes currently require explicit Flush; no automatic write-through or sudden-power-loss guarantee is claimed. No production code, original images or checkpoint pairs changed, and no synthesis/hardware write was run.

## 2026-11-06: milestone 6 validation and diagnostic-disk export

Phone-reset coverage now includes accepted C: and PMM program writes and a 16 KiB C: erase through the actual `ngage_mister`, DDR arbiter, DDR adapter and dirty tracker. The CPU stays held until backing work finishes, and all three dirty sectors are presented to the flush scanner. Delayed reads and a reset coincident with a response are also covered; an actual DDR-adapter cold-reset read drains correctly. An integrated cold reset also cancels a DDR write not yet physically accepted and allows a subsequent flash program. Sudden power loss and cold-reset durability of an already committed write are still not guaranteed: cold reset resets the save manager/tracker, so a remount restores the saved disk image and must not be described as preserving unsaved DDR contents.

The local MiSTer Main source (`Main_MiSTer/user_io.cpp` around `UIO_CHK_UPLOAD`) polls core-initiated ioctl uploads only for selected core families, so the earlier generic upload request was not a reliable export path. It has been replaced with a separate standard two-sector virtual disk (`S1,NGD`): `ngage_diag_export.v` freezes trace insertion briefly, snapshots the 64-event ring, counts events dropped while frozen, and writes exactly 1024 bytes via HPS block I/O. The real diagnostic ring → HPS-sector test → disk image → `tools/ngage_diagnostics.py decode` passed, including fault address/reason, event ordering and dropped-event count. Create a new disk without overwriting an existing file with `python3 tools/ngage_diagnostics.py create /path/to/diagnostics.ngd`, mount it in the OSD, choose **Export diagnostics**, then decode that file on the host. Readonly or undersized images fail visibly. A second test drives the actual `sys/hps_io.sv` virtual-disk mount, request, LBA, acknowledgment and all 512 data words; its test-only copy adjusts legacy PS/2 generate-block scope for Verilator, leaving SD logic unchanged. Real MiSTer Main and media have not been exercised. The first fault can change during snapshot if it occurs after its header word was captured; a subsequent export captures it.

LCD now tracks complete 88-word rows and can establish full frame validity from line bands in any row order. Incomplete fragments remain marked incomplete; unknown LCD controller commands produce a visible warning instead of being presented as understood. The retained full firmware frame still matches checksum `6de5f326`. A new integrated ARM/MMU/write-back-cache test runs LCD DMA before and after clean-by-MVA and write-buffer drain: DMA sees the old physical SDRAM word first and the new word after cleaning. This is the intended noncoherent behavior, not a claim of verified phone timing.

MiSTer `OSD_STATUS` now suppresses all keys and clears held PS/2 keys while the menu is open; controller levels and keyboard ownership have directed press/hold/release tests. F10 now drives a separately named active-low UEM `PWRONX` boundary and the staged UEM status-bit hypothesis; the electrical and interrupt behavior remain unverified. USB keyboard disconnection without release events still has no signal in this interface, so an already held keyboard key may remain held until OSD open or reset. Firmware UI navigation, actual keypad IRQ needs, physical LCD command/window behavior and complete hardware validation remain open; do not claim an interactive phone. No long boot, FPGA synthesis or real-board deployment has been run.

Focused tests: `tests/phone/flash_reset/run.sh`, `tests/phone/diag_export/run.sh`, `tests/phone/lcd_display/run.sh`, `tests/phone/lcd_dma/run.sh`, `tests/phone/keypad/run.sh` in `jotego/simulator:arm64`; `sh tests/phone/lcd_cache/run.sh` runs the ARM cache/board integration through that image.

## 2026-11-06: review fixes and MiSTer milestone 6 in progress

The independent review in `docs/mister-review-2026-11-06.md` identified a real stale flash-response bug. The CPU is now held in reset while accepted flash operations drain; the controllers remain in reset long enough to clear command state, without waiting for uncompleted command sequences. Cold transport reset explicitly cancels controller state. The original reproducer now passes, as do delayed code/C:/PMM reads and a reset coincident with response. Existing C: erase-reset and save tests pass. **Still required:** an integrated reset test for delayed C:/PMM program and erase writes, dirty accounting across both reset domains, and cold reset during backing writes (standalone C: and PMM programs now also survive phone reset with dirty events). A delayed cold-reset read now passes through the actual DDR adapter and a fresh flash request; power-loss persistence is not established. Cold reset can cancel an accepted backing operation whose completion is discarded by the adapter, so do not claim committed-write dirty tracking is proven across cold reset.

Seeded PMM retains physical NOR 1→0 semantics in RTL; a new cleared-bit test passes without a spurious dirty event. The staged C++ overlay still differs for the first write into a seeded halfword. Use erased PMM for the first software-parity comparison; seeded-profile parity remains open. Current structural elaboration with HPS/PLL stubs reports no `UNOPTFLAT` warning in its current log; this is not a real FPGA timing analysis.

Milestone 6 implementation now includes: a separate board-instantiated transaction-level LCD display and 320×240 diagnostic raster; a UPP-side observed-shape LCD DMA channel connected to the shared SDRAM arbiter and ICU IRQ 7; the experimental active-low keypad matrix/rocker and separate F10 UEM power-key level hypothesis; PS/2 make/break and controller held-state mapping; and a 64-entry MMIO trace ring with sticky first-fault address/reason. MiSTer OSD defaults to **CPU Hold** and **Diagnostic** display; Run is an explicit choice gated by image/load/save/scrub readiness. The diagnostic screen has color bars and status cells (left to right: PLL, firmware bundle, SDRAM scrub, board init, save mounted, first fault). The HPS upload path exposes 16-bit diagnostics words and OSD requests export, but Main support and upload length have not been verified on real hardware.

Directed tests pass for full/incomplete direct frames, RGB444 halfword order, raster sync, partial DMA and invalid destinations, held requests, IRQ/ack and CPU-lock contention. A full 18,304-word DMA traversed the real SDRAM arbiter and framebuffer; the retained firmware frame from `boot-v15-simif-noatr-faulttrace` reproduced checksum `6de5f326` (local trace replay, no firmware image copied into source). A PNG rendered from that same retained frame is `build/sim/screens/milestone6-lcd/retained-firmware-frame.png`; it shows the Nokia logo and is not a new phone boot. The CPU integration test programs a partial DMA and confirms the actual framebuffer write, IRQ acknowledgement and a captured fault. Tests also cover all 20 keypad contacts, rocker and held/released inputs, mixed keyboard/controller hold, simultaneous keys, F10 power-level press/release, ring wrap and first-fault stickiness. The focused flash/save, SIM, board, LCD-transport and stubbed-top regressions pass using `jotego/simulator:arm64`. No firmware UI or MiSTer board was exercised.

**Milestone 6 remains incomplete:** the F10 status-level hypothesis is not a physical PWRONX pin model; OSD/disconnect key release, broader mixed controller/keyboard cases, controller window/format commands, line-band frame validity, cache-clean visibility and a full hardware-bound firmware run need work. The diagnostic framebuffer is single-buffered and partial updates before an initial complete frame are marked incomplete. The LCD bus, timing, byte orientation and keypad wiring remain hypotheses; no actual UI input response is established. The DDR reservation, real HPS save/upload, PLL, RAM inference, FPGA fit and timing remain unverified. Next: extend integrated flash reset/dirty tests, finish physical input/power and LCD command/partial-frame coverage, validate HPS diagnostic export, and build the no-C++-fallback hardware-bound short replay before any long boot or synthesis.

Tests: `docker run --rm --network none --platform linux/arm64 -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 -c 'sh tests/phone/flash_reset/run.sh && sh tests/phone/lcd_display/run.sh && sh tests/phone/lcd_dma/run.sh && sh tests/phone/keypad/run.sh && sh tests/phone/diagnostics/run.sh && sh tests/phone/mister_transport/lint-top.sh'`; `sh tests/phone/mister_board_cpu/run.sh`. Retained frame replay is skipped visibly if its local trace is missing.

## 2026-11-06: independent review of MiSTer milestones 0–5

Reviewed implementation and current staged SIMIF changes; see [mister-review-2026-11-06.md](mister-review-2026-11-06.md). Reproduced a P1 reset lifecycle bug: a delayed pre-reset flash response acknowledges a restarted master's different request without fetching its address (`scratch/mister-review-20261106/reset-repro.log`). Fix ownership/cancellation/drain and command reset before releasing the CPU. Existing 27 focused script groups, integrated ARM/board/SIMIF test, reference hashes/fixtures/digests, actual-controller SDRAM tests/full scrub and full bundle/save tests pass independently; they do not cover this reset case or prove a complete firmware boot. Seeded-PMM first-program semantics still differ from C++. Recommended order: short reset/integration gate, then milestone 6 split into diagnostics/video first, LCD DMA/display, and controls. No implementation, firmware, screenshots or checkpoint pairs changed; no long firmware simulation, synthesis or hardware deployment performed.

## 2026-11-06: MiSTer milestone 5 diagnostic SIMIF

Milestone 5's scoped diagnostic SIMIF port is complete and tested. `ngage_simif.v` resides inside the UPP peripheral hierarchy, and `ngage_test_sim.v` is a separate board-level synthetic card. Both use a byte-transaction shortcut; the physical UPP–UEM–SIM serial wiring and timing are not modeled. The existing DSP behavior is unchanged and no successful modem self-test has been invented. The MiSTer OSD selects **No ATR** or **Test card**, sampled on reset; default is No ATR. The card FIFO has 64 entries and reports sticky overflow through the SIMIF unmodeled path until reset.

Validation with `jotego/simulator:arm64`: 554 test-card operations are byte- and FIFO-depth identical to staged C++ `TestCard`, including absent optional OPL/PNN; bounded overflow/reset passes. A separate staged `BootProfile` comparison passes 31 no-ATR and 194 present-card transactions, including byte lanes, auto-clearing control read, single ATR injection, card commands, FIFO thresholds, W1C and pending state; every request is held uncommitted for two clocks first. Board tests check reset-only profile selection, group status and FIQ bit 26 masking; an ARM program running through `ngage_mister` exercises ATR and SELECT on the integrated CPU/card bus. Existing board wrapper, address inventory, IRQ, system-control, LCD transport, C++ fixture and MiSTer CPU regressions pass, as does top-level structural elaboration with HPS/PLL stubs.

Fresh staged-reference/HDL shadow runs for both profiles each reached 20,000,000 cycles with 1,016 HDL board claims and no divergence (`build/sim/runs/milestone5-short-{present,noatr}/`, 56 KB each). These short startup runs did **not** reach SIM initialization and do not establish card recognition. The isolated runner and build live in `scratch/milestone5/`; it starts from reset and must not restore older CPU checkpoints. Its instruction-fetch error path was corrected to let both models generate the architectural abort, as the MiSTer board does; an earlier run stopped at 43,493 because the temporary harness incorrectly stopped on that expected fetch fault. No firmware boot completion, physical SIM accuracy, FPGA synthesis or hardware test is claimed.

Test commands: `docker run --rm --network none --platform linux/arm64 -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 -c 'sh tests/phone/card_fixture/run.sh && sh tests/phone/simif_reference/run.sh && sh tests/phone/simif_board/run.sh'`; `sh tests/phone/mister_board_cpu/run.sh`; `sh scratch/milestone5/build.sh && python3 scratch/milestone5/short.py`. Continue with milestone 6; a longer controlled firmware comparison remains a later integration task.

## 2026-11-06: schematic-based chip boundaries

Added `docs/chip-inventory.md`, based on NEM-4 schematic issue 1, with component identities, connections, current RTL and unknowns. The schematic identifies D550 TMS320DA250GHH-144 as a **separate audio DSP** and D551 M28W160BT100ZB6T as its separate 16-Mbit flash; the three D310/D311/D313 64-Mbit main flash chips are separate. UPP D100, UEM D190, SDRAM D312, Bluetooth N430 and GSM RF N601, codec, tuner, connectors and UI are inventoried with sheet references.

`ngage_board.v` now instantiates `ngage_upp.v`, `ngage_uem.v` and `ngage_adsp.v`. The MiSTer UPP instance contains the ARM and the existing UPP peripheral logic; an external-master mode preserves focused tests. Existing UEM and MDI behavior is unchanged but is **transaction-level**, not serialized physical CBUS/AMA signaling. `ngage_lrb2.v` and `ngage_mjoelner.v` expose pin-named digital boundaries and explicitly do not drive or implement radio behavior; they are instantiated disconnected and held in reset. No inferred Bluetooth/GSM responses were connected. Main-flash controllers and MiSTer SDRAM adapters still reside outside the board chip hierarchy. The main NOR controller now instantiates three separate `ngage_am29n643_state` logical die-state modules, but their physical chip-select mapping, complete per-chip interfaces and physical memory buses are not implemented.

`AGENTS.md` now requires an individual HDL module for each relevant physical chip, schematic-named interfaces where supported, Verilog-2001 for new HDL, explicit approximation notes and regression testing. The module split changes Verilator hierarchy; old CPU snapshots are incompatible and must remain untouched. Board, chip, reference, NOR/save, CPU and MiSTer top regressions passed; matched 20M-cycle shadow/exclusive runs after the full UPP/UEM/DSP split matched pre-split counters. The latter is not a full phone boot. No synthesis or hardware test was performed.

## 2026-11-06: MiSTer milestone 4 acceptance

Milestone 4 is complete for the scoped boot-critical board-model port and its directed acceptance tests. The IRQ/FIQ controller, timers, CBUS/UEM, NOS status, clock/boot latches, GPIO loopbacks, upload/scratch/ASIC regions and debug sinks are connected in HDL. A compact inventory from four retained firmware traces contains 132 device/address pairs; all are claimed by the board decoder with the late-boot configuration. This is an address-ownership check, not proof of all read/write semantics or all future addresses.

A new no-C++ test instantiates the actual `ngage_mister` CPU, board, flash controllers and address map with delayed test-memory responders. An ARM program fetches through the HDL flash path, writes and executes scratch and upload RAM, calls the Thumb ASIC stub, receives and acknowledges IRQ/FIQ, handles an invalid-register abort, and writes a success word through the SDRAM port. `tests/phone/mister_board_cpu/run.sh` passes. The responders are test models, not physical SDRAM/DDR or an FPGA fit test.

Timer and system-control accesses now reject unobserved values and uninitialized states using the staged profile’s observed rules; a C++/RTL fixture checks accepted and rejected cases. The 0x0c120074 write now requires the staged CBUS 0x8d prerequisite, and its 0x0c14d latches agree with both C++ references in the selected feature-on profile. IRQ source 7 and FIQ source 26 are exposed and board-level tested with injected pending signals; the top ties them low until the LCD DMA and SIM modules are implemented in milestones 6 and 5. No DMA transfer or SIM functionality is claimed.

The complete focused milestone 4 suite passes, including both C++ reference boards, timer and UEM edge comparisons, IRQ priority/masking, simultaneous acknowledgements, executable memories, stalled reads, bounded/invalid accesses, 132-address decoder inventory and HPS/PLL-stubbed top elaboration. Matched shadow and exclusive startup runs each reached the 20,000,000-cycle limit without a reported divergence; they did not reach the first modeled timer interrupt and are not a phone boot. The original milestone-0 reference hashes are preserved as `tests/phone/fixtures/source-hashes-milestone0.json`; `source-hashes.json` now records the two intentionally changed current simulator wrapper files.

Remaining project work is explicitly outside this milestone: diagnostic SIM/card integration (5); LCD DMA/framebuffer/video and held/released controls plus hardware diagnostics/trace export (6); full hardware-bound firmware comparison, FPGA fit/timing and MiSTer validation (7). The 64-entry sparse diagnostic store remains bounded and reports overflow; the inventoried traces do not prove an exhaustive upper bound. The CPU reset hold remains in the MiSTer top pending those integration gates. No full firmware boot, synthesis, real HPS handshake, or board test was performed.

## 2026-11-06: MDI stalled-read side effect

A directed MDI test now verifies that a stalled, uncommitted pointer read does not mark the pointer initialized, while the accepted read does. This covers a read-side effect across bus stalls alongside the LCD transport stall fixture. The MDI test passes.

## 2026-11-06: LCD transport and retained-trace inventory

A new Verilog-2001 LCD transport fixture compares accepted and rejected command sequences, status/readback data, header reset and stalled/uncommitted accesses against both C++ boards (`tests/phone/lcd_transport/run.sh`). Both pass. This validates the existing bus sink only; framebuffer, DMA and video are milestone 6 work and remain absent.

The selected retained 2B–4B, 4B–8B, power-key and no-ATR bus traces contain six distinct observed generic 0x0d register words, below the HDL sparse store’s 64-entry limit. The traces do not establish a complete address set or eliminate overflow on other boots. No retained logs or checkpoints were removed.

## 2026-11-06: cycle-by-cycle timer and UEM comparisons

Added a compact event fixture generated independently by each C++ board. It compares boot and periodic timer IRQs, unit-1 IRQ, unit-60 FIQ, register data, rearming, pending-source masking, and acknowledgement coinciding with expiry across two full periodic intervals. Fixed one-cycle arming errors in all four timers, incorrect boot one-shot status, periodic rearm masking, and acknowledgement timing. Both references pass; these results establish parity for the tested model cases, not physical timer accuracy. Run `tests/phone/timer_conformance/run.sh` inside `jotego/simulator:arm64`.

A separate Verilator/C++ comparison exercised the full 7,995,392-cycle UEM alarm, an alarm/acknowledgement collision and the 104,000,000-cycle UEM 1 Hz event against both C++ models; both pass (`tests/phone/cbus_timing/run.sh`). These are focused device tests, not full-phone boots. ARM tests also execute code from boot scratch and upload RAM, and call the Thumb ASIC ROM stub, in shadow and exclusive modes.

Added the observed write-only `0x0c120074 = 3` system-control hypothesis and five `0x0c14d000..10` masked latches after that write. Unlike the C++ probe, RTL does not additionally enforce the C++ ICU/CBUS configuration prerequisites for the 0x74 write; its physical behavior remains unknown. LCD DMA start is still rejected and milestone 4 remains incomplete.

## 2026-11-06: NOS and diagnostic register comparisons

Extended the integrated ARM/C++/HDL fixture to 24 transactions, including 0x0c004xxx NOS storage and two distinct 0x0d diagnostic addresses; shadow and exclusive runs pass and verify no aliasing. The adapter test now checks that upload RAM survives a phone reset and is cleared by a cold reset. Generic GPIO now rejects unsupported byte-enable combinations without modifying RAM, as the software model does. Dedicated tests and the rebuilt CPU-level comparisons pass. These changes do not implement the LCD DMA engine or establish full firmware-device parity.

## 2026-11-06: HDL ownership, interrupt timing and bounded firmware comparison

The HDL-board CPU simulator now accepts `hdl-exclusive`: claimed peripherals are accessed only in RTL and IRQ/FIQ come from RTL; unclaimed peripheral windows stop visibly instead of falling back. External flash/RAM remain in the C++ model and are counted by device in the JSON result, so this is not an all-HDL phone/memory validation. A separate shadow mode still compares C++ and RTL. Both modes pass an 18-transaction ARM fixture including CBUS, GPIO, epbus and DMA configuration latches under stalls. A second ARM program receives and acknowledges HDL IRQ and FIQ; negative tests confirm missing peripheral and unimplemented LCD DMA start stop. Trace writes are exported in `hdl-board-trace.tsv`, bounded to 4096 records with a dropped count in JSON. This export is simulation-only, not an HPS hardware buffer.

Ported missing 0x0c120014/018/034/038 clock latches, suppressing the overlapping GPIO backing-RAM write and ICU/DMA-configuration and epbus registers in Verilog-2001. LCD DMA start is deliberately rejected until the engine exists; plain DMA setup registers are just the staged C++ latch hypothesis. The first short firmware attempt exposed speculative instruction fetches into unwritten scratch being treated as fatal; the harness now returns fetch faults to the CPU instead. MDI/NOS same-edge handling now follows the current C++ runner's access-before-tick order: the tick sees a just-written ring pointer and a new event wins over a simultaneous W1C. Focused cases match both C++ board references.

From cycle 0, shadow and exclusive modes each reached the bounded **20,000,000-cycle timeout**, with 1,016 HDL-owned transactions and 2,770,023 retired instructions; no modeled timer interrupt had occurred, so this is not a timer-interrupt or boot-completion result. Test command: `python3 scratch/current-boot/build.py --hdl-board`, then `sh tests/phone/board_shadow/firmware_smoke.sh shadow` and `... exclusive`. Results/logs are in `build/sim/unit-hdl-shadow-20000000/` and `build/sim/unit-hdl-exclusive-20000000/`. No old checkpoints were restored, no screen was produced, and no synthesis/hardware test was run.

Milestone 4 remains incomplete: more reached-device/event parity and reset/stall coverage, an actual LCD DMA/IRQ source, complete keypad/serial and additional hardware blocks, bounded hardware trace export, removal of C++ memory dependencies in the hardware-bound integration, and later platform validation. The current reset hold remains in place. See `docs/mister-board-bringup.md`.

## 2026-11-06: CPU/HDL board shadow integration

`scratch/current-boot/build.py --hdl-board` now builds a separate simulator with the ARM and `ngage_board`, without replacing the normal binary. Board cold scrub finishes before the CPU is released. The existing harness runs C++ as a shadow oracle, compares each HDL-claimed read, commits the HDL only for an accepted claimed request, and waits for RAM-backed devices. It still uses C++ IRQ/FIQ and deliberately updates the C++ shadow; it is not the exclusive-owner, hardware-bound profile and cannot establish fallback-free operation. Old CPU checkpoints are incompatible with this separate build.

A small ARM diagnostic compares 14 CBUS and GPIO bus transfers, including wait states and the routed loopback. It found a missing staged `0x0c14b000` version bit; adding that observed hypothesis resolved the divergence. Build with `python3 scratch/current-boot/build.py --hdl-board`, then run `sh tests/phone/board_shadow/run.sh`. Both passed. No firmware simulation or synthesis was run. Next integrate a true exclusive-ownership mode, resolve interrupt/timebase ownership and compare further real device transactions before claiming milestone 4 complete.

## 2026-11-06: MiSTer milestone 4 continued — MDI and GPIO

Ported staged MDI ring consumption and delayed announcement into Verilog-2001, connecting its events to NOS status and ICU routing without inventing a DSP response. Directed MDI tests pass, as do timing/status fixtures against both C++ board references. Ported staged GPIO set/clear and UEM-routed loopbacks; focused and integrated interrupt/GPIO tests pass. UEM alarm and 1 Hz counters now preserve the staged global-cycle phase rather than restarting when armed. Added a Verilog-2001 simulation bus adapter and a test for exclusive HDL ownership, invalid transactions and fallback. It is not yet connected to the C++ firmware harness.

Milestone 4 remains incomplete: integrate the adapter and trace export; verify all reached devices, event ordering and stall behavior against C++, and finish missing ICU/DMA, keypad/serial and other stateful peripheral cases. MDI event pulse delivery may be one cycle later than the C++ model and requires explicit comparison. SIM FIQ and DMA depend on their actual modules. The MiSTer CPU is still held in reset; no firmware boot, FPGA synthesis or board test was performed. See `docs/mister-board-bringup.md`.

## 2026-11-05: MiSTer board milestone 4 in progress

Ported and connected initial staged-model ICU, timers, NOS counter/interrupt registers, selected UEM/CBUS sequencing, boot latches and executable scratch. CPU IRQ/FIQ now come from the board. A small real ARM program receives and acknowledges both IRQ and FIQ and reaches a data-abort handler for an invalid board read. Corrected former low-address aliasing by splitting upload, NOS and GPIO banks and initializing them before CPU release; the 0x0d diagnostic store now has full-address tags and an explicit 64-entry limit. Trace writes produce testable events but have no hardware buffer/export yet.

Focused RTL tests pass for the above, including reset/commit behavior, masking, FIQ source 3, timer wrap, CBUS RTC/ADC cases checked against both C++ boards, bank separation and trace widths. The current C++ model has two distinct NOS counter rates (3174 and 104000 clocks), which are now separate in RTL. Alarm and periodic UEM interrupt phases differ from the C++ model and remain unverified hypotheses. Top-level structural elaboration passes with HPS/PLL stubs. No full firmware run, synthesis or hardware test was performed; the MiSTer CPU remains held in reset.

Milestone 4 is not finished: DSP/MDI shared RAM/ring and IRQ behavior, other stateful peripheral registers, GPIO/keypad quirks, DMA, SIM FIQ, complete event-by-event C++ parity, trace buffering/export, an HDL phone wrapper and resource/timing validation remain. See `docs/mister-board-bringup.md` for exact limitations and next steps.

## 2026-11-05: MiSTer flash and save implementation, simulated validation

Connected C: and code/PMM flash state machines to the core's DDR transport, including two-lane array descrambling, per-chip/bank status, observed C: program/erase commands, and dirty-sector events. C: intentionally matches the software model's 0-to-1 program behavior; PMM uses bitwise AND with its seed, a documented discrepancy requiring further evidence. Code-flash program operations outside PMM return errors. Both C++ board references pass matching C: command cases; RTL flash tests, 1,548 descrambler vectors, and the stock MD5 through RTL pass.

Connected a simulated MiSTer virtual-disk save manager: separately prepared 4 MiB C:/64 KiB PMM working image, size/read-only/header CRC/profile/firmware-header validation, restore, dirty-sector snapshot and flush, overlap rescan, reset deferral, and safe failure on timeout/incomplete reads/media change. The loader recognizes the audited core/extension using checked CRC-32 values; it does not compute SHA-256 in hardware, despite comparing the save header to the corresponding compiled-in SHA values. A full-sized simulated disk test restored, flushed boundary sectors, and reloaded all data; a second end-to-end test programmed C: and PMM via the actual flash/DDR path, flushed, reloaded, and tested concurrent writes and failures. All directed tests and top-level elaboration with HPS/PLL stubs pass.

No MiSTer hardware, real Main HPS disk handshake, synthesis, FPGA fit/timing or power-cycle test was performed; the CPU remains held in reset. There is no write journal, power-loss guarantee, or automatic recovery/export of unsaved volatile DDR after failed I/O. The PLL metadata mismatch and DDR reservation remain unresolved. Do not treat simulated HPS ACK as proof of durable media writes. Save-image creation, OSD flow, LED signals, tests and exact limitations are in `docs/mister-flash-save.md`.

## 2026-11-05: MiSTer SDRAM milestone implementation and tests

Connected `rtl/ngage_sdram_arbiter.v` and `rtl/ngage_sdram_adapter.v` to the MiSTer top. The CPU/DMA arbiter latches full requests, reserves RAM across CPU SWP lock, and treats an asserted Wishbone request after ACK as a new transfer. A first design waiting for the request to drop deadlocked the real associative CPU on back-to-back reads; the integrated ARM test exposed this and the arbitration was corrected. DMA is currently tied off until the LCD port exists. The adapter captures each 32-bit request, serializes two 16-bit accesses, waits for registered controller `rdy`, drains interrupted responses, and holds the complete word across arbitration. It cold-clears 16 MiB before CPU release, preserves RAM over phone resets, and schedules nine controller refreshes every 6,800 nominal 104 MHz cycles. The earlier `0x0bxxxxxx` alias is rejected by the existing ROM/RAM map.

Actual `jtframe_sdram64` + local Micron memory model tests pass at a nominal 104 MHz/-2404 ps test clock: read `ack` led valid `rdy` by about 29 ns, and tests cover all byte masks, 8 MiB bank transition, last 16 MiB word, latched request changes, single ACK after release, reset before and during an outstanding read, repeated traffic with refresh, and CPU/DMA lock. An ideal responder test verified all 8,388,608 halfword addresses in the full cold scrub. Seven associative ARM cases (load widths, MMU FCSE, write-through cache, drain, SWP, cached SWP/IRQ and external abort) passed through the actual new adapter/arbiter with idealized halfword responses at wait settings 0/3/11; the existing unmodified memory-harness width test also passed at 0/3. Test-only HPS/PLL stub top elaboration passed.

Controller high-frequency startup wait changed from 10,000 to 11,000 cycles to exceed 100 us at 104 MHz. The instantiated PLL RTL still requests two 104 MHz clocks, but `rtl/pll.qip` metadata still describes one 20 MHz clock; this cannot be reconciled or validated by the available simulator and must be resolved with the compatible installed Quartus before PLL regeneration/synthesis. Real SDRAM capacity, physical clock/IO timing, retention and FPGA fit remain unverified; the Micron model does not test full refresh retention. The CPU remains deliberately held in reset pending later flash/peripheral integration. No long phone simulation, Quartus fetch, synthesis or hardware boot was performed. See `docs/mister-sdram.md` for reproducible commands, model provenance and the remaining hardware gates.

## 2026-11-05: MiSTer milestones 0 and 1 transport implementation

Milestone 0 reference: `tests/phone/fixtures/` captures hashes for 18 current/staged/keypad sources, both actual board models' deterministic flash, negative-access and timer/IRQ transaction fixtures, explicit erased/seeded/no-ATR profiles, and the staged runner's extracted static options and dynamic bindings. `verify_digests.py` passes the selected factory core's stock descrambled MD5 and the selected assembled extension descriptor. PMM in the matched erased profile is explicit; the seed is a separate profile. These are software-model reference fixtures, not proof of physical hardware behavior.

Milestone 1: `Template.sv` now connects the v1 bundle loader through `ngage_ddr_arbiter` and `ngage_ddr_adapter` to the 64-bit MiSTer DDR port, with `ngage_rom_map` backing offsets. OSD selects one NGB bundle; the nonfunctional Save action was removed. The phone CPU is intentionally held in reset unconditionally until SDRAM, flash command and peripheral integration in later milestones. Candidate DDR base 0x30000000 remains unverified against installed Main; do not deploy this build to hardware until reservation is checked. Flash writes, real persistence, video, controls and board parity remain later work.

`tests/phone/mister_transport/run.sh` passes map, all byte masks/halves, BUSY, delayed response, stale read drain, SWP-style arbiter reservation, response ownership, corrupt/short/duplicate/hole/oversized downloads, partial final word, and small end-to-end fake-DDR tests. Full selected 25,165,952-byte bundle loaded over 12,582,912 accepted writes, then all section words were read through CPU-side arbiter and adapter and compared byte-for-byte; guard stayed intact (132,120,640 simulated transport cycles). `run-full.sh` reproduces this with a temporary bundle under scratch and deletes only its own output. Top-level Verilator structural elaboration passes with HPS/PLL test stubs; real `hps_io.sv` elaboration fails under the available Verilator due to existing PS2 generate-scope assignments, so HPS behavior and timing are not validated by that check. No Quartus, synthesis, on-board boot or long phone simulation was run.

The next milestone is SDRAM controller data-valid/refresh/reset work, followed by flash command and save implementation. Do not remove the CPU hold until their stated integration gates pass. Keep the real HPS handshake, actual DDR reservation, CDC, synthesis/fit/timing and durable storage as explicit hardware validation items.

## 2026-11-05: loader and DDR adapter exercised together

`tests/phone/mister_transport/integrated_tb.sv` connects the loader to the DDR adapter and a delayed fake 64-bit DDR memory. A small four-section bundle passes byte-for-byte readback at the four allocated base offsets under BUSY stalls; its malformed, short and duplicate-address cases also pass. This is a bounded unit test with 4-byte sections, not a real-size image readback or MiSTer/HPS test. Arbitration, top-level integration, full-image readback and the remaining milestone 0 reference fixtures are still outstanding. Run all focused transport tests in `jotego/simulator:arm64` using `tests/phone/mister_transport/run.sh`.

## 2026-11-05: MiSTer milestones 0–1 started; integration remains

Added `tools/prepare_mister_images.py`: checks exact audited sizes and SHA-256 for core, extension and 11B C:, plus seeded PMM when requested; `diagnostic-erased-pmm` explicitly creates an FF PMM and `diagnostic-seeded-pmm` uses the separately audited seed. It creates a new provisional v1 bundle and JSON manifest without overwriting inputs. A full erased-profile output was read back and each section CRC32/SHA-256 verified; the temporary bundle was removed. `tests/phone/fixtures/` records 18 board/reference source hashes and named profiles. The existing independent stock digest script passed on the service-derived linear input; this does not yet verify FPGA read-side descrambling or the extension on HDL. Direct board transaction fixtures and complete resolved launch options remain to do.

Added standalone `rtl/ngage_ddr_adapter.sv` and `rtl/ngage_loader.sv`, and included them with the existing map/lanes modules in `files.qip`. Directed container tests pass for all 32 lane/mask combinations, busy holding, delayed read, draining a pre-reset read, address boundaries, valid small bundle, truncated input, duplicate address, corrupt payload CRC and invalid section offset; existing flash PMM-bank test passed. The loader and adapter are NOT connected to each other, `Template.sv`, a real/fake DDR memory, or the CPU; there is no arbiter or readback verification yet. No loader integration, SDRAM initialization gate, hardware boot, synthesis, or firmware run has been performed. The current top's original unsafe loader is unchanged; do not interpret `files.qip` inclusion as a completed port.

Next: implement a combined loader/adapter/fake-DDR test including delayed acceptance, readback, interrupted/oversized downloads, exact bounds and reset; add and test arbitration and integrate the top with CPU held until validated. Complete milestone 0 board transaction/tick/IRQ fixtures and runtime option capture; verify image digest on selected derived inputs. Review HPS download start/end and real DDR base before hardware use. Preserve all checkpoint pairs and firmware images.

## 2026-11-05: MiSTer migration implementation plan audited

Planning-only repository audit produced [mister-implementation-plan.md](mister-implementation-plan.md): exact image hashes/origins, current/staged/live-keypad model differences, nonoverlapping DDR allocation, loader/save design, device migration and directed-test gates through first hardware boot. Confirmed the existing DDR/map failures plus SDRAM early-ack/data-valid and missing refresh risks, GPIO low-address storage aliases, missing reset initialization, disconnected descrambler/interrupt/video/input and stub C: upload. Latest matched SIM runner defaults omit `pmm-image` despite provenance hashing the seed; PMM seed bytes are external to host checkpoints. Resolve the chosen seeded-versus-erased profile explicitly before comparing cold boots. THC NOS/IAT files are also hashed but unused by the current command; factory service bytes with read-side descrambling provide NOS. Recommended first implementation: tested 64-bit DDR adapter and nonoverlapping loader with CPU held. No RTL, firmware, checkpoint or screen changed; no simulation, synthesis or Quartus download performed. Diagnostic SIM and shared present/no-ATR ADSP assertion remain unresolved.

## 2026-11-05: GSS lifecycle replay completed

`simif-gss-lifecycle` reached 1.2B from `idle-c939`, preserving its 1B checkpoint pair. Generic lifecycle dispatch at 0x514bb682 ran 44 times from 945,932,265 to 955,691,853; SIM event producer 0x515107ac ran at 962,933,179. Selected probes saw no GSS c004 initializer, c012 activation handler, task-start batch, SMS task entry, ATKinf gate, or SIM queue drain. This does not exclude initialization before 939.8M. A short full trace `simif-gss-group-first` shows the first lifecycle dispatch sends c012 to object 0x80009d10, not the separately identified GSS object 0x800092c8; investigate the object list and remaining dispatches before drawing conclusions. Neither the synthetic SIM nor an ADSP response has been validated.

## 2026-11-05: early GSS activation probe completed

`simif-gss-early` completed at 1B from the fresh present-card 176.8M checkpoint and preserved its 1B pair. It observed SIM event-0x1280 producer at 962,933,179 but no selected GSS c012 activation handler, GSS task-start batch, SMS task entry, ATKinf gate or SIM queue drain/pop from 176.8M–1B. The previously recorded 1B–4B GSS probes were also silent; this is selected-PC evidence only, not proof of why activation has not occurred. `simif-gss-lifecycle` now traces the GSS c004 initializer, c012 activation and generic lifecycle dispatch from preserved `idle-c939` to 1.2B with live capture, to determine whether GSS registers or receives group events; preserve its billion-cycle checkpoints. In parallel, the ADSP assertion has been confirmed in both diagnostic card-present and no-ATR lineages, so do not assume the SIM alone is the cause.

## 2026-11-05: tracing earlier GSS/SIM task startup

`simif-gss-early` is replaying the validated fresh-card 176.8M CPU/host pair to 1B with selected PCs for GSS event 0xc012 handler, the GSS task-start batch, SMS task entry, ATKinf gate, SIM queue drain/pop and event 0x1280. Prior negative probes cover 1B–4B but not this earlier interval. The run preserves its 1B CPU/host pair and live captures under `build/sim/screens/boot-v15-simif-gss-early-live/`; do not modify its hashed inputs. Compare its actual hits and their ordering before attributing the pending SIM notification to an unstarted task.

## 2026-11-05: last synthetic SIM file is optional EF-OPL

The [3GPP SIM-ME specification TS 51.011 v4.3.0 §10.3.42](https://www.etsi.org/deliver/etsi_ts/151000_151099/151011/04.03.00_60/ts_151011v040300p.pdf) identifies the synthetic card's last selected file 0x6fc6 as optional EF-OPL and requires its absence when EF-PNN is absent. The current synthetic profile also lacks EF-PNN (0x6fc5), so its file-not-found response is consistent with that particular standard condition. This does not validate the complete card/service-table profile or establish the cause of the pending SIM notification. See `docs/sim-presence.md`; continue investigating actual completion and the separate ADSP response path rather than returning generic success for optional files.

## 2026-11-05: no-ATR ADSP request and thread scheduling

`simif-noatr-adsp-pre`, `simif-noatr-adsp-start` and `simif-noatr-adsp-scheduling` reproduced the no-ATR lead-up from its 9B/9.5B checkpoints; `idle-c9500.cpu` and `.host` are preserved. The same ADSP self-test starts at 9,525,703,003, sends its request to object 0x3c/task 0x2c and the NOSDRIVER mailbox delivers it to the adspserver Main thread 0x8041e29c at 9,525,816,373. That thread's first selected scheduler hits after the request are at 9,533,893,113. `simif-noatr-adsp-wake` shows it loading 50,000 into r0 at 0x510ed37e and calling the same blocking function observed in the present-card lineage; the unrelated 0x5902 reaches the waiting test at about 9,534,511,351. No selected NOS send-handler call from adspserver appeared between request and 9.534B; the short window and selected probes do not prove absence of all possible replies. This reproduces the same software-level ordering under diagnostic no-ATR, but neither the exact time unit of the blocking call nor the missing ADSP response cause is established. Continue tracing its wait/callback and model timing; do not treat 50,000 as verified microseconds or synthesize a response.

## 2026-11-05: no-ATR boot hit the same ADSP assertion

`simif-noatr-faulttrace` reproduced the 9,534,596,302-cycle halt from the no-ATR 9B checkpoint and preserved `idle-c9534.cpu` and `.host`. Its full trace identifies the same `St_product.c` line 0xdf2 ADSP self-test assertion as both present-card runs: dispatcher key 0x5902 arrives while the test expects message ID 0x8b, but the received ID is 0x02. This demonstrates that the diagnostic no-ATR boot can hit the same failure without synthetic ATR injection; it weakens a SIM-only explanation but does not prove the physical phone would behave similarly. Timing differs (9.535B no-ATR versus 7.226B and 7.843B present-card variants). Continue tracing the shared adspserver response path, BTTestServer message routing, and modeled timing; do not patch out the assertion or fabricate a self-test response.

## 2026-11-05: no-ATR boot stopped at 9.535B

`simif-matched-noatr-12b` stopped at cycle 9,534,596,302 in the generic masked-interrupt kernel loop 0x50324294; it preserved 9B CPU/host and live capture at `build/sim/screens/boot-v15-simif-matched-noatr-12b-live/`. The stop address alone does not identify the underlying failure or show whether it matches the earlier ADSP assertion. `simif-noatr-faulttrace` is now replaying from the saved 9B pair with `simif-no-atr` explicitly reapplied, full instruction/bus tracing at 9.5339B–9.534597B, and a 9.534B CPU/host savepoint. Compare the actual assertion with the 7.226B present-card result; no-ATR remains a diagnostic model, not proof of physical no-card behavior.

## 2026-11-05: no-ATR comparison passed 8B

`simif-matched-noatr-8b` completed its 8B-cycle budget with no reported firmware stop and saved every 2B–8B CPU/host checkpoint pair. It passed both present-card test halt cycles (7.226B and 7.843B), but this does not prove the card caused those failures: boot paths and timing differed, and the no-ATR option is not a verified physical no-card model. Its latest live PNG, `build/sim/screens/boot-v15-simif-matched-noatr-8b-live/frame0012_cycle7295060050.png`, visually shows a white screen with a small blue icon; intermediate frames are retained. The selected probes in this long run did not include the ADSP self-test entry, so absence of that self-test cannot be inferred. Continued the same no-ATR lineage from its 8B CPU/host pair to 12B as `simif-matched-noatr-12b`, retaining every billion-cycle checkpoint and live screens at `build/sim/screens/boot-v15-simif-matched-noatr-12b-live/`. Inspect its outcome, compare UI and failure traces, and continue investigating the present-card response-routing path.

## 2026-11-05: matched SIM comparison shows different firmware paths

`simif-matched-present` and `simif-matched-noatr` both completed at 1.2B from the same 176.8M CPU/host pair with the same rebuilt simulator and inputs except `simif-no-atr`; both saved their 1B checkpoint pairs. The present run reproduced internal SIM event 0x1280 at cycle 962,933,179, exactly matching the earlier present-card trace. The no-ATR run instead observed SIM_Server storing state 5 at cycle 1,140,954,512 and parameter 0x74; no matching 0x1280 probe fired through 1.2B. At the 1B checkpoints, page-table-translated raw SDRAM shows the present notification list count 1 versus no-ATR count 0, while both show MTC state 3; these reads do not overlay dirty CPU cache. The state-5 write is an actual instruction trace but the no-ATR switch is a diagnostic, not a validated physical no-card model. The matching present-card trace and unchanged RTL/host format support this checkpoint comparison, within those limits.

Continued the no-ATR lineage from its 1B pair to 8B as `simif-matched-noatr-8b` with `simif-no-atr` explicitly reapplied, live screens under `build/sim/screens/boot-v15-simif-matched-noatr-8b-live/`, and all billion-cycle pairs preserved. Compare its ADSP self-test and 0x5902 behavior against the earlier present-card run; do not infer causality before it reaches that interval.

## 2026-11-05: matched SIM/no-ATR comparison started

Added an opt-in `simif-no-atr` diagnostic to the staged SIMIF board: the default card-present model is unchanged, while this option disables the synthetic ATR injection and returns zero on a direct FIFO read. This is a controlled no-ATR experiment, not a validated physical no-card model. The runtime option does not alter the serialized host layout and must be applied from a pre-card checkpoint; `run.py` now records all extra arguments in provenance. The directed `no_atr_board_test.cpp` passes against the actual staged board and confirms present/default versus no-ATR status/FIFO behavior. Rebuilt with `jotego/simulator:arm64` after all prior runs completed.

Started matched `simif-matched-present` and `simif-matched-noatr` from the same saved 176.8M pre-card CPU/host pair, with identical board, firmware, C: image and input settings except `simif-no-atr`; each targets 1.2B, preserves its 1B pair and captures live frames in its own `boot-v15-<name>-live` screen directory. Check both results and verify provenance/input hashes before comparing SIM events and state. The checkpoint was created by the previous build with unchanged RTL and host layout, but compatibility and pre-card state still require observational verification. This comparison does not bypass the ADSP assertion or establish physical SIM detection behavior.

## 2026-11-05: power-key comparison hit the same ADSP assertion

`simif-powerkey-faulttrace` reproduced the 7,843,031,842-cycle halt from the power-key run's 7B checkpoint, preserving `idle-c7842.cpu` and `.host`. Full trace confirms incoming dispatcher key 0x5902 and the identical `St_product.c` line 0xdf2 assertion: the ADSP self-test expected message ID 0x8b and read 0x02 instead. Thus changing only modeled power-status input 1→2 changed the stop timing but did not eliminate this observed failure. It also changed the raw NOS startup reason but left MTC state 3 at the 2B checkpoint; do not infer that the two inputs fully match real hardware or that the SIM caused this assertion. Continue tracing adspserver's response path and the waiting self-test's message routing, and use the preserved 7B/7.842B pairs for focused comparisons. No timeout or assertion was bypassed.

## 2026-11-05: power-key comparison stopped at 7.843B

`simif-powerkey-8b` passed the input-1 fresh-card run's 7,225,961,838-cycle stop but stopped at 7,843,031,842 with the same masked-interrupt kernel halt address 0x50324294. This address is a generic fatal handler, so the underlying cause has not yet been established. The input-2 run preserved its 3B–7B CPU/host checkpoint pairs and live screens under `build/sim/screens/boot-v15-simif-powerkey-8b-live/`; its last reported frame was at 6,691,757,677. `simif-powerkey-faulttrace` is running from its 7B pair with the same power-key input 2, a full 7.8424B–7.843032B window and a 7.842B CPU/host savepoint. Compare its actual fault source with the input-1 ADSP self-test assertion before choosing any fix. The earlier 1B/2B raw snapshots found MTC state 3 and one pending SIM notification under both inputs, without dirty-cache overlay.

## 2026-11-05: power-key comparison continuing past 4B

`simif-powerkey-8b` is running from the preserved 2B pair and has saved the 3B and 4B CPU/host checkpoint pairs. Its latest live frame is `build/sim/screens/boot-v15-simif-powerkey-8b-live/frame0001_cycle2926027550.png`. The 2B comparison found power-status input 2 changed the kernel startup value and NOS reason but not the raw MTC state 3 or pending SIM notification; wait for the 7.226B ADSP/BT failure point before interpreting the full boot. Keep simulator sources, C: image and checkpoint pairs unchanged while it runs. Earlier diagnostics established that the original fresh-card boot's failure was an ADSP self-test assertion after a BTTestServer 0x5902 message was routed into the pending response handler; causation and a hardware-faithful fix are still under investigation.

## 2026-11-05: power-key input comparison reached 2B

`simif-powerkey-2b` completed at 2B without a reported stop, preserving 1B and 2B checkpoint pairs. Unlike the original input-1 run, the modeled power-key input 2 made ecust cache startup value 0 at 919,012,369 and raw NOS startup reason 1 at 1B/2B instead of 3. However, raw MTC state is still 3 and the SIM notification list count is still 1 at 2B (no dirty-cache overlay). This matches the firmware's previously observed conversion of reason 1 to state 3; it does not demonstrate that the SIM queue is released. The controlled input changed only the UEM power-status setting; its physical meaning remains a hypothesis. Live frame `build/sim/screens/boot-v15-simif-powerkey-2b-live/frame0002_cycle971398369.png` was produced. Continued from its 2B pair to 8B as `simif-powerkey-8b`, preserving the same UEM input, live frames under `build/sim/screens/boot-v15-simif-powerkey-8b-live/`, and all billion-cycle CPU/host pairs. Compare the ADSP/BT failure and screen progression at the original 7.226B point; do not assume that result.

## 2026-11-05: controlled power-key boot running

`simif-powerkey-2b` starts from reset using the same staged diagnostic-SIM board and C: image as the fresh-card lineage, changing the modeled UEM power-status input from 1 to 2. Historical firmware analysis identifies bit 1 as the power-key boot hypothesis, but this must be checked in the current run; it does not alter the RTC model, force a startup reason, suppress an alarm, or prove actual hardware semantics. The run preserves every billion-cycle CPU/host pair, logs selected startup/SIM/self-test sites, and captures live screens under `build/sim/screens/boot-v15-simif-powerkey-2b-live/`. Compare the actual ecust/MTC startup state, SIM notification, and screens against the original power-status=1 run after completion. This is a controlled input experiment, not a default hardware fix.

## 2026-11-05: self-test waiting window and cross-delivery

The full `simif-adsp-previous-event` trace shows the ADSP self-test sends its 0x0e/0x2b request, arms timeout value 0x0bb8, and sets test state 1. On the later 0x5902 arrival, `simif-adsp-msg-origin` shows the generic handler taking its default route because 0x8000c0fd is 0, saving the unrelated message as the self-test response and triggering state 1's 0x8b assertion. The completed `simif-adsp-client-path` and `simif-adsp-client-block` traces show adspserver enters a request-processing path and calls a 50,000-argument blocking function before the 0x5902 send; the resumed thread had not made a selected NOS send call during the observed interval. This is an observed cross-delivery and waiting-order problem, not evidence by itself that Bluetooth is incorrectly emulated or that the timeout value is wrong. Next identify the adspserver blocking function and callback/response path, and compare against the known firmware and platform timing before implementing a change. The SIM card remains diagnostic and not yet established as serving.

## 2026-11-05: adspserver receives the self-test request before BT message

`simif-adsp-channel-activity` completed through 7.2259B with compact selected-PC logs. Between the self-test request and BTTestServer's 0x5902 send, the observed NOS send-handler entries were associated by the last scheduler record with other threads (EtelServer, MediaServerStub and BTTestServer); none was associated with the adspserver Main thread. `simif-adspserver-wake` and `simif-adspserver-later` traced that thread after delivery: it first called a function with 50,000 as argument, and later executed user code with request bytes 0x0e/0x2b and sender 0x82 visible in saved registers. This supports the request reaching adspserver and remaining unanswered in this observed interval, but selected-PC coverage is not proof that no alternative completion was sent. Continue following its 0x0e/0x2b branch through the adsp library and hardware interface, compare against real ADSP documentation, and retain the separate finding that unrelated BTTestServer 0x5902 was accepted by the waiting test.

## 2026-11-05: 0x5902 sender traced to BTTestServer thread

In the complete `simif-adsp-msg-origin` trace, scheduler global 0x80006744 was last set to thread 0x804124d4 at cycle 7,225,773,347; no later scheduler write to that global appears before the user-mode construction of the `0x5902` message at 7,225,836,797. The 7.225B checkpoint's translated kernel objects identify that thread as `Main` in process `BTTestServer`, executable `Z:\System\Programs\BTTestServer.exe`. This is strong trace-and-checkpoint evidence that the conflicting message originated in BTTestServer, not proof that the Bluetooth model or SIM caused the error. The earlier ADSP self-test request was delivered to adspserver; while it was awaiting 0x8b, generic NOS dispatcher 0x51591810 passed the BTTestServer message to its shared response pointer. Next trace how each client is registered/routed and whether response correlation or a missing ADSP completion allows the cross-delivery; do not block BTTestServer or fabricate a response.

## 2026-11-05: self-test request recipient is adspserver

In `simif-adsp-delivery`, NOSDRIVER mailbox delivery of the `0e 2b` request uses thread object 0x8041e2a0 (trace at 7,209,826,674). Page-table-translated 7.225B host checkpoint links that thread to process object 0x8041e090; the process name and executable path there are `adspserver` and `Z:\System\programs\adspserver.exe`, with thread name `Main`. This identifies the observed recipient of the self-test request, subject to normal checkpoint/cache caveats; it does not establish that adspserver produced the later 0x5902 message. Trace the receiving thread and its outgoing NOS messages to identify the origin and expected 0x8b response; do not invent a response.

## 2026-11-05: ADSP test request delivered through NOS/Symbian bridge

`simif-adsp-delivery` completed its 7.2097B–7.2102B full trace. The state-0 self-test sends its `0e 2b ...` payload to object 0x3c; ROM table 0x516f49e0 maps object 0x3c to NOS task 0x2c. The trace records that payload enqueued at 7,209,754,678 and dequeued at 7,209,800,203; it passes through 0x515a05f2/0x515a0600 into a bridge queue and then 0x514a0e40/0x514a0b34, consistent with the documented NOSDRIVER/Symbian mailbox. The task descriptor's wrapper string says `Idle exec'd`, but the live dequeue proves the self-test message was handled by other code; do not infer that it was discarded just from the wrapper. Next identify the Symbian process/channel receiving object 0x3c and where it should generate response 0x8b, and trace the unrelated 0x5902 client and shared response handler. No proven DSP mailbox transfer or SIM causal link has yet been established.

## 2026-11-05: self-test request precedes unrelated response

`simif-adsp-previous-event` showed the earlier invocation at 7,209,728,059 in self-test state 0. Firmware builds an 8-byte request beginning `0e 2b`, sends internal event 0x82 and sets its self-test state to 1; its state-1 path expects response message ID 0x8b. At 7,209,754,048 the send path enqueues the request for NOS task 0x2c (0x514a77f8), whose descriptor points to wrapper 0x5151c9c8. At 7.2258B the generic 0x51591810 dispatcher instead passes a 0x5902 message into the shared response pointer while the test is waiting; the next test invocation asserts. The `simif-adsp-task-events` replay saw no selected 0x5151ca40 handler hit between 7.209B and 7.225B; it does not establish that the task did not consume the request. Need identify the generic receiver invoked by task 0x2c, trace handling/response of `0e 2b`, and explain why a 0x5902 message resumes the waiting test. Do not fabricate an 0x8b response or attribute this to SIM or RTC without evidence.

## 2026-11-05: self-test ran before the fatal message

`simif-adsp-pre-fresh` and `simif-adsp-pre-baseline` both reached 7.225B. The fresh-card replay hit the ADSP self-test handler 0x516a6218 at cycle 7,209,728,059 and several dispatcher/shared-response probes earlier; none of the selected sites appeared in that interval of the historical cardless checkpoint replay. Different boot history and board profile prevent attributing this timing difference to SIM presence. `simif-adsp-previous-event` is tracing every instruction around that earlier self-test invocation from the fresh 7B checkpoint and will preserve `idle-c7209.cpu` and `.host`, to determine its state and expected response before the later 0x5902 message.

## 2026-11-05: pre-failure dispatcher comparison running

Launched `simif-adsp-pre-fresh` and `simif-adsp-pre-baseline`, each probing the self-test and dispatcher paths from the respective fresh-card and historical cardless 7B checkpoints to 7.225B. The older baseline uses a different boot lineage and the staged present-card board after restore, so this is diagnostic rather than a controlled no-card comparison. Inspect both outcomes and selected hits, then identify the pending self-test request and why 0x5902 is accepted. Both runs use the unchanged build and original checkpoint pairs.

## 2026-11-05: ADSP assertion received resource 0x59 / message 0x02

`simif-adsp-msg-origin` traced 7.225B–7.2259B from `idle-c7225`. The failing object at 0x80026930 is routed with key 0x5902: dispatcher 0x514bb030 reads message byte 0x02, handler 0x51591810 subsequently stores its payload pointer 0x80026938 in shared 0x8000c104, and its continuation leads the self-test to assert that byte should be 0x8b. A prior byte-copy line logs a post-incremented destination register, so its displayed 0x80026939/0x08 is not evidence the byte later changed: the following post-increment store places 0x02 at that address. This establishes an unexpected message reaching a self-test response path; its producer, expected filtering, and whether DSP/model/firmware scheduling is responsible remain unproven. Continue by tracing the self-test's pending request and registration from before this message, and compare its dispatcher with the cardless boot. No assertion, messages, or firmware were patched.

## 2026-11-05: 7.226B stop is an ADSP self-test assertion

`simif-fresh-faulttrace` reproduced the stop from the fresh-card 7B checkpoint and saved `idle-c7225.cpu` and `.host`. Full instruction trace shows NOS self-test code 0x516a6286 reading message ID 0x02, comparing it with 0x8b, then calling its fatal assertion handler. The firmware's own assertion text is `pResp_adsp->message_id == ST_ADSP_RUN_RESP`, in `../../ENOS/CMT_SW/CONFIG/St_product.c`, line 0xdf2 (3570). The following masked-interrupt loop at 0x50324294 is the fatal handler. The trace alone does not establish why message 0x02 reached this handler, whether it came from real DSP traffic or other firmware routing, or whether the preceding RTC alarm or the SIM caused it. `simif-adsp-msg-origin` now traces 7.225B–7.2259B from `idle-c7225`; inspect message allocation/routing and the original ADSP mailbox model rather than suppressing the assertion.

## 2026-11-05: fresh-card boot stopped at 7.226B; failure replay running

`simif-fresh-gss-8b` stopped at cycle 7,225,961,838 with `firmware_loop` at kernel 0x50324294 (interrupts masked); this is earlier than the older cardless boot's 11.928B stop, but different runs are not a controlled comparison. The run preserved 5B, 6B and 7B checkpoint CPU/host pairs and produced live screen frames under `build/sim/screens/boot-v15-simif-fresh-gss-8b-live/`; the latest PNG at completion shows the Nokia logo. Do not infer cause or SIM involvement from the stop address. `simif-fresh-faulttrace` has started from the saved 7B pair with a complete 7.2254B–7.225962B window and a 7.225B savepoint to identify the actual kernel fault and its caller. Separately, the focused RTC trace shows that the staged UEM model's unconditional assumed status bit 3 feeds the alarm-start chain; hardware semantics and a safe correction remain unverified. Preserve all active inputs and screen frames.

## 2026-11-05: assumed RTC alarm bit drives the alarm-start chain

`simif-rtc-alarm-window` completed at 916.7M and preserved `idle-c916.cpu` and `.host`. The complete trace shows the kernel RTC handler receiving status bit 3, comparing its two time/alarm representations as equal (the inspected comparison values are zero), and writing RTC driver state 1 at 916,670,252. The staged board's UEM 0x35 read explicitly ORs in bit 3 unconditionally (`base | 8 | ...`) under a documented frozen-clock/equal-alarm hypothesis. This is a concrete source of the observed ALARM startup, but a hardware defect is not proven: the current model deliberately assumes a level-matched alarm and real UEM acknowledgement, clock and alarm-register semantics still need verification. Do not simply remove the bit: prior notes report later RTC faults under different alarm timing. Investigate UEM RTC documentation/firmware and implement a tested clock/alarm model or a clearly labelled controlled experiment only after the active 8B run finishes; do not alter its hashed inputs. The current run has live screen updates after the Nokia logo; inspect them and its final result.

## 2026-11-05: current RTC alarm handler located

`simif-rtc-alarm-origin` completed at 919.1M. The RTC alarm handler at 0x5034e6a0 executed around cycle 916,648,194 and wrote driver state 1 at 916,670,252, before the traced ecust startup query. The compact bus log shows the handler reading several assumed UEM/CBUS values, including 0x31, 0x32, 0x33, 0x21, 0x23 and 0x22 as zero, but these observations alone do not establish which input caused state 1 or the real UEM semantics. `simif-rtc-alarm-window` now captures every instruction and bus access at 916.64M–916.68M and preserves the nearby `idle-c916` CPU/host pair; compare the actual conditional path with manual and board model before making a fix. The separate 8B boot remains active.

## 2026-11-05: RTC driver caused the observed alarm selection

`simif-rtc-reason` completed at 919.1M and saved `idle-c918.cpu` and `.host`. Its full trace confirms the first ecust startup query saw sentinel 8 at 919,010,434, took the ordinary RTC-driver branch at 0x50349840, then read RTC object state 1 at 919,011,621 and cached return value 1 at 919,011,855. NOS later maps that value to its explicitly labelled ALARM reason. This reproduces the old RTC lead on the current card-present boot, but does not yet establish why the RTC was in state 1 or whether that state is incorrect for the firmware inputs. `simif-rtc-alarm-origin` now probes the RTC alarm handler/state transitions from the same fresh boot checkpoint to 919.1M. The live fresh-card boot to 8B continues separately. Do not suppress the RTC alarm or force a normal startup.

## 2026-11-05: kernel startup query observed

`simif-alarm-origin` completed at 940M. At cycle 919,010,331 the fresh-card firmware loaded vtable +0xd0 = 0x503497dc, then called it at 919,010,339; its result was stored to startup selector 0x8000ceb5 at 919,011,943. This confirms the real interface identified from the checkpoint. The selected-PC trace alone does not show the internal branch or return register. `simif-rtc-reason` is now tracing 918,990,000–919,030,000 from the same fresh 176.8M pair and will save `idle-c918` CPU/host. Inspect the actual kernel return path and RTC state before considering any model fix. The separate fresh-card boot to 8B continues with live LCD captures and preserved checkpoints.

## 2026-11-05: fresh card-present boot reached 4B, continued to 8B

`simif-fresh-gss-4b` completed at its 4B budget with no reported stop and preserved `roll-simif-fresh-gss-4b-r4000.cpu` and `.host`. No selected GSS task-start, SMS entry, SIM gate, MTC receiver or queue-drain PCs fired in the 2B–4B interval. The latest live screen was the Nokia logo at 2,922,985,940; the end-of-run offline LCD render has a restored-relative cycle label and does not supersede the live capture. Started `simif-fresh-gss-8b` from the compatible 4B pair to 8B with the same focused probes, live screen capture under `build/sim/screens/boot-v15-simif-fresh-gss-8b-live/`, and preserved billion-cycle CPU/host pairs. The alarm-origin investigation remains separately active. These results do not establish a working SIM.

## 2026-11-05: historical RTC lead matches fresh checkpoint structure

Kernel constructor 0x503487b8 initializes ecust object +0x14 to sentinel 8. On first query 0x503497dc chooses a hardware startup path and caches its result. Historical November 1 notes at status.md's `RTC alarm vs startup-reason ordering` identified ecust's +8 object as the RTC driver and its +0xc state 1/2 as an ALARM reason; those conclusions predate current CPU/board changes. In fresh `idle-c939` raw translated SDRAM, ecust +8 points to 0x804056a4 and that object's +0xc is 1; ecust +0x80 is 0. This is consistent with the older RTC lead, but is not a live trace of how this run reached state 1, and does not prove the RTC model is wrong. Once the active origin replay finishes, trace the first kernel startup-reason query and RTC state transitions on this fresh-card lineage, then compare actual UEM/RTC behavior with available schematics and documented semantics. Do not suppress the alarm or force a normal reason.

## 2026-11-05: alarm-selection interface resolved to kernel object

Static import analysis using the digest-verified `scratch/flash-cipher-r4/window-dec.bin` maps NOS import slot 0x5146e768 to ARM kernel accessor 0x503346b4, which returns the object pointer stored at 0x8000038c. At fresh `idle-c939`, page-table-translated raw SDRAM holds object 0x80404080 and ROM vtable 0x5034a970; its +0xd0 entry is 0x503497dc. This routine returns object word +0x14 directly unless it equals 8; raw checkpoint word at 0x80404094 is 1. Thus the expected source of NOS's initial 1 is a kernel object's startup value, not yet a demonstrated SIM-interface defect. Dirty cache and the actual call remain to be checked by `simif-alarm-origin`, which is running. Identify who initializes that object word and what hardware or software input it represents before changing the board model.

## 2026-11-05: startup reason 3 is explicitly ALARM

`simif-startup-reason` completed at 940.2M and preserved `idle-c939.cpu` and `.host`. At 939,943,660 firmware reads 1 from 0x8000ceb5; its 0x514c235c jump table selects the branch referencing the in-ROM string `MTC:SU:ALARM` at 0x516cf72c and writes 3 back to that same variable at 939,945,309. With observed startup flags lacking 0x80, it copies 3 to 0x800107e0 at 939,977,926. Thus the firmware itself identifies this path as alarm startup; whether the selection is appropriate is unproven and must not be forced. Static ARM code 0x514a661c–0x514a662c obtains the earlier value for 0x8000ceb5 from an indirect interface vtable entry +0xd0. `simif-alarm-origin` is tracing that actual call and return from the fresh 176.8M checkpoint to 940M; determine what implementation supplies 1 and whether it represents emulated hardware, firmware, or an assumption. The fresh-card 2B–4B boot continues with live LCD and checkpoint preservation.

## 2026-11-05: fresh-card boot passed 3B

The running `simif-fresh-gss-4b` replay preserved `roll-simif-fresh-gss-4b-r3000.cpu` and `.host`. Page-table-translated raw SDRAM at 3B has the same SIM notification list count/head, MTC state, gate and task 0x18 state bytes as 2B; dirty cache is not overlaid. The Nokia logo frame remains the latest confirmed LCD output. Continue to 4B and inspect actual PC hits/result before drawing conclusions.

## 2026-11-05: Nokia logo on fresh card-present boot

The active `simif-fresh-gss-4b` replay produced a live LCD frame at cycle 2,922,985,940: `build/sim/screens/boot-v15-simif-fresh-gss-4b-live/frame0001_cycle2922985940.png`. Visual inspection shows the blue NOKIA wordmark on white. This is actual captured simulated LCD output under the existing display assumptions; it does not establish a working SIM or that the later App. closed / Main and ViewSrv failures are fixed. Preserve the image and continue the boot and startup-reason trace.

## 2026-11-05: modem state follows firmware startup reason 3

`simif-startup-state` completed at 942M, preserving `idle-c941.cpu` and `.host`. Its full trace establishes that 0x514c21c4 reads startup reason 3 from 0x800107e0 at cycle 941,619,791. Firmware validates it, then carries 3 through 0x8001095a at 941,647,919 and 0x8001095c at 941,649,613; the previously traced 955M code copies that state to 0x8001095b and sends 0x1511/state 3. Correction to earlier notes: the `CMP` trace line's `10@00000002` is the comparison result 3−1, not register r0=2; the preceding load explicitly shows r0=3. State 3 is therefore firmware-selected from its startup reason, not an arbitrary MTC default. Why the earlier producer chose reason 3 and whether it is correct for the hardware model remain unknown. `simif-startup-reason` is tracing 939.9M–940.1M from the fresh 176.8M checkpoint and will preserve `idle-c939` CPU/host; the separate fresh-card boot to 4B continues. Do not force startup reason or modem state.

## 2026-11-05: fresh-card notification queue timing confirmed

`simif-fresh-init-events` and full-window replays `simif-fresh-1280` / `simif-fresh-1280-queue` used the fresh `idle-c955` pair. The firmware posts internal event 0x1280 at cycle 962,933,182, its SIM_Server transition matches at 963,068,113, and the notification list at 0x80029630 gains its first node 0x80026510 at 963,142,420–461. Thus the MTC 0x15c0/action 0x0c received at 955.837M precedes the queue by ~7.3M cycles and cannot explain its later release. No selected gate, queue-drain or 0x126b completion entry appeared in the 955M–999.999M probe. This confirms a live sequence rather than inferring it from raw 1B/2B RAM; it does not establish why no later acknowledgement arrives. The 941.6M startup trace and fresh-card 2B–4B boot continue.

## 2026-11-05: fresh card and earlier cardless 2B snapshots

Page-table-translated host SDRAM at 2B in `roll-current-tlbhold-20b-r2000` has MTC state 3, gate 0 and task 0x18 state byte 5, matching the fresh corrected-card 2B snapshot. The raw SIM notification list count differs: 0 in that older cardless checkpoint versus 1 in the fresh card-present checkpoint. This is an informative historical comparison, not a controlled matched run: the board/profile and boot lineage differ, and neither raw snapshot overlays dirty CPU cache. It supports investigating what releases the card-generated queue without claiming that SIM presence caused the shared MTC state or any UI failure.

## 2026-11-05: corrected-card boot reached 2B; continuing to 4B

`simif-fresh-gss-2b` completed at 2B without a reported firmware stop, saving `roll-simif-fresh-gss-2b-r2000.cpu` and `.host`. No selected GSS event/task-start, SMS entry, SIM gate, MTC receiver or SIM queue-drain probe fired between 1B and 2B; no SIMIF bus records or new live LCD frames were observed. Using page-table translation, raw host SDRAM at 2B retains the same notification list count 1/head 0x80026510, gate 0, MTC state 3 and task 0x18 state byte 5 as at 1B. These are raw SDRAM, without dirty CPU-cache overlay, so they do not prove architecturally visible persistence. Continued this same corrected-card lineage from 2B to 4B as `simif-fresh-gss-4b`, with live screens at `build/sim/screens/boot-v15-simif-fresh-gss-4b-live/` and all billion-cycle checkpoint pairs retained. The independent startup-state replay is still running. Inspect its trace and 4B boot result before deciding changes.

## 2026-11-05: traced modem state message to firmware startup

`simif-mtc-request-origin` completed its 955M–955.760M replay. At 955,725,376 firmware 0x514c5cdc copies 3 from 0x8001095c to 0x8001095b, and its startup helper 0x514c62b8 constructs MTC message 0x1511 with that byte at 955,726,132–152. The MTC server then publishes the observed 0x15c0/action 0x0c at 955.761M, which SIM_Server receives at 955.837M but does not treat as READY. This establishes the immediate sender and state source; why 0x8001095c was set to 3 remains unknown. `simif-startup-state` is now tracing the earlier 941.6M startup decision from the fresh 176.8M checkpoint and will save the paired `idle-c941` checkpoint. It runs alongside the fresh 2B boot and must not have its inputs modified. Do not force a state or assume action 0x0c's meaning.

## 2026-11-05: observed MTC indication is not READY

`simif-mtc-msgtrace` completed at 956M and preserved `idle-c955.cpu` and `.host`. Its full trace shows MTC server receiving message key 0x1511 with byte +2 = 3 at cycle 955,760,775; it changes 0x8001df48 from 0 to 3 and builds 0x15c0 with action 0x0c, not the hypothesized READY action 4. SIM_Server receives key 0x15c0 and at 955,843,258 reads action 0x0c; it takes neither its action-4 nor action-3 branch, so this message does not trigger that queue-drain path. The later queued SIM notification was not yet known to exist at this point. This identifies the earlier builder/receiver hits and rules out treating them as a READY observation; the true startup-sync request and any later READY remain unobserved. `simif-mtc-request-origin` is tracing the preceding 955M–955.759M interval from the compatible new 955M checkpoint to find the sender and state-3 origin. The separate fresh-card run to 2B remains active with live screens and selected task/SIM probes.

## 2026-11-05: fresh card boot extended to 2B

`simif-gss-after1b-long` completed from fresh 1B to 1.2B with no hits at selected GSS lifecycle/task-start, SMS-task or ATKinf-gate PCs. This does not establish whether they ran before 1B or will run later. Started `simif-fresh-gss-2b` from that compatible 1B CPU/host checkpoint through 2B, monitoring selected GSS/SIM paths and saving live LCD changes under `build/sim/screens/boot-v15-simif-fresh-gss-2b-live/` and the 2B CPU/host pair. This extends the corrected-card boot beyond the earlier 1.2B endpoint; it is distinct from the parallel 955M MTC message trace, whose inputs must remain unchanged. Inspect both results and continue the investigation without assuming either result in advance.

## 2026-11-05: probing GSS task startup after 1B

`simif-gss-after1b` restored the fresh card-present 1B checkpoint and reached 1.02B; selected PCs for GSS event 0xc012 handler, task-start batch, GSS lifecycle dispatch, SMS task entry and ATKinf gate had no hits in that 20M-cycle interval. This does not cover earlier or later boot. `simif-gss-after1b-long` now extends the same probe through 1.2B while the separate earlier MTC message window is being traced. Preserve both active simulations' inputs and checkpoint pairs. Neither replay changes firmware behavior.

## 2026-11-05: focused MTC message trace running; GSS startup lead

`simif-mtc-msgtrace` is replaying the card-present 176.8M checkpoint to 956M, with a complete instruction/bus window at 955,750,000–955,850,000 around the observed MTC builder and SIM receiver entries. It will also save CPU/host checkpoint `idle-c955`; live captures go to `build/sim/screens/boot-v15-simif-mtc-msgtrace-live/`. Do not change its hashed inputs. Static ROM inspection separately found that function 0x515e9610 starts NOS tasks including 0x14 and SMS task 0x18; its direct caller 0x51503e84 is registered for internal event 0xc012 in the GSS Server table at 0x516d2284. It is unproven whether this event ran or whether raw checkpoint task-state bytes reflect architectural state. Trace the event and scheduler behavior before attributing the pending SIM notification to either task.

## 2026-11-05: early MTC replay completed at 1B

`simif-mtc-startup` completed its 1B cycle budget from the fresh card-present 176.8M checkpoint, preserving `roll-simif-mtc-startup-r1000.cpu` and `.host`. Selected trace records show MTC indication builder entry at cycle 955,761,261 and SIM_Server receiver entry at 955,837,080, before the observed final SIM SELECT at 962,820,584. These entries alone do not identify the message or establish whether it was READY, nor prove the later queued SIM notification was released. The selected startup-sync handler and known READY caller probes did not hit in this replay. The startup reason comparison at 941,620,727 showed subtraction result 2; the input was 3, as confirmed by the subsequent full trace (see newer entry). No new live screen was captured. Next inspect message arguments, receiver dispatch and exact ordering with a short replay from a compatible checkpoint; retain the new 1B checkpoint pair and current traces.

## 2026-11-05: verified NOS task descriptor indexing

N-Gage ROM initialization 0x514a87e4 walks the 12-byte descriptor array at 0x516c9968 sequentially, incrementing the task index and storing it in each 16-byte RAM task record. Thus task 0x18's descriptor at 0x516c9a88 really points to 0x514fee45, the SMS loop; task 0x14 points to 0x514e331d. This confirms the static routing of candidate SMS posts (0x0c90/0x0c92 to task 0x18, 0x0a33 template to task 0x14), but not that any posts happened or that the SIM_Server handled them. At the fresh 1B checkpoint, raw RAM task 0x18 record at 0x8007dc24 has queue head zero and metadata ending `0x00180550`; CPU-cache overlay and meaning of state byte 5 are not yet established. The MTC startup replay is active from 176.8M; preserve its inputs and checkpoint pairs.

## 2026-11-05: fresh boot also has queued SIM notification

Offline host-RAM inspection of the new card-present 1B checkpoint found SIM_Server notification list 0x80029630 with count 1 and head 0x80026510; that node points to 0x800263c0, whose fields are type 1, resource 0x53, payload pointer 0x800266c8. This is structurally the same queued notification as in the previous card-after-checkpoint run, with different allocation addresses. Host-RAM inspection does not overlay dirty cache, so confirm any conclusion about later consumption with live PC/bus probes. The MTC startup trace from 176.8M to 1B is running; inspect its actual startup reason, state and READY-call sites on completion. No firmware or checkpoint was changed.

## 2026-11-05: fresh 1B–1.1B MTC probe completed

`simif-mtc-fresh-r1b` restored the card-present 1B CPU/host pair, reached 1.1B and saw no selected hits at MTC startup-sync dispatch, READY builder/callers, SIM ISI receiver/drain, MTC state-change entry, ATKinf gate, queue pop or c054/0x126b callback. This is limited to that 100M-cycle interval; it does not say whether MTC startup activity happened before 1B. Next trace the earlier boot from the preserved 176.8M pair with targeted startup-reason, MTC initialization, READY and SMS probes. Save its 1B CPU/host pair and do not alter active inputs.

## 2026-11-05: fresh card-present boot reached 1.2B

`simif-zero-resume176` completed its 1.2B-cycle budget after resuming the genuine card-present boot at 176.8M. It preserved `roll-simif-zero-resume176-r1000.cpu` and `.host` at 1B. SIM FIFO commands reached SELECT 6fc6 at cycle 962,820,584; none followed through 1.2B. Selected corrected-PC probes for SIM state, candidate ATKinf gate, SMS producer/consumer and c054/0x126b did not fire in the observed portion 176.8M–1.2B. No new PNG was emitted after the checkpoint; the original from-zero white clear is `build/sim/screens/boot-v15-simif-fromzero-gate-live/latest.png`. Raw 1B checkpoint SDRAM has SIM_Server state 1, gate 0, MTC current-state byte 0x8001df48=3, and startup reason byte 0x800107e0=3. In earlier cardless 1B and test-card-after-1B 2B checkpoints that reason byte was 1, although MTC state was also 3; these RAM reads have dirty-cache limitations and do not establish causation. Next probe MTC startup-sync/READY events using the fresh 1B pair, and independently trace early startup-reason origin from the preserved 176.8M pair; preserve both CPU/host pairs and original firmware.

## 2026-11-05: startup reason 1 and an upstream GPIO path

`0x514c21c4` reads the byte at 0x800107e0. Raw SDRAM snapshots show that byte = 1 in the old cardless 1B and 11B checkpoints and the diagnostic-card 2B checkpoint (dirty-cache caveat). Static control flow in 0x514c59c0 converts startup reason 1 to modem state 3 at 0x514c5a60, and 0x515999e0 subsequently copies MTC control state 0x8001095b into 0x8001df48. One route that sets reason 1 is 0x514c1f48 when flags include 0x80 and 0x514c11b8 returns 3; static code 0x514c12b4 can derive that flag from bit 0x04 of the halfword at virtual 0x58150000, and 0x514c11b8 can read virtual 0x5800428e when GPIO bits are set. Actual values, selected branch and whether the GPIO/ASIC model is correct during the current boot remain unverified. Trace the boot-time producer and compare the schematics/manual before modifying reset inputs; do not simply force the reason or MTC state. The fresh SIM replay remains active.

## 2026-11-05: compact bus silence is expected during early checksum

Comparison against the preserved cardless `current-tlbhold-20b` bus log shows an 18.2M-cycle gap from 176,924,338 to 195,124,702 and fewer than 128 further logged records before cycle 864M. The current from-reset resume can therefore legitimately leave a buffered compact bus file empty for a long period while executing the checksum; silence cannot be used to estimate its current cycle or diagnose a hang. Continue `simif-zero-resume176` without restarting it. The earlier bounded trace independently showed the CPU active at cycle 180M.

## 2026-11-05: MTC state source narrowed

Static N-Gage ROM code shows MTC server constructor 0x515999e0 obtains its initial current-state byte for 0x8001df48 from 0x514c6414, which reads 0x8001095b. MTC control bootstrap 0x514c59c0 obtains a startup reason via 0x514c21c4; along one branch 0x514c5a60 converts reason 1 to state 3 before continuing. This makes the observed raw state 3 potentially relevant to startup reason/power-key/RTC modeling, but it does not establish which branch this boot took or prove 3 means alarm in this exact firmware. After the active from-reset run, trace 0x514c21c4 return, 0x514c5a60, actual writes to 0x8001095a/5b and 0x8001df48, and the MTC READY sender with correct Thumb trace-PC offsets. Compare the earlier and current power/RTC model assumptions before any fix; do not force NORMAL.

## 2026-11-05: no MTC probe hits at 2B–2.05B

The independent `simif-mtc-probes-r2b` replay completed 2B–2.05B with no selected hits at the MTC startup-sync dispatch, READY builder/callers, SIM_Server receiver/drain or MTC state-change entry. This is a narrow interval from the previous test-card checkpoint, and cannot establish whether these paths fired earlier or later. Next probe the 1B–1.05B interval around SIM event 0x1280 using the corrected ICCID, while the fresh boot continues. Do not infer missing events merely from silent bus logs.

## 2026-11-05: independent MTC probe running

While the fresh card-present replay continues from 176.8M, launched a distinct short `simif-mtc-probes-r2b` replay from the preserved 2B checkpoint to 2.05B. It probes the N-Gage MTC startup-sync dispatch, READY indication builder/callers, SIM_Server ISI receiver/drain and MTC state-change handler. The 2B checkpoint contains the earlier invalid-ICCID history, so this run tests only the later modem-control path, not the corrected card identity. No sources or active inputs changed; preserve the original 2B pair. Inspect output before deciding whether to trace further or implement any model change.

## 2026-11-05: MTC READY state byte is not yet normal

For MTC action READY (4), builder 0x5159a2ba loads the state byte from 0x8001df48 and puts it at message +2. Raw host SDRAM in both the diagnostic-card 2B checkpoint and earlier cardless 11B checkpoint has 0x8001df48 = 3 (and +1 = 3). In the later Nokia oFono definitions, MTC state 3 is ALARM; the N-Gage SIM receiver only drains on state 1 or 4, so a READY message carrying 3 would not satisfy that branch. This is a strong next hypothesis, not proof of the current architecturally visible value, the N-Gage enum meaning, actual emission, or causation: checkpoint reads do not overlay dirty cache and no READY message was observed in these intervals. Probe the builder/state stores and real MTC events; compare cardless and test-card boots rather than changing the byte or forcing a transition.

## 2026-11-05: MTC startup synchronization can generate SIM queue release

Nokia oFono `drivers/isimodem/mtc.h` identifies MTC resource 0x15, `MTC_STARTUP_SYNQ_REQ` message 0x0b, response 0x6e, and `MTC_STATE_INFO_IND` 0xc0. N-Gage ROM independently shows MTC server dispatcher 0x51599c56 switching on received resource 0x15 and message ID; jump-table index 0x0b selects 0x51599d0c -> 0x5159a9ac. That handler sends response 0x6e and, when its internal flag is zero, calls the actual indication builder 0x5159a198 with 0xc0/action 4 (READY). SIM_Server can drain its pending notification on that READY indication when the reported MTC state is NORMAL 1 or TEST 4. This is a plausible end-to-end path but is static: we have not yet observed whether 0x150b is sent by this N-Gage firmware boot, whether its handler executes, what state is reported or whether timing matches the pending SIM message. Trace the real MTC request/client and resulting broadcast with corrected trace PCs; do not synthesize a request or force a response. The from-reset SIM boot continues from checkpoint 176.8M with live capture.

## 2026-11-05: quiet fresh boot was still progressing

`simif-zero-earlytrace` completed 180M and preserved CPU/host checkpoint `idle-c176.*` at cycle 176.8M. Full trace shows the ARM actively executing its checksum loop around 0x50004040 at 180M; compact bus silence after 176.9M was not proof of a stall. Stopping the earlier long run was premature. Resume the fresh card-present boot from the new 176.8M checkpoint, preserve every billion-cycle checkpoint and live screen outputs; do not infer a fault from quiet logs during this checksum. The white clear from the from-zero run is in `build/sim/screens/boot-v15-simif-fromzero-gate-live/`.

## 2026-11-05: from-reset replay stopped for focused diagnosis

`simif-fromzero-gate` showed white live frame at cycle 168,453,013. Its last flushed bus record remained cycle 176,916,188 for over four minutes while the simulator container consumed a CPU core; no selected-PC hits were flushed. This does not prove the simulated cycle was stuck, because compact logging can be silent. Stopped that run to replace it with a bounded from-reset trace around 176.8M–177.6M and a CPU/host checkpoint at 176.8M; no result or 1B checkpoint was produced. The live screen and run evidence remain preserved. Inspect the bounded trace before attributing the silence to a fault.

## 2026-11-05: firmware MTC ready-indication builder identified

ROM MTC server source `CORESW/SERVERS/MTC/Mtc_srv.c` has a concrete ISI builder at 0x5159a198. For message 0xc0 it allocates a four-byte message, writes id at +1, MTC state at +2 and action at +3; callers 0x5159a0c6 and 0x5159a9d8 invoke it with c0/4 (READY), whereas 0x5159a706 sends c0/3 (START). This matches the independent Nokia oFono definitions and the SIM_Server's 0x15c0 drain conditions. Determine whether actual READY caller runs, what state byte it uses, and whether its indication reaches the SIM server after the notification is queued. Suggested trace-PC probes: 0x5159a194 (builder entry), 0x5159a0c2 and 0x5159a9d4 (ROM callers minus four), 0x5159b600 (SIM receiver), 0x5159b6b6 (drain call), plus state-change 0x514c5b64. From-reset run `simif-fromzero-gate` remains active with unchanged inputs and live screens.

## 2026-11-05: alternate SIM queue trigger is MTC state indication

SIM_Server receiver 0x5159b604 compares its ISI key to 0x15c0; when body byte +3 is 4 and body byte +2 is 1 or 4, it calls queue drain 0x5159b5ac. Nokia-authored oFono definitions independently label resource 0x15 `PN_MTC`, message 0xc0 `MTC_STATE_INFO_IND`, action 4 `MTC_READY`, and states 1/4 `MTC_NORMAL`/`MTC_TEST` (https://kernel.googlesource.com/pub/scm/network/ofono/ofono/+/refs/tags/2.14/drivers/isimodem/mtc.h; later implementation, corroborative rather than N-Gage-specific proof). This makes a real modem-control ready indication a concrete alternate route to drain the queued SIM notification. Old November 1 notes discuss MTC startup stall, but their claimed causes predate major CPU/board changes and must not be assumed for this run. Raw host SDRAM byte 0x8001095a reads 3 in the 1B, synthetic-card 2B, and old baseline 11B checkpoints; cache/writeback and the variable's exact present meaning remain to be validated. After the active from-reset run, probe actual MTC state changes and 0x15c0 handling in both profiles and locate the genuine sender. Do not inject a guessed ready indication.

## 2026-11-05: upstream producer belongs to SMS_Server

The ROM data surrounding the 0x0c90 template names `SMS_Server` and `CS_SERVERS/SMS/Srv_sms.c`; the upstream 0x515aa29c dispatcher accesses its state halfword at 0x8002239a. Its jump-table entry for state 9 reaches the branch containing the candidate 0x0c90 post at 0x515ab348, subject to further input and helper checks. This is static evidence linking the possible SIM notification release to SMS_Server startup, not proof that SMS_Server caused the observed boot stall. The from-reset card-present run is active with live capture and probes; check whether these paths occur before choosing a fix.

## 2026-11-05: another candidate 0x0c90 sender

ROM table 0x516e44ec begins with internal message id 0x0c90. In firmware, 0x515ab342 loads that template and 0x515ab348 posts it to task 0x18 after a call to 0x5166b3c4 returns zero. This is a second candidate upstream path to the SMS task's 0x0c90 branch and 0x0a33 template. The template pointer and task number are statically visible; whether the sender branch executes and what the helper's result means remain unknown. The from-reset replay currently probes related dispatcher PCs but not this newly identified send site; after it completes, use a compatible checkpoint to probe trace PC 0x515ab33e and its helper return without modifying firmware behavior.

## 2026-11-05: dispatch probes absent after 1B; tracing from reset

`simif-sms-dispatch` reached 1.05B from the preserved 1B checkpoint with corrected ICCID. None of the selected Thumb-offset probes at the upstream dispatcher, 0x0c92 builder, SMS task entry/receive, 0x0c90/0x0c92 branches, or ATKinf c063 hit in 1B–1.05B. These negative results do not cover earlier boot; the original 1B checkpoint is from a cardless run. Next run the current synthetic-card board from reset, with PC probes and live screens through 1.2B, preserving the 1B CPU/host pair. This determines whether the initial SIM notification chain differs when the card is present from power-on. Do not edit source or active inputs until it completes; results will be recorded separately from checkpoint-restored runs.

## 2026-11-05: upstream SMS probes absent in later interval

`simif-sms-upstream-r2b` completed 2B–2.1B using the preserved old-ICCID host/CPU checkpoint. No selected hits occurred at the SMS receive-loop load, 0x0c90/0x0c92 branches, candidate 0x0c92 builder, or ATKinf gate. This does not prove the SMS task never ran outside that interval. Next probe the larger upstream firmware dispatcher 0x515aa29c, SMS task entry and queue receive over a fresh corrected-ICCID replay; identify the missing message source rather than inject 0x0a33.

## 2026-11-05: candidate message handoff matches task table

The ROM task descriptor array appears to start at 0x516c9968, with 12-byte rows: index 0x18 points to entry 0x514fee45 (the SMS loop), and index 0x14 points to 0x514e331d. This supports a concrete candidate chain: 0x515ab58e builds message 0x0c92, 0x515ab59e posts it to task 0x18, SMS loop can process 0x0c92 and post the 0x0a33 template to task 0x14. Table indexing and the actual runtime delivery/conditions still need to be validated with probes; this is not yet an observed end-to-end chain. Current 2B-based upstream replay is active. Next trace whether 0x515ab58e is reached and what event/condition selects its branch.

## 2026-11-05: SMS producer probes absent in early interval

`simif-sms-upstream` replayed 1B–1.05B with corrected trace-PC offsets. It saw no selected hits for the SMS task receive point, event 0x0c90/0x0c92 branches, their candidate sender, or ATKinf c063. This is limited to those PCs and that interval; it does not establish whether the SMS task existed, ran earlier, or is waiting. Next inspect the 2B-based state with the same upstream probes and follow the actual task queue/scheduler before altering a peripheral.

## 2026-11-05: corrected late gate probes

`simif-sms-tracepc-r2b` replayed 2B–2.15B with corrected Thumb trace-PC offsets. No selected hits were observed for candidate SMS event producers, ATKinf gate, SIM notification drain, list pop or completion callback in that late interval. The checkpoint still carries the earlier synthetic ICCID. Next instrument the SMS task receive loop, its 0x0c90/0x0c92 branches and the candidate 0x0c92 builder to find what upstream event is absent or delayed; no conclusion is drawn about any unobserved interval.

## 2026-11-05: SMS task inputs preceding the candidate completion

Static disassembly of SMS task loop 0x514fee44 shows two paths to the candidate 0x0a33 template: input event 0x0c90 branches to 0x514ff40c and may post 0x0a33 at 0x514ff43a; input event 0x0c92 branches to 0x514ff478 and may post it at 0x514ff4a2. Conditions in those branches still matter. One producer of a message headed 0x0c92 is 0x5166b274 (literal load and STRH at 0x5166b2d8), called by 0x515ab58e, followed by a post to task 0x18 at 0x515ab59e. Whether this producer actually constructs the relevant message in our boot, or its task-0x18 recipient is the same SMS loop, is not established. Use trace PCs offset -4 when probing and verify message delivery; do not conflate static references with runtime evidence.

## 2026-11-05: corrected Thumb probes absent through 1.05B

`simif-sms-tracepc` replayed 1B–1.05B using the corrected ICCID and trace-PC offsets (ROM PC minus four). It saw no selected entry hits for candidate SMS producers, ATKinf c063, notification drain/pop, or c054/0x126b dispatch in this interval. This supports the early non-occurrence but does not exclude activity before 1B or after 1.05B. Next inspect a later window from the preserved 2B checkpoint with the corrected probe addresses; that checkpoint contains the older ICCID history. The CPU/host pair remains preserved.

## 2026-11-05: correction on Thumb probe addresses

The simulator instruction trace labels Thumb instructions four bytes before their ROM disassembly address: e.g. the ROM STRB at 0x5159c020 appears in trace at 0x5159c01c. Several recent PC probes used ROM entry addresses directly, so their negative results do not reliably exclude execution of those entry instructions. Re-run candidate probes with trace PCs four bytes below ROM addresses and, where possible, probe multiple neighboring PCs; use a full trace to validate correspondence. The current `simif-sms-producer` run started before this correction and should not be used to exclude the candidates. Full trace observations and the state-1 conclusion remain separate evidence.

## 2026-11-05: no late SIM queue-release probe through 2.15B

`simif-queue-gate-r2b` replayed the old-ICCID 2B checkpoint through 2.15B, probing 0x5165e684, both drain callers, 0x5159b5ac, ContainerList pop and the c054/0x126b paths. None of those selected PCs fired in that interval. The earlier 1B–1.02B probe used the corrected ICCID and likewise had no selected hits; do not extrapolate to unobserved intervals. ROM template 0x516d1dd0 starts with bytes 33 0a 00 00, so its payload byte +2 would satisfy the ATKinf c063 zero test if delivered in the expected message shape. Trace actual candidate SMS producer 0x514ff432/0x514ff49a and dispatcher, not just static assumptions.

## 2026-11-05: candidate internal event 0x0a33 producer

Read-only ROM search found a static message template at 0x516d1dd0 beginning with 0x0a33; its nearby firmware source string is `CS.ISA/CS_CN/SMS/Smcl_srv.c`. Code at 0x514ff432 and 0x514ff49a loads that address and posts it to task 0x14 through 0x516c755c, under different SMS-state branches. This is a candidate producer of the internal event routed to ATKinf c063, not proof these branches ran or that a posted template is handled by SIM_Server. Probe these branch entries along with 0x5165e684 and queue-drain PCs, then follow their preceding conditions and actual recipient. SIM notification flow may depend on another firmware subsystem; do not infer it from event numbers alone.

## 2026-11-05: correction: 0x0a33 and 0x5301 are internal event IDs

`docs/modem-model.md` identifies 0x516e09c8 as the SIM_Server *internal-event* routing table, separate from its ISI service table at 0x516e02a8. Therefore the earlier notes calling 0x0a33 or 0x5301 resource/message keys are not established and should be read as **internal event identifiers**. This invalidates the inference that network resource 0x0a is their source. Event 0x0a33 routes to ATKinf c063 and 0x5301 to c054; their actual senders remain unproven. `simif-queue-gate-r2b` is probing the gate and callback from the preserved 2B checkpoint. Next trace who posts those internal events and whether an actual subscriber consumes the 0x53 notification; do not invent external messages or SIM-ready transitions.

## 2026-11-05: notification gate belongs to ATKinf

`simif-queue-gate` replayed 1B–1.02B with the corrected ICCID and selected probes at 0x5165e684, 0x5159b5ac, 0x516a8aa8, both drain callers, c054, and 0x51513120. None fired in that interval; this is not evidence about later time. ROM class metadata identifies the c063 object receiving route key 0x0a33 as `ATKinf`, with firmware source path `SIM_SERVER_DCT4/Srvsim_atkinf.c`. It sets the queue-release flag when incoming payload byte +2 equals zero. The exact sender and the protocol meaning of 0x0a33 remain unresolved; its name suggests toolkit-related functionality, but do not equate it with a real network-registration event based on resource number alone. Continue tracing routes and firmware clients; do not invent replies or assume a working card.

## 2026-11-05: 2B-based callback replay completed

`simif-completion-r2b` restored the original synthetic-card 2B CPU/host pair and reached 2.2B. Its selected probes saw no 0x51664c74, 0x51506d2c, 0x51513120 or SIM state-change hit in that interval; no post-restore screen was captured. This run carries the earlier invalid-ICCID test history; it cannot evaluate the corrected ICCID. Next trace the queue-release gate 0x5165e684 and dequeue paths during 1B–1.02B, then inspect the sender/client of resource key 0x0a33; do not infer the handshake occurs solely from static code.

## 2026-11-05: identified notification-release gate

Static disassembly shows SIM_Server queue drain at 0x5159b5ac is called by 0x5159ba7e only when global 0x8000c234 is nonzero; the preserved 2B host RAM has that byte zero (cache caveat). A separate path 0x5159b6ba can also invoke the drain when its incoming byte +2 is 1 or 4. ROM method 0x5165e684 sets 0x8000c234=1 when its incoming byte +2 is 0, and is method c063; routing table entry 0x516e0cf8 maps key 0x0a33 to c063. This is a concrete candidate handshake that may release the queued resource-0x53 notification, but timing and originating component are unproven. Probe handler 0x5165e684, queue-drain 0x5159b5ac and list pop 0x516a8aa8, then trace the real sender of 0x0a33 before changing any model. Never force the flag. The 2B-based completion-probe run remains active.

## 2026-11-05: SIM notification appears queued at 2B

The 0x1280 handler created a notification containing type 1, resource 0x53, payload beginning 01 00 00; `ContainerList` method 0x3008 appended node 0x80026780 to object 0x80029630 at cycle 1,009,212,593. Offline SDRAM inspection of the 2B host checkpoint still shows list count 1 and the same node pointing to 0x80026750 with fields 1/0x53/0x800267e8. This suggests the notification was not dequeued by 2B, but the checkpoint inspection does not overlay potentially dirty CPU cache and cannot alone prove that. ROM ContainerList method 0x3009 at 0x516a8aa8 removes the head and decrements its count. Next trace whether that method runs for this list and identify the guest task/client expected to consume it; do not manufacture a 0x5301 reply. The 2B-based callback-probe replay remains active and preserves the checkpoint.

## 2026-11-05: corrected ICCID did not change early SIM behavior

`simif-checksum-completion` used the Luhn-valid synthetic ICCID and ran from 1B to 1.02B. Unit tests pass. The observed APDU sequence and final 6fc6 file-not-found match the previous test, with no observed state write and no hit on c054, 0x126b dispatch or 0x51513120 by 1.02B. This only rules out those probed paths during that interval. Next use the preserved 2B CPU/host checkpoint from `simif-acc-2100m` for a focused continuation with those probes; it contains the previous invalid-ICCID test history, so cannot establish the effects of the corrected ICCID, but has compatible serialized card fields. Track whether actual callback or screen activity occurs and preserve all checkpoints.

## 2026-11-05: 2.1B SIM replay completed

`simif-acc-2100m` completed 2.1B with no selected SIM_Server state change after its early state 1 event and no SIM FIFO writes after 6fc6 at 1,008,895,154. The live watcher generated no new PNG; restore at 1B does not reconstruct an initial frame. The 2B CPU/host checkpoint pair is preserved at `roll-simif-acc-2100m-r2000.*`. The older synthetic ICCID used in this run failed Luhn; corrected its final byte f4→f8 and added an independent Luhn assertion. Next run focused PC probes for c054/0x126b, along with the checksum-corrected card, then investigate whether resource 0x5301 is sent by firmware client. This run does not establish a serving SIM.

## 2026-11-05: candidate completion input and state mapping

For the outstanding asynchronous path, ROM byte 0x800c98f8 was set to 3. Firmware handler 0x51513120 dispatches by that byte; state 3 selects case 0x51513180, where incoming completion values 0 or 1 lead to SIM ready status 1 (values 2–5 follow other statuses). Its sole direct BL caller is 0x51506d2e, reached by internal message 0x126b. Firmware method c054 builds this message, taking its byte either from request data after an internal 8-byte comparison or defaulting to 3; its server routing key is 0x5301. This statically narrows the missing completion, but does not prove that the guest should receive one, which component sends it, or what data should be accepted. After the current run, probe 0x51664c74, 0x51506d2c and 0x51513120, and trace resource 0x53 requests/clients before modeling anything. Do not synthesize security or readiness messages without identifying the actual path.

## 2026-11-05: candidate asynchronous completion route

Static ROM inspection located the potential completion path: SIM subsystem dispatcher 0x51506624 indexes its jump table with internal message ID minus 0x1195; index for 0x126b branches to 0x51506d2c, calling 0x51513120 with message byte +2. Depending on its state/input, that routine can emit SIM status 1 through 0x51615174, which the documented server table maps to serving state 8. Internal message 0x126b is constructed by firmware method 0x51664c74, listed as c054 in class table 0x516fc0ac; the SIM server routing table entry 0x516e0d1c maps key 0x5301 to that method/object. The observed 0x1280 path sends an internal notification associated with resource 0x53; whether an external 0x5301 reply is actually expected or whether this callback is exercised through another route is unproven. Inspect firmware clients and targeted PC probes, and model only observed underlying behavior, never inject a guessed ready event. The 2.1B run is still active.

## 2026-11-05: firmware's asynchronous SIM-ready path

Read-only disassembly and `simif-last-select` clarify the 0x258 path: at 0x5150baa8 firmware calls 0x515107c0, whose actual ROM body is `movs r0,#0; bx lr`. Because it returns zero, the firmware stores 3 at 0x800c98f8 and calls 0x515107b0, which posts internal event 0x1280; the alternative branch would send SIM status 1 to 0x51615174. Event 0x1280 is dispatched via ROM table 0x516e0c74 (method c053, object 0x800ca718), then SIM_Server stays state 1. This is evidence of a firmware-selected asynchronous path, not permission to change the ROM stub or force status 1. Identify the actual completion message/caller that should follow; the 2.1B live-screen replay remains active with fixed inputs.

## 2026-11-05: synthetic ICCID checksum needs correction

An independent check found that the current synthetic ICCID decodes to `8901012345678901234` and fails the Luhn check. A valid-checksum replacement using the same fabricated prefix is `8901012345678901238` (last encoded byte f8 instead of f4). This may or may not affect firmware progress; no causality is established. Do not change the test-card header while `simif-acc-2100m` is running because the runner validates input hashes. After it finishes, correct the test ICCID and add an independent Luhn unit assertion, then compare from the same 1B checkpoint.

## 2026-11-05: live-screen SIM continuation to 2.1B

`simif-acc-2100m` starts from the original 1B checkpoint with the same isolated SIM profile as the completed 1.5B run. It preserves every billion-cycle checkpoint and uses a SIM-specific live LCD watcher adapted from the current-boot watcher; live PNGs, if actual updates occur, are in `build/sim/screens/boot-v15-simif-acc-2100m-live/`. No initial screen is implied by restoring at 1B. Observe later SIM state, commands and any display change, then investigate the next failure. Keep sources and inputs fixed until it completes.

## 2026-11-05: SIM remains in initialization state 1

`simif-acc-1500m` completed 1.5B without any later SIM bus commands or state-change probe, and did not capture a new screen from the restored checkpoint. The detailed `simif-last-select` trace explains one part: SIM_Server processes event 0x1280 at cycle 1,009,186,824, matches transition row 0x516e1604 and stays in state 1 with method 0x3111; it does not reach serving state 8. The event is generated after internal 0x258, itself returned at 0x51507144 after 0x5150efca sets flag 0x800ce050 bit 3. Determine what later internal event moves SIM_Server out of state 1 and why it never arrives. Do not infer completion merely from a missing state-write probe: the unchanged-state path skips the write. All this is from the isolated test card/controller; compare with real firmware logic and preserved cardless run.

## 2026-11-05: optional-file completion reaches modem state handler

In `simif-last-select`, the missing 6fc6 produces event 0x0a and the caller returns internal value 0x258 at 1,008,998,073. Firmware dispatches that value through 0x5150b65c and sets byte 0x800c98f8 to 3 at 1,009,003,178. Meaning of 0x258 and the byte is not yet established. A 1.5B replay `simif-acc-1500m` is running with unchanged inputs; do not duplicate it or alter its sources. Output is under `build/sim/runs/boot-v15-simif-acc-1500m/`; after completion inspect SIM state, later bus traffic and screen capture. It uses the runner's post-run screen capture, not a live PNG watcher.

## 2026-11-05: last optional SELECT completion traced

`simif-last-select` traced 6fc6 SELECT response 94 04 (file absent). The firmware receives and dispatches SIM event 0x0a by cycle 1,008,951,545; this is not enough to conclude the caller has finished or identify its subsequent wait. Through 1.15B `simif-acc-long` showed no SIM state transition or further card command. Next run the same verified model to 1.5B with compact SIM probes and post-run screen capture; compare the cardless baseline and inspect any eventual event, without treating missing optional operator files as fatal. No sources should change during the run.

## 2026-11-05: ACC replay stalls after optional operator files

`simif-acc-long` passed provenance and reached 1.15B. It selected/read EF_ACC (6f78), then received file-not-found for 6f14 and 6fc6, optional CPHS operator name and operator network list. No subsequent SIM FIFO write or selected SIM_Server state transition was observed through 1.15B; this is not evidence of a working SIM. Next capture full instructions around the 6fc6 response and follow the actual completion/wait path. EF_ACC unit tests pass. The earlier `simif-imsi-long` result is invalid because source changed mid-run and must not be used. Sources are frozen for each future run.

## 2026-11-05: long replay provenance invalidated

The SIM source was edited to add and unit-test EF_ACC (6f78) while `simif-imsi-long` was running. The runner correctly detected changed inputs and rejected its output, so do not use that run as evidence even though the executable itself was already running. Rebuild with EF_ACC and rerun from 1B, and do not edit tracked simulation sources until it completes. Optional files 6f14 (CPHS operator name) and 6fc6 (operator network list) may legitimately be absent; don't fabricate success.

## 2026-11-05: test IMSI replay advances

`simif-imsi` reached 1.03B without any observed SIM_Server state write; after accessing the test IMSI it attempted 6f78, 6f14 and 6fc6, all currently unsupported. No later SIM FIFO write was recorded through the budget. This is not proof the SIM is serving; run a longer compact replay to determine whether the firmware progresses after its timers. The diagnostic IMSI is synthetic, unit tests pass, and existing checkpoint and firmware are intact.

## 2026-11-05: EF_AD and test IMSI

`simif-admin` read the synthetic 4-byte EF_AD and next requested EF_IMSI (6f07); state 6/event 0x75 followed at 1,008,141,683 because that file was absent. Added a fabricated test-network IMSI (001010123456789), no real identity, and directed test. The SIM controller remains experimental; continue firmware replay and inspect actual requests and state, without assuming a successful network registration.

## 2026-11-05: location-file replay completed

`simif-loci` completed its 1.03B budget. Firmware selected EF_LOCI, sent GET RESPONSE, then selected unimplemented EF_AD (6fad); state 6/event 0x75 followed at 1,007,595,311. The current model only supports READ BINARY for LOCI at offset zero, which was not observed, so its usage is not established. Output: `build/sim/runs/boot-v15-simif-loci/`. Investigate and implement a standards-backed EF_AD test profile, test, then replay. Checkpoints preserved.

## 2026-11-05: next card file is location information

`simif-terminal-profile` passed the new TERMINAL PROFILE exchange, selected and read the synthetic SIM service table, then attempted EF_LOCI (6f7e), after which state 6/event 0x75 appeared at 1,007,205,449. Added a synthetic 11-byte unregistered location-information file with test. Continue replay; values and controller are experimental and serving state remains unconfirmed. TERMINAL PROFILE partial-transfer restore unit test passed after fixing the test setup.

## 2026-11-05: TERMINAL PROFILE is the next exchange

`simif-phase-sst` ran to 1.03B. After selecting and reading EF_PHASE the firmware sent A0 10 00 00 09 (TERMINAL PROFILE); the card did not implement it, and no subsequent SIM commands or state writes were observed. Implemented bounded card-side T=0 acceptance of its profile bytes followed by 9000, with checkpointed partial transfer state and a restore unit test. This synthetic no-services card does not implement proactive SIM toolkit commands. Rebuild and firmware validation next; checkpoints intact.

## 2026-11-05: PIN-disabled profile asks for additional files

`simif-pin-disabled` moved beyond state 3 PIN wait and reached state 6/event 0x75 at 1,006,256,883. Before failing it selected 6fae (SIM phase) and 6f38 (SIM service table), previously unimplemented. Added synthetic phase 3 and a conservative all-zero 16-byte service table, plus unit tests; these are test profile values, not extracted from a real card. Continue replay and identify required services rather than assuming they are all absent. The implementation is isolated and not yet a working virtual SIM.

## 2026-11-05: simulated card reaches PIN wait

`simif-language` confirms firmware GET RESPONSE and READ BINARY on the new EF_LP; it then enters state 3 at 1,005,547,111 with event 0x72. `docs/modem-model.md` identifies state 3 as PIN wait. The test card advertises CHV1 enabled, consistent with this result. ETSI TS 51.011 byte 14 bit 8 describes CHV1 disabled; changed the synthetic test profile to advertise disabled PIN (0xb0) and added assertions. This models a card with PIN disabled rather than bypassing firmware; replay and actual serving state remain to be verified. Unknown SELECT 7f40 still returns file-not-found.

## 2026-11-05: complete DF response advances the SIM

The card incorrectly returned 9f0f for a directory while claiming nine additional bytes. ETSI TS 51.011 specifies directory information through byte 22 including CHV status. Corrected directory SELECT response length to 0x16 and provided 22 synthetic STATUS bytes with test CHV counters. Unit test passes. `simif-full-df` confirms firmware requests STATUS length 0x16, advances beyond former state-6 event and tries files 6f05 and 7f40; it reaches SIM_Server state 3 with event 0x72 at 1,005,241,504. State meaning and eventual service not yet established. 6f05 is DF GSM language preference; adding it as a synthetic English file with unit test. 7f40 remains unimplemented/unknown, and no generic success is fabricated. Standard: https://www.etsi.org/deliver/etsi_ts/151000_151099/151011/04.14.00_60/ts_151011v041400p.pdf. Preserve checkpoints and continue focused replay after rebuild.

## 2026-11-05: traced state-6 decision to parsed STATUS fields

`simif-status-first-compare` captured the first STATUS; compared with `simif-get-response` final STATUS. The latter reaches 0x51510518, reads zero from parsed object byte +25, chooses R5=0, writes 0 to 0x800ce375, and eventually 0x5150bb8e emits event 0x75. This localizes the decision; the meaning of byte +25 and whether it should be nonzero remain unproven. The parser at 0x5151515a derived +25 from bit 7 of receive-buffer offset +21 (0x8001103d), which was zero. The modeled STATUS supplies only 15 information bytes, yet claims nine additional directory bytes in byte 13, and a raw procedure byte is also copied into the receive buffer. Investigate standards-compliant DF response length, firmware requested length and procedure-byte handling before changing it: do not simply force the flag or bypass failure. No simulation is currently active; both comparison traces and checkpoints remain available.

## 2026-11-05: SIM continuation replay completed

`simif-ecc-long` completed its 1.15B cycle budget from the preserved 1B checkpoint. The only observed SIM state transition was state 6 at 1,004,519,349 with parameter 0x75; the last observed SIM command was STATUS at 1,004,246,028 and no later SIM FIFO writes were logged. No working card is demonstrated. Run output: `build/sim/runs/boot-v15-simif-ecc-long/`. Next compare final STATUS handling with the earlier successful STATUS to isolate event 0x75; preserve checkpoints.

## 2026-11-05: GET RESPONSE advances card initialization

`simif-get-response` replayed 1B–1.010B after adding a synthetic transparent EF GET RESPONSE (A0 C0) and a directed unit test, which passed. Firmware now reads the 3-byte EF_ECC after GET RESPONSE, then issues STATUS; SIM_Server still enters not-serving state 6 at 1,004,519,349 with event parameter 0x75. This proves progress through an additional real firmware exchange, not a functioning SIM. File metadata and the controller interrupt/FIFO timing remain experimental. Next compare subsequent activity through 1.15B, and trace the final STATUS result and event generation against the earlier successful STATUS rather than masking the failure. Full trace: `build/sim/runs/boot-v15-simif-get-response/`; checkpoint and input firmware preserved.

## 2026-11-05: voltage class advances synthetic SIM; GET RESPONSE missing

The initial synthetic DF STATUS advertised only 5V; related Nokia hardware supports 1.8/3V. Setting GSM voltage-class bits 0x30 changed the observed initialization failure from event parameter 0xc6 and let firmware select MF, read ICCID, and select optional EF_ECC (6fb7). Added synthetic ECC and correct separate current-directory tracking. `simif-ecc-voltage` then showed two GET RESPONSE (A0 C0, length 15) commands, which the card did not implement; SIM_Server still reached not-serving state 6 at cycle 1,004,562,215. Added a synthetic transparent-EF GET RESPONSE for ECC/ICCID; testing is pending. This is an experimental card/controller, not a validated real SIM or resolution of other boot failures. Earlier event and receive-classification conclusions remain qualified below. Original 1B checkpoint and firmware remain intact.

## 2026-11-04: correction on receive classification

Re-examined handler 0x51635c20 and downstream behavior. It writes byte 0x0b to 0x800ca048 when the first received value is neither 0x60 nor in the 0x6x/0x9x ranges; earlier notes called 0x0b an error, but its exact meaning is unverified. In the bridge run the 0xa4 procedure echo takes that branch and the firmware subsequently sends the SELECT file ID, so classifying 0x0b as necessarily fatal is not justified. What is proven is that the overall bridge STATUS path later transitions SIM_Server to not-serving state 6. SIMIF status 0x04 invokes transmit routine 0x51635e14, 0x08 invokes setup/notification routine 0x51635d28, and 0x10 invokes the registered receiver. The earlier simple ACK-swallow test stalled; determine exact 0x04/0x08/0x10 sequencing and whether 0x0b is normal data/procedure notification versus error by tracing how firmware consumes the resulting message. Do not label it an error without that evidence.

## 2026-11-04: bridge restored and related UPP/UEM reference

`simif-bridge-restored` reproduced SELECT DF GSM and STATUS then state 6 at 1,002,885,853 after reverting the ACK-consumption experiment; thus the tested card bridge is restored, but still fails initialization. A Nokia 7650/NHL-2 service manual for related UPP_WD2 + UEM hardware describes SIM I/O/clock at UPP and SIM power/reset/card-detect at UEM, with UPP–UEM interaction (https://electronicsandbooks.com/edt/manual/Hardware/N/Nokia/Phone/7650/11-nhl2-trouble%20%5B148%5D.pdf, SIM card section). This is primary Nokia documentation for a related device, not proof of N-Gage register mapping. It reinforces checking UEM SIMIF power/reset/card-detect and UPP/controller interaction, rather than modeling only an APDU responder. Exact register bits and T=0 ACK handling remain unresolved. No new cardless or long boot was run; active binary is idle and all original checkpoints remain intact.

## 2026-11-04: controller ACK-consumption hypothesis rejected

`simif-ack-consume` tested swallowing the card's T=0 instruction echo and raising only the hypothesized transmit/setup status. Firmware sent SELECT header `a0 a4 00 00 02` but never sent its two file-ID bytes through the 1.006B budget. In comparison, exposing the echo led it to send 7f20 (though the parser marked echo 0xa4 as error). Therefore simple controller-side swallowing without an additional modeled completion is insufficient; it does not establish that physical hardware exposes the echo as ordinary data. Reverted the experimental swallow logic to the previous bridged card model; isolated rebuild required. The FIQ setup handler now raises receive-ready only when the checkpointed card output queue has bytes, avoiding a false empty-FIFO signal. Next trace how transmit/procedure acknowledgement should advance firmware without queuing error 0x0b; inspect actual firmware ISR status bits and test the exact event sequence rather than using generic success. Original checkpoints are safe.

## 2026-11-04: tested T=0 card connected to isolated SIMIF bridge

Connected `scratch/simif-investigation/test_card.h` to `scratch/simif-board/board/boot_profile.cpp`: guest FIFO writes feed the synthetic card and output is made available via the experimental SIMIF status/interrupt path. Card selected file, partial APDU header and pending output are snapshotted in reserved entries of the existing checkpointed map; the card unit test now covers save/restore mid-command. The isolated build manifest hashes the card header. `simif-card-bridge` replay from 1B to 1.004B produced real SELECT of DF GSM, but raw card STATUS procedure byte 0xf2 was exposed to the firmware receive parser; that parser marked it error 0x0b and SIM_Server entered state 6 at 1,002,885,853. The raw SELECT procedure byte 0xa4 was likewise seen by that parser and marked 0x0b, even though the earlier counterfactual exchange continued; previous progress through command writes must not be mistaken for accepted transactions. This identifies the next controller gap: T=0 procedure-byte handling and delivery/interrupt ordering between the card and firmware. No claim of a complete SIM; do not substitute the counterfactual status-first probe in the actual card model. Original firmware, C image and billion-cycle checkpoints were preserved. Next investigate firmware/UPP handling of T=0 ACK and response bytes, unit-test bridge FIFO/interrupt and checkpoint behavior, then replay. `test_card_test.cpp` including snapshot restore passed under jotego/simulator:arm64.

## 2026-11-04: separate diagnostic GSM card model and tests

Added `scratch/simif-investigation/test_card.h`, a standalone synthetic T=0 card prototype separated from the unverified SIMIF transport. It implements the observed SELECT, DF STATUS and ICCID READ BINARY exchanges, tracks selected 0x3f00/0x7f20/0x2fe2, returns errors for unknown files/commands and uses fabricated ICCID and metadata. `test_card_test.cpp` passes under jotego/simulator:arm64, covering procedure bytes, data/status, selection, unsupported file and reset. Its output order is card-side T=0, not proof of the N-Gage controller's FIFO order; it is not yet connected to a firmware boot. The current staged board still uses the counterfactual 9f 0f status-first probe and generic file success; do not mistake it for this card model. Next implement and test the controller transport (procedure-byte consumption, status ordering, FIFO, interrupt timing) between this card and firmware, then replace the diagnostic generic-success experiment and compare boots. Preserve all checkpoints.

## 2026-11-04: counterfactual status-first probe reaches ICCID read

`simif-status-first` shows a diagnostic 60 9f 0f response avoids the immediate state-6 failure and leads firmware to issue another SELECT. This is a counterfactual probe, not a verified GSM STATUS response or evidence of SIM success. Extended only `scratch/simif-board` to recognize successive SELECT headers and capture arbitrary requested file IDs, with the same generic synthetic 9f 0f response; this incorrectly treats unknown files as available and is diagnostic only. `simif-multi-select` ran to 1.01B without a selected SIM state write: after DF GSM 0x7f20, firmware selected MF 0x3f00, selected EF 0x2fe2 (ICCID), then issued READ BINARY `a0 b0 00 00 0a`. The model does not implement B0, so the exchange stops there. `simif-iccid-read` captured the next operation; firmware prepares a 13-byte receive expectation and flag 0x800ca164=1. Actual procedure-byte, 10-byte ICCID data and trailing status ordering must be resolved before implementing a realistic response. Restored the original 18-byte synthetic DF fixture for the existing unit test and separated the three-byte probe; fixture test passes. Original firmware and checkpoint untouched. Next implement a test-card APDU/file state machine with explicit unknown-file errors and standards-backed EF ICCID data and T=0 procedure handling; replace generic success and validate via unit tests before long boot comparison.

## 2026-11-04: STATUS firmware expects a status-class first byte

The full `simif-rx-fifo-drain` trace shows that after it skips 0x60, firmware reads the synthetic first STATUS-data byte 0x00 at cycle 1,002,620,503; with flag 0x800ca164=1, handler 0x51635c48–0x51635c84 accepts a first non-null byte whose high nibble is 0x6 or 0x9, and stores error 0x0b for 0x00. Thus the previously modeled direct data ordering is incompatible with this firmware path. This is an observation of firmware expectations, not proof of actual SIM bus order or that the whole STATUS result should be status-only. Testing a strictly diagnostic counterfactual response 60 9f 0f to determine whether firmware then requests response data; this temporarily replaces the isolated fixture only, and is not asserted as a compliant STATUS transaction. Keep the 15-byte fixture in prior git history/scratch trace and reconstruct it before normal operation. No changes to maintained phone model or original checkpoints.

## 2026-11-04: state 6 confirmed failure; FIFO hypothesis still incorrect

The state-6 trace confirms firmware event 0x70d/parameter 0x75, with not-serving handler 0x3114 (see modem-model.md), so the earlier state change is not a successful SIM. Event 0x75 follows SIM_SUBSYSTEM internal event 0x15, with command byte 0xf2. The experiment `simif-status-rxonly` stopped generating repeated 0x08 setup events but still entered state 6 at cycle 1,002,990,777; it also produced excess zero FIFO reads and an underflowing firmware receive counter. `simif-rx-fifo-drain` clears pending receive-ready when synthetic bytes run out; it still enters state 6 at 1,002,885,849, and its full window shows 19 SIMIF reads for an 18-byte diagnostic stream. Thus neither change fixes the protocol. The first response byte 0x60 is skipped by firmware while it initially expects 18 data bytes; a FIFO-empty read supplies an artificial zero. Do not continue a long boot or assume these experimental timings are correct. Next decode how the SIMIF 0x08/0x10 events, expected-byte count 0x800ce954 and outstanding length 0x800c9f24 evolve for STATUS; design a bounded FIFO where the firmware cannot read nonexistent bytes and only signals actual thresholds, then re-test and compare state. Keep source changes isolated, all checkpoints preserved, and retain the shorter causal traces.

## 2026-11-04: state 6 is not-serving; repeated setup events are suspect

`simif-state6-cause` captured event 0x70d/parameter 0x75 selecting transition row 0x516e135c, writing SIM_Server state 6 and not-serving method 0x3114. Existing `docs/modem-model.md` already identifies state 6 as initialization failure (status 0xfc), not a serving card. Trace `simif-event15-origin` follows 0x75 to SIM_SUBSYSTEM/Sim_upl.c event 0x1e generated after internal event 0x15; the failing operation concerns command 0xf2. Crucially, `simif-status-waitbyte` shows our experimental model raises status 0x08 before every two received bytes, and handler 0x51635d28 queues the constant object 0x516d508c (event code 7) repeatedly. Those code-7 events precede event 0x15 and failure; a causal connection still needs testing. Modified only the isolated SIM model so later FIFO batches raise receive-ready 0x10 without reasserting 0x08; test against the original 1B checkpoint before treating this as correct. Superseded select-procedure and select-rx-sequence run directories were moved to Trash; their findings and newer traces are retained.

## 2026-11-04: diagnostic SIM comparison reached state 6

`simif-status-state-check` completed its 1.15B budget without a reported stop; 13MB run directory. The selected SIM_Server state-write probe recorded state 6 at cycle 1,003,406,951, whereas the original cardless run recorded state 5 at cycle 1,140,847,072. No state-5 write was observed by these selected probes through 1.15B. State 6's meaning and whether this state persists must be established; do not claim it means a serving SIM or that the Insert SIM screen has disappeared. The synthetic model responded to SELECT and two STATUS commands and no later SIM TX bytes appeared in the captured bus trace. Original billion checkpoints and cardless baseline are intact. Next decode state 6 via firmware state table, identify missing commands/data and run a longer screen comparison once the test-card protocol is sufficient; retain full provenance.

## 2026-11-04: diagnostic SIM phone comparison running

Started `simif-status-state-check` from the preserved 1B baseline checkpoint through 1.15B using the isolated phone board with synthetic SELECT and repeat STATUS responses. Selected PCs cover retry counter and SIM_Server state transition; compact trace enabled. Compare against baseline state 5 at cycle 1,140,847,072 and watch output size. Command: `python3 scratch/simif-board/run.py 1150000000 simif-status-state-check '' 0 unused restore=/work/build/sim/checkpoints/roll-current-tlbhold-20b-r1000 pc-log=0x51514570 pc-log=0x51513d76 pc-log=0x5159c01c pc-log=0x5159c020 pc-log=0x5159c028`. This is an experimental test card, not proof of faithful controller behavior. Preserve all checkpoints and active binary; after the run determine actual SIM state and next unhandled exchange before planning a full screen comparison.

## 2026-11-04: repeat STATUS supported and fixture test added

`simif-status-repeat` completed its 1.02B-cycle budget. Firmware sent a second `a0 f2 00 00 0f`; `simif-status-second` confirmed the receive setup and callbacks read the synthetic reply again. No later SIM transmit command appeared in the compact bus trace through 1.02B; this does not establish why or whether the card was accepted. No state-5 conclusion can be drawn before the original 1.14B transition. Added `scratch/simif-board/board/simif_status.h` for the explicit diagnostic DF GSM fixture and `scratch/simif-investigation/status_test.cpp`; a directed build/test in jotego/simulator:arm64 passes, and the isolated build manifest now hashes the fixture. The repeat response, ISO wait-byte handling, FIFO thresholds, and control-register completions remain hypotheses; this is not a complete or default SIM. Next trace firmware handling and event completion after the second STATUS, compare against standard lengths/fields and trace the first missing response; run compact bounded checkpoints rather than another blind long simulation. Preserve all billion-cycle checkpoints.

## 2026-11-04: isolated SIM STATUS response modeled

Implemented an isolated, synthetic response for observed `a0 f2 00 00 0f` in `scratch/simif-board`: 15 bytes of DF GSM metadata and 90 00, delivered with provisional two-byte FIFO/interrupt behavior. ETSI GSM 11.11 v5.3.0 section 9.2.2 defines STATUS as returning the selected MF/DF information; section 9.2.1 defines the directory fields (https://www.etsi.org/deliver/etsi_gts/11/1111/05.03.00_60/gsmts_1111v050300p.pdf). The values and controller timing describe a synthetic card, not a phone dump. `simif-status-response` initially delivered F2 as received data, which firmware treated as an error; `simif-status-data` removed it and delivered metadata and status, with an extra trailing byte. `simif-status-waitbyte` tested a 0x60 wait byte followed by the 17 metadata/status bytes; firmware reads all and issues another STATUS at cycle 1,002,949,434. Whether that is normal polling or a retry is unresolved. Model now allows repeat STATUS and needs a bounded continuation with selected-PC and compact tracing. No working SIM or validated hardware behavior is claimed.

## 2026-11-04: synthetic SELECT status advances to next SIM command

`simif-select-status` completed through 1,005,000,000 cycles. In the isolated experimental SIM model, after header `a0 a4 00 00 02`, diagnostic procedure 0xa4, and file identifier 0x7f20, the test injects speculative response `9f 0f`. Firmware read both response bytes at cycles 1,002,474,779 and 1,002,475,098 and then issued the next five bytes `a0 f2 00 00 0f` starting at 1,002,614,311. This is progress through real firmware control flow but does not prove the response represents a real card or that SIM initialization succeeds. The model only recognizes this one transaction and cannot complete the next command. All SIMIF control completion, interrupt sequence and card bytes remain experimental in `scratch/simif-board`, not the maintained model. Next decode firmware consumer/expected payload for the 0xf2 command, find reliable reference for SIM file contents and response semantics, add an explicit test-card state machine and directed tests, then replay with compact tracing. `build/sim/runs/boot-v15-simif-select-status/` contains the full <1M-cycle window. No long simulation is currently active.

## 2026-11-04: SIM SELECT reaches file identifier under diagnostic hypotheses

`simif-select-rx-control` tested two additional isolated hypotheses: signal receive-setup status 0x08 then received-data 0x10, and clear control bits 0x39 after writing 0x7e to SIMIF+0x06. Firmware executed receive handler and read the synthetic procedure byte 0xa4 at cycle 1,002,384,196, then wrote bytes 0x7f 0x20 at cycles 1,002,469,259 and 1,002,469,418. Alongside the observed `a0 a4 00 00 02` header this is consistent with SELECT of file 0x7f20. This is an experimental synthetic exchange, not proven hardware behavior or a working card. Next provide a clearly labeled diagnostic status response and trace the next firmware request; implement card contents and protocol only after their requirements are established. Run `simif-select-rx-control` and the baseline are preserved; no original checkpoint was modified.

## 2026-11-04: SIM procedure-byte experiment and second control wait

`simif-select-procedure` recognized only the observed SELECT header and injected a synthetic 0xa4; the real SIM receive callback ran, but its expected-byte counter was still zero and it did not read the byte. Isolated `simif-select-rx-sequence` hypothesized status bit 0x08 before 0x10, making the firmware enter its receive setup handler 0x51635d28. That handler writes 0x7e to SIMIF+0x06 and loops while bits 0x39 remain set; the generic latch returns 0x7e forever. Therefore it never reached the receive callback. This is a second missing control-operation behavior, not proof that the guessed 0x08/0x10 sequence or procedure byte is hardware-accurate. Testing a separate isolated completion hypothesis for 0x7e; retain the trace and baseline, and avoid claiming a working card.

## 2026-11-04: SIM control completion exposes first card command

`simif-control-complete` ran from the original 1B checkpoint through 1,003,600,000 with an isolated, explicitly speculative control-register completion: after firmware writes 0x79 to SIMIF+0x06, bits 0x3a clear on the following read. The firmware leaves its former tight loop and writes five successive bytes `a0 a4 00 00 02` to SIMIF+0x0c at cycles 1,002,378,124–1,002,378,760. This is consistent with an ISO 7816/GSM SELECT FILE command header; the target file and card response have not yet been observed. No card response or complete SIM protocol is modeled, so this is not a functioning SIM. Control-bit timing and semantics remain hypotheses and are restricted to `scratch/simif-board`. Next decode how firmware expects the procedure byte and sends the two file-id bytes, then build an isolated test-card transaction state machine and compare the callback and subsequent traffic. The full trace is in `build/sim/runs/boot-v15-simif-control-complete/`; original firmware and checkpoints are unchanged.

## 2026-11-04: resumed at SIM interface busy wait

The earlier `simif-atr-softirq-cont` run was deliberately stopped at about 1,056,112,846 cycles (no result.json) because it was endlessly polling and producing large logs. Full short trace `simif-atr-softirq` shows firmware writes 0x79 to SIMIF+0x06 at 1,002,357,443, then loops at PC 0x5152521a while `(SIMIF+0x06 & 0x3a) != 0`. Our generic RW latch returns 0x79 indefinitely; evidence indicates missing peripheral completion but does not establish what actual hardware does or correct timing. The 800K short trace preserves the first occurrence. The 80MB stopped run only repeats that read; move it to Trash before the next experiment, preserving all checkpoints. Test a clearly labeled isolated hypothesis in which the relevant written control bits clear on a later read, then inspect the next real firmware request; do not apply this assumption to the maintained board without supporting evidence.

## 2026-11-04: ATR plus software-interrupt continuation running

Phone flash regression passed after maintained-board 0x2000 change. Started isolated `simif-atr-softirq-cont` from original 1B checkpoint to 1.15B with the same PC probes used for the earlier ATR-only comparison. Full command: `python3 scratch/simif-board/run.py 1150000000 simif-atr-softirq-cont '' 0 unused restore=/work/build/sim/checkpoints/roll-current-tlbhold-20b-r1000 pc-log=0x515250a0 pc-log=0x51525570 pc-log=0x51514570 pc-log=0x51513d76 pc-log=0x5159c01c pc-log=0x51635b88 pc-log=0x51635c20`. Inspect result and compare retry counter, state 5 and SIMIF exchanges with `simif-atr-continuation`. The synthetic SIMIF model remains isolated and incomplete. Preserve all original checkpoint pairs; do not rebuild the isolated binary while this run is active.

## 2026-11-04: second NOS software interrupt delivers ATR callbacks

The isolated `simif-atr-softirq` replay confirms the 0x2000 hypothesis: after adding set/clear handling, queued 0x51525395 executes at cycle 1,002,172,575 and 0x51525575 at 1,002,192,484; the firmware clears 0x2000 at 1,002,212,101. With no 0x2000 model these callbacks never ran in the 800K-cycle comparison. Applied corresponding provisional 0x2000 set, clear and checkpoint-restoration status mask to the maintained phone simulation alongside the existing 0x1000 mechanism. This is an evidence-backed simulation fix, not a verified hardware specification. Next run existing board test and extend isolated ATR run to 1.15B; inspect whether it stops retrying and which SIM exchanges follow. No default SIM has been added.

## 2026-11-04: synthetic ATR schedules work on unmodeled 0x2000 software interrupt

`simif-atr-follow` replay traced 800K cycles after response. The initial FIQ queues two NOS callbacks (0x51525395 and 0x51525575) into 0x80025878 and 0x8002588c; neither executes in the captured interval. At cycles 1,002,164,353 and 1,002,166,415 enqueue code writes 0x2000 to UPP IRQ enable-set VA 0x58150012. The firmware IRQ table 0x516cddf8 has an entry with status 0x58150100, clear 0x58150010, set 0x58150012, mask 0x2000; our existing provisional software-interrupt model only raises bit 0x1000, dropping this distinct queue signal. This is evidence for a second software interrupt, not yet proven to drain these callbacks. Experimentally extended only the isolated board to raise and clear bit 0x2000 like 0x1000 (including status serialization mask); rebuilding and replaying to check callback execution. Do not change the maintained board until behavior is demonstrated.

## 2026-11-04: ATR-only experiment still fails SIM initialization

`simif-atr-continuation` completed at 1.15B. Despite the isolated 3b 00 delivery observed in the short replay, selected trace shows the same code-0x11 retry counter reaches 2, 3 and 4 and the SIM_Server state is set to 5 at cycle 1,140,847,249, essentially the cardless timing. Therefore the injected response alone does not produce a serving SIM. Later scheduled ATR-processing callbacks and/or the next hardware/protocol step did not yield a successful initialization; precise reason unproven. Compare queue execution and retry timer, and trace response processing using another <1M-cycle full window. Do not claim the SIM model is functional. Isolated board/binary and run logs preserved; original firmware, C image and checkpoints unchanged.

## 2026-11-04: isolated ATR continuation in progress

After the register-priority change, existing `sh tests/phone/flash/sim.sh` passes. Started `simif-atr-continuation` from the original 1B checkpoint to 1.15B using the isolated SIMIF binary, compact bus log and selected SIM callback/state PCs; original C, firmware and checkpoint remain untouched. Command: `python3 scratch/simif-board/run.py 1150000000 simif-atr-continuation '' 0 unused restore=/work/build/sim/checkpoints/roll-current-tlbhold-20b-r1000 pc-log=0x515250a0 pc-log=0x51525570 pc-log=0x51514570 pc-log=0x51513d76 pc-log=0x5159c01c pc-log=0x51635b88 pc-log=0x51635c20`. On completion inspect result and selected PCs and compare SIM state, subsequent reads/writes, retries and stop with the cardless baseline. This is a 3b 00 synthetic ATR experiment only; model does not yet implement a real SIM protocol. Isolated build source/binary must not be modified while running.

## 2026-11-04: synthetic SIM ATR reached firmware callback

The isolated `simif-atr-statusfix` replay reaches FIQ source 26 and invokes the real registered SIM reset callback at cycle 1,002,162,244. The firmware reads the two diagnostic bytes 3b 00 and stores them at VA 0x800c9f28–29. This proves the experimental path can deliver a synthetic reset response to firmware; it does not yet show a working SIM or later boot. The prior probe stalled because a generic ICU handler shadowed the dedicated FIQ fast-status handler. After successful isolated replay, applied a narrowly scoped handler-priority fix to maintained `scratch/current-boot/board/boot_profile.cpp`: exclude 0x0c120050 from the generic ICU handler only when the existing FIQ model is enabled. CPU RTL and default cardless behavior otherwise unchanged. No active baseline binary is altered; rebuild is required. Next run board regression and continue the isolated SIM experiment beyond the two-byte response, inspect firmware processing and further peripheral traffic. Preserve original 1B and all other checkpoints.

## 2026-11-04: correction — fast status handler is shadowed

The `simif-atr-probe` compact `bus.tsv` DOES show 0x0c120050 reads returning 7 from `assumed_icu_bank`; the earlier statement that no external access was observed was incorrect (the short window log omits those bus rows). The generic ICU-bank handler in `boot_profile.cpp` intercepts 0x0c120050 before the dedicated FIQ fast-status handler, so the previous write of 7 is incorrectly read back. This is a board model priority bug, not evidence of a CPU cache bug. In the isolated `scratch/simif-board` copy, excluded 0x0c120050 from the generic handler to let the existing dedicated status handler run. Rebuilding and repeating the ATR probe; do not change the maintained board until tested. Preserve original run and checkpoints.

## 2026-11-04: isolated ATR probe reached FIQ but exposed a new blocker

Built a separate diagnostic board and binary under `scratch/simif-board/` and `build/sim/obj-simif-board/`; the maintained board and original checkpoints are unchanged. It experimentally injects synthetic 3b 00 when SIMIF+0x08 is written 1, asserts FIQ source 26 and offers provisional status/FIFO handling; this is not a verified card or physical timing model. `simif-atr-probe` replay from the preserved 1B checkpoint to 1.003B shows the ARM takes FIQ at cycle 1,002,160,531, so the source can reach the CPU. It does NOT reach the SIM callback: the kernel FIQ dispatcher repeatedly reads 7 from VA 0x58120050 and loops through the fast-status path. No corresponding external access was observed in the captured bus window, suggesting a cached/stale read; verify the page attributes and cache/write-buffer state before concluding. The earlier generic model expects this status to read zero but the CPU sees 7. This experiment is a failure, not a working SIM. Next investigate why 0x58120050 reads 7 and fix or isolate the actual mapping/cache/model error before retesting the SIM interrupt; do not hide the condition by patching firmware. Unit model remains provisional. Re-run from the original 1B checkpoint after correction, preserving the experiment trace.

## 2026-11-04: SIMIF fast source 26 and diagnostic model

`simif-fast-dispatch` completed at 1.003B. In the full first-attempt trace, firmware registers dispatcher 0x514c0a6d on interrupt object 0x804058a8, whose source value is 0x1a; at cycle 1,001,787,824 the kernel writes bit 26 (0x04000000) to physical FIQ enable 0x0c1201c8. The dispatcher scans registered callbacks against their descriptor's status and enable registers; SIM uses 0x0c1500b8 bit 4 and 0x0c15000a enable. This ties the SIM callback to FIQ source 26; exact peripheral event timing and ACK semantics are hypotheses.

Added isolated `scratch/simif-investigation/simif.h` and `test.cpp`, an explicitly provisional event/FIFO/masking model, not yet connected to the board or firmware. A unit test in jotego/simulator:arm64 passes using synthetic diagnostic 3b 00 bytes, checking initial cardless state, event and source 26, masking, ACK and FIFO order. These tests validate the experiment's own behavior, not hardware equivalence or a bootable card. Next integrate opt-in in a separate board/build copy, implement FIQ source 26 with coexistence of source 3 and compatible pending/current registers, register byte lanes and group-enable behavior, then run a short checkpoint replay with live probe of the reset-response callback. Keep baseline unchanged and preserve all checkpoints.

## 2026-11-04: SIM callback uses FIQ registration

The firmware's source-file string for registration routines 0x514c14b0/0x514c1524 is `../../ENOS/CMT_SW/CORESW/HWDRV/Hw_fiq.c` (VA 0x516ced90). The observed initial SIM callback 0x515250a1 is installed in FIQ callback slot 1 with descriptor index 8. This is stronger evidence of a FIQ path than earlier generic IRQ wording; the exact outer ICU source and dispatch still need tracing. The current board drives CPU FIQ only from `unit60_fiq()` in `scratch/current-boot/board/main.cpp`; it does not model a SIMIF FIQ. This is an actionable omission, but simply driving FIQ without the correct ICU pending bit/source and acknowledge semantics would be unreliable. Disassemble the shared fast-interrupt dispatcher and descriptor setup before implementing the opt-in ATR experiment.

## 2026-11-04: initial SIM answer-to-reset callback identified

`simif-registration` completed at 1.003B. The earlier full first-attempt trace confirms at cycle 1,001,785,980 registration routine 0x514c1524 receives slot 1, callback 0x515250a1 and descriptor index 8. That callback, not 0x51635b89, is the first-attempt handler; the latter is a later replacement path. Firmware sets the receive count at 0x800c9f24 to 2, and callback 0x515250a0 tests SIMIF status bit 0x10 and reads that number of bytes from the SIMIF receive helper, then schedules further processing. The first callback is never triggered in the unmodified baseline. This strongly suggests the immediate experiment should provide a diagnostic two-byte answer-to-reset and assert the SIMIF status/IRQ, but the exact card bytes, FIFO behavior and outer ICU source still require explicit validation. No SIM model change has yet been made. Next trace outer IRQ routing and implement the experiment opt-in, preserving cardless default and checkpoint safety.

## 2026-11-04: first two SIM attempts fail before any SIMIF interrupt

`simif-irq-attempts` completed at 1.05B. Selected retirement probes saw the code-0x11 path and counter increments to 1 at 1,001,753,828 and 2 at 1,048,244,313, but no selected SIMIF status handler, receive callback, send handler or bit-8 handler in this interval. This is limited to selected PCs and the 1B–1.05B window. Each failure precedes that attempt's subsequent SIMIF setup. The original compact trace shows the same register sequence repeating around 1.002B and 1.048B.

The NOS initialized interrupt descriptor table (ROM 0x51712ad4 / RAM 0x8000888c; 20 bytes per entry) has entry 8 = status VA 0x581500b8, enable/disable registers VA 0x58150008/0x5815000a, mask 0x04. Firmware IRQ registration routine 0x514c14da–0x514c1500 matches status address and mask to a descriptor, then 0x514c1524 registers a callback using its table index. This independently matches the SIMIF helper polling status 0x581500b8 bit 4. Do not assume set/clear polarity without further evidence; locate the boot-time registration and enable sequence and verify which ICU source carries this group. The callback may be registered via RAM pointer 0x80009570, initialized to 0x51635b89, as seen at 0x515255ee; this call site is conditional and not yet observed during initialization.

## 2026-11-04: SIMIF interrupt probe running

Started `simif-irq-attempts` from matching 1B checkpoint to 1.05B with compact bus trace and selected PCs for the SIMIF status handler, receive callback, two other interrupt branches and the earlier state/counter PCs. Command: `python3 scratch/current-boot/run.py 1050000000 simif-irq-attempts '' 0 unused restore=/work/build/sim/checkpoints/roll-current-tlbhold-20b-r1000 pc-log=0x51635b88 pc-log=0x51635c20 pc-log=0x51635d28 pc-log=0x51635e14 pc-log=0x51514570 pc-log=0x51513d76`. Inspect `build/sim/runs/boot-v15-simif-irq-attempts/` when complete; identify whether any handler runs and correlate with bus and firmware return paths. Preserve its inputs and original checkpoints. This is observational, not a SIM fix.

## 2026-11-04: SIMIF receive callback and status path identified

Further NOS disassembly and the first-attempt trace identify an actionable boundary. At 1,001,790,652 the firmware stores callback 0x51635c21 at VA 0x800ce950. Handler 0x51635b88 collects SIMIF+0x00 status and branches on bit 0x10 through that callback; callback 0x51635c20 reads incoming halfwords from SIMIF+0x0c into its buffer. Bit 0x04 invokes buffered transmission at 0x51635e14; bit 0x08 invokes 0x51635d28. Status bits 0x23 take an error path. Helper 0x51635bec reads and acknowledges SIMIF+0x00 and repeats while physical 0x0c1500b8 bit 0x04 remains set. These are firmware-derived dispatch semantics, not verified complete hardware semantics. During the first initialization it registers the RX callback, polls status as zero, then enables/changes SIMIF+0x08; no RX invocation was observed in the traced 450K window. Next trace where 0x51635b89 is registered and how its IRQ is raised, then test a minimal, opt-in status/FIFO/interrupt model and explicit test-card response without changing the default cardless path.

## 2026-11-04: first SIMIF attempt replay complete

`simif-first-attempt` completed at its 1,002,200,000-cycle budget from the original 1B checkpoint; no display update expected in this short window. It reproduces the SIMIF setup, reads zero from 0x0c150800 twice, then writes 1 to 0x0c150808 at cycle 1,002,160,485. Register setup and the same later write repeat after each ~46M-cycle attempt. The trace does not yet establish the missing status or interrupt.

Static disassembly of the decrypted `build/firmware/thc/nos-image.bin` (mapped at 0x5149d280) shows code at 0x51635c3a reads halfwords at physical SIMIF+0x0c into a receive buffer, with special handling for bytes 0x60 and 0x6x/0x9x; code 0x51635e40 writes buffered bytes to SIMIF+0x0c. This is consistent with SIM/ISO 7816 traffic and independently strengthens the SIMIF identification; exact interrupt/status/FIFO and protocol timing remain to be determined. Prior +0x800 FBUS label should not be relied on. Next trace the SIMIF handler registration and interrupt/status paths, then build focused tests for a minimal card interface based on observed firmware expectations. Do not assert arbitrary bits or bypass the timeout.

## 2026-11-04: SIM interface candidate and first-attempt replay

The existing compact `sim-event-earlier` bus trace shows near-identical access sequences to physical 0x0c150800–0x0c150814 at cycles 1,001,791,445, 1,048,282,205, 1,094,455,652 and 1,140,676,700, about 46M cycles apart. The final sequence follows the counter crossing 3. The model currently treats this block as generic zero-reset read/write latches. A separate TriX hardware emulator describes SIMIF at ASIC11 CTSI base +0x800 (0x06010800; `scratch/references/TriX/plugins/TriX_HWemu/hwemu.c`); its CTSI offsets match several observed 0x0c150000-group registers and it labels +0x30/+0x32 sleep mode. This is evidence that our +0x800 block may be SIMIF, not proof of register equivalence on N-Gage. TriX's SIMIF handler is unimplemented, so it supplies no response semantics. An older `status.md` label calling this an FBUS/port block is not established.

Started `simif-first-attempt`, replaying the original matching 1B checkpoint to 1,002,200,000 and tracing cycles 1,001,750,000–1,002,200,000; run `python3 scratch/current-boot/run.py 1002200000 simif-first-attempt 1001750000:1002200000 0 unused restore=/work/build/sim/checkpoints/roll-current-tlbhold-20b-r1000`. Inspect `build/sim/runs/boot-v15-simif-first-attempt/` for response expectations and PC paths. No firmware or device behavior has changed. Preserve the existing paired checkpoints.

## 2026-11-04: SIM failure path has a retry counter

Re-examined the existing full `sim-event-earlier` trace without a new simulation. Immediately before the previously documented 0x70d/0x74 event, at cycle 1,140,593,885 the firmware increments byte VA 0x800c9998 from 3 to 4 at PC 0x51513d76. At 0x515137fa–fc it compares that byte with 3 and falls through only after exceeding 3; it then writes halfwords 0x0080 and 0x0200 to VA 0x58150032 and calls the flag-dependent failure routine 0x51515648. The path also records code 0x11 at VA 0x8001113b; the same trace shows it is loaded at 0x51514570 from byte +4 of ROM object VA 0x516d50ac (factory core offset 0x2d50ac), returned by the call at 0x5151453c. This identifies its immediate source but not the event semantics. This supports a repeated-attempt or failure counter, but the meaning of code 0x11, counter and peripheral writes remains unverified. Do not treat the counter as proof of SIM detection or force it. Next trace where code 0x11 originates and identify physical 0x0c150032 from schematics/manuals and board model; determine what earlier attempts waited for. The existing complete trace covers only the final attempt, so select an earlier checkpoint/window if needed. No model changes yet.

## 2026-11-04: cleanup before autonomous SIM work

Moved obsolete pre-fix run directories `boot-v15-current-c11-20b`, `boot-v15-current-flashfix-20b`, `boot-v15-current-fault-instrumented`, `boot-v15-current-fiqfix-20b` and `boot-v15-fault3650` to Trash; historical notes may reference their former paths. Their conclusions are recorded below. Current 11.928B run, SIM/Main investigation traces, live screen captures, all billion-cycle and near-fault CPU/host checkpoints were preserved. Trash still occupies disk space until emptied. Before later investigations, discard only clearly superseded large logs after recording findings, and never remove the billion-cycle checkpoint pairs.

## 2026-11-04: replay reached Main dialog

`app-main-late` replayed from `idle-c10692` to 10,809,000,000, including a complete 500K-cycle trace covering the first Main dialog frame at 10,808,369,344. The selected kernel termination probes saw only the already-known 10.692B and 10.701B entries, both exit type 0/reason 0; no 0x503338e4 panic-entry probe appeared during this suffix. The 10.701B object 0x804210d0 points at descriptor 0x8041ddcc, whose checkpoint bytes decode to `WatcherMainThread`, not simply `Main` (checkpoint predates the exit). This is not enough to explain the dialog; the crash may have happened earlier, follow a different path, or the notification may be delayed. No SIM/display causality established. Next trace the dialog/notification creation or examine earlier panic paths rather than claiming a cause.

## 2026-11-04: early Main-dialog candidates are ordinary thread exits

`app-main-reasons` completed its 10.702B budget, saved `idle-c10692.{cpu,host}` and captured the 10,692,311,244 termination. All four selected thread termination calls in 10B–10.702B passed exit type 0 and reason 0; they are not evidence of a Main panic. The 10.692B thread object 0x80422b70 points to name descriptor 0x8041f4c4, whose UTF-16 decodes to `MsvServer`. This is a checkpoint-based identification with normal cache/alias caveats. None of these calls alone explains the Main-app dialog at 10,808,369,344. Do not attribute that dialog to SIM or to these normal exits.

Next locate the dialog producer or associated process panic near the first displayed frame. The previous replay stopped at 10.702B, before 10.808B; retain its checkpoint and use focused PC probes or display trace to avoid tracing the whole interval. SIM investigation remains at `sim-flag-origin`: initialized flag copied as 1; no subsequent direct CPU write was observed through 1.15B.

## 2026-11-04: from-reset SIM flag and Main probes complete

The isolated `sim-flag-origin` run completed its 1.15B budget. Its selected CPU-store log shows one direct store to the watched flag word: at cycle 916,790,781 `0x503a733c` stores `0x000100bd` at VA 0x800092e4, setting byte 0x800092e6 to 1. This agrees with the original firmware's initialized-data source. No later direct store to watched addresses appeared through 1.15B; indirect aliases, unusual accesses and DMA are not ruled out. The flag is then read by the SIM path before 0x70d/0x74 -> state 5; its exact semantics and the correct hardware response remain unproven. Do not patch it.

`app-main-trace` from 10B completed its 10.85B budget and found four kernel thread-termination routine entries at cycles 10,534,533,806; 10,572,517,291; 10,692,311,244; and 10,701,176,616. The first observed “App. closed / Main” screen is at 10,808,369,344; selected entry PCs alone do not identify which thread or reason produced it. An additional bounded replay around the 10,692,311,244 event will capture thread object, descriptor and reason, plus broader selected panic-entry probes. Preserve all original checkpoints; do not assume this failure is caused by SIM.

## 2026-11-04: Main app closure trace

Confirmed the user's reported dialog first appears in `frame0025_cycle10808369344.png`: “App. closed / Main”; it also appears over the N-Gage splash in `frame0027_cycle10844464559.png`. This is earlier than the Insert SIM frame and ViewSrv 11 timeout; no causal relation is established. `app-main-trace` now replays from the preserved 10B checkpoint to 10.85B with selected kernel panic/termination PCs (0x503338e4, 0x503336d0, 0x50333ca4). Identify the panic time and use a short full trace to decode thread, category and reason; it may involve another process. The isolated from-zero `sim-flag-origin` trace continues separately. No hardware model or firmware behavior was changed.

## 2026-11-04: SIM-related flag has initialized value 1

Prior nosstarter disassembly documented a copy of 0x5790 initialized bytes from VA 0x51711138 to VA 0x80006ef0. The observed flag VA 0x800092e6 is offset 0x23f6 in that range, corresponding to image VA 0x5171352e. The current factory core byte at physical/image offset 0x31352e is 0x01; independent `build/firmware/thc/nos-image.bin` byte for the same VA is also 0x01. Thus the firmware image's initial value is 1, and nosstarter should copy it to the flag. This does not prove the runtime flag is never modified or what 1 means. The from-zero `sim-flag-origin` CPU-store trace remains active to verify the copy and later writes; DMA, aliases and dirty cache remain caveats. Do not change initialized firmware or force the flag.

## 2026-11-04: isolated SIM flag writer trace

`sim-event-earlier` traced the SIM non-serving event to a firmware-generated message: at cycle 1,140,594,391 routine 0x5151564c reads VA 0x800092e6 = 1, then sends internal message 0x1f; a chain maps that to 0x25d and 0x5150bb24 constructs event 0x70d/parameter 0x74, leading to state 5. The precise meaning and origin of the flag remain unknown. Static code at 0x51507084–86 clears it, but the setter has not been identified. Do not patch it or assert its meaning without tracing.

Built isolated diagnostic `scratch/sim-origin/` with unchanged CPU, firmware and board behavior, adding trace selection for CPU stores to 0x800092e4–e7. Its fresh from-zero `sim-flag-origin` run targets 1.15B cycles with the same C:/PMM and options; selected trace is `build/sim/runs/boot-v15-sim-flag-origin/instructions.tsv`, result alongside. This instrumentation only observes CPU stores and can miss writes through aliases, DMA or earlier cached state. Compare its 1B checkpoint and event against the original before trusting results, preserve both sets of checkpoints, and look up the setter/caller.

## 2026-11-04: SIM event producer narrowed

`sim-event-earlier` completed the bounded 1,140,000,000–1,140,711,000 window. At 1,140,619,970 firmware routine 0x5150bb24 explicitly constructs 0x74 and invokes 0x51615174; at 1,140,623,677 helper 0x5161576a stores that value into queued message VA 0x800267e4 for event 0x70d. The later trace shows SIM_Server receives it and writes state 5 at 1,140,847,072. The triggering firmware path passes internal code 0x25d into 0x5150b65c, then dispatches to 0x5150bb08; earlier execution constructs internal request 0x1f at 0x5151533c after testing flag VA 0x800092e6 = 1. The flag is also 1 in both 1B and 2B SDRAM checkpoints, though cached state must be considered. No conclusion yet about what sets the flag, what the underlying card interface reports, or whether its state is correct.

Next identify the setter and semantics of flag 0x800092e6 and trace the upstream device/startup path. Do not just patch the flag or event: a simulated present SIM must provide consistent initialization, status/identity and completion responses. The `sim-init-state` 2B replay and `sim-router` later replay have both completed; their billion-cycle checkpoints remain preserved.

## 2026-11-04: SIM failure event verified

`sim-init-event` replay captured the real event: the SIM handler receives event 0x70d and parameter 0x74 (exact cited instruction rows in `instructions.tsv` include 1,140,715,762/1,140,716,600). The transition matcher later selects table row 0x516e1410 and at cycle 1,140,847,072 stores state 5 to SIM_Server+8 (VA 0x800ca78c). This confirms the earlier table inference. The event parameter is read at 1,140,710,746 from a queued buffer at VA 0x800267e4, but it was already queued before the first captured window, and checkpoint SDRAM at that address contained stale-looking 0x55555555 rather than the CPU-observed 0x74; do not use RAM-only snapshots as cache-coherent evidence.

`sim-event-origin` replayed from `idle-c1140` with a 21K full window, but the producer predates that checkpoint. A new `sim-event-earlier` replay from the preserved 1B checkpoint captures the preceding 711K cycles (under one million) to locate the CPU store or hardware event that constructs 0x70d/0x74. No ROM, state, or active simulation input was altered.

## 2026-11-04: later SIM router window completed

`sim-router` replayed from 11,157,240,000 through the reproducible 11,928,098,499 shutdown. Selected instruction tracing at router resource-byte read 0x514bcea0 observed 2 executions with resource 0x1c and 6 with 0x3a; there were no selected hits for resource 0x09 or the SIM gate/IMSI/0x64 handler entry PCs in this suffix. The instrumentation logs architectural retirement at specific PCs, not all possible internal transports; absence is limited to these probes and this interval, not proof that the SIM is never queried earlier. The earlier `sim-init-event` replay remains active to trace the actual 0x70d->state-5 transition.

## 2026-11-04: SIM non-serving event found

The in-progress `sim-init-state` replay logged SIM transition routine 0x5159bfb0 at cycle 1,140,752,265 with event 0x70d. At 1,140,847,103 it loads the default method from table address 0x516e141c, which is +12 into row 11 at 0x516e1410 of the ROM state table; that row is event 0x70d, parameter 0x74, any prior state -> state 5, not-serving handler 0x3114. This is a table-address-based identification, not yet a captured full register trace of the parameter or originating hardware event. Checkpoint RAM independently shows state 1 at 1B and 5 by 2B.

A short bounded `sim-init-event` replay from the preserved 1B checkpoint is capturing cycles 1,140,700,000–1,140,860,000 and saving a nearby checkpoint. Determine the event's producer and the actual value at the state write; follow any SIM hardware command or status rather than patching the firmware state. The `sim-router` and `sim-init-state` diagnostics continue independently.

## 2026-11-04: trace actual firmware SIM state transition

Offline RAM inspection using `scratch/tools/inspect_checkpoint.py` found the documented SIM_Server singleton 0x800ca784 present with expected class/table pointers. Its +8 low byte is 1 (starting) in the preserved 1B checkpoint and 5 (non-serving) in the 2B, 3B, 5B, 8B and 11B checkpoints and near 11.157B. RAM snapshots may lag dirty CPU cache, and the exact timing remains to be traced, but these values support an in-firmware SIM initialization failure rather than evidence that the separate UART responder was queried.

Two independent read-only diagnostic replays are active: `sim-init-state` from the original 1B checkpoint through 2B logs SIM state-machine entry and state store PCs 0x5159bfb0/0x5159c01c/0x5159c020/0x5159c028; `sim-router` from `idle-c11157` through 11.928B logs in-process router resource reads and SIM server gate/response PCs. Monitor both; use results to locate the event/hardware source and actual resource 0x09 traffic. Their source and binary remain unchanged. The present-SIM IMSI fixture is tested under `tests/phone/sim_present`, but is not wired to the firmware and 0x64/0x61 still returns non-serving.

## 2026-11-04: first NOSDRIVER frame decoded

`sim-nosdriver-call` completed at cycle 11,157,560,000 with full micro-op and bus capture from 11,157,250,000 to 11,157,550,000; it saved `idle-c11157.{cpu,host}` at 11,157,240,000. CPU writes build a 10-byte ISI request at VA 0x85c1510c, with resource 0x1c at +3 and message 0x10 at +9. NOSDRIVER control 4 invokes gsmstuff, the router reads resource 0x1c at cycle 11,157,291,414, and the accessory server consumes key 0x1c10 at cycle 11,157,311,514. Thus the in-process driver path is real and observable; this frame is an accessory query, NOT a SIM request. This supports an ISI channel diagnostic boundary but does not yet identify actual SIM request, reply delivery or why the SIM prompt appears. The run's separate UART model still saw no data-register accesses.

Next find an actual resource 0x09 request or indication, including the client, status and completion. Selectively instrument the in-process router at 0x514bcea0 with bounded event tracing, preserving the unmodified firmware and checkpoint; compare with the NGVM NOSDRIVER channel implementation and documented resource-0x09 status. Then integrate the optional test-card profile only when its delivery path is understood. Do not attribute app closure or ViewSrv timeout to missing SIM without a controlled A/B test.

## 2026-11-04: Phone-service call trace

`sim-phone-path` finished at its 11,674,050,000 budget. Targeted PCs confirm the current firmware calls NOSDRIVER methods 0x511b41b8/0x511b41d0 and their in-process gsmstuff handlers 0x514a1554/0x514a1654, e.g. at 11,157,277,055 and 11,157,538,875. There were no hits for the separately probed 0x511b41e8/0x514a183c in this interval. This confirms the OS reaches this interface, but the selected-PC log does not identify the resource, payload, client or completion; do not claim those are SIM requests. The prior Phone module transition at 11,673,959,403 is a call through a Phone image thunk, not a demonstrated crash.

A new bounded `sim-nosdriver-call` replay from the preserved 11B checkpoint captures all micro-ops/bus transfers over 11,157,250,000–11,157,550,000, spanning the first matching control/request pair, with a nearby checkpoint. Decode descriptors and request/response payloads; compare the emulator's NOSDRIVER channel semantics before connecting the present-SIM profile. The 0x64 SIM startup response still needs a real serving-state implementation.

## 2026-11-04: Phone activity and SIM integration trace

`tlbhold-viewmodules` completed its 11,872,920,000 diagnostic budget. Its ROM module-transition trace recorded 5,795 transitions into the Phone image's 0x50ca–0x50cc buckets; the last recorded transition was 0x50cc850c at cycle 11,673,959,403, after the Insert SIM display frame at 11,650,151,158. This is the last observed *transition*, not proof that it is the last Phone instruction or that it caused ViewSrv timeout. The view timeout later selected the Phone UID object.

Next `sim-phone-path` replays from the preserved 11B checkpoint through 11,674,050,000, capturing 100K cycles around that observed Phone transition and logging NOSDRIVER/gsmstuff entry PCs for the whole suffix. This should clarify the actual phone-service boundary and recent Phone execution before selecting a SIM injection point. Original C:/PMM inputs and billion checkpoints remain untouched.

## 2026-11-04: present-SIM diagnostic profile

The user requested a simulated inserted card to investigate the SIM prompt and app closure. Existing `scratch/modem/ngage_modem.c` already supports a successful IMSI response in serving state, but defaults to cardless/unregistered. Added isolated `tests/phone/sim_present/` test-network card profile and test: its IMSI reply passes, while 0x64 still returns not-serving even with the card present. This profile is NOT connected to the firmware boot. The 11.928B run shows no accesses to hypothesized UART data register 0x0c150500, so simply toggling this state there would not establish a working SIM; docs/modem-model.md describes an in-process gsmstuff/NOSDRIVER path. See [sim-presence.md](sim-presence.md) for evidence, limitations and next steps. `tlbhold-viewmodules` is still running; its inputs and binary were not modified.

## 2026-11-04: ViewSrv timed-out object points to Phone UID

Offline inspection of `idle-c11872.host` using the checkpoint's active page table maps ViewSrv object 0x0041d748 and related object 0x0041d8c8; both contain the repeated word 0x100058b3. ROM image `phone` has UID3 0x100058b3 and code 0x50ca2464–0x50ccff7b; firmware RFS script also associates that UID with phone volume settings. This is evidence that the pending view relates to the Phone application, not yet proof that the Phone process itself failed or why. Checkpoint RAM may be stale relative to dirty cache, and the inspector's unrelated kernel anchor 0x800004ac differs from its historical expected value; observed 0x45 in the live CPU trace matches the checkpoint object.

Next replay from matching 11B checkpoint enables existing module-transition logging and probes ViewSrv timeout/callbacks. Correlate Phone image execution, scheduling and device wait with the view request before attributing blame. Do not infer SIM, timer or Bluetooth causality from the UID.

## 2026-11-04: ViewSrv timeout detailed replay

`tlbhold-viewtimeout` completed its 11,872,920,000-cycle diagnostic budget and saved matching `idle-c11872.{cpu,host}` at 11,872,870,000. The detailed window shows ViewSrv walking a list rooted at 0x004086f4 and finding object 0x0041d748 with matching identifier 0x45 at object+0x84. At 11,872,900,449 it prepares reason 11 and invokes the panic path. The selected-PC trace also recorded the final micro-op at 11,872,901,598; the difference is instruction/micro-op trace timing, so use the detailed trace for causality. The identity of object 0x0041d748 and why the response was missing remain unknown. Starter later propagates ViewSrv 11; PLAT 91 is secondary.

Next inspect object 0x0041d748 and related view/list data from the compatible checkpoint using the project's checkpoint inspection tools, accounting for cached writes and process-specific translations. Trace its registration/acknowledgement and the client it identifies. Do not claim the SIM message, Bluetooth or the modeled clock is responsible without evidence.

## 2026-11-04: ViewSrv timeout path identified

`tlbhold-viewsrv11b` reproduced the stop and captured the reason-11 candidate at 0x5064cc7a on cycle 11,872,901,598; it calls 0x5064dd38 with object 0x0041d748. The second candidate 0x5064d55e was not observed in the 11B–stop interval. Static Thumb disassembly shows the observed branch checks a state in an object and a related pointer before issuing reason 11. Starter later copies ViewSrv 11 and triggers the PLAT shutdown. This narrows the active branch but does not yet identify the nonresponding application or underlying cause.

Next replay captures all CPU micro-ops and bus operations in a narrow window around cycle 11,872,901,598, saving a compatible nearby checkpoint. Decode the view-server object and caller and determine who was expected to acknowledge the view; compare timer and peripheral assumptions before changing behavior.

## 2026-11-04: identified ViewSrv 11 timeout

`tlbhold-shutdown11b` reproduced the stop and confirms the kernel copies the seven UTF-16 characters `ViewSrv` and reason 11 from Starter's descriptor at 0x00401d14 / reason at 0x00401de4, then StarterServer termination triggers secondary PLAT 91. This is distinct from the older E32USER-CBase 42 failure. The documented Symbian v6/v7 meaning of [ViewSrv 11](https://docs.huihoo.com/symbian/s60-3rd-edition-cpp-developers-library-v1.1/GUID-35228542-8C95-4849-A73F-2B4F082F0C44/html/SDL_93/doc_source/faqSDK/faq_0900.html) is a view event response timeout; whether the triggering nonresponse is software scheduling, simulated timer accuracy, a device or another cause is unknown. The SIM prompt and HCI timeouts are observations, not proven causes.

Static disassembly of the loaded viewsrv.dll (0x5064bf04, size 15116) has two `movs r1,#11` panic candidates at 0x5064cc7a and 0x5064d55e, each calling 0x5064dd38. A targeted replay from the matching 11B checkpoint probes those PCs, their predecessor routines and Starter's propagation. Next establish which path actually fires, which process/view failed to respond, and its preceding wait. Preserve current checkpoints; do not patch out the timeout.

## 2026-11-04: shutdown tracing narrowed

`tlbhold-shutdown` reproduced the stop from `idle-c11928` with a full 50K-cycle window. It starts in kernel cache-maintenance scanning, so the initiating event predates that checkpoint. It subsequently enters 0x503407cc and the PLAT shutdown path; this is insufficient to establish the initiating thread failure. A new 11B checkpoint replay will save a slightly earlier near-stop checkpoint, capture cycles 11,927,990,000–11,928,050,000, and log shutdown-entry PCs for the entire suffix. This is a diagnostic replay, not an assumption that the Starter -13 caused shutdown.

## 2026-11-04: Starter -13 origin

The `tlbhold-starter-error` replay captured 70,000 cycles around the 9,957,555,129 Starter error and saved `idle-c9957.{cpu,host}` at 9,957,490,000. Starter 0x5096c8fc reads object field 0x0040222c = 1; 0x5096c902–904 explicitly constructs -13 and calls 0x5096d1f4. The field is cleared later at 0x5096d21c. Thus -13 is generated by Starter's state machine, not an observed RFS return; its meaning and causal relationship to the later shutdown remain unproven. No store setting that field appears in the short window. Avoid treating this error as the root cause.

Next inspect the shutdown call chain itself from the already-preserved near-stop checkpoint, and trace the point that initiates the PLAT 91 path. Previous 8B–11.928B probes show no taken SetActive panic branch; a different thread failure or earlier event remains possible.

## 2026-11-04: RFS probes 9B–10.05B

`tlbhold-rfs9b` completed its 10.05B budget. It reproduced Starter error handler 0x5096d1f4 receiving -13 at cycle 9,957,555,129 and logged 169 CActive checks, all without taking the panic branch. None of the selected old-run RFS loop, MkDirAll, disk-full or Starter RFS-call PCs occurred during this window. This does not exclude an earlier RFS issue, but it does not support transferring the old run's disk-full diagnosis to this one.

Next replay from preserved 9B checkpoint captures all CPU micro-ops and external bus transactions only during cycles 9,957,500,000–9,957,570,000 and saves a nearby matching checkpoint. Trace where -13 originates, the calling thread and error path; retain the distinction between this diagnostic and an authentic hardware model.

## 2026-11-04: Starter probes from 8B

`tlbhold-starter8b` reproduced the 11.928B stop. It logged 932 CActive::SetActive checks from 8B onward and none took the active-object panic branch at 0x50399c18; the Starter calls around 10.0349B also do not take it. Therefore the earlier c4 E32USER-CBase 42 diagnosis must not be applied to this boot without earlier evidence. Starter error handler 0x5096d1f4 received 0xfffffff3 (-13) at 9,957,555,129, rather than the older run's count 9. The shutdown's thread pointer and PLAT 91 signature remain shared, but the initiating error has not been identified. The final display is Insert SIM card; Bluetooth HCI timeouts appear in logs but causality is unproved.

Next replay from the preserved 9B checkpoint probes the RFS operation/count and filesystem failure paths until shortly after Starter's -13, retaining the original model and images. Existing detailed c4 findings (-26 on C:\System\Bootdata and RFS failure count 9) are useful hypotheses only; this boot uses a different C: image and later CPU, so they require confirmation.

## 2026-11-04: 11.928B stop replayed

`tlbhold-stoptrace` reproduced the exact 11,928,098,499 stop from the matching 11B checkpoint. Saved the matching near-stop checkpoint pair `idle-c11928.{cpu,host}` at 11,928,050,000. The firmware passes thread object 0x8040f108 to shutdown path 0x503336d0 and emits PLAT 0x1005b, matching the object and secondary shutdown signature from the previously documented StarterServer failure. This does not prove the same upstream cause; none of the selected Starter function PCs appeared after 11B despite 271 calls to CActive::SetActive, so the initiating event may be earlier or this may be a different execution path.

Next targeted replay starts from the preserved 8B checkpoint with selected Starter and panic probes through the stop. Compare timing and caller details to the previous documented StarterServer panic and investigate the earlier RFS return; the valid PPM root and script must not be incorrectly described as absent. Do not claim the SIM prompt caused the fault without evidence.

## 2026-11-04: TLB-hold long boot stopped at 11.928B

Fresh `current-tlbhold-20b` passed the former 3.65B CPU fault, then stopped at cycle 11,928,098,499 in kernel park 0x50324294 with interrupts masked. It reached a live **Insert SIM card** screen; final capture `build/sim/screens/boot-v15-current-tlbhold-20b-live/frame0035_cycle11650151158.png`. Checkpoint pairs 1B through 11B are preserved. Trace shows the kernel reporting category PLAT, code 0x0001005b, the same secondary shutdown signature as an older run; that earlier run had a StarterServer E32USER-CBase 42 panic, but the trigger here is not yet established. No data abort immediately precedes the halt in the CP15 tail.

A targeted replay from the matching 11B checkpoint is being launched with a small near-stop trace and selected Starter/SetActive probes. First determine whether the same StarterServer panic and preconditions recur; do not assume the SIM prompt or Bluetooth is the cause. The C: input was the existing 11B image, not a freshly formatted disk.

## 2026-11-04: fresh boot after TLB-wait fix

Full `tests/cpu/run.sh` passed 119 checks including the new cold-page LDM case at delays 0 and 3; upstream patch verification passed. A 2M-cycle from-reset startup smoke completed its budget with 275,287 retired instructions and 380,818 bus transfers. Compact bus logging omits ordinary traffic, so early file inactivity alone is not evidence of a stall.

Fresh 20B run `current-tlbhold-20b` started from cycle 0 with the current CPU, 11B C: image and PMM image. Live PNGs: `build/sim/screens/boot-v15-current-tlbhold-20b-live/`; logs/results: `build/sim/runs/boot-v15-current-tlbhold-20b/`; billion checkpoints: `build/sim/checkpoints/roll-current-tlbhold-20b-r*`. Monitor through the existing project heartbeat, staying quiet while unchanged. It must pass the previous 3.65B failure to establish firmware progress. No FPGA synthesis was run.

## 2026-11-04: page-walk restart fix under validation

Scratch-only signal tracing of the matching cold-page unit failure showed `err2=1` when the LDM reached VA 0x40001000 and its TLB began a page walk, immediately after R0 had received 0xffffffff. The ZAP replay restarted the instruction after this partial completion. In `rtl/arm/zap_dcache.sv`, the associative path now retains requests when the TLB is busy/walking and suppresses the retry while a translation is pending; stale fault outputs are masked during the busy interval. Change recorded as `patches/zap/0037-hold-tlb-multi-load.patch`. The cold-page reproducer now passes at latency 0 and 3, including its exact expected loaded values; the broader CPU regression is running with log `scratch/fault3650/full-regression.log`. This is not yet proof of correct abort/interrupt behavior or a successful firmware boot.

The full firmware simulator is being rebuilt with the candidate fix. Existing 3B and near-fault checkpoints are from the previous RTL and cannot safely be treated as compatible with the rebuilt model. Fresh boot required unless a compatibility investigation proves otherwise.

## 2026-11-04: firmware fault reproduced from checkpoint

`boot-v15-fault3650` replay from 3B reproduced the original stop at 3,650,819,340; new near-fault pair is `build/sim/checkpoints/idle-c3650.{cpu,host}`. Detailed trace shows `ldmia r0,{r0,r3,r4,r5,r6,r12}` starting at 3,650,815,990 with base 0x80415ff8. It successfully loads r0=0xffffffff and r3=0x84001d04, then restarts the same multi-op at cycle 3,650,816,024 using the changed r0 as its base, leading to FAR 0xfffffffc and data abort. This confirms the restart is the direct cause; the internal signal causing the restart still needs investigation. The matching cold-cache CPU unit failure provides a fast reproducer. Preserve both checkpoint pairs and traces.

## 2026-11-04: standalone cold-load reproduction

`CPU_PROGRAM=ldm_base_fault3650 CPU_ASM_DEFINES=-DCOLD_CACHE CPU_DELAYS=0 tests/cpu/core/sim.sh` reproduces a data abort with FAR 0xfffffffc, matching the firmware fault address. The test cleans/invalidates both lines, drains writes and invalidates the TLB before the six-register LDM across small pages; the warm version passed at latencies 0 and 3. This is evidence of a CPU failure under similar conditions, not yet proof that it caused the firmware failure. Earlier `docs/display-bringup.md` documents a similar older multi-load restart after a miss; the current associative adapter may have a different trigger. Do not add the cold variant to the passing regression until fixed. The fault3650 checkpoint replay continues independently.

## 2026-11-04: 3.65B firmware loop investigation

The fresh `current-fiqfix-20b` boot passed the previous 1.586B stop but parked at cycle 3,650,819,340, PC 0x50324294, with IRQ/FIQ masked. The latest live frame is the Nokia logo at cycle 1,978,272,342. At cycle 3,650,816,119 the data abort vector ran; CP15 later reported FAR 0xfffffffc and FSR 0x05 (section translation fault). The exception handler saved PC 0x5032a308, corresponding to `ldmia r0, {r0,r3,r4,r5,r6,r12}`. Earlier instructions set its base to 0x80415ff8, crossing a page boundary, and the first word was stored as 0xffffffff. A CPU sequencing fault is a hypothesis, not established: the saved trace omits internal micro-ops. The code was executing in UND mode as part of the firmware's system-call path, not necessarily an undefined-instruction crash.

A targeted replay `boot-v15-fault3650` was launched from preserved checkpoint `roll-current-fiqfix-20b-r3000`, with detailed trace for cycles 3,650,815,500–3,650,816,650 and a new near-fault checkpoint at 3,650,815,400. Check `result.json`, `instructions.tsv`, and `window-bus.tsv` once complete; compare micro-op addresses, banked registers and translation against the firmware before changing CPU code. The source checkpoint is untouched.

The directed `ldm_base_fault3650` CPU test covers the same register list, UND mode, -1 first word, and two mapped small pages crossing a boundary; it passed with memory delays 0 and 3. This rules out that simple isolated case, not a timing-dependent failure. Added it to `tests/cpu/run.sh`.

## MiSTer DDR lane preparation (2026-11-03)

Added standalone `rtl/ngage_ddr_lanes.sv` for byte-address to 64-bit DDR lane translation, with directed tests in `tests/phone/mister_ddr_lanes`. The adapter is not connected; it does not handle DDR requests or busy. The next step is a handshaking controller and a non-overlapping loader, tested together before integration. See [mister-port.md](mister-port.md). The running simulation's inputs were not changed.

## MiSTer port preparation (2026-11-03)

The shared CPU improvements are already selected by `files.qip`, but the MiSTer phone board is incomplete. Added an independently tested simulation-derived ROM/RAM/C:/PMM address decoder; it is not yet connected to the existing incomplete DDR path. See [mister-port.md](mister-port.md) for firmware bank offsets, the 64-bit DDR/loader problems and ordered integration work. The ongoing firmware simulation and its inputs were not changed.

## 2026-11-03: FIQ permission race identified and fixed

The instrumented replay reproduced the 1,586,410,487 stop and captured a checkpoint pair `idle-c1586.{cpu,host}` at cycle 1,586,406,000. At cycle 1,586,407,572 the pending store at 0x59800aaa was still FIQ (post-ALU mode 0x11), while the ALU had already advanced through exception return to user mode 0x10; the data TLB was fed the ALU's newer user mode and raised permission fault 0x1d. `rtl/arm/zap_core.sv` now exports the data lookup stage's own CPSR mode and `zap_top.sv` uses it for the data TLB, including the existing forced-user translation flag. Instruction fetch uses its actual CPU mode rather than the data instruction's forced-user flag. The ZAP change is in `patches/zap/0036-data-privilege-pipeline.patch`; upstream patch verification passes.

A controlled, diagnostic-only short replay tested the fix against the old near-failure checkpoint. Verilator normally rejected it as a different model. The old/new generated serialization field lists had 2,202 entries, identical except three same-width combinational input fields (write, read, mode) at positions 71-73; a separate generated-code diagnostic build explicitly accepted the old model signature and remapped those fields. No original checkpoint or production executable was modified. With the fix, that counterfactual replay passed the old failing instruction: A0 was written to 0x02400aaa at cycle 1,586,407,576 and data 0x31e5 to 0x02492340 at 1,586,407,580, continuing to the 1,586,450,000 budget without the old crash. This is strong local evidence, not a validated fresh boot: the modified checkpoint deserializer and short window limit what it proves. A normal unchanged production build has been rebuilt; old checkpoints are not accepted by it.

The full focused CPU regression passed 115 checks and the pre-existing legacy-cache XFAIL, plus directed FIQ tests and the live-display test. FIQ controls passed but did not naturally recreate the exact pipeline overlap; a forced-signal experiment also failed to distinguish old/new and was discarded. A fresh from-zero run is still necessary. Direct LCD capture was extended to full nonwhite frames; replaying the failed run's LCD stream produced the same Nokia PNG as the offline RGB444/low-halfword-first renderer (pixel format remains assumed). The current run's saved Nokia frame is `build/sim/screens/boot-v15-current-flashfix-20b-frames/frame01_c637683392_24d67f-lohi.png`.

## 2026-11-03: current flashfix boot reached Nokia, stopped at 1.586B

`current-flashfix-20b` passed the previous 616M flash-status failure and rendered a Nokia logo in full direct LCD frame `frame01_c637683392_24d67f-lohi.png` under `build/sim/screens/boot-v15-current-flashfix-20b-frames/`. The initial white clear appeared live; the subsequent logo was only rendered offline because the direct live parser previously accepted only white. The parser now captures complete nonwhite frames under the existing RGB444/low-halfword-first hypothesis; its recorded-trace test reproduced the exact Nokia PNG and unit test rejects incomplete frames.

The run ended at cycle 1,586,410,487 at kernel park 0x50324294 with IRQ/FIQ masked. Trace shows a data-abort exception entered from FIQ during C: flash programming: fault register 0x1d (domain 1 section permission fault), FAR 0x59892340, PC saved 0x50385248, with adjacent AMD program command stores at 0x02400aaa. The final L1 descriptor for VA 0x59800000 is 0x0240043a (domain 1, privileged RW); FIQ mode is privileged. This mismatch needs investigation; fault origin/PC timing and stale translation context are not yet proven, and should not be patched by skipping the exception. The preceding execution wrote to C: nine times.

Control unit tests `fiq_privileged_store` and `fiq_privileged_ldrt` pass at delays 0/3 with the same privileged domain-1, write-through section attributes, including FIQ interrupting an unprivileged translated load; these simple scenarios do not reproduce the fault. `fiq_flash_sequence` also passes 128 alternating FIQ halfword writes while incrementing across cache-line boundaries through the observed destination range, with the same command addresses and descriptor attributes at delays 0/3; the target is synthetic RAM, not a complete flash or interrupt model. `fiq_store_return` also passes with the firmware-like conditional return immediately after the privileged store; this does not rule out timing-dependent privilege context issues. The `current-flashfix-debug` replay from the preserved matching 1B checkpoint reproduced the identical park at 1,586,410,487. Its 4,500-cycle window shows AMD AA and 55 command writes at 1,586,407,564 and 1,586,407,570, then an architectural data abort at PC 0x50385248 at 1,586,407,573 before the A0 command reached the bus; FAR is the following target 0x59892340, and FSR is 0x1d. All available CPU micro-ops and bus traffic were logged only between 1,586,406,000 and 1,586,410,500. A second `current-fault-instrumented` replay uses the same checkpoint and an isolated C++-instrumented simulator; a 10-cycle restore smoke passed. It records per-cycle privilege, TLB and fault signals in `tlb-debug.tsv` only for that window and is configured to save a reusable checkpoint at cycle 1,586,406,000. Both use the same unchanged RTL and checkpoint; provenance records their different executable hashes. The first replay completed and reproduced the stop; the instrumented replay continues unattended. A separate repeated-FIQ injection experiment timed out in its synthetic interrupt harness and was removed; it is not evidence of the firmware bug. The runner records checkpoint hashes and marks it restored. Check its result and `window-bus.tsv`, `instructions.tsv`, `cp15.tsv`, compare fault timing and translation; avoid dumping the whole log into context. No changes to the running simulator source/binary should be made until it finishes, because provenance checks require stable inputs.

## 2026-11-03: flash lock bank and live direct-clear fix

The failure at 616,577,518 was reproduced at the board-model level: after 0x60 PMM lock writes at 0x007f0000, the old model incorrectly returned the lock status 0x00010001 to instruction reads at 0x0027ee60. The related [Spansion Am29BDS643G reference](https://datasheet4u.com/pdf/564541/AM29BDS643G.pdf), whose exact identity with the N-Gage AM29N643 marking is unverified, describes four independent 2 MiB banks and bank-addressed operations. The current board model scopes its existing lock-status hypothesis to the addressed bank, allowing other banks to return array data. It also corrects a key collision that had accidentally shared PMM command state between different physical chips. `tests/phone/flash/sim.sh` verifies the exact crash sequence, different-chip isolation, return to array mode and 0x60 as programmed data. It is a directed test; the firmware has not yet been replayed to 616M on this build, so progress beyond the former crash is not yet proven. This remains a provisional flash model, not confirmation of exact chip behavior.

The live launcher now incrementally observes direct LCD bus transactions as well as DMA. It writes an assumed-white `latest.png` only for the previously recognized complete all-ones clear followed by display-on; it does not invent images for unknown nonwhite direct transfers. `tests/phone/lcd/test_direct.py` covers known and unknown patterns, and replaying the failed run's recorded bus stream produced the expected PNG at cycle 168,453,013. The LCD pixel interpretation remains an assumption. The current board files are now source-of-truth under `scratch/current-boot/board`; `build.py` no longer silently overwrites them with the old frozen board. The small current-boot source folder is unignored for Git; firmware, images and build outputs remain ignored.

Build and launcher 1,000-cycle smoke passed. Fresh user launch: `python3 scratch/current-boot/live.py current-flashfix-20b`. It starts at cycle zero, uses the same 11B C: image and 20B limit, retains every billion checkpoint, and displays PNGs in `build/sim/screens/boot-v15-current-flashfix-20b-live/`. It may encounter further unknowns. Old run `current-c11-20b` remains available for comparison.

## 2026-11-03: current CPU 20B boot stopped at 616,577,518

`boot-v15-current-c11-20b` stopped at cycle 616,577,518 with architectural instruction abort VA 0x518ffffc. The C: image was not written. `bus.tsv` shows from cycle 611,243,522 instruction fetches at physical 0x0027ee60 etc were served `0x00010001` as `flash_pmm_status` immediately after 0x0060 lock commands to physical 0x007f0000; the CPU subsequently ran through the status pattern until it left mapped flash. `scratch/current-boot/board/boot_profile.cpp` applies its hypothesized PMM lock-status response to the whole flash chip, including instruction fetches, which is a strong candidate for the failure. Whether the model is wrong or the updated CPU/firmware sequencing caused an unexpected mode remains unverified. Inspect the command state, firmware and actual flash behavior before changing the model; do not blindly skip the fault. No billion-cycle checkpoint exists for this run.

Display: offline bus analysis identifies a white 176x208 clear at cycle 157,886,175 in `build/sim/screens/boot-v15-current-c11-20b/screen.png`. The promised live PNG did not appear: `live-lcd.bin` was empty and `main.cpp` calls `dump_live_lcd` only on the 0x0c120348 DMA trigger, while this clear was captured from the bus trace. Fix live capture for direct LCD transactions before relying on it. Do not claim the launcher displayed the clear live.

Next: make a small flash-lock-mode regression reproducing command 0x60 to the PMM sector followed by instruction fetch from 0x0027ee60; check the real chip model/data and compare previous frozen-run behavior before selecting a response. Then make direct-LCD updates produce live PNGs, rebuild current board, and start a fresh 20B run with a new name. Existing run outputs provide evidence and were not deleted.

## 2026-11-03: historical checkpoint pruning

At the user's explicit request, pruned old checkpoints after confirming complete pairs. Retained the ten latest pairs from `roll-overnight-c11-24b`: 14B through 23B (the run stopped before 24B). Deleted the other 24B-run pairs and old `wt-reset-12b`, controls-dialog and wrapper-check pairs, freeing approximately 627 MiB. Current-run checkpoint files, unrecognized files, and `scratch/overnight/cdrive-11b.img` remain untouched. The active current-CPU boot started at cycle 0 with that C: image, not from an old CPU checkpoint. Continue preserving billion-cycle checkpoints from the new run; the user's pruning instruction applied to the historical checkpoints.

## 2026-11-03: old screenshot cleanup

At the user's request deleted the old screenshot folders, including tracked milestone PNGs and the overnight baseline images. The active `boot-v15-current-c11-20b-live` folder is retained for new images. The old `scratch/live-controls/start.py` expects a deleted overnight seed PNG and cannot resume that old visual setup without recreating or replacing the seed. Billion-cycle checkpoints and the active simulation were not removed.

## 2026-11-03: simulation output cleanup

Removed 88 obsolete run folders, 23 rebuildable unit/old simulator object folders, 28 non-billion old checkpoint files and 15 empty screen directories. `build/sim` fell from approximately 4.9 GB to 1.1 GB at cleanup time. All 72 existing billion-cycle checkpoint files, historical PNGs, the old frozen simulator under `scratch/overnight`, the current CPU build, firmware/C: inputs and active `boot-v15-current-c11-20b` run were retained. Small provenance/result/log summaries for the prior overnight and write-through runs remain under `build/sim/history/`. Confirmed Docker was still running the current CPU and its bus log continued to grow after cleanup. Old object/unit outputs can be rebuilt by their scripts.

## 2026-11-03: current-CPU live boot launcher

`scratch/current-boot/live.py` starts a cycle-zero boot with the current `build/sim/obj-current-boot/Vngage_cpu_sim`, the fuller overnight board model, the 11B C: snapshot `scratch/overnight/cdrive-11b.img` and `scratch/overnight/pmm-aan.bin`. Default budget is 20,000,000,000 cycles; launch from the project root with `python3 scratch/current-boot/live.py current-c11-20b`. It refuses existing run names, validates CPU binary/source hashes against its build manifest, records actual C:/PMM hashes and assumptions, writes live PNGs under `build/sim/screens/boot-v15-current-c11-20b-live/`, and preserves checkpoint pairs at every billion cycles. The 1,000-cycle launcher smoke test completed successfully; it is not a firmware boot validation. There is no PNG until a complete display update is observed. Do not use `scratch/overnight/run_24b.py` for the current CPU: it uses the frozen CPU.

## 2026-11-03: overlapping data-cache linefills with buffered writeback

The data-cache controller can now issue an unrelated cache-line refill before all buffered writebacks drain. The write buffer checks all queued physical word addresses, including groups crossing cache-line boundaries; an overlapping physical line waits for the earlier writes. A bus-owner latch prevents preemption of an already-offered stalled transfer. Uncached accesses, MMU page walks and explicit drain still retain their existing stricter ordering. The overlap check conservatively considers already-retired words in a still-active group.

Directed `tests/cpu/cache_access/sim.sh` shows a replacement completing after 1 of 8 dirty writeback words in a controlled scenario; the other 7 drain afterward. This establishes overlap, not a measured phone boot-speed improvement. Tests also cover a blocked bus beat remaining stable, a pending write to a different word in the same line via a virtual alias, all buffer entries and crossing-line groups, and error recovery with a refill and write both pending. The full CPU regression passed 107 checks plus the pre-existing legacy-cache XFAIL; the expanded error test was rerun separately and passed. Local ZAP patch verification passed. Rebuild `scratch/current-boot/build.py` after any further RTL changes; no long firmware run or FPGA synthesis was started.

## 2026-11-03: integrated SWP lock and external-abort handling

The extracted `firmware/disk_dump/Z/System/Libs/ekern.exe` contains ARM `swp ip, ip, [r0]` at file offset 0x8394 amid plausible kernel code; whether this specific routine executes during our boot is not established. The earlier standalone SWP bus experiment was superseded and removed.

SWP read/write metadata now travels with micro-operations through the ZAP pipeline, including stalls, flushes and failed conditions. For a noncacheable swap, the data adapter retains the read-side external fault until after attempting the write, preserves FAR/FSR, drains prior buffered writes, forces the swap write to be nonbuffered, and requests exclusive bus ownership. Lock can be asserted while older buffered writes drain, earlier than the manual describes; this conservatively holds the bus longer and needs timing refinement. The ZAP instruction/data merger holds the data channel during the lock; `ngage_cpu.wb_lock` and `ngage_mister.bus_lock` expose that reservation to the board. Cacheable swaps continue through ordinary cache behavior without asserting external lock (ARM DDI 0151C section 4.3.5). ZAP edits are preserved in `patches/zap/0035-swp-metadata-and-lock.patch` and the full local patch verification passes.

Focused tests pass at delay 0/3 for word/byte/failed-condition swaps, cacheable and noncacheable-bufferable mappings, translation fault, a read external abort (including original destination and fault address), a write external abort, errors on both bus beats, IRQ/FIQ at the read and IRQ combined with read abort. Read-abort no longer XFAILs. The bus test checks a continuous CPU lock and a simulated competing master; IRQ at CPU read completion tests both cache-hit and uncached cases, accepting restart before architectural completion. Basic lock, read-abort, IRQ and FIQ also pass delays 20/50. The final full CPU regression passed 107 PASS lines and the pre-existing legacy-direct-map XFAIL; all new programs are in `tests/cpu/run.sh`.

Limits: the real board has no competing phone-memory DMA master yet; `Template.sv` receives the lock but a future shared-memory arbiter MUST honor it. The simulated competitor is not hardware proof. MMU permission combinations, every fault/interrupt ordering, SWP timing/burst behavior and firmware execution remain unverified. The current simulator must be rebuilt after subsequent RTL changes and old checkpoints remain incompatible. No long firmware boot or FPGA synthesis was started.

## 2026-11-03: SWP lock and fault investigation continued

`rtl/arm920/swp_bus_lock.sv` implements an **isolated, unintegrated** noncacheable read-lock-write transaction: it keeps a lock asserted across stalls and both beats, attempts the write after a read error, reports either bus error after the write, handles byte enables, and releases the lock on reset. `tests/cpu/swp_bus_lock/sim.sh` passes its unit tests with a simple competing-master grant model. The module is NOT connected to the ZAP pipeline, cache, CPU boundary or real board arbiter, so it does not fix architectural SWP behavior yet.

CPU-directed SWP write-abort, IRQ during the read, and FIQ during the read pass at memory latencies 0 and 3 in the uncached configuration. The IRQ/FIQ tests check that the handler sees both memory and the destination register after the swap. Basic SWP/SWPB also pass. `tests/cpu/swp_abort/sim.sh` still XFAILs: an external read abort causes the write to be suppressed. No CPU-level bus lock exists, so another master could interleave; the synthetic arbiter unit check is not an end-to-end test. Cached SWP, MMU fault distinctions, abort-versus-interrupt priority, competing DMA and full board arbitration remain open.

Next integration requires carrying an executed (condition-passed, flush-safe) SWP identity and its source/address through decode, pipeline and cache; ensuring translation/permission faults do not start physical transactions; draining or reconciling cache and write-buffer ordering; deferring an external read abort until the write beat has been attempted; propagating lock to and honoring it in both the ZAP instruction/data merger and any external bus arbiter; and adding end-to-end contention, fault and interrupt tests. Do not wire the module by guessing SWP from a dummy register or a speculative fetch. No long boot or FPGA synthesis was run.

## 2026-11-03: SWP fidelity investigation

The ZAP micro-op sequencer explicitly states its SWP/SWPB expansion does not preserve bus atomicity: it emits a load, store, then move, with no documented interconnect lock. `sim/programs/swp_basic.S` now verifies the ordinary word and byte results at memory delays 0 and 3; both pass. This does not test atomicity, DMA/bus contention, or aborts. ARM DDI 0151C section 3.8 also states that for a noncacheable read-lock-write sequence, the write is attempted even if the read aborts; a directed test now confirms ZAP takes the data abort without attempting the write. Reproduce with `tests/cpu/swp_abort/sim.sh` (documented XFAIL); the basic SWP/SWPB functional tests pass. Inspect the full CPU-to-board interface and implement an end-to-end lock and correct abort behavior with directed bus-contention/fault tests before calling the CPU conformant. Do not assume suppressing interrupts alone makes SWP atomic against other bus masters.

## 2026-11-03: buffered cache writeback

Dirty data-cache clean and eviction beats now enter the existing write buffer rather than directly waiting for external bus acknowledgement. Maintenance completes after enqueue; cached hits can proceed while its writeback drains. Eviction accepts one or both dirty half-lines into the buffer and waits for the buffer to drain before issuing the replacement linefill; that ordering is conservative and does not yet provide the overlap described by ARM DDI 0151C section 4.3. The Wishbone adapter does not yet model ASB burst timing. Existing buffered-error policy retains/retries a failed beat; exact hardware behavior for persistent errors remains unverified.

Directed cache tests cover a stalled clean, cached hit during pending writeback, error retry, and a stalled 65th-way eviction with both dirty halves and eight correctly ordered words. Both focused tests pass. The complete existing CPU regression passed (83 PASS lines and one documented legacy-cache XFAIL); see `build/sim/cpu-regression-writeback.log`. The previously built `obj-current-boot` is stale after this RTL change and must be rebuilt before use. No firmware simulation or FPGA synthesis was started.

## 2026-11-03: final focused regression for default cache

`tests/cpu/run.sh` completed with 83 passing check lines; its one XFAIL is explicitly the retained legacy direct-mapped cache. The default associative cache passes the expanded CPU, prefetch, WFI, interrupt, buffer, TLB ordering, load/alignment and maintenance tests. Warming the instruction cache gives 120/120 one-cycle consecutive dependent ADD intervals at both memory delays; cold misses still stall. Default SYNTHESIS-defined Verilator lint and the complete upstream-plus-patches verification pass. The separately located default simulator executable's manifest matches the current RTL. No firmware run or Quartus compilation was performed.

The development default is not proof of MiSTer FPGA fit or 104 MHz timing. Dirty eviction/maintenance writebacks remain synchronous, pseudo-random replacement is approximate, and prefetch fault/cancellation, permanent bus failures, debug wake and wider interrupt/CPU interactions require work. The new CPU binary is incompatible with older checkpoints; retain the old checkpoints. Rebuildable CPU/cache-access unit build intermediates were removed after validation; their test runners recreate them.

## 2026-11-03: translated instruction prefetch

`icache_prefetch_translated` verifies two prefetches of an unaligned MVA through a nonidentity mapping, then locks the line and executes 64 conflicting instruction lines. It passes at bus delays 0/3 and confirms only one physical line fetch. This covers the manual's unaligned-MVA behavior for a valid cacheable translation; prefetch translation/permission faults and interrupt cancellation still need separate investigation. The new cache remains the development default; FPGA fit/timing and full firmware boot remain unverified.

## 2026-11-03: instruction-cache hit throughput and ADD regression

Selecting the new cache as default initially reduced warmed cached ARM ADD throughput to one instruction every four clocks because the instruction-cache bridge serialized every hit. Added a synchronous next-sequential-line lookup and a checked-address fast-hit path, with normal lookup/refill used on a mismatch, branch or miss. The directed `cpu_timing` program now measures 120/120 warm consecutive dependent ADD intervals at one cycle at both synthetic memory delays 0 and 3; the test now fails on a regression. Cold intervals still stall on instruction fills (observed up to 33/50 cycles for the respective delays). The complete focused suite passed after the change, including instruction-cache associativity, prefetch, IRQ/FIQ/WFI, LDM, FCSE, alignment and maintenance tests. This is not proof of cycle-accurate ARM920 execution or 104 MHz physical timing.

The ARM920-shaped caches remain the development default, with the old cache available using the documented legacy flag. Dirty eviction writebacks remain synchronous; prefetch faults, exact random replacement, untested interrupt races, FPGA resource inference/fit and physical timing remain open. No firmware or Quartus simulation was run.

## 2026-11-03: associative I/D caches selected as development default

The ARM920-shaped associative instruction/data cache and write buffer are now selected by default in `files.qip`, `sim/run.py` for the N-Gage variant, and focused CPU tests. Set `NGAGE_ASSOC_EXPERIMENT=0` for the simulator or `CPU_ASSOC_EXPERIMENT=0` for an individual CPU test to retain the previous direct-mapped configuration; the suite runs the old associativity test as an explicit XFAIL. The legacy RTL remains available. The default change follows 81 passing focused checks across the new cache, CPU, MMU, interrupt, WFI and maintenance tests; it is a development default, not evidence that a MiSTer build fits or meets timing.

The user requested unit tests rather than repeated firmware simulations. No firmware replay was run. Verilator SYNTHESIS-path syntax passes for both new and old configurations, but there has been no Quartus compilation, FPGA RAM inference, resource fit or 104 MHz timing verification. Dirty eviction/maintenance writebacks remain synchronous; pseudo-random replacement is approximate; prefetch translation-fault behavior, persistent errors, debug wake and wider interrupt/cancellation cases remain unverified. The new CPU build is incompatible with previous checkpoints; preserve those checkpoints and use a fresh run when firmware testing is authorized.

## 2026-11-03: buffered page-table ordering and broader CPU diagnostics

Instruction and data TLB walks now wait for older buffered stores before issuing a memory request, while already-offered walks stay stable through acknowledgement. The standalone gate test passes. `cache_tlb_write_order` and `icache_tlb_write_order` verify at a 20-cycle bus delay that a buffered page-table descriptor update overlaps a later data or instruction TLB walk and the walk sees the update. Existing load-width, multiple-load, alignment and FCSE CPU programs also pass against the new caches at delays 0/3 after extending the unit bench RAM to cover their full 2 MiB address range. Initial failures were bench limitations (the previous bench rejected the programs' RAM and diagnostic addresses), not CPU failures.

The caches are still experimental as of this checkpoint. No Quartus synthesis or real firmware run was performed. Existing billion-cycle checkpoints are retained and cannot be restored into a simulator with different CPU RTL.

## 2026-11-03: instruction prefetch and cache interrupt tests

The experimental I-cache now handles CP15 prefetch by MVA, waits for its TLB and linefill, and restores/resynchronizes the instruction lookup before releasing normal fetch. `icache_prefetch_lockdown` verifies a line is fetched once, remains resident after a second prefetch, and stays locked while 64 other instruction lines execute. `icache_prefetch_uncached` checks that a noncacheable target is not fetched. Both pass at synthetic memory delays 0/3. The first prefetch implementation incorrectly acknowledged a normal instruction fetch while taking over the port; the directed test exposed and fixed the failure. Translation faults during prefetch currently complete without a fill; verify this behavior against ARM920T and expand permission, cancellation and simultaneous IRQ tests. In the old default cache, prefetch currently acknowledges without a fill and is not ARM920-equivalent.

Added CPU tests that assert a level-sensitive IRQ during either an active data linefill or a dirty eviction; both complete the memory operation, enter the handler and return at delays 0/3. A short pulse during a stalled refill was not observed by the CPU, while holding the interrupt until handler entry passes; this does not prove all edge/interrupt-controller behavior. These remain focused tests, not a firmware replay.

The associative caches and write buffer are still opt-in; asynchronous dirty writeback timing, full exception/interrupt cases, physical FPGA RAM inference, resource fit and 104 MHz timing remain open. No Quartus synthesis or firmware simulation was run.

## 2026-11-03: buffered writes, external aborts and WFI

The experimental cache now has an asynchronous four-address/16-word write buffer. Consecutive single stores can share a group; bus beats stay ordered and byte enables are preserved. Cacheable write-through hits update the cache and enqueue writes, WB write misses and noncached buffered writes enqueue, and cached hits can proceed while writes drain. Nonbufferable stores, noncached loads, D-cache fills, I-side external requests and CP15 drain wait for the buffer. Focused tests cover sixteen words, full/backpressure, simultaneous push/pop, ordered loads/fills, code fetch after buffered code writes, CP15 drain, transient errors and both delay settings. Dirty eviction/maintenance still writes back synchronously, so not all ARM920 writeback timing or interrupt latency is reproduced. Permanent buffered errors keep retrying and can halt progress; architectural buffered abort delivery is not claimed.

For uncached external read errors, the experimental CPU now carries the TLB mapping type and domain to CP15 FSR, and preserves the faulting MVA in FAR. CPU tests inject section and small-page errors in domain 6 and pass at 0/3 synthetic bus delays. Cached refill/clean and buffered bus errors retry rather than raising guest external aborts; wider error and cancellation scenarios still need tests.

Implemented CP15 WFI: it first waits for write-buffer drain, then waits for an interrupt. A CPU regression initially showed IRQ arriving one instruction late; the wake event is now latched through predecode so IRQ/FIQ entry precedes the following instruction. Directed tests pass for IRQ, FIQ and masked IRQ at both delays; EmbeddedICE/debug wake and all interrupt/cancellation races remain unimplemented or unverified. Normal caches remain default pending complete CPU/peripheral tests and FPGA implementation evidence. No firmware simulation or Quartus synthesis was run.

## 2026-11-03: regression and experimental simulator build

After the lockdown ordering change, `tests/cpu/run.sh` completed with 40 passing check lines and one expected failure for the old default direct-mapped data cache. The opt-in I/D cache tests pass. Experimental SYNTHESIS-defined Verilator syntax and the full ZAP patch-series verification pass; the separate experimental simulator binary was rebuilt successfully. No firmware was run and no Quartus synthesis, fit, timing, or asynchronous write-buffer implementation is claimed. Unit build intermediates for the CPU and cache-access benches were removed after testing; runners recreate them.

## 2026-11-03: instruction lockdown and ordering

A CPU instruction-lockdown test now runs the driver from an uncached high ROM alias, places a function in I-cache way zero, locks it, executes 64 conflicting instruction lines, and verifies the first line is fetched only once. It passes at bus delays 0/3. The first attempt exposed a real overlap between a CP15 lockdown update and an in-flight fetch; the cache bridge now defers the update until the access finishes, and CP15 waits for acknowledgement. A directed CP15 bench checks that it waits while the cache is busy. The first version of the test also accidentally occupied the target way with its own cacheable driver; the uncached alias removes that test flaw.

The replacement remains experimental: run `NGAGE_ASSOC_EXPERIMENT=1 python3 -B sim/run.py --rtl-lint` for a synthesis-path syntax check, and see the following checkpoints for outstanding buffer, fault, interrupt, synthesis and performance work. Do not restore older CPU checkpoints into a simulator built with changed RTL.

## 2026-11-03: FCSE cache-space directed test

`CPU_ASSOC_EXPERIMENT=1 CPU_PROGRAM=cache_fcse tests/cpu/core/sim.sh` passes at both synthetic bus delays. It runs code outside the FCSE window, maps the same low virtual address through two process IDs to different physical small pages, switches between them and back, and checks each page value. This is evidence for the tested data-cache/TLB FCSE path only; other aliases, process-switch timing and instruction FCSE remain untested. The test is included in `tests/cpu/run.sh`.

## 2026-11-03: experimental I/D cache and CP15 maintenance

The opt-in `NGAGE_ASSOC_EXPERIMENT=1` build now connects the associative cache to both CPU cache ports. Focused CPU tests pass at bus delays 0/3 for data and instruction associativity, data lockdown across 64 competing lines, write-back/write-through store behavior, disable/re-enable, write-buffer drain, MVA clean and index clean+invalidate, instruction MVA invalidation, and a Thumb return with nonidentity user/small-page translation. The instruction-conflict test fetched the first line twice with the old cache and once with the experimental one. A cache-access bench also checks 65th-way dirty eviction, MVA miss, and single-line isolation. CP15 RR and separate I/D lockdown registers are connected; pseudo-random replacement is an approximation.

`NGAGE_ASSOC_EXPERIMENT=1 python3 -B sim/run.py --rtl-lint` passes Verilator with `SYNTHESIS` defined, and `patches/zap/verify.sh` passes. The optional simulator build uses a separate `build/sim/obj-ngage-assoc-experiment` object directory and includes its source in the build hash; checkpoints from another CPU build are incompatible. `files.qip` includes the new modules but does not turn on the experiment. No firmware replay or Quartus synthesis was run.

Do not treat this as complete ARM920T or delete the old cache yet. Normal builds still use the old caches. No FPGA RAM inference, area, or 104 MHz timing is established, and the current all-ways combinational tag search may be costly. Stores and refills are serialized, not the ARM920 asynchronous write buffer; bus/cache error behavior, MMU FCSE aliases, interrupts/cancellation and outstanding transactions need targeted tests. CP15 wait-for-interrupt and I prefetch are not implemented, and single operations are only covered for the listed cases. Maintenance uses per-line dirty halves and must still be checked on failed bus transactions and CP15 overlap in the complete CPU context. ADD stall investigation is still pending.

## 2026-11-03: experimental associative data cache reaches CPU tests

The current ZAP CPU cache now fixes two independently demonstrated ARM920T differences: write-back store misses no longer allocate (`0019`; test `CPU_PROGRAM=cache_write_miss`), and disabling/re-enabling either cache no longer discards its tags (`0020`; test `CPU_PROGRAM=cache_disable_reenable` verifies dirty D-cache contents). Both tests failed before the respective fixes and pass at synthetic memory delays 0 and 3. Stores remain serialized rather than buffered.

The new `rtl/arm920` bank now has a serialized access path, whole/indexed maintenance controller, dirty-half writeback and refill engine. Focused tests verify WB/WT hits and misses, no-write-allocate, 64 resident ways plus 65th-line dirty eviction, indexed clean, clean-all, invalidate-all, stalls and local error retry. Experimental compile flag `NGAGE_ASSOC_EXPERIMENT`, exercised with `CPU_ASSOC_EXPERIMENT=1 tests/cpu/core/sim.sh`, connects this D-cache to ZAP; CPU-level associativity, write-through, drain, write miss, cache disable/re-enable, and Thumb return tests pass at delays 0 and 3, including nonidentity user/small-page return. RR control is now connected from CP15; pseudo-random replacement is approximate. The first experimental run failed from a spurious retry while no data request was active; gating retries fixed the directed tests.

This is **not a completed replacement**: the normal build still uses ZAP's data and instruction caches; the CPU-level normal associativity test remains XFAIL. The experimental bridge handles only coarse clean/invalidate, forces cache lockdown base zero, lacks CP15 per-MVA/index commands and instruction cache replacement, serializes all memory access instead of using the ARM920 asynchronous write buffer, and its treatment of external errors does not establish ARM920 semantics. MVA/FCSE aliasing, cancellation/interrupts, full CPU load-store sequences, reset/maintenance races and Wishbone arbitration need directed tests. No Quartus synthesis or BRAM/fit/timing evidence exists; tags use parallel comparisons and may be expensive. Do not delete old cache until the replacement and instruction side are tested and built. No firmware simulation was run.

## 2026-11-03: associative replacement bus prototypes

Added `rtl/arm920/cache_transfer.sv` and `cache_refill.sv`; focused `tests/cpu/cache_transfer/sim.sh` and `cache_refill/sim.sh` pass. The replacement engine writes only dirty 16-byte halves, holds bus requests stable during wait states, loads eight refill words, and retains the old dirty line after a write-back or refill error so the operation can be retried. These are standalone prototypes, not connected to either CPU cache. The local engine error must not be confused with a guest-visible ARM abort: ARM920T TRM table 4-1 states that cached reads/writes/write-backs cannot be externally aborted; the implementation must determine proper bus-error semantics before CPU integration. TRM 4.3 says data cache allocates on *read* misses; WB write misses go to the write buffer. ZAP currently allocates on WB write misses, a separate behavior the replacement must correct and test. Real asynchronous write buffering, CP15 operations and lockdown control, integration with TLB/stalled CPU and Wishbone arbitration, instruction cache replacement, and synthesis remain open. Preserve the old cache until the replacement passes the CPU tests; the CPU associativity test remains XFAIL. ADD timing work has not started this session.

# Development checkpoint and resume guide

## 2026-11-03 associative-cache line-storage prototype

Added `rtl/arm920/cache_lines.sv`: standalone synchronous 512×32-byte line storage with per-byte write enables and `(way,segment)` slot addressing; no data reset, relying on tags for validity. `tests/cpu/cache_lines/sim.sh` passes full-line refill, sparse byte writes, and way/segment isolation. Same-slot read-during-write is explicitly unspecified and must be bypassed/avoided by the future controller. This and `cache_tags.sv` are NOT connected to the CPU; neither FPGA block-RAM inference nor fit/timing is established. Next connect tag-selected way to storage with explicit RAM latency, then implement atomic dirty-half writeback and refill under stalls/errors, CP15 maintenance and CPU integration before removing the associativity XFAIL.

## 2026-11-03 associative-cache replacement prototype

User authorized a radical redesign rather than retaining ZAP's shape. Added `sim/programs/cache_associativity.S` and `tests/cpu/cache_associativity/sim.sh`: under RR replacement, two cacheable addresses separated by 16 KiB should coexist in the ARM920T's 64-way segment. Current ZAP writes the first dirty line back on the second access; test reports explicit XFAIL (a genuine cache-geometry mismatch, not a passing test).

Added isolated `rtl/arm920/cache_tags.sv`, an 8-segment × 64-way MVA tag/victim prototype for 16 KiB/32-byte lines, physical writeback tags, two dirty halves, RR/experimental pseudo-random selection, single/all invalidation and lockdown base. `tests/cpu/cache_tags/sim.sh` passes 64 same-segment allocations/lookups, segment isolation, dirty halves, victim physical address, invalidation, RR wrap and lockdown bounds. This module is NOT connected to the CPU, has NOT been synthesized or timed on the FPGA, does not implement the data array, bus/writeback ordering or full CP15 maintenance, and does not claim complete ARM920T replacement semantics. Random sequence is an approximation. Next design the pipeline and atomic dirty-victim handshake, integrate data storage and CP15 index/MVA maintenance, then rerun the existing XFAIL and timing/fault unit tests; preserve the working cache until replacement passes.

## 2026-11-03 CPU ID, MMU permissions and closer abort reproducer

ARM920T TRM table 2-5 specifies implementer 0x41, specification 1, architecture 2 (ARMv4T), part 0x920; old ZAP CP15 ID was placeholder 0x0005aaa0. For the N-Gage ARMv4T configuration `0018-arm920-identification.patch` reports 0x41129200, with layout revision 0 an explicit model choice, not independently measured phone silicon. CP15 unit test was observed failing before and passes afterward; preserve legacy identifier for other ZAP config. Patch stack verified.

`tests/cpu/tlb_attributes` checks all four descriptor types, all cache attributes and 768 combinations of domain, AP, defined S/R, user/supervisor, read/write against ARM920 manual; these directed checks pass (not proof of complete MMU correctness). The POP-to-PC/Thumb add dependency reproducer passes with user mode, non-identity virtual mapping, small pages, caches and latency 0/3. This still does NOT reproduce the earlier Etel abort; next isolate surrounding scheduling/interrupt/cancellation, exact data-cache/TLB state and compare the complete trace with an independent CPU. The cache type register reports ARM920 64-way but ZAP really is direct-mapped; user explicitly authorized radical redesign if needed, so future work may replace cache architecture rather than preserving this mismatch.

## 2026-11-03 cached ARM ADD timing unit benchmark

Standalone `CPU_PROGRAM=cpu_timing tests/cpu/core/sim.sh` executes ten repetitions of sixteen dependent ARM ADDs in a cacheable code region, measures consecutive writeback retirements, and compares them with TRM ch.12's one-cycle normal data operation under cached-access assumptions. At latency 0: 150 gaps, 149 at 1 cycle, one 13-cycle gap (PC 0xe0, sample 16). At latency 3: 148 at 1 cycle, gaps 52 and 37 during the first pass; the first-pass gaps include bus transfers. After discarding the first two passes, all 120 consecutive ADD intervals are one cycle at both latency settings. The 13-cycle second-pass stall has zero external bus transfers in the interval, while the two first-pass delayed-memory stalls include 9 and 6 transfers respectively. The former is not yet attributed: branch prediction or internal pipeline scheduling needs its own isolated test. This measures this synthetic model only, not physical N-Gage timing or a proof of full timing compliance. Both functional tests pass. The normal `tests/cpu/run.sh` now includes the timing benchmark.

## 2026-11-03 focused CPU unit tests and CP15 fix

At user request, use standalone directed HDL unit benches following jtpublicfork CPU-test style, not repeated long firmware simulations. `tests/cpu/run.sh` runs CP15, TLB attributes and a minimal CPU/ROM/RAM unit bench, each with an individual runner. No phone firmware is needed. ARM920T TRM register 1 says bits 11:10 are reserved/read zero and RR bit14 resets zero; prior RTL reset/read 0x4878, forced reserved bit11 high, and incorrectly coupled bit14 to the core's ARMv4 behavior. `0017-arm920-control-register.patch` forces 11:10 to zero, resets RR to zero, and keeps ARMv4 behavior enabled for the N-Gage configuration independently of RR. Standalone `tests/cpu/cp15/sim.sh` fails on old RTL and passes with the correction; checks reset, writes, cache type readback and drain. Actual cache remains direct-mapped despite ARM920's 64-way-reported type: it is NOT fixed by readback check. Standalone `tests/cpu/tlb_attributes/sim.sh` passes C/B propagation for section/small/large/fine and disabled MMU.

Simplified firmware-like POP-to-PC + Thumb add/load unit program `sim/programs/thumb_return_dependency.S` now passes via `tests/cpu/core/sim.sh` at 0/3 bus delays. Early test failures were test setup (wrong page-table index; invalid Thumb-to-ARM test exit), not demonstrated RTL regressions. This simplified pass does not explain or invalidate the actual EtelServer trace's R7/R0 discrepancy; preserve its trace and reproduce fuller context/scoreboard or request cancellation with unit tests. Unit bench reports whole-program cycle counts only, not ARM920T instruction-cycle conformance; manual ch.12 timings assume cached accesses and external stalls are additional. Next build isolated instruction throughput/interlock measurement and address cache geometry/maintenance gaps without claiming cycle-exact behavior.

## 2026-11-03 live keypad and screenshots experiment

`python3 scratch/live-controls/start.py NAME` resumes overnight 23B by default; `NGAGE_CONTROL_CHECKPOINT=9000` resumes the 9B EtelServer dialog. Current live test `controls-dialog` was started from 9B and writes `build/sim/screens/boot-v15-controls-dialog-live/latest.png` plus cycle-numbered PNGs. In another terminal `python3 scratch/live-controls/keys.py list` shows experimental controls; `tap leftsoft`/`press KEY`/`release KEY`/`clear` write an atomic shared held-key mask, and only one live-control sim can use this shared input. EKeyB reads 0x3e row + 0x1e column during leftsoft press; short trace `softkey-trace` shows changed keypad-driver queue path vs `softkey-idle`, but a 35-second leftsoft press did not immediately dismiss the dialog, so UI key correctness remains unproven. An ensuing screen update at 9,202,896,827 shows Nokia logo; do not attribute it to any key without a control replay.

Schematic A-13 key mapping and hardware assumptions in `docs/live-controls.md`. Direction, center, leftsoft/menu, clear/radio, rightsoft, digits 0–9, star/hash, shift/send/end and music have named injection hypotheses. GPIO30/row-drive, music and low-level electrical behavior require validation; power PWRONX is not modeled. `latest.png` is seeded from last screen prior to checkpoint and updated on DMA events; direct LCD writes not yet streamed. Pressing a key does not guarantee a frame. User confirmed the left soft key dismisses the dialog on the phone. Next test: compare EKeyB queue / raw key event and WindowServer delivery against no-press control, then correct matrix/timing or wake behavior and demonstrate actual dismissal.

## 2026-11-03 Etel abort and physical rocker probe

At user request stopped overnight run around 23.18B (container SIGTERM; incomplete `result.json`); 23B paired checkpoint remains intact, no 24B result. User wants left soft key, then Menu, then stick directions and OK on an app. Schematic A-13 (`docs/ser-no-n-gage-schematics.pdf`, page 13; render `scratch/keypad-probe/schematic-p13.png`) labels left soft key matrix COL0 GPIO8/ROW0 GPIO12, Apps key COL1 GPIO9/ROW0 GPIO12; separate active-low rocker contacts: down GENIO10, left GENIO13, acceptance GENIO11, up GENIO1, right GENIO2. EKeyB `0x5041aaf0` reads 0x5815020a, inverts the halfword, and maps raw bit10 to logical 0x80000.

Isolated experiment `scratch/keypad-probe` based on frozen overnight RTL/23B checkpoint drives assumed inactive-high bits at physical 0x0c15020a then pulses down, left, center (three reads each), no changes to firmware or saved checkpoint. `boot-v15-rocker-down-left-ok` 20M cycles: bus shows down 0x2806, left 0x0c06, center 0x2406 and release 0x2c06. Detailed 100K-cycle `rocker-down-trace` shows EKeyB reads 0x2806 and produces logical 0x80000. No LCD DMA/update observed in that 20M-cycle run; this is not yet proof of UI key events, correct matrix polarity, waking/unlocking, or working games. Need implement left-soft/Apps matrix, trace debouncing/event delivery, test full user sequence and save live screens in resumed simulation. Prior arbitrary `0x0c150400` bit0 probe also reached firmware but has no verified real key meaning; do not conflate.

Targeted replay `boot-v15-etel-abort-a`, from 5B to 5,268,340,000 with full 20K-cycle window, reproduces abort cycle 5,268,334,447 in `phonetsy!ord1+0x17370` at actual Thumb PC 0x5095a9f2, after calls through `commdb!ord13`. CP15 FAR=0x000000bd, FSR=1 (alignment fault). Exception frame saves R7=0x85c0bb44 and R0=0xbd. Immediately preceding Thumb instructions `adds r0,r7,#0; adds r0,#0xbc` should calculate 0x85c0bc00, but observed trace shows first 0x85c0bb44 then 0xbd; apparent CPU operand/dependency error requires directed reproduction and independent verification (trace micro-op caveats apply). This differs from the older historical commdb null-row theory and is strong evidence for a CPU issue, but association to the later EtelServer dialog must still be established. Next compare frozen ZAP with Unicorn/ARM reference over exact preceding sequence, including the POP-to-PC return, then fix with directed tests if confirmed. A second abort at 6,879,480,924 remains untraced.

## 2026-11-03 overnight run: EtelServer app closed

User launched `overnight-c11-24b`, frozen write-through baseline from reset with copied 11B C: snapshot. It is running at >=9.13B cycles, live LCD capture works and `build/sim/screens/boot-v15-overnight-c11-24b-live/latest.png` shows `App. closed EtelServer` with OK button, latest captured LCD update at cycle 8,962,031,644. This is a guest application/server failure, not simulator termination. Cause, error reason, and whether still current require investigation; preserve running simulation and all billion checkpoints. Live DMA screenshot capture did not show the earlier direct full-screen clear before the first DMA; live monitor now shows later DMA-composited frames. Need add direct LCD transfer support for future runs without touching frozen source/binary currently executing. CP15 drain fix (patch 0016) is in working RTL but intentionally not in this frozen overnight run.

## 2026-11-03 overnight command and CP15 drain correction

Overnight command from project root: `python3 scratch/overnight/run_24b.py` (optional unique lowercase/hyphen run name). It starts at cycle 0 with a frozen copy of `wt-cdrive-11b.img` and PMM, uses an isolated frozen write-through simulator/source so subsequent RTL work cannot alter its behavior, and defaults to 24,000,000,000 cycles. Live screenshots: `build/sim/screens/boot-v15-overnight-c11-24b-live/latest.png` and `frameNNNN_cycleNNN.png`; screen is emitted only once all pixels have been observed. Incremental binary DMA records are emitted after each transfer. Offline verification reproduced all 14 previous LCD updates and exactly matched prior N-Gage final composite; 10M-cycle startup test passed and confirmed a final-boundary CPU/host checkpoint. End-to-end 115M-cycle live-display test is running (`overnight-live-check`); check its result before claiming verified live from a running simulator. Final checkpoint uses state after cycle limit-1, stored under boundary name, to support restoration. The frozen 24B binary predates the CP15 drain fix below.

Added `0016-cp15-drain-write-buffer.patch`: C7/C10/op2=4 no longer falls through to whole-cache clean/invalidate. The current core uses synchronous stores rather than an asynchronous buffer; focused `cache_drain.S` previously failed due to dirty cache data being written through during drain, now passes latency 0/3. `make sim-compat` passes; patch-series verification passes. Overlapping/background refill/buffer-drain semantics require further proof, and many manual omissions remain in `docs/arm920-manual-audit.md`; do not claim full ARM920T implementation. Bluetooth stub not implemented: NGVM `sw/kernel/chan.c` has an HLE controller, but this low-level core needs its actual CBUS/transport path and no hardware command protocol has been verified.

## 2026-11-03 12B error-log review

The 12B write-through replay ended by the configured cycle budget, no blocked address/reason. Retained guest debug text includes 10 each of `BTLDD: CompleteWithError: 1 -33`, HCI CBUS receiver ERROR -33, and HCI CBUS sender ERROR -33 (Symbian KErrTimedOut); timing/source and whether blocking are not established. It also includes `CSysApAppUi::ConstructL: Start listening`, evidence that system-app startup code ran, not proof of a fully usable UI. No explicit panic text appears in captured debug59 output; silence is not proof no guest thread panicked. Compact instruction log records two data-abort vector entries at cycles 5,211,321,217 and 8,172,097,472; origins and whether intentional remain uninvestigated. `fetch_bus_faults=36` counts bus fetch faults, which may include speculative fetches and are not by themselves crashes. Simulator output kept head/tail only and explicitly omitted 2,747,929,728 bytes; 5,073 captured warning lines mainly concern potentially unpredictable LDM/STM or halfword decoding, but may be speculative decode and need retirement correlation. This prevents exhaustive crash or warning claims. No previous StarterServer panic has been positively reproduced in the retained records; exact original failure and RFS outcomes remain to be checked. Useful next step is focused replay from a preserved checkpoint with compact probes around the two data-abort vectors / panic handler, followed by actual C: filesystem inspection.

## 2026-11-03 cleanup of pre-write-through simulations

At user request, removed identified pre-fix C4/auth35/auth36/earlier run folders, their old checkpoint files and related screen folders under `build/sim` after checking timestamps. Current write-through run, its 1B–11B CPU/host checkpoint pairs, screenshots, input images, and post-fix tests were preserved. Older sections below retain historical findings but paths to deleted run artifacts may no longer exist. `build/sim` decreased from 5.1 GiB to 1.4 GiB. The 12B checkpoint was never created; see next entry.

## 2026-11-03 write-through 12B replay completed: N-Gage logo

`boot-v15-wt-reset-12b` finished at its requested 12,000,000,000-cycle limit with status `timeout` (budget exhausted), no blocked address, 1,437,176,936 retired instructions. This exceeds the previous 9,385,739,603-cycle firmware shutdown, but does not establish that the specific flash timeout vanished or that Symbian fully booted. LCD composition used 14 DMA arms/14 update streams; `build/sim/screens/boot-v15-wt-reset-12b-composite/final.png` shows the N-Gage logo. Output is a reconstructed screen under documented LCD hypotheses. Boot profile reports 233,298 C: programming operations and zero erases (not bytes written). Latest retained checkpoint is paired `roll-wt-reset-12b-r11000`; the 12B milestone is MISSING because run terminates at limit without saving that boundary. Fix checkpoint-at-limit handling before the next run; never prune billion checkpoints. Extracted 11B drive `scratch/c4-after-boot/wt-cdrive-11b.img`, 64/64 LFFS signatures and 454,392 bytes differ from starting volume; not a filesystem listing or proof of health. No 12B drive snapshot exists. Next: trace guest progress at 11B/check end and determine whether prior flash timeout / nine RFS failures remain; use the extracted C: with existing HLE tools and compare actual files to `firmware/disk_dump`, with no claim of success until verified. Implement requested live screen capture before next long simulation.

## Next simulation: live LCD screen history

User requests that the next simulation produce actual screen images as the LCD changes, with a trail of timestamped/cycle-numbered frames available while the run is active. Implement incremental capture and compositing of full and partial LCD updates using the existing DMA/framebuffer evidence; publish the latest image and preserve update history under `build/sim/screens/`. Avoid fabricating a screen when there is insufficient data; distinguish partial/incomplete transfers and keep disk use reasonable. Verify against known Nokia-logo and partial-update traces before relying on it. Do not change or interrupt the current `wt-reset-12b` replay; its current live log yields full-frame images only, and `lcd-dma.tsv` is unavailable until run completion.

## 2026-11-02 write-through replay progress at 3.58B

Fresh `wt-reset-12b` run is still running at least 3,576,970,590 cycles; paired billion checkpoints at 1B, 2B and 3B are present. Extracted 3B C: checkpoint to `scratch/c4-after-boot/wt-cdrive-3b.img`: 64/64 LFFS block signatures, 308,736 bytes differ from the initial image. This is raw byte comparison, not a file listing or evidence of corruption. LCD full-frame extraction from the live bus log produced `build/sim/screens/boot-v15-wt-reset-12b-live-frames/frame01_c760081553_24d67f-lohi.png`, displaying a Nokia logo; this is the last complete extracted frame, not necessarily the current screen because later partial updates have not been composited (live `lcd-dma.tsv` is unavailable). No final result yet.

## 2026-11-02 write-through implementation and fresh 12B replay

Implemented page B-bit propagation through TLB and data-cache pending-translation state, and ARM920 write-through stores in `rtl/arm/zap_dcache_fsm.sv`. For C=1/B=0 a hit updates the cached line, and every hit or miss sends the original width/data to the bus; writes wait for bus acknowledgment, rather than using an asynchronous ARM920 write buffer. C=1/B=1 keeps the existing write-back path. Focused `sim/programs/cache_write_through.S` passes section hit/miss, halfword, write-back control, and write-through small page at latency 0 and 3. Full `make sim-compat` passes, including the new diagnostic. An initial version failed cache-hit coherence; fixed by clocking the RAM update while capturing the translated bus request on that edge.

Fresh run `boot-v15-wt-reset-12b` started from reset with budget 12,000,000,000, fresh C image `scratch/fresh-c-investigation/c4-reset.img`, factory ROM/extension and same PMM/power inputs as prior run; script `scratch/c4-fulltrace/run-write-through-reset.py`, simulator process session 34724. It writes checkpoints every billion to `build/sim/checkpoints/roll-wt-reset-12b-r*.cpu/.host`; the diagnostic harness no longer rotates billion-cycle milestones. Earlier checkpoints must not be assumed compatible after the RTL change or trustworthy after previous flash timeouts. Check process/result and screenshots under `build/sim/screens/boot-v15-wt-reset-12b`; no boot or C-drive outcome claimed yet. The wrapper hashes its default C input rather than the overridden C/PMM inputs: separately recorded SHA-256 values are C `8f7ce5de2a20a8cfcbb4967d77f89c40315ff97411ada9944fe65f8ca87b0482` and PMM `c7075d001311f5f122137fc891b2ade159fb39931810ae0d9965aea2a07e2496`. RTL change is reproduced in `patches/zap/0015-arm920t-write-through.patch`; the local upstream-plus-patches verification passed.

Manual chapter inventory and important outstanding cache, CP15, MMU, clock and debug gaps: `docs/arm920-manual-audit.md`. This is an audit inventory, not full conformance testing.

## 2026-11-02 write-through evidence and phone identification limit

Checked local ARM920T TRM (ARM DDI 0151C Table 4-1): when the CP15 cache-enable bit and page descriptor C bit are set, C=1/B=0 denotes write-through; all writes appear on the external bus, whether or not the data is in cache. C=1/B=1 is write-back, so a fix must preserve both behaviors. The actual boot firmware checkpoint's L1 descriptors explicitly set the command mapping to C=1/B=0 and poll mapping to C=0/B=0. The retained physical-phone virtual/physical map confirms both aliases but reports only VA/PA and sizes, NOT descriptor C/B or CP15: it cannot independently prove attributes on the real phone. Schematic identifies UPP_WD2 and three flash chips but does not identify its integrated CPU/cache. Local N-Gage reference calls it ARM920T; hardware ID/CP15 dump or authoritative UPP documentation is still needed to independently establish exact physical CPU/cache. Nevertheless original firmware and ARM920T semantics plus the observed missing bus transactions strongly justify implementing write-through in our ARM920T-compatible model and validating the replay.

## 2026-11-02 write-through cache missing: flash program never reaches bus

`c4-flash-poll` window 7,614,215,000:7,614,230,000 captures the fault: preceding halfword at PA 0x027e353c was programmed to 0x81bc. At cycle 7,614,226,359–410 CPU executes stores for AMD unlock AA to VA 0x59800aaa, 55 to 0x59800554, A0 to 0x59800aaa, then 0x0001 to VA 0x59be353e. The bus trace contains cache-line fills at those physical locations but no matching halfword programming writes for that second sequence; uncached poll VA 0x595e353e returns 0xffff and driver produces -33. Runtime L1 sections read from r7600: 0x59800aaa=0x0240043a and 0x59be353e=0x0270043a, C=1 B=0; 0x595e353e=0x02700432, C=0 B=0. ARM920T TRM local `docs/ARM920T_TRM1_S.pdf`, C/B table, specifies C=1 B=0 cached write-through: every write appears on external bus. Existing ZAP `rtl/arm/zap_tlb_check.sv` retains only cacheable C bit (drops B), and `zap_dcache_fsm.sv` marks cache hits dirty instead of forwarding every store. This is a strong, directly supported root-cause candidate for flash timeouts, not yet a tested fix. Implement ARM920 write-through handling while preserving write-back for C=1 B=1, propagate page-table B bit through TLB and data-cache pipeline, add focused tests covering hit/miss write-through halfword transactions, then replay the exact poll and verify AA/55/A0/data reach flash and no -33. Re-run allocator and boot after proving it; avoid firmware/flash patches. Cached 32-bit evictions previously ignored by model are likely consequences of wrong write-back treatment; do not blindly implement bare-word NOR programming. Preserve checkpoints.

## 2026-11-02 flash poll produces the timeout

Targeted store watcher `c4-timeout-writer` found kernel completion writes -33 to 0x80601a6c at 7,614,246,521, repeatedly for preceding flash requests. Full 20K-cycle trace `c4-timeout-origin` locates origin in the media flash driver: at 7,614,226,725 ARM 0x50385278 reads halfword 0xffff at virtual 0x595e353e and compares to expected 0x0001; at 0x5038528c it generates -33 on mismatch. Driver propagates this to the LFFS request. Trace also shows 8-word cache-line writes to physical C: flash such as 0x027e3520, which `cdrive_access` currently accepts and ignores in array-read mode. Whether these ignored writes caused the mismatch requires verification: inspect earlier flash command/program transaction, MMU cacheability and data-cache semantics; these could also be unrelated cache alias/writeback effects. Do not blindly make bare writes program flash, since AMD NOR requires command sequencing. No simulation running.

## 2026-11-02 timeout precedes allocation threshold drop

`c4-block-selection` confirms no observed CPU stores to the special-node pointer 0x80618878 or the last node fields +0x30/+0x38 between 7.6B and 7,614,350,000; selection may predate the checkpoint or use aliases. Full trace `c4-threshold-drop` shows immediately before the 0xf380 -> 0x80 subtraction, a virtual filesystem operation returned 0xffffffdf (Symbian KErrTimedOut = -33), propagated through ELocal 0x50395212 to retry wrapper 0x503906d2; wrapper retries on nonzero except -26. On retry, it matches last node 0x80619a68 against volume+0x10 and subtracts its contribution. Need find source of timeout and whether the retry/accounting behavior results from C: flash or another request; do not claim causation yet. Replay trace window began after timeout was placed in request status: capture earlier full micro-ops/bus around the request initiation/completion, possibly extend backward from r7600, or use a narrow store watcher to locate the producer. No simulator running.

## 2026-11-02 allocation threshold writers traced

Completed targeted replay `c4-allocation-writers` from r7600 to 7,624,803,500. CPU stores show live volume+0x2b8 repeatedly adjusted, then at cycle 7,614,340,400 ELocal actual 0x503966a4 reduces 0xf380 to 0x80. The candidate +24 fields are subsequently set to 0xec94 at 7,618,369,297 and 0x5578 at 7,624,778,921, explaining their later rejection against 0x80. Bounded complete 20K-cycle micro-op/bus trace `build/sim/runs/boot-v15-c4-threshold-drop/` captures the reduction: the firmware subtracts 0xf300 while processing list node 0x80619a68 (index 64); 0xf300 was derived from 0x1e6 shifted by 7, with another bound 0xffd0. This is guest accounting, not yet evidence that the arithmetic is incorrect. Next establish what this function is doing and why that final node is removed from the available pool; inspect its caller and predecessor operations, compare on-flash records and geometry. An HLE mount/write of the same snapshot is not a matching MkDirAll test. No simulation is running.

## 2026-11-02 allocator checkpoint caution

The r7600 checkpoint RAM image has a 64-node linked volume list. The first two nodes have uninitialized (`0xffffffff`) +24 fields in RAM; indices 3–63 are bypassed by the later allocator based on its current allocation range. At 7,624,793,666 the live CPU trace reads 0x80 from object +0x2b8, whereas saved r7600 SDRAM holds 0x11980 there. These are different times and cached writes may not yet have reached checkpoint SDRAM, so neither an intervening change nor the live field contents can be inferred from the old RAM snapshot alone. Trace the writer of virtual 0x80618b20 and the two candidate nodes, then correlate with actual flash operations before deciding whether allocation accounting or flash emulation is wrong. No simulation is currently running.

## 2026-11-02 allocator rejection trace

`c4-allocator` captured all CPU micro-ops and external bus traffic during 7624700000:7624803500. ELocal allocator loops through linked block candidates at 0x50391c10. Its usable candidate range leaves only blocks indexed 1 and 2 for detailed checks; their fields at +24 are 0xec94 and 0x5578. Both exceed threshold 0x80 loaded from volume object +0x2b8, and the allocator branches past them; it reaches list end with no selection and sets the persistent full flag at 0x50391d86. This is observed control flow, not yet a decoded interpretation of the fields or proof of full physical storage. Need determine field +24 and threshold semantics, why only candidates 1/2 qualify for detailed checks, and whether layout/geometry or earlier flash operations yielded those values. The failure likely originates before the later first MkDirAll, not in MkDirAll itself.

## 2026-11-02 LFFS allocator sets full flag

The software emulator mounted a copy of the r8000 C: snapshot and made 1585 writes over 16 seconds, no StarterServer panic (`scratch/c4-after-boot/hle-r8000.log`), but it did not reproduce the exact same MkDirAll call, so this does not establish physical correctness. Isolated `c4-full-flag` replay found the guest CPU store: cycle 7,624,802,477, ELocal actual Thumb `0x50391d86` writes 1 to `0x80618af8`, then returns -26. Disassembly `0x50391c..0x50391d9a` shows candidate-selection loop and enters full path when no candidate was chosen (`r9 == 0`). Need establish why, not assume true exhaustion.

A bounded full CPU/bus trace `c4-allocator`, window 7624700000:7624803500, replayed from r7600, is running. Inspect `scratch/c4-fulltrace/allocator.log` / `build/sim/runs/boot-v15-c4-allocator/`, correlate candidate headers/geometry and look for modeled flash read/write anomalies. No firmware or canonical drive modified.

## 2026-11-02 LFFS full flag set between 7.6B and 7.7B

NGVM loaded a COPY of the 8B C: snapshot and over 16 virtual seconds mounted it, logged 1585 C: writes and no StarterServer panic (`scratch/c4-after-boot/hle-r8000.log`); the 9.3B snapshot also mounts and writes. Different HLE boot and software peripheral assumptions mean this is not yet a direct MkDirAll comparison. The low-level trace pinpoints ELocal `0x50392abc..c4` loading C: volume object's `+0x159a8` state flag (`0x80618af8`), seeing 1 and returning -26 immediately before allocation. The flag is 0 in saved 7.0–7.6B checkpoints and 1 at 7.7B–8.0B; the flag's meaning and why it was set are unproven.

Isolated scratch diagnostic `scratch/c4-fulltrace/main.cpp` now logs CPU store micro-operations to virtual `0x80618af8` (no firmware changes) as well as optional bounded full windows. Replay `c4-full-flag` from `roll-c4-rfs-7b-r7600` to 7700000000 runs with physical `watch-addr=0x0a0a6af8` and same PMM/C: inputs. Log `scratch/c4-fulltrace/full-flag.log`, result `build/sim/runs/boot-v15-c4-full-flag/`. Inspect virtual store trace to find who sets the flag; if absent, check process-specific mapping, cache behavior and DMA. Preserve billion checkpoints and avoid interpreting FF byte counts as LFFS free space.

## 2026-11-02 first disk-full path is C:\System\Bootdata\

The `c4-mkdir-state` replay captured `idle-c8037.host` at cycle 8,037,662,500 immediately after the first -26. In `c4-first-diskfull` instruction trace RFS restores R4=`0x004033d8`; MkDirAll receives descriptor R4+0x1c=`0x004033f4`. `scratch/tools/inspect_checkpoint.py` translation of that descriptor at the checkpoint gives length 19 and UTF-16 text `C:\System\Bootdata\`. Thus the first failure is creating the C: bootdata directory. The image from the 9.3B checkpoint is 4 MiB with 238,937 non-FF bytes, but this is NOT a valid free-space measurement for a log-structured filesystem. Do not assume it is genuinely full. Next trace the EFile/ELocal operation that produces -26, determine LFFS mount/free-space accounting and flash geometry, and compare with the HLE run on a copy of the same 4 MiB image.

## 2026-11-02 first disk-full is RFs::MkDirAll

`c4-first-diskfull` traced the first -26: RFS invokes import at 0x50a980fc, slot 0x503e3e5c resolves to 0x503de559 = efsrv `RFs::MkDirAll`; it returns KErrDiskFull. Thus failure is creating a directory, not evidence that a file copy itself fails. The operation's guest path and target drive are not yet identified; the call started before the 30K-cycle trace window. `c4-mkdir-state` replay from r8000 is running to capture checkpoint-at 8037662500 shortly after first failure; command log `scratch/c4-fulltrace/mkdir-state.log`, intended stem `idle-c8037`, and inspect the RFS process descriptors and mapping to identify the path without modifying firmware.

## 2026-11-02 all nine RFS failures are KErrDiskFull

`c4-rfs-errors` replay from r7900 completed; selected pc logs capture 39 RFS operation results: 29 zero, nine `0xffffffe6` (-26 = KErrDiskFull), and terminal -100. All nine RFS counter increments 1..9 correspond to -26; the first at cycle 8,037,667,054, last at 8,061,461,805. This identifies the immediate cause of restore failure, not which drive or why it reported full. A genuinely full C:, D: RAM drive or incorrectly modeled geometry/free-space/allocation remain hypotheses. Reference: `/Users/andreabogazzi/develop/n-gage/sw/kernel/kobj.h` and EKA2L1 `src/emu/utils/include/utils/err.h` both define -26 as disk full.

`c4-first-diskfull` focused replay launched from `roll-c4-rfs-7b-r8000` to 8037670000 with complete CPU/bus window 8037640000:8037670000, logging under `build/sim/runs/boot-v15-c4-first-diskfull/` and `scratch/c4-fulltrace/first-diskfull.log`. Determine originating file-system call, drive, path and free-space/geometry before fixing. Original firmware and C: images remain unchanged.

## 2026-11-02 complete bounded trace: 9 is RFS failure count

User requested full traces for sub-million-cycle windows. An isolated simulator in `scratch/c4-fulltrace/` records all available CPU micro-operations and all external bus transactions in `window-bus.tsv` for `win-trace`; cached internal accesses are only represented by CPU trace, not external bus. `c4-fulltrace` replayed r8200 through 8,266,873,000 with full window 8266000000:8266872000. Trace found the actual CPU store at cycle 8,266,859,584: Starter `0x5096d120` writes 9 to virtual 0x00402240; RFS client returned it from stack request status, rather than the later cache-line writeback. RFS server at 0x50a97494 initializes r6=0, loop at 0x50a974b6 processes script operations, increments r6 at 0x50a974e2 when an operation/trap failed, and passes r6 to completion at 0x50a974fc; trace at 8,266,716,360 sets argument r1=9, propagated to Starter. Therefore 9 is the number of failed restore-script operations, not a single Symbian error code. Actual cause and which commands failed remain unknown.

Targeted `c4-rfs-errors` replay from `roll-c4-rfs-7b-r7900` to 8267240000 is running to record script loop results and failure count via pc-log; `scratch/c4-fulltrace/errors.log`, outputs `build/sim/runs/boot-v15-c4-rfs-errors/`. The nine failures may predate r7900; if so find an earlier checkpoint. Follow up by correlating individual command result/status to script operations, not modifying firmware or bypassing errors.

## 2026-11-02 correction: observed write of 9 is a cache-line writeback

`c4-rfs-write` completed from r8200 to 8,266,872,000. At cycle 8,266,870,059 the watched physical address 0x0a0e7240 is written 9, followed by seven consecutive writes at +4..+28: this is an eight-word dirty cache-line writeback, not the guest instruction that originally stored the RFS result. Simultaneous CPU instruction is an unrelated LDR at `0x503a8104`, not the producer. Thus 9 is confirmed as the value in memory, but its origin remains unknown. Next identify the CPU-level store to the translated virtual slot `0x00402240` or its cached physical alias, accounting for process/MMU mapping and cache, then correlate it to RFS file/IPC results. This avoids interpreting later physical writeback as the source. The exact earlier Starter panic, original firmware RFS script access, and successful merged PPM root evidence remain as documented below.

## 2026-11-02 correction: RFS result is 9; trace load showed an intermediate uop

Focused `c4-state9` replay from r8200 shows `memory-tail.tsv` physical `0x0a0e7240` is written with 9 at cycle 8,266,870,059 and read as 9 at 8,267,049,279 and 8,267,228,582. The apparent `00@00000000` on the LDR trace line at 8,267,228,581 was an intermediate uop, NOT the completed load result; the caller receiving 9 is consistent with memory. Do not diagnose a CPU bug from that line. This corrects the immediately following prior section's claim that RFS returned zero. The next Starter code passes 9 through `0x5096d1f4` and later double-activates the object.

A targeted replay `boot-v15-c4-rfs-write`, from `roll-c4-rfs-7b-r8200`, window 8266868000:8266872000 with `watch-addr=0x0a0e7240`, is running; inspect `scratch/c4-after-boot/rfs-write.log` and its instruction/memory traces for the PC causing the write of 9. Identify whether 9 is an RFS status/count and what file operation or underlying hardware response produces it; do not skip or alter guest execution.

## 2026-11-02 7B replay result: real script call returns zero

`c4-rfs-7b` completed and reproduced the same shutdown at 9,385,739,603. Targeted instruction log shows Starter passed the real ScriptInit descriptor `0x5096ecb8` into `RRfsClient::RunScriptInFile` at cycle 7,988,093,454. At cycle 8,267,228,581 Starter loads return 0 at `0x5096d13c`/underlying `0x5096d140`; then at 8,267,228,815 `0x5096d1f4` receives argument 9. Therefore the prior note that RFS itself returned 9 is incorrect: observed restore return is 0; identify the separate caller/state producing argument 9 and why its handling leads to repeated SetActive at 9.385B. Between those points the system may switch threads and the sparse pc-log does not capture the control path. The 7B replay's full bus and resulting latest checkpoints remain under the run folder / `roll-c4-rfs-7b-*`; use a focused instruction window near cycle 8,267,220,000–8,267,235,000 with a compatible nearby checkpoint or inspect source and saved stack. Do not claim script failure.

## 2026-11-02 7B restore-call trace

The `c4-rfs-9b` targeted replay completed and reproduced `PLAT` panic at cycle 9,385,739,603. Its selected RFS/restore call PCs produced no earlier hits, so the request may predate its 9B checkpoint (or probe addresses may need correction); it does not establish the origin of status 9. A new `c4-rfs-7b` replay was launched from `keep-c4-reset-12b-r7000` to 9385741000 with selected pc-log probes, same fresh C:/PMM/options; log `scratch/c4-after-boot/rfs-7b.log`, result and instruction log under `build/sim/runs/boot-v15-c4-rfs-7b/`. The original run reads ScriptInit body by 7,993,173,685; watch for RFS calls, results and original panic.

## 2026-11-02 live root pointer verified at 9B

Checkpoint `keep-c4-reset-12b-r9000.host`, decoded by `scratch/tools/inspect_checkpoint.py` with the runtime L1 page table: kernel VA `0x80006678` contains `0x5123e318`, the selected PPM combined Z: root. This is independent evidence that the running firmware uses the PPM root (not merely a raw flash read); the extension is discovered and 1619-entry tree including rfs is reachable through that root. It still doesn't prove all file operations are correct or actual C:/peripheral hardware matches the phone.

## 2026-11-02 targeted 9B restore replay

Compared actual PPM extension merged root at `0x5123e318` (1523 files) with supplied NEM-4 extracted Z: 1092 common paths, 1090 identical bytes, 2 different language configuration files; 432 host-only / 431 PPM-only names are largely different language resources. 19 of 21 Z: sources in real ScriptInit.txt are present and byte-identical to the extracted Z; only Mixpix swap.mix / slide.mix are absent from both. This comparison supports much of the PPM mapping but doesn't prove every device/ROM operation.

Static disassembly identifies `0x5096d04c` -> `0x5096d0b4`; the latter connects to `RRfsClient`, invokes `RunScriptInFile` when a filename is supplied, or `PerformRfs`/`PerformPostEikonRfs` otherwise; return value is retained and later led to the StarterServer double-SetActive panic. A targeted replay from r9300 captured no such call prior to panic: the relevant request may have started earlier, so do not infer why it returned 9. New replay `boot-v15-c4-rfs-9b` from `keep-c4-reset-12b-r9000`, same C:/PMM/options, budget 9385741000 with selected pc-log addresses, was launched; log `scratch/c4-after-boot/rfs-9b.log`. Check result and pc-log, avoid large traces. Earlier 9.3B replay completed and reproduced the same panic but did not capture the original RFS call.

## 2026-11-02 correction: firmware DOES read PPM root and restore script

The earlier missing-visible-root conclusion was WRONG: it came from parsing the immutable main ROM header's core root, not the root selected during boot. The Nokia PPM has a valid extension header at VA `0x51230000`, including combined-root list `0x51230080`; its root `0x5123e318` enumerates 1619 entries, including `System\rfs\ScriptInit.txt` at 0x5132de10. The 0x70000 FF bytes before it do not prevent discovery: actual `c4-reset-12b` bus trace reads the PPM extension header at cycle 113,846,925, reads the real rfs directory 6078 times from 685,324,940 through 9,379,008,340, and reads the script body 1054 times from 717,121,431 through 7,993,173,685. These accesses refute the claim that missing root alone explains the panic. Exact role of each read and success of the later RFS request remain to be traced.

The real PPM script has 21 Z: copy commands: 19 named sources exist in the PPM combined tree and their bytes match the separately extracted NEM-4 Z folder; two Mixpix sources (`System\Apps\Mixpix\swap.mix`, `slide.mix`) are absent from both the selected PPM tree and disk_dump/Z. Their role in the panic is unproven. Across the combined tree and supplied NEM-4 extracted Z there are 1092 common files, 1090 byte-identical and two different language metadata files; the many differing filenames are largely language variants, so do not treat either tree as a perfect reference for the chosen PPM.

The controlled NGVM experiment still proves that hiding the script CAN produce the same StarterServer E32USER-CBase 42, not that this was the low-level crash cause. Need trace the original RFS script execution, return 9, and the Starter reentrant SetActive in the actual low-level run. Identify which request returns 9 and its missing files or device error, and compare with HLE behavior without treating it as physical truth. Do not patch ROM or RAM.

## 2026-11-02 strong root cause: missing ROM extension root

The Z: entry and file are in the original selected Nokia PPM `.326`: its extension directory entry at virtual `0x5123d9ac` points to `0x5132de10` (size 2106). The exact file is `firmware/Nokia N-Gage/Data/drives/z/NEM-4/System/rfs/ScriptInit.txt`; PPM physical addresses are 0x0072de10 for content and 0x0473d9b6 for entry name. `RomFs._dir(0x5123d9a8, "\\System\\rfs")` enumerates it and script0/1. But the current main ROM header at 0x50000094 points to core root list 0x50317000, whose 1107-entry tree has no System/rfs. The tail begins with 0x70000 erased bytes (VA 0x511c0000..0x5122ffff), including the extension header/root-link area; previous `sim/rom_extension.py` reconstructed a synthetic header and merged directory in that gap. Thus PPM content exists but is not reachable from the selected root; missing CNT metadata or incorrect mapping/init is plausible, not yet proven. Earlier note calling the script absent from the ROM was imprecise: absent from visible root, present in PPM.

Controlled NGVM A/B in isolated `scratch/fresh-c-investigation/ngvm4` with identical logical SYM.ROM, 4 MiB erased C: and synthetic deep-restore: (A) remove its empty-script overlay -> same StarterServer E32USER-CBase 42 panic and exit 99, `scratch/c4-after-boot/ngvm-no-script.log`; (B) provide actual 2106-byte PPM-matching script through the HLE directory overlay -> StarterServer does not show that panic over 16 virtual seconds, 9733 C: write events, `scratch/c4-after-boot/ngvm-real-script.log`. This strongly supports missing visible script as the cause; it does not prove any reconstructed ROM header matches physical hardware. NGVM has other HLE limitations and an unrelated AudioServer panic. Neither test modified firmware.

Next: establish authentic factory CNT/extension metadata or correct boot/mapping that links PPM directory; compare live ROM root and mount state to recovered dump. Any synthetic extension/ROM overlay must remain explicitly labeled as diagnostic and not presented as original firmware. Then run low-level firmware against verified extension and confirm StarterServer no longer panics and display reaches N-Gage splash.

## 2026-11-02 StarterServer panic and missing restore script

The 9.385B PLAT 91 fault is secondary: replay shows thread object `0x8040f108`, whose name descriptor at `0x8040d06c` says StarterServer, panics with category E32USER-CBase and reason 42. The actual ROM instructions show `CActive::SetActive` at 0x50399c04 seeing active flag 1 at `0x00402174`, for object `0x0040216c`; the same Starter function 0x5096d778 calls RequestComplete and SetActive twice before the scheduler has cleared the flag. First call is reached from 0x5096caa2; second from 0x5096cf7e, after Starter `0x5096d04c`/`0x5096d0b4` returns 9 and its error handler 0x5096d1f4 re-enters `0x5096ca2c`. Symbian SDK documents E32USER-CBase 42 as SetActive on an already-active object. Earlier inference that a null pointer was the root cause was wrong; the pointer was used in panic reporting.

Strong, unverified hypothesis: 0x5096d04c passes `Z:\system\rfs\ScriptInit.txt` to restore functionality. `RomFs.files()` finds no `System\rfs` directory in the logical SYM.ROM or assembled service image. The source `n-gage/sw/kernel/rom.c` explicitly supplies an EMPTY `System\rfs\ScriptInit.txt` entry to its HLE Z: overlay and says its absence breaks first boot. Real extracted phone Z: folders DO contain ScriptInit.txt, with two non-identical versions (2266 and 2106 bytes). Source body fragment exists in the assembled extension, but its full 2266-byte version was not found; content/availability and root directory provenance remain unresolved. The selected package's missing retail CNT content may matter. Do not patch firmware or C:/RAM to bypass the crash, or assume absence proves causation. Targeted earlier replay `boot-v15-c4-rfs-trace` is in progress from r9300, focusing 9385600000:9385700000; inspect return value 9, actual RFS call and file-server result, and compare physical versus logical ROM filesystem root and real dump.

## 2026-11-02 shutdown replay: PLAT fault

Targeted replay `build/sim/runs/boot-v15-c4-stoptrace/` reproduced the original stop at cycle 9,385,739,603 from r9300. The instruction trace identifies a kernel fault with category `PLAT` (UTF-16 ROM string at 0x50347118) and fault code `0x0001005b` (91 plus 0x10000), then shutdown and masked-interrupt park 0x50324294. The preceding path includes 0x5033390c (R0 = -2), 0x503336d0, 0x50333708 loading 91, 0x50333ca4 and 0x50333e70. Meaning and triggering failure are not yet established; repeated HCI/BTLDD timeouts occur in the NOS trace but causation is not established. Inspect preceding operation and caller context rather than assuming Bluetooth causes this PLAT fault.

The `saur0n/unpacker` GitHub README and source tree were inspected via gh: it documents newer BB5 FPSX and read-only ROFS formats; no LFFS handler was found, so it is not currently a solution for enumerating this raw C: volume. Raw extracted C: and comparison notes are in the next section.

## 2026-11-02 fresh C: extraction and shutdown replay

The user-requested fresh C: long run halted at cycle 9,385,739,603 (`firmware_loop`, PC `0x50324294`, IRQ/FIQ masked), before 12B. Reconstructed final display `build/sim/screens/boot-v15-c4-reset-12b-composite/final.png` is Nokia logo. Checkpoints 7B, 8B, 9B preserved under `keep-c4-reset-12b-*`; 9.3B rolling checkpoint is available.

Extracted C: from `roll-c4-reset-12b-r9300.host` to `scratch/c4-after-boot/cdrive-r9300.img`, SHA-256 `aeee64ed9102427eec340f7da8d16789650fc02e26989e828dfde170dd00b3d3`, 4 MiB, 64 LFFS block markers. 58,494 bytes across 61 blocks differ from the fresh starting image; it is byte-identical to pre-existing `build/firmware/thc/cdrive-stamped-4mib.img`. The fresh generated starting image was itself byte-identical to older `cdrive-formatted-4mib.img`; deterministic first-boot writes may explain the final match, but independent live tracing of actual input is limited by runner provenance hashing the default input, so don't claim more. Embedded UTF-16 candidates include System.ini, HALData.dat, LocaleData.D01, Shareddata, bootdata, Cdbv2.dat; these are not an enumerated live directory and stale records are possible. No LFFS file extraction or file-by-file comparison to disk_dump/C is available yet.

BootProfile `debug59_text` has repeated Bluetooth HCI/BTLDD -33 messages and no literal ASSERT/PANIC/RTC string, but their causal role is unproven. Targeted replay `boot-v15-c4-stoptrace` starts from r9300 with window 9385700000:9385741000 and same fresh C:/PMM/options, log `scratch/c4-after-boot/stoptrace.log`; check result and instruction trace before further conclusions.

## 2026-11-02 checkpoint retention requirement

User requires each billion-cycle checkpoint to be preserved, independent of the rolling window. Current running binary retains only 30 rolling checkpoints; do not modify its hashed sources during the run. Background keeper `scratch/checkpoint-keep/keep-billion.py` copies current run milestones to `build/sim/checkpoints/keep-c4-reset-12b-rN.{cpu,host}`, verifying SHA-256; log `scratch/checkpoint-keep/c4-reset-12b.log`. The 1B–6B checkpoints had already expired before this request and cannot be recovered from this run. After it ends, implement permanent billion-cycle retention in the simulator for future runs and validate that rolling cleanup cannot delete milestone pairs.

## 2026-11-02 fresh C: 12-billion-cycle run

At the user's request the initial 1.3B run and attempted resume were stopped and their generated drive and test artifacts deleted. A replacement 4 MiB C: `scratch/fresh-c-investigation/c4-reset.img` was generated from no save in the isolated NGVM emulator, using its synthetic deep-restore mode. The original logical SYM.ROM issued 3364 writes over 12 virtual seconds; this is therefore formatted and includes first-boot data, not an empty filesystem. SHA-256 `8f7ce5de2a20a8cfcbb4967d77f89c40315ff97411ada9944fe65f8ca87b0482`. Generation log `scratch/fresh-c-investigation/c4-reset-generation.log`.

From-reset LLE simulation `boot-v15-c4-reset-12b` launched with budget 12,000,000,000 cycles, fresh `cdrive-image=/work/scratch/fresh-c-investigation/c4-reset.img`, `pmm-image=/work/build/firmware/pmm-aan.bin`, `cbus-input=0x24=1`, `uem-power-status-extra=2`. Log `scratch/fresh-c-investigation/c4-reset-12b.log`; outputs `build/sim/runs/boot-v15-c4-reset-12b/`; rolling checkpoints `roll-c4-reset-12b-*` (last 10). It was running when recorded. Inherited provenance hashes the default C: path, not this override; independently validate the hash above and input stability. On completion extract the checkpoint C: overlay, determine how to list/export LFFS files, and compare with `firmware/disk_dump/C` allowing for user files. Existing canonical C: image was not replaced.

## 2026-11-02 Nokia service package factory-set clue

`firmware/MCU/extracted/products/NEM-4/NEM_4.ini` configures `FactorySetEnabled=1`, `FactorySetLevel=0`, a 120-second timeout and mode changes including a section explicitly marked Before Factory Set. Product variant INIs such as `0507871.ini` name MCU `.3c1`, PPM `.302`, and `RestoreDefaultRestore=1`; the supplied README identifies Phoenix 2003.29 or newer and FPS-8 firmware as requirements. These are evidence of a configured service factory-settings operation, not proof that it formats C:, erases which range, creates content, or sets a particular startup reason. The package also contains product-profile settings, not an identified raw C: image.

The MCU container includes an on-device flash algorithm already extracted to `scratch/nem440-flash-extract/out/nem440-3c1-algorithm.bin`; earlier `claudia-handoff/flashing_how.md` studies its flash program/write transform. The actual Phoenix host application and a full factory-set command trace have not been identified in the local package: InstallShield files are installer support, not evidence of Phoenix itself. Next: correlate the configured level-0 factory-set operation with service documentation or original host traffic and firmware handlers, identify whether it sets HelperDrv's startup reason or invokes an actual C: format, and separately establish actual flash partition and package erase commands. Preserve the distinction between absent image records and a verified erase.

## 2026-11-02 original package and C: coverage audit

`scratch/package-c-audit/audit.py` re-parses the actual `firmware/MCU/extracted/products/NEM-4/nem440.3c1` and `.326` files, validates every record checksum and reconstructs the current simulator's `core.bin` and `extension.bin` byte-for-byte. Saved output: `scratch/package-c-audit/result.json` (2,268 MCU + 167 PPM records). The PPM header and address overlays follow the existing assembler; unwritten holes are filled with FF, an assumption, not supplied bytes.

Neither of those two package files has ANY data record overlapping the current model's assumed C: window `0x02400000..0x027fffff`. The MCU range ends at `0x023fffff`; PPM records target other ranges. This does not establish the physical C: mapping, prove the window is erased on real hardware, or rule out a separate content/service file. Existing `cdrive-stamped-4mib.img` is emulator-generated, NOT present in the packages. Do not describe it as package-derived or change the default to an empty drive without testing the original firmware's initialization path and actual flash layout. The assembler explicitly notes a missing retail CNT region; the logical Z: completeness claim must remain qualified.

NGVM independent experiment in `scratch/fresh-c-investigation`: original logical `SYM.ROM`, no existing save, NGVM's synthetic deep-restore signal, output `ngvm-fresh-1m.img` (16/16 LFFS headers, 2286 write events); this establishes only the HLE path. Real-kernel deep-restore initiation and 4 MiB formatting remain unverified. A 4 MiB reference rebuild was interrupted at user request; do not treat its artifacts as completed.

## 2026-11-02 simulation cleanup

Removed obsolete generated runs, screens, and checkpoint series to reduce `build/sim` from about 19 GiB to 1.2 GiB. Retained auth35/auth36 and current c1/l2/l3/l4/h5/h6 run evidence, current logo and reference screenshots, and checkpoint stems idle-c12118, idle-c12118-r12100, roll-auth35-r3000/r4000/r5000/r5900, roll-auth36-r9000/r10000/r11000/r11900, roll-l3-r12100, roll-l4-r12100 and roll-w2-r12500. Old dated entries below are historical and their paths/checkpoints may no longer exist. Firmware images and source files were not removed. No simulator container was running when cleaned.

## 2026-11-02 C:/Z: image provenance and HLE comparison

The auth35/auth36 provenance source hashes for `nem4-factory/core.bin`, `extension.bin`, and `thc/cdrive-stamped-4mib.img` match the current files. This checks these three inputs only; auth35 still reported another input changed during the run, so it does not validate that run's full provenance. Auth35 starts with the 4 MiB stamped C: image; auth36 restores the C: state from the auth35 checkpoint. The image descends from ngvm's firmware-formatted 4 MiB volume, later harvested from an LLE checkpoint after its first-boot writes; it is not a raw dump from a real phone or a fresh erased volume. An empty 32-byte `C:\System\Data\Cdbv2.dat` was previously observed in that image (see older comms DB entries), but its involvement in the current AppArc issue is unproven.

The earlier LLE erased-C: attempt read all-FF and returned KErrCorrupt with no flash writes or erases. This proves only that this firmware/model combination did not format on that path; it does not establish factory requirements or real phone behavior. In ngvm, the real user-side firmware formatted an erased, HLE-exposed formattable drive, generating the ancestor image. Compare media attributes (especially FORMATTABLE), reported size and erase geometry, format call path, and flash command/completion behavior before concluding why the LLE differs. Retest with separate from-reset inputs and preserve the existing lineage.

EKA2L1 is a different HLE reference: `system/src/epoc.cpp` `load_rom` parses/maps the logical ROM and creates a ROM filesystem, while `mount_device_drive` creates and mounts host directories for C:/D:/E:. It does not reproduce the physical C: LFFS/flash initialization. Use it to compare guest-visible Z: directory entries, file bytes, and filesystem notifications against the real ROM and observed requests, not as an oracle for physical flash behavior. For the current KErrCorrupt, first trace request/drive/path and the failed check; its relationship to AppArc notification remains unknown.

## 2026-11-02 handoff: AppArc rescans, cause unresolved

Observed: auth35 ran from reset to 6e9 without a halt, with a Nokia logo
DMA update around 2.77e9 and a blank update around 5.78e9. Its runner warned
`Inputs changed while simulation ran; do not use result`: frames were rendered
manually, but input provenance must be checked before treating this as a
validated clean run. auth36 resumed `roll-auth35-r5900` to 12e9 without a
halt or further LCD DMA updates. Neither the N-GAGE splash nor home screen
has been demonstrated on this lineage. Names found in RAM alone do not prove
that every named process is running.

AppArc repeatedly enumerates `Z:\System\Apps`; observed starts at
11,957,042,554, 12,118,600,200, 12,288,493,473 and 12,457,216,888 cycles.
Trace at one boundary shows `RFs::NotifyChange` completion followed by
`CApaFsMonitor::Start` and `CApaAppList::StartIdleUpdateL`. An ELOCAL
`KErrCorrupt` (-20) leave occurred at 12,118,578,671, about 21,500 cycles
before that notification, but causation, drive, operation and path are not
established; 28 such leaves per 200M cycles are not one-to-one with scans.
The earlier claim that the periodic timer alone drives rescans was corrected
by the notification trace. No MMC/card-detect activity was observed at the
investigated boundary; do not change that model on the earlier speculation.
The claim that the UI waits on the scan is also not established.

Next: inspect `idle-c12118` or a nearby available checkpoint and trace the
ELOCAL leave to identify its request, drive, path and corruption check; then
determine independently what completes `NotifyChange` and whether the two
events are related. Fix only an evidenced board/model or content defect;
do not patch firmware or guest RAM. Resume from a compatible checkpoint if
the change permits, and composite any LCD updates. The last delegated
investigation failed with HTTP 429 before producing a result. Local generated
checkpoints, firmware inputs and run artifacts under `build/` and `scratch/`
may not exist on another machine; verify their availability and provenance.
The auth35/36 inputs included `pmm-image=/work/build/firmware/pmm-aan.bin`,
`cbus-input=0x24=1` and `uem-power-status-extra=2`; these and the peripheral
models are hypotheses, not independently verified phone behaviour. See
`docs/README.md` and `docs/bringup.md` for evidence and simulation commands.

## 2026-11-02 ~03:00 auth35 preliminary observation (superseded by handoff above)

Board cycle counter (NOS time base) now saved in checkpoints (commit
6e8c491; before, every resume restarted NOS time at 0 - the auth34 halt at
3.7e9 reproduced only from r2400; a resume artefact is plausible, not proven). auth35 from
reset with all fixes (pmm-image=pmm-aan.bin cbus-input=0x24=1
uem-power-status-extra=2) ran 6e9 cycles with NO halt: Nokia logo DMA at
2.77e9, full blank (wserv) frame at 5.78e9. Kernel memory at r5900 holds
names associated with the S60 stack: Windowserver/EwSrv, FbServ, SplashScreen
(S60SplashScreenGroup), SysAp, Startup, Phone/PhoneServer, Menu,
SecurityNotifier, ViewServer, AppArc, DosServer, C32/ETel, Alarm/Calendar/
Contacts servers, BTServer, AudioServer, ClockApp2. BT HCI over CBus keeps
timing out (-33); their ultimate effect is unknown. auth36 continued r5900 -> 12e9 (old
patched lineage showed the N-GAGE splash 5.9e9-9e9). Checkpoints
roll-auth35-r* are the consistent lineage to resume from.

## 2026-11-01 ~23:00 *** NOKIA LOGO ON THE AUTHENTIC PATH *** (update made with Claude)

Original scrambled ROM + inline descrambler + real NOS, no stub/patches:
run boot-v15-auth34 (resume roll-e3-r2400) DMA'd the Nokia logo frame
(lcd-dma.tsv frame 0, 18304 words, 59 colours; copy in
build/sim/screens/milestone-authentic-nokia-logo/). Fixes since ~21:00,
all hypotheses in boot_profile.cpp: NOS timer IRQ (UPP id reg 0x0c150100
bit 0x80, compare 0x0c150118 on 1 kHz counter 0x0c150116, ICU bank0 b25),
DSP MDI handshake stub (D2M frame from PN dev 0x7C after DSP start ->
MTC no reset, ecust flag -> 3 at 759M), 1 kHz NOS tick (32 kHz starved the
kernel thread), UPP soft interrupt 0x1000 drains the ENOS func queue
(Enos_int.cpp:760 assert). EFile/EStart start ~759M.
NEW STOP: auth34 kernel park 0x50324294 at 3,700,148,646 right after
repeated "BTLDD: CompleteWithError: 1 -33" / "[HCI] CHCTLCBusReceiver/
Sender ERROR -33" (KErrTimedOut) - Bluetooth HCI over the control bus has
no model. Checkpoints roll-auth34-r* up to r3600.

## 2026-11-01 ~21:00 ROOT OF BOTH STALLS: MTC never reaches state 0x0c (update made with Claude)

Chain (PROVEN, sim + disassembly): Symbian user side never starts because a
thread busy-waits at ecust 0x50348a48-5c for ecust flag (0x80404110) bit 1
(same bit whose absence caused the RTC: fault). The NOS entry 0x5149d284
DOES return (750.0M, Sonnet re-check). Bit 1 is set by NOS setter
0x514a4a88(1,1) from EKIF handler 0x51668a40, called by
EKIFTask_RecvMessage on MTC_STATE_INFO_IND (0x5159ef98) when the new MTC
state byte [msg+3] == 0x0c. In run boot-v15-mtcst (resume r700 -> 1.2e9)
MTC's state-change routine 0x514c5b68 runs ONCE (747.76M, state byte
0x8001095a=3) and no MTC_STATE_INFO_IND ever reaches EKIF: the MTC
startup-group activation for the next state never completes (some NOS
server never answers COMMGR_GROUP_ACTIVATE). The midnight-alarm EKIF path
is not the intended source of bit 1. NEXT: log COMMGR group members and
their activate responses (0x515bfb00/0x515bfbf4/0x515bffa4) to name the
server that never answers; suspect DSP-dependent servers (no DSP model).

## 2026-11-01 ~19:30 SELF-TESTS PASS; boot idles in Symbian kernel init (update made with Claude)

NOS startup self-tests (ST_UPP_REGISTER_VER, ST_UEM_CBUS_IF, ST_EAR_DATA_LOOP,
ST_TX_IDP_LOOP, ST_SIM_CLK_LOOP, ST_SIM_IO_CTRL_LOOP, ST_MBUS_RX_TX_LOOP,
ST_BACKUP_BATT; runner 0x5164a914, table 0x516f785c) all pass after the
GPIO loopback/set-clear model (commit 383d915). Before that, a failing
severity-0xc test set MTC startup state 0x800107e0 = 8 ("SELFTEST_FAIL:
FATAL"), EKIF then aborted the startup group (reason 3) and MTC powered off
at 754M. Power-key boot: UEM 0x3f bit 1 at reset -> bootstrap 0x50003108 ->
ecust [+0x80]=1 -> startup reason NORMAL (uem-power-status-extra=2, bit 1
released at the RTC driver unmask). RTC alarm status bit 3 = level (frozen
RTC == alarm). Current inputs: pmm-image=pmm-aan.bin, cbus-input=0x24=1,
uem-power-status-extra=2. Lineage auth31 (from reset) / auth32 (resume r700).

auth32 ran 0.7e9 -> 4.0e9 with NO stop, no power-off, no RTC fault - but no
LCD output. KEY FINDING: on the authentic lineage Symbian never got past
kernel init: kernel memory at r1500/r2300/r3900 (and auth31 r2300) holds
only EKern/Supervisor/KernelBeep/TheRamDriveChunk names - no EFile/EStart.
The earlier "RTC fault" runs were kernel-side only too. At 3.9e9 the
system is idle (timer tick -> NOS periodic handler + ecust+0x15f0, ekeyb
polling). The stub lineage reached user side because its synthetic NOS
answered immediately. NEXT: find what the kernel boot (supervisor/init)
waits on before starting F32 - likely an ecust/Variant init step waiting
for the real NOS (interfaces #3/#6 registration done at 0x9d000 by NOS?
helper/nosdriver request completion?). Method: stack-scan saved thread
contexts in r3900 for blocked kernel calls; compare with stub-lineage
checkpoints that reached EStart.

## 2026-11-01 ~16:00 DECISION POINT: RTC alarm vs startup-reason ordering (update made with Claude)

Model state (boot_profile.cpp, all hypotheses): seeded PMM (aan), 0x24=1,
status bit 4 = power-key level released at the RTC driver's first bit-3
unmask (mask 0xfff7, ~727.4M), RTC alarm bit 3 fires ~8M cycles after that
unmask (no other alarm triggers; the 0x24-write trigger was removed).
Result auth30: boot ROM passes, ecust reason 9 (no power-off), but RTC:
fault at 2.311e9 again. Precise mechanism (pc-log, run boot-v15-irqen):
 - ecust "alarm object" [ecust+8] IS the RTC driver; its +0xc
   (0x5034e83c) returns driver state, and 0x50349840 reports state 1/2 as
   startup reason ALARM -> NOS powers off (auth22/auth28).
 - RTC driver state goes 9 -> 1 only in the alarm handler 0x5034e6a0, which
   runs synchronously at init (727.43M, reads status) or inside EKIF op1's
   0x5034e648 (751.5M); the driver's interrupt object (id 0x44, NOS
   dispatcher vtable 0x517110c4) is only enabled at 0x5034e384 inside op1
   (751.81M), so an alarm IRQ in between (taken 746.47M) is not dispatched.
 - op1 needs state 1 BEFORE its e648 to reach 2 -> so the alarm must be
   latched at init (727M) but ecust's reason query (729.45M) must not see
   state 1. Contradiction in our timing; on hardware the NOS reason query
   may precede the RTC driver init (ordering/timing difference).
 Options: (A) find what really orders reason-vs-RTC-init (NOS 0x514a65e0
 vs ecust RTC init) and whether timing/clock modelling flips it; (B) find
 whether a real power-key boot gets [0x4000101c]!=0 (ecust [+0x80] ->
 reason NORMAL regardless of alarm); (C) find what triggers RtcQueue::Add
 3/4/5 and whether it happens on a real cold boot.

## 2026-11-01 ~14:30 REMOVED three RAM patches; alarm countdown + power-key level (update made with Claude)

boot_profile.cpp contained three "RTC server state patch" hacks (from commit
2e577a3, the modem-integration commit): tick() rewrote RAM byte 0x404110
1->3 every cycle, the RAM read path ORed bit 1 into any read of offset
0x404110, and checkpoint load wrote 3 there. They aimed at the ecust flag
word but used the WRONG offset (the flag is VA 0x80404110 = SDRAM 0xfe0110),
so they never fixed the RTC fault and could corrupt whatever lives at SDRAM
0x404110. All removed (no firmware/RAM patching). Runs before this point
that relied on them are suspect (auth16/17/18-era). Model additions
(hypotheses): RTC alarm fires ~8M cycles after the driver first unmasks
status bit 3 (countdown in cbus_written_ key 0x137, tick()); UEM status bit
4 = live power-key level, reads set until the boot ROM writes mask 0x36
(key 0x235). Run boot-v15-auth26 (from reset, 2.6e9) tests the combination.

## 2026-11-01 ~13:30 Startup-reason chain; PMM seeding; cold-boot model (update made with Claude)

Findings since the ~11:00 entry (all static RE + pc-log/bus correlation):
 - NVD records 0xd40000-2 empty -> Nvd_lib returns the firmware's own ROM
   default (all zero). A used phone has them in PMM. NEW: option
   pmm-image=FILE serves a 64KB PMM sector image (input, not serialized;
   NOS-programmed halfwords still overlay). scratch/pmm/seed_pmm.py writes
   records in the NOS PMM format (sector F0F0/PMMCAT headers, 12-byte record
   headers, no checksum - decoded from format 0x514beb4c / scan 0x515c7a30);
   the NOS parses them (appends its own record after them). Ordering found
   by brute force: --values a,a,n (rec0=rec1=date, rec2=date+1 day) makes
   ecust RTC op1 reach state 2 (0x5034e830, observed). Also needed:
   cbus-input=0x24=1 (ecust RTC init 0x5034e0ec reads logical reg 4 = UEM
   0x24; nonzero = "RTC set", sets driver [+0x3c]).
 - A day-counter hack on config-7 reg 0x21 was WRONG (logical reg 1 = 0x21
   is polled to 0 at init) and is removed.
 - With the RTC fixed the NOS no longer faults but POWERS OFF (MTC_POWER_OFF
   0x514c214c(1) -> 0x514c10b4). Cause: ecust startup reason
   [ecustobj+0x14] (computed 0x503497dc/0x50349840): [+0x80] (copied from
   bootstrap flag [0x4000101c], cleared on cold boot) -> 0 NORMAL; else
   alarm object -> 1/2 ALARM; else UEM 0x35 bit 4 -> 4 CHARGING; else 9.
   uem-status35=16 (old guess) => CHARGING => no charger => power off.
   With uem-status35=0 and the alarm bit latched at power-on => ALARM wake =>
   power off again (auth22). Model now: alarm status bit NOT latched at
   power-on. Run boot-v15-auth23 (from reset, 2.4e9, seed aan, 0x24=1,
   status35=0) tests the honest cold power-key boot.
 - OPEN: a cold boot yields reason 9 (no path returns NORMAL unless
   [0x4000101c]!=0); verify what the NOS does with 9 (raw >6 -> MTC FAILED).

## 2026-11-01 ~11:00 RTC chain decoded; blocker is now empty NVD records (update made with Claude)

FPGA: CI 41289756644 FITS - 19,778/41,910 ALMs (47%), 186/553 RAM blocks,
full 16KB caches (zap_ram_lane8 per-lane M10K) and board in block RAM.

Boot (auth19 lineage, from reset with rtl/arm CPU; checkpoints roll-auth19-r*;
NOTE auth18 checkpoints are from an older CPU build and no longer restore):
 - ecust flag word ecustobj+0x90 (VA 0x80404110) is set ONCE by the NOS at
   ~751.8M via setStartupState 0x514a4a88(a,b): b!=0 -> 3, else a (=1). The
   caller EKIFTask_Activate (~0x5159ebec, Ekif.c) passes b=0 on the
   "EKIFTask_Activate: No midnight alarm" path, i.e. when ecust RTC op 1
   (0x516c77b4 -> ... -> ecust 0x5034e444) returns 0.
 - ecust RTC driver (object at 0x804056a4, state [+0xc]) register map, found
   with pc-log + bus correlation (run boot-v15-rtcmap): driver logical
   0x15/0x16 -> UEM 0x35 status / 0x36 mask (config 0xf); time read
   0x5034f374 = config-7 regs 0x31 sec(&0x3f), 0x32 min(&0x3f), 0x33
   hour(&0x1f), 0x21 day counter; alarm handler 0x5034e6c8 waits for UEM
   status bit 3 (RTC alarm).
 - MODELED (boot_profile.cpp, hypotheses, state kept in cbus_written_ keys
   0x124/0x135 so checkpoint layout is unchanged): status bit 3 latched from
   power-on until written to 0x35 (W1C), re-raised (+ICU source 1) when the
   alarm compare 0x24 is programmed and bit 3 unmasked; config-7 0x31-0x33
   read as a frozen RTC counter (writes like NOS init 0x32=0x20 don't alter
   it); day counter 0x21 reads 1. Result: the 727M handler now runs and sets
   driver state 1.
 - REMAINING BLOCKER: op 1 still yields state 9 because its request time
   (from NVD records 0xd40000/1/2 read by EKIF through Nvd_lib 0x5152ba5c) is
   all-zero = TTime(0) -> 0x5034e138 treats it as "no alarm". Our PMM is
   empty (ANOTHER_ID_PMM_EMPTY). NEXT: how NVD resolves records on an empty
   PMM / what a real first boot writes there (subagent RE in progress), then
   seed or model it and rerun from roll-auth19-r700 (changes act >=727M).
 - Tools: scratch/rtc-fault/armdis.py (ROM ARM), nosdis.py (NOS Thumb with
   literals). Resume runner now forwards extra options (pc-log=...).

## 2026-11-01 ~10:00 CORRECTION: RTC: fault NOT broken; root mechanism found (update made with Claude)

auth15 (device-ID fix) still faulted at 2.382e9 right after "RtcQueue::Add: 4";
auth16 only avoided it because the source-4 IRQ livelock slowed it beyond its
budget; auth17 faulted again (2.366e9). Mechanism (static disassembly, ROM VA
= SYM.ROM offset + 0x50000000): ecust RTC op 0x5034f6d0 checks bit 1 of the
ecust flag word (ecustobj+0x90, getter vtable+0x12c, test at 0x5034fbe0) and
otherwise calls the "RTC:" fault helper 0x5034fc00 with reason 6 (= 0x10006).
Flag value in roll-auth17-r2300 (SDRAM 0xfe0110) = 1: bit0 set, bit1 (RTC
ready) clear. The stub lineage had 3 only because scratch/nos-stub-blob/
nos_stub.S hardcoded setter(3) - the real NOS writes 1. NEXT: find the real
NOS setter call (pc-log 0x50349d8c, run boot-v15-auth18) and the condition
under which the NOS would set bit 1 (its RTC driver init), then model the
missing hardware. Tool: scratch/rtc-fault/armdis.py VA LEN [thumb].

## 2026-11-01 ~09:30 FPGA FIT ROOT CAUSES + ONE CANONICAL ZAP (update made with Claude)

Quartus "232144 combinational nodes, device has 83820" was NOT the ARM being
too big. Per-entity map reports (CI runs 41263284904 / 41271094458, copies in
scratch/quartus-fit/):
 - ngage_board: 191-195K ALUTs + 524,702 registers. Its 64KB GPIO latch array
   was read combinationally, so it became flip-flops plus a huge read mux.
   Fixed: the three latch arrays use rtl/ngage_bram_be.v (registered read,
   byte-lane M10K); the board gains a `ready` output (one wait state on
   RAM-backed reads), wired to wb_ack in rtl/ngage_mister.v and to the HDL
   sim harness (main.cpp board_wait). The GPIO claim now excludes the CBUS
   pair 0x0c150420/424 (stateful, C++-only; the 11-01 range widening had
   swallowed it).
 - ZAP 16KB caches: data RAM (256-bit, 32 byte enables) not inferred ->
   ~270K registers. Fixed by patch 0014 (per-byte-lane RAMs, proven
   equivalent). The cache/BTB shrink commits cd93a00/9d1e0aa are REVERTED:
   rtl/ngage_cpu.sv is back to 16KB/16KB, default BTB.
 - Expected after both fixes: well under the 41.9K ALMs; NOT yet confirmed by
   a Quartus run (next CI build is the check).
ZAP consolidation: Quartus compiled pristine third_party/zap (+compat) while
all simulations used the untracked scratch/boot-v15-quiet-zap (0001-0009 +
three unrecorded changes). Now rtl/arm = upstream + patches/zap 0001-0014
is the only copy (patches/zap/verify.sh downloads upstream to
scratch/zap-upstream and checks it); files.qip, sim/run.py and all scratch
build/run scripts compile rtl/arm; third_party/ and the scratch copies are gone. Details and
per-patch notes: docs/cpu-patches.md. A 150M from-reset authentic run was
cycle-identical old vs new CPU, but restoring OLD checkpoints into the new
binary may fail (Verilator layout) - expect to start from reset.
CAVEAT on auth17 (below/after auth16): it ran on the shrunken 1KB-cache CPU
(binary 05:47 after cd93a00), so its 2.366e9 shutdown park (same 0x1a /
0x200 / GPIO 4 signature as the RTC: fault) cannot be attributed to the UART
IRQ removal alone. Rerun with the restored CPU before drawing conclusions.

## 2026-11-01 ~05:30 *** RTC FAULT BROKEN — auth16 ran 3.3e9 cycles clean *** (update made with Claude)

boot-v15-auth16 (device ID fix + FBUS sync echo + UART RX IRQ source 4)
ran the full 3.3e9 budget with STATUS: TIMEOUT (no crash, no fault, no
unmapped access). The RTC: 0x10006 fault at 2.382e9 is GONE.
Three fixes combined:
 1. Factory device-ID table at PA 0x13a (non-blank → ANOTHER_ID_OK path
    → 0x514c6800(1) sets the ID-ready flag)
 2. FBUS sync echo (0x55 TX bytes echoed back to RX immediately)
 3. UART RX interrupt on ICU source 4 (the NOS FBUS driver is
    interrupt-driven; without it, echoed bytes sat unread)

HOWEVER: no LCD DMA transfers = no logo yet. The trace shows
ANOTHER_ID_OK → ANOTHER_ID_PMM_EMPTY but never reaches "NORMAL" or any
display activity. The UART RX interrupt is in a LIVELOCK (33% of all bus
traffic = ICU current reads): the ISR fires, checks status, doesn't find
valid RX data (our status bit 0 doesn't match what it expects), returns,
interrupt re-fires. This eats a third of the CPU and likely prevents the
MTC state machine from advancing.
NEXT: trace the FBUS UART ISR to find the correct RX-data-available
status bit, and make the interrupt clear when the ISR drains the data.
Then the NOS should advance through MTC:SU:NORMAL → server chain → logo.

Quartus build 4: reduced ZAP caches 16KB→1KB, BTB 512→64 (was 4x too
large for Cyclone V). Build in progress.

## 2026-11-01 ~03:30 RTC: fault is a startup TIMEOUT, not modem-dependent (update made with Claude)

auth14 (FBUS sync echo + modem integration) hit the same RTC: fault at
2,382,059,104 — zero Phonet frames exchanged, zero UART data register
(0x0c150500) accesses. The FBUS sync echo is correct but irrelevant:
the NOS never reaches the FBUS data-transfer phase within 23 modeled
seconds. The trace shows: MTC:SU:main() → ANOTHER_ID_DEF → RtcQueue
→ fault. "ANOTHER_ID_DEF" (string 0x516cf633) is a device-ID fallback
in the MTC startup — likely the ASIC ROM stub (PA 0x0c000000, returns
BX LR for every entry) returning 0 instead of a device identifier that
the startup task expects. The real ASIC ROM returns a product/hardware
ID that MTC:SU uses to select the device configuration; our BX-LR stub
makes it fall to ANOTHER_ID_DEF and the startup stalls.
NEXT: trace the MTC:SU:ANOTHER_ID_DEF path to find which ASIC ROM call
returns the device ID, and what value it should return for NEM-4.

Quartus build: passed elaboration (ZAP enum + SDRAM state + RAM init
all fixed); build 3 in fitting/timing. MiSTer core structure complete
(DDR3 flash + SDRAM phone RAM + descrambler + board + modem + PLL 104MHz).

## >>> HANDOFF / START HERE (2026-11-01, written with Claude) <<<

Read this block first; the dated entries below are the evidence log
(newest first). Three entries below were corrected in place: the
"power-on reason" theory is SUPERSEDED (wrong), the 1Hz RTC tick did NOT
fix the fault, and the old "bit 29" title was a misread (it is bit 25).

### Two boot lineages - know which one you are looking at

1. STUB lineage (older, 2026-10-30/31): plaintext NOS image + synthetic NOS
   entry stub + rewritten digest. Reached the NOKIA LOGO (~3.3e9, resume of
   roll-r3300, pixel-identical to the ngvm oracle) and the N-GAGE SPLASH
   (5.9e9-9e9), then the EtelServer/commsdb crash at 3.165e9 on some
   variants. Artifacts: build/sim/screens/milestone-nokia-logo/.
2. AUTHENTIC lineage (current, user's direction "no patches"): the ORIGINAL
   scrambled service ROM build/firmware/nem4-factory/core.bin (+
   extension.bin) with the solved inline descrambler (option
   descramble-window), stock MD5 2c09c86f passes natively, REAL NOS runs.
   No stub, no nos-image, no digest rewrite.
   LOGO STATUS: NOT YET on this lineage. It shows the early LCD clear
   (~114M); the logo point (~3.3e9 on the stub lineage) lies beyond the
   current blocker.

### Current frontier and blocker (authentic lineage)

Run boot-v15-auth7 (restore roll-auth7-r800, budget 3.3e9) halts
DETERMINISTICALLY at cycle 2,382,059,099: kernel park 0x50324294 after
K::Fault(category "RTC:" = ROM string 0x503503a8, reason 0x10006), path
kernel 0x50349da4 -> 0x5034fbf4 -> 0x50350380 -> 0x50350284 -> 0x50333e70
(found with the instruction-window trace boot-v15-shutdowntrace from
roll-auth7-r2300). The shutdown writes 0x1a to 0x0c00428e, 0x200 to clock
control, 4 to GPIO 0x0c150000, then parks. The NOS trace text up to it is
clean (no assert printed).
TRIED, NO EFFECT (same fault, +/-5 cycles):
 - power-on reason UEM reg 0x3f = 1 (option uem-power-status-extra=1);
 - 1Hz tick raising ICU source 1 every 104M cycles (tick() in
   boot_profile.cpp; ICU current 0x114 read source-1 = 2 5,118 times, so
   source-1 IRQs are taken). Both remain in the model as harmless
   environment hypotheses; revert the tick if it confuses later work.
NEXT HYPOTHESES (in order):
 a. UEM RTC TIME REGISTERS ARE FROZEN: cbus-input=0x20..0x34=0 primes the
    UEM RTC/alarm block to constant 0. A clock that never advances is the
    most likely way to trip an "RTC:" consistency check ~23 modeled
    seconds in. Model the UEM RTC seconds/minutes/hours registers as
    counting (cycles_/104e6) instead of constant inputs; find which regs
    the RTC driver reads (grep bus.tsv for CBUS commands 0x2x near
    RtcQueue activity).
 b. Find the faulting THREAD: walk back from 0x50349da4 in the
    shutdowntrace (re-create it: run-authentic-resume.py 2382059200
    shutdowntrace 2382040000:2382059200 0 roll-auth7-r2300) to the first
    user-side frame; grep euser/ekern for the "RTC:" category users.
 c. Timer unit 1: 0x0c120a24 (control) is read 51,180 times (always 1) and
    the counter 0x0c120a28 is NEVER read - the NOS may expect a different
    unit for its RTC base.

### How to run (authentic lineage)

- Build: python3 scratch/boot-v15-nosprobe/build.py  (NOT
  scratch/boot-v15-periodic/build.py - different obj dir). WARNING: it
  does NOT fail on a C++ compile error; if an option is reported "unknown
  board option", the binary is stale -> check
  build/sim/obj-boot-v15-nosprobe/Vngage_cpu_sim mtime vs the sources.
- Resume: python3 scratch/boot-v15-nosprobe/run-authentic-resume.py
  BUDGET NAME [LO:HI instruction window] 0 CHECKPOINT
  e.g. 3300000000 auth7 '' 0 roll-auth7-r2300. Rolling checkpoints every
  100M: build/sim/checkpoints/roll-auth7-r800 ... r2300 (+ idle-c730 just
  before the 730M delay calibration, roll-auth3-r700 base).
- Result: build/sim/runs/boot-v15-NAME/result.json - status, cycles,
  blocked_address/reason, and debug59_text = the NOS's OWN trace/assert
  text captured from its trace port 0x0def0000 (it prints file/line/
  expression of failed asserts - read it first).
- Wedge detection: one bus address >95% of a 50k-row bus.tsv tail = spin.
  bus.tsv compact trace does NOT log RAM writes; judge progress by cycle.
- Checkpoint signature covers ROM, profile and core options; add
  ENVIRONMENT inputs via the post-signature options uem-adc-extra= and
  uem-power-status-extra= so existing checkpoints stay loadable. New
  latch blocks share the serialized block14d_/keypad maps (caps 262144).
- When editing boot_profile.cpp with scripted replace, ASSERT the anchor
  exists (a silent no-op replace cost three runs tonight).

### What the model contains on the authentic path (all evidence-pinned)

Clock status bits 25+26; delay-calibration counter 0x0c150112/0x114
(fixed the USER-EXEC 3 div/0 panic at 730M); clock-unit lock 0x0c148000
bit0; DSP program upload RAMs 0x0c030000 (64KB) and 0x0c06ff00 (table at
VA 0x5140a000 = PA 0xa000, inside the scrambled window); PMM flash on CS0
top 64KB 0x7f0000 (Intel 0x40/SR/0x50/0x60 + AMD AA/55/A0, overlay in
block14d_, data cycles decoded BEFORE command values, lock reads 0x0001,
erased sector); FBUS TX status 0x0c150504 |= 0x1D0 and 0x0c150568 bits
1+2; MBUS strobe 0x0c15021c self-clears; GSM strap 0x0c150002 bit 0x40;
UEM ADC channels 0-13 = 512 + untracked conversions serve 512; UEM regs
0x3b-0x3e and 0x40-0x9f as zero inputs; ASIC mask-ROM page PA
0x0c000000 = BX LR stub (return provably discarded at 0x514befe8); latch
blocks 0x0c004000, 0x0c100000, 0x0c142000/14a/14b/14c, 0x0c150800,
0x0d000000-0x0dffffff (minus trace sinks). Details in the dated entries.

### Modem and HDL

- Modem: scratch/modem/ngage_modem.{c,h} + rtl/ngage_modem.v, byte-exact
  over 2022 cross-check vectors (scratch/modem/tb_modem.v, iverilog).
  Energy, phone-info IMEI, accessory (inferred), router errors, and the
  SIM server (fully reversed: docs/modem-model.md 3.4). NOT integrated:
  the ISI transport between the app side and the NOS servers is still
  unidentified.
- HDL board (rtl/ngage_board.v): device 1 LCD transport (validated),
  device 2 GPIO 0x0c150400-0x5ff, device 3 ideal-clock block (bits 25+26,
  lint-clean, not lockstep-validated). Everything added to the C++ model
  tonight is NOT yet in HDL - list in docs/hdl-migration.md.

### Repo state

All work committed and pushed to origin/master. Deliberately NOT
committed: .claude/ (local session tooling) and the modified
firmware/MCU/nos-iat-region-0x6e030.bin (firmware/ is git-ignored Nokia
material; the commit attempt was also refused by the session's
permission policy - owner's call).


## 2026-11-01 ~01:00 Shutdown = RTC: 0x10006 kernel fault (CONFIRMED); the 1Hz-tick fix FAILED - see HANDOFF above (update made with Claude)

The 2.382e9 "power-off" was neither power-reason nor timeout: instruction
trace from roll-auth7-r2300 shows K::Fault(category "RTC:" at ROM
0x503503a8, reason 0x10006) via kernel 0x50349da4 -> 0x5034fbf4 ->
0x50350380 -> 0x50350284. The RtcQueue (MTC trace "RtcQueue::Add") never
receives its 1Hz RTC tick: the NOS unmasks ONLY bit 4 in the UEM
interrupt mask (writes 0xffef to reg 0x36 at 729.45M) = the RTC second
interrupt, and our model never raised it. Fix: tick() raises ICU source 1
every 104M cycles (1Hz at 104MHz hypothesis); UEM status reg 0x35 already
returns 0x10 (bit 4). uem-power-status-extra=1 proved ineffectual for
this fault (identical shutdown cycle either way) but stays as plausible
environment. Run relaunched from roll-auth7-r800 (~40 min replay to the
old fault point). Checkpoint-loader note: entry caps raised to 262144
(the widened latch maps outgrew 4096 and r2300 restore failed with
'invalid checkpoint keypad entries' until raised).

## 2026-11-01 (post-midnight) [SUPERSEDED - WRONG DIAGNOSIS] power-on-reason theory; the real cause is the RTC: fault below/above (update made with Claude)

auth7's long cruise ended at 2.382e9 in the DELIBERATE shutdown path
(state 0x1a -> 0x0c00428e, clock 0x200, GPIO 0x150000=4, park; NO panic
dump, trace text clean): UEM reg 0x3f (power-on reason) = 0 means no
power key / charger / alarm, so the phone correctly turns itself off
after its startup window - real-phone behavior with nobody holding the
button. Fix: new post-signature option uem-power-status-extra=1 (power
key held, bit-0 hypothesis) in main.cpp + runner; reg 0x3f is read at
817-823M (after roll-auth7-r800), so the relaunch resumes from r800 with
the key held (replay to the old park point ~40 min). If the bit-0 guess
is wrong the shutdown recurs at ~2.38e9 - try other low bits of 0x3f.
A first relaunch failed with 'unknown board option' because main.cpp
didn't compile (out-of-scope lambda) and build.py does NOT fail the
pipeline on a verilator error - CHECK the binary mtime when an option
mysteriously 'does not exist'. Fixed with std::stoul; run relaunched.

## 2026-10-31 (midnight handoff) auth7 at 1.75e9 and cruising; how to continue (update made with Claude)

boot-v15-auth7 (authentic path, restore roll-auth7-r800, budget 3.3e9) is
at 1.75e9 cycles, clean since 822.8M. The run may outlive this session:
 - If it STOPPED: read build/sim/runs/boot-v15-auth7/result.json
   (blocked_address/reason + debug59_text carries the NOS's own assert
   text) and bus.tsv tail; fix the named device in
   scratch/boot-v15-nosprobe/boot_profile.cpp (patterns for every device
   family are in tonight's commits); rebuild with
   scratch/boot-v15-nosprobe/build.py (NOT boot-v15-periodic's); resume
   from the NEWEST build/sim/checkpoints/roll-auth7-rN with
   run-authentic-resume.py 3300000000 auth7 '' 0 roll-auth7-rN.
 - If it reached 3.3e9: raise the budget and resume from the last
   checkpoint; next milestone zone is the app-side telephony/EtelServer
   region (stub lineage hit the empty-commsdb crash at 3.165e9; on this
   authentic path the real NOS servers are up, so provisioning may now
   proceed - watch debug59_text).
 - Wedge detection: single bus address >95% of a 50k tail = spin; pin the
   poll mask via a win-trace run (see tonight's clockloop2/fbus2 recipes).
The target "frontier 1.2e9 by return" was met at ~23:10.

## 2026-10-31 (night 5) MILESTONE: authentic run crossed 1.2e9 cycles (update made with Claude)

boot-v15-auth7 passed 1.2 BILLION cycles with no stop since 822.8M - a
clean 370M+ stretch after the ADC-fallback fix. The NOS phone stack is up
(MTC startup traces clean, PMM records written and verified, FBUS/MBUS
initialized, periodic ticks + timer-unit polling pattern 0x0c120a24 at
~40% of bus traffic = settling toward idle/scheduler cadence). Rolling
checkpoints banked through roll-auth7-r1100; run budget 3.3e9 continues
toward the app-side boot (stub lineage previously reached EtelServer at
3.165e9). Watch item: if 0x0c120a24 polling share asymptotes to 100%, the
NOS idle path is waiting on a timer-unit-1 interrupt the model does not
raise - pin that bit next.

## 2026-10-31 (night 4) PMM write chain complete: program-data decode fix; frontier 821M+ (update made with Claude)

The PMM write failure ("PMM Write failed" + hw_reset_generate, NOS reset
park 0x514c11ae) had two model bugs, both pinned from the bus evidence:
 1. After a 0x60 lock-op the driver READS the sector lock status (one
    read, then 0xF0): reads in lock-op mode now return 0x0001=protected.
 2. CRITICAL ordering bug: program DATA halfwords can hold command-looking
    values - the driver programs 0x0060 at 0x7f003e; v1 decoded it as a
    lock-op command and the verify read mismatched. Data cycles
    (AMD unlock==6, Intel program-pending) now decode BEFORE any command
    value matching in flash_command.
Also: 0x0c100000 64KB block gated; latch family accepts byte lanes.
Frontier: past 821M and cruising; next rolling checkpoint r900.

## 2026-10-31 (night 3) FBUS/MBUS bring-up chain cleared via live NOS asserts; frontier 875M+ (update made with Claude)

The captured NOS trace port now pays off: instead of inferring stops, the
firmware PRINTS its own asserts and we fix exactly what it names.
 - FBUS (Fbus_drv.c:502 "fbus_reg_tmp & HW_FBUS_TX_BUFF_EMPTY"): TX status
   halfword is 0x0c150504; the gate needs (value & 0x1C0) == 0x1C0
   (0x515bb720) and the flag reader also reports 0x10. Modeled drained
   (|= 0x1D0 on read).
 - System type (Hw_mbus.c:742 "Illegal system type"): getter 0x514c1604
   reads GPIO strap halfword 0x0c150002 (bits 0x40/0x20/0x10/0x08 -> types
   1..4; 5/6 via comm-RAM state byte), else ROM header [0x176] bit15, else
   0 -> assert. NEM-4-straps-GSM hypothesis: reads of 0x0c150000 OR in bit
   22 (type 1). Note the OR-in must live on the latches_ read path.
 - MBUS command strobes 0x0c15021c (writers 0x515b9dxx strobe
   0x8000/0x1000/0x800/0x10/0x8; poll 0x515ba000 waits for self-clear):
   reads of the low halfword return 0; config half 0x21e stays a latch.
 - New blocks gated: 0x0c100000 64KB (scattered regs incl. 0x3e8/0x1f4),
   0x0d space minus trace sinks, 0x0c150800 FBUS/port block.
Frontier: past 875M before the MBUS-strobe fix restart; the mbus/fbus
drivers now initialize. PMM-based "Trace Activation Control Data not
found" fallback is benign (erased PMM).

## 2026-10-31 (night 2) PMM flash writes, UEM scan, 0x0d peripherals: frontier 816.6M (update made with Claude)

The NOS startup proceeded through its persistence + peripheral init:
 - PMM flash writes MODELED (both command styles in the Nokia flash HAL):
   Intel CUI (0x40 program -> status-register reads 0x80-ready, 0x50
   clear, 0x60/0xD0/0x01 lock ops) and AMD (AA/55 unlock decoding A10:0 -
   the NOS writes the 0xaaa/0x1554 long form - then 0xA0 program).
   Programmed halfwords live in the serialized block14d_ map as an
   overlay; array reads serve the overlay first so the driver's verify
   readback passes. Top 64KB of CS0 (0x7f0000+) = the PMM/security
   sector, absent from dump and bank table: factory-fresh erased (0xFF).
 - UEM register scan primed (0x40-0x9f zero cbus-inputs; config 0x01).
 - 0x0d space (0x0d000000-0x0dffffff) gated as zero-reset latches except
   the debug/trace sinks; observed windows 0x0d000000/0x0d010000/
   0x0d6d0000. NOS trace text continues to be captured (debug59_text).
Frontier: 816.6M and advancing. All fixes still replay from
roll-auth7-r800 in ~1 min; goal for tonight is 1.2e9+.

## 2026-10-31 (night) NOS startup running: live MTC traces captured; ASIC-ROM service wall stubbed (update made with Claude)

Authentic frontier at 800.76M and advancing. Since the clock-unit locks:
 - DSP program upload accepted (0x0c06ff00 254B + 0x0c030100 8KB+ more
   sections; table at VA 0x5140a000 = PA 0xa000 INSIDE the scrambled
   window, parsed through the solved cipher).
 - UEM ADC scan: channels 0-13 supplied at mid-scale 512 via new
   'uem-adc-extra' option (merged AFTER the checkpoint signature so adding
   environmental inputs never invalidates checkpoints; main.cpp).
 - NOS trace port found at 0x0def0000 (debug space): ASCII at any width.
   CAPTURED LIVE: "RtcQueue::Add: 2", "MTC:SU:main()" - the NOS startup
   task (MTC = mobile terminal controller) is running and tracing.
 - UEM regs 0x3b-0x3e primed as cbus-inputs (RTC/calibration reads).
 - HARD WALL HIT AND MODELED: the NOS calls into an ASIC-resident ROM at
   PA 0x0c000000 (entries 0x58000001+offset, table 0x516cd980+0xc; call
   site 0x514befd2 -> dispatcher 0x515305b8 BX R12) - no dump of this
   mask ROM exists in the project. Observed call passes comm-RAM buffers
   (in 0x0c004400 len 0x28 = 40 bytes of 0xFF blank personalization, out
   0x0c004428 len 0x20); wrapper discards the return value. STUB: the
   page reads as Thumb BX LR everywhere (assumed_asic_rom_stub). If later
   boot checks the 0x20-byte output, this hypothesis is the first suspect.

Also tonight: SIM server fully reversed by subagent (docs/modem-model.md
3.4 rewritten: Srvsim, status convention 01/24/FA/FB/FC at body[3],
IMSI EF form; 0x091D at 0x5153fad4 was a debug line number, not a key)
and folded into the C+HDL modem; cross-check 2022 vectors byte-exact.

## 2026-10-31 (later) NOS init frontier: 730M -> 800M+; clock-unit lock bits; sibling blocks (update made with Claude)

With the calibration fix the authentic run marched 730.1M -> 829M+. New
devices gated as hit:
 - 0x0c148000 clock unit: NOS writes config 0x2000 then 0x2490 via
   0x515b7e88 (validates targets {0x149000, 0x148000, 0x14a000}), then
   polls halfword bit 0 for LOCK (checker 0x515b7ef0 ldrh/ands#1); zero
   latch spun 99.9% of the bus from 760M. Model: reads return value|1
   (ideal lock, like the PLL 0x0c149000 |1).
 - Sibling unit blocks pre-gated as plain zero-reset latches after the
   0x0c142000 write at 800.0M: 0x142000/0x14a000/0x14b000/0x14c000 (+0x20
   each). Lock-bit reads only added where a poll is observed.
Iteration now restores roll-auth7-r800 (new rolling checkpoints resumed
once the run passed 800M); idle-c730 remains for the calibration window.

## 2026-10-31 Authentic path: NOS init marched to 730.1M; halt = USER-EXEC 3 panic (div/0 in delay calibration), counter modeled (update made with Claude)

After the bit-25 clock fix the NOS hardware-init burst ran 729.42M->730.12M:
GPIO pin-mux writes (new upper-halfword value 0x0200 on 0x0c150206 gated),
timer unit 5 (0x0c120aa4 +0x04=1), UEM over app CBUS (reg 0x36 mask writes
0xffef/0xffff, reg 0x35 status read -> 0x0010), and a new block 0x0c004xxx -
dozens of registers used by UEM/energy code 0x515c1xxx and startup manager
0x51506xxx; 0x428c holds a 0..6 state machine driving GPIO 0x0c150002 bits
(RF/power state). It is likely a small shared RAM; modeled as explicit
zero-reset RW latches (nos-periph-4000, stored in block14d_ map so the
savestate layout is unchanged).

The run then parked at kernel 0x50324294 (self-branch, IRQ+FIQ masked).
Instruction-window trace (boot-v15-poweroff) decoded it: NOT a power-off
decision - the kernel halt fn 0x50324240 dumps panic category "USER-EXE"
(USER-EXEC truncated to 8) + reason 3 into comm RAM 0x0c0047f0/f4/f8, sets
state 0x1a at 0x0c00428e, clock control 0x200, GPIO 0x150000=4, then parks.
Root cause chain: NOS delay-loop calibration 0x514c19fc (Thumb) reads
halfword [0x0c150114] as a tick window and free-running counter
[0x0c150112], busy-counts iterations until the counter advances window/2
ticks, then computes iterations*64 / elapsed via division thunk 0x516c7594
(-> euser 0x503a2fdc). Our model returned ZERO for both -> 0/0 -> euser
raises exec 47 K::Fault("USER-EXEC",3) -> system halt. Setup fn 0x514adce4
(writes 0x9f to 0x114, reads 0x116, writes 0x80 to 0x0c150012) had not run
yet, so the real chip must expose a nonzero reset window there.

Model fix: 0x0c150112 counts one tick per 3174 CPU cycles (32.768 kHz at
104 MHz - hypothesis); 0x0c150114 reads 0x0080 until written. The computed
calibration factor is a rate RATIO (independent of window size), so the
window choice only affects boot time. Board clock cycles_ is deliberately
NOT serialized (deltas only) to keep old checkpoints loadable.

Iteration logistics: all fixes land in 729.4-730.1M, reached by replaying
roll-auth3-r700 (+30M cycles, 1-2 min). This run also pins checkpoint
idle-c730 at 730.1M just before the calibration for seconds-fast iteration;
rolling roll-auth7-r800+ resume once the run passes 800M.

## 2026-10-31 Clock bring-up poll pinned: NOS waits for STATUS BIT 25 (title once said 29 - wrong; body is correct) (update made with Claude)

boot-v15-auth6 spun 729.4M->2.3e9 cycles polling 0x0c120020 while the model
answered 0x08000000 (bit 27). Instruction-window trace from roll-auth6-r800
(boot-v15-clockloop, win-trace) pinned the wait loop 0x514a5b80..8c; raw
word e3100402 = TST R0,#0x02000000 - the loop waits for BIT 25. (First
read of the sim trace's "2 ROR 4" as bit 29 was WRONG - that prints the
rotate FIELD, the rotation is 2*4=8; capstone + hand decode agree: bit 25.)
During the spin only the periodic tick ran (all other threads blocked), so
the wedge was deterministic. NOS bring-up sequence (nos-image.bin @VA
0x5149D280, fn 0x514a5b60): write control 0x40 then 0x20 (no poll between),
poll status for bit 25, then write control 0x10 and command 0x8000 - and
this is the ONLY 0x00120020 literal user in the NOS, no further status
reads. Model fixed: control 0x20/0x40 -> status 0x02000000. auth6 stopped
(provably stuck); boot-v15-auth7 relaunched from roll-auth3-r700 with the
fix. Also fixed: the nosprobe binary must be rebuilt with
scratch/boot-v15-nosprobe/build.py (NOT boot-v15-periodic/build.py, which
builds a different obj dir - the first auth7 ran stale and re-spun).
LESSON: a single-address bus tail (>95% one register) is the wedge
signature; check it before assuming progress on long runs.

## 2026-10-31 MODEM BUILT in C + HDL, byte-exact cross-check PASSES (update made with Claude)

The ISI/Phonet modem responder now exists in both forms, transport-agnostic
(frame in -> frame out), with every reply byte sourced from the real NOS
disassembly (docs/modem-model.md):
 - C: scratch/modem/ngage_modem.{c,h} + unit tests test_modem.c (12 directed
   tests, all pass). Handles energy 0x17 (charger 0x08->0x09, battery
   0x0A->0x0B with all 5 subblocks, empty-OK for the other table ids,
   per-server 0xF0 0x01), phone-info 0x1B (IMEI sb {0x41,20,0,16,16ch},
   status 0=OK), accessory 0x1C (inferred), SIM 0x09 (unregistered ->
   router 0xF0 0x14; registered 0x1D -> 0x1E status-fail until the real
   body is extracted), router error 0xF0 0x14 16-byte frame, LE length.
 - HDL: rtl/ngage_modem.v (Verilog-2001, byte-stream rx/tx with handshake,
   same dispatch; config ports for charger/battery/IMEI/sim_reg state).
 - Cross-check: scratch/modem/gen_vectors.c runs 2014 directed+random
   frames through the C model; scratch/modem/tb_modem.v (iverilog) drives
   the RTL with random rx gaps + tx backpressure: ALL VECTORS BYTE-EXACT.
   The fuzz caught a real C bug (read of absent flags byte req[10] in
   10-byte frames) - fixed: absent body[2] models as 0.
 - NOT yet integrated: the integration point (how the real NOS exchanges
   ISI frames with the app side - mailbox/queue addresses) must come from
   the authentic run (auth6) evidence; do not guess registers.
 - Rebuild/run: cc -o test_modem ngage_modem.c test_modem.c && ./test_modem;
   cc -o gen_vectors ngage_modem.c gen_vectors.c && ./gen_vectors >
   vectors.hex && iverilog -g2001 -o tb tb_modem.v ../../rtl/ngage_modem.v
   && vvp tb   (in scratch/modem/).

Meanwhile boot-v15-auth6 (authentic path, resumed from roll-auth3-r700 with
the clock-ready model 0x20/0x40 -> 0x08000000) is clean at 2.27e9 of 3.3e9,
rolling checkpoints roll-auth6-r* every 100M (keep 30).

## 2026-10-31 AUTHENTIC PATH validated through early boot: original ROM + inline descrambler, NO stub/rewrite (update made with Claude)

User's architecture (no patches; original scrambled service files as ROM +
inline read-side descrambler; real NOS; build the modem/NOS responder in C
then HDL) is now implemented and VALIDATED through early boot (boot-v15-auth2):
 - ROM = build/firmware/nem4-factory/core.bin, the ORIGINAL scrambled service
   assembly with the STOCK digest 2c09c86f (no rewrite).
 - main.cpp applies the 16 solved descramble formulas (descramble_model.h) to
   the window [0xa000,0x2b3000) before the board serves it (option
   'descramble-window'); equivalent to an inline read-path descrambler - the
   HDL core does it per-read. Disk ROM stays the original file.
 - Stub layers DROPPED: no nos-entry-stub, no nos-image, no nos-iat-region.
 - Result at 113.8M cycles: 0 unmapped/unmodeled, 0 synthetic_nos reads, LCD
   clear rendered (36768 rows) => the firmware's OWN MD5 self-check PASSED
   NATIVELY on the descrambled window (the LCD clear is after the digest). The
   real descrambled NOS is what's served. Authentic verification, live.
 - Runner: scratch/boot-v15-nosprobe/run-authentic.py (from reset, rolling
   checkpoints roll-authN-r*). This change is early-boot, so it needs its own
   from-reset lineage (a stub-lineage restore would be inconsistent).
 - NEXT: boot-v15-auth2 to 1.5e9 tests the REAL NOS execution (~729M); then
   build the C modem/NOS ISI responder from docs/modem-model.md (real handler
   bytes: energy 0x17, SIM 0x09, phone-info 0x1B; with the ngvm corrections
   - LE length field, battery subblock {0x16,4,7,bars}, router 0xF0 0x14).


## 2026-10-31 EtelServer crash: C:-image byte-patch is INEFFECTIVE; fault pinned; fix is the modem not C: (update made with Claude)

Tested factory ROM + C: image with Cdbv2.dat renamed (cdrive-nocdbv2.img,
boot-v15-nocdbv2): the data abort recurs at the EXACT same cycle 3,165,666,171,
bit-for-bit - the C: byte-edit had ZERO behavioral effect. LESSON: naive
byte-patching of the LFFS image does NOT surface to the mounted filesystem
(LFFS reconstructs names/structure from log records); C: changes need real
LFFS tooling, not image edits. Fault pinned: edbms (DBMS server) ldr r4,[r0]
at 0x5045094a with a bad r0 = query into an empty-SCHEMA comms DB (no tables ->
null row deref). So a renamed/empty DB can't fix it; it needs a properly
populated Cdbv2.dat (modem/IAP/WAP tables). On real hardware those tables are
provisioned as telephony comes up (needs the modem). CONCLUSION: the stable-UI
fix is the MODEM (ISI provisioning), reversed in docs/modem-model.md, OR a
valid populated Cdbv2.dat built with real LFFS tooling - NOT C: image
byte-patching. Resume base roll-nocdbv2-r3100 (fault at 3.1656e9).


## 2026-10-31 *** FLASH SCRAMBLER SOLVED - STOCK DIGEST 2c09c86f REPRODUCED (authenticity closed) *** see docs/firmware-integrity.md top. 16 GF(2) descramble formulas (build/firmware/thc/scrambler-model.json), each exact on 1.09M pairs; MD5 of the descrambled digest window == stock expected (independently verified). Authentic ROM now passes the native self-check without digest replacement; the 21%% gaps are decrypted. NEXT: assemble the fully-authentic descrambled ROM (the standard user-buildable boot ROM) and drop the NOS stub.

## 2026-10-31 CORRECTION + true root cause: the comms DB IS in ROM; an empty C: file shadows it (update made with Claude)

CORRECTION to the two entries below (the "reconstruction dropped the comms
DB" / "adopt THC verbatim" thread): I had searched only the CORE SYM.ROM.
The populated comms database IS present in our ROM - in extension.bin at
0x1876d0 (= PPM flash bank, physical ~0x743c40; VA 0x50243c40 via the +0x500000
remap), and in every real nem440.3xx PPM record. So the reconstruction did
NOT drop it. The THC-dump-verbatim swap also cannot work: the dump is the
CPU's post-remap VA SNAPSHOT, not a physical flash image, so the board's
physical-bank reads (PPM 0x700000+) have no source and it stops at PA
0x77001c (boot-v15-thcv2, cycle 113.8M). Keep the factory core+extension ROM.

TRUE ROOT CAUSE of the empty comms DB: our C: image (cdrive-stamped-4mib.img)
carries an empty 32-byte C:\System\Data\Cdbv2.dat (LFFS entry file offset
115464, size field 0x20) that SHADOWS the populated z:\System\Data\cdbv2.dat
in ROM. Symbian DBMS opens the C: copy if present, so phonetsy reads the
empty database -> null row deref -> the 3.17e9 data abort. The empty C: file
was created during the sim boot that we harvested the stamped image from
(first-boot provisioning created it empty - why it didn't populate from the
ROM default is the open "format/init" question: likely the CommsDat default-
copy needs state the dead modem would provide, or ran before the ROM default
was readable).

SURGICAL FIX (no THC dump, no cipher): make DBMS use the ROM's populated
default - either (a) remove/invalidate the empty C: Cdbv2.dat LFFS entry so
DBMS falls back to z:\...\cdbv2.dat, or (b) write the populated DB into the
C: entry. Both are LFFS edits on cdrive-stamped-4mib.img (log block +
LFFS_MAGIC 0x503B3B60 checksums); then from-reset. This is the likely
stable-UI unlock and needs no scrambler/modem work.


## 2026-10-31 THE COMMS-DB FIX INGREDIENT FOUND: populated cdbv2.dat exists in the firmware dumps (update made with Claude)

The EtelServer data-abort (phonetsy->commdb->edbms, root-caused above) needs
a POPULATED comms database. It exists - NOT in the ROM CPU-view dump (that
only has the path string z:\System\Data\DefaultCdbv2.dat and the copier
code; the actual file is absent, as ngvm also found), but in the firmware
Z:/disk dumps:
  - firmware/Nokia N-Gage/Data/drives/z/NEM-4/System/Data/cdbv2.dat  (7,925 B, NEM-4 - USE THIS)
  - firmware/Nokia N-Gage/Data/drives/z/RH-29/System/Data/cdbv2.dat  (7,925 B)
  - firmware/disk_dump/Z/System/Data/cdbv2.dat                        (9,066 B)
Our C: image (cdrive-stamped-4mib.img) has only an EMPTY 32-byte Cdbv2.dat
(LFFS entry at file offset 115464; size field 0x20) that our own first boot
created because the copier found no DefaultCdbv2.dat source.

THE FIX (authentic, matches how a real phone provisions it): get the
populated cdbv2.dat onto C: before phonetsy reads it (~3.17e9). Two blockers
to clear together: (1) no DefaultCdbv2.dat in ROM to copy from; (2) an empty
Cdbv2.dat already on C: makes the copier SKIP. So either:
  A. Inject the NEM-4 cdbv2.dat directly as C:\System\Data\Cdbv2.dat in the
     LFFS image (grow the 32-byte entry to 7,925 B - needs an LFFS writer:
     log block + per-block LFFS_MAGIC 0x503B3B60 checksums, see
     scratch/tools/extract_cdrive.py for the format), then from-reset; OR
  B. Add it to the ROMFS as z:\System\Data\DefaultCdbv2.dat AND start from
     a C: WITHOUT Cdbv2.dat so the firmware's own copier populates it
     authentically (ROMFS insertion + removing the empty C: file + new digest
     + from-reset).
Path A is fewer moving parts. Either invalidates checkpoints (from-reset).
This is the concrete next step to the stable main screen.


## 2026-10-31 ROOT CAUSE of the EtelServer crash: empty comms database (phonetsy->commdb->edbms data abort) (update made with Claude)

The "App. closed: EtelServer / System error" loop traced to its exact origin
(boot-v15-deathrun, full instruments from reset): a DATA ABORT at cycle
3,165,666,171 (3.17e9 - BILLIONS of cycles before the dialog; the UI draws
the note only once it can). Chain, romsyms-named: phonetsy!ord1+0x1d708 ->
commdb!ord52 -> edbms!ord179 (DBMS server) -> load abort. ETel's PhoneTSY
plugin queries the comms database for a modem/connection record. EXACTLY
ngvm's launch.c note: Cdbv2.dat (C:\System\Data) is EMPTY because the modem
never populates it -> deref of a row that does not exist -> fault. ngvm adds
one modem (the phone's data port) to the empty table as the fix. NEXT, the
real stable-UI gate: a populated Cdbv2.dat (>=1 modem record) on C:, or the
modem path that fills it - C:-content/modem work, not a hardware register.
Resume base roll-deathrun-r3100 (checkpoint retention now 30). Instruments
that found it (KEEP): always-on exception-vector retirement logging,
watch-word=, pc-log=.


## 2026-10-31 RETRACTION + vector logging (update made with Claude)

The "status pane breakthrough" below-mentioned handshake mirror at
0x0c150208 changed NOTHING: screen-update timelines of boot-v15-cts2 and
the baseline are cycle-identical; the mirror was removed. The status pane
render is real firmware output but exists in BOTH lineages (it was simply
never rendered standalone before). EtelServer death remains the frontier:
it executes zero instructions and leaves no bus-visible fault, so it dies
on an MMU translation fault at creation. main.cpp now ALWAYS logs
retirements at exception vectors 0x4/0xc/0x10 even in compact traces -
rerun any window and the abort cycle appears directly; from the abort the
faulting VA and the loader state are one short trace away.

## 2026-10-31 CONTINUATION GUIDE (final AI session; written with Claude)

State: both boot logos render (pixel-matched to ngvm); boot reaches real UI
and loops on EtelServer KERN-EXEC panics (~every 3.8e9 cycles: splash ->
"App. closed: EtelServer" -> System error -> re-splash). HDL migration live
with 2 devices lockstep-validated.

THE WORKFLOW (all commands from repo root; sims in jotego/simulator:arm64):
 - C++ fast lineage: python3 scratch/boot-v15-nosprobe/build.py (rebuild);
   run-roll.py BUDGET NAME RESTORE (resume w/ rolling checkpoints roll-NAME-r*,
   keep 10); run-fresh.py BUDGET NAME '' 0 (from reset). Board unit tests:
   cd scratch/boot-v15-nosprobe && c++ -std=c++17 -O1 -o /tmp/t \
   test_boot_profile.cpp boot_profile.cpp && /tmp/t   (28 PASS expected).
 - HDL lineage: python3 scratch/hdl-board/build-hdl.py; run-hdl-fresh.py.
   Any read divergence or ownership mismatch vs the C++ oracle stops the
   run with status hdl_divergence and the exact access in bus.tsv.
 - Autopsy toolkit (minutes each): resume near the point with win-trace
   (run-resume-from.py BUDGET NAME LO:HI 0 CHECKPOINT), symbolize with
   scratch/tools/symtrace.py --mods; kernel-heap UTF-16 name diff across
   roll checkpoints finds where progress stops; stack-scan clusters +
   romsyms name blocked calls; scratch/tools/inspect_checkpoint.py for
   thread objects; render frames with scratch/tools/render_lcd_frame.py
   (NOTE: skips updates < 9152 words; composite script pattern in
   build/sim/screens/boot-v15-modem2-composite + the git log).

NEXT BOOT TASK (in flight at session end): EtelServer KERN-EXEC autopsy.
roll-crashhunt-r* checkpoints approach the next death (~10.6e9 in the
modem2 lineage). Procedure: resume the nearest checkpoint with a narrow
win-trace just before the death, find the faulting PC/access in the tail
of instructions.tsv, then fix the root (likely a modem-dependent value:
phonetsy/NOS). After EtelServer survives, expect the energy-management ISI
need (SysAp charger/battery): the authoritative spec for every ISI answer
is ~/develop/n-gage/sw/kernel/chan.c (NOSDRIVER + energy + IMEI/IMSI + DSP).

MODEM (user mandate: software modem now, HDL modem later): euart1 is the
NOS-to-baseband UART. Known: status 0x0c150514 bit2=TX idle (board serves
it set); register tokens listed via the euart1 literal pool (see git log
8be6055 analysis); RX machinery = interrupt object via ekern ord30 bind /
ord112 enable (source number not yet identified). TX bytes do NOT stream
through the GPIO latch window - the send path was not observed writing a
data FIFO; find it before building RX (suspect another DMA channel or the
0x0c14f008 block).

HDL NEXT: device 3 = timers/ICU banks (interrupt heartbeat; ngage_board
grows irq/fiq outputs that main.cpp ORs into i_irq/i_fiq). Then CBUS/UEM.
Then flash. SDRAM+LCD-DMA last, then the MiSTer top (Template.sv + sys/).

STANDARD ROM: firmware/MCU/extracted/products/NEM-4/nem440.3c1 (KEEP
AS-IS) + the DCT4 de-framing (10-byte headers, stride 0x200a, 0x2000
data/record; builder evidence in git log 9479b59) is the path to a
user-buildable boot ROM; the IAT plaintext already ships as
build/firmware/thc/nos-iat-region-0x6e030.bin.

## 2026-10-31 ~08:30 HDL MIGRATION STARTED (user direction): rtl/ngage_board.v device 1 validated in lockstep; boot frontier = SysAp crash loop (update made with Claude)

HDL (docs/hdl-migration.md is the plan): rtl/ngage_board.v on ZAP's
wishbone claims migrated devices; unclaimed falls to the C++ model, which
also shadows claimed accesses (divergence stops the run). Two binaries:
build.py (C++-only, fast iteration, checkpoints untouched) and
scratch/hdl-board/build-hdl.py (obj-boot-v15-hdl, hdl-* checkpoints;
runner scratch/hdl-board/run-hdl-fresh.py). Savestates free via --savable.
Device 1 = LCD transport + device 2 = GPIO banks: boot-v15-hdlfull ran
from reset to 6.2e9 (both logos, dialogs, euart1 era) with 184297 HDL
claims and ZERO divergences against the C++ oracle. The HDL board is
validated on the entire visual boot.

BOOT FRONTIER (boot-v15-boot1, 9e9-12e9): the system is in an APP-CRASH
LOOP - composite final screen (build/sim/screens/boot-v15-boot1-composite/)
shows the N-GAGE splash + "App. closed" + "System error" dialogs with OK.
SysAp dies repeatedly, almost certainly missing the System Agent charger/
battery states that Nokia.dsy derives from NOS energy-management ISI
answers (resource 0x17: 0x08->0x09 subblock 0x13 charger, 0x0A->0x0B
subblock 0x16 battery bars; exact byte layouts in ngvm sw/kernel/chan.c).
NEXT: the modem RX side - euart1 receive path (RX FIFO + RX interrupt in
the board/stub) answering energy-management queries, then SysAp should
survive and the boot proceed toward Startup/idle UI.

## 2026-10-31 ~06:30 *** MILESTONE 2: THE N-GAGE SPLASH RENDERS *** (update made with Claude)

boot-v15-modem2 frame05 (archived in build/sim/screens/milestone-nokia-logo/):
the N-GAGE wordmark, matching the ngvm target, in wserv's partial-frame DMA
updates. The post-Nokia stall was euart1's baseband-UART send loop polling
TX-idle (0x0c150514 bit 2) against a zero latch — the first piece of the
software modem (TX always drains) unblocked 57 screen updates in 5.9e9-9e9
and the boot continues past both logos. Diagnosis pattern that found it in
minutes: traced resume at the stall + symtrace module histogram (euart1
+0x630/+0x640 hot loop) + the register token literal pool.
NEXT: sustained boot toward Startup/SysAp UI (boot-v15-boot1, 12e9); the
modem RX side (ISI answers per ngvm chan.c) when something waits on a reply.
NOTE render_lcd_frame.py skips partial updates < 9152 words (min-size
filter): lower it or composite updates to see small dirty regions.

## 2026-10-31 ~04:40 *** MILESTONE: NOKIA LOGO ON SCREEN — PIXEL-IDENTICAL TO THE NGVM ORACLE *** (update made with Claude)

Commit 51f5499; artifacts build/sim/screens/milestone-nokia-logo/ and
screen.png; captured from boot-v15-dma2 (resume of roll-r3300 with the LCD
DMA engine modeled). The firmware had composed the splash in SDRAM at
0x0a000020 on its own — real NEM-4 4.03 Symbian code on the ZAP ARM920T
RTL end to end; the single missing piece was the DMA transfer to the panel.
Validation from-reset with the complete fix set: boot-v15-logo9 (running at
session close). NEXT TARGET: the N-Gage logo (ngvm shows it ~11 phone-
seconds, i.e. past ~5e9 of our cycles), then sustained boot toward the UI.

## 2026-10-31 (overnight autonomous session) VALUE-3 LINEAGE: four fixes deep, LCD DMA engine modeled, authentic NOS IAT recovered from the user's Nokia data package (update made with Claude)

LINEAGE: from reset with ecust+0x90=3 (stub sets it at 729M). This is the
authentic path and it boots DIFFERENTLY from the patched-checkpoint lineage:
NOS dispatch and euart1 run, display driver uses DMA, SplashScreen loads.

Fix chain this session (each found by rolling-checkpoint autopsy in minutes):
 1. helper request 1 completed by pread2 (chan,1,100) - splash gate.
 2. ZAP mode16 decoder: wrong-path literal-pool fetch no longer $fatal
    (decodes to UND; apmime 0x47ec literal). RTL change.
 3. NOS IAT slot 0x71214 broken (scrambled flash) -> crash at 2.9559e9;
    AUTHENTIC value 0x503a26f4 (euser!ord855) recovered from firmware/MCU.
 4. euart1 pin-mux 0x0c15056a -> GPIO bank probe window grown to 0x600.
 5. LCD DMA ENGINE (the display frontier): driver arms 0x0c120340 block
    (src 0x354=SDRAM frame, dst 0x360=0x10121208 = LCD data port via DMA
    window 0x10000000+(PA-0x0c000000), count 0x36c=words-1, start 0x348=2,
    done IRQ source 7, enable bank-0 bit7 via 0x108, current 0x114 reads 8,
    ack bank-0 +0x0c bit7, pending +0x10 reads 0x80). Without it the white
    clear stalled forever after its header (2.3002e9). Board checkpoint v6;
    pre-v6 resumes with an armed transfer serve it at load. Frames are
    captured to lcd-dma.tsv (bus.tsv format) and rendered by the runners.

AUTHENTIC IAT (ends the per-slot RE loop): firmware/MCU is Nokia's NEM-4
4.03 flashing data package; nem440.3c1 (DCT4 file: 10-byte record headers,
stride 0x200a, 0x2000 data/record) holds the THC-scrambled IAT region in
plaintext. De-framed copy: firmware/MCU/nos-iat-region-0x6e030.bin (+ copy in
build/firmware/thc/). Anchor proof: slot 0x71c38 reads exactly the
independently-RE'd 0x503a2f64. Every future broken NOS import: read the
value from this file, add nos-iat=0xPA=0xVAL. NOTE: .3c1's NOS BODY at
0x9d288 DIFFERS from the THC dump (unresolved; THC body is what boots).
firmware/MCU/extracted/products/NEM-4/ nem440.* are KEEP-AS-IS (user).

INFRA: rolling checkpoints now use PER-RUN stems (roll-<name>-r<M>) after
logo7/logo8 deleted logo6's saves (keep-10 crossed runs). Sim logs keep
head+tail (fatal lines survive warning floods).

## 2026-10-31 DEEPEST BOOT YET: Starter/wserv/fbserv/ewsrv up, LCD driver init at 4.02e9; blocker = helper request 1 never COMPLETED; fix = pread(id 12) calls the kernel completion itself (update made with Claude)

Status of the gate chain after the value-3 + pread-100 run (boot-v15-logo3r,
resume of fresh-c2600-v3 = fresh-c2600 with ecust+0x90 patched 0->3):

  WORKED: ecust spin passes, helper loads, DosServer + SharedDataServer +
  Starter.exe + Windowserver + FbServ + EwSrv + Lcd.LDD + NOSDRIVER.LDD all
  born by 4.3e9 (kernel-heap name diff r4000->r4300). Lcd.LDD pushes real
  LCD command traffic at 4.02e9. Deepest LLE boot so far.

  STALLED at 4.3e9 (r4300==r4600==r4900 heap, only idle/tick/ekeyb runs in a
  6M traced window): NO SplashScreen, no frame.

  AUTOPSY (roll-r4900 stack walks, romsyms-symbolized):
   - Starter blocked: sysutil!ord4 -> dsclient!ord20 (DosServer client
     SendReceive) -> User::WaitForRequest. Waiting on DosServer's answer.
   - DosServer/Nokia.dsy blocked: nokia+0x1842 builds TVersion(1,0,1), opens
     "HelperDrv" (TLitC at 0x50fcb078), fires ASYNC request 1 with
     TRequestStatus=KRequestPending on its stack, then User::WaitForRequest
     forever. So returning 100 from pread does NOT complete the client's
     request - the LDD framework ignores helper's Request() return value.
   - helper.ldd async path disasm (0x50384240-70): pread(iface, 12,
     chan+0x44, chan+0x54), then plain return; the SYNC path completes via
     0x50384828(chan, 1, 100) -> ekern 0x50334fcc (thread=[chan+0x14],
     status slot = chan + 4*reqno + 0x18). The NOS must do the same.

  FIX (committed): stub pread id 12 now calls 0x50384828(r2-0x44, 1, 100)
  itself (guard: only when r3==r2+0x10, helper's exact register shape, so
  ecust's own pread users stay on the zero-fill path), returns KErrNone.
  Run boot-v15-logo4 (resume roll-r4000 -> 5.2e9) is validating.

  ALSO RULED OUT this session: nosdriver.ldd never calls its two NOS imports
  (0x514a0a50/0x514a13cc, PA 0xa0a50/0xa13cc in the THC nos-image window) -
  zero accesses in the whole run, so no ISI traffic is pending at this stage.
  ngvm's chan.c NOSDRIVER model (ISI COMMON_MESSAGE 0xF0 / NOT_IDENTIFIED
  0x01 default reply, energy 0x17 -> SysAgent charger/battery) is the spec
  for the NEXT stage, after the splash.

INFRA (new, keep using):
 - ROLLING CHECKPOINTS: sim option checkpoint-every=N (+checkpoint=stem)
   writes stem-r<Mcycle> every N cycles, keeps the last 10 (main.cpp).
   run-roll.py [budget] [name] [restore] resumes WITH rolling checkpoints to
   build/sim/checkpoints/roll-r*; it also renders any drawn frame via
   scratch/tools/render_lcd_frame.py. Iterations are minutes, not 80-minute
   from-resets: resume the newest roll-r* before the point of interest.
 - CHECKPOINT PATCHING: use inspect_checkpoint.py's va_off (MMU page walk)
   NOT the identity VA-0x80000000 guess (ecust+0x90 is SDRAM off 0xfe0110,
   file off = sdram_start + va_off). fresh-c2600-v3 = patched valid state 3.
 - CACHE GOTCHAS for blob changes on resume: new stub CODE only takes
   effect on an I-cache refill. The idle hook polls pread(iface13, id 13)
   keeping its lines hot, but EKA1 address-space switches flush the ARM920T
   VIVT caches, so first-time callers (Nokia.dsy) DO fetch fresh code
   (observed: single refill at 4.0557e9). Stub WRITES to the 0x9e000 board
   window go through the D-cache and may never reach the board - do not use
   board-window writes from stub code as a live log.
   HARD RULE (boot-v15-logo4 crashed at 4.03e9 proving it): NEVER change
   blob bytes at addresses the checkpoint already executed - partial line
   eviction mixes blob generations inside one function (old first line fell
   into the relocated completion code with garbage registers -> STM-R15
   crash flood, exit 1, no result.json). Put new behavior at virgin
   addresses and reach it by flipping a DATA word (vtable slot), keeping
   every previously-executed byte identical (verify with a byte-diff against
   the blob the checkpoint was built with - git show <commit>:...bin).
 - Verifying in-flight runs: kernel-heap UTF-16 name scan + diff across
   roll-r* checkpoints shows exactly when boot progress stops; stack-scan
   for ROM return addrs per 2KB cluster + romsyms names the blocked calls.

## 2026-10-30 THE EXACT LOGO GATE: one flag (ecust+0x90) drives helper.ldd's startup-reason request into a dead NOS path (update made with Claude)

Traced the complete chain to a SINGLE decision point (all from the
starterwin trace + idle-c4400 forensics + disassembly):

  logo <- SplashScreen <- Starter <- DosServer <- Nokia.dsy (System Agent)
       <- Nokia.dsy opens "HelperDrv" (helper.ldd) and sends REQUEST 1
          ("the software startup reason, returned as the completion code")
       <- helper.ldd request-1 handler (ROM 0x503841f8):
            r0 = ecust.vtable+0x12c()  = *(ecustobj+0x90)   [getter 0x50349da4]
            TST r0,#1 (0x50384214, e3100001)
              bit0 CLEAR -> complete request 1 with 0x64=100  [0x50384278-84]  *** the exit we want
              bit0 SET   -> get NOS iface id=3 (= our synth stub 0x5149d180),
                            call its pread(id=12) (0x5149d18c), RETURN without
                            completing -> waits on the baseband forever.
       <- ecustobj+0x90 (VA 0x80404110) = 0x00000003 in our LLE -> bit0 SET
          -> the dead NOS path. ecust init sets +0x90=0 (0x5034881c); something
          later sets it to 3.

So the logo is gated on ONE flag with a KNOWN-GOOD completion value (100,
matching ngvm's helper_request sw_reason). This is exactly ngvm's HelperDrv
(sw/kernel/chan.c helper_request fn 1 -> request_complete(st, sw_reason)):
on a phone the baseband answers request 1; our synthetic NOS never does.

helper.ldd has NO hardware I/O - it is pure software that delegates the
startup reason to ecust (vtable+0x12c = *(ecustobj+0x90)) and, when that
flag's bit0 is set, to the NOS/Variant interface. ecustobj (0x80404080,
vtable 0x5034a970) is the N-Gage custom-kernel-extension Variant singleton.

TWO FIX PATHS (next):
  A. AUTHENTIC (user's "modem that answers"): make the NOS/Variant interface
     answer helper.ldd's pread(id=12) and complete its pending request with
     the startup reason - the real baseband behavior ngvm stubs. Needs the
     NOS async-completion contract (the synth stub is our code: scratch/
     nos-stub-blob/nos_stub.S).
  B. BOARD/STATE: find what sets ecustobj+0x90 to 3 (setter 0x50349d8c via
     vtable slot +0x128; not called from within ecust, so set by the boot
     flow / a condition) and provide the hardware/state that leaves bit0
     clear, so helper.ldd completes request 1 with 100 directly.
Either unblocks Nokia.dsy -> DosServer -> Starter -> SplashScreen -> logo.

## 2026-10-30 COMPLETE LOGO CHAIN TRACED: it bottoms out at the System Agent's modem query (user was right) (update made with Claude)

Full dependency chain from the logo down, all verified from idle-c4400
saved-thread forensics + disassembly:

  logo
   <- SplashScreen.exe (never launched; draws the logo)
   <- Starter.exe launches the app chain (SelfTestServer..SplashScreen)
   <- Starter's DSClient SendReceive to DosServer completes
   <- DosServer (loads Nokia.dsy per DosServer.ini = "Nokia.dsy")
   <- Nokia.dsy (the System Agent plugin) completes its async
      RSessionBase::SendReceive (opcode 1) to a phone/telephony server
   <- that server's reply
   <- (ultimately) the MODEM provides the phone/charger/battery state.

Both StarterServer (thread 0x8040d210) and DosServer (0x8040dad4) are blocked
in User::WaitForRequest (EUser 0x503b2470), saved-PC confirmed. Nokia.dsy's
last act before DosServer blocked (cycle 3,506,796,079): SendReceive (EUser
0x503b2254) then WaitForRequest on a status at user 0x401e28. nosdriver did
NOT run after 3.447e9, so the query is parked above the ISI hardware (at the
telephony/phone-server level), waiting for a reply that only the modem can
ultimately source.

So the earlier "modem is a red herring for the logo" was WRONG. The modem IS
the root gate - reached via System Agent (Nokia.dsy) <- DosServer <- Starter,
not via a direct nosdriver call. ngvm reaches the logo because its kernel +
servers complete these requests instantly AND its chan.c answers the modem
ISI (charger 0x08->0x09, battery 0x0A->0x0B, identity, service-not-
identified). The USER'S INSTINCT - "emulate a modem that answers, software now,
verilog later" - is correct and is the fix.

NEXT: identify the exact server Nokia.dsy's opcode-1 SendReceive targets
(session at its object +0x1c; likely ETel/RMobilePhone or a Nokia phone
server) and build a responder that supplies the phone/charger/battery state
per ngvm chan.c, at the right layer (phone-server IPC, or trace the request
down to the ISI transport and answer there). That unblocks Nokia.dsy ->
DosServer -> Starter -> the app chain -> SplashScreen -> logo.

## 2026-10-30 CORRECTION: the logo gate is NOT the modem - it is the Starter app-chain launch (Starter <-> FbServ/WServ) (update made with Claude)

The modem/ISI theory is WRONG for the LOGO. ngvm's chan.c charger/battery
replies gate GAMES ("Xanadu Next exits at start"), not the boot splash. In
ngvm's first 6 s the only NOSDRIVER traffic is EStart probing it once; the
energy-management conversation happens later. So the modem is a red herring
for the logo.

What actually draws the logo (ngvm process order after EStart exits clean):
SelfTestServer -> DBRECOVERY -> AudioServer -> AppRun -> **SplashScreen**
(draws the Nokia then N-Gage logo, "lcd: 3 updates") -> Sysamob -> MSexe.

Our LLE reaches the BASE server stack (EwSrv window server, FbServ
Fontbitmapserver, SharedDataServer, DosServer) + Starter.exe runs - but NONE
of the Starter-launched chain executes: SelfTestServer/SplashScreen/AppRun/
Sysamob have **0 instructions**, never created as processes. All their
binaries AND the 3 fonts (Ceurope/CalcEur/Browsereur.gdr) are present in our
ROM (same file table as the THC dump), so nothing is missing.

Pinned gate (ngvm --trace 4 vs our idle-c4400): ngvm's StarterServer connects
to Fontbitmapserver (fn -1) and Windowserver (fn -1) and both COMPLETE
instantly (ngvm's servers are HLE stubs that accept immediately). Our LLE runs
the REAL FbServ/WServ; StarterServer blocks (its thread 0x8040d210 holds an
FbsCli.dll object at +0x44; EwSrv-Main holds a Hal.dll object). Starter.exe
ran until ~3.493e9 then stopped; the window server finished init and entered
WaitForAnyRequest (user mode) correctly. So the block is a real-Symbian
server-session completion that ngvm's stubs sidestep - StarterServer's
Font/Bitmap-server (or window-server) session/request does not complete.

NEXT: find StarterServer's exact block - the server request it waits on and
why the real FbServ/WServ does not complete it (connect accept vs a specific
font/screen request). Compare the real FbServ/WServ RunL path against what
StarterServer sends (ngvm shows FbServ fn 0 args 0x10005 and WServ connect).
The logo is one real-server IPC completion away, not a modem.
Target frames: build/sim/screens/ngvm-logo-target/{nokia,ngage}-logo.png.

## 2026-10-30 LOGO GATE IDENTIFIED: the baseband ISI/Phonet modem conversation (ngvm oracle) (update made with Claude)

ngvm (HLE oracle) boots our EXACT SYM.ROM fully: its process log shows
SelfTestServer -> ... -> AudioServer -> AppRun -> Sysamob -> MSexe ->
Loadersrv -> SplashScreen (draws the Nokia logo, "lcd: 3 updates") -> exits
clean. So the splash is drawn by a SplashScreen process that Starter launches.

The gate is the **baseband modem conversation**, documented authoritatively in
ngvm's sw/kernel/chan.c (NOSDRIVER section, ~line 307): the firmware sends
ISI/Phonet messages to the cellular modem via nosdriver.ldd and waits for
replies. THERE IS NO MODEM. ngvm answers them:
  - most services -> COMMON_MESSAGE / service-not-identified (clients take
    their error path instead of waiting forever);
  - energy management (resource 0x17, via Nokia.dsy -> System Agent charger
    0x100052C9 / battery 0x100052D3): 0x08 answered by 0x09 subblock 0x13
    (charger state), 0x0A by 0x0B subblock 0x16 (battery bars). "Without the
    charger's, Xanadu Next exits at start and System Rush stops after its
    first screens" - i.e. the energy-management reply is a hard gate for the
    boot UI;
  - phone identity 0x1B/IMEI and SIM 0x09/IMSI: made-up test-equipment values.

In OUR LLE the real nosdriver.ldd + the real 2.5 MB NOS/GSM module run, but
the RF/DSP baseband they sit on cannot exist in emulation, so the ISI query
never gets a reply and Starter never launches SplashScreen. This is the
long-flagged baseband/custom-hardware wall, now pinned to a named, documented
protocol with exact reply layouts in chan.c.

### The fork to the logo (decision needed)
A. **Model the modem mailbox at the board level** - find nosdriver.ldd's
   hardware ISI transport (the register/shared-memory + interrupt it uses to
   reach the baseband) and inject the chan.c replies there. Legitimate
   hardware model of the modem interface; the reply CONTENT (charger
   connected, no SIM, test IMEI) is the only synthesised part, which is
   honest for a phone with no modem/SIM. Requires locating the transport.
B. **Inject at the nosdriver channel level** - the ISI conversation is
   software (firmware <-> nosdriver.ldd <-> NOS module), mostly above the
   hardware the board sees, so this is the "LLE fix that smells of HLE" the
   user ranked last: intercept nosdriver's channel control-4/request-0 like
   ngvm does.

Open sub-question blocking A: does the real NOS module, handling an
energy-management ISI query, hit a modellable hardware access, or spin in
software waiting for a baseband processor? (Needs a trace of the System-Agent
query path; the system is already idle at the checkpoints, so the query may
have erred or not yet been sent.) ngvm's chan.c is the exact reply spec for
either path. Reference target: the ngvm Nokia-logo frame.

## 2026-10-30 MILESTONE: full splash server stack is UP (window server + Fontbitmapserver); frontier = Starter blocked, no frame drawn (update made with Claude)

Thread/process census of idle-c4400 (resume to idle, 5.5e9, stuck 2.1e9
cycles with no progress). SEVEN processes now live (was 3 at the C: wall):
EKern, EFile, SharedDataServer, EwSrv (the WINDOW SERVER), FbServ
(Fontbitmapserver), Starter, DosServer - exactly the ngvm-oracle chain that
precedes the splash. Threads: Supervisor, NULL (current = idle), EFile Main
+ LoaderThread + ReclaimThread, SharedDataServer, EwSrv Main (WAITING on
0x804093d8), Fontbitmapserver, StarterServer (WAITING on 0x80406ffc),
DosServer. Names are 16-bit Unicode in the DObject (HBufC at obj+0x10).

No framebuffer exists yet: scan_framebuffer.py (new tool; the panel is 16bpp
0x0RGB per n-gage/docs/hardware.md, so a real frame has every high byte's
top nibble clear across the whole 71.5 KiB) finds only all-black/noise - the
splash was never composed. So the block is BEFORE the first draw: EwSrv and
StarterServer are both parked on wait objects while the NULL thread idles.
Last kernel debug print is still 'TRtcQueue::Add: 2'.

FRONTIER (next): identify what StarterServer waits on (obj 0x80406ffc, user-
side vtable 0x50558575 owned by EFile) and what EwSrv Main waits on
(0x804093d8) - the N-Gage Starter is the splash driver; per the project
memory it historically gates on a baseband/phone (ISI/Phonet energy-mgmt)
reply. Now the REAL NOS runs, so the question is whether Starter waits on a
NOS/phone-app event the board still doesn't deliver, or simply on an app/DLL
load. Compare against ngvm (which completes Starter and reaches the logo).
New tools: scan_framebuffer.py, extract_cdrive.py. idle-c4400 kept as the
forensics base.

## 2026-10-30 STORM GONE: stamped image boots clean; LCD display-on at 2.155e9 from reset (update made with Claude)

boot-v15-freshstamp (from reset, cdrive-stamped-4mib.img, 2.5e9 budget):
185 C: flash programs TOTAL (vs 83K across the storm runs), confined to
1.944-1.962e9 - the storm was one-time first-boot work and is now baked
into the harvested image. The run reached the identical LCD frontier
(162 headers, init + display-on signature) at ~2.155e9, 1.32e9 cycles
earlier than the old-image path, then idles to the budget. New canonical
from-reset base: fresh-c1600 (stamped-image lineage, checkpoint v5).
fresh-c1250 (half-formatted-image lineage) deleted. Boot-to-display-on is
now ~21 simulated seconds (real phone ~6 s to logo; the remaining gap is
the idle-wait frontier plus early-boot timing, not flash churn).

Frontier: after display-on nothing pushes a frame; the system idles in the
null thread. nosbody6 (in flight) writes idle-c4400 at the idle for
thread-state forensics to name the waiter (expected: the FBSERV/EDISP
splash chain waiting on a server or an event the board does not deliver).

## 2026-10-30 LCD REACHED; stamped C: harvested as the canonical image; sim folder cleaned (update made with Claude)

The boot reached lcd.ldd at 3,475,322,608: the display transport is live
(headers 0x09200000/0x49200000 with command bytes 0x65/0x66). New header
0x0784xxxx decoded from lcd.ldd 0x50400978: a 2-byte display READBACK after
command 0x66 (two reads of data register 0x58121208, checked byte must be
<= 0x7f) - modeled (reads return 0). Earlier same run: kernel hw-info query
reads boot-latch 0x08000040 (zero-reset latch added; load_state now keeps
constructor-seeded latches missing from a snapshot, mirroring the probe
merge - previously they vanished on resume).

Flash nailed per the user's ask: the post-storm C: overlay was HARVESTED
from idle-c3400.host (scratch/tools/extract_cdrive.py; the u64-0x400000
marker candidate whose 64KiB blocks carry LFFS magic 0x503b3b60 at +4) into
build/firmware/thc/cdrive-stamped-4mib.img - both run scripts now use it.
Note the OLD image already had 64/64 block headers, so the 1.9e9-cycle storm
was NOT virgin-block stamping: it changed 58,494 bytes across the volume
(write amplification / LFFS GC / first-boot data). Whether it recurs with
the harvested image is being answered empirically by a from-reset run
(boot-v15-freshstamp, budget 2.5e9, writes fresh-c1600): if the storm is
gone, boot-to-frontier drops ~1.9e9 cycles; if it recurs, the flash model
has a real defect to chase (the user flags 4e9 cycles with no logo as wrong
- a real phone boots to logo in ~6s = 0.6e9 cycles, so the storm is the
main authenticity gap).

Cleanup: build/sim/runs 4.6G -> 10M (all run dirs removed except nosbody4
evidence + the two in-flight); checkpoints trimmed to fresh-c1250 (from-reset
base) + idle-c3400 (post-storm frontier base).

## 2026-10-30 POST-STORM FRONTIER: nosdriver statically imports two REAL NOS body functions; image+stub now coexist (update made with Claude)

The storm run (resume idle-c2600, budget 4.5e9) got past the stamping and at
3,290,217,010 nosdriver.ldd (ROM 0x11b4040-0x11c0000) called through its IAT
into the NOS module body: thunk 0x511b4458 -> [IAT 0x511b4030] = 0x514a13cc
(NOS+0x414c), r1=13 - and ABORTED (FSR 0xd section permission) because only
the 648-byte synthetic blob is served there; the run then died at the kernel
fault-dump's second scratch word 0x0c0047f4 (previously unmodeled - window
now grown to cover 0x47f0/f4/f8 as latches, checkpoint v5 + v4-compat).

Full enumeration of ROM-wide word references into the NOS VA range (noise
from JPEG/resource bytes filtered by alignment and module type): exactly TWO
real static imports, both nosdriver's: [0x511b4028]=NOS+0x37d0 and
[0x511b4030]=NOS+0x414c. nosstarter's [0x50350548]=entry+4 was already
handled by the stub. The NOS export directory word 0x514a13cc also sits at
ROM 0x503168dc (plaintext tail region).

Disassembly of the real targets (gsmstuff plaintext):
- NOS+0x37d0 register_handler(ptr, id): id<=0x19 stores ptr into kernel-RAM
  table [0x8000c724 + id*4]; >0x19 panics via a broken import thunk. Sibling
  +0x3808 get_handler(id) reads it back.
- NOS+0x414c ctor(obj, id): sets obj vtable 0x5171103c (const, in-image),
  id==0xfe takes an alloc path through two broken thunks; any other id (13
  observed) calls only NOS-internal helpers 0x514a0ed0/0x514a1034 which
  write kernel-RAM byte tables 0x8000ca64/0x8000ca30 (panic thunk only on
  id>0x19). So the REAL code paths nosdriver exercises are self-contained.

Model change: nos-image now coexists with nos-entry-stub - the stub keeps
its proven boot-time windows (blob [0x9d000,0x9d288) incl. the nosstarter
entry B at 0x9d284, power model at 0x9e000) and the real THC image serves
the body [0x9d288, 0x316900). Both run scripts pass nos-image. The known
risk going deeper into real NOS code: 49 import thunks whose IAT slots live
in scrambled flash (PA 0x6e030-0x725c0, no plaintext anywhere) and NOS
data/bss literals into the below-image pages - each future stop names the
one slot to resolve by RE (board can serve synthesized IAT words at exact
addresses). Run in flight: nosbody1 from idle-c2600, budget 4.5e9.

## 2026-10-30 RESTORE BUG: load_state re-applied the pristine C: image over restored stamps (update made with Claude)

Resuming mid-storm from idle-c2600 exposed it: load_state re-applied
cdrive_image_ over the restored overlay, so every resume silently reverted
the flash to the pristine image while LFFS's RAM state believed its stamps
existed (state divergence; the first corrupted run was killed before any
conclusions were drawn from it). The re-apply dated from when C: was
read-only pre-checkpoint, where it was a harmless no-op. Fix: the saved
overlay IS the flash content; the image seeds the array at construction
only. All current checkpoints (fresh-c1120/c1250, idle-c2600) embed the
image in their saved overlay, so nothing is lost. Earlier runs are
unaffected (fresh-c1250 predates the first C: write). New board test:
programmed cell survives restore with an image configured (29 sections).

## 2026-10-30 FIQ PUMP VERIFIED IN-SIM: the 1.5176e9 wall is GONE; boot alive through 2.5e9 in an LFFS stamping storm (update made with Claude)

Three staged runs from fresh-c1250 after the FIQ model landed:
1. First run: the FIQ was taken (CPSR mode 0xd1), the pump ran its banked-
   register fast path exactly as disassembled (pending read 0x1201d0=8,
   counter re-arm, DQ7 poll of the programmed halfword, buffer-done path,
   DFC enqueued on 0x80006bb8, timer stopped). New stop +4.7K cycles later:
   the FIQ dispatcher tail (0x5032299c) reads fast-status 0x0c120050
   (tst #7; bit1 = fast-DFC kick; the DFC-drain check follows). Modeled:
   reads 0, ack writes accepted (assumed_fiq_status).
2. Second run: +34K cycles - the DFC drained, RequestComplete fired, the
   semaphore signaled, LFFS read back its block headers (the programmed cell
   now reads 0x81bc after a second overprogram pass - correct NOR AND
   semantics) and the kernel did page-table work. New stop: LFFS issues a
   BARE WORD write (select 0xf, value 6, 0x02400540) in read mode. On AMD
   NOR a word write is never a command cycle and is ignored - modeled that
   way (mid-protocol word writes still stop the run).
3. Full-budget run (2.5e9): TIMEOUT WITH THE BOOT ALIVE - flash activity to
   cycle 2,499,984,258. The wall at 1,517,595,533 is gone (+982M cycles).
   The boot is inside a one-time LFFS block-stamping/GC storm: 26,977
   program sequences marching monotonically through the volume (0x2421xxxx
   -> 0x25e17b4 ~= 2 MiB of 4 MiB by budget end) plus constant block-0
   metadata updates; zero erases; instruction tail is pure
   elocal/medint/ecust/ekern churn (no EStart yet - it is serialized behind
   this storm, which started as the completion of the blocking bootdata
   write). Likely cause: the 4 MiB C: image is ngvm's 1 MiB formatted volume
   padded with erased space, and LFFS claims/stamps the virgin blocks on
   first write.

Cost analysis: each halfword program paid ~2800 cycles, dominated by the
arbitrary kUnit60Delay=2000 (the real compare 0x186 prescale is unknown and
the pump is purely event-driven, so the delay is a free parameter).
Lowered to 128 (~5x storm speedup; still past medint's arm sequence).
Next run: 3.2e9 budget from fresh-c1250, checkpoint idle-c2600 at 2.6e9 -
expect the storm to finish by ~1.9e9 and EStart to continue; watch for
FBSERV/EDISP/lcd (the splash chain) after SetEntry completes.

## 2026-10-30 C: WRITE COMPLETION SOLVED: it is a FIQ flash pump; board now models the unit-0x60 FIQ (update made with Claude)

The "nothing ever completes the C: write" wall is closed. The completion is
delivered by FIQ, which the board never asserted (main.cpp pinned i_fiq=0).
Full chain, all from disassembly + the idle-c1517 live heap:

- The FIQ vector (VA 0x1c, kernel vector page PA 0x321000, live phone maps
  VA 0 -> PA 0x321000) loads the handler pair at kernel globals 0x800004e4
  (PC) / 0x800004e8 (banked ip) and jumps; default tail 0x50327a28.
- At the blocked checkpoint [0x800004e4] = 0x503851bc = medint's hand-written
  FIQ flash pump (runs entirely in FIQ-banked r8-ip; pump object also in
  [0x80006ee0], holds the AMD unlock VAs 0x59800aaa/0x554 at +0x10/+0x14 and
  medint's I/O page VA 0x59e011c0 = PA 0x0c1201c0 at +0x30).
- medint's write path (0x50386500): program first halfword via PDD vcall,
  then arm hw timer unit 0x60: +0x04 ctrl = 2 (run), +0x08 counter = 0,
  +0x10 compare = 0x186, and finally ENABLE FIQ-ICU bank0 bit 3 (tail call
  0x50324898(3) -> 0x0c1201c8 |= 8). +0x08=enable-SET, +0x0c=enable-CLEAR -
  the previous model had this polarity INVERTED (that is why the old
  unit60-as-IRQ experiments never fired when gated).
- Each compare match -> FIQ -> one pump step (0x503851bc): read pending
  0x0c1201d0, test bit 3; write counter 0x0c120a68 = 0 (clears the match =
  re-arm); DQ7/DQ5 poll the last programmed halfword; program the next one
  (AA/55/A0 at 0x59800aaa/0x554); return from FIQ. Instant-complete flash in
  the board model means one halfword per FIQ.
- Buffer done (0x50385294): enqueue the completion DFC (node pumpobj+0x1c,
  fn +0x24 = 0x5038693c) on kernel list 0x80006bb8 via 0x503451f4, stop the
  timer (0x120a64=0), mask FIQ (0x1201cc=8). The scheduler (0x50327f48)
  pops that list every yield - the blocked idle loop yields constantly - and
  calls the DFC in mode 0x1b, which runs medint's completion
  (0x50387200-0x50387304: PDD vcalls, re-init compare regs) ->
  DMediaDriver::Complete -> RequestComplete -> ELOCAL's RSemaphore::Wait is
  signaled and the boot resumes.
- Why the first 277 writes "completed": they were absorbed by LFFS's log
  buffering; this one is the first wait on the pump semaphore.
- Second IRQ dispatcher mapped along the way (0x503229a0, reachable from the
  IRQ vector chain): reads status 0x0c120050 (tst #7, write-back ack; bit 1
  -> fast DFC [0x8000001c]), then FIQ-ICU currents 0x1201d4/0x120214/
  0x120254 (+0x14 of each bank; value = source+1; bank0 current 4 = the
  FIQ-owned timer bit, special-cased as cascade-check). Handler table
  0x80000b64 (bound [0x800066e4]=0xba) is indexed v-1 / v+0x1f / v+0x3f by
  this dispatcher and 0x5c+v by the family-A one (0x5032287c, currents
  0x120114/0x154/0x194, enables 0x120108/0x148/0x188). Full live handler
  census at idle-c1517: family-A srcs 0x5d tick (en=1), 0x5e (en=0), 0x63
  (en=0), 0x72/0x74/0x75 epbus (en=0), 0x76 cbus (en=1, clients keypad+rtc
  only), 0x8b cbus class-3 (en=1, zero clients); family-B: none - unit 0x60
  is FIQ-only.

Board model changes (board-only; Verilated RTL unchanged, so existing
checkpoints remain loadable): unit60 compare-match now raises FIQ (new
unit60_fiq(), main.cpp drives i_fiq; removed from timer_irq() and from the
0x120114 IRQ current), FIQ-ICU banks 0x1201c0/0x200/0x240 with +0x08 set /
+0x0c clear (polarity fixed) and new +0x10 pending / +0x14 current reads,
counter write re-arms while ctrl==2 (the pump's per-step re-arm), arm delay
2000 cycles (compare 0x186 prescale unknown; pump is event-driven so any
delay is functionally correct). 28 board-test sections pass. NOTE: idle-c1517
restores a polarity-poisoned mask (enable recorded as clear), so FIQ-era
resumes must start from fresh-c1250 or earlier; fresh-c1250 predates medint
(only the harmless boot-time bit-27 FiqAPIIOAbort write differs).

Also this session: the THC "real NOS" question re-settled - the NOS plaintext
for PA 0x9d280+ exists ONLY in the gsmstuff dump (build/firmware/thc/
nos-image.bin); the ROM-dump low window is the +5MiB remap (VA 0x5000a000-
0x50317000 -> PA +0x500000, confirmed byte-identical against SYM.ROM), NOT a
descramble, and the NOS IAT pages (PA 0x6e030-0x725c0) exist in no file as
plaintext (SYM.ROM there is scrambled flash, entropy 7.9; scrambling resists
XOR/bijection/affine models - plain 0x0000 maps to 26763 distinct scrambled
words, so it is keyed on address in a non-affine way). The import-fixup route
for the real NOS stays parked; the synthetic stub remains the mainline.

## 2026-10-30 ROOT CAUSE FIXED: CTR assoc=0 made EKA1's clean-cache loop endless (update made with Claude)

The post-EStart "idle" was the Supervisor stuck in EKA1's clean-D-cache-by-
index loop (0x50328408, MCR p15,0,R1,c7,c14,2). ZAP's cache type register
(0x03142142) reported assoc=0 (direct-mapped), so the loop's way increment
(1 ROR assoc) was literally +1 and its ADDS/BCC carry exit needed 2^32
iterations (~1.7e14 cycles; trace: outer counter at 0x17 after 18M idle
cycles; a 2.5e9 run confirmed true deadlock). All the while EStart-Main sat
READY in the queue (prio 350, FileSrv 760, resched flag set) - see the
correction entry below. Fix (patch 0009, commit 0164a87): report the real
ARM920T CTR 0x0D172172 (assoc=6, ctype=6) in zap_cp15_cb.sv; ZAP executes
any index clean/inv as a whole-cache op, so only the software-visible
geometry changed; the loop now terminates after 8 sets x 64 ways = 512 MCRs.
The only CTR read in the whole boot is the fatal one at cycle 1112551742,
so the timeline up to there is unchanged.

## 2026-10-30 FRONTIER PINNED TO THE INSTRUCTION: ELOCAL blocks on a media semaphore after its final C: write (update made with Claude)

The mountend window (from fresh-c1250, full instructions 1250M-1521M) traces
the exact stall. Sequence at the end:
- 1470.8M-1517.6M: 278 TBusLocalDrive::Write to C: (LFFS), interleaved with a
  44.4M-cycle burst of ERam (RAM-drive, eram!<code> 65K hits) + ekern memory
  ops - EStart/F32 populating the RAM drive, normal boot work.
- 1517585350 & 1517597929: final two C: writes (LFFS log). The last flash
  program sequence (unlock AA/55, program A0, data 0xffbc -> 0x024214dc) is
  well-formed and the model serves it.
- 1517597929 euser!TBusLocalDrive::Write -> 1517603140 RSessionBase::Attach ->
  1517607076 elocal!ord1+0x2a62 -> 1517607575 euser!RSemaphore::Wait (exec
  0x2a, handle in FileSrv heap 0x8060315c) -> from 1517610529 on, PERMANENT
  idle (ekern ord252 null-loop <-> nosdriver!ord1+0x2e8e90 forever).

So the precise block: ELOCAL (the C:/LFFS local-media FSY), after its final
flash write, calls RSemaphore::Wait on a media/DFC completion semaphore that
is never signaled. 277 earlier writes completed fine, so the signal path
normally works - something about this final write (or the state after the
RAM-drive burst) leaves the completion unsignaled. The real medint.pdd
delivers flash-write completion via a DFC/interrupt; the board model's C:
flash is synchronous (no completion event), so whatever async path this last
write takes waits forever. nosdriver!ord1 is the REAL nosdriver.ldd running
as the idle callback (not the synthetic stub) - unrelated to the block, just
the idle tick.

NEXT (board-model work, in scope - not baseband): find what signals the
media-write-completion semaphore on the 277 good writes vs this one; likely
the model must raise a flash-program-busy-then-done status or a medint DFC
so the async write path completes. Tools: mountend window has the full trace;
compare a completing write (~1473M) against the stuck one (~1517.6M) at exec
level. Resume base fresh-c1120 (before EStart) or fresh-c1250 (EStart ready).
This is the deepest, most precisely-located frontier reached: an authentic
Symbian boot writing LFFS to C: and populating the RAM drive, ~750M cycles
past the session-start C: crash.

## 2026-10-30 TRUE FRONTIER: EStart mounts a filesystem, reads it fully, then blocks at ~1.5176e9 (superseded: pinned to the ELOCAL semaphore wait above) (update made with Claude)

Tracing the estartfinal window (from-reset, 1125M-1134M) showed EStart's last
code (PC 0x503eec28, cycle 1126179781) calls efsrv!RFs::MountFileSystem ->
RSessionBase::SendReceive to the file server, which runs CServer::RunL /
CFileSystem::SetLibrary / CMountCB and then does sustained medint +
TBusLocalDrive::Read - EStart is MOUNTING a second filesystem and reading it.
The longboot run (resumed, C:-byte-read fix active) confirms: C: flash is
accessed with ADVANCING addresses (134256 distinct) up to cycle 1517595533,
including the byte-read at 0x024214dc (be=0x2) which the fix serves correctly,
followed by a fresh command sequence (0x02400aa8<-0xaa). Then C: access STOPS
at 1517595533 and the system goes PURELY IDLE for the next 3.48e9 cycles
(timer/NOS-stub/keypad polling only, no C:, no 4th process) to the 5e9 budget.

So the real block is at ~1.5176e9, AFTER the mount+read: EStart issues one
last C: command then blocks, and no window server is ever launched. This is
well past every prior frontier. A windowed instruction run (boot-v15-mountend,
1515M-1521M from fresh-c1250) is in flight to capture the exact failing F32
operation at that point. NOTE the prior "idle at 2.2e9/3.5e9" checkpoints
(idle-c2200/c3500) and the whole "NOS waiter" investigation were looking at
this same post-mount idle from the wrong angle - ord252 idling is the SYMPTOM;
the cause is the F32/medint operation that completes its read then never
advances EStart. fresh-c1120 and fresh-c1250 are the clean resume bases.

## 2026-10-30 CORRECTION: ord252 is the NULL-thread IDLE loop, not a boot waiter; 0x800004ac is an idle CALLBACK pointer (update made with Claude)

Experiments falsified the "NOS readiness waiter" theory below. Three from-reset
probes that set *(0x800004ac) from a patched NOS stub all crashed the kernel:
the fault PC 0x50331b78 is the return of `MOV LR,PC; MOV PC,r3` at 0x50331b70
- the kernel CALLS *(0x800004ac) as a FUNCTION POINTER (fake value 1 = jump to
address 1 = prefetch abort -> kernel crash-dump handler ekern!ord470+0x298,
which records super-page fault state to debug registers 0x0c0047f0/f4/f8 then
self-loops - that is the 0x0c0047f4 "unmapped" stop). And the loop at
0x50331a60-0x50331bb0 ALWAYS branches back: it never exits. Reading EKA1
semantics: ord252 is the NULL/idle thread loop - each iteration invokes the
Variant's Idle method (vtable+0x48 with r1=0xd) and then any registered IDLE
CALLBACK in 0x800004ac. The "infinite spin" is NORMAL IDLING. The synthetic
NOS stub patch was reverted (pristine blob restored, rebuilt).

So the real frontier is back to: WHY does EStart's F32 request at ~1126.2M
never complete? EStart's last act (estartwin trace) is BL 0x503ef4d0 (an
efsrv import thunk) at 1126179781 after large C: reads; from then on the
system idles with EStart blocked (state 2), FileSrv parked in its CServer
loop, LoaderThread parked. A full-instruction window 1125M-1132M
(boot-v15-estartfinal, from fresh-c1250) is in flight to capture the exact
request and the file server's handling of it. The crash-dump debug registers
0x0c0047f0-f8 are a diagnostic gift: any future kernel fault writes the fault
state there (worth modeling as a latch to capture panics instead of stopping
on unmapped access).

## 2026-10-30 DEEP FRONTIER (fully characterized): kernel boot-waiter spins on NOS Variant iface #13 readiness (SUPERSEDED by the correction above - the "waiter" is the idle loop) (update made with Claude)

After the CTR + C:-byte-read fixes the boot runs to a kernel busy-wait that
never completes; at 3.5e9 cycles (idle-c3500 checkpoint) still only 3
processes (EKern/EFile/EStart), no window server, no logo. Mechanism, fully
disassembled:

- The hot loop (6.5M transitions in a 6M-cycle window at 2.84e9) is ekern
  ord252 at 0x50331a50-0x50331bd4 <-> the synthetic NOS stub at VA
  0x5149d18c. Each iteration: re-load the Variant singleton ([0x8000038c]),
  call its iface #13 method (r1=0xd, vtable+0x48 -> stub 0x5149d18c, a
  zero-fill-and-return-0), then check kernel global *(0x800004ac); if 0,
  BL 0x50323c74 (yield/reschedule) and B 0x50331a60 (loop). Cooperative
  busy-wait - that is why ReclaimThread also runs and the box looks "idle".
- Global 0x800004ac stays 0 at 1.25e9 AND 3.5e9. It is written only by ekern
  ord374 (trivial setter at 0x503452d8: STR r0,[0x800004ac]; BX LR), which
  is reached via a function pointer (no BL callers in ROM) - i.e. the real
  NOS/variant init calls it to publish readiness. The synthetic NOS stub
  (scratch/boot-v15-nosprobe/nos_stub_blob.h, 648B at PA 0x9d000) REGISTERS
  ifaces #3/#6/#13 with the Variant (calls vtable+0xfc three times, each with
  iface vtable 0x5149d180) but never drives the readiness, so ord374 is never
  called and the waiter never exits.
- The waiter's non-zero path (0x50331a98+) passes *(0x800004ac) to
  0x503222e0 as a meaningful pointer/handle, so a blind fake value risks a
  kernel fault; the correct value is whatever ord374 would publish.

This is the project's long-flagged "synthetic NOS is not authentic baseband"
wall, now reached at a concrete, named kernel waiter. Candidate approaches
(next session): (1) extend the NOS stub's registration code to call ord374
with a valid readiness object after registering iface #13 - needs the right
object/value, which means RE'ing what ord252's non-zero path consumes;
(2) model the NOS/variant readiness event at the board/channel boundary
(ngvm answers the analogous NOSDRIVER ISI energy-mgmt exchange in
sw/kernel/chan.c - charger 0x17/0x08, battery 0x17/0x0A, identity 0x1B -
which its notes say gate the first screens); (3) obtain real descrambled NOS
plaintext (exists in no available file). Resume base: build/sim/checkpoints/
idle-c3500 (post-fix model). ekern.def names ord252/ord374 as internal
(not SDK exports), so those names are positional, not from the import lib.

## 2026-10-30 NEXT FRONTIER: EStart runs then blocks in its process-launch loop (superseded by the NOS-waiter entry above) (update made with Claude)

After the CTR fix + C: byte-read fix, EStart EXECUTES (estartwin: first PC
0x503ee8c0 @1112783076, 26 module transitions through 0x503eec28 @1126179781)
and then BLOCKS. idle-c2200 checkpoint (cycle 2.2e9): still only 3 processes
(EKern/EFile/EStart) - EStart never spawns the window server. EStart-Main
NThread state byte went 4 (ready, @1.25e9) -> 2 (blocked/waiting, @2.2e9);
its saved-SP is 0 and its stack+code chunks (0x804099c8 home=0x00502000,
0x8040977c home=0) live in LOW process-relative VAs, so the kernel-home
checkpoint reader can't walk EStart's user stack. EStart's blocking site is
its startup loop at 0x503eec08-0x503eec3e: iterates a list (r7 += 0x10),
calls 0x503ef4c4 / 0x503ef4d0 / 0x503ef4dc per entry - this is EStart reading
its boot config and launching the next servers; it blocks in one of those
calls (likely a Rendezvous/logon on a child it launches, or an RProcess
create that needs a loader step). NEXT: trace EStart's process space across
0x503ef4c4-4dc (need an FCSE/PID-relative reader, or just a full-instruction
window 1126.0M-1130M filtered to EStart+loader+new-process execs); cross-ref
ngvm, whose EStart launches ~12 servers cleanly to the logos. The LLE is now
~1.0e9 cycles past where it stood at session start (767.8M crash -> EStart
executing + blocking deep in its launcher).

VERIFIED (2026-10-30 ~02:05): post-fix run boot-v15-ctrfix reached 1.5176e9
(267M past the old frontier). estartwin window trace shows EStart EXECUTING
from cycle 1112783076 (first PC 0x503ee8c0, 26 module transitions). At the
1.25e9 checkpoint (fresh-c1250): current thread = FileSrv Main running,
StartupThread exited+reaped, EStart-Main READY prio 350 - matches the ngvm
oracle. ctrfix then stopped on a NEW frontier: byte read (byte-enable 0x2)
of C: flash at PA 0x024214dc refused by the halfword-only model. Fixed in
boot_profile.cpp (array-mode reads of any width serve the aligned word;
writes keep the halfword command protocol; tests added). Resume boot-v15-
postbyte (fresh-c1250 -> 3e9, checkpoint at 2.2e9) is in flight.
TODO (queued to avoid touching inputs mid-run): load_state() re-applies the
pristine cdrive-image over the RESTORED overlay - harmless while
cdrive_writes=0 (true through 1.5176e9) but will corrupt post-first-write
checkpoints; apply image only when the checkpoint overlay is empty.

IN FLIGHT (2026-10-30 ~01:40, superseded by the entry above): (1) boot-v15-ctrfix - from-reset, budget 3e9,
checkpoint fresh-c1250 at 1.25e9, screen capture at end (run-fresh.py);
(2) boot-v15-estartwin - from-reset, budget 1.15e9, module-trace + full
window 1112.5M-1115M across the expected clean-loop exit -> reschedule ->
EStart first instructions (run-fresh-mt.py). Old checkpoints deleted (bound
to the pre-fix Verilated model). ekern.def (244 names, from the SDK WINS
import library, UNVERIFIED wins-vs-marm ordinal parity) added to
build/ngage-defs. SDK extracted at build/sdk-extract (Binaries armi/thumb
libs kept; regenerable: unshield x firmware/nS60_sdk_v1_2/data1.cab).

## 2026-10-30 CORRECTION + real frontier: EStart process+main-thread ARE created and RESUMED; the main thread never becomes READY (update made with Claude)

Checkpoint forensics (idle-c1130.host, cycle 1.13e9) OVERTURN the prior
"Resume never reached / LoaderThread never wakes" diagnosis below. Evidence:

- 7 real DThreads exist at idle (vtable 0x50347598): Supervisor, NULL,
  Main(FileSrv 0x804070bc), LoaderThread (0x804075dc), StartupThread
  (0x8040798c), ReclaimThread (0x80409238), and a SECOND "Main" at 0x8040983c.
  That second "Main" is EStart's main thread (every process main thread is
  named "Main"; ngvm shows it as "EStart:Main"). So the loader DID create
  EStart's process + main thread. Thread container array at VA 0x80405200.
- Full-instruction trace (frontier2) shows StartupThread run euser!RProcess::
  Create (returns OK at 1112396138 -> valid handle, no panic) then euser!
  RProcess::Resume at 1112396484 (SWI exec 0x1D). The kernel resume handler
  runs real scheduler code (ekern ord150/ord327 reschedule, CObjectIx::At,
  TDblQueBase::IsEmpty). So Create AND Resume both happen.
- Yet EStart user code (0x503ee8xx, XIP in ROM) is NEVER fetched, and at idle
  the current thread (kernel global 0x800003d0) = NULL (0x80406c48). So EStart's
  main thread is resumed but never scheduled. StartupThread even CONTINUES after
  the resume (would not, if a higher-prio EStart had been made ready+preempted).

So the real gap: RProcess::Resume does not make EStart's main thread READY.
Checkpoint field anomalies on EStart-Main (0x8040983c) vs healthy FileSrv-Main
(0x804070bc): +0x20 = 0x80000000 (vs 0x8000000c), stack/addr +0x30/0x34 =
0x00502000 (vs kernel-region 0x80602000), +0x38 = 0 (vs 0x80601ccc). EStart's
DProcess (0x80409614) has +0x20 = 0 where FileSrv's DProcess (0x80406eb8) has
0x100000bb (likely a code-seg/chunk pointer) - EStart's process load looks
incomplete. Working hypothesis: EStart-Main is left SUSPENDED (count not 0) or
WAITING on code-seg load completion that never fires, so Resume (clears suspend
only) doesn't ready it. EKA1 DThread field offsets are not from the SDK (public
headers omit the private layout); offsets above are empirical, not gospel.
NEXT: trace the loader's EStart process/chunk/main-thread CREATION window
(Loader active 1112244857-1112285321, inside frontier2) to find the incomplete
step; or decode the suspend-count/wait-state field. Tools: inspect_checkpoint.py
(now reads idle-c1130), run-resume-ckpt.py (resume+checkpoint), ngvm oracle.

## 2026-10-29 Frontier settled: pure kernel idle - no user thread becomes ready after the EStart launch (update made with Claude) [SUPERSEDED by the 2026-10-30 correction above: EStart IS created+resumed]

Extended trace past the launch (frontier3, 1112.5M-1114M): the system settles
into a PURE KERNEL idle - only ekern functions, woken every ~404K cycles by the
timer-tick IRQ (vector 0x18 at 1113732286; tick period 0x632ea), running the
null thread. NO user thread runs: LoaderThread (0x503d3539) and EStart
(0x503ee860) have ZERO hits across 1.5e9 cycles. So after StartupThread's init
completes and it launches EStart (User::StartThread + UserSvr::BlockThreads),
every user thread is blocked/suspended and none becomes READY - EStart is
created but never scheduled, and the LoaderThread never wakes to load it. The
scheduler ticks but has no ready user thread to run.

ngvm (oracle) does this correctly: its LoaderThread runs, loads EStart, EStart
runs and EXITS cleanly (it is the transient launcher), then ~12 servers start
(EwSrv window server, ViewServer, AppArc, EtelServer, Watcher...) -> UI/logo.
So the LLE gap is ONE kernel step: making the newly-launched EStart (and/or the
LoaderThread) READY so the scheduler runs it. This is EKA1 thread-resume/
scheduler behavior; the LLE kernel is unsymbolized (no ekern.idt), so pin it by
cross-referencing ngvm's thread-resume path and/or finding the missing kernel
event (a resume/IDFC the real kernel needs). That is the next and possibly
last major gap before the user-side cascade to the logo.

Progress recap: LLE went 767.8M (blank-C: crash) -> 1.11e9 (EStart launch) via
the ngvm 4 MiB formatted C: image; tooling = ngvm oracle, IDT symbols,
cdrive-image, symtrace. mount-c760 is the resume base (checkpoint-at from a
restore does not write - minor; resume+trace from mount-c760 works).

## 2026-10-29 Frontier pinned: EStart is LAUNCHED but never scheduled (update made with Claude)

Deep-dived the ~1.11e9 block with IDT symbols. Sequence: StartupThread's init
state machine (efile!ord3, 0x503d5290) COMPLETES successfully (returns R0=0 at
0x503d54fe, sets its done-flag), then StartupThread calls euser!User::StartThread
+ euser!UserSvr::BlockThreads - the EKA1 thread-launch of the next process
(EStart). The kernel does the creation work (CObjectCon/CObjectIx::At container
mgmt, CBitMapAllocator page alloc - normal, not an infinite spin; IsFree hit
only 10x on page 0x8a). But EStart's code (0x503ee860) NEVER executes and the
LoaderThread (entry 0x503d3539) never runs in-window: EStart is created and
never scheduled. So the frontier is now the EStart thread start/schedule, not
the C: mount (solved) or the state machine (done).

The remaining question is why the newly-started EStart thread doesn't get
scheduled (a kernel scheduler/thread-control step needing a modeled event, or
BlockThreads not followed by the unblock). The LLE runs the real EKA1 kernel
(unsymbolized - no ekern.idt); ngvm (HLE kernel) schedules EStart fine and
reaches both logos, so it is the comparison oracle. NEXT: cross-check the
StartThread/reschedule path against ngvm, or model the missing kernel event,
to get EStart running -> window server -> LCD -> logo in the LLE screen.png.

## 2026-10-29 New frontier: the LOADER is loading EStart (blocked mid-load ~1.11e9) (update made with Claude)

Symbolized the ~1.11e9 block (IDT names): the last F32 work is mount-control
(efile CMountCB/CFormatCB::CheckMount), and crucially the LOADER is active -
euser!TLoaderInfo runs at 1.1116e9/1.1121e9 and ROM-tail reads (process image
bytes, 0x04730xxx) run to 1.1115e9. So EFile::LoaderThread is mid-load of a
process (EStart, from ROM) and blocks before completing it; EStart code
(0x503ee860) NEVER executes. The block is the EStart LAUNCH - the loader waits
on an async op (WaitForAnyRequest) during the load. This is the gap between
F32-up and the user UI, the same spot that matters for the logo.

Progress this session is enormous: LLE went from crashing at 767.8M (blank-C:
KErrCorrupt) to loading EStart at 1.11e9 (+343M), via the ngvm-produced 4 MiB
formatted C: image. Checkpoint mount-c1111 being written for fast iteration on
this frontier. NEXT: pin the loader's exact wait (resume mount-c1111, trace the
TLoaderInfo load path, find the async completion it needs - a drive read DFC,
a memory op, or an IPC), model it, and EStart should launch -> window server ->
LCD -> logo. Validate against ngvm (which loads EStart and reaches both logos).

## 2026-10-29 LLE boots +343M past the C: crash to a new F32/LFFS frontier ~1.11e9 (update made with Claude)

With the 4 MiB formatted C: image the LLE runs from the old 767.8M crash to
~1,112,551,000 (+345M cycles). Module presence 760M-1.12e9: heavy medint
(299K insns, the flash-driver data loop 0x50386628.. hit 29867x) and ELocal
(121K, LFFS), plus EFile/EFSrv/EUser - i.e. the file server exercising the now-
valid C: volume. C: read activity runs to 1.108e9; last distinctive op a WRITE
0x0c120c14 at 1.1123e9; then the EUser(0x5039cb1c)<->ekern(0x503288d4) idle
loop. So a thread blocked AGAIN, still in the F32/LFFS phase - EStart and the
window server have NOT launched yet. Same discovery pattern as the earlier
frontiers, one big stage deeper. cdrive_writes=0 (the mount succeeded on the
valid volume; the firmware has not written C: yet).

The C: unblock is confirmed solid (ngvm HLE reference + 4 MiB formatted image).
NEXT: symbolize the ~1.11e9 block (what StartupThread/F32 waits on now - likely
the next LFFS/F32 step or the EStart launch), write a checkpoint near 1.11e9
for fast iteration, and continue. Cross-check against ngvm (which boots fully)
for what should happen next.

## 2026-10-29 *** LLE PAST THE C: CRASH: 4 MiB formatted LFFS image mounts *** (update made with Claude)

Got a VALID 4 MiB formatted LFFS image by temporarily enlarging ngvm's C:
(NGVM_SAVE_BASE 0x01C00000 / SIZE 0x400000 in ~/develop/n-gage sw/include/
ngvm_hw.h, rebuild kernel, run ngvm --save, revert) -> build/firmware/thc/
cdrive-formatted-4mib.img (64/64 blocks have LFFS_MAGIC 0x503B3B60). The LLE
model now loads it via opt-in cdrive-image= (boot_profile: image loaded in ctor
AND re-applied after load_state so it survives checkpoint restore - a 1 MiB
image failed because our LLE volume is 4 MiB; size MUST match medint's reported
size). Resume from mount-c760 with the 4 MiB image: StartupThread SURVIVES the
mount (cdrive_writes=0 = mount succeeded on the valid volume), boot runs PAST
the old 767.8M KErrCorrupt death, actively reading C: at 769.99M. The C: crash
is SOLVED for the LLE.

Mechanism: our LLE firmware's LFFS, unlike ngvm's formattable HLE drive, does
NOT auto-format a blank C: - it needs a pre-formatted volume. ngvm (fast HLE)
produces one by letting the firmware format its formattable drive; we feed that
formatted image to the LLE. run-resume-760.py / run-stub.py now carry
cdrive-image=.../cdrive-formatted-4mib.img.

NEXT: run the LLE long (2-3e9) to see how far it boots now (EStart, window
server, the LCD path -> Nokia/N-Gage logo in screen.png). Validate against the
ngvm reference frames (build/sim/screens/ngvm-milestone/).

## 2026-10-29 *** MILESTONE: HLE reference boots OUR firmware to NOKIA + N-GAGE logos; formatted C: extracted *** (update made with Claude)

Built and ran the Pocket core's ngvm (Unicorn ARMv4T HLE: NGVM C kernel +
our user firmware) on OUR SYM.ROM:
  python3 ~/develop/n-gage/tools/ngvm/ngvm.py --rom /tmp/ngage_sym.rom
    --kernel ~/develop/n-gage/build/kernel/kernel.elf --save <c.img>
    --seconds 12 [--frames-to DIR --frame-every 60]
Result: FULL boot. Dozens of servers up (EwSrv/EikSrvs window server, AppArc,
SystemAgent, Phone, C32 comms, Starter, FbServ, EFile...), and the captured
frames show the authentic NOKIA logo (~5 s) then the N-GAGE logo (~11 s) -
saved build/sim/screens/ngvm-milestone/{nokia-logo-5s,ngage-logo-11s}.png.
So OUR firmware + ROM are correct and boot to the logos; the block was never
the firmware.

KEY for the LLE: ngvm presents C: as FORMATTABLE flat memory, so the firmware
FORMATS the empty C: itself (3124 writes) and ngvm saved the resulting VALID
formatted LFFS (1 MiB, every 64 KiB block word[1]=0x503B3B60 LFFS_MAGIC) ->
build/firmware/thc/cdrive-formatted-1mib.img. This is exactly what our LLE
needs: our LLE crashes because its C: is blank/unformatted and (unlike ngvm)
not auto-formatted. Prebuilt tools now available: ngvm (bootable HLE
reference), romsyms+IDTs (names), the formatted C: image.

NEXT (LLE boot past the C: crash): either (a) pre-fill the LLE cdrive_ overlay
with a formatted LFFS image - but size must match what our medint reports to
LFFS (the LLE scan expected 0x400000=4 MiB; ngvm's image is 1 MiB, so rebuild
ngvm with NGVM_SAVE_SIZE=4 MiB, or match the LLE flash size to the image), or
(b) make the LLE C: FORMATTABLE like ngvm so the real firmware formats it
(exercises our flash program/erase model) - the more authentic fix. Validate
the LLE boot against ngvm's logo frames.

## 2026-10-29 ROOT CAUSE CONFIRMED: blank C: scans as invalid LFFS -> KErrCorrupt -> crash; C: must be pre-formatted (update made with Claude)

Decoded the exact failing check (trace decode, IDT-independent): ELocal's LFFS
mount runs a scan loop (0x5038fb80..0x5038fbd4) over the whole volume in 64 KiB
(erase-block) steps, R5 summing to the total size [R7+4]=0x00400000 (4 MiB);
it validates each block into R0, every block reads invalid on the erased flash
(R0==0), the scan reaches the end having found NO valid block, and returns
MOV R0,#20 / RSB R0,R0,#0 = -20 = KErrCorrupt. StartupThread then
User::LeaveIfError -> User::Leave -> RThread::Kill (dies). So the firmware does
NOT auto-format a blank volume - a real N-Gage C: is PRE-FORMATTED at the
factory. Our erased (all-0xFF) C: is an invalid LFFS -> crash.

RECONCILIATION (I flip-flopped earlier; this is the evidence-backed answer):
the user's C: content IS needed to boot - not as files the startup reads, but
because C: must be a VALID FORMATTED LFFS volume. The Pocket core's "erased C:
boots" note does not hold for THIS firmware build (our firmware crashes on a
blank C:, proven by the scan-loop decode). The user's C: dump
(firmware/disk_dump/C) is a real phone's formatted C: contents.

FIX PATHS: (fast) a RAW C: flash/partition image (the actual flash dump) drops
straight into the cdrive_ overlay via an opt-in cdrive-image= and boots; (slow)
build an LFFS on-media image from the extracted file tree, which needs the
LFFS format (block header with LFFS_MAGIC 0x503B3B60 at word[1] per Pocket
drive.c, plus the log/free structures the scan validates - the per-block
validator is a helper not yet fully RE'd). Minimal empty-but-formatted LFFS is
also possible once the block header is pinned. Secondary hypothesis to keep:
mediaatt FORMATTABLE (0x04) in the drive caps medint reports - if unset, F32
would not auto-format; Pocket sets it.

Tooling ready: build/ngage-defs (IDT ordinal names), symtrace.py. NEXT: obtain
a raw C: image if one exists (instant), else RE the LFFS block header to build
a valid image from the dump.

## 2026-10-29 KErrCorrupt likely a C: flash geometry/size mismatch (update made with Claude)

The erased C: mount returns KErrCorrupt without attempting format (208 pre-
crash C: reads all 0xFFFFFFFF; cdrive_writes=0). On the working Pocket core
the same real LFFS formats an erased C: on first mount. Difference must be the
flash geometry/caps medint derives from our flash model. Mismatches found:
- SIZE: our cdrive overlay = 4 MiB (0x02400000-0x027fffff); THC live map shows
  real C: = 6 MiB (0x02400000-0x029fffff); device ID 0x257e implies an AM29x643
  = 64 Mbit = 8 MiB part. So our size is likely wrong, and medint's caps
  (iSize/iEraseBlockSize) may not match what the ROM-built LFFS expects.
- GEOMETRY: our model has 16 KiB boot sectors at each 2 MiB die top
  (cdrive_sector); Pocket uses uniform 64 KiB. Non-uniform geometry can break
  LFFS structural math -> corrupt.
Diagnostic in flight: resume mount-c760, window-trace 760-764.2M with the
IDT symbols to catch the TBusLocalDrive::Caps query and the exact size/erase/
mediaatt medint reports, then correct the C: flash model (size + uniform
geometry + formattable) so LFFS formats-on-mount instead of KErrCorrupt.

## 2026-10-29 REFRAME: boot does not hang - StartupThread CRASHES on C: mount KErrCorrupt (update made with Claude)

Symbolized the block with the user-supplied IDA IDTs (firmware/IDA IDTs 1st
Edition/*.idt, ordinal->name; converted to build/ngage-defs/*.def for romsyms).
Alignment VERIFIED against the independent exec table (euser ord630 =
User::Leave <-> exec 0x73 = User::Leave; ord627 LeaveIfError, 621 RThread::Kill,
1208/1209 WaitForAnyRequest all coherent). The 767.8M "idle" is NOT a wait:
the sequence is elocal LFFS mount -> returns KErrCorrupt (-20, raw value, IDT-
independent) -> User::LeaveIfError -> User::Leave -> CCleanup::PopAndDestroyAll
-> RThread::Kill. StartupThread LEAVED on the corrupt C: and KILLED ITSELF; the
later WaitForAnyRequest loop is just the null/idle thread. So the thread that
would launch ESTART is DEAD - every earlier "waiting on X" analysis was the
aftermath, not the cause.

Root cause: our empty/erased C: (all 0xFF) makes the real LFFS mount return
KErrCorrupt (origin in ELocal LFFS code ~0x5038fbd4, elocal!<code>+0x7840).
cdrive_writes=0/cdrive_erases=0 => the mount scan rejected the volume as
corrupt BEFORE formatting. On the working Pocket core (drive.c) an erased C:
is fine because "LFFS formats on the first mount". Ours returns corrupt
instead of formatting. FIX options: (a) make format-on-mount work (find why
the erased-flash mount scan concludes corrupt - likely flash geometry/CFI or
a read value our model gets wrong - and fix the C: flash model); (b) pre-fill
C: with a minimal VALID formatted LFFS image (LFFS_MAGIC 0x503B3B60 per
Pocket + minimal log), far smaller than the 1.7MB file tree. The user's C:
file tree is NOT needed to boot (Pocket proves erased boots) but a VALID
empty LFFS is. NEXT: read Pocket drive.c format handling + find the exact
corrupt check.

Tooling: build/ngage-defs (IDT-derived ordinal names), scratch/tools/
symtrace.py --defs build/ngage-defs names any trace line.

## 2026-10-29 SYMBOLIZATION unblock: block = StartupThread User::WaitForRequest; SDK defs incoming (update made with Claude)

The Pocket core's tools/ngvm/romsyms.py symbolizes OUR SYM.ROM to
library!ordinal(+off) directly from the ROM export tables (works without the
SDK). New helper scratch/tools/symtrace.py annotates any sim trace with it.
Key corrections this gave:
- efile and elocal are the SAME thread (ELOCAL.FSY runs in the file-server
  process), so the elocal WaitForAnyRequest IS StartupThread blocking, not a
  separate idle FS thread. Earlier "it's a normal media-change idle" was the
  wrong read.
- The block is euser!ord621 = User::WaitForRequest(TRequestStatus&) (reads
  [R0]=status, waits via exec 0x4d) - StartupThread waits on ONE SPECIFIC
  async request from its LFFS-mount/startup path that never completes.
- StartupThread = efile!ord3 (entry 0x503d5290), a startup state machine of
  panic-guarded steps (efile!ord4 helpers). Last ops before the block:
  efile!ord20+0x744 (media-readiness 0x503cfa30), efile!ord16, efile!ord4,
  then elocal -> User::WaitForRequest.

USER is getting a Series 60 1st Ed SDK. romsyms needs its per-library ordinal
.def files (euser.def/efile.def/elocal.def/... lines "Name @ ord NONAME") at
NGAGE_DEFS. With them every trace line gets a real name and the exact pending
request/completer is pinned in minutes. Ordinals to resolve first: euser 621
(block), 627/630 (request issue around the 767799317 exec), 863/823/360/121/
178; efile ord3/4/16/20; elocal ord1. If the SDK ships only .lib import
libraries, extract ordinal->name from those (petran/def dump) into NGAGE_DEFS.

## 2026-10-29 ROOT CAUSE of the user-side block: missing ISI/Phonet baseband responder (update made with Claude)

Traced StartupThread's full exec set across the mount (reqtrace 764-767.82M):
WaitForAnyRequest(162), heap, trap, locked inc/dec, plus RFs::Connect
(RSessionBase::Attach 0xbf to the file server - normal), TFindLogicalChannel
(0xb7), UserHal::DriveInfo (0x83), CServer/RServer (0x2e). No flash/MMC/timer
wait, no C: content dependency. Then the Pocket core docs/hardware.md S8 named
it exactly: the firmware boot (Starter) opens channels to NOSDRIVER (the
baseband) and sends ISI/Phonet messages - energy management (resource 0x17:
charger msg 0x08->0x09 subblock 0x13 "not connected", battery 0x0A->0x0B
subblock 0x16 "full 7 bars"), phone identity/IMEI (0x1B), SIM/IMSI (0x09) -
and WAITS for replies. The Pocket core implements NOSDRIVER as an ISI/Phonet
ROUTER (sw/kernel/chan.c) answering these; the fallback for everything else is
"open and never complete, or complete with KErrNotSupported." Our synthetic
NOS stub provides only the entry code and does NOT route ISI, so StartupThread's
CActiveScheduler waits forever for a baseband reply. "Without the charger's
reply, Xanadu Next exits at start" - the charger/battery replies are needed
early.

So the real frontier is a minimal ISI/Phonet baseband responder (like Pocket's
chan.c) at our LLE hardware level: find how the firmware's NOSDRIVER exchanges
ISI messages with the baseband (shared memory + interrupt), and answer the
energy-management set (+ KErrNotSupported / never-complete for the rest). The
real THC NOS image is the authentic alternative but needs its import table
fixed; the minimal responder is the faster path and matches what the working
Pocket core does. NEXT: read chan.c's ISI router for the exact message/subblock
layouts and the hardware mailbox, then model the responder.

## 2026-10-29 COURSE CORRECTION: C: content NOT needed; block is medint async mount completion (update made with Claude)

The user supplied the real C: as a FILE TREE (firmware/disk_dump/C, 120 files,
1.7MB; also Z: 1566 files, D: empty) - no raw flash image. Before building an
LFFS on-media image (a big sub-project), the Pocket core (~/develop/n-gage
sw/kernel/drive.c) settled it: on that working HLE core C: starts ERASED (0xFF)
and "LFFS formats on the first mount" - it boots to the N-Gage with an EMPTY
C: and never populates it (LFFS_MAGIC 0x503B3B60 is written only when there's
a save to restore). So missing C: content is NOT the blocker; our empty C: is
authentic. Keep the disk_dump for later (game saves in C:\System\Apps), but
do NOT build an LFFS image to boot.

Real block: drive.c's drive_executor shows the local-media executor calls -
sub 0x38 connect, sub 0x3B MOUNT (completes a TRequestStatus via
request_complete), sub 0x3E MediaChangeNotify (stays pending forever by
design; not the block). On our LLE sim the REAL medint.pdd runs the mount and
must complete that TRequestStatus via a flash-hardware DFC/interrupt we don't
generate - so StartupThread's CActiveScheduler waits on a mount/media
TRequestStatus that never completes. This is a "model the completion event"
problem (like the UEM IRQ that unblocked epbus), NOT a content problem.

NEXT: find medint's async completion path - what flash-controller event
completes the mount request (the program-ISR unit 0x60 / IRQ source 3 is one
candidate; a flash read/ready DFC is another). Trace medint during the mount
(the medint 0x50386628 loop seen in smtrace) to see which status register it
polls / which interrupt it expects, then fire that completion and resume.

## 2026-10-29 StartupThread is a CActiveScheduler waiting on an async request; C: content is the next lever (update made with Claude)

Decoded StartupThread's final sequence before the block (idle2 trace): it
constructs active objects (0x50389xxx/0x50394xxx), dispatches through a global
callback (0x503957ac: LDR R3,[global]; BX R3), and enters EUser 0x503b7fb8 ->
exec 0x4d WaitForAnyRequest — i.e. a CActiveScheduler::Start wait loop. The
busy stretch before it (ELocal 0x5038b714 <-> EUser 0x503a6abc, ~675 iters)
is a Mem::Fill zeroing a large buffer (legit work), NOT a hardware poll. No C:
write (cdrive_writes=0), no flash/MMC hardware wait. So the F32 startup's
active scheduler is blocked waiting for an async request completion that never
arrives; EStart is not launched because the startup hasn't passed this wait.

Most promising next experiment: populate C: with real content. On N-Gage the
file-server startup reads system startup data from C:; our C: is an empty
(all-0xFF) LFFS, so first-boot/startup may wait on resources that a populated
C: provides. User offered the real C: content twice. Plan: add an opt-in
`cdrive-image=<raw LFFS partition image>` that pre-fills the cdrive_ overlay
(digest-neutral; C: is not in the boot digest), then resume from mount-c760
and see whether the startup's active scheduler completes and launches EStart.
If a populated C: does not unblock it, fall back to deeper RE of the pending
request (identify the active object and its async call).

## 2026-10-29 MILESTONE: boot reaches EKA1 user-side startup; StartupThread blocked mid-state-machine (update made with Claude)

Deep checkpoint+trace analysis of the 767.8M re-idle (tools: inspect_checkpoint
on mount-c768, idle-window trace idle2 from mount-c760). The boot is NOT stuck
on a device register — it reached the user-side startup:
- F32 (file server) is fully up: live DThread objects named Main, Loader,
  Supervisor, StartupThread, Startup exist in the kernel heap (found by RAM
  name-scan; StartupThread DThread at PA 0xafdf764, vtable 0x503a20e0, owns an
  RHeap). C: (LFFS) mounted EMPTY — ELocal did a full linear mount-scan of the
  erased volume (0x02400000+, all 0xFFFFFFFF, to ~offset 0xf0000) and finished.
- EStart was NEVER launched as a process ("EStart" in RAM is only the ROM
  file-table directory entry at 0xa0886b4 / 0x50317466, not a DProcess).
- The blocked actor is StartupThread: EFile.exe creates it (name literal
  0x503dc664, ENTRY 0x503d5290) and it runs a multi-step startup state machine
  (sequence of panic-guarded init calls, panic fn 0x503d8c14, codes 7/8/9/e/f).
  It is blocked in WaitForAnyRequest (exec 0x4d, confirmed via SWI 0xef00004d /
  exec-table 0x503ac664) after an ELocal/C: operation; an EFile op at 0x503cfa10
  returned KErrNotReady (-18, [req+0x18] null path) just before the block
  (767800239). All idle-window execs are benign (WaitForAnyRequest, heap, trap,
  locked inc/dec) — no device/semaphore wait pending.

Reframed problem: no longer device-register modeling. StartupThread's state
machine is waiting for an async request to complete that never does. Candidates:
(a) a driver request needing an interrupt/DFC completion we don't fire (like the
UEM IRQ that unblocked epbus one layer up); (b) a drive-readiness retry (the
KErrNotReady). NEXT: trace StartupThread's state machine (0x503d5290+) from
mount-c760 across 766.5M-767.82M to pinpoint the exact blocking request and
which drive/driver it targets; then model that completion. Fresh pinned
snapshots mount-c760/mount-c768 are the iteration base.

## 2026-10-29 fresh correct-path snapshot mount-c768; F32 idle wait is next (update made with Claude)

Consolidation after a long advancing session. Fresh pinned snapshot
mount-c768 written from reset on the current UEM path (cycle 768M, after F32's
C: filesystem batch, just before the re-idle); validated by the inspector
(L1 table + anchor resolve). Stale pre-UEM checkpoints c1300/c1307900000
RETIRED (wrong shorter-epbus path); pinned set is now mount-c760 + mount-c768
(see build/sim/checkpoints/README.txt). run-resume.py auto-latest now globs
mount-c*. build/sim trimmed 1.4G->88M (traces regenerable; results/provenance
and checkpoints kept).

The 767.8M re-idle: F32 is Thumb-compiled; the last executed frames are EFile
media-readiness logic (0x503cfa10: [req+0x18] null -> returns -18 KErrNotReady)
and ELocal. System reached the 1.32e9 budget with no crash and no wake for
550M cycles => event-blocked on a non-timer signal, same pattern that the UEM
IRQ resolved one layer up. EStart (first user process, 0x503ee860) has NOT
executed yet in any trace.

NEXT (precise): from mount-c768, Thumb-RE the blocked F32 thread's wait —
whether it is (a) a driver waiting on another hardware completion to model
(most likely, given the pattern), or (b) F32 legitimately idle awaiting an
EStart request, meaning the block is upstream in loader/EStart creation.
Decide by checking, from the c768 RAM image, whether a loader/EStart thread
exists and what it waits on (inspector + the DThread vtable), then model the
event or unblock EStart creation. Iterate via run-resume (minutes/attempt).

## 2026-10-29 epbus clock-block + C: word reads: F32 exercises C: filesystem, re-idles ~767.8M (update made with Claude)

Two model additions cleared the epbus/LFFS frontiers in single rebuilds:
(1) opt-in `epbus-clkblk` serves 0x0c120600..0x0c1206ff as RW word latches
(epbus swept 0x604/0x610/0x614=0x280/0x618/0x624 during peripheral init);
(2) C: flash array now serves word reads (select 0xf -> two cells, array-read
mode only; commands/status stay halfword) — LFFS reads its mounted volume as
words. Result: boot advanced to the 1.32e9 budget with NO crash; medint
(783), EFile (1503), ELocal (248) transitions show F32 did a full batch of C:
filesystem work (last C: read 0x024f003c at 767.1M), then the boot thread
re-idled at ~767.8M (last real frames: EFile 0x503cfa30/0x503d91d6, ELocal
0x5038925c, then pure tick to 1.32e9). Same event-blocked pattern as before,
now one mount deeper. Checkpoint v4 serializes the clock block.

NEXT: write a fresh correct-path checkpoint near 767.8M (the stale pre-UEM
c1300/c1307900000 are retired) and run inspect_checkpoint on it to name the
newly-blocked thread and its wait object, then model that event. Iterate via
run-resume from the fresh checkpoint.

## 2026-10-29 UEM IRQ unlocked more epbus init; checkpoints re-based on mount-c760 (update made with Claude)

Full-boot module-trace from reset shows the span is dominated by healthy
EUser/ekern/EFile/EFSrv file-server work (F32 running), with lcd.ldd and
nosstarter now appearing (1 and 4 transitions) — forward progress, not a
stall. The from-reset run stops at a NEW frontier: epbus WRITE 0x280 to
0x0c120614 at 764,607,560 (same 0x1206xx block as 0x604/0x618/0x624; added
as a probe). KEY: this is not a regression though 764.6M < the old 1.31e9
frontier — the older runs reached 1.31e9 by a SHORTER epbus path because the
first power instance never completed; now that uem-irq-source1 delivers that
completion, epbus proceeds further and needs 0x614. Consequence: the c1300
and c1307900000 checkpoints are from the PRE-UEM path and are now stale; the
freshly written pinned mount-c760 (from reset with the current binary) is the
canonical current-path snapshot. probe-register args do NOT enter the
checkpoint signature, so adding probes keeps mount-c760 resumable.
In flight: run-modtrace resumes mount-c760 with 0x614 probed to get the real
current-path timeline past this point.

## 2026-10-29 mount window traced: medmmc is a clean no-card no-op; module-trace tool (update made with Claude)

run-mount-window.py (from reset, win-trace 761.0M-761.45M) shows the span
after the C: mount: EFile/EFSrv work steadily, medmmc runs ONCE at
761.403M-761.411M purely in software (PDD factory create via ordinal lookup
0x50330960 -> entry 0x503feb44, 0x20-byte alloc, constructor 0x503fd858;
ZERO hardware accesses), then F32 continues (EFile/EFSrv active to the
window edge at 761.45M). USER INPUT (2026-10-29): the MMC card is optional
on real hardware — boot without a card is authentic; full MMC/D: support
is a later feature, not a logo-path requirement. So the no-card path is
correct and D: is NOT the blocker; the park happens somewhere in the
untraced 761.45M-1.31e9 span.

New instrument for exactly that: `module-trace` option in main.cpp logs one
line per PC transition between ROM binaries (tiny output over any span);
run-modtrace.py resumes the pinned mount-c760 snapshot and produces the
complete module timeline 760M-1.32e9. Pinned snapshot mount-c760.{cpu,host}
written by run-c760.py (excluded from rolling prune); run-resume-760.py
replays the mount span with optional win-trace in ~1 minute.

## 2026-10-29 checkpoint inspector built: blocked thread is the F32 mount in medmmc (update made with Claude)

New tool `scratch/tools/inspect_checkpoint.py` (offline, no simulation):
parses a .host checkpoint, locates the 16 MB SDRAM image (verified by finding
the kernel L1 page table via the 0x58000000->0x0c000000 I/O section
signature; L1 at PA 0xa074000 in c1307900000), walks sections + coarse L2 so
kernel VAs resolve, and supports --dump VA hexdumps plus vtable-clustered
object scans and stack discovery (RAM pages dense with ROM return
addresses). Findings on checkpoint c1307900000: kernel object names are not
ASCII-in-RAM on this build (only string: "INFO Server"), so identification
goes by stacks/vtables; 16 stack-like pages found and module-mapped.

CORRECTION (same day): the code-pointer-dense pages are the KERNEL HEAP,
not stacks — the 'return addresses' at 0x503fefxx/0x503fd854 disassemble as
medmmc import-table/vtable DATA. So the right reading of PA 0xafe4000 is
that medint/medmmc/ramdrive/ELocal driver OBJECTS exist (media drivers
instantiated, including medmmc's), and of 0xafe2000 that the three epbus
instance objects (vtables 0x50339c08/0x50339d5c/...) live at
0x804067xx/0x804068xx/0x804069xx. Which thread is blocked on what is NOT
yet proven; stack discovery needs SVC-frame signatures, not raw density.
In flight: from-reset run-mount-window.py (win-trace 761.0M-761.45M, the
span right after the C: mount where the mount thread last ran) to catch the
park in the instruction stream directly.

NEXT: RE medmmc's wait entry (around 0x503fef88/0x503fd854) to identify the
exact completion it needs (second UEM interrupt client? card-detect GPIO?
MMC controller registers — none modeled yet at any address), then model the
minimal "no card present" or "card ready" answer so the mount completes or
fails cleanly and boot proceeds to EStart. Iterate with run-resume from
c1307900000.

## 2026-10-29 unit-1 = ekeyb scan timer; system idles event-blocked; next: thread-state inspector (update made with Claude)

The unit-1 run (boot-v15-unit1, 3e9 budget, rolling checkpoint written at
1.3079e9 — checkpoints now c1300 + c1307900000) resolved the chain: timer
unit 1 is ekeyb's KEYPAD SCAN timer (5,561 expiries at ~3 ms cadence; each
scan: read 0x15020c=0x9090 / 0x150208-upper=0 (no keys), drive rows 0x1f/0x3f
via 0x150400-block, touch 0x14f018/0x120c14, re-arm). The post-wake activity
previously attributed to epbus was ekeyb powering up (keypad page writes
0x150100=0xc/0xee). The scanner and tick run healthily for 16+ simulated
seconds; the only ms-timer live is the scan period (diag2 window: countdown
3->0). No EStart/ELocal/medmmc code observed in any captured window; no new
debug59 output after "TRtcQueue::Add: 2". Conclusion: the boot-progress
thread is EVENT-blocked (not timed) on a signal the board never delivers,
and guess-and-rerun has hit diminishing returns.

NEXT (planned): build an offline EKA1 thread-state inspector that parses the
checkpoint .host RAM image (16 MB SDRAM at offset per save_host layout in
scratch/boot-v15-nosprobe/main.cpp) and walks the kernel thread list to name
each thread and its wait object (anchors from disassembly around the known
scheduler globals 0x80006xxx; ~/develop/n-gage docs/eka1_exec.md and
tools/ngvm symbol tooling as reference). That converts "who is blocked on
what" from guesswork into a lookup, using checkpoints as free RAM dumps.

## 2026-10-29 UEM IRQ WOKE EPBUS; next: unit-1 settle timer; rolling checkpoints (update made with Claude)

The uem-irq-source1 hypothesis run (boot-v15-uemirq, resumed from c1300)
WORKED: the injected source-1 IRQ after the UEM 0x30=0x40 write was dispatched
(0x114 read 2 at 1,307,939,636), the cbus ISR ran and the chain continued —
UEM power-status 0x13f read, new GPIO-block writes 0x0c150100=0xc/0xee
(accepted by the keypad-GPIO latch model), UEM 0x35/0x36 reads, ack 0x10c=2.
epbus's wait completed. The thread then programs TIMER UNIT 1 as a settle
delay: repeated control 0x0a24 stop/start, compare 0x0a30=0x7fffffff parked,
status 0x0a28 ack, ICU 0x108=2 re-enable, compare rewritten 0x6590 — i.e.
ICU source 1 is (also) unit 1's expiry line; the UEM-write trigger and the
unit-1 expiry share one pending bit in the model. Unit-1 model added (counts
CPU cycles to the compare latch; scale unverified; board tests cover it).

Infrastructure (user policy, saved to memory): default budgets are now 3e9
cycles everywhere (don't kill an unblocked run); run-resume.py auto-restores
from the LATEST build/sim/checkpoints/boot-v15-c*.{cpu,host}, takes
[budget] [name] [ckpt_at] and with ckpt_at writes a rolling checkpoint near
the frontier, then prunes to the newest 2 checkpoints. Board checkpoint
format v3 (0x4e470003) appends source-1/unit-1 state; v2 files still load
(fields default). main.cpp now allows restore+checkpoint in one run.
In flight: resume with unit-1 live, rolling checkpoint at 1.3079e9
(boot-v15-unit1, budget 3e9).

## 2026-10-29 epbus wait decoded: UEM interrupt client; source-1 model in test (update made with Claude)

RE of the park point: epbus does NOT wait on a GPIO edge — it registers with
cbus.dll's UEM-interrupt dispatcher (bind call 0x503f5ba8/0x503f5bf4 →
cbus.dll 0x503820c4 with r1=type 1, r2=client id 0xb, r3=bit 8). The client
table at 0x50383574 (20-byte rows) maps id 0xb → {type 1, group 2, bit 3};
ids 0x9..0x11 are the group-2 UEM interrupt clients with consecutive bits.
Around the bind, epbus writes 8 to 0x0c120c0c/0x0c120c10 and halfword 1 to
GPIO bytes 0x150206/0x150208 (pin arming for both instances, pools
0x503f5bc8-0x503f5c1c). Driver-init ICU enable 0x0c120108=2 (source 1) at
729.6M is the candidate UEM IRQ line; the tick-queue insert at 0x50343374
confirmed the thread sleeps on an event, not a timeout.

Model (opt-in `uem-irq-source1`, run scripts updated, assumption recorded):
kernel-phase CBUS write to UEM reg 0x30 (the epbus power-up tail 0x2b=0x81,
0x30=0x40) sets ICU source 1 pending; 0x0c120114 reads 2; bank0 +0x0c bit-1
write acks. Pending state is transient (not checkpoint state — c1300 precedes
any UEM write, so resumes are safe). Plan: resume-iterate (boot-v15-uemirq);
when the cbus ISR runs it will READ the UEM interrupt-status register over
CBUS — whichever register it reads, supply bit 3 (client 0xb) there next
iteration. If the ISR instead reads an unexpected ICU current value, source 1
is wrong — check bank2 candidates (the 0x12018c=0x800 clear at 729.6M).

C: drive status (user asked): the kernel never formatted or wrote C: — LFFS
mounted the erased volume read-only (cdrive_writes=0, cdrive_erases=0 in
every run; the unit-0x60 program ISR has never fired). The user HAS a real C:
content dump; when boot reaches file-server reads from C:, check its format
(raw LFFS partition image vs file tree) and add an opt-in `cdrive-image=`
overlay (digest-neutral; C: is not hashed by the boot digest).

## 2026-10-29 checkpoint/resume proven; frontier: epbus power-up completion event (update made with Claude)

Checkpoint at cycle 1.3e9 written (build/sim/checkpoints/boot-v15-c1300.{cpu
53 KB, host 25 MB}) by run-checkpoint.py, which from reset also advanced the
frontier past 0x0c120624 to 0x0c120618 (both now probe registers; epbus walks
its 0x0c1206xx block: 0x604 W, 0x624 R, 0x618 R). load_state now MERGES probe
values so a resume can add newly probed registers (the standard iteration).
First resume runs validated: run-resume.py restores at 1.3e9 and a windowed
run-diag.py (restore + 15k-cycle win-trace) answered a who-writes-what
question in ~2 minutes end-to-end. Resume runs cannot capture screens (LCD
init precedes the checkpoint; known cosmetic limitation).

Current frontier (from the diag window, boot-v15-diag): after 0x618 the chain
continues — CBUS writes UEM 0x2b=0x81 then 0x30=0x40 (cbus.dll 0x503833a4 on
behalf of epbus), GPIO-block write 0x0c150208=1 just before (likely arming a
power-good pin interrupt), probe 0x0c120c10=8 — then the epbus thread inserts
itself into a wait queue (TDblQue insert 0x503bb818 via EUser 0x503bbb5c; the
PSU vtable path at 0x503fbf68 was NOT taken) and the scheduler parks the
system: 4.6 simulated seconds of pure tick+idle to the 2.5e9 budget, no
timeout path fired, no new TRtcQueue entries. Reading: DPBusSocket-style
power-up wait whose completion on hardware is an interrupt (UEM power-good
or the GPIO pin enabled via 0x150208). NEXT: RE who signals that wait object
(find the TDblQue remove/signal call sites in epbus and the ISR behind them,
starting from the 0x150208 enable), then model the completion event behind an
opt-in flag and iterate via run-resume (minutes per attempt).

## 2026-10-29 1e9 was the wall: 2.5e9 run reaches 1.31e9; checkpoint/resume v2 (update made with Claude)

The 2.5e9-cycle run (boot-v15-long) CONFIRMED the 2-second-timer analysis: the
sleeping thread woke past the old budget and boot continued to 1,307,930,588
cycles (+546M past every previous run; 1,433 ticks = 5.6 s simulated). All
earlier "idle forever" results at exactly 1e9 were budget artifacts. New
frontier: epbus (0x503f41b8 path) writes 0x0c120604=0 then READS 0x0c120624 —
added probe-register=0x0c120624:0:15 (reset 0 hypothesis) to all run scripts.

Simulation economics (user asked): Verilator --threads is 11x SLOWER here (60M
cycles: 55 s single vs 626 s with 6 threads) — never thread this model. The
fix is checkpoint/resume: board checkpoint format v2 (0x4e470002) now
serializes ALL device-model state (probe regs, periodic timer, ICU banks +
Interrupt-API masks, timer units + unit60, keypad, block14d, C: overlay + FSM,
power model, stub/image counters, debug59 buffer) and the post-UIF guard is
gone; roundtrip covered in the board tests (25 sections). New scripts:
`run-checkpoint.py` = full 2.5e9 run writing
build/sim/checkpoints/boot-v15-c1300.{cpu,host} at cycle 1.3e9 (in flight);
`run-resume.py [budget] [name]` resumes there, so frontier iterations cost
minutes instead of ~40 (the ~30-sims/day ceiling is gone). Resumed results
carry checkpoint_restored=true and never count as from-reset evidence.

## 2026-10-29 stub pread zero-length bug was the real 0x47f0 frontier; NOS scout ran real code (update made with Claude)

CORRECTION to the previous two entries: the 0x0c0047f0/0x0c0047f4 scratch
writes are the kernel EXCEPTION path, not a Variant table — the strlen loop
before them walks the string "Exception" in ABT mode, and 0x50324240 is the
fault-dump/reboot handoff ({3 words to scratch 0x47f0/f4/f8 from the
superpage block at VA 0x40000400, halfword 0x1a to 0x0c00428e, 0x200 to SYSC
0x0c120004, doorbell halfword 4 to 0x0c150000, then a parked self-branch}).
Root cause found in the trace: a kernel query (0x50331a84) called the
synthetic stub's pread (0x5149d078) with byte length 0 and a non-writable r3;
the stub's "default to 4 bytes" path STRB'd into it and data-aborted at
0x5149d09c. Fixed in scratch/nos-stub-blob/nos_stub.S: zero length now writes
nothing (iface_vt pinned at VA 0x5149d0c0 with .org; blob regenerated, still
648 bytes; toolchain arm-none-eabi on host). The scratch-window growth to
0xac stays (harmless, covers the real fault path if it ever runs).

Follow-up: the first rerun with the edited blob FAILED the boot digest (halt
0x50003290) — SYM.ROM embeds the blob and power-model words at 0x9d000/0x9e000
and the derived digest hashes them, so overlay edits change digest input.
Fixed like the nos-image window: both synthetic windows now gate on the kernel
tick (periodic_period_); the digest hashes the ROM-embedded (old) bytes, the
kernel phase gets the edited blob. Any future blob edit stays digest-neutral.

Gated/fixed run result: TIMEOUT at 1e9 with a clean system — no crash, the
pread abort is gone. The windowed diagnostic (run-park-window.py, trace
761.29M-761.6M, output boot-v15-park-window) decoded the "idle": a kernel
boot waiter (0x50331a50) loops forever — each iteration calls the Variant
interface getter pread(iface, id=13, dest=NULL, len=0) and then tests a
kernel global ([pool 0x50331bb4] = 0x806028fc, dereferenced) against zero,
yielding via 0x50323c74 and retrying. The kernel is waiting for interface
id 13 to be REGISTERED (our stub registers only #3 via exec slot +0x128 and
#6 via +0xfc). Stub updated: nos_init now also registers iface 13 through
exec slot +0xfc before the #3 registration; ret0/pread moved after the
pinned vtable to fit (new VAs ret0 0x5149d184, pread 0x5149d18c; iface_vt
still 0x5149d0c0, iface 0x5149d180, blob still 648 bytes; digest-neutral via
the kernel-tick gate). Hypothesis: the poll's global is the iface-13 table
slot the registration exec writes.

REFRAME after the iface-13 run (still timeout at 1e9): 0x50331a50 is the
kernel IDLE THREAD, not a boot waiter — it polls pread(13) every iteration
and the global only selects the timed-idle branch (fn ptr [0x80006c1c],
time-adjust 0x503459e8, tick accumulator [0x80000488]). The iface-13
registration is kept (it matches what the idle loop expects to exist). The
REAL last actor: a user-side thread does 64-bit time math (EUser 0x503a3ad4),
blocks, and the scheduler (0x50327f48) finds an empty ready list. Combined
with the last debug line "TRtcQueue::Add: 2" this reads as a 2-SECOND timer
sleep. Arithmetic: tick reload 0x632ea = 406,250 cycles, 256 ticks/s (CPU
~104 MHz), so +2 s with up-to-1 s second-boundary slack lands at ~0.97-1.07e9
cycles — AT THE EDGE of the 1e9 budget. Decisive test in flight: run-long.py
(2.5e9 cycles, output boot-v15-long). If the thread wakes, the system was
never stuck and long budgets are the new normal for late boot.

Simulation speed (user asked): Verilator --threads 6 benchmarked 11x SLOWER
than single-threaded on this design (60M cycles: 55 s vs 626 s) — do not use
model threading; the design is too small to partition. Docker VM already has
all 14 host CPUs. Practical speedups: parallel independent runs (one core
each), and checkpoint restores for late-boot iteration (main.cpp already
supports checkpoint_at/restore; mark results checkpoint_restored=true, keep
authentic-path claims to full runs).

NOS scout result: with the kernel-tick gate the digest PASSED and nosstarter
EXECUTED the real THC NOS entry at 729,412,537 (B 0x514a6b48, stack setup,
R0=0x40 call). It died at an import thunk (0x516c7010): the pool slot at
0x516c7018 reads 0 — the THC gsm image's import table is UNFIXED (zero
slots), so the real module needs an E32 import fixup pass against the
same-build ROM's export tables before it can run further. Parked: the
~/develop/n-gage tools/ngvm ROM/symbol tools are the suggested starting
point. The synthetic-stub path remains the mainline toward the logo.

## 2026-10-29 digest/nosstarter timing corrected; scratch window grown (update made with Claude)

Second NOS scout halted identically — the one-shot gate was wrong because the
boot MD5 runs AFTER the one-shot: the bus trace's code/data column settles the
real timeline (compact trace does not log flash reads, which misled the first
diagnosis). Measured in the stub run: digest sweeps PA 0x9d000+ as DATA reads
at ~139.26M-139.4M; the kernel tick arms at ~452M; nosstarter EXECUTES the
entry (CODE fetches at 0x9d280/0x9d284) at 729,412,514. The image-run digest
computes until ~683.49M then enters the 0x50003290 halt (BNE at 0x500032e8).
nos-image gate changed to periodic_period_ != 0 (kernel tick armed).

C: chain advanced to 761,316,873 — nosstarter ran, and the kernel Variant
registration (0x50324248, pool 0x5032429c) stores the interface pointer
0x5149d09c at scratch 0x0c0047f0, one word past the modeled window: scratch
grown 0x9c -> 0xac bytes (0x0c004748..0x0c0047f3; gap bytes still stop on
unwritten reads; old board-checkpoint binary layout changed, prior checkpoints
already deleted in cleanup). Board tests pass (scratch end boundary moved to
0x47f4). Both runs relaunched.

## 2026-10-29 NOS scout diagnosed (digest reads raw bytes); epbus 0x120604 probe (update made with Claude)

First NOS-image scout halted at 0x50003290 (masked-IRQ dead loop) at ~137.85M
cycles: the 695,376 image reads were the boot-time MD5 digest sweeping PA
0x9d280+ — serving the live-dump bytes there changed the digest input and
validation halted right after the boot one-shot IRQ handler (UEM 0x35/0x36
reads + 0x150100=0x8000). This is the docs/discord.md descrambler warning in
board form: at digest time the raw window must present RAW flash bytes. Fix:
the nos-image window now activates only after the boot one-shot has fired
(timer_irq_cycle_ set, ~137.849M) — measured ordering: digest reads end
≤137.85M, nosstarter's entry call at 139.26M (synthetic-stub run evidence).
Descrambler-enable timing is a hypothesis.

C: chain meanwhile advanced to 761,291,676: epbus (delay loop 0x503f51b0,
after clock writes 0x120014=0x580/0x120018=0x200) writes 0x40 to NEW register
0x0c120604 — added as probe-register=0x0c120604:0:15 to both run scripts (no
code change). Board tests 24 sections pass; both runs relaunched.

## 2026-10-29 C: mounts without format; frontier moved to epbus; NOS scout queued (update made with Claude)

unit60 iteration 2 (control-register arming + ICU 0x10c acknowledge): the
first iteration's interrupt storm (738k dispatcher acks of source 3; "any
nonzero unit write arms" fired during medint setup while the unit was stopped)
is fixed — arming now follows a nonzero +0x04 control write (medint's setup
uses the kernel stop-and-settle helper 0x50324960: +0x04=0 five times,
compare 0x186 at +0x18, counter reset +0x10=0) and ICU 0x10c bit-3 writes
acknowledge pending. Result: medint init completes WITHOUT the program ISR
(unit60_irqs=0, cdrive 0 programs/0 erases — LFFS mounted the erased volume
as-is; formatting/writes will engage the ISR later), boot advanced to
761,278,878 (+218k past the pre-C: frontier), kernel debug prints
"TRtcQueue::Add: 2". New stop: epbus.dll init (0x503f5bbc) writing halfword 1
to GPIO byte 0x0c150206 — accepted into the gpio206-extra-write set (ekeyb
0x0006, epbus 0x0001). Board tests 24 sections pass.

In flight: (1) rerun of the authentic C: chain with the epbus value accepted;
(2) first NOS scout run (`run-nos-image.py`, output boot-v15-nos-image) with
the REAL THC NOS/GSM image served at PA 0x9d280+ via the new opt-in
`nos-image=` option replacing the synthetic stub (mutually exclusive;
writes into the window stop the run). Expect the scout to stop at the first
baseband/DSP access — that address is the deliverable.

## 2026-10-29 THC real-device dump verifies sim addresses; real NOS image recovered (update made with Claude)

User-supplied `firmware/THC N-Gage ROM Dump/` (see docs/references.md for the
full inventory) — same firmware build as our reconstruction (binaries byte-
identical from 0x317000). Verified against the live phone's page table: I/O
0x58000000->0x0c000000, debug sink 0x59000000->0x0de00000, raw CS0 window
0x51400000->0x0 (so the NOS entry PA 0x9d280 assumption holds), C: internal
flash 0x59200000..0x597fffff->0x02400000..0x029fffff — NOTE 6 MiB mapped
(cached+uncached aliases at 0x598xxxxx), vs the 4 MiB cdrive-flash model; if
LFFS walks past 0x027fffff the model must grow. Real header metadata recovered
(iTime 0x56F2F400 at 0x84, iCheckSum 0x4B0A78B0 at 0xA8) for two synthesized
fields; THC's ROM view must NOT be reused as digest-time MD5 input (+5 MiB
post-boot remap, per docs/discord.md). The gsmstuff dump is a 0x60-byte
TRomImageHeader copy + the REAL NOS/GSM module payload for PA 0x9d280+
(entry B-instruction at PA 0x9d284 confirmed); extracted to
`build/firmware/thc/nos-image.bin` (0x279680 bytes, sha256 72787f4aed7c48e6…).
Planned opt-in `nos-image=<path>` board option replacing the synthetic
nos-entry-stub for an authentic-NOS scouting run (edit deferred until the
in-flight unit60 rerun lands — run-stub.py hash-checks its sources).

## 2026-10-29 ICU mask banks + unit-0x60 IRQ-3 model implemented, run in flight (update made with Claude)

Kernel disassembly resolved the 0x0c1201cc blocker: InterruptEnable
(0x503248f0) / InterruptDisable (0x503248a4) are a three-bank Interrupt API
mask file — banks at 0x0c1201c0/0x200/0x240 for sources 0-31/32-63/64-95,
+0x0c enable-set, +0x08 enable-clear (pools 0x1201cc/0x12020c/0x12024c and
0x1201c8/0x120208/0x120248). The blocked write was InterruptEnable(3) = 1<<3
→ 0x1cc, and the known early 0x1c8=0x08000000 exact sink re-reads as
InterruptDisable(27), not a FIQ enable (prior note revised). medint's setup
(0x503872dc..): enable source 3, exec(unit 0x60, 0x186) (reload hypothesis),
two zero writes, then unit reg +0xc=0 via kernel helper 0x503249a8 (unit base
= 0x0c120a00 + unit id; the I/O write primitive 0x503245bc stores via VA
0x58000000 + offset). Import stubs resolve through a load-time table, so the
remaining register roles are left to dynamic discovery.

Model added in `scratch/boot-v15-nosprobe` (opt-in `timer-unit60-irq3`): the
six mask registers latch and read back; a nonzero unit-0x60 (0x0c120a60..7f)
register write while mask bank0 bit3 is set raises IRQ source 3 after an
ASSUMED fixed 20000-cycle delay; ICU current 0x0c120114 then reads 4
(source+1); any unit-0x60 write acknowledges; unit status +0x08 reads 1 while
pending. Delay and start/ack register roles are hypotheses, not silicon.
Board tests extended (all 23 sections pass); full from-reset run with the new
flag is in flight. Expected outcomes: medint's program ISR runs and LFFS
format proceeds (next frontier appears), or the ISR's real ack/status
accesses stop the run and refine the hypothesis.

## 2026-10-29 cdrive-flash run: LFFS format DOES need the program ISR (update made with Claude)

The first cdrive-flash run (started 09:49) was killed by a host power cut
~2.5 min in; rerun completed cleanly, no state lost. RESULT: unmapped_access at
761,118,521 cycles (+57,919 past the prior medint block at 761,060,602), blocked
on a WRITE of 0x8 to ICU 0x0c1201cc. The C: flash model was accepted end-to-end:
308 accesses at 0x024xxxxx — LFFS scanned the erased array (scattered reads, all
0xFF = unformatted volume), then medint began format work (autoselect 0x90 with
protect-verify reads 0, reset 0xf0, sector ops). It then configured hw timer
unit 0x60 (write 0x0c120a6c=0) and tried to enable an interrupt by writing 0x8
(bit 3 = IRQ source 3) to 0x0c1201cc — the exact multi-halfword-program
dependency predicted in the RE note below. So the open question is answered:
LFFS format does engage the program-ISR path; an empty C: cannot mount without
it. 0x0c1201cc is 4 above the known FIQ enable-set sink 0x0c1201c8, value bit 3
— plausibly IRQ enable-set for source 3, unverified. Screen still the white
clear. Next: RE-confirm 0x0c1201cc's role, then model it plus timer unit 0x60
raising IRQ source 3 so medint's program ISR can run, and rerun.

## 2026-10-29 C: drive (LFFS) flash model + parallel Thumb-decoder audit (update made with Claude)

C: drive modeled: `scratch/boot-v15-nosprobe` option `cdrive-flash` adds a 4 MiB
RAM-overlay AMD x16 flash at PA 0x02400000 (LFFS volume; medint.pdd checks no
IDs/CFI, only sector-protect==0). Minimal command FSM: reset 0xf0/0xff, blind
0x60 sector lock, autoselect (protect-verify reads 0, IDs don't-care), single-
halfword program into the overlay, sector erase with DQ poll (first poll returns
0x0008 = DQ7=0/DQ3=1, then the sector reads back 0xFF), 0xb0 suspend finishes
instantly; sector map = two 2 MiB dies, 64 KiB sectors + 4x16 KiB boot sectors
per die top. Reads serve the 0xFF-initialised overlay. Board tests cover
reset/lock/autoselect/program/erase (note: byte 0xaaa arrives as a high-halfword
store, select 12 at word 0xaa8 — same convention as the code flash). Known next
dependency (from the RE): multi-halfword program needs hw timer "unit 0x60"
(0x0c120a60) raising IRQ source 3; single-halfword + erase work without it, so
run first and see whether LFFS format needs the program ISR.

Thumb-decoder audit RESULT (clean): a full capstone-differential sweep of all 18
Thumb formats + SWI/BX/BLX/BKPT in zap_mode16_decoder.sv found NO siblings — the
format-11 SP-relative U-bit bug (patch 0008) is the only decode error. Every
positive-offset load/store (formats 6,9,10,13, both register-offset forms) emits
U=1 correctly; PUSH/POP and LDMIA/STMIA P/U/W directions, halfword SH/imm split,
branch sign-extension/scaling, and the BL half-pair join (−1 PC compensation,
LR|1 interworking) all verified. Harness: `scratch/thumb-decoder-audit/audit.py`
(bit-exact Python port + capstone ground truth), output audit-output.txt.
Minor non-functional deviations noted, none affecting compiler-generated code:
(D1) 0xDExx (cond=1110) decodes as unconditional branch instead of the ARMv4T
UNDEFINED trap — revisit only if a UDF-based mechanism surfaces; (Q2) BKPT drops
its immediate; (Q3) MOV/MVN set Rn=Rd instead of SBZ (harmless, mode32 ignores
Rn); (Q4) ADD Rd,SP force32-aligns the SP operand. Belt-and-braces items for a
future Verilator decode-differential: BL half-pair across pipeline stalls, and
bit-0 handling on PC writes for POP{PC}/MOV PC,LR (writeback path, not the
decoder). Note the vendored third_party/zap line 483 is still unpatched by
design (patch 0008 applies it in the maintained build; the experimental sim uses
the directly-fixed scratch/boot-v15-quiet-zap copy). Next CPU-correctness step
when useful: execution lockstep vs Unicorn (the ~/develop/n-gage Pocket core has
a full harness); the ARM920T TRM is the semantics reference per flagged case,
not a cover-to-cover read.

## 2026-10-29 CPU fix validated: +31M cycles, EFile runs F32, reaches C: drive mount (update made with Claude)

The Thumb SP-relative U-bit fix is validated: a full from-reset run advanced from
the old panic (729,986,403) by +31M cycles to 761,060,602 — EFile cleared the
KERN-EXEC 0, ran into real F32 init, and the boot now reaches the internal-media
/ C: drive mount: medint.pdd (VA 0x50384990) issues AMD flash commands to the
internal user flash at physical 0x02400000 (CS1 upper half) — reset 0xf0 then
0x60, which our flash command FSM doesn't model (it only knows the three
identified chips' identify/CFI/burst sequences). 86 ticks; still the white clear.
NOTE the zap pristine constraint is LIFTED (user, 2026-10-29): edit the CPU
freely; patches/zap/0008 kept only because the build's upstream-comparison uses
pristine zap as baseline. The Thumb fix is also live in the sim RTL copy
scratch/boot-v15-quiet-zap.

This is the "mount C: via medint.pdd" obstacle predicted from the 6600 analysis.
The C: region is internal user flash we have no content for; the plan is to model
CS1-upper (0x02400000..0x027fffff) as an erased AMD flash (array reads 0xFF so C:
is unformatted/empty) and accept medint's command set (reset/autoselect/CFI/
sector-lock/erase/program, program+erase sinking to a RAM overlay) so F32 mounts
an empty C: and proceeds — the splash lives on Z: (ROM) and does not need C:
content. A focused RE of medint's exact command set is in progress.

## 2026-10-29 ROOT CAUSE: ZAP Thumb SP-relative LDR/STR decoder bug (real CPU fix) (update made with Claude)

The EFile block is a genuine CPU RTL bug, NOT a synthetic-stub gap. ZAP's Thumb
decoder mis-decodes format 11 (LDR/STR Rd,[SP,#imm8*4]) with the ARM U bit = 0
(subtract) instead of 1 (add): `zap_mode16_decoder.sv` T_SP_REL_LDR_STR emits
`{3'b010, P=1, U=1'd0, B=0, W=0, L=bit11, ...}`. The two correct siblings in the
same file use U=1'd1 — T_PC_REL_LOAD (format 6) and T_LDR_STR_5BIT_OFF (format
9). Thumb SP-relative transfers are always positive-offset, so `str r1,[sp,#4]`
wrongly computed SP-4. EFile's E32Main (0x503d5838) did `str KCurrentThreadHandle
,[sp,#4]` then read the handle back from the correct SP+4 (still stale =
0x503cdbc5, EFile's own entry); exec 55 (ThreadSetPriority) got that bad handle,
DObjectIx::At returned NULL, and the kernel panicked the EFile thread with
KERN-EXEC 0 (EBadHandle) and killed it — after which only the idle thread runs.
F32 init 0x503d5554 (LoaderThread/ESTART) was never reached; "LoaderThread
created" in the prior note is wrong. Boot survived 730M cycles because the only
earlier Thumb SP-relative store used imm=0 (U irrelevant); EFile's E32Main is
the first nonzero-offset SP store.

Fix (verified by source + trace): set U=1 in T_SP_REL_LDR_STR. Production patch
`patches/zap/0008-thumb-sp-relative-ldr-str-add-offset.patch` added
(third_party/zap kept pristine); the sim RTL copy
`scratch/boot-v15-quiet-zap/src/rtl/zap_mode16_decoder.sv` is fixed and a
full from-reset validation run is in progress. This corrects ALL Thumb nonzero
SP-relative loads/stores — a broad correctness fix the real user side (all
Thumb: EFile, EStart, apps) depends on. Expected: EFile proceeds past 0x503d5862
into real F32 init. The synthetic power model / MMC questions only become
relevant after that. This should also be added to the maintained sim RTL and
validated with the ZAP Thumb benches (a `str/ldr [sp,#4]` round-trip).

## 2026-10-29 CORRECTION: EFile (file server) DID start and run; blocks in F32 init (update made with Claude)

The "EFile never started" reading below was a trace-window artifact. A windowed
trace (`win-trace=LO:HI` added to main.cpp; run `run-efile-window.py`, output
`build/sim/runs/boot-v15-efile-window/`, preserved as efile-window.tsv /
cp15-window.tsv) shows EFile.exe WAS created, resumed, and executed F32 init for
~23k cycles (cycles 730,502,230..730,525,057; its data region VA 0x80100000 is
page-mapped and still live at run end; two context switches into its process
domain, DACR 0x55555717, bracketed by the moving-model TLB/cache flush). It ran
its main 0x503d5838 (past the "FileServer" find-server gate 0x503d57e4, into
F32 init 0x503d5554 which creates LoaderThread), then blocked in the kernel
reschedule (WaitForAnyRequest, 0x50329cc8/0x5032a5a8) and never ran again — nor
did any EFile-process thread (LoaderThread) for the remaining ~270M cycles; the
idle thread spins. So the boot is NOT stuck at a kernel hand-off: EFile is
blocked on a request/event that is never completed, or waiting on LoaderThread
which never runs. Leading suspects (per investigation): the synthetic power
model's no-op vtable swallowing a request completion F32 waits on, a
LoaderThread scheduling issue, or local-media (medint.pdd/MMC) init waiting on a
media-ready event the board latch model never fires. A focused decode of the
exact blocking exec is in progress. This is tractable (not the 6600's hard
wall) and remains an authentic-boot inflection worth user input on HLE depth.

## 2026-10-29 (superseded by the correction above) EKA1 kernel idle; EFile not yet started

With the Variant interface param-read slots (+0x48/+0x50) upgraded from ret0 to
zero-fill (so product_info's identity method gets an in-range value instead of
uninitialized heap, clearing its reason-3 Kern::Fault), the authentic from-reset
V15 run NO LONGER FAULTS: it runs the full 1,000,000,000-cycle cap with 675
periodic ticks and no new unmodeled register. Preserved:
`build/sim/runs/boot-v15-kernel-idle-milestone/`.

This is the deepest milestone to date — the real NEM-4 EKA1 kernel boots from
reset through digest, VARIANT, scheduler, synthetic NOS (interfaces + power
model), product_info, full pin config (GPIO/PUP/ICU/timers), driver init (real
power handlers register) to the kernel IDLE state. The retirement tail is ~98%
the D-cache clean/invalidate loop at 0x50328408..0x50328414 (the idle thread
spinning, woken only by timer ticks). HOWEVER the first user process, EFile.exe
(the file server), never runs (grep of the trace: 0 hits on its entry
0x503cdb60), so the user-side boot chain EFile→EStart→EwSrv→Starter→SplashScreen
has not begun and the LCD is still the white clear (18353 words, 75 headers).

This is the same frontier the Nokia 6600 recompiler documented as unsolved
natively: "after Init2/Init3 the kernel idles by design; the kernel alone never
creates the first user process — the hand-off starts EFile." The open question
is whether EFile is (a) never created (a kernel boot step that spawns it did not
run or needs state a stub left out), (b) created but blocked on a resource our
model doesn't provide, or (c) started but needs far more than 1e9 cycles. A
focused investigation of the EKA1 kernel→EFile hand-off is in progress. This is
a real inflection worth the user's input on how far to push synthetic HLE vs.
awaiting real NOS content; flagged rather than burning many more blind
iterations. All board models and tests remain green; the NOS content gap is
unchanged.

## 2026-10-29 power model installed; kernel boot-complete; into next init phase (update made with Claude)

The null singleton at 0x80006bc4 was identified as the EKA1 kernel POWER MODEL,
installed only by ekern export ordinal 394 (0x5033c8f8) — which no ROM code
calls, so on real hardware the NOS/baseband installs it during nosstarter.
Our no-op stub skipped it. Fix: the synthetic NOS stub now installs a minimal
power model. `scratch/nos-stub-blob/nos_stub.S` calls ordinal 394 with a
board-backed RW object in the NOS window (PA 0x9e000 / VA 0x5149e000,
supervisor-RW mapped): vptr → the all-ret0 vtable, an empty self-linked
power-handler queue (+0x10/+0x14 → &self), iOffset 4, status 0. The object is
served RW by the board (`synthetic_nos_power_model`); the kernel writes its
fields and later drivers add handlers via ordinal 5. The digest-probe now
overlays the blob AND the power-object initial image. Board tests cover the
window; all pass.

Result: the boot vcall at 0x5033183c ran the no-op, the kernel-server boot
phase completed (boot-complete magic 0x55555517 written) and the boot jumped
~280,000 cycles to 729,884,779 — the largest single advance since the tick.
New frontier is the system-control block (0x0c120c18), modelled with the same
zero-reset RW latch treatment (block 0x0c120c00..0x0c120c20 added to the
board register-latch model). 10 periodic ticks now. Still the white clear;
chasing toward the server/UI startup where SplashScreen blits the logo.

## 2026-10-29 device-init tail walked; stop at uninitialized kernel singleton (update made with Claude)

After the synthetic NOS registration (below), the boot streamed through the
whole device-init tail with bounded, opt-in peripheral models added to
`scratch/boot-v15-nosprobe`:
- `keypad-gpio`: board GPIO/PUP pin-config as zero-reset RW latches over the
  whole UIF/GPIO page (0x0c150000..0x0c1504ff) and PUP page
  (0x0c14f000..0x0c14f0ff), plus a widen rule so a GPIO register latched at one
  width serves other widths with new bytes reading zero (idle input). Specific
  handlers (CBUS, UIF-protocol, ADC, timer) keep precedence by running earlier.
- `icu-banks`: IRQ-ICU enable-set/clear/pending banks (0,1,2); pending reads 0.
- `timer-units`: timer units 1..4 as RW latches (status reads not-expired).
- ICU enable writes to 0x0c120108/0x10c that are not the timer-0 values now
  defer to the ICU bank model (so enabling IrqTimer1 = value 2 is accepted).
All board tests pass (incl. new per-feature boundary tests); defaults unchanged.

The boot reached cycle 729,606,213 and faulted on a virtual call
`ldr pc,[r3,#0xc]` at VA 0x5033183c: the function loads a singleton pointer
from global [VA 0x80006bc4], takes its vtable and calls method +0xc. The
singleton at 0x80006bc4 is never initialized (no write in the captured memory
tail), so the vtable fetch/dispatch aborts; the fault handler records PC
0x5033183c and fault code 0x10000000. This is a kernel singleton left null by
incomplete init — not a missing MMIO register. Next: disassemble the owning
function and identify what populates [0x80006bc4] and whether a stub (NOS, a
driver modelled only as latches) prevented it; it may need another synthetic
interface registration or a fuller driver model. The NOS/baseband content gap
is unchanged. No pixels yet; LCD still the white clear.

## 2026-10-29 synthetic NOS registration clears product_info; into ekeyb keypad (update made with Claude)

Disassembly (recorded in the investigation) showed product_info faults only
because the real NOS, during its entry call, registers "interface #3/#6" with
the kernel Variant singleton ([0x8000038c]); it is NOT an ISI round-trip, and
product_info tolerates garbage parameter values gracefully. The no-op stub was
therefore upgraded to a minimal synthetic registration routine
(`scratch/nos-stub-blob/nos_stub.S`, built with arm-none-eabi, embedded as
`scratch/boot-v15-nosprobe/nos_stub_blob.h`): entry at VA 0x5149d284
trampolines into a routine that reads the Variant pointer, calls
RegisterInterface(variant,3,iface) and (…,6,…) and the readiness setter, with
an all-`MOV R0,#0; BX LR` interface vtable so every method returns without
writing. Served read-only for both code and data over PA 0x0009d000..0x0009d288
(VA 0x5149d000; the kernel maps VA 0x51400000→PA 0x0 per the dumped L1 in
`boot-v15-nosprobe/l1-final.tsv`). Because that window lies inside the core
digest range, the digest-probe was recomputed over the image AS SERVED
(factory + stub overlay): `build/firmware/nem4-factory/digest-probe-core-nosstub/`.
NOT authentic — placeholder for the hardware-descrambled baseband, swappable.

Result (`build/sim/runs/boot-v15-nos-stub/`): the digest passes, nosstarter's
call returns, product_info and the kernel interface-waiter are satisfied
(nos_stub_fetches 300 = kernel actively reading the registered objects), and
the boot advances past product_info/ekeyb-registration to cycle 729,585,848,
where ekeyb (the keypad driver, VA 0x5041a4xx) configures the keypad GPIO block:
halfword registers phys 0x0c150400/0402/0404/0408 via the 0x58000000-window
writer at 0x503245bc/0x50324608. Modeled with an opt-in `keypad-gpio` probe:
zero-reset RW halfword/word latches over 0x0c150400..0x0c15040f (config writes
read back; input reads are zero = idle, no keys) — a standard GPIO-bank model.
Rerunning with it; next frontier expected further into device init
(display/MMC/window-server), per the EFile→EStart→EwSrv→Starter→SplashScreen
chain. No pixels yet; LCD still the white clear.

## 2026-10-29 NOS entry stub passes nosstarter; new frontier product_info/ISI (update made with Claude)

Since the authentic NOS/baseband bytes exist in no available file, an explicit
opt-in SYNTHETIC stub was added (`scratch/boot-v15-nosprobe`, option
`nos-entry-stub`): code fetches at PA 0x0009d280..0x9d29f (the NOS entry line,
reached via the kernel's VA 0x51400000 raw-flash window — confirmed mapped:
L1[0x514..0x518]=0x00000..0x40000|0x43e, PA 0x02400000+, dumped in
`build/sim/runs/boot-v15-nosprobe/l1-final.tsv`) return `MOV R0,#0; BX LR`.
Data reads and writes are never served by the stub; board tests cover the
boundaries. This is NOT an authentic boot component — it is a placeholder for
unavailable hardware-descrambled baseband code, swappable for real NOS content.

Result (`build/sim/runs/boot-v15-nos-stub/`): nosstarter's call returns cleanly
and the kernel CONTINUES into the extension-init loop (0x50331680 walking the
kernel-extension directory: rtc, nosstarter, pnmsg, isimsg, phonet, cbus,
helper.ldd, medint.pdd, ELocal.fsy, EUser, Hal, EFile, EFSrv, EStart, EDISP,
btldd...). ~6,500 cycles later it faults with a kernel panic naming
product_info.DLL (diagnostic write 0x0c0047f0='prod', the fault path prints the
ROM banner "product_info.DLL V 4.03 26-11 NEM-4 (c) NMP. N-Gage"). No bus
access precedes the fault — it is a CPU/RAM panic during ISI/baseband extension
init, the expected consequence of a no-op NOS (the Pocket HLE core answers ISI
queries via a fake NOSDRIVER; see `docs/references.md` and
[[ngage-pocket-core-reference]]). The next frontier is therefore the ISI/Phonet
extension init path, not a new MMIO register. Investigate what pnmsg/isimsg/
phonet/product_info init require from the NOS (likely ISI message round-trips
the stub must answer, per the Pocket core's documented energy-mgmt/identity
replies) before extending the stub into a minimal ISI responder. This is the
first point where the missing baseband's behavior — not just its bytes —
matters.

## 2026-10-29 scramble closed: CMT-side hardware descramble; boot remap found (update made with Claude)

Cipher analysis (consolidated in `scratch/nem440-flash-extract/out/cipher-analysis.json`)
closed the encrypted-region question. The container's algorithm blob is a flash
program/erase driver + field-service loader (strings dev_flash.c, loc_task.c,
FLL_01_43_00; the only crypto inside is the Bluetooth SAFER+ suite, uncalled on
the write path) — it programs payloads verbatim. The opaque region is CS0 phys
0xA000..0x2B3000, scrambled for the DCT4 cellular-MCU (CMT) fetch path and
descrambled by UPP hardware on that side; the scramble is stateless, word-local
and position-keyed, and provably not any byte/word XOR, additive keystream,
GF(2)-affine map, or phosher/DCT4Crypter-style construction (2 MiB of exact
known plaintext exists because factory phys 0x50A000..0x700000 is the
plaintext twin of 0xA000..0x200000). Phys 0x200000..0x2B3000 (0xB3000 bytes)
has no plaintext twin and is unrecoverable from files. Public knowledge agrees
(DCT4Crypter/phosher cover classic DCT4 only; WD2/Symbian variant undocumented).

Newly discovered boot behavior that resolves the dump "artifacts": boot code at
phys 0x33E4..0x34C8 patches the page tables, adding +0x500000 to the physical
base of every page in [0xA000, 0x317000) — the ARM920 reads the plaintext twin
at 0x50A000+, the PPM bank, and the 8-MiB chip mirror, exactly reproducing the
phone dump's layout. The Symbian side never reads the scrambled window. The
supplied dump is therefore a faithful post-remap view, and identity-mapping the
dump in the simulator has been accidentally correct. Plaintext Nokia ENOS
CMT_SW Thumb code begins at phys 0x2B3000 (source paths at 0x2c7e3c).

The main digest stays unmatched and is provably unmatchable from the
containers: even the real phone's own content hashes to 1784c17a..., not the
embedded 2c09c86f... (90+ layouts tried, including the exact boot-remap view).
The expected value most plausibly covers golden pre-personalization content
(the 56-byte per-device hole sits inside the digest window via the 0x300000
mirror; EEPROM-emulation sectors at 0x7F0000/0x7FC000 mutate at runtime). The
digest-probe accommodation therefore stands, now with a precise justification.

The .326 extension at phys 0x4730000 (VA 0x51230000) begins with a valid
scanner-compatible EKA1 extension header: next-base 0x51230000, size 0x140000,
root list 0x51230080, version/time words matching the core's — and its content
digest passes. v4.17 extraction lives in `out-v417/` (extract_tolerant.py; the
original parser lost sync once on a checksum coincidence). Next: assemble the
factory-faithful flash image set (factory bytes, erased-FF gaps, real .326
extension in place of the synthetic reconstruction), regenerate the digest
probe over it, and run V15 from reset. The nosstarter NOS-image gap (CS1 upper
half / third CNT container) remains the open content question.

Done: `scratch/authentic-flash-image/assemble.py` builds
`build/firmware/nem4-factory/{core.bin,extension.bin,manifest.json}` (VA-linear
factory content, MCU+PPM flash-order overlay, per-device hole and unwritten
flash erased 0xFF) — the .326 extension descriptor verifies over the assembly
(0b1173ee..., PASS). `digest-probe-core/SYM.ROM` replaces only the 16-byte core
expected-digest field (new computed value ac2ac9c5...; manifest records
before/after). The V15 from-reset run on the factory inputs completed at cycle 729,407,390 on
the identical nosstarter frontier (diagnostic write 0x0c0047f0=0x5149d290):
the extension scanner handled the erased head, the firmware's own extension
digest check passed on authentic content, both digest gates cleared with only
the 16-byte core accommodation, 8 periodic ticks and the RTC/debug-console
sequence ran as before. Output `build/sim/runs/boot-v15-factory/`; screen is
the assumed white clear. This is the cleanest validated configuration to date;
`boot-v15-factory` supersedes `boot-v15-periodic` (dump-input lineage).

The sole remaining blocker to further boot progress is CONTENT, not modeling:
the extension head (VA 0x511c0000..0x5123e338, retail CNT container) and the
NOS image (CS1 upper half, PA 0x02400000+0x400000). Next development session:
obtain a NEM-4 CNT container or a hardware CS1 chip read; alternatively
investigate the QD images' equivalent modules (read-only, for identification
not substitution) to name the component that installs the 0x514xxxxx mapping.

## 2026-10-28 factory flash files extracted and validated (update made with Claude)

`scratch/nem440-flash-extract/` now holds a checksum-validated parser for the
Nokia "WD2 BT2" containers (record grammar documented in extract.py: data
records [0x14][phys addr:4 BE][ck1][len:3 BE][ck2][payload], both files parse
end-to-end with zero residue) and extracted images under out/ with full
per-record JSON maps. nem440.3c1 programs CS0 0x0..0x6FFFFF, CS1
0x2000000..0x23FFFFF, CS2 0x4000000..0x46B4FFF plus an embedded 0x2dd94-byte
flash algorithm blob; nem440.326 (PPM) programs the updated ROM header words,
CS0 0x700000..0x76BFFF and CS2 0x4730000..0x47FFFFF.

Verified: the .326 extension digest descriptor (VA 0x51230000..0x5136BFFF,
MD5 0b1173ee849db3045a8a0b78507bd96b) matches the extracted content exactly —
the factory extension is authentic, bit-validated, and supersedes the
synthetic reconstruction. The factory core matches the dump byte-exactly over
phys 0x317000..0x11B5000 (14.5 MiB); the dump's lower window is proven
artifact (2 MiB self-duplication, another build's PPM content, duplicated
header) — the dump fails its own digest for that reason. The main digest
(2c09c86f...) remains unreproducible because phys 0xA000..~0x2F0000 (~2.9 MiB)
in the factory file is ENCRYPTED (8.0 bits/byte, referenced by no ROMFS entry
or E32 header); its plaintext exists in no available file. That blob's size is
close to the expected NOS image (~3 MiB at CS1 0x2400000+, which neither file
programs), and the containers ship a flash algorithm that runs on the phone
during flashing — a plausible decrypt-and-place agent. Cipher analysis is in
progress. The ROOT dump's first ~0xC0000 bytes match neither factory file:
retail phones carried a third container (CNT/content pack) for the extension
head (VA 0x511C0000..0x5123E338). Unwritten factory gaps (erased 0xFF on a
fresh phone): phys 0x46B5000..0x472FFFF and the PPM-bank tail above 0x76C000.
Bank tables in factory and dump are identical (an earlier divergence note was
wrong). BOOT-101F8C19.dmp equals phys 0x321000 (kernel code start).

A second complete build arrived: `firmware/NEM-4 v4.17 EN/` (nem441.7d1 MCU +
nem441.738 PPM, extracted from the V4.17 RAR-SFX updater; source link in the
archive: gem-flash.com). The MCU file is byte-identical in size and format to
v4.03's; the encrypted CS0 region differs between builds in 320/371 records
(build-varying code — consistent with the NOS image), giving the cipher
analysis a second ciphertext at identical addresses.

Next: verify the .326 extension begins with a scanner-compatible image header
at phys 0x4730000, assemble an authentic flash-content set for the board model
(factory bytes, erased-FF gaps, no synthetic tail), identify the cipher of the
encrypted region via the flash-algorithm disassembly, and ask the user for
possible additional factory containers (CNT/content pack; ISA/NOS flash file)
from the same source.

## 2026-10-28 authentic run validated; frontier identified as the NOS entry; factory flash files arrived (update made with Claude)

The authentic from-reset run (`scratch/boot-v15-periodic/run.py`: V15 cache CPU,
all-0x257e flash, no RAM intervention, periodic tick, all current probes)
completed at cycle 728,190,258 on the identical frontier as the fast chain: the
kernel crash write 0x0c0047f0=0x5149d288 after calling VA 0x5149d284. It passed
VARIANT authentically, delivered 8 periodic ticks, completed the RTC read-out
and printed the same "TRtcQueue::Add: 2" debug line. Outputs
`build/sim/runs/boot-v15-periodic/`; screen remains the assumed white clear.

Instruction-level disassembly identified the frontier precisely: nosstarter.ext
(148 bytes at file 0x3504a0, entry 0x50350504) copies 0x5790 bytes of
initialized data from VA 0x51711138 to 0x80006ef0 (EUser Mem::Copy), zeroes
0xc27a8 bytes of BSS at 0x8000c680, and calls VA 0x5149d284 with r0=-1 — the
entry point of the separately linked NOS/baseband (ISA cellular) program that
lives in flash OUTSIDE the Symbian logical ROM. The core ROM references exactly
two addresses above the ROM window: 0x5149d284 and 0x51711138 (both nosstarter
literals; all other 0x51400000+ word hits are data noise/0x51EB851F constants).
All three firmware variants contain the same stub with per-build addresses
(RH-29: 0x5149e4c4/0x5170b054; RH-4: 0x5149f934/0x517050c4). The superpage
carries a type-3 bank window {PA 0x02400000, size 0x600000} (CS1 upper half) —
the evidence-consistent home of the NOS image, probably mapped at VA
0x51400000; kernel-side confirmation of the mapping code is in progress. The
NOS content exists in NO supplied dump (the in-phone dumper faulted at
0x51370000; signature/literal-density searches across all dumps are negative).
Do not stub the call: the goal is an authentic boot.

Kernel-side mapping disassembly settled the window question: bootstrap routine
0x1ff8 maps the type-3 banks unconditionally, pre-MMU, with a running VA cursor
from 0x58000000 — the NOS window PA 0x02400000 (+0x600000 declared) lands at
VA 0x59200000 (uncached, L1 entries 0x02400432..) and again at VA 0x59800000
(cached, 0x0240043a..), supervisor-only AP=01 (which is why the on-phone
user-mode dumper could never read it). No code in any supplied image writes an
L1 entry for VA 0x514xxxxx — ekern never walks bank types, and the exception
dispatcher reached the fatal mailbox path, so no runtime abort-fixup handler
was registered either. The variant ecust.dll geometry method (file 0x349c98,
the ROM's only 0x59200000 literal) reports the NOS/baseband flash as PA
0x02400000 size 0x400000 for our flash classes. Conclusion: the agent that
creates the real phone's 0x514xxxxx linear mapping (or abort fixup) must live
in the unrecovered extension head VA 0x511c0000..0x5123e338 — synthesized as
directories+FF in our reconstruction. The content gap is therefore twofold:
the real extension head AND the NOS image at PA 0x02400000..0x027fffff. Do
not hand-add a 0x514xxxxx mapping; without real NOS bytes it only moves the
frontier to an unbacked fetch at PA 0x0249d284.

The user supplied Nokia factory flash-programming files
`firmware/NEM-04 v.04.03 N-GAGE/nem440.3c1` (MCU, 18,777,938 bytes) and
`nem440.326` (PPM, 1,361,703 bytes), dated 27-11-2003 — DCT4 "WD2 BT2 /
STARSHIP & BT ALGORITHM" containers. Initial analysis: the core ROM image is
embedded from .3c1 offset 0x2defc with periodic block framing (~0x500 bytes
per MiB, grammar not yet derived) and differs from the dump in content
(header checksums at image +0x84/+0xa8, the bank-table region, and the digest
descriptor region ~0x8d06 where the factory bytes carry the expected MD5
2c09c86f... — the factory image may pass the digest check the dumps fail).
Container reverse-engineering and full extraction are in progress in
`scratch/nem440-flash-extract/`; if the files program CS1 0x02400000+ the
missing NOS image is recovered and the digest-probe input modification can be
retired. A Nokia 6600 factory file (`firmware/NHL-10 v.05.53 6600.rar`) is
also available for format cross-reference.

## 2026-10-28 kernel runs to the extension-VA frontier (update made with Claude)

With the tick, block-0x14d probe, debug sink, and explicit kernel-phase CBUS
inputs (new repeatable `cbus-input=REG=VALUE`, supplied zero for registers
0x20–0x34; observed reads so far 0x24, 0x31, 0x33, 0x21 — the RTC path), the
continuation `build/sim/runs/boot-variant-periodic-timer/` processes four
periodic ticks, completes the kernel RTC read-out and the "TRtcQueue::Add"
debug line, and runs to cycle 453,235,865. It then stops on the diagnostic
mailbox write 0x0c0047f0=0x5149d288 from the kernel crash path: the nosstarter
region code at VA 0x5035053c performs `MOV PC, R4` with R4=0x5149d284 (a core-
ROM literal at file offset 0x350548), and that VA takes an MMU translation
abort — no bus access is attempted, so the kernel simply never mapped it.
VA 0x5149d284 lies ~700 KiB beyond the reconstructed extension's end
(0x513f0000) and beyond bank table 0x830's 19.94 MiB span; this is the
predicted missing-ROM-content frontier (flash-layout.md's CS2 0x046c001c
question). Research is in progress to reconcile the extension descriptors,
the CS2 physical mapping, and whether any supplied dump contains the content.
Do not paper over this with a stub: the call is the NOS/baseband starter path
and the goal is an authentic boot.

The authentic from-reset run (`scratch/boot-v15-periodic/run.py`, V15 cache
CPU, all-0x257e flash, no RAM intervention, all current probes) was launched
and is expected to reach this same frontier in a few hours; output
`build/sim/runs/boot-v15-periodic/`, screen capture attempted on completion.

## 2026-10-28 periodic tick delivered; kernel debug console found (update made with Claude)

The corrected periodic-tick model (scratch/variant-periodic-timer, option
`timer-periodic`) now matches the kernel disassembly: the kernel reload write
0x632ea with control 2 arms a free-running tick; the stale early-boot enable is
treated as cleared until the kernel's own enable-set 0x0c120108=1; any status
write to 0x0c120a08 acknowledges; ICU current 0x0c120114 reads 1 (IrqTimer0)
while pending and 0 after acknowledgement; secondary banks 0x0c120154/0x194
read 0; the dispatcher-exit entropy read of 0x0c120a10 returns the compare
latch. The continuation `build/sim/runs/boot-variant-periodic-timer/` matched
all 241 predecessor bus rows, delivered the tick at cycle ~452,656,800, and the
authentic kernel IRQ path executed exactly as disassembled: vector 0x18 →
0x50327698 → dispatcher 0x5032287c → ICU current=1 → tick ISR 0x503225b0 →
status ack 0x0c120a08=0 → drain reads → wait flag 0x8000000c set → idle loop
woke. Full IRQ-path disassembly notes (dispatch table [0x800066e0] index
IRQ+0x5c, ID map "IrqTimer0"=0x5d, FIQ-ICU at 0x0c1201c0 — the 0x0c1201c8
write enables FiqAPIIOAbort and is unrelated to the tick) are recorded in
[uem-control-bus.md](uem-control-bus.md). The timer tick unit (one CPU cycle)
remains an unverified assumption.

After the tick, kernel routine 0x5032430c initialized an unidentified UPP
block (0x0c15053c=0xffff, 0x0c15053a=0x4c, 0x0c14d000=2/0x300, 0x0c14d004=
0x205, 0x0c14d008=0, reads of 0x0c14d00c/0x10), modeled by the explicit
zero-reset `block14d-probe`. The kernel then began writing characters through
routine 0x503243a8 (CR/LF handling, gated on a debug-enable flag) to a
byte-addressed window at VA 0x59000000 = physical 0x0de00000: the write-only
`debug59-sink` captured genuine Symbian kernel trace text, starting with
0xc0 then "TRtcQueue::Add: ". The device identity (debug console buffer) is
unverified; bytes are retained in the result JSON as `debug59_text`.

`scratch/boot-v15-periodic/` is the authentic-path configuration: V15
cache-enabled CPU, all-0x257e flash (no RAM intervention, counterfactual code
removed), the periodic tick and both new probes; its `sync-from-chain.py`
reapplies the deltas after chain updates, and `run.py` performs the from-reset
1e9-cycle run with capped logs and a screen-capture attempt. Board tests for
both directories pass. Launch the long run once the fast chain stops
discovering new registers at this cadence.

## 2026-10-28 flash identity resolved by disassembly (update made with Claude)

Full disassembly of the firmware's flash probes settles the VARIANT question.
The first probe (file offsets 0x95c–0xb34, chooser 0xb38) identifies only CS1
(and Intel-on-CS2): AMD mfr 0x0001 with first ID word 0x257e or 0x267e →
result 2 → bank table 0x830 (16 MiB RAM); 0x22d1 → table 0x744; nothing →
fallback 0x638 (8 MiB). 0x227e matches nothing there. The classifier at 0x5cc0
(helpers 0x598c/0x5a34/0x5ad8, pools listed in flash-layout.md) maps
0x257e/0x2502/0x2500 with handshake bit0=0 (0x42) → class 4, and
0x227e/0x2202/0x2200 with bit0=1 (0x43) → class 0. The config routine 0x5d74
gives classes 0/4/5/6 the same timing word 0x10202132, and class 2
(0x227e + 0x42) hangs on CS0/CS1. The validator at 0x34933c only requires the
middle chip's class to repeat an already-seen family (hence 0,4,0 faults and
homogeneous sets pass); classes 0/4/5 select the same AMD burst driver.

Therefore all three chips reporting 0x0001/0x257e/0x2502/0x2500 with handshake
0x0042 is the unique self-consistent configuration: table 0x830 (16 MiB SDRAM,
matching the NEM-4 schematic), classes 4,4,4, validator accepted, no RAM
intervention. Public Am29BDS643G parts return 0x227e/0x43 (datasheet in
`scratch/research/schematics/am29bds643g.txt`, autoselect table + note 10:
0x43 = handshaking enabled), and no public AMD part returns 0x257e — the
schematic's AM29N643GT70MVAI has no public datasheet and is evidently a
Nokia-custom part the firmware was built for. Unverified remainder: the real
chip's autoselect words (inference from firmware expectations), burst/CFI
protocol details, dump-tail coverage of table 0x830's 19.94 MiB spans versus
the 17.75 MiB image, and chip-select assignment. The flash-class RAM
counterfactual is fully explained and permanently retired. The authentic
configuration equals the existing `flash-all-257e-probe` model; the completed
`boot-v15-all-257e` run (cycle 725,805,161, past VARIANT, stopped at the
0x0c120074 frontier) is the from-reset baseline to extend.

## 2026-10-28 periodic timer: kernel IRQ dispatch reached (update made with Claude)

Goal restated by the user: an authentic boot to the Nokia logo — the firmware
must execute its real path. The flash-class RAM counterfactual is therefore not
an acceptable final path; it remains only a discovery tool on the fast
cache-off checkpoint chain. The authentic target configuration is the V15
cache-enabled CPU with defensible flash IDs, run from reset.

`scratch/variant-periodic-timer/` adds the explicit opt-in `timer-periodic`
hypothesis modeled on the Nokia 6600 recompiler `nk_bus_tick`: the observed ICU
`0x0c1201c8=0x08000000` write arms a periodic IRQ with the latched compare
period `0x632ea` (406,250 cycles); expiry presents timer status bit 0 at
`0x0c120a08`, and the observed write-1 acknowledgement clears it. Board tests
cover arming order (requires SYSC74 and the compare write), early-fire, ack,
re-fire, and constructor rejection; defaults are unchanged and
`test_default` passes. The timer tick unit (one CPU cycle) is an unverified
assumption.

The checkpoint continuation `build/sim/runs/boot-variant-periodic-timer/`
matched all 241 predecessor bus rows, took the periodic IRQ at cycle
~452,847,900 (one IRQ delivered), and executed authentic firmware IRQ entry:
vector 0x18 → handler 0x50327698 (SUB LR,LR,4; stack setup; a zero check at
0x80005e78) → dispatch at 0x5032287c, which loads literal 0x58120114 and reads
physical `0x0c120114` — the UPP ICU current-IRQ register predicted by the 6600
model. The run stops there: the register value (the IRQ number the kernel
dispatches on) is unknown. Disassembly of the dispatch table is in progress to
determine which value routes to the tick handler (0x503225b0..0x50322610) that
sets the kernel wait flag 0x8000000c. Do not guess this value; a wrong number
dispatches to the wrong kernel handler.

Separately verified by firmware/bitmap analysis: the first drawn logo on this
platform is Symbian `SplashScreen.exe` blitting `SPLASHSCREEN.MBM` (ROM-format
MBM at SYM.ROM offset 0x9718d0; bitmap 0 is 176×208 8bpp EByteRLE, ~1,463
non-white pixels — the embossed NOKIA logo; a 20-frame 176×208 12bpp startup
animation lives at offset 0xbc3140). The boot chain to it is
EFile→EStart→EwSrv(+scdv/lcd.ldd/FbServ)→Starter→SplashScreen, all XIP from the
mapped ROM; no extension-image bitmaps are involved. Success signature in a
trace: ROM reads near offset 0x97191c followed by non-uniform LCD data words.
Expected later obstacles (from the 6600 bring-up): a second timer/IRQ source,
Init3 HAL/UEM requests, C:-drive mount through medint.pdd (flash write/erase),
and Starter's baseband/NOS synchronization.

The earlier `boot-variant-wait-trace` result was reproduced bit-identically
before new work (all six output files; log differed only in one interleaved
startup line).

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

## 2026-10-30 LIKELY ROOT CAUSE: empty C: forces first-boot init, which blocks; EStart reads bootdata files (update made with Claude)

Disassembled EStart's startup loop (0x503ee900-0x503eeb20). It: RProcess::
SetSystem, reads a config via efsrv!RFile::Read (0x503eea3e), HAL::Get(37)/
(68) + HAL::Set (0x503eea60-0x503eeb4), User::LoadLogicalDevice (0x503eeacc),
and extensive drive/dir scanning (RFs::DriveList, RDir::Open, RFs::Mount/
NotifyChange). The HAL::Get(37/68) match C:\system\bootdata\HALData.dat
(persisted HAL attributes). Our C: image is FORMATTED BUT EMPTY (all reads
0xffffffff), so EStart runs FIRST-BOOT initialization every time - that is
what the LFFS writes at 1.5176e9 are (creating HALData.dat/CommonData/etc.) -
and the first-boot path is where EStart blocks in User::WaitForRequest on a
client-server reply that never comes. A factory device has these files, so
it SKIPS first-boot.

The user provided the real C: tree (firmware/disk_dump/C): system/bootdata/
{FirstBoot.dat,HALData.dat,CommonData.D00,LocaleData.D01}, system/Shareddata/
*.ini, System.ini - exactly what EStart reads. ngvm's own boot CREATES these
(its --save C: image has HALData/CommonData/System.ini/bootdata/Shareddata,
29% full, valid LFFS). Built a POPULATED 4 MiB LFFS image by enlarging ngvm's
C: to 4 MiB (ngvm_hw.h NGVM_SAVE_BASE 0x01C00000/SIZE 0x00400000, rebuild,
boot 14s, save, REVERT) -> build/firmware/thc/cdrive-populated-4mib.img
(64/64 LFFS blocks, HALData/CommonData/System.ini present). Testing it in the
LLE (run-fresh-pop.py -> boot-v15-populated): if EStart finds the bootdata it
should skip first-boot and proceed toward the server chain / logo. RISK: the
LLE's real ELOCAL.FSY must read ngvm's HLE-written file layout (the empty
format mounts fine; file structures unverified). FirstBoot.dat was not in the
ngvm image - may need adding, or the LLE creates it. Hypotheses falsified
first: NOS iface-13 readiness (= idle loop), unit-60 flash IRQ (delivers but
no effect). Resume bases: fresh-c1120, fresh-c1250, idle-c1517.

## 2026-10-30 FRONTIER PINNED TO THE EXEC (populated-C: falsified): EStart's async F32 func 23 never completes (update made with Claude)

The populated-C: image (real bootdata: HALData/CommonData/System.ini) was
tested from reset: it MOUNTS fine (past 767M) and the LLE does 3x the C:
reads (424715 vs 134256) - EStart reads the real files - but blocks at the
EXACT same cycle 1517595533 and idles to 2.5e9. So the empty-C:/first-boot
hypothesis is FALSIFIED: the block is content-independent and fully
deterministic.

Decoded EStart's blocking execs (mountend window, EStart stack 0x00501):
EStart parses a text config (exec 0x4f unicode-classify x151), then issues
ONE async client-server send - exec 0xc000bf (RSessionBase::Send) at cycle
1516656954 with session handle R0=0x400f0001, IPC function R1=0x17 (23),
args 0x00501ea8, status 0x00501e90 - then exec 0x4d (WaitForAnyRequest) and
blocks forever. At the block (idle-c1517) the only running servers are
FileServer (x7 refs) and Loader (x4); the handle 0x400f0001 resolves into the
file-server object cluster (0x804036xx-0x80403cxx all named "FileServer").
So EStart sends F32 function 23 to the file server, which is running but
NEVER completes/replies to the request.

This is a file-server-side async completion that never fires (the drive
thread / local-media op doesn't finish). It is NOT: the flash device (writes
complete, no post-write poll), unit-60 IRQ (delivers, no effect), NOS
readiness (idle loop), or C: content (populated = same block). NEXT: identify
F32 function 23 (needs the EKA1 TFsMessage enum) and why the file server
leaves it pending - likely the local-media (medint) async write/format
completion DFC that a synchronous board flash never signals. The 0x400f0001
handle and function 23 are the exact keys. Resume bases: fresh-c1120,
fresh-c1250, idle-c1517. Populated image: build/firmware/thc/
cdrive-populated-4mib.img (works as a C: image, just doesn't change this).

## 2026-10-30 ngvm LEAD: LLE file server never completes EStart's func-23; ngvm does, then reaches Fontbitmapserver (the splash path) (update made with Claude)

ngvm (oracle, trace 0x2) shows EStart's SendReceive at the SAME PC 0x503b76b0
talking to **Fontbitmapserver** (FBSERV, the font/bitmap graphics server that
renders the splash/logo). So in ngvm EStart gets PAST the file-server func-23
request and reaches the graphics server. In the LLE, EStart blocks ON the
file-server func-23 send (handle 0x400f0001) and never reaches FBSERV - which
is why no window/graphics server ever starts and there is no logo.

So the frontier is: the LLE's file server leaves EStart's async F32 func-23
request pending forever, whereas ngvm's completes it. The file server IS
running (FileServer object cluster at 0x804036xx). The missing piece is the
file-server-side completion of this one async op - most likely the local-
media (ELOCAL/medint) async completion DFC that a synchronous board flash
never signals. Confirmed NOT: flash device timing, unit-60 IRQ, NOS, C:
content. The concrete next step is to identify F32 func 23 (not in the public
SDK; needs the internal EKA1 TFsMessage enum or disassembly of the file
server's dispatch) and model/trigger the completion the file server waits on.
Getting past it should let EStart reach FBSERV -> window server -> splash.

SESSION NET: 2 real fixes (CTR cache-type register patch 0009; C: any-width
array reads) took the boot from the 767.8M C: crash to an authentic EStart
running LFFS/RAM-drive init and blocking on one file-server async request at
1.5176e9 (~+750M cycles). Frontier pinned to the exact exec; 3 hypotheses
falsified; ngvm oracle lead identifies the next server (FBSERV).

## 2026-10-30 ROOT CAUSE REVERSED FROM THE WAITING THREAD: EStart blocks on HelperDrv (helper.ldd) startup-reason request (update made with Claude)

Fully reversed the block from EStart (the waiting thread) down to the driver.
EStart's final wait is User::WaitForRequest(status 0x00501e90) on an async
request it issued at cycle 1515094: exec 0xc000bf (SendReceive) handle
0x400d0001, function R1=0xffffffff (-1 = the EConnect/session-connect
message). That handle resolves to kernel object 0x804092c0 (owned by EStart
DProcess 0x80409614, EStart-Main 0x8040983c) whose +0x34 field names
**"HelperDrv"** - the N-Gage helper.ldd device driver. The connect IS accepted
(the server's CServer::RunL runs CSharableSession::CreateL), so the session is
created; EStart then has an outstanding request to HelperDrv that never
completes.

ngvm (oracle) models HelperDrv explicitly (sw/kernel/chan.c:37-70):
  control 0 = HARDWARE startup reason (0 ordinary power-on);
  request 1 = SOFTWARE startup reason, returned as the completion code;
  control 6 = set the software reason for next boot.
  Factory-fresh = 105 ('i', deep restore): EStart formats C: when LFFS won't
  mount, Starter runs first-boot restore, then sets 100. ngvm's helper_request
  does request_complete(st, sw_reason) IMMEDIATELY.
So EStart queries HelperDrv for the startup reason and that value DRIVES the
boot path (first-boot vs normal). The LLE runs the real helper.ldd (ROM
0x50383e80; request-1 handler 0x503842e0 -> C++ virtual dispatch vtable+0x130)
and it NEVER completes the request. helper.ldd does NOT read board MMIO in the
window (checked) - it reads from memory / a kernel object, so the completion
is a kernel/driver-level event, not a board register.

This is the authentic N-Gage DEVICE-DRIVER layer. ngvm's chan.c models the
exact drivers EStart depends on: HelperDrv (startup reason), NOSDRIVER (modem
ISI; a request "waits until cancelled" = EStart's SIM-language query of a
modem that doesn't answer in time), LesterDrv/adspctrl (audio DSP). The LLE
runs the real drivers but they wait on hardware/kernel events the board/
synthetic-NOS never provides. THE FIX PATH: model these driver completions the
way ngvm's chan.c does - starting with HelperDrv request 1 returning a startup
reason (105 first-boot), then NOSDRIVER's request-cancel behaviour. This is
the first time the block is traced to a NAMED, ngvm-MODELLED driver with a
known expected completion - the clearest actionable path of the session.
Resume base idle-c1517 (at the block). cdrive-populated-4mib.img available.

## 2026-10-30 Block fully traced to EStart's async function-2 to a file-server CAsyncNotifier; ngvm's EStart exits cleanly (update made with Claude)

Full reverse from the waiting thread, with handles/functions decoded:
- 1515094 SendReceive handle 0x400d0001 function -1 (connect) -> ACCEPTED
  (server CServer::RunL + CSharableSession::CreateL create the session).
- 1515132 SendReceive handle 0x400d0001 function 2 (async, status reused
  0x00501e90) -> routed to a file-server-hosted server: CServer::RunL ->
  efile CMountCB::SetDiskSpaceChange -> euser CAsyncNotifier::Notify. The
  server HOLDS this request (async notification) and never completes it.
- 1516657 SendReceive handle 0x400f0001 function 23 (the C: LFFS write) ->
  SYNCHRONOUS, completes at 1517603 (write done, file server returns to
  WaitForAnyRequest).
- EStart's final exec 0x4d WaitForAnyRequest (1517603360) then blocks: its
  only outstanding, never-completing request is the function-2 CAsyncNotifier.

ngvm (same EStart.exe) shows EStart EXITS cleanly (type 0 reason 0) - so the
function-2 request COMPLETES in ngvm's HLE F32 but not against the LLE's real
F32/ELOCAL. ngvm's drive.c completes C: writes synchronously (program() then
request_complete) and keeps media-change notifications "pending" (never fire
for C:). So the LLE gap is one real-F32 async notification/completion that
ngvm's HLE does implicitly. The medint pre-write-return call ekern!ord495+0x218
(0x5033a1dc) is a C++ virtual dispatch (LDR PC,[r12,#0x28]); unit-60 IRQ was
tested as the completion and ruled out (fires+acks, no effect). Ruled out:
flash device, unit-60, NOS readiness, C: content, RTC/timeout (no RTC reads at
the block; 5e9-cycle run byte-identical). THE LLE FIX is the specific F32/
ELOCAL async-completion for EStart's CAsyncNotifier request - needs tracing the
real CAsyncNotifier/ELOCAL C++ dispatch to the DFC/event it awaits, then
providing it. Resume base idle-c1517 (at the block); fresh-c1250 (EStart
ready). This is the precise, named frontier; the completion is the one unknown.

## 2026-10-30 ROOT CAUSE: flash-write completion is an EPBUS interrupt; my unit-60 fires on source 0x60 which has NO handler (update made with Claude)

Drilled the real mechanism. EStart blocks INSIDE RFs::SetEntry (func-23, the
bootdata write): after euser!TBusLocalDrive::Write, the FILE SERVER itself does
User::WaitForRequest (exec 0x4d) - the drive write is ASYNC and the file server
waits for medint's completion that never fires. So SetEntry never completes and
EStart (blocked inside SetEntry) never returns.

The completion is INTERRUPT-driven. Disassembled the ISR dispatcher (0x5032287c):
source index = ICU_bank0_current + 0x5c (bank1 +0x7c, bank2 +0x9c). The
registered interrupt handlers (table at 0x80000b64, from idle-c1517) are:
  src 0x5d/0x5e/0x63 -> ekern; src 0x72/0x74/0x75 -> **epbus!ord31** (shared obj
  0x80405d8c); src 0x76 -> cbus. medint has NO handler of its own - the flash
  (C:) is an EPBUS peripheral, and the write completion is an epbus interrupt.
My "flash timer unit-60" model raises ICU bank0 = 4 -> source 0x5c+4 = 0x60,
which has NO handler (table[0x60] = garbage 0x0000e007). That is why the unit-60
experiment fired+acked but never completed the request. The firmware, during the
write, only writes 0x0c120a64=2 / 0x0c120a70=0x186 / 0x0c120a68=0 (the flash-
program command to the epbus-managed timer) and then WAITS for the epbus IRQ -
no ICU enable, no status poll.

THE FIX (LLE): model the flash-program completion as an EPBUS interrupt. When
the firmware writes the program command to 0x0c120a64, after the program delay
raise the correct epbus source (0x72/0x74/0x75 = ICU bank0 0x16/0x18/0x19) and
provide the 0x0c120a60/epbus status the epbus ISR (epbus!ord31) reads, so the
ISR -> DFC -> medint completion -> file server wakes -> SetEntry completes ->
EStart returns and proceeds. NEXT: identify which of 0x72/0x74/0x75 is the flash
timer and what epbus status the ISR reads (disassemble epbus!ord31 ISR + the
epbus obj 0x80405d8c). The whole earlier "unit-60 -> source 3" hypothesis
(provenance flash-program-timer) is WRONG; this epbus-interrupt path is the real
one. Resume base idle-c1517.

## 2026-10-30 Interrupt dispatch fully mapped; my tick (0x5d) works, UEM/unit-60 land on disabled/no-handler sources (update made with Claude)

Dispatcher detail (0x5032e730): handlers are a CHAIN; a source's ISR runs only
if handler_obj[+4]==1 (enabled) and is called as PC=[[obj+0x10]+8]. ISR funcs:
cbus src 0x76 -> 0x50382498 (reads CBUS status); epbus src 0x74 -> 0x503f566c
(epbus!ord56+0x164c). My board's ICU current (0x0c120114) mapping vs the
0x5c-offset source index:
  tick ICU=1 -> src 0x5d (ENABLED at block, WORKS - that is why the tick fires)
  UEM  ICU=2 -> src 0x5e (DISABLED at block, obj[+4]=0 - UEM IRQ never handled)
  unit60 ICU=4 -> src 0x60 (NO handler, table[0x60]=garbage)
At idle-c1517 only src 0x5d (tick) and 0x76 (cbus) are enabled. So the flash-
write completion interrupt is on a source that is enabled only WHILE the write
is in flight; by the block it is disabled again. NEXT: trace medint's interrupt-
enable during the write (ord418/416/421 calls at 1517595874+) to read the exact
source number it binds/enables for the flash completion, then raise THAT source
(ICU = src-0x5c) from the board after the flash-program command, with the epbus/
cbus status its ISR reads. This replaces the wrong unit-60/source-3 model.


## 2026-10-30 Only sources 0x5d (tick) and 0x76 (cbus) are EVER enabled; flash completion must be the CBUS/UEM interrupt (update made with Claude)

Checkpointed mid-flash-program (1517596800) and mid-write: the ONLY enabled
interrupt handlers (obj[+4]=1) throughout are src 0x5d (tick, ICU=1) and src
0x76 (cbus/UEM ISR 0x50382498, ICU=0x1a). The epbus srcs 0x72/0x74/0x75 and
UEM src 0x5e are never enabled. The tick (0x5d) fires regularly but its ISR
only touches unit 0 (0x0c120a08/a10), not unit-60, so it does not complete the
drive write. Therefore the deferred drive-write completion is the CBUS/UEM
interrupt (src 0x76): the N-Gage NOR flash program is gated on a UEM/CBUS
power/ready event, and the cbus ISR completes medint. medint makes NO Kern::Add
(DFC) and NO RequestComplete in the write path - it is purely interrupt-driven.
My UEM IRQ model fires src 0x5e (ICU=2, DISABLED) - wrong; the real one is src
0x76 (ICU=0x1a). TESTING: flash completion -> ICU=0x1a (src 0x76 cbus); run
boot-v15-cbustest from fresh-c1250. If the cbus ISR needs CBUS status, the sim
error names it (discovery loop).

## 2026-10-30 Flash-completion is an async event medint never signals; src 0x76 ruled out; write goes via ecust (update made with Claude)

Ruled out the cbus source empirically: unit-60 -> ICU=0x1a (src 0x76) made the
cbus ISR run 738x (flooding, since it acks via CBUS not the unit path) but ZERO
RequestComplete - the cbus ISR does not complete the drive request. So the flash
completion is NOT cbus, NOT the tick (unit 0 only), NOT epbus (disabled), NOT
unit-60/src-3 (no handler). medint writes the NOR data (0xffbc -> 0x024214dc)
then RETURNS WITHOUT completing and runs 0 times after - it set up an async
completion that never fires. ngvm completes C: writes SYNCHRONOUSLY (rw() ->
program() -> request_complete); the LLE real medint is async and waits for a
hardware program-done event. The write path runs ecust (N-Gage custom kernel
extension, 0x50348750) + one nosdriver call + TInactivityLink::Start. So the
completion likely depends on ecust/custom-hardware (the flash+baseband shared
bus) that the synthetic NOS cannot provide - the long-flagged synthetic-NOS
wall, now localized to the LFFS metadata write completion. Next: ecust MMIO
reads during the write (wrong read -> medint skips completion?). Clean model
restored (unit-60 reverted to src-3/masked).

## 2026-10-30 COMPLETE driver-interaction understanding: the C: write completion mechanism (update made with Claude)

Full driver stack for the blocking bootdata write (RFs::SetEntry), reversed:
  EStart RFs::SetEntry (async) -> file server CServer::RunL
   -> ELOCAL.FSY (C: LFFS): computes block/offset (elocal!ord1, _udivsi3),
      calls euser!TBusLocalDrive::Write (ASYNC, status 0x80601a6c on the file
      server stack)
   -> medint (NOR flash local-media PDD): writes the AA/55/A0 program + data
      (0xffbc -> 0x024214dc, served), arms the 0x0c120a60 'unit-60' timer
      (control=2, compare=0x186), coordinates with:
       * ecust (N-Gage custom kernel extension, 0x50348750): read-modify-write
         of power/clock-gating bits in the boot latch 0x08000014 (0x200000 set,
         0x20000 toggled) - gating the flash/baseband shared bus
       * nosdriver (baseband) - one call; TInactivityLink::Start
   -> medint RETURNS without completing, runs 0x afterwards. The async
      completion (program-done) never fires.

The F32 request (status 0x80601a6c) is never RequestComplete'd by ANYTHING -
confirmed: 0 RequestComplete, 0 Kern::Add(DFC) in the write path, and every
interrupt source ruled out empirically (cbus 0x76 floods with no complete; tick
0x5d services unit 0 only; epbus 0x72/74/75 disabled; unit-60 src 0x60 no
handler). ngvm sidesteps this entirely: its HLE drive.c rw() completes C: writes
SYNCHRONOUSLY (program(); request_complete()).

CONCLUSION: the LLE's authentic medint NOR-program completion is an async event
delivered through the ecust/baseband-shared-bus custom hardware. The synthetic
NOS (zeros) and the unmodeled custom-bus/program-done event mean nothing signals
the completion, so the write request hangs, SetEntry never returns, and EStart
blocks forever at cycle 1517595533. This is the synthetic-NOS / custom-hardware
wall, now localized to the exact instruction. To pass it in the LLE either (a)
find how ecust/the custom bus signals program-done and model that event, or (b)
the real NOS/baseband plaintext (exists in no available file). The boot reached
an authentic LFFS bootdata write at ~1.52e9 - ~+750M cycles past the session-
start crash; this is the deepest, most precisely-characterized frontier.

## 2026-10-30 EXHAUSTIVE: no interrupt/DFC/poll completes the C: write; unit-60 timer has no handler - custom auto-completion (update made with Claude)

Final checkpoints (right at the timer arm 1517596100, mid-program 1517596800,
mid-write 1517587001): the ONLY enabled interrupt handlers throughout are src
0x5d (tick, services unit 0 only) and src 0x76 (cbus, floods with no
RequestComplete). The firmware NEVER registers a handler for unit-60s source
(0x60) and never reads the unit-60 timer (0x0c120a60) after arming it - so the
0x0c120a60 timer is neither polled nor interrupt-handled. medint writes the NOR
data, arms this timer, and returns without completing; nothing (no IRQ, no DFC,
no poll, no RequestComplete) ever completes the file-server drive-write request
(status 0x80601a6c). The keypad reads 0 (no activity resetting any inactivity
timer). So the NOR-program completion is a CUSTOM HARDWARE auto-completion
(ecust/0x08000014 power-gating + the 0x0c120a60 program-timer + the baseband-
shared bus) that signals program-done through a path this board does not model
and the synthetic NOS cannot provide. This is the definitive wall, fully
localized. Passing it needs either (a) reverse-engineering the exact ecust/
custom-flash-controller program-done signal and modeling it (the 0x0c120a60
timer behaviour and what consumes it is the key unknown), or (b) real NOS/
baseband plaintext (in no available file). All interrupt-source and DFC
hypotheses are now empirically eliminated. Boot reached authentic LFFS bootdata
writes at ~1.52e9, ~+750M cycles past the session-start crash.

### 2026-11-03: associative cache bank prototype

The standalone cache bank combines the ARM920-shaped tag and data prototypes and blocks a dirty replacement until its caller acknowledges write-back. Its focused test covers victim address and data, stalled refill, and replacement. The caller must keep the requested address stable through this transaction; bus control and acknowledgement validation remain to be implemented. This prototype is not connected to ZAP, has not been checked for FPGA RAM inference or fit, and does not fix the CPU cache yet. The CPU-level associativity test remains an expected failure. Next: design the bus-side transaction controller and CP15 maintenance before integrating the new bank. No firmware simulation was run.

### Bluetooth identification (2026-11-03)

N430 is Nokia LRB2_0630271, with CBUS, UART, sync and interrupt wired to UPP. See `docs/bluetooth.md` for schematic pins, related public references, and limitations. An isolated no-radio HCI responder and directed tests were added; it is **not connected** to the board and does **not** establish a fix for the previous Bluetooth timeout. The previous overnight run used a frozen board and CPU; a fresh simulator must explicitly combine the current CPU with that more complete board model instead of silently reusing the frozen binary.

The current CPU plus the preserved full board model now compiles via `python3 scratch/current-boot/build.py`, producing `build/sim/obj-current-boot/Vngage_cpu_sim` and a source-hash manifest. The build copies the frozen board into `scratch/current-boot/board`, adjusts its stale modem-header path, and includes existing modem and NOS support code. No firmware simulation has been run with this binary, and the old overnight runner still selects the frozen binary; do not use that runner for a current-CPU boot until adapted.
