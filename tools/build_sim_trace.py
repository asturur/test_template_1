#!/usr/bin/env python3
"""Build the native NEM4 SIM fallback tracer into an unused guest ROM pad."""
import hashlib
import json
from pathlib import Path
import struct
import subprocess
ROOT = Path(__file__).resolve().parents[1]
BASE = 0x511b7000
HOOKS = [(0x2fa978, 0x5165ed25, BASE), (0x2fa958, 0x5165ecd1, BASE+4)]

def main():
    out=ROOT/'build/firmware-overlays/sim-trace'
    out.mkdir(parents=True,exist_ok=True)
    subprocess.run(['arm-none-eabi-gcc','-c','-march=armv4t','-marm',
                    str(ROOT/'firmware_overlays/diagnostics/sim_trace.S'),
                    '-o',str(out/'trace.o')],check=True)
    subprocess.run(['arm-none-eabi-ld',f'-Ttext={BASE}', '--entry=sim_trace',
                    str(out/'trace.o'),'-o',str(out/'trace.elf')],check=True)
    subprocess.run(['arm-none-eabi-objcopy','-O','binary',str(out/'trace.elf'),
                    str(out/'trace.bin')],check=True)
    data=(out/'trace.bin').read_bytes()
    if len(data)>4096 or len(data)%4:
        raise ValueError('SIM tracer payload bounds')
    records=[(BASE-0x50000000+i,0xffffffff,struct.unpack_from('<I',data,i)[0])
             for i in range(0,len(data),4)] + HOOKS
    result=dict(base=BASE,bytes=len(data),sha256=hashlib.sha256(data).hexdigest(),
                hooks=HOOKS,records=sorted(records))
    (out/'trace.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k!='records'},indent=2))
if __name__=='__main__':main()
