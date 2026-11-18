# Transferable ngage2 ideas after the 5K simulation

## First performance experiment: pick up an operand at execute

**Executed as Step5L:** the isolated original implementation measures forward
36,528→34,995 and reverse36,453→34,920 clocks, both latency profiles.
Retain for broader qualification and timing; production is unchanged.
[Measured schedule, safety and decision](cpu-late-operand.md).
The proposal and pre-experiment screen below are retained as provenance.

The donor distinguishes sources that must reach its shifter or multiplier early from an unshifted source that its ALU can pick up later. Its decoder classifies source use, and execute carries a pending producer match across a register boundary. The mainline already issues on load commit and has special late store-data handling. The new experiment would allow selected arithmetic consumers to enter an earlier stage while their older load still owns the result. Start with the two unshifted adds and the compare in the original Super Monkey Ball span. A compare requires the same cancellation and ordering protection for flags as an add requires for its register write.

I screened the existing combined-5K event journal without compiling either CPU. In each span pattern, I selected actual issues at PCs 0x10093e3c, 0x10093e5c and 0x10093e80 with two preceding edges present in the 1,400-edge trace. For **57 of 59** issues in each pattern the same valid consumer was waiting with a load lock two edges before issue and the global data stall was clear. One edge before issue that same consumer was still locked, and the older load had both ACK and data stall asserted. Per-site counts meeting both conditions were 18/20, 20/20 and 19/19. The complete-window issue-distance histograms cover 512 occurrences at each site. The bounded edge observations do not establish how many earlier consumers can advance through execute.

Test a single in-order consumer slot carrying one unresolved source tied to its exact older load. Try accepting it in the earlier free edge and forwarding the registered, permission-checked value when it reaches execute. A held load must keep the consumer stable. A fault, retry, failed condition, redirect or flush must suppress the younger result and flags or replay it exactly once as appropriate. Begin with a single outstanding eligible word load and ordinary arithmetic, excluding shifted values required early, PC and bank/context transitions. Keep permission/ACK/register-match logic off the combinational path to a new ALU result. The first trace should show whether useful execute, retirement and the following issue also advance. If only acceptance moves, stop or change the boundary.

One net clock saved at all three sites per pixel would be 1,536 clocks out of the 36,528-clock forward span (4.2%). This is a sensitivity calculation. Compare identical fixed work, then check original Thumb JPEG, independent streams and precise flag/fault behavior, plus fitted timing. The existing eight-line stream and frame-fill tests guard against trading away benefits elsewhere.

[Donor decode](../../ngage2/rtl/cpu/arm9v2/arm9v2_decode.sv) · [Donor execute](../../ngage2/rtl/cpu/arm9v2/arm9v2_execute.sv) · [Mainline issue](../rtl/arm/zap_issue_main.sv) · [5K full-window measurements](evidence/cpu-load-lookup-20261117.json) · [Bounded event journal](evidence/cpu-load-lookup-20261117.events.json.gz)

## Area experiment: bank the main TLB search

**Investigated offline:** full searches are common in matrix/JPEG, but the
corrected hit-row audit finds their scored hits in entries0–7. One eight-lane
BRAM-tag prototype preserves all64 entries and first-row latency; warm original
work matches qualified5L. Source storage/comparator reductions are measured
structurally; ALM/M10K mapping remains an estimate pending matched fit.
[Actual resource comparison, tests, costs and plan](tlb-area.md).
The original screening proposal below is retained as provenance.

Fitter **ALMs needed**, from the seed-42 5F master report and the supplied 16-November ngage2 report. Rows overlap hierarchically. The ngage2 build and local source checkout have separate provenance.

| Hierarchy | 5F | ngage2 |
|---|---:|---:|
| Whole design | 40,012.1 | 34,114.5 |
| CPU with caches and MMU | 18,483.3 | 14,752.5 |
| Execution core subtree | 6,446.5 | 8,726.0 |
| Instruction + data TLB subtrees | 4,620.9 | 2,414.2 |
| CPU DSP blocks | 3 | 3 |

The two 5F main TLB bank instances alone account for 4,042.5 ALMs. They each compare 64 mixed-page entries in parallel, including overlap handling at fill. Their payloads already live in block RAM. The stock donor partitions its translation structures differently. Our area experiment would preserve all 64 entries per side and every page size, with the existing checked-mapping fast path. First count actual main-bank lookups, mutations and exposed waits on JPEG, matrix, a translation-heavy case and boot. Then try an eight-bank, eight-entry-per-bank layout: read one row from each bank per clock, compare eight tags, scan up to eight rows. Prototype the tag RAM mapping and count actual M10Ks. Account for the slower full search on misses, mutation serialization, mixed-size and overlapping mappings, MVA invalidation, lockdown/preserve, and revocation of stale checked results. Measure ALMs, added RAM and cycles before adoption. The 2,207-ALM TLB hierarchy gap is context, not a savings estimate.

[Mainline TLB bank](../rtl/arm920/tlb_bank.sv) · [ARM920 TLB contract](arm920-tlb.md) · [Donor geometry and matched CPU measurements](ngage2-vs-5c-benchmark.md)

## DSP priority

The 5F multiplier subtree uses 126.4 ALMs and three DSP blocks. The donor CPU also uses three DSPs. Its source saves the product for accumulation. Mainline's previous full-product mapping already packed multiply input/output registers; the published earlier fit showed unused hard accumulation features, whose usability depends on the selected DSP mode. If multiply becomes the priority, test capture of the registered product plus addend in the existing result stage and compare elapsed dependent cycles, DSP inference and routed adder delay. The earlier span trace puts one accumulation hold per pixel at stake. The two multiplies in the largest sampled Asphalt loop use ordinary MUL, so an MLA-only shortcut would miss that pair.

[5I accumulation schedule](super-monkey-ball-span.md) · [DSP fit audit](dsp-mapping-audit.md) · [Asphalt trace](asphalt-urban-gt-profile.md)
