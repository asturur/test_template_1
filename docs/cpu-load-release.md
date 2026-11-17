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
