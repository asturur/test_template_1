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
 orr r0,r0,#5
 orr r0,r0,#0x1000
 mcr p15,0,r0,c1,c0,0
 nop
 nop

 ldr sp,=RAM+0x20000
 mov r5,#0
 mov r6,#32
arm_loop:
 bl arm_outer
 subs r6,r6,#1
 bne arm_loop
 mov r7,#12
 bl recursive
 adr r0,thumb_entry+1
 adr lr,after_thumb
 bx r0
arm_outer:
 str lr,[sp,#-4]!
 bl arm_inner
 ldr lr,[sp],#4
 bx lr
arm_inner:
 cmp r5,r5
 movne pc,lr
 add r5,r5,#1
 mov pc,pc
 b fail
 mov pc,lr
recursive:
 str lr,[sp,#-4]!
 add r5,r5,#1
 subs r7,r7,#1
 blpl recursive
 ldr lr,[sp],#4
 mov pc,lr
fail:
 mov r0,#0x79
 b finish
.align 2
.thumb
.thumb_func
thumb_entry:
 push {lr}
 movs r6,#16
thumb_loop:
 bl thumb_outer
 subs r6,#1
 bne thumb_loop
 pop {r0}
 bx r0
.thumb_func
thumb_outer:
 push {lr}
 bl thumb_inner
 pop {r0}
 bx r0
.thumb_func
thumb_inner:
 adds r5,#2
 mov pc,lr
.align 2
.arm
after_thumb:
 cmp r5,#77
 bne fail
 b pass
.ltorg
