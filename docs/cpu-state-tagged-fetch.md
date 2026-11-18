# State-tagged fetch on the original N-Gage workloads

Retain the isolated frontend prototype. The original Sega Rally full-screen
scan uses **33.73% fewer clocks at 0:0 and 33.19% fewer at 2:9**. The two
designs retire the same 1,427,984 instructions and make the same 146,481
ordered writes. The scan still needs to lose 1,319,667 or 1,385,374 clocks,
respectively, to finish at twice the combined baseline throughput. The
prototype leaves the textured spans and Thumb JPEG close to their prior
results. Its routed area, timing and native game performance are unmeasured.

Andrea reports an index around 224 at 104 MHz against an expected 500.
If that index is proportional to throughput under matched conditions, the
target is 2.23× throughput, or 55.2% fewer clocks for the same work at the
same frequency. The tables below use a separate 2× fixed-work target for
each measured case.

## Frozen sources and timing

The combined baseline starts at published banked TLB and third-D-slot
commit `1928aeef68cbd65699014854326c38101f5249a7`. All source hashes match
the prior banked qualification. The qualified ordinary Thumb early-load
patch is reapplied using its archived hash, and the resulting combined
source is frozen independently of the working checkout. The candidate
changes seven frontend and branch-resolution modules. Its bench, generated
programs, firmware bytes and memory responder match the combined baseline.

The stock donor uses commit `23541bb5519972eccd38eb6a4912472a50b5b6fc`.
The three compiled files, including the QIP-selected `arm925t_gen.v` and
the donor's RAM simulation models, were frozen from local Git objects and
checked against the archived compilation hashes. The comparison reuses
six archived SPMark/GLES cases and the archived original Thumb JPEG case.
The other three JPEG cases and all six game fixtures with stock donor rows
were run for this study. Both cores advance by one core clock per simulated
edge. The donor top drives this CPU at `clk_sys`, documented as 104 MHz.
The archived mainline fit used a 78 MHz PLL. Andrea's current 104 MHz
report and the equal-clock simulation comparison refer to different runs.

The same synthetic peer timing uses a line-read startup with one 16-bit
beat per clock, and one 32-bit scalar word with the selected scalar wait.
The donor packs two fill beats per word. Both runs use warm instruction and
data state after two warmups, five scored windows and two agreeing repeats
per profile. Cache and translation policies follow each core. Combined
mainline has 16 KiB instruction and 16 KiB data caches with 32-byte lines
and 64 ways. The donor has 16 KiB and 8 KiB, respectively, with 16-byte lines
and two ways, and its own section and small-page translation policies.
Identical peer waits therefore allow different bus traffic and elapsed
external service. [Archived donor setup](ngage2-vs-5c-benchmark.md) ·
[Combined Thumb qualification](cpu-thumb-early-load.md)

The scan visits 36,608 original screen pixels and writes 18,316. It runs
the original game loop and the firmware's two FbsCli methods through the
original veneers. The fixture creates the checked post-`Begin` bitmap
cursor and memory layout. Bounded spans, original JPEG and SPMark/GLES
retain their existing work and timing boundaries. The independent oracles
check complete outputs and guards. The runners require their deliberately
wrong expected results to fail. Scoped retired-PC and ordered-store
fingerprints agree, with two documented observer conventions. The mainline
scan observer prints two ARM BX veneer PCs with a +4 alias after the T
change. The collector checks both PC spellings against the independent
Unicorn sequence. The donor counts each Thumb BL suffix as a retirement.
Directly checked suffix counts account for the raw JPEG retirement deltas.
[Game inputs and output checks](cpu-third-data-mapping.md) ·
[Reproducer](../tests/cpu/cpu_architecture/README.md)

## Fixed-work results

Clocks are scored medians. The 2× budget is half the frozen combined
median. Fractional entries indicate the mathematical budget, with the
integer clock limit rounded down. The retire column uses mainline's
instruction convention. Parentheses in the donor column give raw
retirements for JPEG. The ARM stream row includes its wrapper. The
favorable section still starts 224 useful operations in 224 clocks.

