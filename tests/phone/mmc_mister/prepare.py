"""Generated, non-private card with strict identity and 2 KiB payload."""
from pathlib import Path
import importlib.util

root = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('mmc_image', root / 'tools/ngage_mmc_image.py')
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)
out = root / 'build/sim/unit-mmc-mister'
out.mkdir(parents=True, exist_ok=True)
cid = bytes.fromhex('00112233445566778899aabbccddee')
cid += bytes([(tool.crc7(cid) << 1) | 1])
csd_bits = (2 << 126) | (3 << 122) | (0x015 << 84) | (9 << 80) | (1 << 79) | (1 << 77)
csd = csd_bits.to_bytes(16, 'big')[:15]
csd += bytes([(tool.crc7(csd) << 1) | 1])
metadata = bytearray(512)
metadata[:8], metadata[8] = b'NGAGEMMC', 1
metadata[16:32], metadata[32:48], metadata[48:52] = cid, csd, bytes.fromhex('00ff8000')
payload = bytes((n * 37 + 0x93 + (n >> 9) * 17) & 255 for n in range(2048))
image = payload + metadata
Path(out / 'image.hex').write_text(''.join(f'{int.from_bytes(image[n:n+2], "little"):04x}\n' for n in range(0, len(image), 2)))
assert cid.hex() == '00112233445566778899aabbccddee91', cid.hex()
program = (out / 'program.bin').read_bytes()
program += bytes((-len(program)) % 4)
(out / 'program.hex').write_text(''.join(f'{int.from_bytes(program[n:n+4], "little"):08x}\n' for n in range(0, len(program), 4)))
