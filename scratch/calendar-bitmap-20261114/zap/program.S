.syntax unified
.arm
.global _start
_start: b start
b fail
b fail
b fail
b fail
b fail
b fail
b fail
start:
    ldr sp,=0x80008000
    ldr r0,=0x80002000
    mov r1,#176
    str r1,[r0,#0x1c]
    mov r1,#208
    str r1,[r0,#0x20]
    mov r1,#8
    str r1,[r0,#0x2c]
    mov r1,#1
    str r1,[r0,#0x30]
    mov r1,#0
    str r1,[r0,#0x38]
    ldr r1,=0x80004000
    ldr r2,=0x80003000
    mov r3,#0
    str r3,[r2]
    str r3,[r2,#4]
    ldr r3,=0x80005000
    str r3,[sp,#12]
    mov r3,#176
    adr lr,fail
    ldr r12,=0x505598a5
    bx r12
fail:
    ldr r1,=0xf0000000
    ldr r0,=0xbad00001
    str r0,[r1]
    b fail
