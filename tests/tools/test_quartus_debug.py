import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'tools/set_quartus_debug.py'


class DebugChoice(unittest.TestCase):
    def test_toggle_preserves_other_settings_and_provenance(self):
        for newline in (b'\n', b'\r\n'):
            with self.subTest(newline=newline), tempfile.TemporaryDirectory() as directory:
                folder = Path(directory)
                qsf, metadata = folder/'test.qsf', folder/'build.json'
                original = newline.join([b'# leave this comment', b'set_global_assignment -name SEED 44',
                                         b'set_global_assignment -name VERILOG_MACRO "OTHER=1"']) + newline
                qsf.write_bytes(original)
                metadata.write_text(json.dumps({'fitter_seed':44, 'commit':'fixed-source', 'run_id':'test'}))
                for enabled in ('false', 'true', 'true', 'false'):
                    subprocess.run([sys.executable, str(SCRIPT), str(qsf), '--enabled', enabled,
                                    '--metadata', str(metadata)], check=True, capture_output=True)
                    expected = original + b'set_global_assignment -name VERILOG_MACRO "ENABLE_DEBUGGER=' + (b'1' if enabled=='true' else b'0') + b'"' + newline
                    self.assertEqual(qsf.read_bytes(), expected)
                    info = json.loads(metadata.read_text())
                    self.assertEqual(info['enable_debugger'], enabled=='true')
                    self.assertEqual(info['commit'], 'fixed-source')
                    self.assertEqual(info['fitter_seed'], 44)

    def test_bad_value_does_not_change_qsf(self):
        with tempfile.TemporaryDirectory() as directory:
            qsf = Path(directory)/'test.qsf'
            qsf.write_bytes(b'original\n')
            result = subprocess.run([sys.executable,str(SCRIPT),str(qsf),'--enabled','maybe'],capture_output=True)
            self.assertNotEqual(result.returncode,0)
            self.assertEqual(qsf.read_bytes(),b'original\n')


if __name__ == '__main__':
    unittest.main()
