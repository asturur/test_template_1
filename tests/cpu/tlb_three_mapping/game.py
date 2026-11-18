"""Checked original Sega Rally and Asphalt rendering-loop fixtures."""
from collections import Counter
import struct

from source import ROOT
from build import digest

BASE = 0x10000000
RAM = 0x80000000
A, B, STACK, TABLE, DEST = (RAM+i for i in (0x1000, 0x3000, 0x5000, 0x6000, 0x8000))
PIXELS = 512
IMAGES = {
    'sega': ('sega_rally/local/6R12.app', 251508,
             '236f5094346a8ebf4ec49ac76bcd381f59ba49642fd3f182e27c28a248bfbe16'),
    'asphalt': ('asphalt_urban_gt/local/6R67.app', 642196,
                '41b55148917bae5c48bcb3985c225fac9bcb81a7714e9b889b6bd892a170bf84'),
}
LOOPS = {
    'sega-span': ('sega', 0x1da54, 0x1daa0),
    'sega-fill': ('sega', 0x1c9f4, 0x1ca04),
    'asphalt-table': ('asphalt', 0x56d3c, 0x56da0),
    'asphalt-double': ('asphalt', 0x56eb4, 0x56efc),
    'asphalt-single': ('asphalt', 0x56f30, 0x56f5c),
}


def image(game):
    path, size, sha = IMAGES[game]
    raw = (ROOT/'tests/cpu'/path).read_bytes()
    assert len(raw) == size and digest(raw) == sha
    offset = struct.unpack_from('<I', raw, 25*4)[0]
    assert offset == 0x7c
    return raw[offset:]


def halfwords(values):
    return b''.join(struct.pack('<H', value) for value in values)


def stack_words(entries):
    stack = bytearray(128)
    for offset, value in entries.items():
        struct.pack_into('<I', stack, offset, value)
    return bytes(stack)


