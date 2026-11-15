"""Original, bounded SPMark/GLES workloads; no recompiled rendering kernels."""
import hashlib
import random
import struct
from pathlib import Path

PAYLOAD_BASE = 0x10000000
ROM_BASE = 0x50300000
RAM_BASE = 0x80000000
RAM_SIZE = 0x20000
EXPECTED_IMAGES = {
    '3DTEST.DLL': '5b918e3d10a8b4e91265325649c98c72fba7260be6cab37a102d7f50cd7eebef',
    'libGLES_CM.dll': '3008a3900a91471200ea00b26733066aad288d589a7f48cefbfc0c6b62ebad2b',
}
ROM_SHA = 'be8b2ecdf5ff81f424b58838a8b93a1d1f65c0ae74890d2b96df8d5a7189b524'


def words(values):
    return struct.pack('<%dI' % len(values), *(v & 0xffffffff for v in values))


def image(path):
    raw = Path(path).read_bytes()
    if hashlib.sha256(raw).hexdigest() != EXPECTED_IMAGES[Path(path).name]:
        raise ValueError(f'unexpected original payload: {path}')
    h = struct.unpack_from('<31I', raw)
    if h[19] != PAYLOAD_BASE or h[13] or h[18]:
        raise ValueError('unsupported E32 image layout')
    return bytearray(raw[h[25]:h[25] + h[12]])


def cases():
    rng = random.Random(0x534d3034)
    result = []
    n = 16
    a = [rng.randrange(-200000, 200000) for _ in range(n * 16)]
    b = [rng.randrange(-200000, 200000) for _ in range(n * 16)]
    expected = []
    for i in range(n):
        aa, bb = a[i*16:(i+1)*16], b[i*16:(i+1)*16]
        expected += [sum((aa[r+k*4] * bb[k+c*4]) >> 16 for k in range(4))
                     for c in range(4) for r in range(4)]
    result.append(dict(id='matrix4', module='3DTEST.DLL', entry=0x216c,
                       iterations=n, unit='4x4 matrix products',
                       writes=[(0x80001000, words(a)), (0x80002000, words(b))],
                       regs=[0x80003000, 0x80001000, 0x80002000],
                       strides=[64, 64, 64], checks=[(0x80003000, words(expected))]))
    n = 32
    a = [rng.getrandbits(32) for _ in range(n * 16)]
    expected = [a[i*16+c+r*4] for i in range(n) for c in range(4) for r in range(4)]
    result.append(dict(id='transpose4', module='3DTEST.DLL', entry=0x2644,
                       iterations=n, unit='4x4 matrix transposes',
                       writes=[(0x80001000, words(a))], regs=[0x80001000],
                       strides=[64], checks=[(0x80001000, words(expected))]))
    ctx, arena, output = 0x80000100, 0x80004000, 0x80000300
    writes = [(ctx + 0x30, words([arena])), (ctx + 0x38, words([output])),
              (ctx + 0xd0, words([0, 64, 0, 64])),
              (output + 0x34, bytes(12)), (arena + 0x3a04, bytes(128))]
    for i, (x, y) in enumerate([(4, 4), (28, 4), (4, 28)]):
        writes.append((arena + 0x804 + 128*i + 0x28, words([x << 12, y << 12])))
    # Original edge setup uses a top-left/right-exclusive rule:23 nonempty
    # scanlines, followed by one zero-width extent. No host division stub.
    result.append(dict(id='triangle_edges', module='libGLES_CM.dll', entry=0x2be0,
                       iterations=16, unit='triangle edge setups', writes=writes,
                       regs=[ctx, 0x020100, 0], strides=[0, 0, 0],
                       checks=[(output + 0x34, words([23, arena + 0x3a04, 4])),
                               (arena + 0x3a04, words([(w << 16) | 4 for w in range(23, -1, -1)] + [0]*8))]))
    for id_, entry, count, value, offset, width in [
            ('fill16_frame', 0x2ab4, 176*208, 0x5a7c, 0, 2),
            ('fill16_tail', 0x2ab4, 1023, 0x31a7, 2, 2),
            ('fill8_tail', 0x29f8, 2051, 0x5a, 1, 1)]:
        start = 0x80004000
        before = bytes([0xa5]) * ((count*width + 19) & ~3)
        expected = bytearray(before)
        expected[offset:offset+count*width] = value.to_bytes(width, 'little') * count
        result.append(dict(id=id_, module='libGLES_CM.dll', entry=entry,
                           iterations=1, unit='pixels' if width == 2 else 'bytes',
                           operations=count, writes=[(start, before)],
                           regs=[start+offset, value, count], strides=[0, 0, 0],
                           checks=[(start, bytes(expected))]))
    for c in result:
        c.setdefault('operations', c['iterations'])
        c['warmups'], c['samples'] = 2, 5
    return result


