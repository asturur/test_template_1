"""Generated, non-private MMC vectors; no filesystem or external dependencies."""
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
TOOL = ROOT / 'tools/ngage_mmc_image.py'
spec = importlib.util.spec_from_file_location('ngage_mmc_image', TOOL)
mmc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mmc)
WORK = ROOT / 'scratch/ngage2-integration/p3-images'


def polynomial_crc7(data):
    """Independent polynomial long division, unlike the bitwise shift register."""
    polynomial = 0x89
    message = int.from_bytes(data, 'big') << 7
    while message.bit_length() > 7:
        message ^= polynomial << (message.bit_length() - 8)
    return message


def with_crc(data):
    return data + bytes([(polynomial_crc7(data) << 1) | 1])


def csd_vector(c_size=0, mult=0, read_len=9, structure=2, version=3, protected=False):
    # Test builder sets bit ranges directly, independently of production's
    # byte-offset source in donor mkcard.describe.
    value = ((structure << 126) | (version << 122) | (read_len << 80) |
             (c_size << 62) | (mult << 47) | ((1 << 13) if protected else 0))
    return with_crc(value.to_bytes(16, 'big')[:15])


CID = with_crc(bytes.fromhex('00112233445566778899aabbccddee'))
CSD = csd_vector()
OCR = bytes.fromhex('00ff8000')


def footer(cid=CID, csd=CSD, ocr=OCR):
    data = bytearray(512)
    data[:8], data[8] = b'NGAGEMMC', 1
    data[16:32], data[32:48], data[48:52] = cid, csd, ocr
    return bytes(data)


