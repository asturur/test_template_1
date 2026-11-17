"""Independent untimed post-index cases added to the existing memory guest."""
from pathlib import Path

# label, address, stored word, resulting R5, expect accept/base commit, credit
CASES = [
 ('post_add0',0x80001d00,0x11223344,0x80001d04,1,1),
 ('post_add1',0x80001d04,0x55667788,0x80001d08,1,1),
 ('post_add12',0x80001d08,0x11223344,0x80001d14,1,1),
 ('post_sub8',0x80001d14,0x55667788,0x80001d0c,1,1),
 ('post_same_base',0x80001d0c,0x80001d0c,0x80001d10,1,0),
 ('post_false',0,0,0,0,0),
 ('post_true',0x80001d10,0x11223344,0x80001d14,1,0),
 ('post_pre',0x80001d18,0x55667788,0x80001d18,1,0),
 ('post_after_pre',0x80001d18,0x11223344,0x80001d1c,1,1),
 ('post_latedata',0x80001d20,0xaabbccdd,0x80001d24,1,0),
 ('post_device',0xf0000004,0x11223344,0xf0000008,1,0),
]
for name in ['translation','permission','alignment']:
    CASES += [(f'post_fault_{name}',0,0,0,0,0),(f'post_forbidden_{name}',0,0,0,0,0)]
CASES += [('post_after_bad_load',0,0,0,0,0)]

