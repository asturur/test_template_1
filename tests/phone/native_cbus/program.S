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
 ldr sp,=0x8001f000
 // Original CBUS low-level write, logical UEM register27 -> wire register3B.
 // No guest instruction is substituted. The native HAL helpers run as well.
 sub sp,sp,#8
 mov r0,#0
 str r0,[sp]
 ldr r0,=0x1234
 str r0,[sp,#4]
 ldr r0,=0x80001000
 mov r1,#1
 mov r2,#27
 mov r3,#16
 ldr r4,=0x503822bc
 mov lr,pc
 bx r4
 add sp,sp,#8
 cmp r0,#0
 bne fail
 ldr r0,=0x50415353
 b finish
fail:
 ldr r0,=0xbadf00d
finish:
 ldr r1,=0xf0000000
 str r0,[r1]
park: b park