| Workload | Waits | Retired | Combined clocks | 2× budget | Stock donor clocks | Tagged fetch clocks | Δ from combined |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| matrix4 | 0:0 | 14,353 | 41,667 | 20,833.5 | 23,675 | 41,667 | +0.00% |
| matrix4 | 2:9 | 14,353 | 41,667 | 20,833.5 | 35,925 | 41,667 | +0.00% |
| transpose4 | 0:0 | 1,025 | 3,560 | 1,780.0 | 1,910 | 3,015 | -15.31% |
| transpose4 | 2:9 | 1,025 | 3,560 | 1,780.0 | 3,484 | 3,015 | -15.31% |
| triangle_edges | 0:0 | 8,657 | 23,120 | 11,560.0 | 12,634 | 23,120 | +0.00% |
| triangle_edges | 2:9 | 8,657 | 23,120 | 11,560.0 | 13,844 | 23,120 | +0.00% |
| fill16_frame | 0:0 | 22,905 | 71,259 | 35,629.5 | 105,069 | 71,238 | -0.03% |
| fill16_frame | 2:9 | 22,905 | 201,302 | 100,651.0 | 275,892 | 201,281 | -0.01% |
| fill16_tail | 0:0 | 663 | 1,332 | 666.0 | 707 | 1,311 | -1.58% |
| fill16_tail | 2:9 | 663 | 1,332 | 666.0 | 760 | 1,311 | -1.58% |
| fill8_tail | 0:0 | 676 | 1,647 | 823.5 | 717 | 1,617 | -1.82% |
| fill8_tail | 2:9 | 676 | 1,647 | 823.5 | 743 | 1,617 | -1.82% |
| diffuse_m10_8x8_jpeg | 0:0 | 22,508 | 80,473 | 40,236.5 | 36,251 (23,413 raw retires) | 80,379 | -0.12% |
| diffuse_m10_8x8_jpeg | 2:9 | 22,508 | 80,473 | 40,236.5 | 36,631 (23,413 raw retires) | 80,379 | -0.12% |
| diffuse_m10_8x8_random | 0:0 | 22,495 | 80,488 | 40,244.0 | 36,250 (23,400 raw retires) | 80,394 | -0.12% |
| diffuse_m10_8x8_random | 2:9 | 22,495 | 80,488 | 40,244.0 | 36,630 (23,400 raw retires) | 80,394 | -0.12% |
| diffuse_m8_8x8_random | 0:0 | 22,316 | 79,573 | 39,786.5 | 35,931 (23,221 raw retires) | 79,558 | -0.02% |
| diffuse_m8_8x8_random | 2:9 | 22,316 | 79,573 | 39,786.5 | 36,311 (23,221 raw retires) | 79,558 | -0.02% |
| diffuse_m10_16x8_jpeg | 0:0 | 44,524 | 158,441 | 79,220.5 | 71,543 (46,325 raw retires) | 158,347 | -0.06% |
| diffuse_m10_16x8_jpeg | 2:9 | 44,524 | 158,441 | 79,220.5 | 72,400 (46,325 raw retires) | 158,347 | -0.06% |
| monkey-forward | 0:0 | 10,240 | 31,052 | 15,526.0 | — | 31,050 | -0.01% |
| monkey-forward | 2:9 | 10,240 | 31,052 | 15,526.0 | — | 31,050 | -0.01% |
| monkey-reverse | 0:0 | 10,240 | 31,007 | 15,503.5 | — | 31,005 | -0.01% |
| monkey-reverse | 2:9 | 10,240 | 31,007 | 15,503.5 | — | 31,005 | -0.01% |
| monkey-forward-small | 0:0 | 10,240 | 31,052 | 15,526.0 | — | 31,050 | -0.01% |
| monkey-forward-small | 2:9 | 10,240 | 31,052 | 15,526.0 | — | 31,050 | -0.01% |
| monkey-reverse-small | 0:0 | 10,240 | 31,007 | 15,503.5 | — | 31,005 | -0.01% |
| monkey-reverse-small | 2:9 | 10,240 | 31,007 | 15,503.5 | — | 31,005 | -0.01% |
| sega-span | 0:0 | 10,249 | 32,908 | 16,454.0 | 15,990 | 32,908 | +0.00% |
| sega-span | 2:9 | 10,249 | 32,908 | 16,454.0 | 16,143 | 32,908 | +0.00% |
| sega-fill | 0:0 | 2,567 | 9,311 | 4,655.5 | 2,596 | 9,311 | +0.00% |
| sega-fill | 2:9 | 2,567 | 9,311 | 4,655.5 | 2,628 | 9,311 | +0.00% |
| sega-scan | 0:0 | 1,427,984 | 8,111,262 | 4,055,631.0 | 3,471,563 | 5,375,298 | -33.73% |
| sega-scan | 2:9 | 1,427,984 | 8,242,680 | 4,121,340.0 | 4,503,455 | 5,506,714 | -33.19% |
| asphalt-table | 0:0 | 13,325 | 41,169 | 20,584.5 | 22,524 | 41,169 | +0.00% |
| asphalt-table | 2:9 | 13,325 | 41,169 | 20,584.5 | 23,991 | 41,169 | +0.00% |
| asphalt-double | 0:0 | 9,742 | 18,441 | 9,220.5 | 12,960 | 18,441 | +0.00% |
| asphalt-double | 2:9 | 9,742 | 18,441 | 9,220.5 | 15,472 | 18,441 | +0.00% |
| asphalt-single | 0:0 | 6,156 | 12,731 | 6,365.5 | 8,332 | 12,731 | +0.00% |
| asphalt-single | 2:9 | 6,156 | 12,731 | 6,365.5 | 8,657 | 12,731 | +0.00% |
| arm-stream | 0:0 | 268 | 337 | 168.5 | — | 337 | +0.00% |
| arm-stream | 2:9 | 268 | 337 | 168.5 | — | 337 | +0.00% |

