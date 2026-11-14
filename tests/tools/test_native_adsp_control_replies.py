"""Original MADI accepts RTL77/AB errors; original AB/3C dispatch advances.

Original D550 constructor locations are qualified against the immutable image
and recovered jump table. No audio success is inferred. Descriptor/allocation
leaves and the *called* reset/consumer/free methods are spies; the native ARM
response classifier executes unchanged, including the outstanding-reset guard.
"""
from pathlib import Path
import hashlib
import runpy
import struct
from unicorn import UC_HOOK_CODE
from unicorn.arm_const import UC_ARM_REG_R0, UC_ARM_REG_PC, UC_ARM_REG_LR

ROOT = Path(__file__).resolve().parents[2]
dsp = (ROOT/'firmware/MCU/extracted/products/NEM-4/E403A400H450.USB').read_bytes()
assert hashlib.sha256(dsp).hexdigest() == '0be93de04ebccd676d34ceaa2b9f4a901b3d0941565bc7b0f795e78ba8866429'
# Original 17 invalid argument: status2, reply77, payload allocation4.
for offset, code in ((0x46c4a, 'e60002'), (0x46c68, '76007748'),
                     (0x46c72, '3d45'), (0x463fe, 'e60002'),
                     (0x46407, '7600ab48'), (0x46411, '3d45')):
    assert dsp[offset:offset+len(bytes.fromhex(code))] == bytes.fromhex(code)
arm = runpy.run_path(str(ROOT/'tests/tools/test_native_adsp_bootstrap.py'))
u, call, word = (arm[x] for x in ('u', 'call', 'word'))
rx, host, payload = (arm[x] for x in ('rx', 'host', 'payload'))
seen = []
# Frame-to-Phonet descriptor leaves, as in test_native_adsp_boot_protocol.
def leaf(c, a, size, unused):
    x = c.reg_read(UC_ARM_REG_R0)
    if a == 0x510ef820:
        from unicorn.arm_const import UC_ARM_REG_R1
        n = c.reg_read(UC_ARM_REG_R1)
        assert n <= arm['rd'](x) & 0xfffffff
        c.reg_write(UC_ARM_REG_R0, 0x10000000 | n)
        c.reg_write(UC_ARM_REG_R1, arm['rd'](x+8))
    elif a == 0x510ef82c:
        from unicorn.arm_const import UC_ARM_REG_R1
        value = arm['data'](c.reg_read(UC_ARM_REG_R1))
        c.mem_write(arm['rd'](x+8), value)
        word(x, 0x20000000 | len(value))
    elif a in (0x510ed308, 0x510eaf18, 0x510ec174, 0x510eac7c):
        seen.append(a)
        if a == 0x510eaf18:
            c.reg_write(UC_ARM_REG_R0, 1) # fixture has a registered consumer
    else:
        return
    c.reg_write(UC_ARM_REG_PC, c.reg_read(UC_ARM_REG_LR))
u.hook_add(UC_HOOK_CODE, leaf)
frames = [bytes.fromhex(l.split()[1]) for l in
          (ROOT/'build/sim/unit-adsp-boot-peer/replies.txt').read_text().splitlines()
          if l.startswith('control ')]
assert len(frames) >= 4
cases = 0
for frame in frames:
    assert len(frame) == 20 and frame[11] in (0x77, 0xab)
    assert frame[12:16] == bytes.fromhex('00030002')
    arm['packet'](frame[2:])
    call(0x510edc6c, rx)
    assert u.reg_read(UC_ARM_REG_R0) == 1
    word(rx+0x14, 0x510f0488)
    call(0x510ee1a4, rx)
    buffer = u.reg_read(UC_ARM_REG_R0)
    length = arm['rd'](buffer) & 0xfffffff
    phonet = bytes(u.mem_read(buffer+4, length))
    assert length == 14 and phonet[8:] == frame[10:16]
    # Original classifier uses the serial-frame descriptor, not Phonet output.
    # With reset already outstanding it discards AB/3C; otherwise it calls
    # the real reset method (spied here), independently of returned status.
    for pending in (0, 1):
        word(host+0x8c, pending)
        word(rx, 0x80003000)
        word(0x80003008, 0) # destructor dispatch leaf is spied
        seen.clear()
        call(0x510ece24, host, rx)
        if frame[11] == 0xab:
            assert (0x510ed308 in seen) == (not pending)
            assert 0x510eaf18 not in seen
        else:
            assert 0x510eaf18 in seen and 0x510ec174 in seen
        assert seen[-1] == 0x510eac7c
        cases += 1
assert bytes(u.mem_read(0x50000000, len(arm['r']))) == arm['r']
print(f'PASS {len(frames)} RTL77/AB/status2 packets: original CRC/Phonet, '
      f'{cases} original response-classifier/guard cases; ROM unchanged')
