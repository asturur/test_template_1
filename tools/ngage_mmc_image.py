#!/usr/bin/env python3
"""Inspect and losslessly split/join NGAGEMMC v1 raw-sector card images.

This archival tool does not build filesystems, synthesize card identities, or
mount cards. The donor format is raw 512-byte sectors plus one metadata sector:
NGAGEMMC at 0, version 1 at 8, CID at 16, CSD at 32, big-endian OCR at 48.
Only the locally evidenced MMC 3.1 CSD (structure 2/spec 3/READ_BL_LEN 9) is
accepted for import. CRC-valid unknown profiles can be inspected/exported.
"""
import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import stat

SECTOR = 512
CHUNK = 1024 * 1024
MAGIC = b'NGAGEMMC'
VERSION = 1
MANIFEST_FORMAT = 'ngage-mmc-image-v1'
MAX_MANIFEST = 64 * 1024


def crc7(data):
    """MSB-first x^7+x^3+1, as used by MMC register responses."""
    remainder = 0
    for byte in data:
        for shift in range(7, -1, -1):
            feedback = ((remainder >> 6) ^ (byte >> shift)) & 1
            remainder = (remainder << 1) & 0x7f
            if feedback:
                remainder ^= 0x09
    return remainder


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def hex_bytes(text, name, lengths):
    # Permit whitespace separators, not silently discarded punctuation/typos.
    if not isinstance(text, str):
        raise ValueError(f'{name}: expected a hexadecimal string')
    clean = ''.join(text.split())
    if not re.fullmatch(r'[0-9a-fA-F]+', clean) or len(clean) % 2:
        raise ValueError(f'{name}: expected hexadecimal bytes')
    value = bytes.fromhex(clean)
    if len(value) not in lengths:
        raise ValueError(f'{name}: expected {" or ".join(map(str, lengths))} bytes')
    return value


def register(value, name, normalize=False):
    original = value
    repair = None
    if len(value) == 15:
        if not normalize:
            raise ValueError(f'{name}: 15-byte Linux register needs --normalize-register-crc')
        value += bytes([(crc7(value) << 1) | 1])
        repair = 'appended-crc7-and-end-bit'
    elif len(value) == 16 and value[15] == 0 and normalize:
        value = value[:15] + bytes([(crc7(value[:15]) << 1) | 1])
        repair = 'replaced-zero-crc7-and-end-bit'
    expected_end = (crc7(value[:15]) << 1) | 1
    if len(value) != 16 or value[15] != expected_end:
        raise ValueError(f'{name}: invalid CRC7 or register end bit')
    return value, {'original_hex': original.hex(), 'stored_hex': value.hex(),
                   'repair': repair}


def identity(cid, csd, ocr):
    # Primary source: donor mkcard.describe and rtl/board/mmc_card.sv.
    # cap = (C_SIZE+1) << (C_SIZE_MULT+2) << READ_BL_LEN.
    bits = int.from_bytes(csd, 'big')
    fields = {'structure': (bits >> 126) & 3,
              'spec_version': (bits >> 122) & 15,
              'read_bl_len': (bits >> 80) & 15,
              'c_size': (bits >> 62) & 4095,
              'c_size_mult': (bits >> 47) & 7,
              'permanent_write_protect': bool(bits & (1 << 13)),
              'temporary_write_protect': bool(bits & (1 << 12))}
    supported = (fields['structure'], fields['spec_version'], fields['read_bl_len']) == (2, 3, 9)
    supported = supported and not (int.from_bytes(ocr, 'big') & 0x60000000)
    capacity = ((fields['c_size'] + 1) << (fields['c_size_mult'] + 2)) << 9 if supported else None
    return {'cid_hex': cid.hex(), 'csd_hex': csd.hex(), 'ocr_hex': ocr.hex(),
            'card_type': 'mmc-standard-observed-3.1' if supported else 'unsupported-profile',
            'supported_profile': supported, 'csd_fields': fields,
            'capacity_bytes': capacity}


