#!/usr/bin/env python3
"""Build/inspect NOS_Compatibility.ngo without modifying original firmware."""
import argparse, hashlib, json, re, shutil, struct, subprocess, zlib
from pathlib import Path
import service_firmware as svc
ROOT=Path(__file__).resolve().parents[1]
MAGIC=0x314F474E
DIGEST=bytes.fromhex('2c09c86ff047484fdcc0e226f49c44a9')
MAX_RECORDS=640

def decode(image):
    result=bytearray(image)
    text=(ROOT/'rtl/ngage_descramble.v').read_text()
    rules=[]
    for bit, expr in re.findall(r'assign\s+plain\[(\d+)\]\s*=\s*(.*?);',text,re.S):
        cm=int(re.search(r"C & 16'h([0-9a-f]+)",expr)[1],16)
        am=re.search(r"A & 22'h([0-9a-f]+)",expr)
        pairs=[(int(a),int(b)) for a,b in re.findall(r'A\[(\d+)\] & A\[(\d+)\]',expr)]
        rules.append((int(bit),"1'b1" in expr,cm,int(am[1],16) if am else 0,pairs))
    if len(rules)!=16:raise ValueError('descrambler format changed')
    for a in range(0xa000,0x2b3000,2):
        c=int.from_bytes(image[a:a+2],'little');p=0
        for bit,k,cm,am,pairs in rules:
            v=k ^ ((c&cm).bit_count()&1) ^ ((a&am).bit_count()&1)
            for j,l in pairs:v^=((a>>j)&(a>>l)&1)
            p|=int(v)<<bit
        result[a:a+2]=p.to_bytes(2,'little')
    return result

def inspect(data):
    if len(data)<64 or len(data)%4:raise ValueError('overlay length')
    h=struct.unpack_from('<16I',data)
    if h[0:3]!=(MAGIC,1,1) or not 0<h[3]<=MAX_RECORDS:raise ValueError('overlay format/type')
    if h[5:7]!=(svc.PROFILES['mcu'][4],svc.PROFILES['ppm'][4]):raise ValueError('target firmware')
    if data[28:44]!=DIGEST or h[11]!=len(data) or len(data)!=64+12*h[3]:raise ValueError('profile/size')
    if h[12:15]!=(0,12,0):raise ValueError('unsupported flags')
    if zlib.crc32(data[:60])!=h[15] or zlib.crc32(data[64:])!=h[4]:raise ValueError('overlay CRC')
    records=list(struct.iter_unpack('<III',data[64:]));previous=-1
    for off,old,new in records:
        if off&3 or off>=svc.BACKING_SIZE or off<=previous:raise ValueError('overlay bounds/order')
        previous=off
    return records

