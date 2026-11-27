# SPMark04 v1.10 PolyCount on v5 at 78 MHz

The isolated 32 KiB L1 I-cache saves 3,317,832 clocks per steady torus
frame on the v5 production memory RTL. The simulated rendering rate
rises from 24.19 to 30.79 Ktriangles/s. Perfect instruction-cache hits
raise it to 31.31. The 37 Ktriangles/s target still needs 2.04 million
clocks per frame from the 32 KiB build, or 1.84 million even with all
instruction refills removed.

## Original test and timed work

- `SPMark.app` calls the torus benchmark factory at `0x1000d09c` and
  registers the object with selector 7. The factory's vtable leads to
  `0x10002604`, which constructs the test and calls `0x10002248` for the
  score. The result formatter labels field 8 `3D PolyCount`.
- The original app builds the mesh at `0x10001390` with 30 and 80 ring
  steps. Execution produced 2,400 used vertices and 4,800 distinct
  faces. All 7,200 undirected edges are shared by two faces, with Euler
  characteristic zero. The setup enables lighting, light 0, culling
  and depth testing, and supplies fixed-point positions and normals
  without enabling texturing.
- The timed body begins after the timer start at `0x1000247c` and
  calls `0x10001e00` at `0x10002488`. It clears color and depth, updates
  transforms and the light, submits one `GL_TRIANGLES` call with
  14,400 `GL_UNSIGNED_SHORT` indices at `0x10001f5c`, and swaps at
  `0x10001f68`. The timer stop is at `0x10002490`. The numerator at
  `0x100022ac`–`0x100022c4` is completed frames times 4,800, then
  integer-scaled to thousands before the elapsed-time division.
- The draw and swap resolve to `libGLES_CM.dll` exports 55 and 22.
  `3DTEST.DLL` is loaded by the 3D Game path at the `3dtest.dll`
  reference at `0x100028a8`. The PolyCount call chain executes the
  app, GLES, original ROM helpers and a GLES-generated ARM rasterizer.

## Matched rendering replay

The replay starts from the original renderer's state after its first
draw, including generated ARM code. It runs four original frame bodies
and discards the first RTL frame to warm the hardware. The fixture uses
a 176×208 EGL pbuffer with RGB444 in 16-bit words and 32-bit depth.
The library chooses the same pbuffer configuration for buffer-size
requests 0, 12 and 16, as checked through the original EGL exports.
The original frame function receives a fixed elapsed-time argument of zero and
advances both saved rotation angles. The pbuffer goes through the
original `eglSwapBuffers` entry. Window-server presentation, guest
scheduling, benchmark timers and live LCD scanout are outside the
window. A two-instruction ARM TLS shim returns the captured thread
pointer on the 15 calls per frame. The shaded output, geometry, guest
math, fixed-point transforms, clipping and rasterizer are original.

App and GLES pages are placed in SDRAM, as are the heap and generated
code. Original ROM helper instructions take the real flash/DDR path.
Both legs use the same 78 MHz TB, streaming SDRAM controller and Micron
pin model, block writes, 32 KiB D2, 39 MHz MMC, 64 Hz NOS, firmware,
test inputs and observer. Both keep D=16 KiB, two ways, 32-byte lines
and the XOR D-side section TLB. These are fixed-work rates from RTL
clocks. The full Symbian score can vary with presentation, angles and
the OS page placement.

| I-cache | Clocks/frame | Clocks/triangle | Ktriangles/s at 78 MHz | I fills | Exposed I-bus wait |
| --- | ---: | ---: | ---: | ---: | ---: |
| 16 KiB | 15,478,142 | 3,224.61 | 24.19 | 183,925 | 1,381,291 |
| 32 KiB | 12,160,310 | 2,533.40 | 30.79 | 11,006 | 73,380 |
| Ideal hits, existing I-TLB and frontend | 11,956,024 | 2,490.84 | 31.31 | 0 | 0 |
| 37 Ktriangles/s target | 10,118,919 | 2,108.11 | 37.00 | | |

The table uses the same middle-ranked frame in all three legs. Each
timed window submitted 4,800 triangles and completed one swap. That
frame retired 7,322,287 instructions in all legs, counting conditional
instructions that completed false and one architectural instruction
per ARM register-list operation. The final object, indices, RGB444
and depth bytes matched the original ARM replay exactly. Combined
SHA-256 is `6b40df550fe6fecdf042e623ab384683a8065a71605a0a169f8d0c01365b4d77`.

