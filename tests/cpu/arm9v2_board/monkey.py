"""Public synthetic inputs/reference; original game code is read only at run time."""
import hashlib
import struct
from collections import Counter
from pathlib import Path

SHA = 'd43052bebaed6401bd8a1482b5a2072022b2d0ff3ac7d6f538be860f0d5ddd77'
BASE, ENTRY, EXIT = 0x10000000, 0x93e38, 0x93e88
PIXELS, FIRST = 512, 3
SOURCE, DEST, STACK = 0x80001000, 0x80004000, 0x80008000
ARENA, ARENA_SIZE = DEST - 32, 1088


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def extract(path):
    raw = Path(path).read_bytes()
    if len(raw) != 793068 or digest(raw) != SHA:
        raise ValueError('private SuperMonkeyBall.app does not match the profile')
    header = struct.unpack_from('<31I', raw)
    if header[25] != 0x7c or header[12] != 0xbd718 or header[19] != BASE:
        raise ValueError('unexpected E32 code layout')
    return raw[0x7c + ENTRY:0x7c + EXIT]


def fixture(pattern):
    if pattern == 'forward':
        source = bytes(((i * 73) ^ (i >> 3) ^ 0xa6) & 255 for i in range(4096))
        coordinate, delta, stride, bias = 0x10000, 0x2000, 17, 3
    elif pattern == 'reverse':
        source = bytes(((i * 29 + 17) ^ (i >> 1) ^ (i >> 5)) & 255 for i in range(4096))
        coordinate, delta, stride, bias = 0x3f8000, -0x1800, 19, 7
    else:
        raise ValueError('unknown pattern')
    initial = bytes((i * 41 + (i >> 2) + 0x5d) & 255 for i in range(ARENA_SIZE))
    expected = bytearray(initial)
    addresses = []
    # Per-pixel mathematical definition, independent of ARM decoding/execution.
    for pixel in range(PIXELS):
        row = (coordinate + pixel * delta) // 65536
        offset = 2 * (row * stride + bias)
        assert 0 <= offset < len(source) - 1
        address = DEST + 2 * (FIRST + pixel)
        value = source[offset] + 256 * source[offset + 1]
        struct.pack_into('<H', expected, address - ARENA, value)
        addresses.append(SOURCE + offset)
    stack = bytearray(128)
    for offset, value in {0: 0, 4: bias, 32: stride, 44: SOURCE,
                          20: delta, 104: FIRST + PIXELS}.items():
        struct.pack_into('<I', stack, offset, value & 0xffffffff)
    return dict(pattern=pattern, source=source, initial=initial, expected=bytes(expected),
                stack=bytes(stack), coordinate=coordinate, delta=delta, stride=stride,
                bias=bias, addresses=addresses)


def check(actual, expected):
    if actual != expected:
        index = next(i for i, (a, b) in enumerate(zip(actual, expected)) if a != b)
        raise ValueError(f'pixel/guard mismatch at arena byte {index}')