def fixture(name):
    # Deliberately put roles in distinct 1 KiB regions inside the same section.
    # All active source indices are bounded independently by these functions.
    stack = bytes(128)
    if name == 'sega-span':
        texture = [((i*1973) ^ (i>>2) ^ 0x519d) & 0xffff for i in range(256)]
        inputs = [(A, halfwords(texture))]
        first = 3
        x0, dx, y0, dy = 1<<16, 0x3000, 2<<16, 0x6800
        regs = {0:x0, 4:dx, 5:dy, 8:PIXELS+first, 12:y0, 14:first}
        stack = stack_words({0:DEST-2*first, 44:15, 48:15, 52:16, 64:A})
        values = [texture[16*(((x0+i*dx)//1024)&15)+(((y0+i*dy)//1024)&15)]
                  for i in range(PIXELS)]
    elif name == 'sega-fill':
        inputs = []
        first = 3
        regs = {0:DEST-2*first, 1:PIXELS+first-1, 2:first, 12:0xb67d}
        values = [0xb67d]*PIXELS
    elif name == 'asphalt-table':
        scales = [0x0c000+i*0x1800 for i in range(32)]
        textures = [[(0xf201+i if (i+source)%3==0 else 0x2200+source*0x4100+i)
                     for i in range(256)] for source in range(2)]
        inputs = [(A, halfwords(textures[0])), (B, halfwords(textures[1])),
                  (TABLE, struct.pack('<32I', *scales))]
        x0, dx, y0, dy, z0, dz = 0x4200, 0x680, 0x8000, 0x5b0, 0x500, 0x80
        regs = {0:x0, 1:y0, 2:dx, 3:dy, 4:z0, 5:dz, 6:15, 7:4, 8:DEST, 14:0}
        stack = stack_words({56:DEST+2*PIXELS, 60:B, 64:A, 68:TABLE})
        values = []
        for i in range(PIXELS):
            scale = scales[(z0+i*dz)//4096]
            x = ((x0+i*dx)//1024*scale//65536)&15
            y = ((y0+i*dy)//1024*scale//65536)&15
            values.append(textures[i%2][x+16*y])
        assert all(any(test(values[i]) for i in range(source, PIXELS, 2))
                   for source in (0,1) for test in (lambda v:v<=0xf000, lambda v:v>0xf000))
    else:
        x0, dx, y0, dy = 0x8000, 0x6700, 0x28000, 0x9700
        texture = [0x1100+i if i%3 else 0xf700+i for i in range(256)]
        extra = [0x0240 if i%2 else 0xe800 for i in range(512)]
        inputs = [(A, halfwords(texture))]
        regs = {0:x0, 1:y0, 2:dx, 3:dy, 4:15, 5:4, 6:A, 7:DEST, 8:DEST+2*PIXELS}
        if name == 'asphalt-double':
            inputs.append((B, halfwords(extra)))
            regs.update({9:B, 14:17})
        values = []
        for i in range(PIXELS):
            index = (((x0+i*dx)//65536)&15) + 16*(((y0+i*dy)//65536)&15)
            values.append(texture[index] | (extra[index+17] if name=='asphalt-double' else 0))
    initial = bytes((0x53+i*19+(i>>2))&255 for i in range(2*PIXELS+64))
    output = bytearray(initial)
    stores = []
    for i, value in enumerate(values):
        if not name.startswith('asphalt') or value<=0xf000:
            struct.pack_into('<H', output, 32+2*i, value)
            stores.append((DEST+2*i, 2, value))
    if name.startswith('asphalt'):
        assert 0<len(stores)<PIXELS
    inputs += [(STACK, stack)]
    return dict(id=name, regs=regs, writes=inputs+[(DEST-32, initial)],
                checks=[(DEST-32, bytes(output))]+inputs, stores=stores,
                unit='pixels visited', operations=PIXELS, warmups=2, samples=5)


def verify(case, code, entry, last):
    from unicorn import Uc, UC_ARCH_ARM, UC_MODE_ARM, UC_HOOK_CODE, UC_HOOK_MEM_WRITE
    from unicorn.arm_const import UC_ARM_REG_R0, UC_ARM_REG_SP, UC_ARM_REG_CPSR, UC_ARM_REG_PC, UC_ARM_REG_LR
    cpu = Uc(UC_ARCH_ARM, UC_MODE_ARM)
    cpu.mem_map(BASE, 0x100000)
    cpu.mem_write(BASE+entry, code)
    cpu.mem_map(RAM, 0x20000)
    cpu.reg_write(UC_ARM_REG_CPSR, 0x13)
    cpu.reg_write(UC_ARM_REG_SP, STACK)
    for address, raw in case['writes']:
        cpu.mem_write(address, raw)
    for reg, value in case['regs'].items():
        cpu.reg_write(UC_ARM_REG_LR if reg==14 else UC_ARM_REG_R0+reg, value)
    pcs, stores = Counter(), []
    cpu.hook_add(UC_HOOK_CODE, lambda c, a, n, u: pcs.update([a]))
    cpu.hook_add(UC_HOOK_MEM_WRITE, lambda c, t, a, n, v, u: stores.append((a,n,v)))
    exit_pc = BASE+last+4
    cpu.emu_start(BASE+entry, exit_pc, count=case['operations']*26+1)
    assert cpu.reg_read(UC_ARM_REG_PC) == exit_pc
    assert pcs == Counter({BASE+pc: case['operations'] for pc in range(entry,last+4,4)})
    assert stores == case['stores']
    outputs = []
    for address, want in case['checks']:
        got = bytes(cpu.mem_read(address, len(want)))
        assert got == want, (case['id'], hex(address))
        outputs.append(dict(address=hex(address), bytes=len(want), sha256=digest(got)))
    return dict(status='PASS', instructions=sum(pcs.values()), stores=len(stores), outputs=outputs,
                loop_sha256=digest(code))


def assembly(case, entry, bad, standard):
    # Reuse the original RAM/MMU setup and full-buffer checks. The captured
    # inline loops use r11 and/or lr, so the wrapper keeps its sample count in
    # an untimed RAM word and uses an out-of-loop absolute return shim.
    template = standard(dict(case, regs=[], strides=[], iterations=1, entry=entry), corrupt=bad)
    counter = case.get('counter',0x800060fc)
    stack = case.get('stack',STACK)
    template = template.replace(' mov r11,#7', f''' ldr r0,={counter:#x}
 mov r1,#7
 str r1,[r0]''')
    start = template.index(' mov r8,#1')
    end = template.index('body_end:', start)
    regs = '\n'.join(f' ldr r{i},={value}' for i,value in sorted(case['regs'].items()))
    template = template[:start]+f''' ldr sp,={stack}
.global body_begin
body_begin:
 nop
 {regs}
 ldr pc,={BASE+entry}
.global loop_return
loop_return:
.global body_end
'''+template[end:]
    return template.replace(' subs r11,r11,#1', f''' ldr r0,={counter:#x}
 ldr r1,[r0]
 subs r1,r1,#1
 str r1,[r0]''')
