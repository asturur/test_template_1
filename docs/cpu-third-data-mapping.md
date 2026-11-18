# Third checked D-side translation mapping on 5L

## RTL and qualification

The experiment freezes published 5L at `0c380ab9bae92916d297b72d6a303d251f1d49d9`.
All 60 RTL and header hashes match the qualified 5L record. The isolated
candidate changes the translation controller and enables its extra record in
the D-cache instance. The architectural bank RTL is byte-identical. The
I-cache still uses two local entries. It has the same shared context and both
architectural TLBs still hold 64 entries. Cache geometry, FCSE address
formation, translation pipeline stages and the synthetic bus peer are
unchanged within each matched comparison. The separately published banked
architecture, section-wide reuse and Thumb early-load changes are outside
this experiment. [Overlay and commands](../tests/cpu/tlb_three_mapping/README.md)

The D controller gains 65 declared state bits. The tag and PA subpage are
22 bits each, C/B and read/write permissions are two bits each, the internal
and external FSR fields are eight bits each, and valid is one bit. Publication
copies the second record to the third. A local hit leaves FIFO age unchanged.
The hit path gains a parallel 22-bit equality comparison gated by valid and
the existing shared context, one more hit input to the owner predicate and
an added priority choice for 42 payload bits across PA, C/B, permissions and
FSRs. The same VA low 10 bits supply the live PA offset and exact FAR.
Walk faults remain first-slot exact request results. There are no new RAM
ports, outstanding requests or cache copies. Physical area, fitted
registers, timing and Fmax are **unmeasured** for this exact unbanked
candidate. A later fit prices the third slot on the published banked
controller. [Matched banked fit](tlb-banked-third-fit.md)

The six maintained MMU units passed against both frozen source sets, with
strict Verilog-2001 elaboration of both controller variants. The extended
two-mapping test verifies a third-slot hit with independent C/B and PA,
a read grant followed by a denied write with exact FAR and FSR, and a
separate neighbor's allowed write. A fourth resident region evicts the
oldest slot even after that slot was just used. The test checks revocation
across CPSR, S/R, DACR, TTBR, MMU disable, MVA and all invalidation, lockdown
write, and architectural entry-65 replacement. A denied third-slot write
leaves an unrelated exact walk fault live for its original address and direction. The deliberate mutation
preserves the oldest grant across a main-table fill. The test rejects it
with `stale third-slot grant after main-table replacement` before the grant
can hide A's changed PA. Both variants also passed 22 ordinary CPU
diagnostic runs and ten additional runs with the actual FIQ, SWP, translated
prefetch and pending-write/walk ordering stimuli.

## Timing and fixture boundaries

Every score uses both synthetic waits 0:0 and 2:9, two warmups and five scored
windows, with two identical positive trials and a failing output control per
source and profile. SPMark and JPEG keep their original retired wrapper
markers, full-buffer checks and native helpers. Triangle setup links the
original EUSER divide export. The four JPEG cases cover the original image
crop and deterministic random input in the established modes and dimensions.
Monkey Ball keeps first operand pop through final original BLT retirement,
with 10,240 original retirements and 512 checked two-byte writes. Its split
layout maps source, destination and stack VAs `80001000`, `80004000`, and
`80008000` through coarse table `0a01b000` to distinct PA pages
`0a014000`, `0a00c000`, and `0a008000`. The preceding destination guard
page maps to `0a00b000`. Guest work and expected memory bytes are identical
to the section layout.

The new renderer fixtures check the hash of each private original executable,
retain exact E32 instructions at the linked offsets and use a return shim
after the final instruction. Their measured wrapper markers include the
short register setup and shim. The independent reference computes each
output from synthetic inputs, then checks every output byte, skipped
destination, guard and immutable input in Unicorn. The RTL guest checks the
same memory again on every window. For the five bounded loops, source A,
source B, stack, table and destination use separate 1 KiB regions within the
same section. The count of writes is also checked against the reference.

- Sega span `1da54–1daa0` uses two advancing fixed-point coordinates,
  a 16×16 halfword texture, stack-provided masks and stride, and 512
  destination writes. Indexed fill `1c9f4–1ca04` uses an initial index of
  3, an inclusive limit and a fixed halfword value.
