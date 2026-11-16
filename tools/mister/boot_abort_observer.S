.syntax unified
.cpu arm920t
.arm
.section .text,"ax"
.global data_entry,prefetch_entry
data_entry:
 tst lr,#0x50000000
#ifndef FIRST_ABORT
 bne 0x608
#else
 nop
#endif
 mov r2,#1
 b emit
prefetch_entry:
 tst lr,#0x50000000
#ifndef FIRST_ABORT
 bne 0x5f8
#else
 nop
#endif
 mov r2,#2
 b emit
emit:
 mrc p15,0,r0,c1,c0,0
 tst r0,#1
 ldreq r0,=0x0c0047f0
 ldrne r0,=0x580047f0
 str lr,[r0]
 mrc p15,0,r1,c6,c0,0
 str r1,[r0,#4]
 mrc p15,0,r1,c5,c0,0
 orr r1,r1,r2,lsl #16
 mrs r3,spsr
 orr r1,r1,r3,lsl #24
 str r1,[r0,#8]
 tst lr,#0x50000000
 b 0x60c
.ltorg