def decode_footer(footer):
    if len(footer) != SECTOR:
        raise ValueError('metadata sector must be exactly 512 bytes')
    if footer[:8] != MAGIC:
        raise ValueError('missing NGAGEMMC metadata magic')
    if footer[8] != VERSION:
        raise ValueError(f'unsupported NGAGEMMC metadata version {footer[8]}')
    cid, _ = register(footer[16:32], 'CID')
    csd, _ = register(footer[32:48], 'CSD')
    return identity(cid, csd, footer[48:52])


def capacity_report(payload_bytes, card, allow_truncated=True):
    if type(payload_bytes) is not int or payload_bytes <= 0 or payload_bytes % SECTOR:
        raise ValueError('payload must contain a positive whole number of 512-byte sectors')
    capacity = card['capacity_bytes']
    if capacity is None:
        return {'scope': 'unknown-capacity', 'complete_payload': None,
                'writable_mount_eligible': False,
                'note': 'unsupported CSD/OCR profile; archival inspection/export only'}
    if payload_bytes > capacity:
        raise ValueError(f'payload {payload_bytes} exceeds CSD capacity {capacity}')
    complete = payload_bytes == capacity
    if not complete and not allow_truncated:
        raise ValueError(f'payload {payload_bytes} is below CSD capacity {capacity}; '
                         'use --allow-truncated only for an archival prefix')
    protected = (card['csd_fields']['permanent_write_protect'] or
                 card['csd_fields']['temporary_write_protect'])
    return {'scope': 'full-capacity' if complete else 'truncated-prefix',
            'complete_payload': complete,
            'writable_mount_eligible': complete and not protected,
            'note': ('format/extent eligibility only; no hardware mount is verified' if complete else
                     'archival prefix; missing sectors are absent, not zero-filled; NOT safe for writable mounting')}


def signature(info):
    return info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns


@contextmanager
def source_file(path):
    descriptor = os.open(path, os.O_RDONLY | getattr(os, 'O_NONBLOCK', 0) | getattr(os, 'O_NOCTTY', 0))
    with os.fdopen(descriptor, 'rb') as stream:
        before = os.fstat(stream.fileno())
        if not stat.S_ISREG(before.st_mode):
            raise ValueError(f'{path}: source must be a regular file')
        yield stream, before


@contextmanager
def new_outputs(paths):
    """Reserve every output exclusively; roll back only files we created."""
    if len({path.resolve() for path in paths}) != len(paths):
        raise ValueError('output paths must be distinct')
    opened = []
    try:
        for path in paths:
            stream = path.open('xb')
            info = os.fstat(stream.fileno())
            opened.append((path, stream, (info.st_dev, info.st_ino)))
        yield [entry[1] for entry in opened]
        for _, stream, _ in opened:
            stream.flush()
            os.fsync(stream.fileno())
        for _, stream, _ in opened:
            stream.close()
    except BaseException:
        for path, stream, inode in opened:
            stream.close()
            try:
                current = path.lstat()
                if (current.st_dev, current.st_ino) == inode:
                    path.unlink()
            except FileNotFoundError:
                pass
        raise


def copy_payload(stream, count, target=None):
    payload_hash = hashlib.sha256()
    image_hash = hashlib.sha256()
    left = count
    while left:
        data = stream.read(min(left, CHUNK))
        if not data:
            raise ValueError('source truncated while reading payload')
        if target is not None:
            target.write(data)
        payload_hash.update(data)
        image_hash.update(data)
        left -= len(data)
    return payload_hash.hexdigest(), image_hash


def assert_source_unchanged(stream, info, path):
    if signature(info) != signature(os.fstat(stream.fileno())):
        raise ValueError(f'{path}: source changed while reading')


def source_record(path, size, digest):
    return {'path': str(path.resolve()), 'bytes': size, 'sha256': digest}


