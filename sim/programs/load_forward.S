.include "sim/programs/common.inc"
.equ TABLE, RAM+0x4000
reset_entry:
 ldr sp, =RAM+0x20000
 ldr r4, =TABLE
 mov r0,#0
 mov r1,#4096
.global measure_init_target
.global measure_init_branch
measure_init_target:
1: str r0,[r4],#4
 subs r1,r1,#1
measure_init_branch:
 bne 1b
 ldr r4,=TABLE
 ldr r0,=0x00000c0e
 str r0,[r4]
 ldr r0,=0x80000c0e
 add r5,r4,#0x2000
 str r0,[r5]
 ldr r0,=0xf0000c02
 add r5,r4,#0x3c00
 str r0,[r5]
 mcr p15,0,r4,c2,c0,0
 mov r0,#1
 mcr p15,0,r0,c3,c0,0
 mrc p15,0,r0,c1,c0,0
 bic r0,r0,#2
 orr r0,r0,#5
 orr r0,r0,#0x1000
 mcr p15,0,r0,c1,c0,0
 nop
 nop
 ldr r4,=RAM+0x31000
 ldr r2,=0x10203040
 str r2,[r4]
 ldr r3,=0x55667788
 str r3,[r4,#4]
 add r0,r4,#4
 str r0,[r4,#8]
 mov r0,#3
 str r0,[r4,#12]
 mov r6,#16
load_loop:
 ldr r0,[r4]
 add r1,r0,#1
 ldr r5,=0x10203041
 cmp r1,r5
 bne fail_forward
 ldr r0,[r4]
 mov r1,r0,lsl #3
 ldr r5,=0x81018200
 cmp r1,r5
 bne fail_forward
 ldr r0,[r4,#12]
 mov r1,r2,lsl r0
 cmp r1,r5
 bne fail_forward
 ldr r0,[r4,#8]
 ldr r1,[r0]
 cmp r1,r3
 bne fail_forward
 ldr r0,[r4]
 str r0,[r4,#16]
 ldr r1,[r4,#16]
 cmp r1,r2
 bne fail_forward
 ldr r0,[r4]
 ldr r0,[r4,#4]
 add r1,r0,#1
 ldr r5,=0x55667789
 cmp r1,r5
 bne fail_forward
 ldr r0,[r4]
 cmp r2,r2
 movne r0,#255
 add r1,r0,#1
 ldr r5,=0x10203041
 cmp r1,r5
 bne fail_forward
 mov r0,#123
 cmp r2,r2
 ldrne r0,[r4]
 add r1,r0,#1
 cmp r1,#124
 bne fail_forward
 ldrb r0,[r4,#3]
 add r1,r0,#1
 cmp r1,#17
 bne fail_forward
 ldrsb r0,[r4,#4]
 add r1,r0,#1
 mvn r5,#118
 cmp r1,r5
 bne fail_forward
 ldrh r0,[r4,#2]
 add r1,r0,#1
 ldr r5,=0x1021
 cmp r1,r5
 bne fail_forward
 ldr r0,[r4,#1]
 add r1,r0,#1
 ldr r5,=0x40102031
 cmp r1,r5
 bne fail_forward
 subs r6,r6,#1
 bne load_loop
 b pass
fail_forward:
 mov r0,#0xd8
 b finish
.ltorg