def program(text):
    guest = '''
 b post_cases_start
 .ltorg
post_cases_start:
 ldr r5,=0x80001d00
 ldr r6,=0x11223344
 ldr r7,=0x55667788
 ldr r0,[r5]
.global post_add0
post_add0: str r6,[r5],#4
.global post_add1
post_add1: str r7,[r5],#4
.global post_add12
post_add12: str r6,[r5],#12
.global post_sub8
post_sub8: str r7,[r5],#-8
.global post_same_base
post_same_base: str r5,[r5],#4
 cmp r6,r6
.global post_false
post_false: strne r7,[r5],#4
.global post_true
post_true: streq r6,[r5],#4
.global post_pre
post_pre: str r7,[r5,#4]!
.global post_after_pre
post_after_pre: str r6,[r5],#4
 ldr r0,=0x80001d1c
 cmp r5,r0
 bne fail
 ldr r0,=0x80001d00
 ldr r1,[r0]
 cmp r1,r6
 bne fail
 ldr r1,[r0,#4]
 cmp r1,r7
 bne fail
 ldr r1,[r0,#8]
 cmp r1,r6
 bne fail
 ldr r1,[r0,#12]
 add r2,r0,#12
 cmp r1,r2
 bne fail
 ldr r1,[r0,#16]
 cmp r1,r6
 bne fail
 ldr r1,[r0,#20]
 cmp r1,r7
 bne fail
 ldr r1,[r0,#24]
 cmp r1,r6
 bne fail
 // Cold source, resident destination: exercise the existing late-data owner.
 ldr r0,=0x80001f00
 ldr r1,=0xaabbccdd
 str r1,[r0]
 mov r1,#0
 mcr p15,0,r1,c7,c14,0
 ldr r5,=0x80001d20
 ldr r1,[r5]
 .balign 32
 ldr r6,[r0]
.global post_latedata
post_latedata: str r6,[r5],#4
 ldr r1,[r5,#-4]
 ldr r2,=0xaabbccdd
 cmp r1,r2
 bne fail
 ldr r2,=0x80001d24
 cmp r5,r2
 bne fail
 // Device store keeps the serialized exactly-once path and its base update.
 ldr r6,=0x11223344
 ldr r5,=0xf0000004
.global post_device
post_device: str r6,[r5],#4
 ldr r0,=0xf0000008
 cmp r5,r0
 bne fail
 ldr r0,[r5,#-4]
 cmp r0,r6
 bne fail
 mov r11,#0
'''
    for name,base,status in [('translation',0x70000000,5),('permission',0x81010000,13),('alignment',0x80001d01,1)]:
        if name=='alignment':guest+=' mrc p15,0,r0,c1,c0,0\n orr r0,r0,#2\n mcr p15,0,r0,c1,c0,0\n'
        guest+=f''' ldr r5,=0x{base:08x}
 mov r4,r5
 mov r3,r5
 mov r2,#{status}
 mov r8,#100
 ldr r12,=post_after_{name}
.global post_fault_{name}
post_fault_{name}: str r6,[r5],#4
.global post_forbidden_{name}
post_forbidden_{name}: str r7,[r10,#48]
post_after_{name}:
 cmp r5,r4
 bne fail
'''
        if name=='alignment':guest+=' mrc p15,0,r0,c1,c0,0\n bic r0,r0,#2\n mcr p15,0,r0,c1,c0,0\n'
    guest+='''
 // An older failed load must cancel the post-indexed store AND base write.
 ldr r5,=0x80001d30
 mov r4,r5
 ldr r3,=0x70000000
 mov r2,#5
 mov r8,#100
 ldr r12,=post_after_load_fault
 ldr r6,[r3]
.global post_after_bad_load
post_after_bad_load: str r6,[r5],#4
post_after_load_fault:
 cmp r11,#4
 bne fail
 cmp r5,r4
 bne fail
 // Interrupt a real overlapping post-index stream at nonzero store credit.
 ldr r5,=0x80001d40
 mov r0,#0
 mov r1,#16
post_irq_clear: str r0,[r5],#4
 subs r1,r1,#1
 bne post_irq_clear
 ldr r5,=0x80001d40
 ldr r6,=0x11223344
 ldr r0,[r5]
 ldr r0,[r5,#32]
 mov r8,#101
 mrs r0,cpsr
 bic r0,r0,#0x80
 msr cpsr_c,r0
.global post_irq_begin
post_irq_begin:
 .rept 16
 str r6,[r5],#4
 .endr
.global post_irq_end
post_irq_end:
 b fail
after_post_irq:
 mov r8,#0
 mrs r0,cpsr
 orr r0,r0,#0x80
 msr cpsr_c,r0
 ldr r0,=0x80001e00
 ldr r1,[r0]
 cmp r5,r1
 bne fail
 ldr r0,=0x80001d40
post_irq_check:
 cmp r0,r5
 bhs post_irq_check_suffix
 ldr r1,[r0],#4
 cmp r1,r6
 bne fail
 b post_irq_check
post_irq_check_suffix:
 ldr r2,=0x80001d80
 cmp r0,r2
 bhs post_irq_check_done
 ldr r1,[r0],#4
 cmp r1,#0
 bne fail
 b post_irq_check_suffix
post_irq_check_done:
 b post_cases_done
 .ltorg
post_cases_done:
 ldr r1,=0x11111111
 ldr r2,=0x22222222
 ldr r3,=0x33333333
 ldr r4,=0x44444444
 mov r9,#1
 ldr r0,[r10]
 ldr r0,[r10,#32]
'''
    marker=' mov r11,#7\nsample_loop:'
    assert text.count(marker)==1
    text=text.replace(marker,guest+marker)
    text=text.replace('abort_handler:', 'abort_handler:\n cmp r8,#100\n beq post_abort_handler\n',1)
    text=text.replace('irq_handler:', 'irq_handler:\n cmp r8,#101\n beq post_irq_handler\n',1)
    text+='''
post_abort_handler:
 cmp r5,r4
 bne fail
 mrc p15,0,r0,c6,c0,0
 cmp r0,r3
 bne fail
 mrc p15,0,r0,c5,c0,0
 and r0,r0,#15
 cmp r0,r2
 bne fail
 add r11,r11,#1
 mov r8,#0
 movs pc,r12
post_irq_handler:
 ldr r0,=0x80001e00
.global post_irq_snapshot
post_irq_snapshot: str r5,[r0]
 ldr r12,=after_post_irq
 movs pc,r12
.ltorg
'''
    return text

def arguments(symbols,out):
    rows=[]
    for label,va,data,base,accept,credit in CASES:
        rows.append(''.join(f'{x:08x}' for x in [symbols[label],va,data,base,accept,credit]))
    p=out/'post-cases.hex';p.write_text('\n'.join(rows)+'\n')
    root=Path(__file__).resolve().parents[3]
    return ['+post_cases=/work/'+str(p.relative_to(root)),f'+post_count={len(rows)}']+[
        '+'+k+'='+format(symbols[k],'x') for k in ['post_irq_begin','post_irq_end','post_irq_snapshot']]