## Why 32 KiB helps and where the remaining clocks go

The original median frame touched 819 distinct 32-byte instruction
lines, or 25.6 KiB. The two-way footprint exceeds two live lines in
168 sets at I=16 KiB and 91 at I=32 KiB. GLES instruction fetches from
SDRAM account for 1,376,530 exposed I-refill clocks at 16 KiB and
71,644 at 32 KiB. ROM/NOR accounts for 4,131 and 1,524 respectively.
I-line completions drop 94.0%, and
the measured speedup is 27.3% in rendered triangles per clock. The
original donor board controls at 104 MHz show +25.5% (29.58 to 37.11
with D=32 KiB) and +24.6% (28.20 to 35.13 with D=8 KiB). Their end-to-end
scores corroborate the direction of the I-cache effect. The 37.11 donor
result uses roughly 2,802 board clocks per triangle at its stated clock.

Perfect I hits preserve the v5 instruction TLB and hit pipeline and
serve instructions from the same original program bytes. Zero I-line
fills saves 204,286 further clocks from the 32 KiB variant. Even that
idealized replay needs a 15.4% cycle reduction to hit the target.
Critical-word-first or early restart addresses only part of that
already measured refill ceiling.

The median 32 KiB frame completes 1,110,106 interior micro-ops in
addition to architectural retirements. It spends 271,674 otherwise
idle clocks waiting on the D-side path and 904,194 on execution and
dependencies. The median 16 KiB frame spends 304,327 and 960,024 in
those categories. D-line completions remain at 8,508 in all three
legs. The I-TLB completes 58 walk words per leg. The D-TLB completes
two on the control and zero on the 32 KiB leg. Stall bins are mutually
exclusive. Line completions and TLB words are event counts reported
separately from elapsed clocks.

Register-list hotspots include the 10-register push/pop at GLES
`+0x118e0/+0x11c20` and 13-register push at `+0x673c`. Frequent signed
long multiplies at `+0x119f4`, `+0x11ac4` and `+0x11ad4` and stack/vertex
load-use sequences such as `+0x6c60/+0x6c6c` concentrate execution
wait. Measure faster resident register-list transfers and the load-use
and signed-long-multiply dependency paths against this same replay.
Track each change's savings together with the residual frontend bubbles.
[Frame counters, PC and backing-target breakdown](evidence/spmark-polycount-v5-20261119.json).

The 32 KiB simulation overlay changes only I-cache capacity and CP15
CType (`0x0514a14a` to `0x0514a18a`). The generator reproduced the
baseline from the pinned donor netlist. The directed physical cache
probe finds 256 versus 512 sets, with two ways in both. Three lines
8 KiB apart refill 12 times during four repeated rounds at 16 KiB and
stay resident at 32 KiB. `c7,c5,0`, `c7,c5,1` and `c7,c5,2` each flush
all three target lines on both builds, matching the existing RTL's
whole-I-cache handling of those opcodes. Scalar fallback, accepted
32-byte transport, CP15 CType, D geometry and XOR walking passed with
zero and five wait clocks.

The experiment preserves the v5 production build at `70b8ef3`.
Neither cache overlay has a routed 104 MHz result, and the fixture's
clock setting alone cannot establish that it fits. No board RBF was
replaced.

## Instruction scheduling with the 16 KiB I-cache

The same median native frame executed 7,320,907 ARM and 1,241 Thumb
instruction callbacks in Unicorn, including failed conditions. The
largest individual opcode groups are `LDR` (1,066,151), `ADD` (858,476),
`MOV` (824,372), `CMP` (648,652), `LSR` (412,370) and `STR` (379,214).
It encounters 212,478 `SMULL`, 79,602 `SMLAL`, 31,024 `UMULL`, and 9,830
`MLA` instructions. The ARM count includes the guest-generated rasterizer.
There are 389,903 ARM operations with a register-controlled shift,
including ALU instructions with a shifted operand.

