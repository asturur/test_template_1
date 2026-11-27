# Previous master experiment checkpoints

Source `0f6113fe40d4bb12267ff00d348f54e38c74e218`. These entries describe the earlier CPU lineage. Current development uses the v5 source tree.

## 2026-11-18 — Game audio and writable MMC before CPU speed work

Master owns both fixes. The two branches share the audio and MMC implementation.
Keep each fix in a separate master commit, then apply those commits to
`ngage-v5` and run the same tests with its ARM9V2 CPU and caches.

1. **MMC on master passed.** Original FExplorer copied the 374-byte README
   into `E:\WRITE_TEST` on archived fit `1928aee` at 78 MHz. The Linux image
   contained the exact bytes, with two matching FATs and just four expected
   changed sectors. A fresh Main and guest mount reopened and read the file.
   The offline original FAT replay also passed a four-sector write, independent
   reopen and read-only rejection. Retain the existing write path and apply
   the same verification on v5. [Evidence and runner](mmc-write-diagnosis.md)
2. **Game audio on master.** Original NEM-4 Sega Rally supplies 720-sample
   mono buffers at 16 kHz. The first `0x23` submission is followed by `0x27`
   refills after reply `0x24`. The 78 MHz PCM candidate passes the original
   samples, signed stereo, register/completion and shared SDRAM checks in
   simulation. The exact-ROM send callback, reply route and deferred work
   ring pass. The game exits and relaunches with nonzero audio on both
   launches under the reference kernel. On physical MiSTer the stock NOS
   route delivered 119 start replies and the original SoundDevice
   submitted 119 first buffers. The native bridge now handles the shared
   timer-5 IRQ and produces 48 kHz WAVs from the physical Sega Rally menu,
   Desert race, and a full game relaunch. LCD DMA overlap is observed.
   The FExplorer copy read back exactly, with PCM and MMC overlap still
   measured only in the production-RTL fixture. The fitted PCM-on variant
   adds 410 ALMs and moves worst 78 MHz setup from −0.868 to −1.598 ns.
   Both fits miss the timing gate.
   [Capture, candidate and reproduction](game-pcm.md)
3. **Port and qualify.** Apply the master commits in the existing v5 worktree.
   On each CPU, exercise playback during a save and rendering, remount and
   check the saved bytes, then fit the exact revisions used. Record simulation
   and MiSTer results separately. Resume CPU speed experiments after the
   functional checks on both builds.

