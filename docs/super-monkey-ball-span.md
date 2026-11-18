# Step 5I — original Super Monkey Ball span benchmark

Follow-up: [Step 5J](cpu-load-pipeline.md) tests pipelined P1 load ownership on
this unchanged original span fixture and separates initiation throughput from
the remaining seven-clock dependent load-use path.

**Retain accepted 5F. The original span now has a checked offline benchmark.**
For 512 pixels, the forward pattern takes **38,063 cycles, 74.341796875 cycles
per pixel**, at both 0:0 and 2:9. The reverse pattern takes **37,988 cycles,
74.1953125 per pixel**. Recommend one bounded next experiment: capture the
registered product plus nonzero addend in the multiplier's existing S1 result
register, eliminating its separate S2 accumulation hold. There are **512
exposed S2 clocks per window**, a conditional local opportunity of **1.35%**.
This is a proposal, not a measured gain or an implemented CPU change.

## Original code, synthetic work and checks

The private app is 793,068 bytes, SHA-256
`d43052bebaed6401bd8a1482b5a2072022b2d0ff3ac7d6f538be860f0d5ddd77`, matching the
[hardware profile](super-monkey-ball-profile.md). The runner checks the E32
header and extracts the original 80 bytes at code offsets 0x93e38–0x93e84
inclusive at run time. They execute unchanged at 0x10093e38. The original
backward branch remains intact. On its final fallthrough, a separate BX LR
shim at 0x10093e88 returns to the wrapper. No surrounding game routine, runtime
relocation, imported helper or host rendering substitute executes.

Inputs are synthetic, not captured game state. r4 starts at 3, r7 at
0x80004000, SP at 0x80008000. Stack slots +0/+4/+0x14/+0x20/+0x2c/+0x68
hold destination bias, source bias, coordinate step, source stride, source
base and exclusive destination bound. The [test README](../tests/cpu/super_monkey_ball/README.md)
documents every value, both nonuniform byte formulas, guard initialization and
the independent per-pixel equation. The forward coordinate advances by 1/8
with stride 17; reverse retreats by 3/32 with stride 19. All math stays within
signed 32-bit range and every pair of source bytes stays within its 4,096-byte
buffer. Forward selects 64 distinct halfwords in 64 cache lines, reverse 49
in 49 lines. Each writes 512 halfwords across **33 destination lines**.

The mathematical reference computes each selected little-endian halfword
independently of instruction decoding. Original-byte Unicorn execution must
match that reference and **512 ordered two-byte writes / 10,240 original
instructions**. Its whole 1,088-byte destination arena matches, including
38 leading and 26 trailing nonuniform guard bytes. Source and all 128 stack
bytes stay unchanged. Deliberate flips in the first pixel and both guards
are rejected by the host checker. The RTL guest checks the same complete
arena, source and stack after every window. An additional guest run at each
pattern/profile flips an actual output byte after execution and is rejected
by that unchanged checker. These are executed negative controls.

Original binaries, extracted code and disassembly remain private and ignored.
The public test contains only generators, reference equations, wrapper logic
and passive observations.

## Timing and reproducibility

The CPU/cache snapshot is exact accepted commit
`8e70b1ebc16486443d09f008384b4c0bc41c071c`, with no overlay. All **60 frozen
RTL/header hashes** match that accepted tree and the current master. This is
the established freezer's complete RTL closure; Verilator's actual source
journal reads **51 RTL/header files** in this harness, including its five ARM
headers. The extra frozen SDRAM sources are not instantiated by the scalar/line
memory model. The compiler input list is retained with the local run receipts.

The installed image is `jotego/simulator:arm64`, identity
`sha256:df6f55924d5fab96083d01332e45cd734f22277c4dd3b34f55a09cd8dbc3eb8d`.
Builds and simulations ran serially, one compiler job, with pulls and network
disabled. The transport is the existing CPU/cache benchmark's synthetic
scalar/16-halfword-line model. 0:0 and 2:9 mean additional instruction/data
response waits; they are not physical SDRAM timings.

**Start:** actual operand dequeue of the first original loop instruction.
**End:** ordinary retirement of the 512th original conditional back edge.
Cycles are the difference between these rising-edge numbers. Initialization,
wrapper call, return shim and output checks are outside the score. Two warm-up
windows precede five scored windows; two complete executions repeat each
pattern/profile. Every scored window has **zero external scalar reads/writes
and zero line requests/beats**. All five samples and both repeats match exactly.