class ImageTests(unittest.TestCase):
    def setUp(self):
        WORK.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix='test-', dir=WORK)
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.raw = self.directory / 'source.img'
        self.payload = bytes(range(256)) * 8  # Minimum CSD capacity = four sectors.
        self.raw.write_bytes(self.payload)
        self.output = self.directory / 'card.mmc'
        self.identity_args = ['--cid', CID.hex(), '--csd', CSD.hex(), '--ocr', OCR.hex()]

    def cli(self, *arguments, ok=True):
        process = subprocess.run([sys.executable, '-I', '-B', str(TOOL), *map(str, arguments)],
                                 text=True, capture_output=True, timeout=10)
        if ok:
            self.assertEqual(process.returncode, 0, process.stderr)
            return json.loads(process.stdout)
        self.assertNotEqual(process.returncode, 0, process.stdout)
        self.assertNotIn('Traceback', process.stderr)
        return process.stderr

    def make(self, *extra):
        return self.cli('import-raw', self.raw, self.output, *self.identity_args, *extra)

    def source_state(self, path):
        info = path.stat()
        return (info.st_size, info.st_mtime_ns, info.st_mode, path.read_bytes())

    def test_crc_independent_known_vectors(self):
        # Standard CMD0/CMD8 command CRC7+end bytes 95 and 87 respectively.
        vectors = [(bytes.fromhex('4000000000'), 0x4a),
                   (bytes.fromhex('48000001aa'), 0x43),
                   (bytes(15), 0), (bytes([0xff]) * 15, 0x7f)]
        for data, expected in vectors:
            self.assertEqual(polynomial_crc7(data), expected)
            self.assertEqual(mmc.crc7(data), expected)
        for n in range(256):
            data = bytes((n * 17 + k * 13) & 255 for k in range(15))
            self.assertEqual(mmc.crc7(data), polynomial_crc7(data))

    def test_layout_roundtrip_every_byte_and_read_only_sources(self):
        self.raw.chmod(0o444)
        before = self.source_state(self.raw)
        made = self.make()
        expected = self.payload + footer()
        self.assertEqual(self.output.read_bytes(), expected)
        self.assertEqual(made['image']['sha256'], hashlib.sha256(expected).hexdigest())
        self.assertEqual(made['metadata']['bytes'], 512)
        self.assertEqual(made['payload']['bytes'], 2048)
        self.assertEqual(made['payload']['sectors'], 4)
        self.assertTrue(made['extent']['writable_mount_eligible'])
        self.assertEqual(self.source_state(self.raw), before)
        side = expected[-512:]
        self.assertEqual(side[0:8], b'NGAGEMMC')
        self.assertEqual(side[8:16], bytes([1]) + bytes(7))
        self.assertEqual(side[16:32], CID)
        self.assertEqual(side[32:48], CSD)
        self.assertEqual(side[48:52], OCR)
        self.assertFalse(any(side[52:]))
        self.output.chmod(0o444)
        card_before = self.source_state(self.output)
        exported = self.directory / 'export.img'
        manifest = self.cli('export-raw', self.output, exported)
        self.assertEqual(exported.read_bytes(), self.payload)
        self.assertEqual(Path(str(exported) + '.sidecar').read_bytes(), side)
        self.assertEqual(self.source_state(self.output), card_before)
        restored = self.directory / 'restored.mmc'
        imported = self.cli('import-raw', exported, restored,
                            '--metadata', str(exported) + '.json')
        self.assertEqual(restored.read_bytes(), expected)
        self.assertEqual(imported['image']['sha256'], manifest['image']['sha256'])
        self.assertEqual(len(imported['sources']), 2)
        inspected = self.cli('inspect', self.output)
        self.assertEqual(inspected['image'], imported['image'])
        self.assertEqual(self.cli('inspect', exported, '--raw', '--metadata',
                                 str(exported) + '.json')['image'], imported['image'])

    def test_identity_is_mandatory_and_strict(self):
        self.assertIn('requires --cid', self.cli('import-raw', self.raw, self.output, ok=False))
        self.assertIn('requires --cid', self.cli('import-raw', self.raw, self.output,
                                              '--cid', CID.hex(), '--csd', CSD.hex(), ok=False))
        self.assertFalse(self.output.exists())
        for option, invalid in [('--cid', '01'), ('--csd', 'x' * 32),
                                ('--ocr', '123'), ('--cid', CID.hex() + '!')]:
            args = self.identity_args.copy()
            args[args.index(option) + 1] = invalid
            self.cli('import-raw', self.raw, self.output, *args, ok=False)
            self.assertFalse(self.output.exists())

    def test_crc_and_explicit_normalization_preserve_original_bytes(self):
        for value in (CID[:15], CID[:15] + b'\0'):
            args = self.identity_args.copy()
            args[1] = value.hex()
            self.cli('import-raw', self.raw, self.output, *args, ok=False)
            made = self.cli('import-raw', self.raw, self.output, *args,
                            '--normalize-register-crc')
            self.assertEqual(made['normalization']['cid']['original_hex'], value.hex())
            self.assertEqual(made['normalization']['cid']['stored_hex'], CID.hex())
            self.assertTrue(made['normalization']['cid']['repair'])
            self.assertEqual(self.output.read_bytes()[-496:-480], CID)
            self.output.unlink()
            Path(str(self.output) + '.json').unlink()
        # A nonzero corrupt CRC is not a Linux zero-CRC normalization input.
        args = self.identity_args.copy()
        args[1] = (CID[:-1] + bytes([CID[-1] ^ 2])).hex()
        self.cli('import-raw', self.raw, self.output, *args,
                 '--normalize-register-crc', ok=False)
        self.assertFalse(self.output.exists())
        # CSD normalization is independently recorded as well.
        args = self.identity_args.copy()
        args[3] = CSD[:15].hex()
        made = self.cli('import-raw', self.raw, self.output, *args,
                        '--normalize-register-crc')
        self.assertEqual(made['normalization']['csd']['original_hex'], CSD[:15].hex())
        self.assertEqual(made['normalization']['csd']['stored_hex'], CSD.hex())

    def test_capacity_fields_and_observed_retail_geometry(self):
        for size, mult, expected in [(0, 0, 2048), (4094, 1, 16773120),
                                     (4094, 2, 33546240), (4094, 3, 67092480),
                                     (4095, 7, 1073741824)]:
            decoded = mmc.decode_footer(footer(csd=csd_vector(size, mult)))
            self.assertEqual(decoded['capacity_bytes'], expected)
            self.assertEqual(decoded['csd_fields']['c_size'], size)
            self.assertEqual(decoded['csd_fields']['c_size_mult'], mult)
        retail = with_crc(bytes.fromhex('8c08032a0079a3ffb6c081e1800020'))
        self.assertEqual(mmc.decode_footer(footer(csd=retail))['capacity_bytes'], 16773120)
        self.assertFalse(mmc.capacity_report(2048, mmc.decode_footer(
            footer(csd=csd_vector(protected=True))))['writable_mount_eligible'])

    def test_size_truncation_and_oversize(self):
        for length in (0, 1, 511, 513):
            self.raw.write_bytes(bytes(length))
            self.cli('import-raw', self.raw, self.output, *self.identity_args, ok=False)
            self.assertFalse(self.output.exists())
        self.raw.write_bytes(bytes(512))
        self.assertIn('--allow-truncated', self.make_error())
        made = self.make('--allow-truncated')
        self.assertEqual(made['extent']['scope'], 'truncated-prefix')
        self.assertFalse(made['extent']['writable_mount_eligible'])
        self.assertIn('NOT safe', made['extent']['note'])
        self.assertEqual(made['image']['bytes'], 1024)
        self.assertEqual(self.cli('inspect', self.output)['payload']['bytes'], 512)
        self.output.unlink()
        Path(str(self.output) + '.json').unlink()
        self.raw.write_bytes(bytes(2560))
        self.assertIn('exceeds', self.make_error('--allow-truncated'))

    def make_error(self, *extra):
        return self.cli('import-raw', self.raw, self.output, *self.identity_args, *extra, ok=False)

    def test_unknown_profile_inspection_export_but_not_import(self):
        for csd, ocr in [(csd_vector(structure=1), OCR), (csd_vector(version=4), OCR),
                         (csd_vector(read_len=10), OCR), (CSD, bytes.fromhex('40ff8000'))]:
            self.output.write_bytes(self.payload + footer(csd=csd, ocr=ocr))
            value = self.cli('inspect', self.output)
            self.assertIsNone(value['identity']['capacity_bytes'])
            self.assertFalse(value['identity']['supported_profile'])
            self.assertFalse(value['extent']['writable_mount_eligible'])
            target = self.directory / 'unknown.img'
            self.cli('export-raw', self.output, target)
            self.assertEqual(target.read_bytes(), self.payload)
            restored = self.directory / 'unknown.mmc'
            self.assertIn('unsupported import profile', self.cli('import-raw', target, restored,
                '--metadata', str(target) + '.json', '--allow-truncated', ok=False))
            for path in (self.output, target, Path(str(target) + '.sidecar'), Path(str(target) + '.json')):
                path.unlink()

    def test_corrupt_footer_and_container_lengths(self):
        for position, value in [(0, 0), (8, 2),
                                (16, CID[0] ^ 1), (31, CID[15] ^ 1), (47, CSD[15] ^ 2)]:
            side = bytearray(footer())
            side[position] = value
            self.output.write_bytes(self.payload + side)
            self.cli('inspect', self.output, ok=False)
        for data in (b'', footer(), self.payload + footer()[:-1],
                     self.payload + footer() + b'\0'):
            self.output.write_bytes(data)
            self.cli('inspect', self.output, ok=False)
        self.output.write_bytes(bytes(2560) + footer())
        self.assertIn('exceeds', self.cli('inspect', self.output, ok=False))

    def test_sidecar_and_existing_card_identity_reuse(self):
        side = self.directory / 'actual.sidecar'
        side.write_bytes(footer())
        before = self.source_state(side)
        self.cli('import-raw', self.raw, self.output, '--metadata', side)
        self.assertEqual(self.source_state(side), before)
        another = self.directory / 'another.mmc'
        self.cli('import-raw', self.raw, another, '--metadata', self.output)
        self.assertEqual(another.read_bytes(), self.output.read_bytes())
        self.cli('import-raw', self.raw, self.directory / 'bad.mmc', '--metadata', side,
                 '--cid', CID.hex(), ok=False)

    def test_opaque_metadata_bytes_preserved_and_json_payload_not_misdetected(self):
        side = bytearray(footer())
        side[9:16] = b'opaque!'
        side[52:] = bytes((index * 17 + 3) & 255 for index in range(460))
        payload = b'{' + self.payload[1:]
        self.output.write_bytes(payload + side)
        value = self.cli('inspect', self.output)
        self.assertTrue(value['metadata']['opaque_reserved_nonzero'])
        exported = self.directory / 'opaque.img'
        self.cli('export-raw', self.output, exported)
        self.assertEqual(Path(str(exported) + '.sidecar').read_bytes(), side)
        restored = self.directory / 'opaque.mmc'
        self.cli('import-raw', exported, restored, '--metadata', str(exported) + '.json')
        self.assertEqual(restored.read_bytes(), self.output.read_bytes())
        # Full-image identity reuse must not mistake a JSON-looking sector for
        # a JSON manifest; opaque metadata remains byte-for-byte identical.
        other = self.directory / 'from-card.mmc'
        self.cli('import-raw', exported, other, '--metadata', self.output)
        self.assertEqual(other.read_bytes(), self.output.read_bytes())

    def test_overwrite_and_multi_output_rollback(self):
        self.output.write_bytes(b'keep original')
        self.make_error()
        self.assertEqual(self.output.read_bytes(), b'keep original')
        self.output.unlink()
        manifest = Path(str(self.output) + '.json')
        manifest.write_bytes(b'keep manifest')
        self.make_error()
        self.assertFalse(self.output.exists())
        self.assertEqual(manifest.read_bytes(), b'keep manifest')
        manifest.unlink()
        # Same inode/source path cannot become an output.
        before = self.raw.read_bytes()
        self.cli('import-raw', self.raw, self.raw, *self.identity_args, ok=False)
        self.assertEqual(self.raw.read_bytes(), before)
        self.make()
        exported = self.directory / 'payload.img'
        side = Path(str(exported) + '.sidecar')
        side.write_bytes(b'keep sidecar')
        self.cli('export-raw', self.output, exported, ok=False)
        self.assertFalse(exported.exists())
        self.assertEqual(side.read_bytes(), b'keep sidecar')
        self.cli('export-raw', self.output, exported, '--sidecar', exported, ok=False)
        self.assertFalse(exported.exists())

    def test_manifest_checksums_sizes_types_and_corruption(self):
        self.make()
        exported = self.directory / 'payload.img'
        original = self.cli('export-raw', self.output, exported)
        meta = Path(str(exported) + '.json')
        for section, key, invalid in [('payload', 'bytes', True), ('payload', 'sectors', 5),
                ('metadata', 'bytes', 511), ('metadata', 'hex', None), ('image', 'bytes', 999),
                ('payload', 'sha256', '0' * 64), ('metadata', 'sha256', '0' * 64),
                ('image', 'sha256', '0' * 64), ('identity', 'capacity_bytes', 2048.0),
                ('extent', 'writable_mount_eligible', 1)]:
            value = json.loads(json.dumps(original))
            value[section][key] = invalid
            meta.write_text(json.dumps(value))
            result = self.directory / 'rejected.mmc'
            self.cli('import-raw', exported, result, '--metadata', meta, ok=False)
            self.assertFalse(result.exists())
            self.assertFalse(Path(str(result) + '.json').exists())
        for data in ('{', '{"format":NaN}', '[]', '{"format":"wrong"}', '{' + ' ' * 65536):
            meta.write_text(data)
            self.cli('import-raw', exported, self.directory / 'rejected.mmc', '--metadata', meta, ok=False)
        meta.write_text(json.dumps(original))
        exported.write_bytes(bytes([1]) + self.payload[1:])
        self.cli('import-raw', exported, self.directory / 'rejected.mmc', '--metadata', meta, ok=False)
        self.assertFalse((self.directory / 'rejected.mmc').exists())

    @unittest.skipUnless(hasattr(os, 'mkfifo'), 'FIFO check requires Unix')
    def test_nonregular_sources_rejected_without_waiting(self):
        fifo = self.directory / 'not-a-disk.fifo'
        os.mkfifo(fifo)
        self.assertIn('regular file', self.cli('inspect', fifo, ok=False))
        self.assertIn('regular file', self.cli('import-raw', fifo, self.output,
                                              *self.identity_args, ok=False))
        self.assertFalse(self.output.exists())
        self.cli('inspect', self.directory, ok=False)

    def test_streaming_chunk_bound(self):
        class LimitedReads(io.BytesIO):
            def read(self, size=-1):
                self.assert_size(size)
                return super().read(size)
            def assert_size(self, size):
                if size < 0 or size > mmc.CHUNK:
                    raise AssertionError('unbounded payload read')
        data = self.payload * 5
        with mock.patch.object(mmc, 'CHUNK', 1024):
            target = io.BytesIO()
            digest, image_hash = mmc.copy_payload(LimitedReads(data), len(data), target)
            self.assertEqual(target.getvalue(), data)
            self.assertEqual(digest, hashlib.sha256(data).hexdigest())
            self.assertEqual(image_hash.hexdigest(), digest)
            with self.assertRaisesRegex(ValueError, 'truncated'):
                mmc.copy_payload(LimitedReads(b'abc'), 512)


if __name__ == '__main__':
    unittest.main(verbosity=2)
