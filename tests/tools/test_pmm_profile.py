"""Check the audited PMM repair scope; private native capture is required."""
import importlib.util
from pathlib import Path
import hashlib
import subprocess
import sys
import unittest
ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('pmm', ROOT/'tools/ngage_pmm_profile.py')
pmm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pmm)
SOURCE = ROOT/'scratch/menu-bringup-20261112/live-pmm.vhd'

@unittest.skipUnless(SOURCE.exists(), 'requires the private native PMM capture')
class PMMProfile(unittest.TestCase):
    def test_audited_scope_and_invalid_sources(self):
        source = SOURCE.read_bytes()
        a = pmm.build(source, 0)
        b = pmm.build(source, 7)
        self.assertEqual(hashlib.sha256(a).hexdigest(),
                         '77e0e24008ecc2b828ac45c7d7bcefc151037f24fe89cff28f2f6cceaf564dfd')
        self.assertEqual(len(a), 65536)
        self.assertEqual([i for i in range(len(a)) if a[i] != b[i]], [1843])
        changed = {i for i in range(len(a)) if a[i] != source[i]}
        self.assertTrue(changed <= set(range(1830,1844)))
        for bad in (b'\xff'*65536, source[:-1], a):
            with self.assertRaises(ValueError):pmm.build(bad,0)
        for value in (-1,256):
            with self.assertRaises(ValueError):pmm.build(source,value)

    def test_existing_output_is_unchanged(self):
        path = ROOT/'scratch/menu-bringup-20261112/pmm-existing-output-test.bin'
        path.write_bytes(b'preserve existing image')
        try:
            result = subprocess.run([sys.executable,str(ROOT/'tools/ngage_pmm_profile.py'),
                '--source',str(SOURCE),'--output',str(path),'--synthetic-dos-byte','0'],
                capture_output=True)
            self.assertEqual(result.returncode,2)
            self.assertEqual(path.read_bytes(),b'preserve existing image')
        finally:path.unlink()

if __name__ == '__main__':unittest.main()
