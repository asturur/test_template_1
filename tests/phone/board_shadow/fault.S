.syntax unified
.cpu arm920t
.arm
.global _start
_start:
.if MISSING
 ldr r0,=0x0c160000
 mov r1,#1
.else
 ldr r0,=0x0c120348
 mov r1,#2
.endif
 str r1,[r0]
1: b 1b
.ltorg
