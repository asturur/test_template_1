# Resident-store matched full-core fit — 16 November 2026

Fit-only experiment, not production integration or deployment. Base/control:
`9c948da8da413a882e0fe8e559c380ea0cadabf4`, control run
[43866215058](https://github.com/asturur/test_template_1/actions/runs/43866215058).
The source repository's former `asturur/NGage_MiSTer` URL redirects to
`asturur/test_template_1`; both resolve to repository ID **1434988755**.

Candidate: `7aa1a418bbf2d0ba28c215015f10e1412e6dc171`, one child of that exact
control commit, tag `fit-only/resident-store-3a-20261116-s42-01`.
[Matched run 43886019102](https://github.com/asturur/test_template_1/actions/runs/43886019102)
uses Quartus 17.0.2, Cyclone V 5CSEBA6U23I7, seed 42 and ENABLE_DEBUGGER=1.
It was dispatched on the tag, not on the integration branch. The seven-file
remote diff contains three design substitutions plus isolated workflow/report
support. The shared checkout, index and integration history were not used as
build inputs and were not switched or published.

## Actual design selection and replay

Only these design files replace the exact control-tree files:

| File | Stop 3A payload SHA256 |
| --- | --- |
| rtl/arm920/cache_access.sv | 88cfb92a983388a02e9d75657fb648c402b290c2fea5b419346b010f4de46ef5 |
| rtl/arm920/cache_bank.sv | 010b7e116a5651442c2fcfc05e8a4f931c07238728ae706e0bc2c95bbf6d70b7 |
| rtl/arm920/cache_tags.sv | 0291d169a7cd4a1e9a332ed652e5c9d5428ee1ad0bf3898ff154f3a44a274c3f |

Production `rtl/ngage_bram.v` SHA256 is
`df7aa84abdca0e585b062c077cb01b0b9c9961316851b37a72622738e103ba71`.
The simulation collision-poison BRAM was not included. No duplicate module
definition is permitted by the fit manifest. PLL HDL, Template.sv, QIPs, SDCs
and all other design files are byte-identical to the control tree. The normal
workflow changes only the effective seed/debug settings to 42/on, as it did
for the control.

The exact-base archive/staging copy is under
`scratch/resident-store-matched-fit/project/`; reproducible generated preparation
is under `build/fit/resident-store-20261116/`. Durable reporting/publication
helpers are in `tools/resident_store_fit/`. The prepared tree was published
through `gh api` without a local commit, branch, worktree, index mutation or
checkout. Do not rerun submit.py: it creates a uniquely named remote experiment.

To reproduce the **existing tagged experiment**, explicitly dispatch it again
only when another run is authorized:

```sh
gh workflow run ci_build.yml --repo asturur/test_template_1 \
  --ref fit-only/resident-store-3a-20261116-s42-01 \
  -f seed=42 -f enable_debugger=true
```

To collect this run without submitting anything:

```sh
gh run view 43886019102 --repo asturur/test_template_1
gh run download 43886019102 --repo asturur/test_template_1 \
  --name quartus-logs --dir build/fit/resident-store-20261116/candidate
```

The source graph records 178 selected files. The in-job manifest helper failed
on container/host path translation; the recovered input manifest below combines
the actual CI graph, verified immutable tree blobs and effective seed/debug
settings. It is explicitly labeled reconstructed, rather than a successful
in-job manifest step.

## Timing scenarios and coverage

The fit uses unchanged control constraints and the actual **78MHz PLL**. A
separate TimeQuest process in the same job then analyzes the **same routed
database** at 78 and 104MHz; no synthesis, placement or PLL HDL is rerun for 104.
All available operating conditions are enumerated, with setup, hold, recovery,
removal, minimum pulse, clocks, SDC/ignored constraints and UCP reports retained.
Targeted paths cover pipeline owner/pipe_commit→probe, any→pipeline,
certificate→owner, dirty forwarding and the original reset→probe cone.

The analysis-only 104MHz scenario overwrites the existing generated core VCO
clock's relationship from 50×78/5 to 50×104/5 and preserves its output divider
of 10, obtaining **9.615ns** at the core output. Original clock names, sources,
masters, relative phases/duty cycles and targets remain; derived uncertainty
is recomputed. Unrelated clock inventory, periods, waveforms and fanout are
checked for equality. The unused negative-phase PLL output is absent from the
control's routed clock inventory; the script requires the same one-live-output
shape and reports coverage failure if that assumption is false. The 104MHz
PLL cross-check is intentionally inconsistent with unchanged 78MHz HDL and
must be read as hypothetical timing analysis, not a new physical PLL release.

Quartus supports replacing a generated clock by the same name/target, and
report_sdc records the effective constraints. These diagnostics follow the
[Quartus 17 generated-clock command](https://resources.altera.com/quartushelp/17.0/tafs/tafs/tcl_pkg_sdc_ver_1.5_cmd_create_generated_clock.htm)
and [SDC report command](https://resources.altera.com/quartushelp/17.0/tafs/tafs/tcl_pkg_sta_ver_1.0_cmd_report_sdc.htm).

**Existing coverage gap:** the supplied control UCP lists 20 unconstrained input
ports /46 input paths and 86 output ports /170 output paths, including all
SDRAM_DQ inputs. The control has no explicit external SDRAM input/output delay
budget or generated forwarded SDRAM_CLK port clock. These omissions are
preserved, not replaced with guessed board assumptions. Internal 104MHz STA,
even with validated clock retargeting, cannot establish complete SDRAM I/O
closure or a 104MHz release. SDRAM pin register packing is checked separately
and is not a substitute for those missing constraints.

## Control reference

The supplied control artifacts live at
`/Users/andreabogazzi/Downloads/quartus-logs (1)/`. They identify run 43866215058,
exact 9c948da8, seed 42 and debugger enabled. The parsed control summary and
report hashes are retained in `build/fit/resident-store-20261116/control-summary.json`.
Control is 39,594 ALMs needed, 44,682 registers, 503 M10Ks, 40 memory LABs,
4,191 occupied LABs and 41 DSPs. All LABs are occupied; final placed ALMs are
40,801. CPU setup at 78MHz is −0.811ns (TNS −13.752ns), hold +0.251ns;
HDMI setup is +0.432ns. Control 104MHz routed analysis was not supplied: the
architecture review's slack subtraction was a sensitivity estimate only.

## Result and recommendation

**Retime before CPU admission.** The candidate fits below both planning stops,
but fails routed setup at 78MHz and the correctly derived internal 104MHz
scenario. The shared reset/completion/TLB/fast-ACK→probe-owner path remains the
first boundary to break. The new owner→probe and certificate→owner paths also
miss 104MHz; dirty forwarding has margin and is not the first retiming target.
No RTL retiming, CPU admission change, second seed or deployment was performed.

## Measured resources

| Resource | Control | Candidate | Delta |
| --- | ---: | ---: | ---: |
| ALMs | 39,594 | 39,535 | -59 |
| registers | 44,682 | 44,752 | +70 |
| M10Ks | 503 | 503 | +0 |
| MLABs | 40 | 40 | +0 |
| occupied_LABs | 4,191 | 4,179 | -12 |
| DSPs | 41 | 41 | +0 |
| placed_ALMs | 40,801 | 40,344 | -457 |
| design_registers | 41,162 | 41,717 | +555 |
| routing_registers | 3,401 | 2,916 | -485 |

The candidate leaves **915 ALMs** to the 40,450 planning stop and **18 M10Ks**
to the 521 stop. Twelve LABs are empty versus zero in the control. This is a
first-placement screen, not proof of room for the rest of the CPU pipeline.
The −59 ALM whole-design delta is not a claim that added pipeline logic is
free: D-cache access hierarchy grows from 3,957.4 to **4,123.9 ALMs** (+166.5),
while physical optimization/packing changes elsewhere. Whole-design implementation
registers increase 555 and routing registers decrease 485, producing net +70.
Data-cache line/tag memories stay at 82 M10Ks; instruction cache stays at 77.

## Routed timing, same 78MHz constraints

Normal compile reports below are **Slow 1100mV 100C**, matching the supplied
control's model. Extra corners later in the table are candidate-only analyses.

| Clock | Control setup ns | Candidate setup ns | Delta ns |
| --- | ---: | ---: | ---: |
| CPU/core | -0.811 | -1.326 | -0.515 |
| HDMI | +0.432 | -0.101 | -0.533 |
| HPS user | +3.135 | +2.709 | -0.426 |
| FPGA_CLK1_50 | +8.219 | +7.994 | -0.225 |
| FPGA_CLK2_50 | +8.265 | +12.099 | +3.834 |
| Audio | +22.820 | +20.544 | -2.276 |

CPU TNS is −13.963ns versus −13.752ns. CPU hold is +0.194ns versus +0.251ns.
The core violation was already present; its same-corner WNS worsens by 0.515ns.
HDMI setup changes from passing to −0.101ns. Because only cache design files
changed, the HDMI change is a whole-design placement/routing interaction,
not a new HDMI RTL path. It still blocks a passing whole-core result.

## Candidate corner analysis, same routed netlist

Global worst slacks across constrained clocks, ns. At 78MHz fast corners the
worst setup clock is HDMI; at 104MHz fast corners it is the core. Slow corners
are core-limited. These are measured reports, not Fmax conversion or subtraction.

| Scenario | Model / temperature | Setup | Hold | Recovery | Removal | Min pulse |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 78MHz | slow, 100C | -1.326 | +0.194 | +2.402 | +0.835 | +0.641 |
| 78MHz | slow, -40C | -1.520 | +0.010 | +2.701 | +0.796 | +0.641 |
| 78MHz | fast, 100C | +2.388 | +0.099 | +5.154 | +0.412 | +0.641 |
| 78MHz | fast, -40C | +3.139 | +0.039 | +5.417 | +0.345 | +0.641 |
| 104MHz | slow, 100C | -4.531 | +0.194 | -0.803 | +0.835 | +0.480 |
| 104MHz | slow, -40C | -4.725 | +0.010 | -0.504 | +0.796 | +0.480 |
| 104MHz | fast, 100C | +1.902 | +0.099 | +3.862 | +0.412 | +0.480 |
| 104MHz | fast, -40C | +2.509 | +0.039 | +4.794 | +0.345 | +0.480 |

Worst candidate setup is **−1.520ns at 78MHz** and **−4.725ns at 104MHz**, both
slow −40C. Only the 100C control is available for a same-corner comparison.
At 104MHz slow 100C, recovery also fails **−0.803ns** from
`loader|slot_valid[0]` to `core|reset_drain~SynDup_63`; it is not a store data
path. The 104MHz model retains uncertainty and half-cycle relationships, so
its hold/recovery/minimum-pulse results are separate checks, not inferred from
setup. All reported hold/removal/minimum-pulse minima are positive.

The script's clock-coverage check passes. Actual core waveform is 0/6.410ns
at 78MHz and 0/4.807ns at 104MHz, period 12.820/9.615ns. All nine unrelated
clock rows remain identical. The 51 explicit exception rows (one clock group,
48 false paths, two multicycle paths) are identical; there are 44 uncertainty
rows in each scenario. Generated-clock and uncertainty checks report zero
issues. The one 104MHz PLL cross-check warning is expected from hypothetical
clock retargeting with physical PLL HDL unchanged.

**Full constraint coverage is not qualified.** Candidate UCP still has 20
unconstrained input ports/46 paths and 86 output ports/168 paths in both
scenarios, including external SDRAM. check_timing also reports 2,473 no-clock
objects (HPS/h2f-related hard-IP objects are among them) and 86 multiple-clock
objects in both scenarios. These checks were exported, not waived. Missing
SDRAM min/max I/O delay budgets and the forwarded SDRAM_CLK clock prevent
104MHz I/O signoff. All 16 DQ input/output/OE registers do pass physical I/O
packing, both in CI and an independent local check; that is a distinct result.

## Longest relevant paths and the first retiming boundary

The table uses slow 100C for a direct control match; data / cell / routing are ns.
Full endpoint names and per-corner path hashes are in the evidence JSON and raw
reports. Small IC correction accounts for rounding in the delay totals.

| Path family / endpoints | Data | Cell | Routing | Levels | 78 slack | 104 slack |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Control reset_drain → probe_owner_way[5] | 13.236 | 4.531 | 8.703 | 10 | −0.811 | not supplied |
| Candidate reset_drain → probe_owner_way[5] | 13.428 | 5.239 | 8.193 | 13 | -1.326 | -4.531 |
| pipe_owner → probe_owner_way[5] | 11.253 | 4.473 | 6.782 | 12 | 0.839 | -2.366 |
| reset_drain → pipe_mva[3] | 11.135 | 4.379 | 6.757 | 10 | 0.922 | -2.283 |
| line_result_tag[2][25] → pipe_owner duplicate | 9.953 | 2.594 | 7.360 | 7 | 2.037 | -1.168 |
| tags commit_selected[10] → commit_dirty[0] | 6.656 | 2.573 | 4.084 | 6 | 5.773 | 2.568 |

The same-corner worst route still traverses `reset_drain` →
`u_data_completion|o_next` → D-TLB primary-match/fault → adapter `fast_hit` →
probe match/way encode → `probe_owner_way[5]`. Candidate logic depth grows
10→13 and cell delay 4.531→5.239ns; routing decreases 8.703→8.193ns. The
critical-path family predates the candidate, but the candidate does not remove
it and adds pipe_busy/fast-return qualifications to the connected control cone.
One placement cannot attribute the entire −0.515ns regression to one added gate.

At cold slow corner, `postalu2|o_und_ff` → the same probe-owner endpoint is worst:
13.618ns data, 7.272 cell, 6.347 routing, 12 levels; −1.520/−4.725ns at 78/104.
The new `pipe_owner`→probe path is also a real 104MHz violation (−2.497ns cold),
so merely fixing the baseline launch reset net is insufficient.

**First justified boundary:** register the locally owned probe/admission
context after request/translation/class qualification and before probe matching
and way selection. Separate private pre-read scheduling from the same-cycle
fast-ACK/completion-next feedback. Keep immediate reset/kill suppression on
small valid bits; do not send it back through wide payload/way capture enables.
Then revisit certificate→owner qualification, which is itself −1.168ns at
104MHz (100C), with a registered ingress/class/way token rather than another
combinational condition on the present owner capture. Requalify fast-read
ownership and the one-clock store recurrence after either latency change.

The fitted store path **survives optimization**: reports contain actual
`pipe_owner`, `pipe_mva`, certificate→owner and pending/recent dirty-state
paths, not empty/pruned groups. Dirty forwarding remains +2.568ns at 104MHz
100C (+2.631ns cold). Retiming its merge first is not supported by this fit.
The path families and data/dirty memories remain present; a fitter report is
not a new post-fit functional-throughput proof.

## Manifest recovery, raw outputs and stopping point

The job is red for two separate reasons: the normal timing gate, and an isolated
reporting-helper path bug. The helper read `/project/Template.qsf` from the
container graph but tried to relativize it to the host Actions workspace. It
failed before writing its JSON, after the three payload assertions passed.
The full fit, standard timing export and 78/104MHz scenario export all succeeded;
scenario errors.txt is empty. No refit was used to repair this reporting issue.

The durable helper now handles container `/project` paths. The reconstructed
manifest uses the **actual uploaded source graph**, the immutable remote tree,
and exact tagged seed/debug helpers. **177 of 178 selected input blobs** match
the remote tree byte-for-byte by Git blob SHA1 and are recorded by SHA256;
the remaining effective QSF is reconstructed from the exact tagged file plus
42/debug-on selection, confirmed by CI logs and fitter settings. Unique module
definitions and the production BRAM SHA256 are verified. Provenance is labeled
reconstructed, not falsely presented as a successful CI manifest step.

- Raw candidate: `build/fit/resident-store-20261116/candidate/`.
- Finished job log, run metadata, submission/tag/tree identity and parsed summaries:
  `build/fit/resident-store-20261116/`.
- Durable input proof: `docs/evidence/cache-resident-store-fit-inputs-20261116.json`.
- Compact resource/corner/path evidence:
  `docs/evidence/cache-resident-store-pipeline-fit-20261116.json`.
- Post-fit scenario reports: `candidate/output_files/timing/resident-store/{78,104}/corner-{1..4}/`.

The tag and run remain for reproduction. No bitstream was downloaded for
installation, and nothing was deployed. Shared production RTL, checkout/index,
78MHz PLL and the running phone remain untouched. Stop here: repair the shared
probe/admission timing boundary before CPU admission; keep a second seed and
the independent DDR3 experiment separate.