def assembly(c, corrupt=False):
    """Guest wrapper does setup/checks outside the retired-PC timing window."""
    setup, data = [], []
    for i, (address, raw) in enumerate(c['writes']):
        assert len(raw) % 4 == 0
        setup += [f'ldr r0,=init_{i}', f'ldr r1,={address}', f'ldr r2,={len(raw)//4}',
                  f'copy_{i}: ldr r3,[r0],#4', 'str r3,[r1],#4',
                  'subs r2,r2,#1', f'bne copy_{i}']
        data += [f'init_{i}:', '.byte ' + ','.join(str(x) for x in raw)]
    checks = []
    for i, (address, raw) in enumerate(c['checks']):
        assert len(raw) % 4 == 0
        expected = bytearray(raw)
        if corrupt and i == 0:
            expected[0] ^= 1
        checks += [f'ldr r0,={address}', f'ldr r1,=expected_{i}',
                   f'ldr r2,={len(raw)//4}', f'check_{i}: ldr r3,[r0],#4',
                   'ldr r7,[r1],#4', 'cmp r3,r7', 'bne fail',
                   'subs r2,r2,#1', f'bne check_{i}']
        data += [f'expected_{i}:', '.byte ' + ','.join(str(x) for x in expected)]
    # LR/BLX construction deliberately uses ARMv4T MOV/BX, not BLX.
    regs = '\n'.join(f'mov r{i},r{4+i}' for i in range(len(c['regs'])))
    pointers = '\n'.join(f'ldr r{4+i},={value}' for i, value in enumerate(c['regs']))
    advance = '\n'.join(f'add r{4+i},r{4+i},#{stride}' for i, stride in enumerate(c['strides']) if stride)
    return f'''.syntax unified
.cpu arm920t
.arm
.section .vectors,"ax"
.global _start
_start:
 b reset_entry
 .rept 7
 b fail
 .endr
.section .text,"ax"
reset_entry:
 ldr sp,=0x8001b000
 ldr r4,=0x0a01c000
 mov r0,#0
 mov r1,#4096
zero_table: str r0,[r4],#4
 subs r1,r1,#1
 bne zero_table
 ldr r4,=0x0a01c000
 ldr r0,=0x00000c0e
 str r0,[r4]
 ldr r0,=0x0a000c0e
 ldr r5,=0x2000
 str r0,[r4,r5]
 ldr r0,=0x10000c0e
 str r0,[r4,#0x400]
 ldr r0,=0x50300c0e
 ldr r5,=0x140c
 str r0,[r4,r5]
 ldr r0,=0xf0000c02
 ldr r5,=0x3c00
 str r0,[r4,r5]
 mcr p15,0,r4,c2,c0,0
 mov r0,#1
 mcr p15,0,r0,c3,c0,0
 mrc p15,0,r0,c1,c0,0
 orr r0,r0,#5
 orr r0,r0,#0x1000
 mcr p15,0,r0,c1,c0,0
 mov r11,#{c['warmups']+c['samples']}
sample_loop:
 {chr(10).join(setup)}
 {pointers}
 mov r8,#{c['iterations']}
.global body_begin
body_begin:
 nop
call_loop:
 {regs}
 ldr r12,={PAYLOAD_BASE+c['entry']}
 mov lr,pc
 bx r12
 {advance}
 subs r8,r8,#1
 bne call_loop
.global body_end
body_end:
 nop
 {chr(10).join(checks)}
 subs r11,r11,#1
 bne sample_loop
 mov r0,#0
 mcr p15,0,r0,c7,c14,0
 ldr r0,=0x50415353
 b finish
fail:
 ldr r0,=0x4641494c
finish:
 ldr r1,=0xf0000000
 str r0,[r1]
 b .
.ltorg
.balign 4
 {chr(10).join(data)}
'''
