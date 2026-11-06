.syntax unified
.cpu arm920t
.arm
.global _start
_start:
.if ASIC
 ldr r0,=0x0c000001
 mov r3,#42
.else
.if UPLOAD
 ldr r0,=0x0c030220
.else
 ldr r0,=0x0c004748
.endif
 ldr r1,=0xe3a0302a
 str r1,[r0]
 ldr r1,=0xe12fff1e
 str r1,[r0,#4]
.endif
 adr lr,returned
 bx r0
returned:
 cmp r3,#42
 bne fail
.global good
good: b good
fail: b fail
.balign 512
.ltorg
