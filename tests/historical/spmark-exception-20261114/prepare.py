from pathlib import Path
import subprocess,struct,inspect,json,hashlib,sys
sys.path.insert(0,'tools');import prepare_native_observer as native
p=Path(__file__).parent
asm='''.syntax unified
.cpu arm920t
.arm
.section .text,"ax"
.macro save
 stmdb sp!,{r0-r12,lr}
 sub sp,sp,#8
 mrs r12,cpsr
 str r12,[sp]
.endm
.macro restore
 ldr r12,[sp]
 msr cpsr_f,r12
 add sp,sp,#8
 ldmia sp!,{r0-r12,lr}
.endm
.global load_return,compare_entry
load_return:
 save
 ldr r12,[sp,#92]
 ldr r0,=0xfff028d8
 cmp r12,r0
 bne 4f
 ldr r1,[sp,#8]
 ldr r2,[r5]
 ldr r3,[sp,#92]
 ldr r0,=fmt_load
 bl debug_print
 mov r1,r6
 ldr r0,=fmt_name
 bl debug_print
4:
 restore
 add sp,sp,#12
 b 0x503ac958
compare_entry:
 save
 ldr r12,[sp,#60]
 ldr r0,=0xfff029fc
 cmp r12,r0
 bne 2f
 ldr r0,[sp,#8]
 mov r2,r1
 mov r1,r0
 mov r3,r12
 ldr r0,=fmt_compare
 bl debug_print
2:
 restore
 stmdb sp!,{lr}
 b 0x503a61c8
'''
asm+='''
.global lookup_return,fatal_entry
lookup_return:
 save
 ldr r12,[sp,#72]
 ldr r0,=0xfff02920
 cmp r12,r0
 bne 5f
 ldr r1,[sp,#8]
 mov r2,#0
 cmp r1,#0xf0000000
 blo 6f
 sub r12,r1,#0x74
 ldr r0,=0xeb3a0
 ldr r2,[r12,r0]
6:
 ldr r3,[sp,#72]
 ldr r0,=fmt_lookup
 bl debug_print
5:
 restore
 ldmia sp!,{r4,r5,lr}
 b 0x503b2520
fatal_entry:
 save
 ldr r7,=0x59000000
 mov r0,#0xc0
 strb r0,[r7]
 ldr r4,=prefix
 bl literal
 ldr r0,[sp,#24]
 bl hex
 bl space
 ldr r6,[sp,#28]
 ldr r0,[r6,#0x3c]
 bl hex
 bl space
 ldr r0,[r6,#0x40]
 bl hex
 bl space
 ldr r5,[sp,#36]
 ldr r0,[r5]
 bl hex
 bl space
 ldr r0,[r5,#4]
 bl hex
 bl space
 ldr r0,[r5,#8]
 bl hex
 bl space
 mov r5,#0
7:
 ldr r0,[r6,r5]
 bl hex
 bl space
 add r5,r5,#4
 cmp r5,#0x3c
 bne 7b
 mov r0,#10
 strb r0,[r7]
 mov r0,#0xc0
 strb r0,[r7]
 ldr r4,=prefix_cp15
 bl literal
 mrc p15,0,r0,c13,c0,0
 bl hex
 bl space
 mrc p15,0,r0,c2,c0,0
 bl hex
 bl space
 mrc p15,0,r0,c3,c0,0
 bl hex
 mov r0,#10
 strb r0,[r7]
 ldr r0,[r6,#0x3c]
 ldr r1,=0x503a6b78
 cmp r0,r1
 bne 9f
 ldr r5,[r6,#0x34]
 cmp r5,#0x00400000
 blo 9f
 cmp r5,#0x01000000
 bhs 9f
 mov r1,r5,lsl #20
 mov r1,r1,lsr #20
 cmp r1,#0xf80
 bhi 9f
 mov r0,#0xc0
 strb r0,[r7]
 ldr r4,=prefix_stack
 bl literal
 mov r0,r5
 bl hex
 bl space
 mov r6,#32
10:
 ldr r0,[r5],#4
 bl hex
 bl space
 subs r6,r6,#1
 bne 10b
 mov r0,#10
 strb r0,[r7]
9:
 restore
 mov r0,#3
 b 0x5032cd24
literal:
 ldrb r0,[r4],#1
 cmp r0,#0
 bxeq lr
 strb r0,[r7]
 b literal
space:
 mov r0,#32
 strb r0,[r7]
 bx lr
hex:
 stmdb sp!,{r1-r3,lr}
 mov r1,#8
8:
 mov r2,r0,lsr #28
 cmp r2,#10
 addlo r2,r2,#48
 addhs r2,r2,#87
 strb r2,[r7]
 mov r0,r0,lsl #4
 subs r1,r1,#1
 bne 8b
 ldmia sp!,{r1-r3,pc}
prefix_cp15: .asciz "S CP15 "
prefix_stack: .asciz "S STACK "
prefix: .asciz "S FATAL "
.balign 4
'''
asm+='''
.global fill_entry
fill_entry:
 save
 ldr r12,[sp,#60]
 cmp r12,#0xff000000
 blo 11f
 cmp r2,#64
 bne 11f
 ldr r1,[sp,#8]
 ldr r3,[sp,#60]
 ldr r0,=fmt_fill
 bl debug_print
11:
 restore
 stmdb sp!,{r4,lr}
 b 0x503a31d8
'''
for k,s in [('fill','S FILL dst=%08x len=%08x caller=%08x'),('lookup','S LOOK factory=%08x glerr=%08x caller=%08x'),('load' ,'S LOAD code=%08x handle=%08x caller=%08x'),('name','S DLL %S'),('compare','S CMP0 lo=%08x hi=%08x caller=%08x')]:
 asm+=f'.balign 4\nfmt_{k}: .word {hex(0x10000000|len(s))},str_{k}\nstr_{k}: .hword '+','.join(str(ord(c)) for c in s)+'\n'
