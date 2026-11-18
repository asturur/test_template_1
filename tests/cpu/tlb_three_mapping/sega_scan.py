"""Original Sega Rally full-screen loop and its native FbsCli hot callees."""
from collections import Counter
import re
import struct

import game
from build import digest

PIXELS = 176*208
ENTRY, LAST = 0x1dcc4, 0x1dcf4
SRC, DEST, OBJECT = 0x80020000, 0x80004000, 0x80000800
STACK = 0x80018000
FBS_BASE, FBS_EXPORTS = 0x50500000, 0x50560ab0
IMPORTS = {0x3c178:(62,0x5055d3bd),0x3c17c:(105,0x5055d2b1)}


def fixture(rom):
    code = game.image('sega')
    for iat,(ordinal,target) in IMPORTS.items():
        assert struct.unpack_from('<I',code,iat)[0]==ordinal
        assert struct.unpack_from('<I',rom,FBS_EXPORTS-0x50000000+4*(ordinal-1))[0]==target
    src = [(i*1297^(i>>1)^0x73aa)&0xffff for i in range(PIXELS)]
    initial = [(0x45b3+i*17)&0xffff for i in range(PIXELS)]
    final = [prior if pixel&0x8000 else pixel for pixel,prior in zip(src,initial)]
    written = sum((value&0x8000)==0 for value in src)
    guard = bytes.fromhex('b579e31c')*8

    # Exactly the fields read by SetPixel and IncXPos. Begin's original
    # 16bpp branch sets mask=0xffff, step=16, X shift=0 at (0,0); the
    # native cursor wraps to base at the bitmap end. OS ownership is outside
    # this steady-state replay. Adjacent object bytes are checked unchanged.
    obj = struct.pack('<10I',0,DEST,DEST,DEST+PIXELS*2,16,1,0,0xffff,88,0)
    saved = max(i for i,value in enumerate(src) if value<0x8000)
    stack = struct.pack('<II',saved,game.BASE+0x1dce4)
    writes = [(SRC-32,guard+game.halfwords(src)+guard),
              (DEST-32,guard+game.halfwords(initial)+guard),
              (OBJECT-32,guard+obj+guard),
              (STACK-40,guard+bytes(8)+guard)]
    checks = [writes[0], (DEST-32,guard+game.halfwords(final)+guard), writes[2],
              (STACK-40,guard+stack+guard)]
    case = dict(id='sega-scan', operations=PIXELS, unit='pixels visited', written_pixels=written,
                regs={4:0,5:OBJECT,6:SRC}, stack=STACK, counter=0x80018400, writes=writes, checks=checks, warmups=2, samples=5)
    return case, code


def payload(code, symbols):
    # Keep exact loop and veneer bytes at their normal E32 offsets. Only
    # the IAT entries are linked and an outside-the-loop return shim added.
    data = bytearray(max(IMPORTS)+4)
    data[ENTRY:LAST+4] = code[ENTRY:LAST+4]
    data[LAST+4:LAST+12] = struct.pack('<II',0xe51ff004,symbols['loop_return'])
    data[0x35018:0x35038] = code[0x35018:0x35038]
    for iat,(_,target) in IMPORTS.items():
        struct.pack_into('<I',data,iat,target)
    return bytes(data)


def assembly(case, bad, standard):
    asm = game.assembly(case,ENTRY,False,standard)  # game assembly uses section RAM
    setup = ' str r0,[r4,r5]\n mcr p15,0,r4,c2,c0,0'
    assert asm.count(setup)==1
    asm = asm.replace(setup, ''' str r0,[r4,r5]
 ldr r0,=0x50300c0e
 ldr r5,=0x1414
 str r0,[r4,r5]
 mcr p15,0,r4,c2,c0,0''')
    # The source is immutable. Its init bytes are also its expected bytes,
    # so the wrapper need not store a second 73 KiB copy. Flip an expected
    # destination byte for the negative control.
    pattern = r'^expected_0:\n\.byte [^\n]+$'
    if bad:
        before, expected = re.search(r'(^expected_1:\n\.byte )([^\n]+)$',asm,re.M).groups()
        values = expected.split(',')
        values[32] = str(int(values[32])^1)
        asm = asm.replace(before+expected,before+','.join(values),1)
    asm,count = re.subn(pattern,'.set expected_0, init_0',asm,count=1,flags=re.M)
    assert count==1
    return asm


def verify(case, code, firmware, observe_pc=None):
    from unicorn import Uc, UC_ARCH_ARM, UC_MODE_ARM, UC_HOOK_CODE, UC_HOOK_MEM_WRITE
    from unicorn.arm_const import UC_ARM_REG_R0, UC_ARM_REG_SP, UC_ARM_REG_CPSR, UC_ARM_REG_PC
    cpu = Uc(UC_ARCH_ARM,UC_MODE_ARM)
    cpu.mem_map(game.BASE,0x100000)
    cpu.mem_write(game.BASE,payload(code,{'loop_return':0}))
    cpu.mem_map(FBS_BASE,0x100000)
    cpu.mem_write(FBS_BASE,firmware)
    cpu.mem_map(game.RAM,0x40000)
    for address,raw in case['writes']:
        cpu.mem_write(address,raw)
    for reg,value in case['regs'].items():
        cpu.reg_write(UC_ARM_REG_R0+reg,value)
    cpu.reg_write(UC_ARM_REG_CPSR,0x13)
    cpu.reg_write(UC_ARM_REG_SP,STACK)
    pcs, stores = Counter(), Counter()
    def execute(cpu, address, size, unused):
        pcs.update([address])
        if observe_pc is not None:
            observe_pc(address)
    cpu.hook_add(UC_HOOK_CODE,execute)
    cpu.hook_add(UC_HOOK_MEM_WRITE,lambda c,t,a,n,v,u:stores.update([a]))
    stop = game.BASE+LAST+4
    cpu.emu_start(game.BASE+ENTRY,stop,count=5000000)
    assert cpu.reg_read(UC_ARM_REG_PC)==stop
    assert cpu.reg_read(UC_ARM_REG_SP)==STACK
    for pc in range(ENTRY,LAST+4,4):
        assert pcs[game.BASE+pc]==PIXELS, (hex(pc),pcs[game.BASE+pc])
    assert pcs[0x5055d2b0]==case['written_pixels'] and pcs[0x5055d3bc]==PIXELS
    assert all(game.BASE<=pc<game.BASE+0x100000 or FBS_BASE<=pc<FBS_BASE+0x100000 for pc in pcs)
    assert sum(count for addr,count in stores.items() if DEST<=addr<DEST+PIXELS*2)==2*case['written_pixels']
    outputs = []
    for address,want in case['checks']:
        got = bytes(cpu.mem_read(address,len(want)))
        assert got==want, (hex(address),next((i for i,(x,y) in enumerate(zip(got,want)) if x!=y),None))
        outputs.append(dict(address=hex(address),bytes=len(got),sha256=digest(got)))
    return dict(status='PASS', payload_instructions=sum(n for pc,n in pcs.items() if pc<FBS_BASE),
                helper_instructions=sum(n for pc,n in pcs.items() if pc>=FBS_BASE),
                written_pixels=case['written_pixels'], memory_writes=sum(stores.values()),
                outputs=outputs, loop_sha256=digest(code[ENTRY:LAST+4]),
                native_exports={ordinal:hex(target) for ordinal,target in IMPORTS.values()})