The index-processing path at GLES `+0x6c14`–`+0x6c6c` runs 14,400
times. It updates bitmaps with two-word `LDM` and `STM` instructions,
uses a register-controlled `LSL`, and then loads halfword and stack
data for the following `AND` and `ORR`. Other parts of the draw run
long multiplies and register-controlled `ASR` in fixed-point arithmetic.
The busiest 279 instruction lines account for 99% of callbacks,
even though the frame touches 819 lines overall.

The stock phone uses 16 KiB of I-cache and 8 KiB of D-cache with
16-byte lines. The original board comparison records 27.52 Ktriangles/s
for the phone. The 37.11 result belongs to the donor core with 32 KiB
of I-cache. For the CPU overlays, the v5 I-cache stays at 16 KiB and
its D-cache and 32-byte memory bursts stay matched to the v5 control.

| Isolated overlay | Clocks/frame | Saving vs v5 | Ktriangles/s at 78 MHz |
| --- | ---: | ---: | ---: |
| v5 control | 15,478,142 | | 24.19 |
| Use the registered product directly for `MLA`/`SMLAL`/`UMLAL` | 15,393,158 | 84,984 | 24.32 |
| Start ready unconditional `SMULL` one stage earlier | 15,316,089 | 162,053 | 24.44 |
| Skip the preparation clock for a ready ARM register shift | 15,183,942 | 294,200 | 24.66 |

The overlays ran the same three scored frames and matched the original
framebuffer, depth, indices, saved object and retired counts. The signed
product overlay checks the accepted operands against the existing execute
stage. The shift overlay forwards a ready register count into the
existing shifter and keeps the existing preparation for scaled memory
addresses. Directed tests cover signed results, immediate consumers,
a failed condition, carry across both accumulator halves, N/Z flags,
and register-shift count and carry edges. They pass at both wait settings
with accepted or rejected bursts. The shift overlay costs 233,809 fewer
execution/dependency stall clocks while its median I-line fill count
stays at 183,925. Routed timing is unmeasured.

The trace includes 329,474 `LDM`/`STM`/`PUSH`/`POP` encounters. Of those,
163,042 transfer two registers. For a fast path, begin with two aligned
words in one resident D-cache line, with ordinary register destinations
and no writeback or PC in the list. The existing sequential path can
serve longer and boundary-crossing lists, misses, and other cases.
A correct paired implementation must preserve order and abort behavior.
The 163,042 double-register encounters bound the savings from eliminating
one clock on only the two-register cases, before eligibility and stalls.
Generalizing to adjacent pairs in longer lists gives a larger ceiling.
[Instruction histogram and execute-overlay evidence](evidence/spmark-polycount-v5-execute-20261119.json).

### Pairing two resident LDM words at writeback

The simulation overlay returns the next word from the D-cache's selected
way beside the existing hit response. If both beats of an ARM `LDMIA`
are already in the memory and writeback stages, one completion writes
both destination registers. Eligibility requires two word-aligned
addresses in the same 32-byte cache line, an acknowledged live hit,
ordinary registers, no base writeback and no older unresolved data
request. The second result stays available for forwarding on the next
clock. The ordinary serial path covers other cases.

The warm directed guest checks an immediate consumer of both results,
including a base-in-list load without writeback. Crossing a line, a
cold first access, writeback and a false condition exercise the serial
path. All four memory settings pass, with one pair in the warm test
and zero in both fallbacks.

The decoder still issues two steps per instruction. Combining them in
writeback removes a completion but leaves both upstream issue slots
occupied. A throughput-oriented follow-up should combine the two
steps before issue and retain a serial fallback for ineligible accesses.

In the median frame the overlay merged 56,399 pairs out of 64,556
matching instructions seen together in memory and writeback. Counted
interior operations fell from 1,110,106 to 1,053,707. Elapsed clocks
fell from 15,478,142 to 15,478,112, a 30-clock difference. The frontend
bucket grew by 34,287 clocks and the remaining pipeline bucket grew by
15,410. Exposure to cache refills
stayed nearly constant. The ready-register shift remains the stronger
candidate for production qualification.
[Paired-load clocks and checks](evidence/spmark-polycount-v5-paired-ldm-20261119.json).

### Issuing two LDM registers together

