"""Qualify original ADSP relocation/address evidence, without executing firmware."""
from pathlib import Path
import hashlib
import importlib.util
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('adsp_image', ROOT / 'tools/ngage_adsp_image.py')
adsp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adsp)


class OriginalImage(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original = adsp.DEFAULT_IMAGE.read_bytes()
        cls.manifest, cls.ram, cls.valid = adsp.inspect_image(cls.original)

    def test_native_ram_calls_resolve_to_original_code(self):
        # Reset CALL000460 and startup CALL000900/CALL001E8B resolve inside
        # copied code, rather than requiring guessed on-chip ROM routines.
        self.assertEqual(self.ram[0x460:0x462], bytes.fromhex('4eff'))
        self.assertEqual(self.ram[0x900:0x902], bytes.fromhex('951f'))
        self.assertEqual(self.ram[0x1e8b:0x1e8d], bytes.fromhex('4eff'))
        for addr in (0x460, 0x900, 0x1e8b, 0x2721b, 0x2729d):
            self.assertTrue(all(self.valid[addr:addr + 8]))

    def test_vectors_are_addresses_not_decoded_instructions(self):
        vectors = self.manifest['vectors']
        self.assertEqual(vectors[0]['target'], 0x441200)
        self.assertEqual(vectors[1]['target'], 0x44e85d)
        self.assertEqual(vectors[13]['target'], 0x1d8ee)
        self.assertEqual(self.ram[0x100:0x104], bytes.fromhex('ca441200'))
        self.assertEqual([v['index'] for v in vectors if v['owner'] == 'unresolved'], [8])

    def test_each_loaded_byte_has_one_original_owner(self):
        rebuilt = bytearray(len(self.original))
        for record in self.manifest['records']:
            src, dst, length = record['source_offset'], record['destination_byte'], record['bytes']
            rebuilt[src:src + length] = self.ram[dst:dst + length]
            self.assertEqual(rebuilt[src:src + length], self.original[src:src + length])
        self.assertEqual(sum(self.valid), 91664)
        self.assertEqual(self.valid[0x33b01], 0)

    def test_external_marker_matches_native_diagnostic(self):
        # Native451B5C reads data word2B0000; byte address560000 maps to
        # file160000 with the recovered candidate flash base400000.
        offset = 0x2b0000 * 2 - adsp.FLASH_BASE
        self.assertEqual(self.original[offset:offset + 2], bytes.fromhex('fffc'))

    def test_reject_unqualified_images_and_preserve_source(self):
        changed = bytearray(self.original)
        changed[0x160000] ^= 1
        with self.assertRaises(ValueError):
            adsp.inspect_image(bytes(changed))
        with self.assertRaises(ValueError):
            adsp.inspect_image(self.original[:-1])
        self.assertEqual(hashlib.sha256(adsp.DEFAULT_IMAGE.read_bytes()).hexdigest(), adsp.SHA256)


if __name__ == '__main__':
    unittest.main()
