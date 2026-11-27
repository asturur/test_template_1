# v5 cache and CPU integration

All simulations use 78 MHz, 16 KiB per L1 with two ways and 32-byte
lines, the XOR section TLB, the production SDRAM pin and flash paths,
32 KiB flash caching, 39 MHz MMC and 64 Hz NOS. Production comparison
is exact `57ba6ef`. The matched CI comparison uses seed 42 and DDR
debugger on. Each build is pinned to an immutable commit through a
fit tag.

| Revision | Change | Fit |
| --- | --- | --- |
| `57ba6ef` | Production control | [Baseline](https://github.com/asturur/test_template_1/actions/runs/44643431578) |
| `4e1b12a` | Explicit early restart | [Early restart](https://github.com/asturur/test_template_1/actions/runs/44643422729) |
| `62264bb` | Early restart and hit under miss | [Hit under miss](https://github.com/asturur/test_template_1/actions/runs/44643427371) |
| `4c98d07` | Fold the branch target index | Included in combined candidate |
| `ead78c7` | Admit repeated scalar load destinations | Included in combined candidate |
| `619a9af` | Collapse failed ARM register lists | [Quartus parser failure](https://github.com/asturur/test_template_1/actions/runs/44645438493) |
| `91129ba` | Use a Verilog-2001 loop in repeat-load decoder | [Repaired combined stack](https://github.com/asturur/test_template_1/actions/runs/44646489373) |
| `c09a2b7` | Track lower and upper dirty halves independently | Reversible extension |
| `8064adc` | Add address-hinted two-word ARM LDM | [Quartus assertion elaboration failure](https://github.com/asturur/test_template_1/actions/runs/44647719381) |
| `ba06812` | Exclude the LDM assertion from synthesis | [Full extension fit](https://github.com/asturur/test_template_1/actions/runs/44648444968) |

The five changed production RTL inputs and their generator are
isolated in the commit chain. The cache candidates reproduce the earlier offline
netlists byte for byte. The four bound board integration files were
formatted with the repository formatter and compared ignoring
whitespace. The combined CPU source regenerates from the pinned
stock artifact and matches the full simulation candidate byte for
byte. Quartus selects these same file paths through `files.qip`.

## Simulation results

Clocks are medians of five scored fixed-work windows or three warm
native frames. Each fixed-work case checks its original output in
two complete runs and rejects a deliberately corrupted expected
result. Every native replay has the same retired work and 4,800
submitted triangles. Framebuffer, depth, indices and saved object
match byte for byte. The LDM column is a separate experiment on
hit-under-miss, without the three incremental CPU changes.

| Workload | Production | Early restart | Hit under miss | + BTB index | + repeat-load | + failed lists | Hit under miss + LDM |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| SPMark04 matrix | 16,814 | 16,814 | 16,817 | 16,841 | 16,841 | 16,841 | 16,817 |
| SPMark04 transpose | 2,772 | 2,769 | 2,769 | 2,769 | 2,769 | 2,769 | 2,769 |
| GLES triangle edges | 12,229 | 12,229 | 12,229 | 12,140 | 12,127 | 12,127 | 12,213 |
| GLES 16-bit frame fill | 112,705 | 112,705 | 112,705 | 112,652 | 112,652 | 112,652 | 112,705 |
| GLES 16-bit tail fill | 726 | 726 | 726 | 719 | 719 | 719 | 726 |
| GLES 8-bit tail fill | 747 | 747 | 747 | 747 | 747 | 747 | 747 |
| Monkey Ball forward | 15,934 | 15,931 | 15,931 | 15,931 | 15,931 | 15,931 | 15,931 |
| Monkey Ball reverse | 15,934 | 15,931 | 15,931 | 15,931 | 15,931 | 15,931 | 15,931 |
| Sega Rally textured span | 15,424 | 15,424 | 15,424 | 15,424 | 15,424 | 15,424 | 15,424 |
| Sega Rally solid fill | 2,622 | 2,622 | 2,622 | 2,622 | 2,622 | 2,622 | 2,622 |
| Asphalt table | 21,396 | 21,396 | 21,394 | 21,385 | 21,127 | 21,127 | 21,394 |
| Asphalt double lookup | 11,961 | 11,961 | 11,961 | 11,961 | 11,961 | 11,961 | 11,961 |
| Asphalt single lookup | 7,756 | 7,756 | 7,756 | 7,747 | 7,747 | 7,747 | 7,756 |
| Sega Rally full scan | 2,391,228 | 2,391,228 | 2,391,228 | 2,391,224 | 2,391,224 | 2,391,224 | 2,391,228 |
| Thumb JPEG 8×8 | 35,903 | 35,903 | 35,903 | 35,524 | 35,324 | 35,324 | 35,903 |
| Native PolyCount | 14,928,261 | 14,696,883 | 14,472,614 | 14,361,808 | 14,346,494 | 14,281,218 | 14,464,555 |

The folded BTB saves another **110,806 native clocks** on top of
hit-under-miss and costs 24 matrix clocks in the median. Repeated
scalar load admission saves **15,314 native**, 258 Asphalt table,
and 200 JPEG clocks on top of the BTB change. Failed-list collapse
saves **65,276 more native clocks** and ties all fixed-work windows.
The full candidate's worst fixed-work regression versus production
is 42 matrix clocks in one scored window. Its median matrix
regression is 27 clocks.

The full stack saves **647,043 native clocks (4.33%)**, giving
**26.22 Ktriangles/s** at 78 MHz and 2,975.25 clocks per triangle.
That leaves 867.25 clocks per triangle to the 2,108 target. The
saved native cycles range from 643,195 to 651,746 across all four
original frames. The full candidate passes all four memory profiles
in each of the directed predicate/abort, branch and Thumb IRQ,
load-forwarding/order, multiply/shift and I-cache/permission suites.

## Dirty halves and two-word LDM on the full CPU

Quartus 17 rejected a SystemVerilog loop in the repeat-load decoder
before synthesis. The Verilog-2001 repair `91129ba` passes the parsing
check and exactly reproduces every fixed-work window and native frame
clock from `619a9af`. The full extension regenerates byte-for-byte
from the same pinned stock donor. Quartus elaborated a simulation-only
assertion in `8064adc`, so `ba06812` explicitly excludes that block
from synthesis. The generated Verilog changes by two comment lines.

| 78 MHz replay | Native PolyCount clocks | Clocks/triangle | Ktriangles/s | Sega Rally scan clocks | Scan writeback blocks | GLES triangle-edge clocks |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `91129ba` | 14,281,218 | 2,975.25 | 26.216 | 2,391,224 | 4,274 | 12,127 |
| `c09a2b7` | 14,276,385 | 2,974.25 | 26.225 | 2,389,539 | 3,358 | 12,127 |
| `8064adc` | 14,264,843 | 2,971.84 | 26.246 | 2,389,539 | 3,358 | 12,114 |

Dirty-half tracking skips 916 unmodified 16-byte writeback blocks in
the scan. The independent index-clean and backing-memory checks pass
on all four bus profiles. The native warm frame saves 4,833 clocks,
and the 16-bit fill saves two clocks. The other 13 fixed-work medians tie.

The hinted LDM path handles ARM LDMIA with two ordinary destinations
and no base writeback. A resident same-line response can commit both
words. The serialized path rechecks the next effective address. Tests
cover base/destination overlap, a failed predicate with an unmapped
base, and a forced stale hint that causes a second-word translation
abort. In that case the first destination commits, the second stays
unchanged, and CP15 reports the second address. All four bus profiles
pass for these cases and the separate failed-list and IRQ suite.

Hinted LDM removes 36,645 interior operations from the middle-ranked
native frame and saves 11,542 elapsed clocks on top of dirty halves.
It improves the triangle-edge median by 13 clocks, with one five-clock
slower window. The other 14 fixed-work medians tie. The original
guest renders 4,800 triangles per frame and retires the same 7,322,287
instructions in the middle-ranked frame, with matching framebuffer,
depth, indices and object. The complete extension saves 663,418 clocks
(4.44%) versus the production control and remains 864 clocks per
triangle above the 2,108 target. The replay uses the captured original
draw with production memory RTL. A board score still requires a native run.

The middle-ranked frame's counters account for every elapsed clock.
Exposed refill stalls, walks and execution waits are disjoint. A change
can move clocks between bins as instruction issue overlaps a refill.

| Clock category | `57ba6ef` | `91129ba` | Full extension |
| --- | ---: | ---: | ---: |
| Architectural retirements | 7,322,287 | 7,322,287 | 7,322,287 |
| Interior operations | 1,110,106 | 1,039,189 | 1,002,544 |
| Exposed I-refill waits | 1,432,956 | 1,467,714 | 1,463,712 |
| I-walk waits | 608 | 1,006 | 1,029 |
| D-cache waits | 304,621 | 286,480 | 285,929 |
| D-walk waits | 0 | 23 | 23 |
| Execution wait | 597,577 | 547,742 | 552,071 |
| Frontend wait | 2,474,291 | 1,483,067 | 1,481,860 |
| Other | 1,685,815 | 2,133,710 | 2,155,388 |
| Total elapsed | 14,928,261 | 14,281,218 | 14,264,843 |

## Other CPU and cache experiments

| Earlier change | Disposition |
| --- | --- |
| Ready ARM register shift, independent early SMULL, direct DSP accumulate | Already in `57ba6ef`. |
| XOR section TLB and 16-byte transfers from dirty victims | Already in `57ba6ef`. |
| Two-word LDM writeback pairing | The earlier merge-only path saved 30 clocks. Early issue supersedes it. |
| Address-hinted two-word ARM LDM issue | The isolated `62264bb` experiment saves 8,059 native clocks. The qualified full stack saves 11,542 clocks from this change after dirty halves. The assertion tracks actual predicate collapse so it can distinguish a passed pair with matching first/last flags. |
| Passed STM/PUSH pairing | Workload eligibility and optimistic estimates exist. The production cache accepts one word per clock and a working two-value write path is still unimplemented. |
| Scalar W-hit forwarding | Existing execute already consumes the first confirmed W hit. The new repeated-destination guard covers a different interlock. |
| 32 KiB I-cache, alternate ways, ideal I hits | Separate geometry change or diagnostic. This task holds 16 KiB and two ways. |
| Packed metadata with whole-line dirty tracking | The packed control exactly matches the combined timing windows. The useful variant is the independent dirty halves in `c09a2b7`. |
| Earlier scalar SDRAM admission / immediate response | Measured against the retired JTFRAME integration. Current streaming controller and posted/16-byte writeback already replace that path. |

[Early restart](arm9v2-icache-restart.md) ·
[Hit-under-miss](arm9v2-icache-hum.md) ·
[Decoder and predicate tests](arm9v2-decoder-splits.md).

## Seed-42 routed comparison with DDR debugger enabled

| Commit | ALMs | Registers | RAM blocks | DSP blocks | Worst 78 MHz setup | Worst 104 MHz setup | SDRAM pin check |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `57ba6ef` | 39,338 | 44,729 | 444 | 46 | −1.410 ns | −4.615 ns | Pass |
| `4e1b12a` | 39,793 | 43,533 | 444 | 46 | −1.846 ns | −5.051 ns | Pass |
| `62264bb` | 39,802 | 44,096 | 444 | 46 | −1.092 ns | −4.297 ns | Pass |
| `91129ba` | 39,889 | 44,334 | 444 | 46 | −1.620 ns | −4.825 ns | Pass |
| `ba06812` | 40,714 | 44,313 | 444 | 46 | −2.434 ns | −5.639 ns | Pass |

The 104 MHz columns use the 78 MHz routed database with the core clock
retargeted in TimeQuest. Clock fanout, unrelated clocks and timing
exceptions are checked. All first three revisions produced RBFs and
failed the 78 MHz setup gate. Baseline's worst path runs from CPU W
valid into the SDRAM scheduler. The other two land in the DDR
telemetry snapshot RAM. The CPU's own paths into the DSP input
register also miss 78 MHz by 1.504 ns and 1.077 ns respectively in the
worst setup corner. The baseline CPU-only debt there is 0.998 ns.
The resident-hit build improves global setup slack by 0.318 ns versus
the baseline and stays 4.297 ns short of the diagnostic 104 MHz goal.
The repaired combined stack's worst setup path goes from the D-cache
FSM's live-hit trust signal to the execute multiplier's high-half
input register. In the full extension, CPU writeback valid reaches
that multiplier input on the worst path. It adds 825 ALMs versus
`91129ba` and uses 97.1% of available ALMs. RAM and DSP counts match.
At 78 MHz the five builds pass hold, recovery, removal and pulse-width
checks. The full extension also misses recovery by 1.335 ns in the
104 MHz retargeted analysis. A separate half-only fit would be needed
to attribute the extension's routed cost to dirty halves or LDM.

All five routed revisions missed the 78 MHz timing gate. Andrea
subsequently promoted `ba06812` with its measured timing debt. The
local branch and GitHub `ngage-v5` were verified at that commit. Both
corrected candidates and the three cache controls have verified
fit-only tags and archived RBFs. Board verification is pending.

[Best routed setup slack, `62264bb`](https://github.com/asturur/test_template_1/actions/runs/44643427371/artifacts/14588454370) ·
[Fastest offline replay, `ba06812`](https://github.com/asturur/test_template_1/actions/runs/44648444968/artifacts/14591819074).

## Timing repair on promoted `ba06812`

The worst setup path in the slow 1,100 mV, 100 °C model launches from
core `w[541]` (writeback valid) on the 78 MHz core clock and ends at
`u_execute|Mult0~mult_hh_pl[0][0]` on that same clock. TimeQuest lists
11 logic levels and 14.730 ns of data delay. Summing the incremental
delays after the launch clock gives 8.988 ns of routing elements,
5.744 ns of cell delay (including 3.549 ns at the DSP endpoint), and
−0.002 ns of interconnect adjustment. Clock skew is −0.224 ns. The
104 MHz diagnostic retains the same data delay through the same path.

The named cells trace `w[541]` through the paired-LDM completion and
split logic, the forwarded `operand[68]`, `shift_amount[4]`, the
barrel-shifter cells, and the early `product_left` mux. There are 28
high-partial DSP endpoints at −2.434 ns and 36 low-partial endpoints
at −2.390 ns, all launched by `w[541]` in the exported worst-per-endpoint
set. The `direct_reg_shift` condition requires `DP`. Early SMULL
requires `MULL` and its decoded shift amount is zero. The RTL candidate
feeds the selected unshifted operand to `product_left` only on early
launch. It keeps the W-load/forwarding selection, the launch and
product-ownership rules, and the ordinary DP shifter.

| Other limiting path on the core PLL | 78 MHz setup | 104 MHz setup |
| --- | ---: | ---: |
| Wishbone merger address to SDRAM scheduler `PRE_WAIT` | −2.064 ns | −5.269 ns |
| CPU W valid to decoder packet `d2_q[122]` | −2.010 ns | −5.215 ns |
| UPP PCM owner to DMA buffer control | −1.962 ns | −5.167 ns |

The separate HDMI, HPS, 50 MHz input and audio PLL clock groups all
pass reported setup in the physical 78 MHz build. HDMI is the tightest
of those groups at +0.397 ns. The 104 MHz retarget changes the core
PLL clock and preserves unrelated clock definitions. It also exposes
an independent −1.335 ns recovery violation from the SDRAM scrub-done
register to the core reset-drain register. Fixing the DSP data path
alone leaves the paths above to close.

The matched Verilator runs pass all 15 fixed-work cases with identical
clock windows and memory counters. Each of the four original PolyCount
frames matches clocks, retirements, interior operations and output
bytes. The warm median remains 14,264,843 clocks for 4,800 triangles.
The four directed profiles also match, with ten early SMULL launches
and one using the W-load operand in each. The guest checks warm and
cold forwarding, resident LDM destinations, multiply flags, conditional
failure and a precise load abort before the dependent SMULL.

The bypass is committed as `cd36f15` and pushed to `ngage-v5`. The
requested build uses seed 42 with DDR debug disabled and the same
78/104 MHz timing reports. Both the operand path and debugger setting
differ from the routed `ba06812` control, so the result measures their
combined impact. [Build run](https://github.com/asturur/test_template_1/actions/runs/44694095878)

The fit completed and passed SDRAM pin checks. It uses 37,873 ALMs,
41,787 registers, 438 RAM blocks and 46 DSP blocks. Setup slack is
−2.128 ns at 78 MHz and −5.333 ns in the 104 MHz diagnostic. The worst
path is now CPU writeback valid to the SDRAM scheduler. The worst
multiplier input path in the slow 100 °C corner is −0.485 ns at 78 MHz
and −3.690 ns at 104 MHz. The verified RBF was archived with
`ENABLE_DEBUGGER=0`. [RBF artifact](https://github.com/asturur/test_template_1/actions/runs/44694095878/artifacts/14611847456)

The slow 100 °C report traces writeback valid through Wishbone and
scalar request acceptance, the memory address mux and comparison, and
the SDRAM scheduler's timing counter `t[4]`. The data delay is 14.176 ns
over 15 logic levels, with 9.628 ns of routing elements, 4.553 ns of
cell delay and −0.005 ns of interconnect adjustment. A separate
writeback-to-MMC host path misses setup by 2.093 ns at 78 MHz.
[Quartus logs](https://github.com/asturur/test_template_1/actions/runs/44694095878/artifacts/14611543668)


## Reproduce the accepted simulation stack

The pinned stock donor and the final generated Verilog can be
compared directly without a new FPGA build.

```sh
python3 tools/gen_arm9v2_phone.py --check --stock /Users/andreabogazzi/develop/ngage2/rtl/cpu/arm925t_gen.v
pin=build/sim/unit-hardware-boot-real-sdram/mt48lc16m16a2-verilator.v
python3 tests/cpu/arm9v2_board/payload_clocks.py --name v5-recheck \
  --config 2:64 --flash-cache-bytes 32768 --stream-sdram --block-writeback --sdram-model "$pin"
python3 tests/cpu/polycount_v5/run.py --name v5-recheck --legs i16 \
  --capture build/sim/polycount-v5/native-qualified --pin-model "$pin"
```

[Raw simulation timing windows and directed outcomes](evidence/arm9v2-v5-combined-20261120.json).
