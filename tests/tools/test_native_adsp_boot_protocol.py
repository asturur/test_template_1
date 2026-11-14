"""Original NOS -> original MADI -> RTL reply -> original MADI/NOS contracts.

Execution uses immutable original instructions with explicit allocator,
descriptor, timer and transport leaves. The CPU/board UART segment is tested
separately by native_adsp_boot; no full RTOS boot is claimed here.
"""
import argparse
import hashlib
import runpy
import struct
from pathlib import Path
from unicorn import UC_HOOK_CODE
from unicorn.arm_const import UC_ARM_REG_R0, UC_ARM_REG_R1, UC_ARM_REG_PC, UC_ARM_REG_LR

ROOT = Path(__file__).resolve().parents[2]
# The production signature is the audited factory image's actual word, not an
# arbitrary success constant or a claim that the C55x firmware is executed.
dsp=(ROOT/'firmware/MCU/extracted/products/NEM-4/E403A400H450.USB').read_bytes()
assert hashlib.sha256(dsp).hexdigest()=='0be93de04ebccd676d34ceaa2b9f4a901b3d0941565bc7b0f795e78ba8866429'
assert dsp[0x160000:0x160002]==bytes.fromhex('fffc')
parser = argparse.ArgumentParser()
parser.add_argument('--emit', type=Path)
parser.add_argument('--capture', type=Path)
args = parser.parse_args()
arm = runpy.run_path(str(ROOT/'tests/tools/test_native_adsp_bootstrap.py'))
nos = runpy.run_path(str(ROOT/'tests/tools/test_native_startup_contracts.py'))
u, call, word, desc, data = (arm[k] for k in ('u','call','word','desc','data'))
# Native TPtrC8 Left() return and TDes8 Copy() leaves needed by the original
# frame-to-Phonet conversion. All protocol instructions remain original.
def imports(c, address, size, unused):
    a, n = c.reg_read(UC_ARM_REG_R0), c.reg_read(UC_ARM_REG_R1)
    if address == 0x510ef820:
        pointer = arm['rd'](a+8)
        assert n <= arm['rd'](a) & 0xfffffff
        c.reg_write(UC_ARM_REG_R0, 0x10000000|n)
        c.reg_write(UC_ARM_REG_R1, pointer)
    elif address == 0x510ef82c:
        value = data(n)
        pointer = arm['rd'](a+8)
        c.mem_write(pointer,value)
        word(a,0x20000000|len(value))
    else:
        return
    c.reg_write(UC_ARM_REG_PC,c.reg_read(UC_ARM_REG_LR))
u.hook_add(UC_HOOK_CODE, imports)

native, sent, timers, _, _ = nos['fixture']()
assert nos['call'](native,0x516a6218)==2
assert timers==[3000] and len(sent)==1 and sent[0][0]==0x82
header, body, packet = 0x80001000,0x80001100,0x80001200
for a,p,value in ((header,0x80001400,bytes.fromhex('00000082')),
                  (body,0x80001500,b'\0\0'+sent[0][2])):
    desc(a,p,len(value));u.mem_write(p,value)
call(0x510ee2e0,packet,header,body,1)
for entry,value in ((0x510edcac,1),(0x510edcc4,None),(0x510ee168,None),
                    (0x510ee088,1),(0x510edc0c,None)):
    call(entry,packet,*(() if value is None else (value,)))
request = data(packet+4)
assert request.hex()=='555520780082000c00000e2b00070042000001412fd9'
if args.emit:
    args.emit.mkdir(parents=True,exist_ok=True)
    (args.emit/'diagnostic.bin').write_bytes(request)
    # This is also verified by the original D0/04 receive branch above.
    (args.emit/'link-ack.bin').write_bytes(arm['REPLY'])

frames = []
if args.capture:
    for line in args.capture.read_text().splitlines():
        if line.startswith('NATIVE_RX '):
            capture=bytes.fromhex(line.split()[1])
            assert len(capture)==62
            assert capture[:14]==arm['BOOT'] and capture[14:28]==arm['RESET']
            # The boot peer ACK must match the outstanding original host packet,
            # including resource/address and sequence; not merely a valid CRC.
            arm['packet'](capture[28:40][2:])
            call(0x510edc6c,arm['rx']);assert u.reg_read(UC_ARM_REG_R0)==1
            call(0x510edfc4,arm['rx']);assert u.reg_read(UC_ARM_REG_R0)==1
            call(0x510ee014,packet,arm['rx']);assert u.reg_read(UC_ARM_REG_R0)==1
            call(0x510ee0e0,arm['rx']);assert u.reg_read(UC_ARM_REG_R0)==1
            frames.append(capture[40:62])
else:
    path=ROOT/'build/sim/unit-adsp-boot-peer/replies.txt'
    if path.exists():frames=[bytes.fromhex(l.split()[1]) for l in path.read_text().splitlines() if l.startswith('reply ')]
for frame in frames:
    assert frame[:2]==b'UU' and len(frame)==22
    arm['packet'](frame[2:])
    call(0x510edc6c,arm['rx']);assert u.reg_read(UC_ARM_REG_R0)==1
    word(arm['rx']+0x14,0x510f0488)
    call(0x510ee1a4,arm['rx'])
    buffer=u.reg_read(UC_ARM_REG_R0)
    length=arm['rd'](buffer)&0xfffffff
    phonet=bytes(u.mem_read(buffer+4,length))
    assert length==16 and phonet[:6]==bytes.fromhex('20007882000a')
    payload=phonet[8:]
    assert payload[:4]==bytes.fromhex('0e8b0007')
    native, sends, deadlines, freed, _ = nos['fixture']()
    native.mem_write(nos['STATE'],b'\1')
    native.mem_write(nos['RESPONSE'],struct.pack('<I',nos['MESSAGE']))
    native.mem_write(nos['MESSAGE'],payload)
    assert nos['call'](native,0x516a6218)==0
    assert bytes(native.mem_read(nos['OUT'],1))==bytes([int(payload[6:8]!=b'\0\0')])
    assert freed==[nos['MESSAGE']] and not sends and not deadlines
assert bytes(u.mem_read(0x50000000,len(arm['r'])))==arm['r']
print(f'PASS original NOS diagnostic request/deadline, MADI fragment, {len(frames)} RTL/native-UART replies, original frame-to-Phonet and NOS result/free; ROM unchanged')
