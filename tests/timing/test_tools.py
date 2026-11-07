#!/usr/bin/env python3
"""Meaningful acceptance checks for timing gates and report processing."""
import csv
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[2]
def load(name):
    spec=importlib.util.spec_from_file_location(name,ROOT/'tools'/f'{name}.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module
GATE=load('check_quartus_timing')
SUMMARY=load('summarize_quartus_paths')
def report(**changes):
    values={'setup':'0.1','hold':'0.2','recovery':'0.3','removal':'0.4','minimum pulse width':'0.5'}
    values.update(changes)
    return '\n'.join(f'Info (332146): Worst-case {k} slack is {v}' for k,v in values.items())
class TimingTools(unittest.TestCase):
    def test_positive_complete_report(self):
        self.assertEqual(len(GATE.check(report())),5)
    def test_failed_corner_cannot_be_hidden_by_positive_corner(self):
        with self.assertRaisesRegex(ValueError,'negative'):
            GATE.check(report()+'\n'+report(setup='-0.25'))
    def test_missing_result_fails_closed(self):
        with self.assertRaisesRegex(ValueError,'missing'):
            GATE.check('\n'.join(report().splitlines()[:-1]))
    def test_vendor_failure_overrides_positive_numbers(self):
        with self.assertRaisesRegex(ValueError,'Timing requirements not met'):
            GATE.check(report()+'\nCritical Warning (332148): Timing requirements not met')
    def test_actual_board_build_is_rejected(self):
        path=ROOT/'scratch/hardware-bringup/build-d068883/output_files/Template.sta.rpt'
        if not path.exists():self.skipTest('local board report not available')
        with self.assertRaises(ValueError):GATE.check(path.read_text())
    def test_grouping_sorting_and_quoted_nodes(self):
        # Distinct data endpoints, intentionally out of slack order.
        with tempfile.TemporaryDirectory(dir=ROOT/'scratch') as d:
            path=Path(d)/'paths.csv'
            with path.open('w',newline='') as f:
                w=csv.writer(f);w.writerow(['slack_ns','data_delay_ns','logic_levels','from_node','to_node'])
                w.writerow(['-2','12','6','top|zap_alu:a|r[0]','top|zap_alu:a|r[1]'])
                w.writerow(['-43.7','53.3','62','top|arm920_cache_tags:t|a[0]','top|arm920_cache_tags:t|b[0],"quoted"'])
            text=SUMMARY.summary(path)
            self.assertIn('arm920_cache_tags | arm920_cache_tags | 1 | -43.7',text)
            self.assertLess(text.index('-43.7 ns'),text.index('-2 ns'))
            self.assertIn('b[0],"quoted"',text)
    def test_tcl_export_flow_and_csv_roundtrip(self):
        # Mock only the unavailable Quartus API, not timing computation.
        # This tests Tcl flow, filenames, limits and CSV escaping; it is NOT
        # validation of a real fitted netlist or the vendor API implementation.
        with tempfile.TemporaryDirectory(dir=ROOT/'scratch') as d:
            script=Path(d)/'mock.tcl'
            script.write_text('''
package provide ::quartus::project 1.0
package provide ::quartus::sta 1.0
set model ""
set netlists 0
proc project_open {args} {}
proc project_close {} {}
proc create_timing_netlist {args} {global model netlists; set model [lindex $args 1]; incr netlists}
proc read_sdc {} {}
proc update_timing_netlist {} {}
proc delete_timing_netlist {} {}
proc make_report {args} {
 set p [lindex $args [expr {[lsearch -exact $args -file]+1}]]
 set f [open $p w];puts $f MOCK;close $f
}
proc report_clocks {args} {make_report {*}$args}
proc report_clock_fmax_summary {args} {make_report {*}$args}
proc report_ucp {args} {make_report {*}$args}
proc report_timing {args} {
 if {[lsearch -exact $args -setup]>=0} {
  if {[lindex $args [expr {[lsearch -exact $args -npaths]+1}]]!=1000} {error "wrong setup count"}
  if {[lsearch -exact $args -show_routing]<0 || [lsearch -exact $args full_path]<0} {error "missing full routing"}
 }
 make_report {*}$args
}
proc get_timing_paths {args} {return {1 2}}
proc foreach_in_collection {var items body} {uplevel 1 [list foreach $var $items $body]}
proc get_path_info {option path} {
 switch -- $option {
  -slack {return -43.7}
  -data_delay {return 53.3}
  -num_logic_levels {return 62}
  -from_clock - -to_clock {return clk}
  -from {return "from$path"}
  -to {return "to$path"}
 }
}
proc get_clock_info {args} {return clk104}
proc get_node_info {option id} {return "top|zap_alu:alu|$id,\\\"quoted\\\""}
set argv {Template 1000}
source '''+str(ROOT/'tools/report_quartus_timing.tcl')+'''
if {$netlists!=2 || $model ne "fast"} {error "missing slow/fast analyses"}
''')
            subprocess.run(['tclsh',str(script)],cwd=d,check=True,capture_output=True)
            with (Path(d)/'output_files/timing/worst-setup.csv').open(newline='') as f:
                rows=list(csv.DictReader(f))
            self.assertEqual(len(rows),2)
            self.assertEqual(rows[0]['to_node'],'top|zap_alu:alu|to1,"quoted"')
            self.assertTrue((Path(d)/'output_files/timing/hold-fast-full.rpt').exists())
if __name__=='__main__':unittest.main()