Across the six SPMark/GLES kernels, the tagged core's throughput geometric
mean relative to the combined baseline is 1.0340× at both waits. The donor
achieves 1.6131× and 1.3330×. Transpose accounts for most of the prototype's
gain there. The donor also takes more clocks on full-frame fill at both
waits. JPEG and the games are outside the geometric mean.

On the scan at 0:0, the combined, donor and tagged designs use 221.57,
94.83 and 146.83 clocks per visited pixel. At 2:9 they use 225.16, 123.02
and 150.42. The stock donor beats the scan's 2× budget at 0:0 and takes
382,115 more than the budget at 2:9. It also beats the 2× budgets for both
the Sega textured span and the original 8×8 JPEG at both waits. The tagged
core still needs to lose 40,143 whole clocks to meet the original JPEG
budget.

## Where the donor gains clocks

The first 52 complete original scan pixels at 0:0 have the same normalized
retirement sequence on all three designs. Each interval is charged to its
preceding retired instruction. Clocks in distinct rows do not overlap,
but an individual interval can contain more than one kind of delay.
Medians describe the sampled sites. Totals sum to the measured duration.

| Prior instruction | Intervals | Combined clocks / median | Donor clocks / median | Tagged clocks / median |
| --- | ---: | ---: | ---: | ---: |
| ARM BX to Thumb | 79 | 1,938 / 21 | 415 / 1 | 382 / 1 |
| Thumb BX to ARM | 79 | 1,078 / 14 | 197 / 2 | 377 / 1 |
| Taken BL to veneer | 79 | 1,211 / 15 | 718 / 9 | 593 / 5 |
| Pixel backedge | 52 | 706 / 18 | 52 / 1 | 261 / 8 |
| Skipped BL | 25 | 25 / 1 | 39 / 1 | 63 / 1 |
| Other | 1,736 | 6,909 / 2 | 3,937 / 1 | 6,306 / 2 |
| Total | 2,050 | 11,867 | 5,358 | 7,982 |

The two interworking directions explain 2,404 of the 6,509-clock gap
to the donor in this sample. Substituting the donor's measured BX gaps
alone gives 9,463 clocks. An ideal one-clock gap for every BX gives 9,009.
The actual prototype reaches 7,982 because the state also propagates
through subsequent call, return and fetch decisions.

At one measured IncXPos call, the ARM BX at `10035030` enters Thumb
at canonical PC `5055d3bc`. In clocks relative to that BX's retirement,
the combined core redirects at −3, accepts the target into the ALU at +18
and retires it at +21. The donor accepts it at −1 and retires it at +1.
The tagged core also retires it at +1 and takes the prediction without
a redirect. Its target is already in the ALU at −2. The donor journal
observes the A-stage execute accept, and the mainline journal observes
the ALU stage and operand dequeue separately.

The full scan confirms the intervention. At 0:0 the exclusive occupancy
bins are as follows. The priority is global data hold, shift/multiply,
operand lock, empty operand stage and remaining work. External service and
redirect signals are separate counters.

| Full scan counter | Combined | Tagged |
| --- | ---: | ---: |
| Data hold | 1,587,133 | 1,553,042 |
| Shift/multiply | 0 | 0 |
| Operand lock | 1,450,030 | 1,410,803 |
| Empty operand stage | 3,240,791 | 812,085 |
| Remaining clocks | 1,833,308 | 1,599,368 |
| Total | 8,111,262 | 5,375,298 |
| Overlapping external-service clocks | 66,286 | 66,286 |
| ALU redirects | 176,478 | 22,659 |
| Predecode redirects | 119,019 | 2,178 |

Both mainline variants use 4,142 line fills, 152 scalar bus reads and
10,366 bus writes. The donor uses 8,416 shorter line fills, 109,852 scalar
reads and 13,344 bus writes in its 0:0 score. These are bus transactions.
Ordered guest stores match. Moving to 2:9 adds about 131,400 clocks to
either mainline variant and about 1.03 million clocks to the donor.

### Resident reads in Asphalt's double-lookup loop