- Asphalt `56d3c–56da0` uses a 32-word scale table and alternates two
  distinct 16×16 textures. Both choices cover written and skipped pixels.
  `56eb4–56efc` combines a halfword lookup with a second table index offset
  by 17. `56f30–56f5c` uses a single indexed halfword. All three visit
  512 pixels. The reference applies the original unsigned `<= 0xf000`
  test and checks initial bytes for every skipped pixel.
- Sega full-screen `1dcc4–1dcf4` scans all 36,608 halfwords, calling native
  FbsCli ordinal 62 (`TBitmapUtil::IncXPos`, `5055d3bd`) on every pixel and
  ordinal 105 (`TBitmapUtil::SetPixel`, `5055d2b1`) on bit-15-clear pixels.
  Checked original veneers at `35018` and `35028` reach exactly those
  exports through linked IAT entries. The firmware range remains at its
  original virtual address and is backed by the test peer's firmware
  aperture. The peer models 256 KiB of RAM for disjoint guarded source and
  destination buffers, stack and object. The synthetic post-`Begin` cursor
  starts at (0,0) with a 16-bit step, `0xffff` mask, and the correct start
  and end pointers. This reproduces every field read by the two original
  methods, both source bit-15 outcomes and the final cursor wrap. The
  phone's live bitmap allocation and the surrounding `Begin`/`End` calls
  are outside the scored interval. Both complete buffers, the object,
  stack effects and the original ARM/Thumb retirements are independently
  checked. [Sega capture](sega-rally-profile.md) · [Asphalt capture](asphalt-urban-gt-profile.md)

## Measured comparison

Each hits column lists D-side completed demands served by slot 1/2/3
without a main-table search for that demand. Searches count bank launch
pulses. Walks count architectural misses that start a first-level descriptor
read rather than counting descriptor beats. D busy + hold counts an offered
data demand that sees both translation busy and the CPU data hold in the
same clock. These cover the measured windows only. The evidence retains all
seven windows, walk beats, whole-run totals and separate setup/check/cleanup
counts. Event samples include the terminal edge. A search launching on
that edge can belong to the first post-score check, while a search and its
completion can straddle either timing boundary. Percentages are
elapsed-clock changes against 5L. The workloads are
fixed original-code replays with synthetic inputs and memory delays.

### Where the clocks went

The six-kernel throughput geometric mean is **1.01608×** at both wait
settings. Matrix saves 3,406 clocks (7.56%) and triangle setup 400 (1.70%).
Transpose and the three fills finish in the same clocks. The four JPEG cases
separately save 1.51–1.81%.

Monkey Ball saves **11.27% forward and 11.21% reverse** in both layouts.
Scored demand order is identical, including all 4,608 addresses and 512
halfword writes per window. Replaying the recorded addresses from an empty
FIFO reproduces the earlier **1,537 / 10** prediction. RTL measures
**1,536 / 9** in each scored case. The first stack-region demand is already
a slot-2 hit in each warmed variant. The setup publishes that mapping
before the first operand-pop edge, so the empty model counts one compulsory
miss the scored RTL never takes. The refined window counts 4,096 → 25
clocks with both data hold and translation busy. Total data hold falls
9,891 → 5,948 forward and 9,816 → 5,903 reverse. The split fixture adds
three actual D walks in setup (3 → 6 between memory layouts at 0:0),
with zero walks in scored windows in either layout.

Sega's textured span saves **11.05%**, with 1,538 → 5 D searches. The
indexed fill stays flat. Asphalt's two-lookup loop saves **6.92%**, with
518 → 5 D searches. The table/multiply loop uses stack, table, one of two
textures and the destination on written iterations. It still searches
the bank 1,627 times per window and saves **1.40%**. The single lookup
has a two-region hot set and finishes in the same clocks.

In the halfword-tail trace, the third slot eliminates the final search at
edge 1,332. That edge is already the timed endpoint and the request is the
checker literal at `00000158`. Both peers show data hold and a load-locked
operand for the checker. The guest writes and return have already occurred
in the same elapsed cycles. The favorable ARM stream retains **224 useful
starts in 224 consecutive clocks** at both wait settings. Its wrapper
window gains six clocks around initial translation and stream entry.

The Sega full-screen scan saves **53,508 clocks** in either profile,
or **0.64% at 0:0 and 0.63% at 2:9**. It visits 36,608 pixels and
writes 18,316. D searches fall 256,330 → 238,014, one eliminated
search for every written pixel. The I side still launches 234,763
searches per window across the original game and firmware calls. Both
peers perform 4,142 external line transfers per scored window.
The first 0:0 window incurs one D walk and two I walks. All scored
windows have zero page-table walks. The synthetic post-`Begin` bitmap
state and full-duration native calls get the scan past the original
replay dependency.