def oracle(code, f):
    from unicorn import Uc, UC_ARCH_ARM, UC_MODE_ARM, UC_HOOK_CODE, UC_HOOK_MEM_WRITE
    from unicorn.arm_const import UC_ARM_REG_R0, UC_ARM_REG_PC, UC_ARM_REG_SP, UC_ARM_REG_CPSR
    cpu = Uc(UC_ARCH_ARM, UC_MODE_ARM)
    cpu.mem_map(BASE, 0x100000)
    cpu.mem_write(BASE + ENTRY, code)
    cpu.mem_map(0x80000000, 0x20000)
    for address, value in [(SOURCE, f['source']), (ARENA, f['initial']), (STACK, f['stack'])]:
        cpu.mem_write(address, value)
    cpu.reg_write(UC_ARM_REG_CPSR, 0x13)
    cpu.reg_write(UC_ARM_REG_SP, STACK)
    for r in range(13):
        cpu.reg_write(UC_ARM_REG_R0 + r, 0x12340000 + r)
    for r, v in {4: FIRST, 5: f['coordinate'], 7: DEST}.items():
        cpu.reg_write(UC_ARM_REG_R0 + r, v)
    pcs, writes = Counter(), []
    def executed(c, address, size, unused):
        pcs[address] += 1
    def written(c, access, address, size, value, unused):
        writes.append((address, size, value))
    cpu.hook_add(UC_HOOK_CODE, executed)
    cpu.hook_add(UC_HOOK_MEM_WRITE, written)
    cpu.emu_start(BASE + ENTRY, BASE + EXIT, count=PIXELS * 20 + 1)
    assert cpu.reg_read(UC_ARM_REG_PC) == BASE + EXIT
    assert pcs == Counter({BASE + ENTRY + i * 4: PIXELS for i in range(20)})
    assert len(writes) == PIXELS
    assert [(a, s) for a, s, v in writes] == [(DEST + 2 * (FIRST + i), 2) for i in range(PIXELS)]
    got = bytes(cpu.mem_read(ARENA, ARENA_SIZE))
    check(got, f['expected'])
    assert bytes(cpu.mem_read(SOURCE, len(f['source']))) == f['source']
    assert bytes(cpu.mem_read(STACK, len(f['stack']))) == f['stack']
    negatives = []
    for index in [DEST + FIRST * 2 - ARENA, 0, ARENA_SIZE - 1]:
        bad = bytearray(got)
        bad[index] ^= 1
        try:
            check(bytes(bad), f['expected'])
        except ValueError:
            negatives.append(index)
        else:
            raise ValueError('reference accepted deliberate pixel/guard corruption')
    return dict(status='PASS', instructions=sum(pcs.values()), stores=len(writes),
                source_unique_halfwords=len(set(f['addresses'])),
                source_lines=len({a // 32 for a in f['addresses']}),
                destination_lines=len({a // 32 for a, s, v in writes}),
                output_sha256=digest(got), negative_bytes_rejected=negatives)


def assembly(f, corrupt=False):
    # Same section mappings/cache enable as the existing original-payload harness.
    prefix = (Path(__file__).parents[1] / 'spmark_payload/workloads.py').read_text()
    prefix = prefix.split("return f'''.syntax unified", 1)[1].split(' mov r11,', 1)[0]
    prefix = '.syntax unified' + prefix
    setup, data = [], []
    for label, address, raw in [('source', SOURCE, f['source']), ('arena', ARENA, f['initial']),
                                ('stack', STACK, f['stack'])]:
        setup += [f'ldr r0,={address}', f'ldr r1,={label}', f'ldr r2,={len(raw)//4}',
                  f'copy_{label}: ldr r3,[r1],#4', 'str r3,[r0],#4',
                  'subs r2,r2,#1', f'bne copy_{label}']
        data += [label + ':', '.byte ' + ','.join(map(str, raw))]
    checks = []
    for label, address, raw in [('expected', ARENA, f['expected']),
                                ('source_check', SOURCE, f['source']),
                                ('stack_check', STACK, f['stack'])]:
        checks += [f'ldr r0,={address}', f'ldr r1,={label}', f'ldr r2,={len(raw)//4}',
                   f'check_{label}: ldr r3,[r0],#4', 'ldr r6,[r1],#4', 'cmp r3,r6',
                   'bne fail', 'subs r2,r2,#1', f'bne check_{label}']
        data += [label + ':', '.byte ' + ','.join(map(str, raw))]
    corruption = f'ldr r0,={DEST + FIRST*2}\n ldrb r1,[r0]\n eor r1,r1,#1\n strb r1,[r0]' if corrupt else ''
    return prefix + f'''
 mov r11,#7
sample_loop:
 {chr(10).join(setup)}
 ldr sp,={STACK}
 mov r4,#{FIRST}
 ldr r5,={f['coordinate']}
 ldr r7,={DEST}
 ldr r12,={BASE + ENTRY}
 mov lr,pc
 bx r12
 {corruption}
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