| Pattern | I:D waits | Scored cycles, all five | Pixels | Cycles/pixel | Retired original instructions |
| --- | --- | ---: | ---: | ---: | ---: |
| Forward | 0:0 | 38,063 | 512 | 74.341796875 | 10,240 |
| Forward | 2:9 | 38,063 | 512 | 74.341796875 | 10,240 |
| Reverse | 0:0 | 37,988 | 512 | 74.1953125 | 10,240 |
| Reverse | 2:9 | 37,988 | 512 | 74.1953125 | 10,240 |

The observer checks the complete retired PC stream, 512 store acceptances,
512 actual two-byte cache RAM mutations and 512 store retirements per scored
window. The forward last RAM mutation is at **38,041**, its store retires at
**38,043**, and the window ends at **38,063**. Reverse is **37,966 / 37,968 /
37,988**. Both include 22 clocks after the last cache write and end with no
pending store or write-buffer entry. This is cache-visible completion; eventual
dirty-line writeback is outside the score. The trained final branch issues
one killed next-iteration prefix instruction: **10,241 dequeues, 10,240
retirements**, with no extra store. It is not counted as retired guest work.

## What delays useful work

One bounded trace records the first 18 iterations of the first scored forward
window at 0:0. Full-window counters cover all windows, profiles and repeats.
The following are exclusive occupancy buckets; overlapping locks during a
data stall are counted only in the data-stall bucket.

| Bucket | Forward | Reverse |
| --- | ---: | ---: |
| Read data stall | 8,160 | 8,085 |
| Write data stall | 3,267 | 3,267 |
| Load dependency, without data stall | 12,794 | 12,794 |
| Other dependency, without data stall | 3,584 | 3,584 |
| Empty operand queue, without either blocker | 18 | 18 |
| Other / advancing | 10,240 | 10,240 |
| **Sum** | **38,063** | **37,988** |

These are occupied clocks, not independent removable budgets. A typical
resident iteration, pixel 7, starts at trace clock 526. Its next iteration
starts 73 clocks later. Relative times below identify actual useful events:

| Event | Typical relative edge |
| --- | --- |
| Destination-bias stack load: dequeue / demand / ACK / dependent add | 0 / 5 / 6 / 7 |
| Stride and source-bias stack loads: dequeues / ACKs | 11,12 / 17,18 |
| MLA dequeue / multiplier busy / next dependent shift dequeue | 19 / 20–23 / 25 |
| Source-base stack load: dequeue / ACK / dependent address add | 26 / 32 / 33 |
| Two byte-load dequeues / their ACKs / pixel assembly dequeue | 34,35 / 42,43 / 45 |
| Register-offset halfword store: dequeue / offer / accept / RAM+ACK / retirement | 46 / 51 / 54 / 56 / 58 |
| Coordinate-step stack load: dequeue / demand / ACK / dependent coordinate add | 47 / 57 / 60 / 61 |
| Bound stack load: dequeue / ACK / compare / back-edge dequeues | 63 / 69 / 70 / 72 |
| Next iteration's first useful dequeue | 73 |

The stack loads demonstrate both pipeline distance and cache response waits.
The two adjacent word loads feeding MLA are dequeued one clock apart; the
second uses an immediate certified response after the first completes. Even
then MLA waits for the second loaded operand. Other direct load consumers
likewise wait through registered completion; the existing issue-on-load-commit
behavior is visible at edges 7, 19, 33, 61 and 70. Adding load-lock counts to
the coincident read stalls would count the same interval twice.

The two byte loads also dequeue consecutively. In the typical iteration the
first waits for a permitted source-line probe, then the second reuses its
registered line and ACKs on the next edge. The adapter records word-aligned
addresses for these separate byte selections; a common recorded word address
does not mean both instructions select the same byte. The assembly operation
still waits until edge 45 for the second byte and its shift dependency.

| Representative pixel | Source pair situation | Store situation | Byte ACKs | Pixel assembly | Store RAM write | Next iteration |
| --- | --- | --- | --- | ---: | ---: | ---: |
| 7 | Existing line | Existing destination line | 42,43 | 45 | 56 | 73 |
| 8 | New source line, resident tag hit | Existing destination line | 46,48 | 50 | 61 | 78 |
| 13 | Existing source line | First halfword in next destination line | 42,43 | 45 | 59 | 76 |
| 14 | Source certificate needs lookup again | Same new destination line, still ordinary store path | 46,48 | 50 | 64 | 81 |

