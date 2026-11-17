# Stop 3D fit-only experiment

`prepare.py` freezes exact 9c948da8 plus the four hash-qualified Stop 3C cache
files, retains production BRAM and PLL, checks every other base file, and
preflights effective seed/debug inputs with both host and container paths.
It writes only a staging copy and generated outputs. Its existing output must
not be overwritten while collecting this experiment.

`submit.py` creates a remote tree/commit and unique fit-only tag through `gh`
and dispatches exactly one seed-42/debug-on job. It refuses an existing
submission identity. Do not run it to collect an existing experiment.

`workflow.yml` and `report.tcl` are fit-only support, not shared production CI
or constraints. The clock scenario is the validated Stop 3B analysis, with
new endpoint groups for adapter hint tags/valids, physical RAM-B and result
captures. Each group retains resolved keeper names/counts as well as ten
worst distinct-endpoint paths; empty groups are evidence limitations.
These use Quartus 17's documented `get_keepers` and `get_node_info` APIs:
https://resources.altera.com/quartushelp/17.0/tafs/tafs/tcl_pkg_sdc_ext_ver_1.0_cmd_get_keepers.htm

`collect.py REPORT_DIRECTORY --output SUMMARY.json` is read-only. It extends
the resident-store collector with all new path groups, physical delay splits,
CPU hierarchy, global families and coverage. Prior Stop 3B outputs stay intact.

`follow.py` follows only run 43906110604 and collects its reports, with no
dispatch capability. `finish.py --decision TEXT` validates the actual manifest,
the exact tool-written QSF edition normalization, clock/exception preservation
and protected checkout before writing durable evidence. `write_report.py`
renders the reviewed comparison for this experiment; it does not choose or
implement another RTL change.

The experiment is not production integration or a deployed bitstream. A
passing selected group cannot establish full-core closure. Existing external
SDRAM delay/forwarded-clock coverage gaps remain explicit.