def report(operation, payload_size, payload_sha, footer, image_sha, sources,
           normalization=None):
    card = decode_footer(footer)
    return {'format': MANIFEST_FORMAT, 'operation': operation, 'sector_bytes': SECTOR,
            'payload': {'bytes': payload_size, 'sectors': payload_size // SECTOR,
                        'sha256': payload_sha},
            'metadata': {'bytes': SECTOR, 'sha256': sha256(footer), 'hex': footer.hex(),
                         'opaque_reserved_nonzero': bool(any(footer[9:16]) or any(footer[52:]))},
            'image': {'bytes': payload_size + SECTOR, 'sha256': image_sha},
            'identity': card, 'extent': capacity_report(payload_size, card),
            'normalization': normalization or {}, 'sources': sources}


def read_image(path):
    with source_file(path) as (stream, info):
        if info.st_size < 2 * SECTOR or info.st_size % SECTOR:
            raise ValueError('MMC image must contain payload sectors plus one complete metadata sector')
        payload_size = info.st_size - SECTOR
        stream.seek(payload_size)
        footer = stream.read(SECTOR)
        capacity_report(payload_size, decode_footer(footer))
        stream.seek(0)
        payload_sha, image_hash = copy_payload(stream, payload_size)
        if stream.read(SECTOR) != footer or stream.read(1):
            raise ValueError('MMC metadata/length changed while reading')
        image_hash.update(footer)
        assert_source_unchanged(stream, info, path)
        return report('inspect', payload_size, payload_sha, footer, image_hash.hexdigest(),
                      [source_record(path, info.st_size, image_hash.hexdigest())])


def json_bytes(value):
    return (json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + '\n').encode('utf-8')


def expect_digest(value, name):
    if not isinstance(value, str) or not re.fullmatch('[0-9a-f]{64}', value):
        raise ValueError(f'{name}: expected lowercase SHA-256')
    return value


def parse_manifest(data):
    try:
        def reject_constant(text):
            raise ValueError(f'non-finite JSON number {text}')
        value = json.loads(data, parse_constant=reject_constant)
        if not isinstance(value, dict) or value['format'] != MANIFEST_FORMAT:
            raise ValueError('unsupported MMC manifest format')
        if type(value['sector_bytes']) is not int or value['sector_bytes'] != SECTOR:
            raise ValueError('invalid manifest sector size')
        meta = value['metadata']
        if type(meta['bytes']) is not int or meta['bytes'] != SECTOR:
            raise ValueError('invalid manifest metadata size')
        footer = hex_bytes(meta['hex'], 'metadata hex', (SECTOR,))
        if sha256(footer) != expect_digest(meta['sha256'], 'metadata SHA-256'):
            raise ValueError('manifest metadata checksum mismatch')
        card = decode_footer(footer)
        opaque = bool(any(footer[9:16]) or any(footer[52:]))
        if type(meta['opaque_reserved_nonzero']) is not bool or meta['opaque_reserved_nonzero'] != opaque:
            raise ValueError('manifest opaque metadata flag disagrees with bytes')
        payload = value['payload']
        capacity_report(payload['bytes'], card)
        if type(payload['sectors']) is not int or payload['sectors'] != payload['bytes'] // SECTOR:
            raise ValueError('invalid manifest payload sector count')
        expect_digest(payload['sha256'], 'payload SHA-256')
        image = value['image']
        if type(image['bytes']) is not int or image['bytes'] != payload['bytes'] + SECTOR:
            raise ValueError('invalid manifest image size')
        expect_digest(image['sha256'], 'image SHA-256')
        if (json_bytes(value['identity']) != json_bytes(card) or
                json_bytes(value['extent']) != json_bytes(capacity_report(payload['bytes'], card))):
            raise ValueError('manifest identity/extent disagrees with metadata')
        return footer, value
    except (KeyError, TypeError, json.JSONDecodeError, UnicodeDecodeError, RecursionError) as error:
        raise ValueError(f'invalid MMC manifest: {error}') from error


