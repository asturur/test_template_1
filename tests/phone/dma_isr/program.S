.syntax unified
.cpu arm920t
.arm
.section .vectors,"ax"
.global _start
_start: b reset
.rept 7
 b fail
.endr
.section .text,"ax"
.macro call address
 ldr ip,=\address
 mov lr,pc
 bx ip
.endm
reset:
 ldr sp,=0x8001f000
 // Synthetic objects: ISR wrapper r4, channel object r5 and callback vtable.
 ldr r4,=0x80001000
 ldr r5,=0x80001100
 mov r0,#0x64
 str r0,[r4]
 str r5,[r4,#0x14]
 mov r0,#1
 str r0,[r5]
 mov r0,#0
 str r0,[r5,#0x20]
 ldr r0,=0x80001200
 str r0,[r5,#0x30]
 ldr r1,=callback
 str r1,[r0,#8]
 // Case 0: completed channel has no remaining bytes; original ISR callbacks.
 mov r6,#0
 bl arm_case
 bl initial_copy
 bl idle
 mov r0,#1
 bl marker
 mov r0,r4
 call 0x5032ca14
 mov r0,#2
 bl marker
 // Case 1: the ISR ACKs, then starts the original next-chunk routine.
 mov r6,#16
 bl arm_case
 bl initial_copy
 bl idle
 mov r0,#3
 bl marker
 mov r0,r4
 call 0x5032ca14
 mov r0,#4
 bl marker
 bl idle
 mov r0,#5
 bl marker
 mov r0,r4
 call 0x5032ca14
 mov r0,#6
 bl marker
 ldr r0,=0x50415353
 b finish
arm_case:
 mov r0,#1
 str r0,[r4,#4]
 str r6,[r5,#0x2c]
 ldr r0,=0x0a000110
 str r0,[r5,#0x24]
 ldr r0,=0x0a000440
 str r0,[r5,#0x28]
 bx lr
initial_copy:
 push {lr}
 mov r0,#1
 mov r1,#0
 ldr r2,=0x0a000100
 ldr r3,=0x0a000400
 call 0x5032130c
 mov r0,#1
 ldr r1,=0x0a000100
 ldr r2,=0x0a000400
 mov r3,#16
 call 0x503213c4
 pop {pc}
idle:
 ldr r1,=0x58120348
 ldr r0,[r1]
 cmp r0,#0
 bne idle
 bx lr
marker:
 ldr r1,=0xe0000000
 str r0,[r1]
 bx lr
callback:
 // Called by original ISR via [channel+0x30]+8 with channel as r0.
 ldr r1,=0xe0000004
 str r0,[r1]
 bx lr
fail:
 ldr r0,=0xfa110001
finish:
 ldr r1,=0xf0000000
 str r0,[r1]
 b .
.ltorg
