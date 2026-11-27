#!/usr/bin/env python3
"""Safety checks for the opt-in derived firmware digest experiment."""
import hashlib
from pathlib import Path
import tempfile
import unittest

import digest_probe as probe


class DigestProbeChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory(prefix='digest-probe-checks-',dir=probe.ROOT/'scratch')
        cls.root=Path(cls.temp.name)
        cls.core=probe.ROOT/'firmware/SYM.ROM'
        cls.tail=probe.ROOT/'build/firmware/nem4-extension/extension.bin'
        cls.original=cls.core.read_bytes()

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_only_selected_digest_metadata_changes(self):
        for mode,offsets in [('core',[0x8f20]),('both',[0x8f20,0x8f08])]:
            with self.subTest(mode=mode):
                path,manifest=probe.build(self.core,self.tail,mode,self.root)
                result=path.read_bytes()
                changed={i for i,(a,b) in enumerate(zip(self.original,result)) if a!=b}
                allowed={i for offset in offsets for i in range(offset,offset+16)}
                self.assertTrue(changed)
                self.assertLessEqual(changed,allowed)
                self.assertEqual(hashlib.sha256(result).hexdigest(),manifest['derived_sha256'])
                self.assertFalse(manifest['authenticity_verified'])
                self.assertEqual(manifest['source_core_sha256'],probe.EXPECTED)
                for item in manifest['changes']:
                    self.assertEqual(result[item['digest_offset']:item['digest_offset']+16].hex(),item['after'])
                self.assertEqual(hashlib.sha256(self.core.read_bytes()).hexdigest(),probe.EXPECTED)

    def test_tampered_output_is_regenerated(self):
        path,expected=probe.build(self.core,self.tail,'core',self.root)
        data=bytearray(path.read_bytes());data[0]^=1;path.write_bytes(data)
        path,actual=probe.build(self.core,self.tail,'core',self.root)
        self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),expected['derived_sha256'])
        self.assertEqual(actual,expected)

    def test_other_core_is_rejected(self):
        path=self.root/'wrong.rom'
        data=bytearray(self.original);data[0]^=1;path.write_bytes(data)
        with self.assertRaisesRegex(ValueError,'original inspected'):
            probe.build(path,self.tail,'core',self.root)


if __name__=='__main__':
    unittest.main(verbosity=2)