The early-issue overlay decodes an ARM `LDMIA` with two ordinary
destinations and no base writeback into one internal operation. The
hazard check tracks both destinations from decode until writeback. A
live, aligned hit with both words in the same D-cache line writes both
registers on one edge. When the first read completes but the second
needs a separate request, writeback commits the first register, holds
the instruction, and reads the next word through the normal path.
Retirement waits for the second word. A fault on that word preserves
the completed first register and leaves the second register untouched.

The shorter fallback presents the second word's address to the D-cache
RAM on the split edge. Advancing the request state by itself reused
the previous RAM lookup at line crossings and failed the directed
test. The decode address hint avoids pairing when the base already
available in decode indicates an unaligned or line-crossing access.
Writeback still checks the actual forwarded effective address.

Each of the three measured overlays passed the directed matrix with
zero or five response wait clocks and burst transfers off or on. The
tests cover a dependent consumer, base in the list, cold and
cross-line accesses, condition failure, writeback, and a second-word
translation abort.

| Overlay | Clocks per median frame | Change from v5 | Paired hits | Serial fallbacks |
| --- | ---: | ---: | ---: | ---: |
| v5 control | 15,478,142 | 0 | 0 | 0 |
| Early issue | 15,489,291 | +11,149 | 56,399 | 8,157 |
| Early issue with shorter fallback | 15,482,523 | +4,381 | 56,399 | 8,157 |
| Early issue with shorter fallback and address hint | 15,469,815 | −8,327 | 36,662 | 1,082 |

The first variant removed 56,399 internal operations and added 23,450
data-request stall clocks. The shorter fallback recovered 6,768 clocks
but still slowed the frame. Of its 8,157 splits, 6,864 were due to address
alignment or a line boundary. The hint eliminated those splits and
reduced the number of paired hits by 19,737. The median frame saved
8,327 clocks (0.054%, or 1.73 clocks per triangle). There were still
84,818 clocks where the pair dependency check flagged a blocked reader
with an available decode slot. That diagnostic can overlap other stall
causes and does not estimate the savings from removing the check.

The warmed frame retired the same 7,322,287 instructions and submitted
the same 4,800 triangles in all runs. The final object, index, color and
depth bytes matched the original guest output in every run. The
ready-register shift saved 294,200 clocks on this replay and remains
the first production qualification candidate. Early LDM issue stays
an offline overlay.
[Replay and directed-test evidence](evidence/spmark-polycount-v5-issue-ldm-20261119.json).

## Production register shift and incremental SMULL

The v5 phone netlist generator in `612fe40` enables direct use of the
forwarded `Rs` count for ready ARM data-processing shifts. The generated
Verilog matches the measured shift overlay byte for byte and is selected
by the MiSTer project's normal source list. Scaled memory addresses and
ineligible shifts keep their original preparation path.

The incremental run starts both legs from that generated netlist. The
second leg launches ready, unconditional signed long multiplies one
stage earlier. It checks the early product against the original
execute-stage operands. Both legs use the original PolyCount replay
at 78 MHz with the same 16 KiB I-cache, 16 KiB D-cache and memory model.
The directed tests cover register shifts, multiply flags and carry,
and cache index maintenance with four response profiles.

| CPU configuration | Median clocks per frame | Saving from preceding row | Ktriangles/s at 78 MHz |
| --- | ---: | ---: | ---: |
| v5 control at `70b8ef3` | 15,478,142 | | 24.19 |
| Production ready-register shift | 15,183,942 | 294,200 | 24.66 |
| Production shift plus early `SMULL` | 15,019,070 | 164,872 | 24.93 |

The incremental `SMULL` saving is 1.09% of the shift-only frame, or
34.35 clocks per triangle. On its own, the same experiment saved
162,053 clocks. The combined path saves 459,072 clocks against the old
v5 control. In the incremental comparison, execute/dependency stalls
fell by 60,615 clocks and frontend wait fell by 72,320 clocks. Exposed
I-refill wait grew by 16,585 clocks. The completed draw and swap counts,
architectural retirements and final guest object, indices, color and
depth bytes match. Commit `78af1df` promotes this `SMULL` path with
identical synthesis input. The simulation operand check uses a
Verilog-2001 procedural check. Routed timing is unmeasured.
[Incremental replay and directed-test evidence](evidence/spmark-polycount-v5-shift-smull-20261119.json).

## Direct accumulate on production SMULL

