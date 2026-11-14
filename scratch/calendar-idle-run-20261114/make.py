from pathlib import Path
p=Path(__file__).parent
s='.syntax unified\n.arm\n.section .text,"ax"\n'
for name,entry in [('start',0x50399d70),('run',0x50399dac),('ready',0x50399da4)]:
 s+=f'''.global {name}_trace
{name}_trace:
 stmdb sp!,{{r0-r12,lr}}
 sub sp,sp,#8
 mrs r4,cpsr
 str r4,[sp]
 and r4,r4,#31
 cmp r4,#16
 bne {name}_restore
 {'ldr r5,[sp,#24]' if name=='ready' else 'mov r5,r0'}
'''
 if name=='start':s+=' mov r6,r1\n mov r7,r2\n'
 else:s+=' ldr r6,[r5,#0x18]\n ldr r7,[r5,#0x1c]\n'
 s+=f''' ldr r4,=0x50833d44
 cmp r6,r4
 blo {name}_restore
 ldr r4,=0x5089495c
 cmp r6,r4
 blo {name}_log
 ldr r4,=0x5099ec44
 cmp r6,r4
 blo {name}_restore
 ldr r4,=0x509b30f8
 cmp r6,r4
 bhs {name}_restore
{name}_log:
 ldr r0,=fmt_{name}
 mov r1,r5
 {'ldr r2,[r5,#4]' if name=='ready' else 'mov r2,r6'}
 {'ldr r3,[r5,#0x14]' if name=='ready' else 'mov r3,r7'}
 bl debug_print
{name}_restore:
 ldr r4,[sp]
 msr cpsr_f,r4
 add sp,sp,#8
 ldmia sp!,{{r0-r12,lr}}
 .word {'0xe8bd4010' if name=='ready' else '0xe92d4010'}
 b {entry+4:#x}
'''
for name in ['start','run','ready']:
 t=(f'I {name.upper()} object=%08x callback=%08x param=%08x' if name!='ready' else 'I READY object=%08x status=%08x priority=%08x');s+=f'fmt_{name}: .word {0x10000000+len(t):#x},str_{name}\nstr_{name}: .hword '+','.join(str(ord(c)) for c in t)+'\n.balign 4\n'
s+='.ltorg\n';(p/'trace.S').write_text(s)
(p/'trace.ld').write_text('ENTRY(start_trace)\ndebug_print = 0x503b409c;\nSECTIONS { .text 0x511b8000 : { *(.text*) } /DISCARD/ : { *(.ARM.attributes) *(.comment) *(.note*) } }\n')
s=Path('scratch/calendar-scan-user-20261114/prepare.py').read_text().replace('calendar-scan-user-20261114','calendar-idle-run-20261114');a=s.index('rom=Path');b=s.index('s=inspect.getsource',a);s=s[:a]+'''for name,addr in [('start',0x50399d70),('run',0x50399dac),('ready',0x50399da4)]:
 extra.append((addr-0x50000000,0xe8bd4010 if name=='ready' else 0xe92d4010,0xea000000|(((syms[name+'_trace']-addr-8)//4)&0xffffff)))
'''+s[b:];a=s.index("r['bitmap_trace']=");b=s.index(";(p/'manifest.json')",a);s=s[:a]+"r['idle_trace']='Global CIdle Start/RunL observation only in USER mode and callbacks within AgnModel/Agnsynca/Agndasvr or Calendar; native debug print; original first push and body preserved';r['scope']='Observe scheduling versus execution, no functional startup substitutions, no kernel printing, no direct MMIO, no idle callback substitution'"+s[b:];(p/'prepare.py').write_text(s)