def load_metadata(path):
    with source_file(path) as (stream, info):
        footer = None
        if info.st_size >= SECTOR and info.st_size % SECTOR == 0:
            stream.seek(info.st_size - SECTOR)
            candidate = stream.read(SECTOR)
            if candidate[:8] == MAGIC:
                footer = candidate
                decode_footer(footer)
        if footer is not None and info.st_size == SECTOR:
            assert_source_unchanged(stream, info, path)
            return footer, None, source_record(path, SECTOR, sha256(footer))
        if footer is None:
            if info.st_size > MAX_MANIFEST:
                raise ValueError('metadata is neither a supported MMC image nor a manifest below 64 KiB')
            stream.seek(0)
            data = stream.read(MAX_MANIFEST + 1)
            footer, manifest = parse_manifest(data)
            assert_source_unchanged(stream, info, path)
            return footer, manifest, source_record(path, info.st_size, sha256(data))
    # A sector payload may begin with JSON punctuation; footer identity takes
    # precedence, and full metadata-source images are still streamed.
    image = read_image(path)
    return bytes.fromhex(image['metadata']['hex']), None, image['sources'][0]


def raw_metadata(args):
    explicit = (args.cid is not None, args.csd is not None, args.ocr is not None)
    if args.metadata:
        if any(explicit) or args.normalize_register_crc:
            raise ValueError('--metadata cannot be combined with identity/normalization options')
        footer, expected, provenance = load_metadata(args.metadata)
        return footer, expected, [provenance], {}
    if not all(explicit):
        raise ValueError('raw input requires --cid, --csd AND --ocr, or --metadata from an existing card')
    cid, cid_note = register(hex_bytes(args.cid, 'CID', (15, 16)), 'CID', args.normalize_register_crc)
    csd, csd_note = register(hex_bytes(args.csd, 'CSD', (15, 16)), 'CSD', args.normalize_register_crc)
    ocr = hex_bytes(args.ocr, 'OCR', (4,))
    footer = bytearray(SECTOR)
    footer[:8] = MAGIC
    footer[8] = VERSION
    footer[16:32], footer[32:48], footer[48:52] = cid, csd, ocr
    return bytes(footer), None, [], {'cid': cid_note, 'csd': csd_note}


def verify_binding(expected, size, payload_sha, image_sha):
    if expected is not None and (expected['payload']['bytes'] != size or
            expected['payload']['sha256'] != payload_sha or expected['image']['sha256'] != image_sha):
        raise ValueError('raw payload/reconstructed image does not match metadata manifest checksums')


def import_raw(args, inspect_only=False):
    footer, expected, provenance, normalization = raw_metadata(args)
    card = decode_footer(footer)
    if not inspect_only and not card['supported_profile']:
        raise ValueError('unsupported import profile: requires MMC CSD structure 2/spec 3/READ_BL_LEN 9 and byte-addressing OCR')
    with source_file(args.input) as (stream, info):
        capacity_report(info.st_size, card, allow_truncated=inspect_only or args.allow_truncated)
        if expected is not None and expected['payload']['bytes'] != info.st_size:
            raise ValueError('raw payload size does not match metadata manifest')
        if inspect_only:
            payload_sha, image_hash = copy_payload(stream, info.st_size)
            image_hash.update(footer)
            verify_binding(expected, info.st_size, payload_sha, image_hash.hexdigest())
            assert_source_unchanged(stream, info, args.input)
            return report('inspect-raw', info.st_size, payload_sha, footer, image_hash.hexdigest(),
                          [source_record(args.input, info.st_size, payload_sha)] + provenance, normalization)
        manifest_path = args.manifest or Path(str(args.output) + '.json')
        with new_outputs([args.output, manifest_path]) as (target, manifest_file):
            payload_sha, image_hash = copy_payload(stream, info.st_size, target)
            image_hash.update(footer)
            verify_binding(expected, info.st_size, payload_sha, image_hash.hexdigest())
            assert_source_unchanged(stream, info, args.input)
            target.write(footer)
            value = report('import-raw', info.st_size, payload_sha, footer, image_hash.hexdigest(),
                           [source_record(args.input, info.st_size, payload_sha)] + provenance, normalization)
            value['artifacts'] = {'image': str(args.output), 'manifest': str(manifest_path)}
            manifest_file.write(json_bytes(value))
            return value