The experimental accumulate path feeds the registered DSP product to
the existing result and flag logic for `MLA`, `SMLAL`, and `UMLAL`.
It removes the extra cycle that copied that product to another
register. The DSP product holds through decode and execute stalls.
If a new early `SMULL` starts as an accumulate completes, its product
replaces the register at the edge that consumes the previous value.
The directed test exercises consecutive `SMLAL` and `SMULL` and
checks both results, alongside the existing carry and flag cases.

| CPU configuration | Median clocks per frame | Ktriangles/s at 78 MHz |
| --- | ---: | ---: |
| Production register shift and early `SMULL` | 15,019,070 | 24.93 |
| Production plus direct accumulate | 14,928,261 | 25.08 |

Direct accumulate saves 90,809 clocks per frame (0.605%, or 18.92
clocks per triangle). The standalone result was 84,984 clocks. Execute
and dependency stalls account for 68,023 clocks of the incremental
saving, with the same retired instructions, interior operations and
I- and D-line fills. The three changes together save 549,881 clocks
against `70b8ef3` in the same replay with 16 KiB per L1 cache.
Both legs submit 4,800 triangles per frame and match the original
object, index, color and depth bytes. All four directed memory
profiles pass. The measured direct-accumulate leg used an isolated
simulation overlay.
[Matched replay and directed-test evidence](evidence/spmark-polycount-v5-direct-mac-20261119.json).

### Direct accumulate workload qualification

Experiment 3 compares production `78af1df` to the direct-accumulate
overlay alone. Both use 78 MHz, 16 KiB I and D, two ways, 32-byte lines,
39 MHz MMC, 64 Hz NOS, and the same streaming SDRAM and 32 KiB flash
cache. Both netlists match their archived PolyCount files byte for byte.
The prior native result therefore carries forward at 15,019,070 to
14,928,261 clocks per frame, with the original 4,800 triangles and
matching color, depth, indices, and object bytes.

| Fixed-work case | Control clocks | Direct accumulate clocks | Clocks saved | Taken MLA per window |
| --- | ---: | ---: | ---: | ---: |
| SPMark matrix | 16,814 | 16,814 | 0 | 0 |
| SPMark transpose | 2,772 | 2,772 | 0 | 0 |
| GLES triangle edges | 12,254 | 12,229 | 25 | 16 |
| GLES 16-bit frame fill | 112,705 | 112,705 | 0 | 0 |
| GLES 16-bit tail fill | 726 | 726 | 0 | 0 |
| GLES 8-bit tail fill | 747 | 747 | 0 | 0 |
| Monkey Ball forward span | 16,443 | 15,934 | 509 | 512 |
| Monkey Ball reverse span | 16,443 | 15,934 | 509 | 512 |
| Sega Rally textured span | 15,936 | 15,424 | 512 | 512 |
| Sega Rally solid fill | 2,622 | 2,622 | 0 | 0 |
| Sega Rally full scan | 2,391,228 | 2,391,228 | 0 | 0 |
| Asphalt table | 21,396 | 21,396 | 0 | 0 |
| Asphalt double lookup | 11,961 | 11,961 | 0 | 0 |
| Asphalt single lookup | 7,756 | 7,756 | 0 | 0 |
| Thumb JPEG 8×8 | 35,903 | 35,903 | 0 | 0 |

The table uses the median of five checked windows after two warm-ups.
Both legs pass all 15 guest checks twice with repeat-identical counters
and separate wrong-output rejection. Guest bytes and payload/helper
retirement counts match between legs. None of the timed windows
regressed. The eleven ties execute none of the affected opcodes in the
timed window. The textured spans save about one clock per MLA. In
triangle edges, memory service timing also shifts. In window 2 the
scalar wait counter falls from 521 to 510 with the same 67 reads.

Warm directed traces show the same result for `MLA`, `SMLAL`, and
`UMLAL` in all four scalar/burst and wait settings.

| Timing, measured in CPU clocks | Control | Direct accumulate |
| --- | ---: | ---: |
| Product launch in A to result leaving A | 2 | 1 |
| Product launch in A to dependent ADD completing in A | 3 | 2 |
| Successive accumulates in a dependent chain | 3 | 2 |
| Successive accumulates across three independent destinations | 3 | 2 |

