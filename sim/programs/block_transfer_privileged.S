.equ CUSTOM_ABORT,1
.include "sim/programs/common.inc"
.equ TABLE,RAM+0x4000
.equ L2,RAM+0x8000
.equ STACK_VA,0x80422350
reset_entry:
 ldr r4,=TABLE
 mov r0,#0
 mov r2,#4096
1: str r0,[r4],#4
 subs r2,r2,#1
 bne 1b
 ldr r4,=TABLE
 ldr r0,=0x00000c02
 str r0,[r4]
 ldr r0,=0x80000402
 ldr r5,=0x2000
 str r0,[r4,r5]
 ldr r0,=L2+0x21
 ldr r5,=0x2010
 str r0,[r4,r5]
 ldr r0,=0x80022552
 ldr r5,=L2+0x88
 str r0,[r5]
 ldr r0,=0xf0000402
 ldr r5,=0x3c00
 str r0,[r4,r5]
 mcr p15,0,r4,c2,c0,0
 mov r0,#5
 mcr p15,0,r0,c3,c0,0
 mrc p15,0,r0,c1,c0,0
 bic r0,r0,#0x300
 orr r0,r0,#1
 mcr p15,0,r0,c1,c0,0
 nop
 nop
#if defined(EXPLICIT_USER_LOAD) || defined(EXPLICIT_USER_STORE)
 ldr r1,=STACK_VA
 ldr r2,=0x0115b5c0
fault_instruction:
#ifdef EXPLICIT_USER_STORE
 strt r2,[r1],#4
#else
 ldrt r2,[r1],#4
#endif
 b unexpected
#elif defined(BLOCK_SINGLE_STORE)
 ldr r1,=STACK_VA
 ldr r2,=0x0115b5c0
fault_instruction:
 stmia r1!,{r2}
 ldr r3,=STACK_VA+4
 cmp r1,r3
 bne unexpected
 ldr r1,=STACK_VA
 ldr r3,[r1]
 cmp r2,r3
 bne unexpected
#else
 ldr sp,=STACK_VA+4
 ldr r1,=0x0115b5c0
 stmdb sp!,{r1}
 mrs r1,cpsr
 bic r1,r1,#0x80
 msr cpsr_fc,r1
fault_instruction:
 ldmia sp!,{r1}
 ldr r2,=0x0115b5c0
 cmp r1,r2
 bne unexpected
 ldr r2,=STACK_VA+4
 cmp sp,r2
 bne unexpected
#endif
 b pass
unexpected:
 mov r0,#0xd2
 b finish
data_abort:
 mrc p15,0,r2,c6,c0,0
 ldr r3,=STACK_VA
 cmp r2,r3
 bne unexpected
 mrc p15,0,r2,c5,c0,0
 and r2,r2,#0xff
 cmp r2,#0x1f
 bne unexpected
 ldr r3,=fault_instruction+8
 cmp lr,r3
 bne unexpected
#if defined(EXPLICIT_USER_LOAD) || defined(EXPLICIT_USER_STORE)
 b pass
#else
 mov r0,#0xd1
 b finish
#endif
