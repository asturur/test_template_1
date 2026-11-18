from pathlib import Path
p=Path('scratch/calendar-lcd-port-20261114');s='.syntax unified\n.arm\n.section .text,"ax"\n'
points=[('window',0x50400544,0xe92d4030,['L WINDOW start=',' end=',' caller=']),('header12',0x50400640,0xe92d4010,['L HEADER12 bytes=',' caller=',' sample25=']),('header16',0x50400668,0xe92d4010,['L HEADER16 bytes=',' caller=',' sample25=']),('line',0x50400efc,0xe92d4070,['L LINE row=',' mode=',' sample25='])]
for name,addr,word,fmt in points:
 s+=f'''.global {name}_trace
{name}_trace:
    stmdb sp!,{{r0-r12,lr}}
    sub sp,sp,#8
    mrs r4,cpsr
    str r4,[sp]
'''
 if name=='line':s+='''    ldr r5,[r1]
    ldr r6,[r0,#0x70]
    ldr r7,[r1,#8]
    ldr r7,[r7,#100]
'''
 else:
  s+='    mov r5,r0\n'
  s+=('    mov r6,r1\n    mov r7,lr\n' if name=='window' else '    mov r6,lr\n    mov r7,#0\n')
  if name=='header12':s+='''    ldr r0,=0x5040184c
    cmp r6,r0
    bne 1f
    ldr r0,[sp,#24] // Original caller r4: first row.
    ldr r1,[sp,#28] // Original caller r5: DMA object.
    ldr r2,[sp,#36] // Original caller r7: row count.
    cmp r2,#0
    beq 1f
    mov r3,#60
    cmp r0,r3
    bhi 2f
    add r4,r0,r2
    cmp r4,r3
    bhi 3f
2:  mov r3,r0
3:  add r4,r3,r3,lsl #2
    add r4,r3,r4,lsl #1
    ldr r12,[r1,#0x38]
    add r12,r12,r4,lsl #5
    ldrh r7,[r12,#50] // Pixel25 in a row within the pending DMA band.
1:
'''
 s+='''    ldr r12,=0x59000000
    mov r0,#0xc0
    strb r0,[r12]
'''
 for idx,reg in enumerate(['r5','r6','r7']):s+=f'    ldr r0,=text_{name}_{idx}\n    bl emit_string\n    mov r0,{reg}\n    bl emit_hex\n'
 s+=f'''    ldr r4,[sp]
    msr cpsr_f,r4
    add sp,sp,#8
    ldmia sp!,{{r0-r12,lr}}
    .word {word:#x}
    b {addr+4:#x}
'''
s+='''emit_string:
    ldr r12,=0x59000000
4:  ldrb r1,[r0],#1
    cmp r1,#0
    strbne r1,[r12]
    bne 4b
    bx lr
emit_hex:
    ldr r12,=0x59000000
    mov r1,#8
5:  mov r2,r0,lsr #28
    cmp r2,#10
    addlo r2,r2,#48
    addhs r2,r2,#87
    strb r2,[r12]
    mov r0,r0,lsl #4
    subs r1,r1,#1
    bne 5b
    bx lr
'''
for name,addr,word,fmt in points:
 for idx,t in enumerate(fmt):s+=f'text_{name}_{idx}: .asciz "{t}"\n'
s+='.balign 4\n.ltorg\n';(p/'trace.S').write_text(s);(p/'trace.ld').write_text('ENTRY(window_trace)\nSECTIONS { .text 0x511b8000 : { *(.text*) } /DISCARD/ : { *(.ARM.attributes) *(.comment) *(.note*) } }\n')
