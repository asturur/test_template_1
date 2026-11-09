#!/bin/sh
# Run inside jotego/simulator:arm64; optional argument is a real package.
set -eu
out=build/sim/unit-overlay
mkdir -p "$out"
python3 - "$out" "${1:-}" <<'PY'
from pathlib import Path
import sys,struct,zlib
sys.path.insert(0,'tools');import nos_overlay
out=Path(sys.argv[1]);records=[(0x10000,0x12345678,0xabcdef00),(0x320860,0xffffffff,0xe3a00000),(0x13efffc,0x42,0x43)]
body=b''.join(struct.pack('<III',*r) for r in records)
h=struct.pack('<7I',nos_overlay.MAGIC,1,1,len(records),zlib.crc32(body),0x7bc70477,0xc3b897c7)+nos_overlay.DIGEST+struct.pack('<4I',64+len(body),0,12,0)
data=h+struct.pack('<I',zlib.crc32(h))+body
fixtures=[('synthetic',data)]
for name,last in [('bounds',(0x13f0000,0x42,0x43)),('alignment',(0x13efffd,0x42,0x43)),('order',records[1])]:
 bad_body=b''.join(struct.pack('<III',*r) for r in records[:2]+[last])
 bad_h=bytearray(h);struct.pack_into('<I',bad_h,16,zlib.crc32(bad_body))
 fixtures.append((name,bytes(bad_h)+struct.pack('<I',zlib.crc32(bad_h))+bad_body))
for name,data in fixtures+([('real',Path(sys.argv[2]).read_bytes())] if sys.argv[2] else []):
 if name not in ('bounds','alignment','order'):nos_overlay.inspect(data)
 (out/(name+'.hex')).write_text(''.join(f'{v[0]:04x}\n' for v in struct.iter_unpack('<H',data.ljust(8192,b'\0'))))
PY
iverilog -g2012 -s tb -o "$out/test" rtl/ngage_bram.v rtl/ngage_nos_overlay.v tests/phone/overlay/tb.sv
vvp "$out/test" +package="$out/synthetic.hex"
if [ -n "${1:-}" ]; then vvp "$out/test" +package="$out/real.hex"; fi

for bad in bounds alignment order; do vvp "$out/test" +package="$out/$bad.hex" +expected-error=3; done
