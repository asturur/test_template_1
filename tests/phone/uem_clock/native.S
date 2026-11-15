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
 ldr r5,=0x80001000
 ldr r0,=0x80002000
 str r0,[r5,#8]
 ldr r1,=0x80002400
 str r1,[r0]
 ldr r2,=0x50381f7c
 str r2,[r1,#0x10]
 ldr r8,=0x80004000
 ldr r8,[r8]
 // Original ecust calibration reader -> original CBUS client -> native HAL.
 mov r0,r5
 mov r1,#4
 mov r2,#8
 ldr r3,=0x5034f5f0
 mov lr,pc
 bx r3
 cmp r0,r8
 bne fail
 mov r7,r0
 // Original double-seconds-read coherence loop and binary time structure.
 ldr r4,=0x80003000
 mov r0,r4
 mov r1,r5
 ldr r3,=0x5034f374
 mov lr,pc
 bx r3
 ldr r0,[r4]
 cmp r8,#0
 moveq r1,#0
 movne r1,#56
 cmp r0,r1
 bne fail
 ldr r0,[r4,#4]
 cmp r8,#0
 moveq r1,#0
 movne r1,#34
 cmp r0,r1
 bne fail
 ldr r0,[r4,#8]
 cmp r8,#0
 moveq r1,#0
 movne r1,#12
 cmp r0,r1
 bne fail
 ldr r0,[r4,#12]
 cmp r0,#0
 bne fail
 // Execute the original init validity decision and epilogue unchanged.
 // Its constructor/allocation is outside this focused fixture.
 mov r6,#0
 sub sp,sp,#64
 ldr r0,=after_validity
 str r0,[sp,#60]
 ldr r3,=0x5034e104
 bx r3
after_validity:
 ldr r0,=0x80001000
 ldr r0,[r0,#0x3c]
 ldr r1,=0x80004000
 ldr r1,[r1]
 cmp r0,r1
 bne fail
 ldr r0,=0x50415353
 b finish
fail:
 ldr r0,=0xbadf00d
finish:
 ldr r1,=0xf0000000
 str r0,[r1]
park: b park
