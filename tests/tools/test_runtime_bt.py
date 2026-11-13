"""Pinned, volatile Bluetooth patch safety checks; no device access."""
from pathlib import Path
import struct
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import ngage_runtime_bt as bt
import service_firmware as svc


class RuntimeBT(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.package = (ROOT/'runtime/overlays/Bluetooth_Compatibility.ngo').read_bytes()
        cls.records = bt.records_from_package(cls.package)
        cls.original = bytearray(b'\xff' * svc.BACKING_SIZE)
        folder = ROOT/'firmware/NEM-04 v.04.03 N-GAGE'
        for kind in ('mcu', 'ppm'):
            svc.apply(cls.original, svc.parse((folder/svc.PROFILES[kind][0]).read_bytes(), kind), kind)

    def test_slow_wait_trace_is_separate(self):
        blob = (ROOT/'build/firmware-overlays/exit-trace/trace.bin').read_bytes()
        plain = bt.exit_records(blob)
        slow = bt.exit_records(blob, slow_wait=True)
        self.assertEqual([r for r in slow if r not in plain],
                         [next(r for r in slow if r[0] == 0x3b247c)])
        self.assertEqual(next(r[1] for r in slow if r[0] == 0x3b247c), 0xe2844001)
        bt.validate_image(self.original, slow)
        self.assertNotIn(0x3b247c, [r[0] for r in plain])

    def test_view_config_scope(self):
        raw = self.original.copy()
        records = list(bt.VIEW_CONFIG_RECORDS)
        bt.validate_image(raw, records)
        bt.patch_image(raw, records)
        changed = {i for i,(a,b) in enumerate(zip(raw,self.original)) if a != b}
        self.assertEqual(changed, {0x63ea2a,0x63ea2b,0x63ea3c,0x63ea3d})

    def test_view_timeout_scope(self):
        raw = self.original.copy()
        records = list(bt.VIEW_TIMEOUT_RECORDS)
        bt.validate_image(raw, records)
        bt.patch_image(raw, records)
        changed = {i for i,(a,b) in enumerate(zip(raw,self.original)) if a != b}
        self.assertTrue(changed)
        self.assertTrue(changed <= set(range(0x64bf68,0x64bf70)))
        self.assertEqual([new for off,old,new in records], [10000000,100000000])

    def test_identity_and_readback(self):
        raw = self.original.copy()
        bt.validate_image(raw, self.records)
        bt.patch_image(raw, self.records)
        for off, old, new in self.records:
            self.assertEqual(struct.unpack_from('<I', raw, off)[0], new)
        with self.assertRaises(ValueError):
            bt.validate_image(raw, self.records)
        with self.assertRaises(ValueError):
            bt.records_from_package(self.package[:-1])

    def test_partial_write_rollback_and_hook_last(self):
        raw = self.original.copy()
        calls = []
        original_pack = struct.pack_into
        def pack(fmt, memory, off, value):
            calls.append(off)
            if len(calls) == 30:
                raise OSError('injected memory write failure')
            original_pack(fmt, memory, off, value)
        with patch.object(bt.struct, 'pack_into', pack):
            with self.assertRaises(OSError):
                bt.patch_image(raw, self.records)
        self.assertEqual(raw, self.original)
        self.assertFalse(any(0x3f1cd0 <= off < 0x3f1cdc for off in calls))

    def test_held_fresh_guards(self):
        good = [0] * 256
        good[30] = 1
        good[242] = (1 << 4) | (1 << 25)
        self.assertTrue(bt.held_fresh(good))
        for field, value in ((12,1),(13,1),(18,1),(19,1),(30,0),(6,1)):
            bad = good.copy(); bad[field] = value
            self.assertFalse(bt.held_fresh(bad))
        for bit in (6,7,10,26):
            bad = good.copy(); bad[242] |= 1 << bit
            self.assertFalse(bt.held_fresh(bad))
        for bit in (4,25):
            bad = good.copy(); bad[242] &= ~(1 << bit)
            self.assertFalse(bt.held_fresh(bad))
        for state in range(1,8):
            bad = good.copy(); bad[242] |= state
            self.assertFalse(bt.held_fresh(bad))

    def test_exit_trace_scope(self):
        import subprocess
        subprocess.run(['python3',str(ROOT/'tools/build_exit_trace.py')],check=True,stdout=subprocess.DEVNULL)
        blob=(ROOT/'build/firmware-overlays/exit-trace/trace.bin').read_bytes()
        extra=bt.exit_records(blob)
        raw=self.original.copy()
        records=self.records+extra
        self.assertEqual(len({off for off,old,new in records}),len(records))
        bt.validate_image(raw,records)
        bt.patch_image(raw,records)
        for off,old,new in records:self.assertEqual(struct.unpack_from('<I',raw,off)[0],new)
        with self.assertRaises(ValueError):bt.exit_records(blob[:-4])

    def test_torn_snapshot(self):
        memory = bytearray(bt.SIZE)
        w = [0] * 256
        w[0:3] = [0x3244474e,1,17]; w[7] = 406; w[-1] = 17 ^ 0x4344474e
        struct.pack_into('<256I', memory, 0x13ff000, *w)
        self.assertEqual(bt.snapshot(memory)[2], 17)
        struct.pack_into('<I', memory, 0x13ff000+1020, 0)
        with self.assertRaises(ValueError):
            bt.snapshot(memory)


if __name__ == '__main__':
    unittest.main()
