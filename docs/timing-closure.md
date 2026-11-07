# MiSTer timing closure

## Observed baseline and current scope

Completed build **d068883**, action **42365167112**, fits the device but fails
setup timing: **-43.702 ns** core-clock slack, **18.76 MHz** reported Fmax,
**-215405.214 ns** setup TNS. The PLL is still **104 MHz**. Resource use is
33,832/41,910 ALMs and 457/553 M10Ks. Reports are retained locally under
`scratch/hardware-bringup/build-d068883/`.

That artifact contains aggregate STA panels but no detailed critical paths or
fitted database. Node-level launch/capture/routing paths cannot be reconstructed
from the summaries alone. A new post-fit analysis must run while the database
still exists on the GitHub runner.

The user explicitly chose to **keep 104 MHz unchanged** for the next baseline
and request the worst **1,000** paths. The earlier 50 MHz proposal is deferred.
No PLL, clock frequency, timer, SDRAM mode, RTL, SDC or timing exception changed
in this reporting step. Do not attribute the failure to a particular CPU/cache
or debug block before inspecting the actual paths.

## Build artifacts

After normal Quartus compilation the action runs:

```sh
quartus_sta -t tools/report_quartus_timing.tcl Template 1000
python3 tools/summarize_quartus_paths.py output_files/timing/worst-setup.csv \
  --output output_files/timing/path-summary.md
python3 tools/check_quartus_timing.py output_files/Template.sta.rpt
```

The `quartus-logs` artifact always includes `quartus_timing_details.log` and
`output_files/timing/`, even when the timing gate fails. Main outputs:

| File | Contents |
| --- | --- |
| `worst-setup-full.rpt` | Worst 1,000 slow-model setup paths, full launch/capture clock paths, cells and detailed routing |
| `worst-setup.csv` | Rank, slack, data delay, logic levels, source/destination clocks and complete node names |
| `path-summary.md` | Group counts/worst slack by source/destination block and ten worst node pairs; also shown in action summary |
| `hold-slow-full.rpt`, `hold-fast-full.rpt` | Worst 100 hold paths in each model, with routing |
| `recovery-slow.rpt`, `removal-slow.rpt` | Worst 25 reset/asynchronous recovery/removal paths |
| `clocks.rpt`, `fmax-slow.rpt` | Derived clock identities/periods and slow-model Fmax |
| `unconstrained-slow.rpt` | Unconstrained interfaces/paths, kept visible for follow-up |

The setup selection uses `-npaths 1000 -nworst 1`: the worst path to each of
up to 1,000 distinct endpoints. This spreads analysis across many bottlenecks
rather than spending all rows on alternate routes to one register. The text
report and CSV use the same selection. No full path dumps are printed to chat
or the action console; detail stays in the artifact.

The report script analyzes the existing post-fit netlist with normal slow/fast
models. The original compile's multicorner `.sta.rpt` remains the timing-gate
input. Changing or omitting constraints is not a timing fix.

## Timing gate and limits

Quartus can exit successfully and generate an RBF despite a timing failure.
The new gate rejects `Timing requirements not met`, any negative reported
setup/hold/recovery/removal/minimum-pulse slack, and missing metric summaries.
It runs **after** detailed reports are generated. A failed-timing run is
therefore expected to be red while still providing its timing artifact.
Normal RBF upload requires this gate to pass.

This gate checks reported **constrained** timing. It does not certify the
unconstrained external SDRAM/other IO paths. The current interface constraints
still need evidence-backed board-delay work; no false paths, multicycles or
asynchronous-clock exceptions were added to hide them. See
`sdram-104mhz-ddio.md` for that separate hardware gate.

Local verification: `python3 tests/timing/test_tools.py` checks positive,
negative, incomplete and contradictory timing reports, rejects the actual
failed board report, and exercises CSV ordering/grouping/escaping. A mocked
Tcl API validates control flow/output handling only, **not Quartus semantics or
physical timing**. No local Quartus installation/download is used. Real API
execution and the measured paths require the GitHub build.

After obtaining the artifact: group the 1,000 paths, inspect logic depth versus
routing and shared fan-in, identify the real critical structures and make a
measured RTL change. Run the relevant CPU/chip/video regressions and compare
new STA, resources and hardware behavior. Keep each RBF paired with its source
and timing reports. The user monitors new builds; do not watch/poll the action.

Quartus 17 command references:
[report_timing](https://resources.altera.com/quartushelp/17.0/tafs/tafs/tcl_pkg_sta_ver_1.0_cmd_report_timing.htm),
[get_path_info](https://resources.altera.com/quartushelp/17.0/tafs/tafs/tcl_pkg_sta_ver_1.0_cmd_get_path_info.htm),
[report_ucp](https://resources.altera.com/quartushelp/17.0/tafs/tafs/tcl_pkg_sta_ver_1.0_cmd_report_ucp.htm).
