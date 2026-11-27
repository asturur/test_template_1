"""NGA/raw conversion contract; synthetic NEM-4 metadata, no private firmware."""
import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zlib
import struct

spec = importlib.util.spec_from_file_location('save', 'tools/prepare_mister_save.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class RawTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir='scratch', prefix='raw-test-')
        self.addCleanup(self.tmp.cleanup)
        self.p = Path(self.tmp.name)
        self.source = self.p/'original.NGA'
        self.data = m.make_header(1, bytes(range(32)), bytes(range(32,64))) + bytes(range(256))*(m.C_LEN//256) + bytes(reversed(range(256)))*(m.PMM_LEN//256)
        self.source.write_bytes(self.data)
        self.c, self.pmm, self.meta = [self.p/n for n in ('boot0.vhd','boot1.vhd','manifest.json')]
    def split(self):
        return m.split_raw(self.source,self.c,self.pmm,self.meta)
    def assert_source(self):
        self.assertEqual(self.source.read_bytes(), self.data)
    def test_roundtrip(self):
        self.split()
        self.assertEqual(self.c.read_bytes(),self.data[512:512+m.C_LEN])
        self.assertEqual(self.pmm.read_bytes(),self.data[512+m.C_LEN:])
        out=self.p/'rollback.nga';m.join_raw(self.meta,self.c,self.pmm,out)
        self.assertEqual(out.read_bytes(),self.data);self.assert_source()
    def test_modified_payload_retains_valid_metadata(self):
        self.split()
        for p in (self.c,self.pmm):
            d=bytearray(p.read_bytes());d[0]^=0xff;d[-1]^=0xff;p.write_bytes(d)
        out=self.p/'changed.nga';m.join_raw(self.meta,self.c,self.pmm,out)
        data,profile,core,ext=m.parse_save(out)
        self.assertEqual(data[:512],self.data[:512])
        self.assertEqual(data[512:],self.c.read_bytes()+self.pmm.read_bytes());self.assert_source()
    def test_no_overwrite_each_output(self):
        for existing in (self.c,self.pmm,self.meta,self.source):
            with self.subTest(existing=existing.name):
                if existing != self.source:existing.write_bytes(b'keep')
                c=self.source if existing==self.source else self.c
                with self.assertRaises(FileExistsError):m.split_raw(self.source,c,self.pmm,self.meta)
                self.assert_source()
                if existing!=self.source:self.assertEqual(existing.read_bytes(),b'keep');existing.unlink()
        self.split()
        with self.assertRaises(FileExistsError):m.join_raw(self.meta,self.c,self.pmm,self.source)
        self.assert_source()
    def test_invalid_nga(self):
        variants=[self.data[:-1],self.data+b'x',b'',b'QD'+self.data[2:]]
        for offset,value in [(8,2),(12,0),(12,3),(16,1),(20,1),(88,1),(507,1)]:
            d=bytearray(self.data);d[offset]=value;struct.pack_into('<I',d,508,zlib.crc32(d[:508]));variants.append(bytes(d))
        d=bytearray(self.data);d[508]^=1;variants.append(bytes(d))
        for i,data in enumerate(variants):
            with self.subTest(i=i):
                self.source.write_bytes(data)
                with self.assertRaises(ValueError):self.split()
                self.assertFalse(self.c.exists());self.assertEqual(self.source.read_bytes(),data)
    def test_both_supported_profiles(self):
        self.source.write_bytes(m.make_header(2,b'a'*32,b'b'*32)+self.data[512:]);self.split()
        self.assertEqual(json.loads(self.meta.read_text())['profile'],2)
    def test_raw_geometry(self):
        self.split()
        for path in (self.c,self.pmm):
            old=path.read_bytes()
            for data in (old[:-1],old+b'x'):
                path.write_bytes(data)
                with self.assertRaises(ValueError):m.join_raw(self.meta,self.c,self.pmm,self.p/'bad.nga')
            path.write_bytes(old)
        self.assert_source()
    def test_manifest_validation(self):
        self.split();original=json.loads(self.meta.read_text())
        variants=[[], {}, dict(original, source=[])]
        for key,val in [('format','bad'),('header_sha256','00'*32),('profile',2),('core_sha256','00'*32)]:
            d=dict(original);d[key]=val;variants.append(d)
        d=json.loads(json.dumps(original));d['images']['pmm']['offset']=0;variants.append(d)
        d=dict(original);h=bytearray(base64.b64decode(d['header_base64']));h[88]=1;struct.pack_into('<I',h,508,zlib.crc32(h[:508]));d['header_base64']=base64.b64encode(h).decode();d['header_sha256']=hashlib.sha256(h).hexdigest();variants.append(d)
        for d in variants:
            self.meta.write_text(json.dumps(d))
            with self.assertRaises(ValueError):m.join_raw(self.meta,self.c,self.pmm,self.p/'bad.nga')
        self.assert_source()

if __name__=='__main__':unittest.main(verbosity=2)
