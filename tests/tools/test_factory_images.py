"""The factory C:/PMM images: geometry, the one PMM record and the reader."""
from pathlib import Path
import importlib.util
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / 'tools/ngage_factory_images.py'
spec = importlib.util.spec_from_file_location('factory_images', TOOL)
factory = importlib.util.module_from_spec(spec)
spec.loader.exec_module(factory)


class FactoryPmm(unittest.TestCase):
    def setUp(self):
        self.image = factory.factory_pmm()

    def test_geometry_and_erased_space(self):
        self.assertEqual(len(self.image), 65536)
        # Four 32-byte sector headers and one 14-byte record; the rest erased.
        self.assertEqual(sum(byte != 0xff for byte in self.image), 67)
        for sector in range(4):
            self.assertEqual(self.image[sector * 16384:sector * 16384 + 2], b'\xf0\xf0')
        self.assertEqual(self.image[6:12], b'PMMCAT')
        self.assertEqual(self.image[0x8006:0x800c], b'PMMCAT')

    def test_single_record_is_the_format_reason(self):
        self.assertEqual(factory.records(self.image),
                         [(32, 0xf4, 212, 3, struct.pack('<H', 105))])
        self.assertEqual(self.image[32:46].hex(), 'f4d4030055ffffff02002e006900')
        self.assertEqual(factory.aux_startup_reason(self.image), 105)

    def test_reader_follows_the_firmware_replacing_the_record(self):
        # After its format the firmware clears tag bits of the record and
        # appends a new one with 100; only the valid record counts.
        image = bytearray(self.image)
        image[32] = 0xa4
        entry = factory.record(212, 3, struct.pack('<H', 100), 46)
        image[46:46 + len(entry)] = entry
        self.assertEqual(factory.aux_startup_reason(bytes(image)), 100)
        self.assertEqual(len(factory.records(bytes(image))), 2)

    def test_no_record_means_no_reason(self):
        image = bytearray(self.image)
        image[32:46] = b'\xff' * 14
        self.assertIsNone(factory.aux_startup_reason(bytes(image)))

    def test_broken_chain_is_reported(self):
        image = bytearray(self.image)
        image[42] = 0x30
        with self.assertRaises(ValueError):
            factory.records(bytes(image))


class CommandLine(unittest.TestCase):
    def run_tool(self, *args):
        return subprocess.run([sys.executable, str(TOOL), *map(str, args)],
                              capture_output=True, text=True)

    def test_creates_both_images_and_never_overwrites(self):
        with tempfile.TemporaryDirectory() as folder:
            cdrive, pmm = Path(folder) / 'boot0.vhd', Path(folder) / 'boot1.vhd'
            first = self.run_tool('--cdrive', cdrive, '--pmm', pmm)
            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertEqual(cdrive.read_bytes(), b'\xff' * 4194304)
            self.assertEqual(pmm.read_bytes(), factory.factory_pmm())
            again = self.run_tool('--pmm', pmm)
            self.assertEqual(again.returncode, 2)
            self.assertEqual(pmm.read_bytes(), factory.factory_pmm())
            inspected = self.run_tool('--inspect', pmm)
            self.assertIn('"aux_startup_reason": 105', inspected.stdout)


if __name__ == '__main__':
    unittest.main()