Pixel 8 adds five read-stall clocks, with no external miss. Pixel 13 adds
three write-stall clocks: its accepted store takes the ordinary indexed lookup
path rather than the two-edge resident store pipe. Pixel 14 shows both a
source relookup and the longer store path. These are measured phases, not a
claim that every crossing has the same cost. Across the whole window 447 of
512 stores use the resident pipe, but **none receives CPU store credit**:
the original register-offset STRH is outside 5F's word-store class. The next
operation needing data is already a stack load, which must wait for older
stores to finish. The trace therefore does not establish that simply widening
store credit would advance that useful load by the credited amount.

The trained back edge dequeues at 72 and the next iteration at 73 in the
typical case; the crossing cases retain that one-clock spacing. There is no
recurring empty-frontend budget here comparable to the earlier call-heavy
workloads. The full score has only 18 empty-operand clocks. This agrees with
the [Step 5H conclusion](cpu-useful-target.md): early knowledge or earlier local
delivery alone does not establish earlier useful work.

## One recommended throughput experiment

**Fold nonzero accumulation into S1's registered result capture.** The current
multiplier has registered factors and a registered full product. S1 captures
that product into `x`; S2 then captures `x + addend`; S3 exposes the result.
For this original MLA, the addend is nonzero (3 or 7), so the existing
zero-addend bypass never applies. At typical edges **20/21/22/23/24**, the
multiplier states are **IDLE/POST_IDLE/S1/S2/S3**. Its next dependent shift
dequeues at 25. Every traced representative has the same schedule.

The proposed experiment keeps both product pipeline registers and the existing
`x` register, but in S1 captures **registered full product + resolved addend**
and proceeds directly to S3. Preserve zero-addend product capture, paired-high
ownership, modular arithmetic, flags and all existing hold/kill priority. This
is an adder-input/timing change; it needs actual timing and correctness checks,
including the existing long-product tests. No combinational multiplier output
would feed issue or a cache reply.

Full-window passive counters find **2,048 nonoverlapped multiplier-busy
clocks**, including **512 S2 clocks** with the next dependent instruction
present and locked, without any concurrent data stall. S2 is a subset of
the existing dependency bucket, not another 512 clocks to add to it. Removing
that one edge could locally move the dependent shift **25→24**, once per
pixel. Holding all later schedules equal gives **512 clocks = one clock per pixel**,
or **1.345% of the forward score** (1.348% reverse). The arithmetic comparison
would be 38,063→37,551 / 37,988→37,476, but these are **conditional local
budgets, not simulated candidate results**. Changed cache/queue phasing could
alter realized savings. This evidence does not fund a roughly 5% gain claim.

Recommend this single narrow experiment because its removed state directly
blocks the next useful dependent instruction in every pixel. Production RTL
remains exact 5F. Step 5I ends at benchmark and diagnosis; no candidate,
donor work, hardware access, Quartus, fit, new branch or worktree was used.
Kernel cycles do not establish game FPS or phone peripheral correctness.

## Evidence and replay

[Checked windows, manifests, oracle receipts and representative schedules](evidence/super-monkey-ball-span-20261117.json)
· [Complete bounded per-edge trace](evidence/super-monkey-ball-span-20261117.events.json.gz).
Reusable test: `tests/cpu/super_monkey_ball/`. Qualified run:
`build/sim/super-monkey-ball/step5i-5f-05/`.

```sh
python3 tests/cpu/super_monkey_ball/run.py --name NEW_UNIQUE_NAME
python3 tests/cpu/super_monkey_ball/analyze.py \
  build/sim/super-monkey-ball/NEW_UNIQUE_NAME \
  --output docs/evidence/super-monkey-ball-span-NEW.json
```

Fixture corrections before qualification: the first runner lacked its freezer
helper's import path; the initial observer mistook cold refill writes for
halfword mutations, then required cold write-around stores to mutate cache
RAM and treated a killed final-branch prefix as retired work. All were harness
issues, corrected without changing CPU RTL. Run 04 passed the complete timing
and output campaign; run 05 adds full-window MLA/credit counters and reproduces
all four scores exactly. On this macOS runner Unicorn also required executable
memory access; its restricted `mem_map` trap was not a guest-code failure.
Only this investigation's completed generated compiler trees, frozen RTL and
derived machine-code inputs were removed after receipt verification. Compact
logs, generated synthetic assembly, manifests and hashes remain locally.
