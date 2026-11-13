.syntax unified
.cpu arm920t
.arm
.section .vectors,"ax"
.global _start
_start: b start
.rept 7
 b fail
.endr
.section .text,"ax"
start:
 msr cpsr_c,#0xd3
 ldr sp,=0x8001f000
 mov r0,#1
 ldr r1,=0x800004a8
 str r0,[r1]
 // Reproduce the actual board: one sync byte queued, no DSP RX response.
 mov r0,#0
 ldr r1,=0x5815055a
 strh r0,[r1]
 mov r0,#0x5500
 ldr r1,=0x58150554
 strh r0,[r1]
 // Unmodified native drain/stop routine; includes its real HAL and poll leaves.
 ldr r4,=0x510e89cc
 mov lr,pc
 bx r4
 ldr r0,=0x50415353
 b finish
fail:
 ldr r0,=0xbadf00d
finish:
 ldr r1,=0xf0000000
 str r0,[r1]
park: b park
