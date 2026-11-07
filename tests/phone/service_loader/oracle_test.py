"""Malformed containers must fail independently of whole-file identification."""
import importlib.util
from pathlib import Path
spec = importlib.util.spec_from_file_location('service', 'tools/service_firmware.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
b = (m.ROOT/'firmware/NEM-04 v.04.03 N-GAGE/nem440.326').read_bytes()
first = m.PROFILES['ppm'][2]
def reject(data, identify=False):
    try:
        m.parse(data, 'ppm', identify)
    except ValueError:
        return
    raise AssertionError('invalid container accepted')
for cut in (0, 1, 9, 10, first-1, first, first+9, first+10, len(b)-1):
    reject(b[:cut])
for pos in (0, 10, first, first+5, first+9, first+10, len(b)-1):
    corrupt = bytearray(b)
    corrupt[pos] ^= 1
    reject(corrupt, True)
for address in (0x2400000, 0x7F0000, 0xFFFFFFFF):
    corrupt = bytearray(b)
    corrupt[first+1:first+5] = address.to_bytes(4, 'big')
    corrupt[first+9] = (255-sum(corrupt[first+1:first+9])) & 255
    reject(corrupt)
reject(b+b'\0')
print('PASS bounded host parser: truncation, metadata, checksums, writable/overflow addresses and trailing bytes')
