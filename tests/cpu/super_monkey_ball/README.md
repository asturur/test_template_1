# Original Super Monkey Ball span replay

Run from the repository root, with host Python/Unicorn, ARM GNU tools and the
already installed `jotego/simulator:arm64` image:

```sh
python3 tests/cpu/super_monkey_ball/run.py --name NEW_UNIQUE_NAME
python3 tests/cpu/super_monkey_ball/analyze.py \
  build/sim/super-monkey-ball/NEW_UNIQUE_NAME \
  --output docs/evidence/super-monkey-ball-span-NEW.json
```

The run freezes accepted `8e70b1ebc16486443d09f008384b4c0bc41c071c` with the
existing benchmark source freezer, adapts the scalar/line memory transport from
`tests/cpu/spmark_payload/tb.v`, and builds serially (`-j 1`). Container pulls and
network access are disabled. It executes both patterns at I:D extra waits 0:0
and 2:9, seven windows each, two complete repeats. Windows 0–1 are warm-ups;
2–6 are scored only if all external reads, writes and line refills are zero.
Each profile/pattern also runs an actual-output corruption control.

The original app must be supplied locally at `local/SuperMonkeyBall.app` (or
`--app PATH`). `local/` and `build/` are ignored. SHA-256 must match the
[profile](../../../docs/super-monkey-ball-profile.md). At run time only the
80 bytes at E32 code offsets 0x93e38–0x93e84 inclusive are extracted. They execute
unchanged at preferred code base 0x10000000. A separate BX LR exit shim at
0x10093e88 returns to the wrapper. No original binaries, extracted machine
code, or disassembly belong in Git.

`workload.py` defines the independent per-pixel reference and synthetic inputs.
Each run produces 512 halfwords. Initial registers: r4=3, r7=0x80004000,
SP=0x80008000; r5 and stack values are listed below. Other loop inputs are the
six stack slots; other registers are overwritten before use. The wrapper uses
r11 as its sample count and LR as its explicit exit destination.

| Stack slot | Forward | Reverse |
| --- | ---: | ---: |
| +0, destination index bias | 0 | 0 |
| +4, source pixel bias | 3 | 7 |
| +0x14, signed fixed-point step | 0x2000 | −0x1800 |
| +0x20, source row stride in pixels | 17 | 19 |
| +0x2c, source base | 0x80001000 | 0x80001000 |
| +0x68, exclusive r4 bound | 515 | 515 |
| Initial r5 | 0x10000 | 0x3f8000 |

For pixel p, row=floor((initial_r5+p*step)/65536), source byte offset is
2*(row*stride+bias), and destination is 0x80004000+2*(3+p). Both source bytes
are combined little-endian. All source offsets are checked to stay within a
4096-byte source. Forward and reverse use different nonuniform byte formulas.
The 1088-byte destination arena starts at 0x80003fe0: 38 leading guard bytes,
1024 output bytes, 26 trailing guard bytes, all initialized nonuniformly.
Source, destination and the 128-byte stack are initialized before each window;
all three are checked afterward. Original-byte Unicorn execution must match the
mathematical reference, including all guards, exactly 10,240 instructions and
512 ordered halfword writes. Pixel and both guard corruptions must fail the
host checker. The guest checker also rejects a deliberately flipped output byte
after execution at every profile/pattern.

Timing begins at actual operand dequeue of the first original instruction and
ends at retirement of the final original conditional back edge. The score is
the difference between these rising-edge numbers. Setup, call/exit shim and
checks are excluded. The observer verifies the complete issue and retirement
PC order, exactly 512 accepted stores, 512 two-byte cache RAM mutations in each
scored window and 512 store retirements, and an empty pending-store/write
buffer at the end. Cold write-around stores need not mutate cache RAM.
The final trained branch also dequeues one killed next-iteration instruction;
it is included in the issue counter, never the architectural retirement count.
The last RAM mutation and store-retirement offsets are reported separately.
No cache clean is included in the score; completion means CPU cache visibility,
not an external SDRAM writeback.

`observe.vh` records one bounded first-scored-window trace covering the first
18 iterations, including source changes and destination line crossings.
The full-window observer also counts nonoverlapped MLA busy clocks and the S2
clocks where its next dependent instruction is waiting. Stall buckets use
mutually exclusive priority: data read/write stall, then
load/shift dependency lock, then operand queue empty, then other. Their sum
must equal elapsed cycles; these occupancies are not additive savings budgets.

Results and manifests live under `build/sim/super-monkey-ball/NAME/`. Preserve
the compact receipts before removing only that completed run's generated
compiler tree, frozen RTL and derived binary/hex inputs. On macOS the Unicorn
engine needs executable-memory access; a restricted runner may trap at
`mem_map` even before executing guest code. Run it with that access enabled.