The arithmetic contracts cover signed and unsigned high words, low-word
carry, multiply flags, and a following early `SMULL` that reuses the
product register. The control reproduces the prior fixed-work cycle
counts. The repeated-load-destination interlock remains a separate
[follow-up](arm9v2-load-use.md#warm-schedule).

Andrea accepted direct accumulate for production. Commit `57ba6ef`
applies the transform in the generator and produces the qualified
netlist byte for byte. The Quartus source-list check and four directed
profiles pass on the production selection. Routed timing from the DSP
product register through the accumulator and flags logic is unmeasured.
[Per-window, directed, and netlist evidence](evidence/arm9v2-direct-accumulate-v5-20261119.json).

## Reproduce

Run from the v5 worktree with the original v1.10 modules, factory ROM,
ARM binutils, Unicorn and the installed simulator image. The SDRAM pin
model is the same Verilator variant used by the production streaming
SDRAM checks. Supply its local path if the generated default is elsewhere.
The runner defaults to the production CPU netlist. Use the `70b8ef3`
netlist for the historical cache and isolated overlay measurements.

```sh
python3 tools/gen_arm9v2_phone.py --check --stock "$NGAGE2/rtl/cpu/arm925t_gen.v"
python3 tests/cpu/polycount_v5/capture.py \
  --payload-dir "$SPMARK_ORIGINAL" --output build/sim/polycount-oracle
git show 70b8ef3:rtl/arm9v2/arm925t_phone.v > build/sim/arm925t-v5-70b8ef3.v
python3 tests/cpu/polycount_v5/run.py --name fresh-polycount \
  --capture build/sim/polycount-oracle \
  --netlist build/sim/arm925t-v5-70b8ef3.v \
  --pin-model build/sim/unit-hardware-boot-real-sdram/mt48lc16m16a2-verilator.v

ARM9V2_ICACHE_BYTES=16384 ARM9V2_SECTION_INDEX=xor \
  ARM9V2_NETLIST=build/sim/arm925t-v5-70b8ef3.v \
  sh tests/cpu/arm9v2_board/run-contract.sh fresh-polycount-i16
ARM9V2_ICACHE_BYTES=32768 ARM9V2_SECTION_INDEX=xor ARM9V2_CTYPE=0x0514a18a \
  ARM9V2_NETLIST=build/sim/polycount/fresh-polycount/arm925t-i32.v \
  sh tests/cpu/arm9v2_board/run-contract.sh fresh-polycount-i32
```

Use Capstone for the original opcode and register-list counts.

```sh
python3 tests/cpu/polycount_v5/instructions.py \
  --payload-dir "$SPMARK_ORIGINAL" --capture build/sim/polycount-oracle \
  --output build/sim/polycount-instructions.json
python3 tests/cpu/polycount_v5/run.py --name polycount-execute \
  --capture build/sim/polycount-oracle \
  --netlist build/sim/arm925t-v5-70b8ef3.v \
  --pin-model build/sim/unit-hardware-boot-real-sdram/mt48lc16m16a2-verilator.v \
  --legs direct-mac early-smull ready-reg-shift

python3 tests/cpu/polycount_v5/run.py --name polycount-paired-load \
  --capture build/sim/polycount-oracle \
  --netlist build/sim/arm925t-v5-70b8ef3.v \
  --pin-model build/sim/unit-hardware-boot-real-sdram/mt48lc16m16a2-verilator.v \
  --legs i16 paired-ldm
ARM9V2_PAIRED_LDM_TEST=1 ARM9V2_SECTION_INDEX=xor \
  ARM9V2_NETLIST=build/sim/polycount/polycount-paired-load/arm925t-paired-ldm.v \
  sh tests/cpu/arm9v2_board/run-contract.sh polycount-paired-load

python3 tests/cpu/polycount_v5/run.py --name polycount-issue-ldm \
  --capture build/sim/polycount-oracle \
  --netlist build/sim/arm925t-v5-70b8ef3.v \
  --pin-model build/sim/unit-hardware-boot-real-sdram/mt48lc16m16a2-verilator.v \
  --legs i16 issue-ldm issue-ldm-one-gap issue-ldm-address-hint
ARM9V2_ISSUE_LDM_TEST=1 ARM9V2_ISSUE_LDM_HINT=1 ARM9V2_SECTION_INDEX=xor \
  ARM9V2_NETLIST=build/sim/polycount/polycount-issue-ldm/arm925t-issue-ldm-address-hint.v \
  sh tests/cpu/arm9v2_board/run-contract.sh polycount-issue-ldm
```

Reproduce the early `SMULL` comparison against the shift-only commit.

```sh
git show 612fe40:rtl/arm9v2/arm925t_phone.v > build/sim/arm925t-v5-612fe40.v
python3 tests/cpu/polycount_v5/run.py --name polycount-shift-plus-smull \
  --capture build/sim/polycount-oracle \
  --netlist build/sim/arm925t-v5-612fe40.v \
  --pin-model build/sim/unit-hardware-boot-real-sdram/mt48lc16m16a2-verilator.v \
  --legs i16 early-smull
ARM9V2_REGISTER_SHIFT_TEST=1 ARM9V2_MULTIPLY_TEST=1 \
  ARM9V2_ICACHE_BYTES=16384 ARM9V2_SECTION_INDEX=xor \
  ARM9V2_NETLIST=build/sim/arm925t-v5-612fe40.v \
  sh tests/cpu/arm9v2_board/run-contract.sh polycount-production-shift
ARM9V2_REGISTER_SHIFT_TEST=1 ARM9V2_MULTIPLY_TEST=1 \
  ARM9V2_ICACHE_BYTES=16384 ARM9V2_SECTION_INDEX=xor \
  ARM9V2_NETLIST=build/sim/polycount/polycount-shift-plus-smull/arm925t-early-smull.v \
  sh tests/cpu/arm9v2_board/run-contract.sh polycount-shift-plus-smull
```

Measure direct accumulate against the production early `SMULL` path.

```sh
git show 78af1df:rtl/arm9v2/arm925t_phone.v > build/sim/arm925t-v5-78af1df.v
python3 tests/cpu/polycount_v5/run.py --name polycount-smull-plus-direct-mac \
  --capture build/sim/polycount-oracle \
  --netlist build/sim/arm925t-v5-78af1df.v \
  --pin-model build/sim/unit-hardware-boot-real-sdram/mt48lc16m16a2-verilator.v \
  --legs i16 direct-mac
ARM9V2_REGISTER_SHIFT_TEST=1 ARM9V2_MULTIPLY_TEST=1 \
  ARM9V2_ICACHE_BYTES=16384 ARM9V2_SECTION_INDEX=xor \
  ARM9V2_NETLIST=build/sim/polycount/polycount-smull-plus-direct-mac/arm925t-i16.v \
  sh tests/cpu/arm9v2_board/run-contract.sh polycount-production-smull
ARM9V2_REGISTER_SHIFT_TEST=1 ARM9V2_MULTIPLY_TEST=1 \
  ARM9V2_ICACHE_BYTES=16384 ARM9V2_SECTION_INDEX=xor \
  ARM9V2_NETLIST=build/sim/polycount/polycount-smull-plus-direct-mac/arm925t-direct-mac.v \
  sh tests/cpu/arm9v2_board/run-contract.sh polycount-smull-plus-direct-mac
```

Run the fixed-work and MAC timing qualifications with those same netlists.

```sh
for leg in i16 direct-mac; do
  netlist="build/sim/polycount/polycount-smull-plus-direct-mac/arm925t-$leg.v"
  python3 tests/cpu/arm9v2_board/payload_clocks.py --name "direct-mac-$leg" \
    --arm9v2-netlist "$netlist" --config 2:64 --flash-cache-bytes 32768 \
    --sdram-model build/sim/unit-hardware-boot-real-sdram/mt48lc16m16a2-verilator.v \
    --stream-sdram --block-writeback --accumulate-counts
  ARM9V2_MAC_TIMING_TEST=1 ARM9V2_MULTIPLY_TEST=1 ARM9V2_ICACHE_BYTES=16384 \
    ARM9V2_SECTION_INDEX=xor ARM9V2_NETLIST="$netlist" \
    sh tests/cpu/arm9v2_board/run-contract.sh "direct-mac-$leg"
  python3 tests/cpu/arm9v2_board/mac_timing.py "build/sim/arm9v2/contract-direct-mac-$leg" \
    --output "build/sim/arm9v2/contract-direct-mac-$leg/timing.json"
done
```
