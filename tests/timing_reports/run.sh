#!/bin/sh
# Host-only exporter checks; no Quartus netlist or physical timing is simulated.
set -eu
mkdir -p build/sim/unit-timing-reports
tclsh tests/timing_reports/operand_mock.tcl > build/sim/unit-timing-reports/mock.log
python3 - <<'PY'
import csv
rows=list(csv.DictReader(open('build/sim/unit-timing-reports/operand-stages/summary.csv')))
assert len(rows)==12 and len({r['group'] for r in rows})==12
by={r['group']:r for r in rows}
assert sum(r['status']=='ok' for r in rows)==9
assert by['r_to_memory_operand']['status']=='no_paths' and by['r_to_memory_operand']['worst_slack_ns']==''
assert by['r_queue_feedback']['status']=='error' and by['r_queue_feedback']['message']=='mock missing "node, renamed"'
assert by['shifter_recurrence']['status']=='unparsed' and by['shifter_recurrence']['worst_slack_ns']==''
assert all(r['reported_paths']=='10' and float(r['worst_slack_ns'])==.375 for r in rows if r['status']=='ok')
assert '*u_zap_alu_main*' in by['shifter_recurrence']['from_patterns']
print('PASS targeted timing CSV:12 groups; missing, failed and unparsed queries remain distinct')
PY
tail -1 build/sim/unit-timing-reports/mock.log
