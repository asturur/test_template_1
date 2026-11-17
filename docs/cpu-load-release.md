# Combined P1 load start and earlier lookup

The combined CPU starts eligible ordinary ARM word loads from registered P1
when older P2 has no memory action or redirect. A private hint from the existing
registered ALU effective address prepares resident cache lines one clock earlier.
Actual demand permissions, collision/revocation checks, in-order completion,
store ordering and the existing registered forwarding boundary remain intact.
No cache geometry, RAM port, address adder, payload storage or PLL change.

Patch0080 reproduces the exact offline-qualified core. The upstream patch
replay and all 60 frozen RTL/header hashes match the measured candidate.

## Broader original-code regression

Both instruction:data extra-wait profiles 0:0 and 2:9 pass, five scored windows
and two exact repetitions, original program hashes, independent output oracles,
retirement checks and deliberate wrong-output rejection. Triangle uses the
separate accepted 5F triangle receipt rather than an inferred baseline.

| Original work | Accepted 5F | Combined |
| --- | ---: | ---: |
| Matrix | 45,736 | 45,073 |
| Transpose, canonical wrapper | 3,591 | 3,560 |
| Triangle | 23,790 | 23,568 |
| Full frame, 0:0 | 71,259 | 71,259 |
| Full frame, 2:9 | 201,302 | 201,302 |
| Halfword tail | 1,332 | 1,332 |
| Byte tail | 1,647 | 1,647 |
| Separate original Thumb JPEG | 84,353 | 84,353 |

No measured regression. The candidate also matches the already checked game,
stream and safety CPU inputs exactly, allowing reuse of their qualification:
512-pixel original span forward 38,063→36,528 and reverse 37,988→36,453,
typical dependent load-use 7→6 clocks; independent resident-line load/ALU stream
598→343, sustaining 224 architectural starts in 224 clocks; eight-line stream
627→499. Original output/guards, source/stack, ordered retirements and physical
RAM mutation counts pass. Fault, IRQ, kill/device exclusion, stale data after
stores, collision-poison pressure and focused ARM/Thumb/MMU/return tests pass.

Private executables, ROMs, extracted code and disassembly are not published.
The public qualification driver reads local ignored original fixtures at run
time. Commands: `python3 tests/cpu/cpu_load_lookup/qualify.py --name UNIQUE` and
the same command with `--jpeg`; builds use the installed offline simulator,
one compiler job, two original latency profiles and original negative controls.

## Physical build

The requested build selects public master, seed 42 and DDR debugger enabled,
with the unchanged physical 78 MHz PLL. Routed 78/104 MHz setup/hold, source
manifest, SDRAM I/O registers and resources are assessed from the completed
artifact separately from simulated throughput. No hardware deployment.

## Completed fit and reassessment

[Build 44123116917](https://github.com/asturur/test_template_1/actions/runs/44123116917) compiled exact `ccba54f60a2c6f4741e74428b3306a19717ea58d`. [Download the RBF artifact](https://github.com/asturur/test_template_1/actions/runs/44123116917/artifacts/14348463483). The RBF is 4,565,516 bytes, SHA-256 `fc70703be9cbb41f16e1f644fd35adcf85ab68d301dce6644b418402d53ad1e0`. All 178 selected source hashes, seed42/debug-on settings, unique cache modules, unchanged physical PLL/BRAM and all 16 SDRAM DQ input/output/OE register locations pass verification. All eight routed clock/model reports were checked; unrelated clocks and explicit exceptions are unchanged between the 78/104 scenarios.

The artifact was produced successfully, but **neither 78 nor 104 MHz closes slow-corner setup**. Hold is positive in all reported corners. These are measured routed results, separate from the simulated throughput gains.

| MHz / model | 5F setup ns | Combined setup ns | 5F hold ns | Combined hold ns |
| --- | ---: | ---: | ---: | ---: |
| 78 / Slow 1100mV 100C Model | -0.504 | -1.069 | 0.248 | 0.249 |
| 78 / Slow 1100mV -40C Model | -0.550 | -1.019 | 0.149 | 0.209 |
| 78 / Fast 1100mV 100C Model | 2.695 | 2.801 | 0.134 | 0.133 |
| 78 / Fast 1100mV -40C Model | 3.219 | 3.341 | 0.116 | 0.107 |
| 104 / Slow 1100mV 100C Model | -3.709 | -4.274 | 0.248 | 0.249 |
| 104 / Slow 1100mV -40C Model | -3.755 | -4.224 | 0.149 | 0.209 |
| 104 / Fast 1100mV 100C Model | 0.985 | 1.783 | 0.134 | 0.133 |
| 104 / Fast 1100mV -40C Model | 2.772 | 2.530 | 0.116 | 0.107 |

| Resource | Matching 5F | Combined | Delta |
| --- | ---: | ---: | ---: |
| ALMs | 40,012 | 40,834 | +822 |
| registers | 45,173 | 45,605 | +432 |
| M10Ks | 502 | 502 | +0 |
| DSPs | 41 | 41 | +0 |
| block_memory_bits | 2,760,495 | 2,760,495 | +0 |
| placed_ALMs | 40,832 | 40,883 | +51 |
| occupied_LABs | 4,190 | 4,190 | +0 |

The six-kernel geometric simulated throughput gain is **0.5456%**; original
span gains are about **4%** and the favorable stream remains one instruction
start per clock. The mapped design nevertheless uses 822 more ALMs and 432
more reported registers, despite no added architectural storage in the RTL.
Device ALM use is 97%, and 4,190 of 4,191 LABs are occupied. Source-level
state counts do not predict physical replication, packing or routing cost.

**Recommend one next experiment: a registered permission/admission ownership
stage ahead of resident response selection.** The worst hot 78MHz path now
runs from CP15 translation-base `o_baddr[16]` through the resident `fast_hit` /
completion controls to `late_p1_ready`, with 13.073ns data delay, 11 logic levels
and 8.308ns routing. This directly identifies the live translation/response
control cone to break. Carry a permission/admission token with its exact owner,
retain current-context revocation, fault/IRQ/kill and store-order guards, and
use misses/devices as the serialized fallback. Private lookups must still have
no external authority. Require the existing 224 starts/224 clocks and game
36,528/36,453 cycle results to remain useful-work checks while assessing the
new routed path. This is a recommendation only; no further CPU optimization
was implemented in this release step.

The requested 78MHz-configured artifact is retained with its timing violations
reported explicitly; it is not described as timing-closed. No hardware was
loaded. [Compact regression, source and fit receipt](evidence/cpu-load-release-fit-20261117.json).
