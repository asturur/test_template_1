.syntax unified
.cpu arm920t
.arm
.text
 ldr r0,=hybrid
 mov r2,#48
 mov r3,#0
 mov r4,#0
next_mode:
 mov r1,r0
 tst r2,#8
 orrne r1,r1,#1
 cmp r3,#1
 bl veneer
 subs r2,r2,#1
 bne next_mode
 cmp r4,#24
 bne fail
 ldr r0,=0x50415353
 b finish

veneer:
.global observed_bx
observed_bx:
 bx r1

.balign 4
hybrid:
 // ARM mode sees a condition-failed EQ instruction and the ADD below.
 // Thumb mode sees BX LR at the same canonical address and returns.
 .word 0x01a04770
 add r4,r4,#1
 bx lr

fail:
 ldr r0,=0x4641494c
finish:
 ldr r1,=0xf0000000
 str r0,[r1]
 b .
.ltorg