asm+='\n.balign 4\n.ltorg\n';(p/'trace.S').write_text(asm)
(p/'trace.ld').write_text('debug_print = 0x503b409c; SECTIONS { .text 0x511b8000 : { *(.text*) } /DISCARD/ : { *(.ARM.attributes) *(.comment) *(.note*) } }')
for cmd in [['arm-none-eabi-gcc','-c','-mcpu=arm920t',str(p/'trace.S'),'-o',str(p/'trace.o')],['arm-none-eabi-ld','-T',str(p/'trace.ld'),str(p/'trace.o'),'-o',str(p/'trace.elf')],['arm-none-eabi-objcopy','-O','binary',str(p/'trace.elf'),str(p/'trace.bin')]]:subprocess.run(cmd,check=True)
blob=(p/'trace.bin').read_bytes();assert len(blob)<4096 and len(blob)%4==0
symtext=subprocess.check_output(['arm-none-eabi-nm',str(p/'trace.elf')],text=True);(p/'symbols.txt').write_text(symtext);syms={a[2]:int(a[0],16) for l in symtext.splitlines() if len(a:=l.split())==3}
extra=[(0x11b8000+i,0xffffffff,struct.unpack_from('<I',blob,i)[0]) for i in range(0,len(blob),4)]
hooks=[('load_return',0x503ac954,0xe28dd00c),('compare_entry',0x503a61c4,0xe92d4000),('lookup_return',0x503b251c,0xe8bd4030),('fatal_entry',0x5032cd20,0xe3a00003),('fill_entry',0x503a31d4,0xe92d4010)]
for name,a,old in hooks:
 target=syms[name];extra.append((a-0x50000000,old,0xea000000|(((target-a-8)//4)&0xffffff)))
s=inspect.getsource(native.prepare);needle='records = runtime.exit_records(payload, slow_wait=slow_wait)';s=s.replace(needle,needle+'\n    records += extra_records');ns=dict(vars(native),extra_records=extra);exec(compile(s,'prepare_spmark','exec'),ns)
r=ns['prepare'](p/'prepared',False);r.update(spmark_observer_sha256=hashlib.sha256(blob).hexdigest(),scope='Observation only: SPMark-only load/lookup/result and fatal unhandled user exception frame. No functional substitution; kernel uses direct byte port only',hooks=hooks)
(p/'observer-manifest.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r))
