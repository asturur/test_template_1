#!/usr/bin/env python3
"""Verify reconstruction determinism and rejection of altered recovered bytes."""
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest

import rom_extension as extension
from inventory_firmware import rom_tree


class ExtensionChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        scratch = extension.ROOT/'scratch'
        scratch.mkdir(exist_ok=True)
        cls.workspace = tempfile.TemporaryDirectory(prefix='extension-checks-',dir=scratch)
        cls.directory = Path(cls.workspace.name)
        cls.payload = cls.directory/'extension.bin'
        with contextlib.redirect_stdout(io.StringIO()):
            extension.build(cls.payload)
        cls.manifest = json.loads(cls.payload.with_suffix('.json').read_text())
        cls.core = extension.ROOT/'firmware/SYM.ROM'

    @classmethod
    def tearDownClass(cls):
        cls.workspace.cleanup()

    def copy(self,name):
        path = self.directory/f'{name}.bin'
        path.write_bytes(self.payload.read_bytes())
        path.with_suffix('.json').write_text(json.dumps(self.manifest))
        return path

    def test_original_core_unchanged(self):
        self.assertEqual(extension.sha(self.core.read_bytes()),extension.EXPECTED)

    def test_every_file_verified(self):
        self.assertEqual(self.manifest['files_verified'],1524)
        self.assertFalse(self.manifest['header_authentic'])
        self.assertFalse(self.manifest['directories_authentic'])
        self.assertTrue(self.manifest['root_bytes_unchanged'])

    def test_deterministic(self):
        other = self.directory/'second.bin'
        with contextlib.redirect_stdout(io.StringIO()):
            extension.build(other)
        self.assertEqual(other.read_bytes(),self.payload.read_bytes())

    def test_tampered_payload(self):
        path = self.copy('tampered')
        data = bytearray(path.read_bytes());data[0]^=1;path.write_bytes(data)
        with self.assertRaisesRegex(ValueError,'differs from its manifest'):
            extension.validate(self.core,path)

    def test_recovered_bytes_guard(self):
        path = self.copy('bad-root')
        data = bytearray(path.read_bytes())
        data[self.manifest['root_virtual_start']-self.manifest['virtual_start']] ^= 1
        path.write_bytes(data)
        manifest = dict(self.manifest,tail_sha256=extension.sha(data))
        path.with_suffix('.json').write_text(json.dumps(manifest))
        with self.assertRaisesRegex(ValueError,'ROOT bytes have changed'):
            extension.validate(self.core,path)

    def test_wrong_core(self):
        core = self.directory/'other-core.bin'
        data = bytearray(self.core.read_bytes());data[0]^=1;core.write_bytes(data)
        with self.assertRaisesRegex(ValueError,'original N-Gage'):
            extension.validate(core,self.payload)


if __name__=='__main__':
    unittest.main(verbosity=2)
