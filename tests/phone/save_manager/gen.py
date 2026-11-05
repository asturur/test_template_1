from pathlib import Path
import struct,zlib
core=bytes(range(32));ext=bytes(range(32,64));h=struct.pack('<8sIIII32s32s',b'NGSAVE1\0',1,1,512,512,core,ext).ljust(508,b'\0');h+=struct.pack('<I',zlib.crc32(h))
Path('build/sim/unit-save-manager').mkdir(parents=True,exist_ok=True)
Path('build/sim/unit-save-manager/header.hex').write_text(''.join(f'{int.from_bytes(h[i:i+2],"little"):04x}\n' for i in range(0,len(h),2)))
