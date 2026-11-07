from pathlib import Path
import struct,zlib
h=struct.pack('<8sIIII32s32s',b'NGSAVE1\0',1,1,1024,1024,bytes(range(32)),bytes(range(32,64))).ljust(508,b'\0')
h+=struct.pack('<I',zlib.crc32(h))
p=Path('build/sim/unit-save-hps');p.mkdir(parents=True,exist_ok=True)
(p/'header.hex').write_text(''.join(f'{int.from_bytes(h[i:i+2],"little"):04x}\n' for i in range(0,len(h),2)))
