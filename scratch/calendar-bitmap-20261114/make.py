from pathlib import Path
import struct,hashlib
p=Path('scratch/calendar-bitmap-20261114')
base=Path('scratch/calendar-lcd-port-20261114/make.py').read_text().replace("Path('scratch/calendar-lcd-port-20261114')","Path('scratch/calendar-bitmap-20261114')")
exec(compile(base,'base_lcd_generator','exec'),{})
s=(p/'trace.S').read_text();rom=Path('build/firmware/nem4-factory/core.bin').read_bytes();assert hashlib.sha256(rom).hexdigest()=='be8b2ecdf5ff81f424b58838a8b93a1d1f65c0ae74890d2b96df8d5a7189b524'
for name,addr in [('pixel',0x50558f8c),('scan',0x505598a4),('stretch',0x50559f20)]:
 s+=f'''.arm
.balign 4
.global {name}_trace
{name}_trace:
    ldr r3,[sp],#4 // Restore the Thumb entry thunk's temporary r3.
    stmdb sp!,{{r0-r12,lr}}
    sub sp,sp,#8
    mrs r4,cpsr
    str r4,[sp]
    ldr r4,[r2,#4]
    tst r4,#31
    bne {name}_restore
'''
 if name=='pixel':s+=f'    ldr r4,[r2]\n    cmp r4,#0\n    bne {name}_restore\n'
 s+='    mov r5,r0\n    mov r6,r2\n    mov r7,r3\n    mov r8,lr\n    ldr r12,=0x59000000\n    mov r0,#0xc0\n    strb r0,[r12]\n'
 fields=[('G '+name.upper()+' bitmap=', 'mov r0,r5'),(' width=','ldr r0,[r5,#0x1c]'),(' height=','ldr r0,[r5,#0x20]'),(' depth=','ldr r0,[r5,#0x2c]'),(' colour=','ldr r0,[r5,#0x30]'),(' compression=','ldr r0,[r5,#0x38]'),(' x=','ldr r0,[r6]'),(' y=','ldr r0,[r6,#4]'),(' arg3=','mov r0,r7'),(' caller=','mov r0,r8')]
 if name=='scan':fields.append((' data=','ldr r0,[sp,#76]'))
 for i,(t,inst) in enumerate(fields):s+=f'    ldr r0,=gtext_{name}_{i}\n    bl emit_string\n    {inst}\n    bl emit_hex\n'
 s+=f'''{name}_restore:
    ldr r4,[sp]
    msr cpsr_f,r4
    add sp,sp,#8
    ldmia sp!,{{r0-r12,lr}}
    stmdb sp!,{{r12}}
    ldr r12,={name}_replay+1
    bx r12
.thumb
.balign 2
{name}_replay:
    push {{r3}}
    ldr r3,[sp,#4]
    mov r12,r3
    pop {{r3}}
    add sp,#4
'''
 # These exact prologues contain no PC-relative or control-flow instructions.
 expected={0x50558f8c:'f0b54f464646c0b4061c8846',0x505598a4:'f0b557464e464546e0b489b0',0x50559f20:'f0b557464e464546e0b48ab0'}[addr];assert rom[addr-0x50000000:addr-0x50000000+12].hex()==expected
 s+='    .hword '+','.join(hex(x) for x in struct.unpack('<6H',bytes.fromhex(expected)))+'\n'
 s+=f'''    sub sp,#8
    str r3,[sp]
    ldr r3,={addr+12+1:#x}
    str r3,[sp,#4]
    ldr r3,[sp]
    add sp,#4
    pop {{pc}}
.arm
.balign 4
'''
 for i,(t,inst) in enumerate(fields):s+=f'gtext_{name}_{i}: .asciz "{t}"\n'
 s+='.balign 4\n.ltorg\n'
(p/'trace.S').write_text(s)
