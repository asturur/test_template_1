# Retimed probe matched full-core fit — Stop 3D, 16 November 2026

**Sequencing update:** the timing recommendation below records the fitter
review. The project proceeds with the offline [Step 4A CPU overlap experiment](cpu-store-overlap.md)
on this baseline, with timing qualification at a later integrated milestone.

**Further retiming is required before CPU admission.** Keep Stop 3C as a useful
isolated baseline: global setup improves by **0.773 ns hot / 1.214 ns cold**
against Stop 3B at both clock scenarios. The bounded +1.4435% worst workload
cycle cost bought measurable routed improvement. It did not buy closure:
worst setup is **−0.553 ns at 78 MHz / −3.758 ns at 104 MHz**. The main remaining
family is live resident admission through SWP/CPU exclusion; certificate matching
and arbitration into physical RAM-B also still miss 104 MHz. The probe delay
has partly moved into RAM-B, rather than disappeared.

## Run and exact input selection

One fit only: [run 43906110604](https://github.com/asturur/test_template_1/actions/runs/43906110604),
commit `418f6f824ab2e3353f71692382770433d5f0c093`, tree
`a04e3854bc666028d951ae1e84bc471aecde5461`, fit-only tag
`fit-only/probe-retime-3c-20261116-s42-01`. Parent is exact production
`9c948da8da413a882e0fe8e559c380ea0cadabf4`. The former origin name
`asturur/NGage_MiSTer` resolves to the same repository ID 1434988755 as
`asturur/test_template_1`; publication and collection used only `gh`.

Quartus **17.0.2 Build 602 Lite**, Cyclone V **5CSEBA6U23I7**, **seed 42**,
**debugger enabled**, same QIPs, SDCs and physical **78 MHz PLL** as the controls.
The full compile succeeded in 28m42s. Worst-1000 export, actual input manifest,
both scenario analyses, SDRAM pin packing and report upload succeeded. Only the
normal timing gate failed; the job's red conclusion is not a failed fit or an
incomplete analysis. Scenario errors.txt is empty. No second seed/run was used.

The four cache substitutions below exactly match the qualified Stop 3C hashes.
Production BRAM is selected; the unit-test collision-poison BRAM is excluded.

| Selected design file | SHA256 |
| --- | --- |
| rtl/arm920/cache_access.sv | `15f2e214cecaa04801425900b1ced560759496b85383f198e3c908c681257c13` |
| rtl/arm920/cache_adapter.sv | `c0fd8d256523241a0cbb98472434093bb85039243cfe06126c83eaf172c9bf78` |
| rtl/arm920/cache_bank.sv | `010b7e116a5651442c2fcfc05e8a4f931c07238728ae706e0bc2c95bbf6d70b7` |
| rtl/arm920/cache_tags.sv | `0291d169a7cd4a1e9a332ed652e5c9d5428ee1ad0bf3898ff154f3a44a274c3f` |
| rtl/ngage_bram.v (production) | `df7aa84abdca0e585b062c077cb01b0b9c9961316851b37a72622738e103ba71` |

Direct immutable-tree comparison with Stop 3B commit
`7aa1a418bbf2d0ba28c215015f10e1412e6dc171` proves **only cache_access.sv and
cache_adapter.sv differ in design RTL**. Bank/tags and all other design inputs
are identical. The other four differing files are isolated workflow/manifest/
expected-input/report support. GitHub's compare endpoint uses the common parent
for these sibling commits, so the direct tree comparison, not that merge-base
diff, establishes this fact.

The repaired manifest passed both host and `/project` path preflights and the
actual CI step. It records 178 selected inputs and unique definitions for
adapter/access/bank/tags/BRAM. **177 SHA256 values equal preflight exactly.**
Quartus rewrote only QSF metadata `LAST_QUARTUS_VERSION` from “17.0.2 Standard
Edition” to “17.0.2 Lite Edition”; the entire remaining QSF text, including
seed/debug/constraints, matches exactly. This is explicitly verified, not a
blanket QSF exemption. The saved input proof is the successful **postcompile
in-job** manifest, not the reconstructed Stop 3B proof.

## Whole-chip resources and packing

Stock is run 43866215058 on 9c948da8, separately from the primary Stop 3B control
run 43886019102. All three use the matched seed/debug/PLL configuration.

| Resource | Stock | Stop 3B | Stop 3D | 3D − 3B |
| --- | ---: | ---: | ---: | ---: |
| ALMs | 39,594 | 39,535 | 39,549 | +14 |
| registers | 44,682 | 44,752 | 45,104 | +352 |
| M10Ks | 503 | 503 | 503 | +0 |
| DSPs | 41 | 41 | 41 | +0 |
| occupied_LABs | 4,191 | 4,179 | 4,182 | +3 |
| MLABs | 40 | 40 | 40 | +0 |
| placed_ALMs | 40,801 | 40,344 | 40,474 | +130 |
| routing_registers | 3,401 | 2,916 | 3,363 | +447 |
| design_registers | 41,162 | 41,717 | 41,622 | -95 |

ALMs **needed** meet the 40,450 planning screen with **901** remaining; 503
M10Ks leave **18** to the 521 stop. Packing remains tight: only **nine** LABs
are empty versus twelve in Stop 3B. Final **placed** ALMs are **40,474**
(+130), 24 above the numeric 40,450 threshold if it is applied to placement
rather than the review's ALMs-needed metric. These metrics are not interchangeable;
901 is not a promise of easily usable packing room. Total registers rise 352,
comprising −95 implementation registers and +447 routing-optimization registers;
the I/O-register contribution is unchanged. Do not attribute the whole physical
register delta to the nominal +22 RTL state-bit estimate.

CPU hierarchy figures below include children; do not add these rows together.
ALM figures are the fitter's fractional “ALMs needed” attribution.

| Hierarchy | Stock ALMs | 3B ALMs | 3D ALMs | Delta | 3B → 3D registers | M10Ks |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| CPU total | 17,521.1 | 17,881.0 | 17,761.3 | -119.7 | 18462 → 18368 | 168 |
| Execute core | 5,986.8 | 5,995.4 | 5,970.1 | -25.3 | 5847 → 5726 | 7 |
| I adapter + cache | 2,363.4 | 2,437.3 | 2,457.6 | +20.3 | 2602 → 2622 | 77 |
| D adapter + cache | 4,131.9 | 4,291.1 | 4,258.2 | -32.9 | 4625 → 4618 | 82 |
| D access + bank | 3,957.4 | 4,123.9 | 4,094.3 | -29.6 | 4510 → 4456 | 82 |

CPU total decreases 119.7 attributed ALMs while whole-chip needed ALMs increase
14. This is physical optimization/packing redistribution, not proof that a
new register stage is free. I-cache stays 77 M10Ks, D-cache 82, CPU total 168;
whole-chip MLAB/DSP counts remain 40/41.

## Routed timing and matching corners

Normal slow-100C 78 MHz results, ns:

| Clock | Stock setup | 3B setup | 3D setup | 3D − 3B |
| --- | ---: | ---: | ---: | ---: |
| CPU/core | -0.811 | -1.326 | -0.553 | +0.773 |
| HDMI | +0.432 | -0.101 | +0.051 | +0.152 |
| HPS user | +3.135 | +2.709 | +2.512 | -0.197 |
| FPGA_CLK1_50 | +8.219 | +7.994 | +6.908 | -1.086 |
| FPGA_CLK2_50 | +8.265 | +12.099 | +7.449 | -4.650 |
| Audio | +22.820 | +20.544 | +21.826 | +1.282 |

CPU TNS improves **−13.963 → −2.933 ns** (stock −13.752). Normal CPU hold
is **+0.236 ns**, versus +0.194 in 3B and +0.251 stock. HDMI returns to
**+0.051 ns**, a small margin; its RTL did not change. Stock CPU setup remains
a separate −0.811 ns reference, so 3D improves on it by 0.258 ns. No measured
stock 104 MHz analysis is available.

Global minimum slacks across constrained clocks, ns. Slow corners are CPU
limited; at 78 MHz fast corners HDMI is worst. These are actual routed analyses,
not Fmax conversion or slack subtraction.

| MHz | Corner | Setup | Δ setup vs 3B | Hold | Recovery | Removal | Min pulse |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 78 | Slow 1100mV 100C Model | -0.553 | +0.773 | +0.209 | +2.995 | +1.406 | +0.641 |
| 78 | Slow 1100mV -40C Model | -0.306 | +1.214 | +0.093 | +3.323 | +1.308 | +0.641 |
| 78 | Fast 1100mV 100C Model | +2.824 | +0.436 | +0.108 | +4.874 | +0.698 | +0.641 |
| 78 | Fast 1100mV -40C Model | +3.476 | +0.337 | +0.052 | +5.178 | +0.593 | +0.641 |
| 104 | Slow 1100mV 100C Model | -3.758 | +0.773 | +0.209 | -0.210 | +1.406 | +0.480 |
| 104 | Slow 1100mV -40C Model | -3.511 | +1.214 | +0.093 | +0.118 | +1.308 | +0.480 |
| 104 | Fast 1100mV 100C Model | +1.962 | +0.060 | +0.108 | +4.054 | +0.698 | +0.480 |
| 104 | Fast 1100mV -40C Model | +2.824 | +0.315 | +0.052 | +4.903 | +0.593 | +0.480 |

The 3B hot/cold setup pair **−1.326/−1.520** becomes **−0.553/−0.306** at
78 MHz; **−4.531/−4.725** becomes **−3.758/−3.511** at 104 MHz. All corners
have positive hold/removal/minimum-pulse minima. Hot 104 MHz recovery still
fails **−0.210 ns**, now `phone_reset_gate|phone_reset` →
`reset_drain~SynDup_56` (8.917 ns data; 1.224 cell / 7.696 routing), rather
than the former loader-slot path. This remains a separate reset-distribution gate.

## Resolve and measure the new probe boundary

The actual queried D-cache prefix is
`...|zap_dcache:l_generate_with_cache_mmu.u_data_cache|arm920_cache_adapter:cache_adapter`.
Every group saves its resolved keeper names/counts, reported count and full
routed path details. Counts are **reported worst distinct-endpoint paths**,
capped at ten; they are not the total number of timing paths.

The fitter retains **five P1-named tag keepers** (bits 0,1,6,17,20), **28
P2-named tag keepers** including duplication, and both named valid keepers.
These are actual surviving names, not a claim that all 54 nominal payload bits
retain their RTL names after physical optimization. Together the hint query
resolves 35 keepers. The result query resolves **27 tag + 6 way + 1 valid = 34**
keepers. Physical RAM-B resolves **144 address + 16 read-enable keepers** across
the sixteen data M10Ks, with names such as
`...|bank|lines|words[0].ram|ram|auto_generated|ram_block1a0~portb_address_reg0`.
Reported hint/certificate paths reach real address registers. The primitive
ties `rden_b` high and bypasses input clock enables; no changing read-enable
timing path is claimed from the existence of a keeper name alone. Runtime
probe permission/collision gating survives in the **address selection mux**.

| Group | From/to keepers | Paths hot/cold | 78 hot slack | 104 hot | 104 cold | Hot data / cell / route | Hot levels |
| --- | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| any_to_p1_tags | 78158/5 | 5/5 | +8.892 | +5.687 | +5.832 | 3.508 / 0.612 / 2.896 | 0 |
| any_to_p2_tags | 78158/28 | 10/10 | +6.670 | +3.465 | +3.637 | 5.742 / 1.202 / 4.539 | 2 |
| any_to_hint_valid | 78158/2 | 2/2 | +5.618 | +2.413 | +2.594 | 6.399 / 1.683 / 4.717 | 3 |
| hints_to_ram_b | 35/160 | 10/10 | +0.863 | -2.342 | -2.203 | 11.122 / 4.339 / 6.784 | 8 |
| certificate_to_ram_b | 388/160 | 10/10 | +0.500 | -2.705 | -2.461 | 11.499 / 2.736 / 8.765 | 7 |
| any_to_ram_b | 78158/160 | 10/10 | +0.500 | -2.705 | -2.461 | 11.499 / 2.736 / 8.765 | 7 |
| hints_to_result | 35/34 | 10/10 | +1.511 | -1.694 | -1.425 | 10.552 / 3.901 / 6.651 | 8 |
| certificate_to_result | 388/34 | 10/10 | +1.531 | -1.674 | -1.570 | 10.432 / 4.084 / 6.346 | 7 |
| any_to_result | 78158/34 | 10/10 | +1.493 | -1.712 | -1.570 | 10.480 / 3.931 / 6.548 | 7 |
| reset_to_downstream | 82/194 | 10/10 | +2.897 | -0.308 | -0.019 | 9.365 / 2.734 / 6.633 | 5 |
| pipeline_to_downstream | 2/194 | 10/10 | +3.430 | +0.225 | +0.397 | 8.622 / 2.735 / 5.887 | 5 |
| completion_to_downstream | 180/194 | 0/0 | — | — | — | no paths | — |
| any_to_pipeline | 78158/76 | 10/10 | +0.567 | -2.638 | -2.623 | 11.425 / 4.172 / 7.253 | 9 |
| certificate_to_owner | 388/7 | 7/7 | +1.843 | -1.362 | -1.205 | 10.140 / 3.400 / 6.742 | 8 |
| reset_to_store_payload | 82/74 | 10/10 | +0.862 | -2.343 | -2.160 | 11.186 / 2.618 / 8.570 | 10 |
| dirty_forwarding | 161/14 | 7/7 | +4.912 | +1.707 | +1.746 | 7.499 / 2.721 / 4.780 | 6 |
| pipeline_to_any | 2/78158 | 10/10 | +2.647 | -0.558 | -0.604 | 9.447 / 3.484 / 5.967 | 7 |
| result_to_any | 34/78158 | 10/10 | +1.086 | -2.119 | -1.695 | 11.033 / 2.571 / 8.461 | 10 |

The adapter register inputs pass at 104 MHz. Incoming P2 still launches from
the physically optimized completion register `o_next~1_OTERM241`, but ends at
`probe_p2_tag_q[12]` with **+3.465 ns**; its valid input has **+2.413 ns**.
Thus the cut is physically useful, not inferred from missing old endpoints.

The downstream worst probe path is explicitly:

`line_result_tag[6][23]~DUPLICATE` → `probe_matches[6]` → `probe_way` →
combinational `probe_owner_way[5]` → `probe_read~1` → bank address mux →
**data RAM** `words[0]...portb_address_reg0`.

It has **11.499 ns data, 2.736 cell / 8.765 routing**, and **−2.705 ns hot104**
(+0.500 hot78). Cold uses `line_result_tag[3][22]` and misses by 2.461 ns.
Registered P2 hints themselves miss RAM-B by **2.342 ns**; hint-valid/certificate
qualification into `probe_result_tag[3]/[2]` misses by **1.694/1.674 ns**.
The old probe-owner FF is gone, but matching, slot selection, collision and
physical-port arbitration now occupy this next clock. The local path improved
relative to the old −4.531 ns probe family, but its delay partly moved to RAM-B.

Reset still reaches RAM-B through `line_result_revoke` → `probe_read` → bank
mux, **−0.308 ns hot104** (−0.019 cold). `pipe_owner` still reaches RAM-B
address control, but that query now passes **+0.225/+0.397 ns**, compared with
the old owner→probe **−2.366/−2.497 ns**. The completion→downstream query matches
180/194 keepers and reports **zero paths at every corner**. This is recorded
as an empty path group, never as timing margin or proof of whole-design closure.
Its interpretation is supported by the nonempty incoming-hint and hint→RAM
queries, plus actual global/control path walks; no old renamed owner endpoint
is being used to claim improvement.

Consumer feedback remains: `probe_result_way[1]` → adapter **fast_hit** →
CPU exclusion misses **−2.119 ns hot104 / −1.695 cold** (11.033 ns data hot).
The path is in the routed report, so completion/fast return is not globally
decoupled by the private hint cut.

## What is limiting now

Both slow corners' global worst starts at the fitter's completion-derived
`u_data_completion|o_next~1_OTERM241` (physical launch
`o_next~1_NEW_REG240|q`) and ends at
`cpu_inside.block_cpu~0_OTERM8030` / `block_cpu~0_NEW_REG8029|asdata`.
Hot data delay is **12.651 ns = 3.647 cell + 9.005 routing −0.001 IC**,
ten logic levels. Cold is **12.427 = 4.211 + 8.216**, also ten levels.
The actual chain is completion-next → selected demand address → demand
certificate/result_slot → result mux → **accept_demand** → SWP ownership/
CPU exclusion. It is distinct from the new private probe pre-read chain.
The SWP ownership register already exists in RTL; simply recommending “add a
LOCK register” would repeat existing circuitry. Physical optimization has
distributed/retimed ownership logic into board exclusion consumers.

Top-100 global path families, measured at 104 MHz (counts are capped sample
counts, not whole-netlist totals):

| Family | Hot count / worst | Cold count / worst |
| --- | --- | --- |
| CPU exclusion | 2 / -3.758 (VIOLATED) | 2 / -3.511 (VIOLATED) |
| SWP to board/peripheral | 36 / -3.535 (VIOLATED) | 24 / -3.205 (VIOLATED) |
| other | 20 / -3.365 (VIOLATED) | 37 / -3.185 (VIOLATED) |
| D-tag RAM-B | 38 / -3.343 (VIOLATED) | 31 / -3.135 (VIOLATED) |
| D-adapter saved fault | 4 / -3.204 (VIOLATED) | 6 / -3.240 (VIOLATED) |

In particular, **SWP owner→DMA/peripheral exclusion** independently misses
**−3.535 ns hot / −3.205 cold**. Hot representative:
`cache_adapter|swp_lock_active` → DMA engine0 `source_left[0]_OTERM8128`,
12.327 ns data, 2.992 cell / 9.334 routing, nine levels. Completion→packed
**tag RAM** port-B address (distinct from data RAM above) misses
**−3.343/−3.135 ns**, and saved fault-context inputs miss −3.204/−3.240 ns.
A probe-only fix cannot clear these shared request/exclusion families.

The prior separate store paths remain open: general admission→`pipe_mva[3]`
is **−2.638/−2.623 ns**, now from the completion-derived launch; reset→same
payload is **−2.343/−2.160 ns**; certificate→store owner/way is
**−1.362/−1.205 ns**. Hot 3B references were −2.283, −2.283 and −1.168 ns.
Dirty forwarding itself remains positive **+1.707/+1.746 ns**, though with
less margin than 3B +2.568/+2.631. Separately, pipe_owner→commit_dirty ingress
is −0.558/−0.604 ns; a passing selected dirty-merge group does not cover every
control arriving at dirty state.

## Smallest justified next work and workload cost

**Do not widen CPU issue/admission yet.** First isolate a prequalified, locally
owned resident request/class/slot credit **before accept_demand and the existing
SWP ownership boundary**. Keep immediate kill/reset suppression on small valid
bits rather than feeding wide payload capture enables. The global evidence
also requires a local sampled grant/exclusion boundary before board-wide SWP
fanout; preserve SWP atomicity, drain of accepted DMA/external beats and
exclusion before issuing an external cycle. Blindly delaying LOCK is not a fix.
This targets the measured −3.758 ns admission/exclusion family rather than
another rewrite of the already-registered raw hint inputs.

On the private read side, split the certified physical slot/read intent from
RAM-B arbitration and result publication. A registered slot/valid boundary,
with revoke/collision suppressing publication rather than wide address/payload
enables, is the next bounded experiment for the **−2.705 ns** family. It may
cost a read clock; replay the one-clock admission ownership tests and matched
CPU workloads before accepting that cost. Do not claim one added FF stage
closes all families: shared store qualification, board fanout and reset
recovery are separately measured failures.

Stop 3C's unchanged offline gates already proved both five-stream variants:
256 accepts/actual RAM writes/replies each, every gap one clock, latency two,
correct same-line dirty halves and zero measured external traffic. All 20
matched CPU workload/profile groups passed independent oracles/repeats. Worst
cost is matrix **+1.4435% cycles**, JPEG **+1.0259–1.0515%**; equal-weight
throughput indices are 99.81843 and 98.97358 with Stop 3A=100. This fit changes
none of those sources or simulated schedules and does not repeat those tests.
Keep 3C for the next isolated revision because routed benefit is real and the
cost is bounded. It is not yet justified for production adoption, a frequency
increase, or coupling additional CPU issue to this live admission path.

## Clock and external I/O coverage

The validated 3B analysis rewrites only existing generated core VCO/output
clock relationships in TimeQuest, on the same routed database. Physical PLL
HDL stays 78 MHz. Core periods/waveforms are **12.820 ns / 0,6.410** and
**9.615 ns / 0,4.807**. Clock names, masters, targets and fanout are preserved;
all nine unrelated clock rows match exactly, and 51 explicit exception/delay
rows match exactly. Derived uncertainty is recomputed (44 rows each).
104 MHz relationship/fanout coverage reports PASS. No fitting or synthesis
was repeated for this hypothetical scenario.

All corners/scenarios report zero generated-clock, uncertainty, loop and latch
issues. The expected physical-PLL cross-check is zero at 78 and one at 104.
Existing 2,473 no-clock and 86 multiple-clock objects remain; hard-IP objects
are among them. UCP is 20 input ports/46 paths and 86 output ports/**167** paths
(3B 168, stock 170). Missing-input/output-delay checks are 30/129. External
SDRAM DQ inputs still lack explicit min/max I/O budgets and the forwarded
SDRAM_CLK port lacks its generated clock. **Full 104 MHz I/O signoff is not
qualified.** No guessed board delays or new waivers were added.

All sixteen SDRAM DQ **input/output/OE registers pass I/O-cell packing**, both
in CI and the independent local report check. Packing is separate from the
missing external timing coverage and does not establish release closure.

## Evidence, collection and stopping point

- [Compact results and full endpoint identities](evidence/cache-probe-admission-retime-fit-20261116.json).
- [Actual successful CI input manifest](evidence/cache-probe-admission-retime-fit-inputs-20261116.json).
- [Stop 3C source/schedule/workload evidence](cache-probe-admission-retime.md).
- [Primary Stop 3B fit](cache-resident-store-pipeline-fit.md).
- Raw reports, job log, run/tree identity and comparisons: `build/fit/probe-retime-20261116/`.
- Scenario paths: `candidate/output_files/timing/resident-store/{78,104}/corner-{1..4}/`.
- Durable fit preparation/report/collection helpers: `tools/probe_retime_fit/`.

Read-only collection of this existing run (do not redispatch submit.py):

```sh
gh run view 43906110604 --repo asturur/test_template_1
gh run download 43906110604 --repo asturur/test_template_1 \
  --name quartus-logs --dir build/fit/probe-retime-collection
python3 tools/probe_retime_fit/collect.py build/fit/probe-retime-collection \
  --output build/fit/probe-retime-collection/summary.json
```

Protected checkout proof verifies production RTL/project/shared workflow bytes,
HEAD, branch and index entries unchanged. The only remote publication was the
authorized fit-only experiment. No RBF was downloaded for installation; no
phone access, PLL change, production integration, CPU widening, TLB area work,
DDR3 experiment, second seed or other simulation/checkpoint changes occurred.
Stop after this comparison.