The 19th visited pixel starts at `10056eb4`. Both source reads hit
resident cache lines. Clocks are relative to retirement of that pixel's
first original instruction. Each entry gives the boundary visible in
the actual probe on that core.

| Event | Combined | Donor |
| --- | ---: | ---: |
| Lookup A at `10056ec4`, VA `800011ac` | Operand dequeue 0, ALU accept 3, D offer 5, ACK 9, retire 11 | A accept 5, D offer and fast return 7, retire 7 |
| Independent lookup B at `10056edc`, VA `800031d0` | Operand dequeue 12, ALU accept 15, D offer 17, ACK 21, retire 23 | A accept 12, D offer and fast return 14, retire 14 |
| ORR consuming both results at `10056ee0` | Operand dequeue 23, ALU accept 26, retire 29 | A accept 16, retire 18 |
| Backedge at `10056efc` retires | 36 | 25 |
| Next pixel's first instruction retires | 37 | 26 |

The combined core holds while D offers lack ACK. The independent request
spacing is 12 clocks versus seven, and the second load to dependent ORR
execution is 11 versus four. Both designs retire the next target one
clock after the backedge for this pixel. A queue can overlap independent
work. The immediate ORR still depends on the second return. The entire
Asphalt double case has 9,742 retirements, already above its 9,220.5-clock
target with one retirement per clock. Monkey Ball's forward loop needs
15,526 clocks for 2× against 10,240 retirements. At 0:0 it has 5,948
global data-hold clocks, 12,796 operand-lock clocks, 2,048 shift/multiply
clocks and zero external service during the score.

The matched random 8×8 JPEG trace shows the same type of dependency in
Thumb code. With the producer's ALU observation as clock zero, the load
at `505a9e5e` to VA `80000190` offers at +1, acknowledges at +2 and
retires at +4 on both mainline variants. The dependent ADD at `505a9e60`
dequeues at +1 via the existing late operand path, executes at +5, and
retires at +8. On the donor the load offers, returns and retires at +2,
the ADD accepts at +2 and retires at +4. This gives a concrete warm-load
latency target alongside the independent request spacing in Asphalt.

## RTL and correctness

The internal fetch PC records use the otherwise zero low bit for
speculative instruction state. Bus addresses remain canonical. Fetch,
instruction FIFO, Thumb inflater and predecode skid carry each
instruction's predicted state. The BTB adds one source-state bit per entry
to distinguish predictions at the same address. Its target and the
return stack use their existing low target bit. ALU feedback includes the
actual source PC and its pre-branch state. Direct branches and fallthrough
carry the current instruction state. Register-indirect BX can use a
learned address/state pair. A return-stack prediction for MOV or LDM to PC
keeps the current state in ARMv4. The ALU updates CPSR at the existing
resolution boundary and checks the predicted address and state separately.
A mismatch discards younger speculative instructions even if the
canonical address is right. Existing higher-priority exception, load-PC
and CP15 redirects keep their priority and carry resolved state.
State travels with a held fetch request through a cache wait.

The same-address interworking test switches between ARM and Thumb at a
single canonical address, with 24 expected ARM increments in 48 total
branches. At each of 0:0, 2:9 and 0:97 the prototype confirms 41 branches
without a flush and recovers five wrong-state predictions at the correct
address. The control clears all 48. The precise Thumb abort test checks
fault address and status, old flags despite an accepted younger flag
writer, and a cold retry. Twenty-two ordinary diagnostics and ten CPU
runs covering FIQ, SWP, translated prefetch and pending-write/walk
ordering pass. The real IRQ test at zero and three memory waits checks
interrupt entry and return during a multiply, an intact destination pair,
and false-predicate suppression. The full 42-row A/B has no elapsed
regression. The first bounded frontend version left register-indirect BX outside the prediction
path. The final overlay includes the actual Sega veneers and is the only
version used in the scorecard.

## Native comparison

For the phone comparison, record the exact NEM-4 firmware, SPMark04 build
and settings, original input media, and actual CPU clock for each system.
Use the same Game Test scene, resolution and quality settings. Match the
pre-run state and record LCD, autosave and storage conditions that can
affect an elapsed run. Warm both systems, then take repeated independent
runs and retain their individual results and medians. Record Game Test
FPS and total index separately. Record the individual fill, triangle and
image or JPEG results where the same SPMark build exposes them. On the
core, capture elapsed clocks and cache/memory counters over the same
timed interval. This gives a way to check whether the synthetic cache-peer
findings account for the native gap when phone data becomes available.

[Source hashes, windows and qualification receipt](evidence/cpu-state-tagged-fetch-20261118.json.gz) ·
[Representative pipeline and D-port traces](evidence/cpu-state-tagged-fetch-20261118.traces.json.gz)