### Decision

**Retain the isolated candidate for a matched fit.** The same-clock gain
survives the separate small-page layout and appears in several unrelated
original rendering kernels, matrix and JPEG. The checked-context to
ready/ACK path warrants close attention because the third comparator and
result selection feed it. Use the exact unbanked 5L pair when measuring
ALMs and setup/hold at 78 and 104 MHz. All scored workload clocks
matched or improved, and all 32 matched CPU diagnostics had identical
cycle counts. The six-kernel index and the renderer timings describe
fixed work at a common clock.

[All raw window counters, matched inputs and qualification receipts](evidence/cpu-third-data-mapping-20261117.json.gz) · [Representative traces and Monkey Ball demand journals](evidence/cpu-third-data-mapping-20261117.traces.json.gz)

### A/B scorecard

| Case | Waits | Work | Clocks A → B | Clocks/unit A → B | Δ clocks | D hits by slot A → B | Searches D/I A → B | Walks D/I A → B | D busy + hold A → B |
| --- | --- | --- | ---: | ---: | ---: | --- | --- | --- | ---: |
| matrix4 | 0:0 | 16 4x4 matrix products | 45,073 → 41,667 | 2,817.06 → 2,604.19 | -7.56% | 871/873/0 → 391/1,113/960 | 801/160 → 81/160 | 0/0 → 0/0 | 1,873 → 193 |
| matrix4 | 2:9 | 16 4x4 matrix products | 45,073 → 41,667 | 2,817.06 → 2,604.19 | -7.56% | 871/873/0 → 391/1,113/960 | 801/160 → 81/160 | 0/0 → 0/0 | 1,873 → 193 |
| transpose4 | 0:0 | 32 4x4 matrix transposes | 3,560 → 3,560 | 111.25 → 111.25 | +0.00% | 421/376/0 → 767/16/15 | 3/0 → 2/0 | 0/0 → 0/0 | 7 → 4 |
| transpose4 | 2:9 | 32 4x4 matrix transposes | 3,560 → 3,560 | 111.25 → 111.25 | +0.00% | 421/376/0 → 767/16/15 | 3/0 → 2/0 | 0/0 → 0/0 | 7 → 4 |
| triangle_edges | 0:0 | 16 triangle edge setups | 23,520 → 23,120 | 1,470.00 → 1,445.00 | -1.70% | 1,032/456/0 → 911/253/406 | 225/258 → 143/258 | 0/0 → 0/0 | 593 → 379 |
| triangle_edges | 2:9 | 16 triangle edge setups | 23,520 → 23,120 | 1,470.00 → 1,445.00 | -1.70% | 1,032/456/0 → 911/253/406 | 225/258 → 143/258 | 0/0 → 0/0 | 593 → 379 |
| fill16_frame | 0:0 | 36,608 pixels | 71,259 → 71,259 | 1.95 → 1.95 | +0.00% | 18,233/1/0 → 18,233/1/0 | 73/0 → 73/0 | 0/0 → 0/0 | 217 → 217 |
| fill16_frame | 2:9 | 36,608 pixels | 201,302 → 201,302 | 5.50 → 5.50 | +0.00% | 18,233/1/0 → 18,233/1/0 | 73/0 → 73/0 | 0/0 → 0/0 | 217 → 217 |
| fill16_tail | 0:0 | 1,023 pixels | 1,332 → 1,332 | 1.30 → 1.30 | +0.00% | 256/256/0 → 256/256/0 | 3/0 → 2/0 | 0/0 → 0/0 | 7 → 6 |
| fill16_tail | 2:9 | 1,023 pixels | 1,332 → 1,332 | 1.30 → 1.30 | +0.00% | 256/256/0 → 256/256/0 | 3/0 → 2/0 | 0/0 → 0/0 | 7 → 6 |
| fill8_tail | 0:0 | 2,051 bytes | 1,647 → 1,647 | 0.80 → 0.80 | +0.00% | 513/0/0 → 513/0/0 | 4/0 → 4/0 | 0/0 → 0/0 | 8 → 8 |
| fill8_tail | 2:9 | 2,051 bytes | 1,647 → 1,647 | 0.80 → 0.80 | +0.00% | 513/0/0 → 513/0/0 | 4/0 → 4/0 | 0/0 → 0/0 | 8 → 8 |
| diffuse_m10_8x8_jpeg | 0:0 | 64 pixels | 84,353 → 82,943 | 1,318.02 → 1,295.98 | -1.67% | 3,890/6,469/0 → 4,805/1,756/4,213 | 1,219/796 → 804/796 | 0/0 → 0/0 | 3,311 → 2,210 |
| diffuse_m10_8x8_jpeg | 2:9 | 64 pixels | 84,353 → 82,943 | 1,318.02 → 1,295.98 | -1.67% | 3,890/6,469/0 → 4,805/1,756/4,213 | 1,219/796 → 804/796 | 0/0 → 0/0 | 3,311 → 2,210 |
| diffuse_m10_8x8_random | 0:0 | 64 pixels | 84,367 → 82,957 | 1,318.23 → 1,296.20 | -1.67% | 3,890/6,469/0 → 4,805/1,756/4,213 | 1,219/796 → 804/796 | 0/0 → 0/0 | 3,311 → 2,210 |
| diffuse_m10_8x8_random | 2:9 | 64 pixels | 84,367 → 82,957 | 1,318.23 → 1,296.20 | -1.67% | 3,890/6,469/0 → 4,805/1,756/4,213 | 1,219/796 → 804/796 | 0/0 → 0/0 | 3,311 → 2,210 |
| diffuse_m8_8x8_random | 0:0 | 64 pixels | 83,370 → 82,114 | 1,302.66 → 1,283.03 | -1.51% | 3,890/6,469/0 → 4,805/1,756/4,213 | 1,219/794 → 804/794 | 0/0 → 0/0 | 3,311 → 2,210 |
| diffuse_m8_8x8_random | 2:9 | 64 pixels | 83,370 → 82,114 | 1,302.66 → 1,283.03 | -1.51% | 3,890/6,469/0 → 4,805/1,756/4,213 | 1,219/794 → 804/794 | 0/0 → 0/0 | 3,311 → 2,210 |
| diffuse_m10_16x8_jpeg | 0:0 | 128 pixels | 166,289 → 163,271 | 1,299.13 → 1,275.55 | -1.81% | 7,602/12,869/0 → 9,478/3,483/8,309 | 2,371/1,564 → 1,572/1,564 | 0/0 → 0/0 | 6,447 → 4,322 |
| diffuse_m10_16x8_jpeg | 2:9 | 128 pixels | 166,289 → 163,271 | 1,299.13 → 1,275.55 | -1.81% | 7,602/12,869/0 → 9,478/3,483/8,309 | 2,371/1,564 → 1,572/1,564 | 0/0 → 0/0 | 6,447 → 4,322 |
| monkey-forward | 0:0 | 512 pixels | 34,995 → 31,052 | 68.35 → 60.65 | -11.27% | 3,068/4/0 → 2,064/1,759/776 | 1,536/0 → 9/0 | 0/0 → 0/0 | 4,096 → 25 |
| monkey-forward | 2:9 | 512 pixels | 34,995 → 31,052 | 68.35 → 60.65 | -11.27% | 3,068/4/0 → 2,064/1,759/776 | 1,536/0 → 9/0 | 0/0 → 0/0 | 4,096 → 25 |
| monkey-reverse | 0:0 | 512 pixels | 34,920 → 31,007 | 68.20 → 60.56 | -11.21% | 3,068/4/0 → 1,904/1,959/736 | 1,536/0 → 9/0 | 0/0 → 0/0 | 4,096 → 25 |
| monkey-reverse | 2:9 | 512 pixels | 34,920 → 31,007 | 68.20 → 60.56 | -11.21% | 3,068/4/0 → 1,904/1,959/736 | 1,536/0 → 9/0 | 0/0 → 0/0 | 4,096 → 25 |
| monkey-forward-small | 0:0 | 512 pixels | 34,995 → 31,052 | 68.35 → 60.65 | -11.27% | 3,068/4/0 → 2,064/1,759/776 | 1,536/0 → 9/0 | 0/0 → 0/0 | 4,096 → 25 |
| monkey-forward-small | 2:9 | 512 pixels | 34,995 → 31,052 | 68.35 → 60.65 | -11.27% | 3,068/4/0 → 2,064/1,759/776 | 1,536/0 → 9/0 | 0/0 → 0/0 | 4,096 → 25 |
| monkey-reverse-small | 0:0 | 512 pixels | 34,920 → 31,007 | 68.20 → 60.56 | -11.21% | 3,068/4/0 → 1,904/1,959/736 | 1,536/0 → 9/0 | 0/0 → 0/0 | 4,096 → 25 |
| monkey-reverse-small | 2:9 | 512 pixels | 34,920 → 31,007 | 68.20 → 60.56 | -11.21% | 3,068/4/0 → 1,904/1,959/736 | 1,536/0 → 9/0 | 0/0 → 0/0 | 4,096 → 25 |
| sega-span | 0:0 | 512 pixels visited, 512 written | 36,996 → 32,908 | 72.26 → 64.27 | -11.05% | 2,050/512/0 → 517/1,023/2,555 | 1,538/0 → 5/0 | 0/0 → 0/0 | 4,100 → 12 |
| sega-span | 2:9 | 512 pixels visited, 512 written | 36,996 → 32,908 | 72.26 → 64.27 | -11.05% | 2,050/512/0 → 517/1,023/2,555 | 1,538/0 → 5/0 | 0/0 → 0/0 | 4,100 → 12 |
| sega-fill | 0:0 | 512 pixels visited, 512 written | 9,311 → 9,311 | 18.19 → 18.19 | +0.00% | 515/0/0 → 511/0/4 | 3/0 → 3/0 | 0/0 → 0/0 | 7 → 7 |
| sega-fill | 2:9 | 512 pixels visited, 512 written | 9,311 → 9,311 | 18.19 → 18.19 | +0.00% | 515/0/0 → 511/0/4 | 3/0 → 3/0 | 0/0 → 0/0 | 7 → 7 |
| sega-scan | 0:0 | 36,608 pixels visited, 18,316 written | 8,344,171 → 8,290,663 | 227.93 → 226.47 | -0.64% | 311,257/54,948/0 → 292,941/54,948/36,632 | 256,330/234,763 → 238,014/234,763 | 0/0 → 0/0 | 695,748 → 659,116 |
| sega-scan | 2:9 | 36,608 pixels visited, 18,316 written | 8,475,588 → 8,422,080 | 231.52 → 230.06 | -0.63% | 311,257/54,948/0 → 292,941/54,948/36,632 | 256,330/234,763 → 238,014/234,763 | 0/0 → 0/0 | 695,748 → 659,116 |
| asphalt-table | 0:0 | 512 pixels visited, 346 written | 41,753 → 41,169 | 81.55 → 80.41 | -1.40% | 513/512/0 → 384/512/387 | 1,885/0 → 1,627/0 | 0/0 → 0/0 | 5,140 → 4,495 |
| asphalt-table | 2:9 | 512 pixels visited, 346 written | 41,753 → 41,169 | 81.55 → 80.41 | -1.40% | 513/512/0 → 384/512/387 | 1,885/0 → 1,627/0 | 0/0 → 0/0 | 5,140 → 4,495 |
| asphalt-double | 0:0 | 512 pixels visited, 172 written | 19,811 → 18,441 | 38.69 → 36.02 | -6.92% | 345/340/0 → 176/511/511 | 518/0 → 5/0 | 0/0 → 0/0 | 1,552 → 13 |
| asphalt-double | 2:9 | 512 pixels visited, 172 written | 19,811 → 18,441 | 38.69 → 36.02 | -6.92% | 345/340/0 → 176/511/511 | 518/0 → 5/0 | 0/0 → 0/0 | 1,552 → 13 |
| asphalt-single | 0:0 | 512 pixels visited, 343 written | 12,731 → 12,731 | 24.87 → 24.87 | +0.00% | 346/511/0 → 346/511/0 | 4/0 → 4/0 | 0/0 → 0/0 | 10 → 10 |
| asphalt-single | 2:9 | 512 pixels visited, 343 written | 12,731 → 12,731 | 24.87 → 24.87 | +0.00% | 346/511/0 → 346/511/0 | 4/0 → 4/0 | 0/0 → 0/0 | 10 → 10 |
| arm-stream | 0:0 | 128 loads | 343 → 337 | 2.68 → 2.63 | -1.75% | 133/6/0 → 12/0/129 | 2/3 → 0/3 | 0/0 → 0/0 | 5 → 0 |
| arm-stream | 2:9 | 128 loads | 343 → 337 | 2.68 → 2.63 | -1.75% | 133/6/0 → 12/0/129 | 2/3 → 0/3 | 0/0 → 0/0 | 5 → 0 |