def export_raw(args):
    # Validate/hash first, then revalidate the read-only source during copying.
    value = read_image(args.input)
    footer = bytes.fromhex(value['metadata']['hex'])
    sidecar_path = args.sidecar or Path(str(args.output) + '.sidecar')
    manifest_path = args.manifest or Path(str(args.output) + '.json')
    with source_file(args.input) as (stream, info):
        if info.st_size != value['image']['bytes']:
            raise ValueError('MMC source length changed before export')
        with new_outputs([args.output, sidecar_path, manifest_path]) as (target, side, manifest_file):
            payload_sha, image_hash = copy_payload(stream, value['payload']['bytes'], target)
            if stream.read(SECTOR) != footer or stream.read(1):
                raise ValueError('MMC source metadata changed before export')
            image_hash.update(footer)
            verify_binding(value, value['payload']['bytes'], payload_sha, image_hash.hexdigest())
            assert_source_unchanged(stream, info, args.input)
            side.write(footer)
            value['operation'] = 'export-raw'
            value['artifacts'] = {'raw': str(args.output), 'sidecar': str(sidecar_path),
                                  'manifest': str(manifest_path)}
            manifest_file.write(json_bytes(value))
            return value


def add_identity_options(parser):
    parser.add_argument('--metadata', type=Path, help='existing .mmc, exact 512-byte sidecar, or export JSON manifest')
    parser.add_argument('--cid', help='actual card CID, 16 bytes of hex')
    parser.add_argument('--csd', help='actual card CSD, 16 bytes of hex')
    parser.add_argument('--ocr', help='actual card OCR, four big-endian hex bytes; no default')
    parser.add_argument('--normalize-register-crc', action='store_true',
                        help='explicitly append/replace CRC7 for 15-byte/zero-CRC Linux registers; record original bytes')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    inspect = commands.add_parser('inspect', help='validate/checksum an image without writing')
    inspect.add_argument('input', type=Path)
    inspect.add_argument('--raw', action='store_true', help='inspect raw payload with explicit card metadata')
    add_identity_options(inspect)
    join = commands.add_parser('import-raw', help='append verified actual-card metadata to raw sectors')
    join.add_argument('input', type=Path)
    join.add_argument('output', type=Path)
    join.add_argument('--manifest', type=Path)
    join.add_argument('--allow-truncated', action='store_true', help='archive a short prefix; NEVER eligible for writable mounting')
    add_identity_options(join)
    split = commands.add_parser('export-raw', help='export payload, exact metadata sector and checksum manifest')
    split.add_argument('input', type=Path)
    split.add_argument('output', type=Path)
    split.add_argument('--sidecar', type=Path)
    split.add_argument('--manifest', type=Path)
    args = parser.parse_args(argv)
    try:
        if args.command == 'inspect':
            if args.raw:
                value = import_raw(args, inspect_only=True)
            else:
                if args.metadata or args.cid or args.csd or args.ocr or args.normalize_register_crc:
                    raise ValueError('identity options require --raw; existing image metadata is never silently repaired')
                value = read_image(args.input)
        elif args.command == 'import-raw':
            value = import_raw(args)
        else:
            value = export_raw(args)
    except (ValueError, OSError) as error:
        parser.error(str(error))
    print(json.dumps(value, indent=2, sort_keys=True, allow_nan=False))


if __name__ == '__main__':
    main()
