# HDMI low-latency tuner clock model

[Design patch](patches/lltune-generated-clock.patch) and
[baseline evidence](../../evidence/v5-104-lltune-generated-clock.json) are ready for a guarded
pilot. The private candidate tree is
`7127805827ab48253d9b60ab880ccb2fd751e5d7`. The patch applies to the
exact retained `11c4a0c` tree and changes three timing and report files.
The first 104 MHz TimeQuest run uses `5f764ef`, seed 13 and DDR
debugging off. Its parent `6aba907` matches the retained tree.
[Seed 13 pilot](https://github.com/asturur/test_template_1/actions/runs/45805636505) ·
[Seed 43](https://github.com/asturur/test_template_1/actions/runs/45812194690) ·
[Seed 31337](https://github.com/asturur/test_template_1/actions/runs/45812190649)

## Pilot result

The seed 13 build resolved `comb~0|combout` to 47 fitted Delay sinks
at all four corners, including duplicated registers. TimeQuest derived
the expected three setup and hold margins below and confirmed that the
core-to-tuner crossing stays timed. The native PLL, actual generated
clock waveform, minimum pulse analysis, and SDRAM pin checks pass.
Worst setup is −2.297 ns against −2.061 ns on the matched control.
Core setup TNS improves from −4606.649 to −3553.560 ns. Area moves
from 36,420 to 36,599 ALMs and 321 to 315 M10Ks. The overall fit
misses setup. [Pilot reports and four clock audits](../../evidence/v5-104-lltune-generated-clock-pilot.json)

## Gate identity

`Template.sv` uses the 104 MHz PLL output for `clk_sys` and
`CLK_VIDEO`. The framework connects `CLK_VIDEO` through `clk_vid` and
`clk_ihdmi` to `ascal.i_clk`. The scaler outputs that clock as
`o_lltune(6)`. `sys_top` ANDs the bus with `cfg_done`, and
`pll_hdmi_adj.vhd` uses `lltune(6)` for the rising-edge Delay process.
The six register families total 41 logical bits. The parent and sibling
`sys_top.v` and `pll_hdmi_adj.vhd` files are byte-identical.

The retained Fitter clock table shows the top-level LUT `comb~0`
driving a local clock in three independent fits. Seed 43 has 41 sinks.
Seed 13 has 44, including three Fitter duplicates of Delay counters.
Seed 31337 has 45, including four duplicates. These fit reports establish
the expected structure and give an independent check on future queries.

Sibling commit `afd9642201ba31888a216f568077196864002f9e` first added the
clock. Its routed STA from run 44777214314 places `lltune_clk` on
`comb~0|combout` at 104 MHz and reports 238 active core-to-tuner paths
and 874 active tuner-to-tuner paths. The tuner-to-FPGA_CLK1_50
crossing remains under the existing exclusive group. The retained v5
constraints set 0.300 ns setup and 0.280 ns hold uncertainty for
the aggregate core domain at all four corners.

The three retained Fitter reports already show placement effort 4.0,
maximum router optimization, and all-path hold optimization.

The candidate derives the gate name from actual Delay register clock
arcs. It requires all expected register bits, a single driver, the
complete fanout and ancestry from both the core PLL and `cfg_done`.
An incorrect or ambiguous selection raises an error before assignment.
The native 104 MHz variant sets one unity generated clock before
`derive_clock_uncertainty`. Existing 78 MHz models and their diagnostic
retargeting continue to use the original constraints. The patch also
retains the optional `spi_sck` group. SPI clock creation is ignored in the
three retained runs because the relevant SPI pin is absent.

## Post-fit audit

The native 104 MHz production report runs the audit at each existing
operating corner. It records the resolved gate and Delay sink names,
the core PLL period and unity waveforms, the generated parent, and
the exact Delay register count. It checks TimeQuest's derived setup
and hold margins and observes actual paths. The expected margins come
from the sibling's routed experiment.

| Transfer | Setup | Hold |
| --- | ---: | ---: |
| Native PLL to itself | 0.140 ns | 0.080 ns |
| Gated tuner to itself | 0.300 ns | 0.280 ns |
| Native PLL to gated tuner | 0.220 ns | 0.180 ns |

TimeQuest can apply 0.000 ns on a hold path with a common physical edge
even though the derived hold margin is nonzero. The audit checks the
derived table and the applied path uncertainty independently. It
records the reverse tuner crossing if the data path exists. It checks
both directions between the tuner or core and each existing exclusive
clock for setup, hold, recovery and removal. It records absence
separately for optional clocks such as SPI. The existing global
setup, hold, recovery, removal, unconstrained and pulse-width reports
still run. It additionally verifies minimum-pulse-width analysis is
present for both the parent and tuner clocks.

`tclsh` mock tests exercise a renamed gate and a replicated register.
They reject incomplete sinks, extra fanout, multiple drivers, wrong
PLL, missing enable, a newly active SPI crossing, a cut active
crossing and a weakened tuned-clock margin. They exercise parsing the
real retained setup/hold tables at all four corners for each of the
three seeds. The mock verifies script decisions. TimeQuest collection
behavior, fitted routing, actual derived margins and the full timing
gate still require one real pilot.

## Reproduce

Run from the repository root with a fresh scratch destination.

```sh
experiment=scratch/v5-fit-loop/lltune-clock
replay=scratch/v5-fit-loop/lltune-clock-replay
catalog=docs/experiments/v5-performance/patches
mkdir -p "$replay"
git apply "$catalog/lltune-generated-clock-audit.patch"
git archive 11c4a0c | tar -x -C "$replay"
git apply --whitespace=nowarn --directory="$replay" "$catalog/lltune-generated-clock.patch"
git show 11c4a0c:sys/sys_top.sdc > "$experiment/evidence/retained-sys_top.sdc"
root="$PWD"
(
  cd "$replay"
  for run in 45414696142 45414703565 45414709004; do
    tclsh "$root/$experiment/evidence/mock-lltune.tcl" \
      "$root/build/timing-audit-$run/output_files/timing/resident-store/104" \
      "$root/$experiment/evidence/replay-$run"
  done
)
```

On a fitted Template database, run the normal reports from the
candidate checkout.

```sh
quartus_sta -t tools/probe_retime_fit/report.tcl 104
python3 tools/check_sdram_io_registers.py output_files/Template.fit.rpt
python3 tools/check_quartus_timing.py output_files/Template.sta.rpt \
  --native-corners output_files/timing/resident-store \
  --fit-manifest output_files/resident-fit-manifest.json
```

Inspect `lltune-clock.tsv` and `lltune-clock-transfers.rpt` under each
native corner alongside the ordinary timing gate. An optional same-fit
audit reads the retained and separated system SDCs over the same database
and verifies that the existing clock properties and register counts are
preserved apart from moving exactly the expected sinks. It exports the
clock-transfer and unconstrained reports for both models.

```sh
quartus_sta -t "$root/$experiment/evidence/same-fit-audit.tcl" \
  "$root/$experiment/evidence/retained-sys_top.sdc"
```

[TimeQuest 17.0 clock queries](https://www.intel.com/content/www/us/en/programmable/quartushelp/17.0/tafs/tafs/tcl_pkg_sta_ver_1.0_cmd_get_clock_info.htm) ·
[TimeQuest 17.0 path queries](https://www.intel.com/content/www/us/en/programmable/quartushelp/17.0/tafs/tafs/tcl_pkg_sta_ver_1.0_cmd_get_timing_paths.htm) ·
[Clock-transfer reporting](https://www.intel.com/content/www/us/en/programmable/quartushelp/17.0/tafs/tafs/tcl_pkg_sta_ver_1.0_cmd_report_clock_transfers.htm)