[Master implementation](codex://threads/01a1eb21-2161-7180-b9a8-4323913fe9f2) ·
[v5 port and verification](codex://threads/01a1edd3-0b7a-7171-9e56-4780bb15576b)

## 2026-11-18 — Retain indexed STRH credit on the refined frontend

Applying only the previous STRH credit extension to the verified
4,805-clock frontend drops the original Sega Rally fill to 4,200
clocks at both waits. There are still 2,567 retirements and 512 checked
ordered halfword writes. Of 960 saved store-hold clocks, 356 reappear
as empty operand-stage time. Useful MOV dequeue spans 603 fewer
clocks. The Sega textured span drops from 32,902 to 31,942. The full
scan remains at 5,176,864 and 5,308,282. All 42 matched workload
comparisons and CPU/MMU checks pass. The directed guest checks
both lanes, load-sourced store data, one serialized uncached write,
and translation, permission and alignment aborts with no new issue.
Both sources preserve the existing word-aligned FAR on the two
translation-class faults. The prior 1.4% matrix cost belongs to the
refined frontend. Keep the store candidate and the one-file I-cache
overlay independently reproducible. Routed timing is unmeasured.
[Scorecard, clocks and qualification](cpu-icache-strh.md).

## 2026-11-18 — Retain isolated resident I-cache streaming overlays

Preserving the two completed I-cache lines across an ordinary resident
hit cuts the original 512-pixel Sega fill from 9,311 to 5,473 clocks.
Selecting the next checked PC during invalid request cycles prevents
old fallthrough lookahead from overwriting the backward target slot
and cuts it to 4,805 at both waits. The full Sega scan falls to 5,176,864
and 5,308,282, with the same 1,427,984 retirements and memory effects.
Both overlays pass all 42 matched workloads and keep 224 starts in
224 clocks on the favorable ARM stream. The first overlay has no elapsed
regressions. The second adds a 1.4% matrix cost and improves original
JPEG by 2.2%. Resident alternate-line, revocation, CPU/MMU and interworking
checks pass. Routed timing remains unmeasured.

The three predicted-target launch bubbles still occur upstream. The
faster fetch fills the FIFO and leaves 54 empty operand-stage clocks,
down from 4,563. The original STRH still accounts for 1,635 data-hold
clocks in the full fill. Revisit store completion on the faster frontend
before choosing another global fetch change.
[Matched scorecard and qualification](cpu-icache-stream.md).

## 2026-11-18 — Sega Rally fill gap traced to instruction delivery

The stock donor receives one instruction every clock and runs the five
original instructions in five clocks per steady iteration. The tagged core
predicts the same backward target but leaves three clocks with no fetch
request while launching it. On crossing to CMP and on returning to MOV,
each already-resident line takes another five clocks through the
serialized I-cache reply. All 511 matched fetch recurrences in both wait
profiles show these same 13 clocks. Of the 6,715-clock whole-window gap
at 0:0, 6,630 come from the 510 regular executed iterations. This explains
why the STRH credit moved ADD earlier while the next MOV arrived on the
same edge. Evaluate continuous delivery of the two resident I-cache
lines and the correctly predicted backward target as the next CPU question.
[Exact fetch timeline, state sequence and clock audit](cpu-sega-fill-fetch.md).

## 2026-11-18 — Reject indexed STRH store credit for Sega Rally fill

The retained tagged control, isolated store-credit extension and stock
ngage2 agree on the original 512-pixel fill, 2,567 retirements and every
ordered halfword write. Both mainline variants take 9,311 clocks at
0:0 and 2:9. The donor takes 2,596 and 2,628. The extension releases
480 resident stores two clocks sooner and advances the independent ADD
by two clocks on each of those pixels. All 960 saved store-hold clocks
reappear as empty operand-stage clocks and the next iteration starts on
the same edge. Forwarding the shifted index produces zero store operand
locks. The tagged core has 1,958 empty clocks between taken BLE dequeue
and the next MOV across 511 transitions. The donor takes one clock across
each of those boundaries. Keep the STRH overlay isolated. The measured
backedge-delivery opportunity alone leaves a fixed-trace budget of 7,353
clocks on the tagged core, above the 4,655-clock 2× target.
[Matched timelines, masks and attribution](cpu-sega-fill-store.md).

## 2026-11-18 — Retain isolated state-tagged fetch

The next master experiment isolates the original five-instruction Sega Rally
fill. The tagged core takes 9,311 clocks for 512 pixels against 2,596 on stock
ngage2 at zero extra waits. Both retire 2,567 instructions. Sol is testing
whether the independent counter increment waits for the preceding resident
register-offset halfword store. The first comparison measures that delay
separately from index forwarding and branch delivery. A material store wait
would justify testing the existing resident-store path on this instruction.
[Master experiment](codex://threads/01a1eb21-2161-7180-b9a8-4323913fe9f2).

The exact banked, third-slot and qualified Thumb combined baseline and stock
ngage2 were compared on identical original workloads. At 0:0 the full Sega
Rally scan takes 8,111,262 clocks on the combined core and 3,471,563 on the
donor. Cross-state BX intervals account for 2,404 of their 6,509-clock gap
in the same 52 pixels. Carrying ARM/Thumb state with predictions cuts the
full scan to 5,375,298 clocks at 0:0 and 5,506,714 at 2:9, a 33.73% and
33.19% reduction with unchanged original retirements and ordered writes.
Another 1,319,667 and 1,385,374 clocks must go to reach 2×. The same-address
wrong-state branch test, precise Thumb abort, 34 CPU diagnostics including
IRQ and predication, and all 42 workload comparisons pass. The overlay
stays isolated and routed timing is unmeasured.

The original Sega textured span takes 32,908 clocks on the combined and
tagged cores versus 15,990 on the donor at 0:0. Original Thumb JPEG takes
80,473 combined, 80,379 tagged and 36,251 donor. The matched Asphalt trace
locates a separate warm D-cache gap. Its independent offers are 12 clocks
apart versus seven on the donor, and the second load to dependent ORR takes
11 versus four. Continue with resident-load latency and dependency timing.
Andrea reports 224 versus an expected 500 at 104 MHz. If the index scales
with throughput, that corresponds to 55.2% fewer clocks. The native phone
comparison remains pending.
[Full scorecard, absolute timelines and native comparison method](cpu-state-tagged-fetch.md).

## 2026-11-18 — Matched banked third-slot fit archived

Existing run `44258633306` on published `1928aee` completed. The 178
effective input hashes match the expected manifest, with exactly two
changes against banked control run `44160843231`. Seed 42, debugger,
physical PLL, all eight scenario clocks and timing constraints match.
Both pass the sixteen SDRAM DQ register checks. The third slot costs
456 whole-design ALMs and 30 LABs, with unchanged 514 M10Ks. Direct
D-TLB bookkeeping rises by 109.2 ALMs and 92 fitted registers. Worst
78 MHz setup slack goes from -0.639 to -0.743 ns, now on reset-drain
to D-cache MVA. Min hold remains positive, and worst 104 MHz setup
is -3.948 ns. The RBF and reports are archived with a failed timing gate.
Combined-source smoke reproduces the warm gains. Keep the slot as a
performance candidate while addressing routed timing.
[All eight corners, area and artifact identities](tlb-banked-third-fit.md).

## 2026-11-18 — Retain isolated early ordinary Thumb loads

Experiment 2 freezes exact unbanked 5L and enables private lookup, early
P1 offer and registered late ADD/CMP pickup for aligned immediate and
SP-relative Thumb word loads. Four checked JPEG cases use 2.83–3.03%
fewer clocks. The Sega Rally full scan with original FbsCli uses
2.12–2.15% fewer clocks. The other fixed-work cases match, including
six SPMark/GLES kernels and 224 ARM starts in 224 clocks. All 1,051
matched successful JPEG reports of late pickup shorten the dependent
ALU interval by two clocks and the retirement interval by one.
Exact fault with accepted younger flag writer, both instruction phases,
cold retry, state switching and 32 matched CPU diagnostics pass. The
Thumb overlay stays isolated pending a routed timing comparison.

Separately, published banked-plus-third-slot `1928aee` matches the
unbanked third-slot JPEG, Monkey Ball and ARM stream medians at both
wait profiles. Exact banked controller test sees 1,600 delayed-fill
edges and rejects a stale third-slot grant when commit revocation is
suppressed. [Scorecard and verification](cpu-thumb-early-load.md).

## 2026-11-17 — Retain isolated third D-side mapping for a matched fit

Experiment 1 uses exact published 5L `0c380ab` and a two-file D-only
overlay. Both original Monkey Ball spans reproduce 34,995 / 34,920
clocks and improve to 31,052 / 31,007, including the separate-small-page
layout. Scored D searches are 1,536 → 9 against the empty FIFO's
1,537 → 10 prediction. Sega span improves 11.05%, Asphalt's
two-lookup loop 6.92%, and the complete Sega scan with original FbsCli
calls and a synthetic checked bitmap cursor 0.63–0.64%. Matrix uses
7.56% fewer clocks and the six-kernel throughput geometric mean is 1.01608×
in both synthetic wait profiles. Four separate JPEG cases use 1.51–1.81%
fewer clocks. All 21 cases match or improve in both profiles. The ARM
stream retains 224 starts in 224 clocks. Matched CPU/MMU checks pass,
including the exact third-slot denial and stale-grant negative.
Cost is 65 declared bits, one tag compare and an additional priority
choice on the D hit path. Physical area and timing are unmeasured.
[Complete A/B scorecard and decision](cpu-third-data-mapping.md) ·
[Reproducer and isolated RTL patch](../tests/cpu/tlb_three_mapping/README.md).

## 2026-11-17 — CPU speed review after 5L

In the saved 5L pixel trace, 18 complete pixels spend 144 of 1,227 clocks
with both a data hold and a translation-busy demand. A FIFO replay of all
4,608 addresses per pattern gives 1,537 misses with two 1 KiB local mappings
and 10 with three. The fixture uses a single 1 MiB section. Recommend a D-only
third-slot experiment with a separate small-page control. The original Thumb
JPEG block also executes 5,088 ordinary immediate/SP-relative word loads
outside the early-load class, including 1,147 directly feeding ADDS or CMP.
Recommend testing those Thumb loads separately. These are trace findings and
proposals. The matched-fit decision remains with its existing owner.
[Analysis and reproduction](cpu-speed-review-5l.md).

## 2026-11-17 — GBA CPU reference reviewed

Pinned GBA_MiSTer CPU at93790a: independent fetch/decode, serial execution,
explicit registered arithmetic stages; ordinary immediate ADD has a derived
five-clock minimum acceptance interval. Guest cycle charges are separate from
physical clocks. No demonstrated superior DSP mapping, BRAM RF, predictor or
ARM920 memory overlap. Keep current TLB fit priority. Deferred original idea:
screen fitted shifter cost, then consider sharing shift networks at unchanged
latency if justified. Source review only; no production RTL/hardware/build
changes. [Comparison and evidence](gba-cpu-ideas.md).

## 2026-11-17 — MMC write failure remains a hardware diagnostic task

Operator reports writes still fail; active RBF/image/operation uncorrelated.
Existing actual-HPS tests verify outgoing bytes and independent modeled
persistence/remount, not Linux file I/O. New isolated authored-ARM CMD24/TX2
DMA/full-board/card/adapter test passes297511clocks,4reads/1write,512 stored
bytes plus PIO readback and all adjacent/footer guards. Deliberate persisted
last-halfword corruption rejects even after cached readback. No production
RTL defect demonstrated; no MMC area rewrite, board/card mutation or release
fit changes. Historical installer manifest has CSD WP but is not tied to the
current failure. Next obtain installed identity and failing CMD24/25 R1, then
the first missing data/HPS/persistence milestone. Own generated build retired;
compact receipts and reproducible synthetic test remain.
[Diagnosis and observation sequence](mmc-write-diagnosis.md) ·
[Machine evidence](evidence/mmc-write-diagnosis-20261117.json).

## 2026-11-17 — Matched 5L / banked-TLB builds

Exact qualified 5L published as `0c380ab9bae92916d297b72d6a303d251f1d49d9`;
[control run44155992918](https://github.com/asturur/test_template_1/actions/runs/44155992918).
User explicitly approved public push and concurrent banked build after stopping
monitoring. Exact qualified banked source published as
`613a3d62abee103660a2475df4abec89e64b1542`;
[banked run44160843231](https://github.com/asturur/test_template_1/actions/runs/44160843231).
Both runs confirmed in progress on their immutable SHAs at dispatch verification.
Both use seed42/debug-on, unchanged production78MHz PLL and178 selected inputs;
only the expected seven selected RTL hashes differ. All60 qualified hashes and
patch0082 byte replay PASS before publication. Both remote names resolve to the
same public repository. No active follower or monitoring; wait for the user to
report completion before collecting/comparing. No hardware deployment or5M.
Other chats’ files and runs remain preserved. Publication receipts prevent
accidental duplicate dispatch.
[Matched-fit report](tlb-matched-fit.md).

## 2026-11-17 — Banked main-TLB area prototype retained for matched fit

Actual5K baseline40834/41910ALMs,502/553M10Ks,4190/4191LABs; I/D main banks
2027.1+2068.8=4095.9directALMs. Compared independent MMC2137 and cachemetadata
3453.7directALMs without summing parents/children. One chosen prototype keeps
both64-entry mixed-size TLBs:8comparisons/row, BRAMtags, atomic overlap commit,
queued mutation/CP15busywait andcontext-cancelled installs. No5M or arithmetic/
issue optimization. Passive exact5L counts matrix160I/801D and JPEG796I/1219D
fullsearches per scoredwindow; exposedunions1904/3972clocks. Corrected selector
capture proves scoredhitsrow0; initial allrow7 histogram was discardedbug.
FinalbankSHA952a5a9bebabe610d6ef3b07ccd9df4abc2b63aa0fa72ddb6d828f12f5b1eec3
passes strictVerilog2001 and full exact-source qualification. Bothprofiles/five
scoredwindows/twoequalrepeats/originaloracles/retirements/negatives: sixkernels,
JPEG84353,game34995/34920,streams343/499 and224starts224clocks unchanged. Cold
wrapper totals+40..112clocks; JPEG+58/+48. Later rows/misses2..9edges, mutation
drains8 andqueued14 observed.22matchedCPUdiagnostics pass; shortdataordering
381→455(+19.42%) at0wait, othercold/mutationcosts recorded. ProperFIQ/SWP/
translatedprefetch/forcedwrite-walkoverlap and5Lflag/IRQ/fault/MMIOsafety pass.
Fiveunits plus867-query original-table equivalence with poisonedRAM,329laterrow
hits,50queuedmutations/50cancelledinstalls pass twice;8entrytruncationnegative
rejects. Delayed-fill local-slot rule and declaration-order issues corrected;
no failing assertion waived. Sourcebankstate1744→324 (−2840bits/pair), but
ALMsaving1000–2500 and+10–16M10Ks are **unfitted estimates**:512–518/553used,
35–41remaining. No trusted configured localQuartus or CI fit; matched5Lcontrol/
5L+bank seed42/debug-on/178input/78+104corner plan documented. Retain offline
for physical measurement, do not promote. Production60CPU/header andMMC hashes
unchanged, master/public/history/5L/5M/other runs preserved. No hardware/donor
runs. Own completed compiler/source/private-derived outputs retired; compact
receipts/logs and reusable tests remain.
[Area/latency alternatives, proof and fit plan](tlb-area.md) ·
[Machine evidence](evidence/tlb-area-20261117.json).

## 2026-11-17 — Sega Rally original race payload captured

357 passive snapshots from countdown into racing, 89.5 seconds at 78 MHz. 128 fetch PCs in the game, 227 in firmware. Identified an independent pixel span and a full-screen loop with original FbsCli imports. Private app retained for later replay. [Profile and evidence](sega-rally-profile.md).

## 2026-11-17 — Step5M registered demand admission rejected; keep qualified5L

First completed exact5L broad six-original-workload qualification: no regression,
triangle23568→23520; separate evidence preserves attribution. Then one offline
5M permission-register experiment targeted saved5K CP15baddr→context/busy→
fast_hit/requestACK→retimedlate_p1_ready path13.073ns/11levels. Registered actual
request/PA/permission/fault plus a registered CP15change event breaks this source
cone without livewidecontext checks at token consumption. +165sourcebits;
no RAM/port/geometry/PLL change. Corrected retained-translation cancellation
exposed by direct context test; no second optimization. Final5M output/guards/
retirement/repeat/negative checks PASS bothprofiles, but span34995/34920→
39214/39289 (+4219/+4369), stream343→477 and224starts224→336clocks,
multiline499→514, guardedtranspose3441→3895; checksum239 unchanged. Span
read/write stalls account for every added clock; first-cycle hits wait for
admission and rawP2 fallback probing moves later. Reject this cut on useful-work
cost, not an artificial104MHz gate. Keep exact5L;5M is unpromoted research.
Actual Dcache/TLB new-context/maintenance/permission-denial/changed-address/
kill/invalidate negatives pass twice. ActualCPU flags/predicated writer/IRQ/
fault/MMIO safety passes twice0:0/2:9/0:97; eightfocuseddiagnostics pass;
missing response128held/zeroexecute and retry1/twoaccepts/oneexecute pass.
Unchangedcache collision-pressure evidence reused by exact modulehashes.
No5M JPEG/fullsix or fit after material regression; no timing/ALM gain claimed.
78MHz PLL/104MHz objective, production/public history and other runs untouched.
Own completed generated inputs retired; durable reproducible tests/evidence remain.
[Measured decision and traced boundary](cpu-load-admission.md) ·
[Machine receipt](evidence/cpu-load-admission-20261117.json).

## 2026-11-17 — Exact5L broad six-kernel qualification completed before5M

All60retained5L RTL/header hashes match prior game/JPEG/stream/safety receipts.
Promotedccba54f control reused with matching original programs/payloads/ROM/
harness/image. Both0:0/2:9, five scored windows/two equal repeats, original
outputs/oracles/retirements and six wrong-output controls PASS. Matrix45073,
canonicaltranspose3560, frame71259/201302, halfword1332 and byte1647 unchanged;
triangle23568→23520. No broad regression. Separate receipt recorded before
stacking5M; retain5L offline. Prior JPEG84353/game34995/34920 and directed
safety reused by exact hashes. No production/public changes or new fit.
[Independent broad receipt](evidence/cpu-late-operand-six-20261117.json).

## 2026-11-17 — Step5L late arithmetic pickup retained offline

Isolated original overlay on promoted ccba54f; production and the other chat's
5J/5K fit/release untouched. AL ADD/CMP with one unshifted source owned by a
starting P1 word load may enter Issue early, then capture its registered result
at the execute-operand boundary. Two state bits; no live ACK→ALU/issue path,
new RAM/port/adder or cache geometry/PLL change. Both original512pixel patterns
PASS both0:0/2:9: forward36528→34995 (68.349609375/pixel,−4.1968%),
reverse36453→34920 (68.203125/pixel,−4.2054%). 1534early accepts per pattern;
execute/retirement/next useful issue advance1 locally, load-lock−1534 plus
empty+1 yields actual−1533. First2 destination consumers arrive after P1.
Original bytes/oracles/full guards/source/stack,10240retirements,512actual
stores/mutations, repeats/negatives pass. Independent343/multiline499 and
transpose3441 unchanged; checksum271→239; originalThumbJPEG84353 unchanged.
All60promoted RTL/header hashes checked; compiler read51; only Core/Issue differ.
Precise flags/predicated-writer/WAW/IRQ/fault/MMIO checks PASS twice at0:0/2:9/
0:97; faulting producer's early accepted dependent never executes, saved SPSR
and destination preserved. Cold hold48/59/145clocks. Separate same-CPU controls:
missing response held128clocks, zeroexecute; injectedretry1/twoaccepts/oneexecute.
Eight focused CPU diagnostics PASS. Retain for broader full-kernel qualification
and timing, do not promote. Two muxes/new control fanout require actual timing;
78MHz PLL/104MHz target unchanged, area/timing unmeasured. No Quartus, CI,
hardware, donor or branch/worktree. Own completed generated inputs retired;
compact reproducible evidence/tests remain, other chats' runs/files preserved.
[Schedule and decision](cpu-late-operand.md) ·
[Machine receipt](evidence/cpu-late-operand-20261117.json).

## 2026-11-17 — Combined 5J/5K release fit completed and audited

Promoted/pushed exact ccba54f; published fit report feebc2f. Patch0080 replay and all60CPU input hashes match
qualified six kernels/JPEG and reused5K game/safety evidence. Public seed42/
debug-on run44123116917 compiled and produced RBF4,565,516bytes; SHA256
fc70703be9cbb41f16e1f644fd35adcf85ab68d301dce6644b418402d53ad1e0.
All178selected inputs and unchanged78MHz physicalPLL/BRAM verified,8routed
78/104 corners and16SDRAM DQ input/output/OE registers checked. Actual slow
78 setup−1.069/−1.019ns (5F−0.504/−0.550);104−4.274/−4.224ns
(5F−3.709/−3.755). All holds positive, minimum0.107ns. Artifact exists but
78MHz is not timing-closed; no deployment. ALMs40012→40834, registers45173→
45605; M10Ks502/DSP41/memorybits2760495 unchanged. Broader six-case simulated
geomean+0.5456%, JPEG unchanged; span~4% remains separate from routed timing.
Next proposed experiment: registered permission/admission ownership ahead of
resident response, targeting CP15o_baddr→fast_hit/completion→late_p1_ready
13.073ns/11levels/8.308nsrouting path while retaining useful starts/game gains.
No additional optimization or second fit. Only own completed simulator objects/
derived inputs removed; unrelated dirty files/private inputs preserved.
[Release, artifact and complete comparison](cpu-load-release.md).

## 2026-11-17 — Combined 5J/5K promoted; exact public fit running

Promoted exact qualified CPU as ccba54f60a2c6f4741e74428b3306a19717ea58d
on master and public asturur/test_template_1. Patch0080 pristine replay PASS;
all60frozen RTL/header hashes match game/safety, broader six-kernel and JPEG
simulation inputs. Matrix45736→45073, transpose3591→3560, triangle23790→23568;
frame71259/201302 and tails1332/1647 unchanged, both0:0/2:9. Original program
hashes/oracles, five scored windows/two repeats/retirements/negative controls
PASS. Separate original Thumb JPEG84353 unchanged in both profiles. Six-case
geometric throughput1.005456× versus matched5F; game/stream gains remain
separate. Scoped8-file publication excludes unrelated dirty files and private
inputs/derived code/disassembly. One requested seed42/debug-on fit44123116917
runs at exact ccba54f; physical78MHz PLL unchanged. Matching5F fit44082419726
reports collected (78MHz slow corners already−0.504/−0.550ns). Await routed
78/104 setup/hold,178input manifest, SDRAM register/area/RBF audit. No hardware
deployment. Completed simulation compiler trees/derived inputs retired only
for these new qualification runs. See docs/cpu-load-release.md and local
build/fit/combined-5jk-20261117/qualification.json.

## 2026-11-17 — Step5K earlier resident lookup advances real span consumers

Production remains exact8e70b1e5F. One bounded addition to 5J's core-only
overlay presents the existing registered ALU EA to the private probe one clock
earlier, retaining current P1-memory priority, actual demand permissions and
existing collision/revoke/response ownership. No new state, RAM port or adder.
Fresh 5F/5J/combined matched runs PASS both0:0/2:9, five scored samples/two
equal repeats and zero scored external traffic. Original512pixel forward
38063→36528(74.341796875→71.34375/pixel,−4.0328%); reverse37988→36453
(74.1953125→71.197265625/pixel,−4.0407%). All512occurrences of each of three
load/consumer pairs in both patterns advance one clock: typical use7→6,
BRAMread5→4 andACK6→5. Read stalls−1536, first backedge delivery empty+1,
net−1535. Original10240retirements,512actual stores/RAM mutations and guard/
source/stack checks retained; final cache write completes before window end.
5J one-line stream343 and224starts/224clocks preserved. New eight-line stream
5F627/5J619→499, steady224starts452→342clocks; dependent checksum303→271.
Guarded original transpose3443/3441→3441. All36negative outputs reject.
Extended CPU stall/IRQ/precise fault/flushed-MMIO/store→fresh-load checks pass
on all three variants; actual collision-poison cache pressure and eight focused
ARM/Thumb/FCSE/prefetch/return diagnostics pass. Only overlaycore differs;
all60frozen RTL/header inputs recorded, actual compiler read set51.
Retain combined prototype for broader workload/timing qualification. PLL78MHz/
design104MHz unchanged, timing/ALMs unmeasured; no production adoption,
hardware, donor, CI, Quartus or branch/worktree. Own generated compiler/source/
binary inputs retired after hashes; compact receipts and reusable overlay/test
remain, other chats' files and runs preserved.
[Schedules, three controls and decision](cpu-load-lookup.md) ·
[Machine evidence](evidence/cpu-load-lookup-20261117.json).

## 2026-11-17 — Step5J isolated P1 load-start prototype measured

Production remains exact8e70b1e5F. One core-only overlay permits an eligible
registered P1 load to start while older P2 has no memory/redirect/exception,
then transfers the identical owner to P2 with the existing completion slot.
No added state, address arithmetic, ports or cache geometry. Favorable resident
load/independent-ALU stream598→343cycles, fixed224architectural starts448→224
clocks and matching retirements446→224: instructionII2→1, loadII4→2. All256region PC starts/
retirements and128owned load values checked. Both original512pixel patterns
remain38063/37988cycles(74.341796875/74.1953125perpixel), both0:0/2:9.
Destination-bias/source-base/bound loads offer5→4 but BRAMread stays+5,
ACK+6 and useful consumer+7 unchanged;2048earlier span offers are not gains.
Original-layout transpose3591→3560, matched added-guard layout3443→3441:
wrapper/warm-state sensitivity retained, no universal31clock claim.
Five scored samples/two repeats/original references/negative outputs/guards,
exact retired PC streams/actual RAM mutation and byte counts PASS. Both final
executables pass cold-load stalls, IRQ, exact FAR/FSR fault, destination sentinel
and younger/flushed MMIO exclusion; same candidate CPU passes eight focused
ARM/Thumb/FCSE/prefetch/return diagnostics. One conditional throughput path
demonstrated; retain as research, no production adoption or timing claim.
Next dependent-load work needs earlier registered ALU-address lookup/owned
BRAM response and explicit port/backpressure contract, not another request-only
advance. PLL78MHz/design104MHz unchanged; no donor/hardware/CI/Quartus/branch.
Only own completed generated build/source/binary inputs retired after hashes;
compact receipts, synthetic assembly and maintained overlay/test preserved.
[Schedules, guarded/legacy measurements and decision](cpu-load-pipeline.md) ·
[Machine evidence](evidence/cpu-load-pipeline-20261117.json).

## 2026-11-17 — Step5I original Super Monkey Ball span benchmark completed

Exact8e70b1e5F retained. Original app SHA verified; original80-byte span runs
unchanged with explicit entry/fallthrough exit and bounded synthetic inputs.
512pixels/10240retired original instructions: forward38063cycles(74.341796875/pixel),
reverse37988(74.1953125/pixel), both0:0/2:9. Two warm-ups/five equal scored
windows/two equal repeats per pattern/profile; zero scored external traffic.
Independent per-pixel math+Unicorn, complete output/guards/source/stack,
512ordered stores/actualRAM mutations/retirements and real corrupted-output
rejection PASS. Last cache write ends22clocks before final original branch
retirement; one killed next-iteration dequeue is excluded from retired work.
Typical73-clock iteration, source relookup+5 and destination crossing+3
in measured representatives; only18full-window empty-operand clocks.
Full-window MLA has2048nonoverlapped busy clocks, including512exposed S2
accumulation holds. Recommend one future registered-product+addend capture in
S1, skipping S2: conditional512clocks(~1.35%), not measured elapsed savings.
All60frozen RTL/header hashes match accepted/master; actual compiler journal
reads51. No productionRTL change, prototype, donor job, hardware, Quartus,
fit or branch/worktree. Own completed compiler trees/derived inputs retired;
compact evidence and reusable test retained; other chats' files/runs preserved.
[Benchmark and decision](super-monkey-ball-span.md) ·
[Machine receipt](evidence/super-monkey-ball-span-20261117.json).

## 2026-11-17 — Asphalt Urban GT race capture on 5F

Lap 2 on MiSTer yielded 298 snapshots across 74.5 seconds. Three pixel loops in the matched game executable accounted for 75 fetch-PC samples (25.2%). The largest combines a table lookup, two multiplies and a conditional halfword store. The private executable is available for a later cross-game replay after Step 5I. [Profile and evidence](asphalt-urban-gt-profile.md).

## 2026-11-17 — Step5H useful-target research completed

Retain exact8e70b1e5F; no RTL prototype funded. Passive original matrix/byte
0:0 reproduce45736/1647; ThumbJPEG both profiles84353. All60 frozen CPU inputs
match, seven windows/two repeats/original oracles/negative outputs PASS.
All1024 helper calls/returns and905JPEG calls/returns matched to actual next
retirement/dequeue; full14353/22508 PC streams equal checked5E. Distinguish
source encoding, early target hints, accepted selection and126late RAS repairs.
One registered F-to-empty-FIFO-head model reuses100payload bits plus1consume
bit; held word can advance while successor demand waits, without earlier requests.
Conservative frozen-readiness/older-operand-certified exposed clocks1555matrix
(3.40%),970JPEG(1.15%),6byte; uncertified free-slot screens1856/1360/9 are separate.
These are counterfactual first-scored counts, not elapsed gains or empty budgets.
First late JPEG return issue+22→+16 after ALU correction; most byte backedge
head gains disappear behind older stores. No evidence for planning2287/4218
clocks; deeper owner/registered-queue work needs a new bounded proposal.
ProductionRTL/patch/PLL, donor, independentfit and phone untouched. Only own
completed compiler/frozen-source/generated inputs retired; compact journals,
fixtures, manifests/oracles/results and executable hashes remain.
[Report](cpu-useful-target.md) ·
[Machine receipt](evidence/cpu-useful-target-20261117.json) ·
[Complete compressed events](evidence/cpu-useful-target-20261117.events.json.gz).

## 2026-11-17 — Super Monkey Ball gameplay profile on 5F

Captured 896 hardware fetch-PC snapshots in three windows and recovered the private game executable. Three original pixel loops account for 90 of 239 snapshots in the window that started during confirmed Floor 01 play. The dominant loop varies with the scene. The first proposed fixed-work replay is the 16-bit span loop. [Profile and evidence](super-monkey-ball-profile.md).

## 2026-11-17 — Step5G line-crossing prototype rejected

Pinned8e70b1e5F control reproduced1332/1647 tail medians. All scored windows have
63/64 resident physical-line crossings; two-clock old-store drain blocks126/124
clocks, not the earlier conditional128 byte estimate. One isolated zero-state
registered lookup-owner overlap moves crossing accept/RAM/retire two clocks
earlier but halfword1332→1264 and byte1647→1646, both0:0/2:9. Byte fails1581
retention gate. Disjoint deltas: write−96/empty+29/other−1=−68; write−124/empty+123
=−1. Subsequent useful byte-loop issue barely changes. Historical5F's250 extra
empty clocks are not an independent cache savings budget. Original tails,
oracles/guards/all bytes, repeats/negatives and40 scored journal audits pass;
20,320 independent main-word mutations and2,540 crossings reconciled. Broader
candidate safety/warm64/JPEG/kernel campaign deliberately not run after gate
failure. No candidate qualified/adopted, productionRTL/patch/PLL unchanged,
no second prototype or fit/CI/donor/hardware/deployment. Preserve separately
dispatched5F fit. Keep5F; bounded Step5G ends here.
[Measured schedules and decision](cpu-store-crossing.md) ·
[Machine evidence](evidence/cpu-store-crossing-20261117.json).

## 2026-11-17 — Integrated accepted 5F performance assessment

All six original kernels are now measured on exact5F, at0:0 and2:9; missing
triangle passed23790 both, seven windows/two repeats/original oracle/negative.
Equal-weight geometric throughput versus the actual16-Nov review baseline is
1.3348079×/1.3347998×. Separate JPEG89610→84353,1.0623×. Stock ngage2 still leads
six-case throughput1.6485598×/1.3622997×;5F wins frame. Frame2:9 original201302,
body+first-empty201407 unchanged; warm64 actual issue→lastRAM71. All60 compiled
RTL hashes match acceptedfae4016; no RTL change, donor run, fit/CI/hardware.
Ranked opportunities distinguish occupancy from conditional removable stages.
Exactly one next experiment proposed: registered warm line-transition ownership,
conditional126/128 local clocks, retain only≥4% both tails with all safety gates
and≤0.5% other-case regression. Implementation deliberately stopped.
[Integrated scorecard](cpu-integrated-5f.md) ·
[Audited machine evidence](evidence/cpu-integrated-5f-20261117.json).

## 2026-11-17 — Benchmark and scratch cleanup

The active CPU remains at accepted Step 5F (`fae4016`). For the next comparison, run the [SPMark bench](../tests/cpu/spmark_payload/README.md) using its default local fixture directory. The six original kernels and four JPEG cases passed their Unicorn output checks after relocation. Both C++ board transaction fixtures still match their golden traces. The SDRAM model passed the legacy and current latency tests at 78 and 104 MHz in simulation.

The checkout now occupies about 2.0 GiB including Git, firmware, local observations and the two accepted build bitstreams. Recreate simulator objects, checkpoints and card images on demand. The local [historical test and capture index](../tests/historical/README.md) identifies retained evidence and reference checkout patches. The [current CPU review handoff](../scratch/handoffs/astra-cpu-pipeline-review-20261116.md) and its working notes remain in scratch.

## 2026-11-16 — Retimed probe matched fit collected (Stop 3D)

**Current mainline decision:** keep the 3C baseline and proceed with the
[4A CPU store-overlap experiment](../docs/handoffs/sol-high-04a-cpu-store-overlap.md).
The fit's further-retiming recommendation below applies to physical timing
qualification. CPU performance work proceeds independently. Use local
registered admission state so extra store credits do not lengthen the
measured completion → resident check → SWP exclusion path.

One matched seed42/debug-on full-core fit of exact four-file Stop3C overlay,
production BRAM and unchanged physical78MHz PLL. Fit-only commit418f6f82,
tag `fit-only/probe-retime-3c-20261116-s42-01`,
[run43906110604](https://github.com/asturur/test_template_1/actions/runs/43906110604).
Compile, actual CI manifest, both routed scenarios, I/O packing and upload PASS;
only normal timing gate red. Manifest178 inputs:177 match preflight exactly,
QSF only tool-written Standard→Lite edition metadata; seed/debug/constraints
unchanged. Direct tree comparison vs3B changes only access/adapter design RTL.
39,549 needed ALMs(+14vs3B),45,104 registers(+352),503M10K/40MLAB/41DSP
unchanged. CPU17,761.3 ALMs(−119.7). Planning headroom901 neededALMs/18M10K;
placedALMs40,474(+130),nine emptyLABs: packing remains tight.
Slow hot/cold78 setup−0.553/−0.306ns vs3B−1.326/−1.520;104−3.758/−3.511
vs−4.531/−4.725. Same-corner gains+0.773/+1.214ns; stock78 reference−0.811.
HDMI hot78+0.051ns. All hold/removal/minpulse positive; hot104 recovery−0.210ns
phone_reset→reset_drain. Clock relationships/fanout/exceptions preserved;
external SDRAM timing coverage remains incomplete. DQ input/output/OE packing PASS.
New hint register inputs pass104; actual certificate→data RAM-B misses−2.705ns
hot/−2.461cold, hints→RAM−2.342/−2.203, result payload qualification−1.712/−1.570.
Reset still reaches RAM mux−0.308/−0.019; owner→RAM now+0.225/+0.397.
New global: completion-next→demand certificate/result mux→accept_demand→existing
SWP/CPU exclusion,12.651ns hotdata(3.647cell/9.005route),−3.758ns104.
SWP owner→board/DMA also−3.535ns; general store payload−2.638ns,
certificate→store owner−1.362ns. Dirty forwarding group+1.707ns; separate
owner→dirty ingress−0.558ns. Empty completion→private probe group is not a pass.
Timing review recommendation at completion: retain3C as useful isolated baseline at bounded worst+1.4435% CPU
cycle cost, but NO CPU admission widening. Next isolate prequalified resident
ingress before accept_demand/existing SWP ownership, local board grant/exclusion,
and certified slot/read intent before RAM arbitration; one stage is not proven
to close all families. No further implementation/seed, production/PLL/history/
index/phone or other simulation/checkpoint changes. Raw `build/fit/probe-retime-20261116/`.
[Comparison and exact paths](cache-probe-admission-retime-fit.md) ·
[Measured evidence](evidence/cache-probe-admission-retime-fit-20261116.json) ·
[Actual CI input proof](evidence/cache-probe-admission-retime-fit-inputs-20261116.json).
Stop after reporting; production integration/deployment remain separate.

## 2026-11-16 — Registered probe boundary measured offline (Stop 3C)

New isolated `tests/cpu/cache_probe_retime/rtl/` derives from corrected Stop3A.
Adapter unconditionally captures both raw27-bit P1/P2 tags and small raw valids;
registered P1-first/P2-fallback scheduling no longer uses fast ACK, launched,
ready or current translation/fault to select/enable payload capture. Cache fuses
certificate/way selection into the next synchronous RAM-B read, retaining owned
result identity and admission-edge latency. Single-demand CPU unchanged.
Bank/tags/dirty forwarding unchanged; poisoned RAM in units, production RAM in CPU.
All Stop3A gates PASS, plus actual-adapter before/after schedules, 16 new-stage
revoke/reset cases, exactly-once held/back-to-back ACKs and physical-read token
negative rejected. 256 short admission reads retained. Both five-store streams
PASS:256 accepts/actual RAM writes/replies per stream, all255 gaps1, latency2,
clean8/16/4/4/4, second-clean and measured external transfers0, exact repeats.
Matched actual CPU vs fresh Stop3A control: all12six-kernel +8JPEG groups PASS,
both profiles/two repeats/independent output and wrong-output oracles. Matrix
52164→52917(+1.4435%); transpose5130 unchanged; triangle25431→25332; frame
71263/201306 unchanged; fill16-tail2116→2117; fill8-tail2178 unchanged. JPEG
86720→87618,86736→87634,85590→86490,170976→172730 (+1.0259–1.0515%).
No case exceeds2% threshold. Control100 throughput indices99.81843six-kernel,
98.97358JPEG in both profiles. Counters attribute regressions to fewer immediate
fast edges/more admitted/fallback reads, not altered guest work/backing model.
[Schedules, measurements, commands and structural audit](cache-probe-admission-retime.md) ·
[Source hashes and compact evidence](evidence/cache-probe-admission-retime-20261116.json).
Decision: YES to a matched seed42 measurement fit on this exact four-cache-file
overlay +production BRAM; no routed slack measured here. Certificate→store owner
−1.168ns and reset→store payload−2.283ns hot104 remain separate timing work.
No CI/production/CPU admission/PLL/branch/history/phone or other-run changes.
Stop before fit submission; retain Stop3A/3B as controls. Raw runs under
`build/sim/probe-retime-*` and `{spmark-payload,jpeg-payload}/probe-retime-*`.

**Current mainline priority:** [Step 4A — CPU admission for consecutive resident stores](../docs/handoffs/sol-high-04a-cpu-store-overlap.md).
Start from the verified 3C overlay and measure fewer clocks for the same ARM
program. Stop 3D is optional timing evidence. If already running, retain its
result independently. The PLL remains 78 MHz and 104 MHz remains the design
target; timing closure is qualified later on an integrated candidate.

## 2026-11-16 — Matched resident-store fit collected: retime before admission (Stop 3B)

Fit-only tag `fit-only/resident-store-3a-20261116-s42-01`, commit7aa1a418,
exact parent9c948da8, [run43886019102](https://github.com/asturur/test_template_1/actions/runs/43886019102).
Quartus17.0.2/CycloneV/seed42/debugger on; only three qualified Stop3A cache
substitutions, production BRAM/78MHz PLL/QIPs/SDCs unchanged. Successful full fit:
39,535 ALMs (−59),44,752 registers(+70),503 M10Ks/40 MLABs/41 DSPs unchanged;
4,179 occupied LABs(−12). Planning headroom915ALMs/18M10Ks.
Matched slow100C78MHz CPU setup−1.326ns vs control−0.811ns; HDMI−0.101ns vs
+0.432ns. Cold slow extra corner setup−1.520ns. Same routed104MHz analysis
clock/fanout/exception preservation validated: setup−4.531ns hot/−4.725ns cold,
recovery−0.803ns hot. Hold/removal/minpulse positive across four corners.
Missing external SDRAM I/O budgets/forwarded clock and hard-IP clock warnings
remain explicit; no full104MHz signoff. DQ input/output/OE packing PASS.
Worst path remains reset/completion/TLB/fastACK→probe owner (13.428ns hot).
New owner→probe is−2.366ns at104; certificate→owner−1.168ns; dirty merge+2.568ns.
Decision: register the shared qualified probe/admission boundary before CPU
admission, then ingress/certificate qualification; do not retime dirty merge first.
CI input-manifest helper had container/host path bug; fit and both STA scenarios
completed. Recovered proof uses actual graph +177 verified remote blobs +effective
seed/debug QSF; labeled reconstructed. No second fit. Raw outputs under
`build/fit/resident-store-20261116/`. [Report](cache-resident-store-pipeline-fit.md) ·
[Measured evidence](evidence/cache-resident-store-pipeline-fit-20261116.json) ·
[Input proof](evidence/cache-resident-store-fit-inputs-20261116.json).
HEAD/branch/index/shared production verified unchanged. No RBF installation,
phone access, CPU admission change, second seed or DDR3 work. Stop after comparison.

Next offline handoff: `docs/handoffs/sol-high-03c-probe-admission-retime.md`.
Compare the registered probe boundary against corrected Stop 3A on real CPU
reads and the resident store stream before selecting the payload for another fit.

The [November 16 donor area audit](donor-resource-comparison.md) compares the
supplied ngage2 seed-60 fit with Stop 3B. Our cache/MMU subsystems use 5,730
more ALMs and our execution core uses 2,731 fewer. Keep Stop 3C first. The next
isolated area candidate is TLB lookup/maintenance comparator sharing, preserving
all 64 entries, page sizes and lockdown behavior.

## 2026-11-16 — Resident-store offline qualification complete (Stop 3A)

Separate corrected overlay in `tests/cpu/cache_resident_qualification/rtl/`;
Step 2 sources/evidence unchanged, production still 9c948da8. Reproduced direct
invalidate reply-without-RAM-write and stale fast ACK while a store owner lives.
Fix: capture direct invalidate/lock pulses and payload, block younger requests,
drain older stores before physical control; suppress fast returns through store
drain while retaining independent B-port probes. No bank/tag/poison change.
Final primed-probe lifecycle sweep: 35 cases across empty/owner/adjacent intent/
commit/post-drain, 8 sampled fast consumers, successful gapped 32-byte line,
rejection/scalar fallback, reset-tail drain, distinct MVA/dirty saved-PA reuse.
Full suite exact repeat PASS; existing admit/probe/refill/maintenance and actual
adapter pending-lock regressions PASS. Both five-stream configurations retain
256 accepts/replies/actual writes per stream, all gaps 1, latency 2; correct dirty
halves/clean counts, no measured external traffic. Fresh same-runner control
reproduces four-clock gaps; wrong-byte controls rejected. Final full raw output:
`build/sim/resident-qual-full-20261116-05/`; all source hashes and failing/corrected
traces in [qualification report](cache-resident-store-pipeline-qualification.md)
and [compact evidence](evidence/cache-resident-store-pipeline-qualification-20261116.json).
Decision: READY for matched full-core fit vs 9c948da8, debugger on, seed 42,
actual 78MHz / analysis 104MHz. Added state estimate now ~102 FF, 70–210 ALMs,
0 new RAM/DSP (pre-fit); pipe_busy→fast ACK gating touches existing probe cone.
No fit submitted, CI/PLL/production/CPU adapter/history/phone/other runs untouched.
Stop before matched fit submission; no physical or workload claim.

Next Sol handoff: `docs/handoffs/sol-high-03b-resident-store-matched-fit.md`.
Match the 78 MHz seed-42 control, then analyze the same routed candidate at
104 MHz. Select only the three qualified cache RTL files and the production BRAM.

## 2026-11-16: 128MB Group1 native discovery verified; cleanup complete

Permanent Ultimate_SIS_Pack/Group_1..4 holds103/89/105/86 installers, each<64MB;
all383 original SIS instances verified, related title packages kept together.
Old layout replaced; non-installer resources in Extras; permanent manifests.
Local build/mmc now ONLY sis-group-1-128mb-ro.mmc + its JSON. All old generated
MMC/raw/sidecars for user cleanup removed; useful reports moved to scratch.
Obsolete5 SD installer/control images also deleted after Menu released handles.
New128MB Group1 copied/synced/full-SHA verified to games/NGage, cold-booted with
original b707ebd firmware. Final screen App Manager shows Group1 installer names;
480snapshots/120s no kernel panic/save errors, final save queue0. Phone left
running there,128MB mounted, physical Save On, saved CFG still Hold/SaveOn.
Agent sent only verified OSD CPU Run: no installer/date/phone keys or ROM patch.
Native reads/discovery verified, not all103 installations or full-capacity I/O.
User may have navigated during capture. Next investigate prior383-file failure
without asserting capacity as root cause. See sis-library.md and
scratch/sis-four-groups-20261116/evidence.json. No HDL/PLL change.

## 2026-11-16: Old installer SD cards and build/mmc outputs cleaned

User authorized reboot, then requested full build/mmc cleanup. Confirmed save
queue0/quiescent, unloaded to Menu, verified no old card handles remained and
deleted5 obsolete SD MMCs plus stray AppleDouble. Local build/mmc now contains
only sis-group-1-128mb-ro.mmc and matching JSON. Historical JSON/logs moved to
scratch/sis-four-groups-20261116/retired-reports; old16MB generated outputs also
removed per explicit request. No other-chat sources/simulations touched.
New128MB transfer/native test in progress. Permanent four-group sources verified.

## 2026-11-16: Permanent four SIS groups and verified128MB Group1 ready

User running full SPMark from C:; no phone input/reboot/mount/SD bulk writes.
Reorganized Ultimate_SIS_Pack in place into Group_1..4:103/89/105/86 installers,
51.97/53.12/54.69/52.78MiB, title families intact, all383 SIS hashes preserved.
Old loose layout and two SIS archives replaced after verification; non-SIS
resources preserved in Extras. Group manifests/readme saved permanently there.
Built/audited sis-group-1-128mb-ro.mmc:103SIS, FAT16/4KiB, CSD WP,75.38MiB free,
SHA899ea722eeba5063796d25ed524bb78bbcc0832ba0d119928d91bc55661dabc9.
Deleted obsolete local installer/control MMCs/sidecars/staging for this scope;
retained audit/evidence and unrelated16MB cards. SD cleanup/delivery and native
128MB test pending user's benchmark completion; readiness question outstanding.
No generic preinstallation claim. See sis-library.md, scratch/sis-four-groups-20261116/.

## 2026-11-16: 64MB small installer card reaches FExplorer prompt

User requested64MB directly after256MB/all383 again closed Main. Cold boot
with verified games/NGage/ngage-test-64mb-ro.mmc (3SIS, FAT16/4KiB, CSD WP)
reaches FExplorer Installer information/OK-Cancel screen. No Main error or
kernel panic in480snapshots/120s; final save queue0, no C:/PMM save errors.
No installer confirmation/date keys/firmware patch sent. Phone left at prompt,
64MB card mounted, physical Run/saveOn, original saved CFG Hold/saveOn.
This verifies native reads/discovery, not completed installation or full-card
operation. Collection count/content and capacity differ; root cause not yet
proved. See mmc-large-card-crash.md for images, checksums and captures.

## 2026-11-16: 256MB also closes Main; 64MB small-card boot active

Verified/synced both new read-only cards to SD games/NGage. 256MB/all383SIS
with4KiB clusters still shows App. closed/Main (user and screenshot agree),
no kernel panic/save errors. User requested64MB directly; cold replay now
uses ngage-test-64mb-ro.mmc with SPMark04/FExplorer/Fatal Arena3D.
Original firmware, installed b707ebd,78MHz unchanged. Save queue confirmed
zero/quiescent before reload. No tracer/startup patches/date confirmations.
See mmc-large-card-crash.md and scratch/mmc-1gb-crash-20261116/.

## 2026-11-16: Smaller read-only MMC controls prepared

512MB CSD write-protection control also reproduces Main application error.
User requested 256MB then64MB. Generated and fully audited 256MB/all383SIS
and64MB/3SIS cards, both FAT16/4KiB clusters with temporary write protection.
Native boot results pending; see mmc-large-card-crash.md. Original firmware,
installed b707ebd RBF and C:/PMM remain unchanged by agent replacement.

## 2026-11-16:512MB size/layout controls also fail; protection control active

512MB with all383SIS at root reproduces Main application error. Moving382to
INSTALL and leaving only FExplorer at root also reproduces it; one OK then
reveals a second error naming EtelServer. CPU alive/no kernel panic in both.
Do not claim512MB fixes it or directory layout is the established cause.

Current mounted SD /media/fat/games/NGage/ultimate-sis-512mb.mmc is now the
original root layout with CSD temporary write protection, SHA
16ef5beda7f9a4969b3cc0fa1879f256c60635b38e50a4da7a0b0c431f87c5d4.
Original383SIS bytes unchanged. This tests guest-advertised protection versus
b707's forced read-only backing. Its120s original-firmware capture is running;
no success claimed. Previous folder metadata control is local-only now.
Other images, original saved settings, firmware and CPU clock unchanged.

## 2026-11-16: Populated512MB also closes Main; empty1GB reaches Phone

Investigating user cold-boot App. closed/Main with1GB library on exactb707ebd
(old read-only interface). Original crash CPU alive/no panic/save error. Native
repeat instead hits kernel exception packet PC503416DC/FAR85D03EF8/reason
10000000, then50324294spin. Empty1GB with identical geometry/identity reaches
Phone home and reads through FAT root end295424. Same383SIS at512MB root still
closes Main. Capacity alone is insufficient explanation; no root cause yet.

Current SD /media/fat/games/NGage/ultimate-sis-512mb.mmc is the verified folder
control (FExplorer root,382SIS under INSTALL), SHA a3bdac23...62ec54a, not the
original local512MB root-layout image. Replay is active. Matching local control
build/mmc/ultimate-sis-512mb-folders.mmc.1GBoriginal remains unchanged. No
observer applied: qualified exit tracer was refused by strict startup guard;
no bypass. ROM stays original. Saved CFG original000020... (Hold/saveOn),
physical native replay Run/saveOn. No C:/PMM replacement or PLL/code changes.
See mmc-large-card-crash.md for exact controls, failed setup and caveats.

## 2026-11-16: Missing Samba SIS card recovered by verified SSH copy

User reports1GB MMC vanished after Finder/Samba copy to
/Volumes/sdcard/games/NGage. Both Mac/SSH views had only4096-byte AppleDouble
._ultimate-sis-1gb.mmc, no actual image. Correct share maps to/media/fat;
149,165,047,808bytes free,exFAT mounted rw. Boot log contains a prior improper
unmount warning; no live storage I/O/remount error observed. Samba log does not
identify the failed-copy cause; do not claim a proven Finder/size-limit defect.

Transferred original image over bounded gzip/SSH to a new temporary file,
fsynced, independently re-read full SD image and matched SHA256
5e9818892ef158161345a5cac186445994171ee4ca78d4f2a5323a0ab469bdbd;
then renamed/synced to/media/fat/games/NGage/ultimate-sis-1gb.mmc.
Exact1,073,480,192bytes. It is visible through the user's mounted Samba path;
size/MBR/footer match there too. Temporary upload renamed away, no SD backup,
core input/reload, C:/PMM change, mount or filesystem repair. Current phone
left running. Evidence scratch/samba-sis-copy-20261116/transfer-result.json.

## 2026-11-16: User reports Unix-time boot without setup prompts

User reports the latest phone startup picked up the Unix timestamp and asked
for neither date nor time. No agent confirmation helper or key input was sent
for this reported boot. This is a successful user-observed prompt-free boot,
superseding the assumption that every startup necessarily asks. Exact loaded
RBF, save lineage and cold/warm reset type were not independently recaptured;
no new hardware access was performed. Repeated cold-boot reliability and the
cause of the difference from earlier prompted boots remain unverified. Keep
the working session intact and observe the next ordinary boot before injecting
any setup confirmations. No additional clock patch follows from this report.

## 2026-11-16: MMC write commit pushed; build43846023145 dispatched

Exact7bbf860e7b3481080888bf07e133f9297c536c97 is published on the original
integration branch. Build43846023145 requested seed43/DDR debugger On. No build
completion, fit/timing or native-write success claimed. Current phone left
running b707ebd; no input/reload/media change during this task. Verified1GB
SIS card is build/mmc/ultimate-sis-1gb.mmc,383packages/806.0625MiB free, root
aliases with INDEX.TXT. Existing core reads it only; new RBF needed for writes.
No256MB C: image generated: firmware-visible internal flash remains4MiB.

## 2026-11-16: SPMark FAT12 tooling promoted; disposable experiment removed

Supplied SIS SHA25636bb9f7d…23393 contains12ordinary app/help files and2text
notices; all declared payload sizes verified. Ready app, unchanged installer-only
and blank16MB FAT12 images are now in `build/mmc/`. Reusable builders, extraction,
independent auditor, frozen donor module, provenance and Docker shortcuts live
in `tools/mmc-card/`; durable private payload/source folders are `runtime/mmc/`.
Permanent synthetic file-addition check is `tests/tools/mmc_folder/`; its
transient fixtures/results use `build/mmc-tests/`. Downloaded mtools is a
recreatable cache at `build/tools/mtools/`, with maintained setup shortcut.

Relocated rebuild passes for all3cards and produces the exact prior image
hashes. Independent FAT allocation audits and production footer/CSD/CRC/extent
inspector pass. Permanent long-name/nested/multi-cluster file control passes.
The entire `scratch/spmark-card-20261116/` experiment was removed after promotion.
AGENTS.md now explicitly makes scratch disposable and keeps useful software,
tests, runtime inputs and findings in their maintained directories.

No HDL, firmware, hardware, mounted media, save, CI or other simulations changed.
New cards/normal App Manager installation remain untested on hardware. MMC stays
read-only; installation would require C: if offered. Cold-mounted ready card is
the established Menu discovery route; offline file addition is not MMC writes.
[Media/instructions](mmc-spmark04.md#offline-sis-and-reusable-fat12-media-2026-11-16).