def build(mcu,ppm,out):
    raw=bytearray(b'\xff'*svc.BACKING_SIZE)
    for kind,path in [('mcu',mcu),('ppm',ppm)]:svc.apply(raw,svc.parse(path.read_bytes(),kind),kind)
    plain=decode(raw)
    if hashlib.md5(plain[0x9000:0x11b5000]).digest()!=DIGEST:raise ValueError('stock decoded digest mismatch')
    work=out.parent/'nos-build';work.mkdir(parents=True,exist_ok=True)
    source=ROOT/'firmware_overlays/nos';cc=shutil.which('arm-none-eabi-gcc')
    if not cc:raise ValueError('arm-none-eabi-gcc is required')
    flags=['-marm','-march=armv4t','-Os','-ffreestanding','-fno-builtin','-fno-common','-fno-pic','-fno-tree-loop-distribute-patterns','-Wall','-Wextra','-Werror']
    subprocess.run([cc,*flags,'-I',str(source),'-S','-x','c','-o',str(work/'size.s'),'-'],input=b'#include "nos_isi.h"\nchar object_size[sizeof(struct nos_ch)];\n',check=True)
    size=int(re.search(r'\.size\s+object_size,\s*(\d+)',(work/'size.s').read_text())[1])
    for file in ('nos_isi.c','nos_glue.S','bootstrap.S'):
        subprocess.run([cc,*flags,f'-DNOS_CH_SIZE={size}','-c',str(source/file),'-o',str(work/(file+'.o'))],check=True)
    subprocess.run([cc,'-nostdlib','-static',f'-Wl,-T,{source/"nos.ld"}','-Wl,--build-id=none','-o',str(work/'nos.elf'),str(work/'nos_isi.c.o'),str(work/'nos_glue.S.o')],check=True)
    subprocess.run(['arm-none-eabi-ld','-Ttext=0x50320860','--entry=nos_bootstrap','-o',str(work/'bootstrap.elf'),str(work/'bootstrap.S.o')],check=True)
    patches={}
    def add(off,payload,pad=False):
        payload+=b'\xff'*((-len(payload))%4)
        if off&3 or off+len(payload)>len(raw):raise ValueError('patch bounds')
        if pad and raw[off:off+len(payload)]!=b'\xff'*len(payload):raise ValueError('payload area not erased')
        for i in range(0,len(payload),4):
            a=off+i;n=int.from_bytes(payload[i:i+4],'little');old=int.from_bytes(raw[a:a+4],'little')
            if a in patches:raise ValueError('overlapping patches')
            if n!=old:patches[a]=(old,n)
            plain[a:a+4]=payload[i:i+4]
    for section,off in [('.exp4',0x11b4028),('.exp6',0x11b4030),('.objsize',0x11b413c),('.text',0x11b6000)]:
        dest=work/(section[1:]+'.bin');subprocess.run(['arm-none-eabi-objcopy','-O','binary','-j',section,str(work/'nos.elf'),str(dest)],check=True);add(off,dest.read_bytes(),section=='.text')
    dest=work/'bootstrap.bin';subprocess.run(['arm-none-eabi-objcopy','-O','binary','-j','.text',str(work/'bootstrap.elf'),str(dest)],check=True)
    if dest.stat().st_size>0x120:raise ValueError('bootstrap too large')
    add(0x320860,dest.read_bytes(),True)
    if int.from_bytes(raw[0x350504:0x350508],'little')!=0xea000001:raise ValueError('NOS starter ABI')
    add(0x350504,struct.pack('<I',0xea000000|(((0x50320860-(0x50350504+8))//4)&0xffffff)))
    # Nortido's absent-descriptor path skips the expensive primary scan.
    # Tie this compatibility-only bypass to NOS, including both undo words.
    add(0x8f18,b'\xff'*8)
    records=[(a,*v) for a,v in sorted(patches.items())]
    if len(records)>MAX_RECORDS:raise ValueError('overlay exceeds staging BRAM')
    body=b''.join(struct.pack('<III',*r) for r in records)
    header=struct.pack('<7I',MAGIC,1,1,len(records),zlib.crc32(body),svc.PROFILES['mcu'][4],svc.PROFILES['ppm'][4])+DIGEST+struct.pack('<4I',64+len(body),0,12,0)
    package=header+struct.pack('<I',zlib.crc32(header))+body
    inspect(package);out.write_bytes(package)
    active=bytearray(raw)
    for a,old,new in records:struct.pack_into('<I',active,a,new)
    restored=bytearray(active)
    for a,old,new in records:struct.pack_into('<I',restored,a,old)
    assert restored==raw
    assert active[0x8f18:0x8f20]==b'\xff'*8
    assert active[0x8f20:0x8f30]==raw[0x8f20:0x8f30]
    report={'name':'NOS Compatibility','file':out.name,'format':'NGO1','records':len(records),'bytes':len(package),'sha256':hashlib.sha256(package).hexdigest(),'skip_primary_checksum':True,'checksum_bypass':'absent descriptor (8F18..8F1F = FFFFFFFF)','stock_primary_md5':DIGEST.hex(),'original_files_modified':False,'off_restores_original':True,'inputs':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in (mcu,ppm)},'compiler':subprocess.check_output([cc,'--version'],text=True).splitlines()[0]}
    out.with_suffix('.json').write_text(json.dumps(report,indent=2)+'\n')
    return report

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--mcu',type=Path);p.add_argument('--ppm',type=Path);p.add_argument('--output',type=Path);p.add_argument('--inspect',type=Path);a=p.parse_args()
    if a.inspect:print(json.dumps({'records':len(inspect(a.inspect.read_bytes()))}));return
    if not all((a.mcu,a.ppm,a.output)):p.error('--mcu, --ppm and --output required')
    a.output.parent.mkdir(parents=True,exist_ok=True);print(json.dumps(build(a.mcu,a.ppm,a.output),indent=2))
if __name__=='__main__':main()
