#!/usr/bin/env python3
"""Build a private, volatile NEM-4 synthetic SIM experiment; never edit inputs."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import service_firmware
ROOT=Path(__file__).resolve().parents[1]
BASE=0x51716a00
ROM_SHA='88fd596a23269ecb0d9f7544d540c59010d276574dbe3d0262c870c429e58329'

def rules():
    result=[]
    for bit,expr in re.findall(r'assign\s+plain\[(\d+)\]\s*=\s*(.*?);',
                              (ROOT/'rtl/ngage_descramble.v').read_text(),re.S):
        cm=int(re.search(r"C & 16'h([0-9a-f]+)",expr)[1],16)
        am=re.search(r"A & 22'h([0-9a-f]+)",expr)
        pairs=[(int(a),int(b)) for a,b in re.findall(r'A\[(\d+)\] & A\[(\d+)\]',expr)]
        result.append((int(bit),"1'b1" in expr,cm,int(am[1],16) if am else 0,pairs))
    if len(result)!=16:raise ValueError('descrambler changed')
    return result

def decode16(cipher,address,rule):
    result=0
    for bit,k,cm,am,pairs in rule:
        value=int(k)^((cipher&cm).bit_count()&1)^((address&am).bit_count()&1)
        for a,b in pairs:value^=(address>>a)&(address>>b)&1
        result|=value<<bit
    return result

def encode16(plain,address,rule):
    # Solve the16x16 linear cipher contribution with exact GF(2) elimination.
    target=plain^decode16(0,address,rule)
    rows=[cm|(((target>>bit)&1)<<16) for bit,k,cm,am,pairs in sorted(rule)]
    for col in range(16):
        pivot=next(i for i in range(col,16) if rows[i]&(1<<col))
        rows[col],rows[pivot]=rows[pivot],rows[col]
        for i in range(16):
            if i!=col and rows[i]&(1<<col):rows[i]^=rows[col]
    result=sum(((rows[i]>>16)&1)<<i for i in range(16))
    if decode16(result,address,rule)!=plain:raise ValueError('cipher inverse failed')
    return result

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--production',action='store_true',help='omit debug output and self-test observer hooks')
    args=parser.parse_args()
    out=ROOT/'build/firmware-overlays'/('virtual-sim-production' if args.production else 'virtual-sim')
    out.mkdir(parents=True,exist_ok=True)
    # Reconstruct the audited backing from original service containers. No
    # dependence on a prior live capture or generated scratch artifacts.
    raw=bytearray(b'\xff'*service_firmware.BACKING_SIZE)
    for kind,spec in service_firmware.PROFILES.items():
        path=ROOT/'firmware/NEM-04 v.04.03 N-GAGE'/spec[0]
        service_firmware.apply(raw,service_firmware.parse(path.read_bytes(),kind),kind)
    if hashlib.sha256(raw).hexdigest()!=ROM_SHA:raise ValueError('wrong original ROM')
    out.joinpath('sim.ld').write_text('ENTRY(virtual_sim_indication)\nSECTIONS { .text 0x51716a00 : { *(.entry) *(.text*) *(.rodata*) . = ALIGN(4); } /DISCARD/ : { *(.comment) *(.ARM*) *(.note*) } }\nASSERT(. <= 0x51717000, "SIM payload enters ROM directory")\n')
    for source,mode in [('virtual_sim.c','-marm'),('virtual_sim_entry.S','-mthumb')]:
        subprocess.run(['arm-none-eabi-gcc','-c','-Os','-march=armv4t',mode,
          *([] if args.production else ['-DVSIM_TRACE']),'-ffreestanding','-fno-builtin','-fno-jump-tables','-Wall','-Wextra','-Werror',
          str(ROOT/'firmware_overlays/nos'/source),'-o',str(out/(source+'.o'))],check=True)
    subprocess.run(['arm-none-eabi-ld','-T',str(out/'sim.ld'),
       str(out/'virtual_sim_entry.S.o'),str(out/'virtual_sim.c.o'),'-o',str(out/'sim.elf')],check=True)
    subprocess.run(['arm-none-eabi-objcopy','-O','binary',str(out/'sim.elf'),str(out/'sim.bin')],check=True)
    symbols={p[2]:int(p[0],16) for line in subprocess.check_output(['arm-none-eabi-nm',str(out/'sim.elf')],text=True).splitlines() if len(p:=line.split())==3}
    data=(out/'sim.bin').read_bytes();changes={}
    def patch(off,payload,old=None):
        if old is not None and raw[off:off+len(old)]!=old:raise ValueError('unexpected original bytes')
        for i,value in enumerate(payload):changes[off+i]=value
    if raw[0x316a00:0x316a00+len(data)]!=bytes(len(data)):raise ValueError('NOS pad changed')
    patch(0x316a00,data)
    sim_hooks=[]
    native=(ROOT/'firmware/THC N-Gage ROM Dump/ngage-gsmstuff-0x5149D280.dll').read_bytes()
    if hashlib.sha256(native).hexdigest()!='e5870e918c90d9c7a6403eb0ee305d174e906aeae0a7fa8069e85a18aeec7aa1':
        raise ValueError('wrong audited NOS dump')
    nos=native[96:]
    # Only audited getter methods; retain PIN/security and all other native methods.
    methods=(0x3114,0x3504,0x3330,0x3350,0x3385,0x3386,0x3311,0x3382,0x3380,0x3360,0x3310)
    for method in methods:
        hits=[]
        for i in range(0x516fa000-0x5149d280,len(nos)-8,8):
            if struct.unpack_from('<I',nos,i)[0]==method:
                old=struct.unpack_from('<I',nos,i+4)[0]
                if 0x51400000<old<0x51710000: hits.append((i+4,old))
        # Tables are4-byte aligned, not uniformly8-byte aligned.
        for i in range(0x516fa004-0x5149d280,len(nos)-8,8):
            if struct.unpack_from('<I',nos,i)[0]==method:
                old=struct.unpack_from('<I',nos,i+4)[0]
                if 0x51400000<old<0x51710000: hits.append((i+4,old))
        if len(hits)!=1:raise ValueError(('ambiguous native SIM method',hex(method),hits))
        i,old=hits[0];off=0x9d280+i
        patch(off,struct.pack('<I',symbols['virtual_sim_request']),struct.pack('<I',old))
        sim_hooks.append(off)
    # Virtual handset has no physical RF transceiver or ADSP. Exclude only
    # those two from automatic group2; keep their functions, IDs, severity
    # and explicit diagnostics intact. Never overwrite failure results.
    excluded=[]
    for descriptor,expected_id,name in ((0x2f799c,0x1e,'ST_RF_CHIP_ID_TEST'),
                                        (0x2f79bc,0x36,'ST_ADSP_TEST')):
        name_va=struct.unpack_from('<I',raw,descriptor+4)[0]
        name_offset=name_va-0x51400000
        if raw[name_offset:name_offset+len(name)+1]!=name.encode()+b'\0':
            raise ValueError('wrong native selftest descriptor')
        if raw[descriptor+10]!=expected_id:raise ValueError('wrong native selftest id')
        patch(descriptor+11,b'\0',b'\2')
        excluded.append(dict(id=expected_id,name=name,automatic_group_before=2,
                             automatic_group_after=0,physical_function_retained=True))
    rule=rules()
    calls=[(0x25edc0,BASE,0x514ba2f8),(0x26196a,BASE,0x514ba2f8)]
    if not args.production:
        calls += [(0x1919b6,symbols['virtual_selftest_send']&~1,0x514bddf8),
                  (0x191a60,symbols['virtual_selftest_send']&~1,0x514bddf8)]
    for off,destination,original_target in calls:
        original=b''.join(struct.pack('<H',decode16(struct.unpack_from('<H',raw,off+i)[0],off+i,rule)) for i in (0,2))
        h1,h2=struct.unpack('<HH',original);delta=((h1&0x7ff)<<12)|((h2&0x7ff)<<1)
        if delta&(1<<22):delta-=1<<23
        if 0x51400000+off+4+delta!=original_target:raise ValueError('wrong native broadcast call')
        delta=destination-(0x51400000+off+4)
        if not -(1<<22)<=delta<(1<<22):raise ValueError('Thumb BL out of range')
        halves=(0xf000|((delta>>12)&0x7ff),0xf800|((delta>>1)&0x7ff))
        patch(off,b''.join(struct.pack('<H',encode16(h,off+i,rule)) for i,h in zip((0,2),halves)))
    words=sorted({off&~3 for off in changes});records=[]
    for off in words:
        new=bytes(changes.get(off+i,raw[off+i]) for i in range(4))
        records.append((off,struct.unpack_from('<I',raw,off)[0],int.from_bytes(new,'little')))
    records_sha=hashlib.sha256(b''.join(struct.pack('<III',*record) for record in records)).hexdigest()
    report=dict(records_sha256=records_sha,base=BASE,bytes=len(data),sha256=hashlib.sha256(data).hexdigest(),symbols=symbols,
       excluded_automatic_tests=excluded,
       diagnostic_trace=not args.production,
       hooks=sim_hooks+[0x2f79a4,0x2f79c4,0x25edc0,0x261968,0x26196c]+([] if args.production else [0x1919b4,0x1919b8,0x191a60]),records=records,
       limits='Logical SIM with applicable startup tests; no physical RF/ADSP; carrier/signal not implemented; Menu/Contacts hardware verified with extended deadlines; normal-deadline/save qualification pending')
    (out/'sim.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k!='records'},indent=2))
if __name__=='__main__':main()
