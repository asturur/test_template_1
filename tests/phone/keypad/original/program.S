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
 ldr r9,=0x58150100
 ldr r10,=0xe0000000
 // Exact original dispatcher: op0 clears data, op2 makes outputs,
 // op3 makes inputs and op4 enables per-pin interrupt generation.
 ldr r1,=0xf373
 mov r2,#0
 bl configure
 ldr r1,=0xf300
 mov r2,#3
 bl configure
 mov r1,#0x73
 mov r2,#2
 bl configure
 ldr r1,=0xf300
 mov r2,#4
 bl configure
 mov r0,#32                    // public left softkey: D0/E0
 str r0,[r10]
 ldrh r0,[r9]
 tst r0,#4
 beq fail
 // Stock scan helper reads active-low logical E inputs.
 ldr r0,=0x80001000
 ldr r1,=0xf300
 call 0x5041aa0c
 cmp r0,#0x100
 bne fail
 // Original op5 masks E during the bidirectional scan and original
 // acknowledgement clears CTSI bits 2/3 and GENIO events independently.
 ldr r1,=0xf300
 mov r2,#5
 bl configure
 ldr r0,=0x80001000
 call 0x5041ac84
 ldrh r0,[r9]
 tst r0,#4
 bne fail
 mov r1,#0x73
 mov r2,#3
 bl configure
 mov r1,#0x100
 mov r2,#2
 bl configure
 ldr r0,=0x80001000
 mov r1,#0x73
 call 0x5041aa0c
 cmp r0,#1
 bne fail
 ldrh r0,[r9]
 tst r0,#4
 bne fail
 // Return to idle while masked, then re-enable with the key held.
 ldr r1,=0xf300
 mov r2,#3
 bl configure
 mov r1,#0x73
 mov r2,#2
 bl configure
 ldr r1,=0xf300
 mov r2,#4
 bl configure
 ldrh r0,[r9]
 tst r0,#4
 bne fail
 mov r0,#0
 str r0,[r10]
 mov r0,#32
 str r0,[r10]
 ldrh r0,[r9]
 tst r0,#4
 beq fail
 ldr r0,=0x80001000
 call 0x5041ac84
 mov r0,#0
 str r0,[r10]
 // NEM-4 GPIO30 keeps direction and data separate (ops0/1/2/3).
 ldr r1,=0xf300
 mov r2,#5
 bl configure
 mov r1,#0x80
 mov r2,#2
 bl configure
 mov r1,#0x80
 mov r2,#1
 bl configure
 mov r0,#0x200000             // public0 contacts GPIO30/E2
 str r0,[r10]
 ldr r0,=0x80001000
 mov r1,#0x1000
 call 0x5041aa0c
 cmp r0,#0
 bne fail
 mov r1,#0x80
 mov r2,#0
 bl configure
 ldr r0,=0x80001000
 mov r1,#0x1000
 call 0x5041aa0c
 cmp r0,#0x1000
 bne fail
 mov r0,#0
 str r0,[r10]
 // Original GENIO dispatcher maps rocker and music separately.
 ldr r1,=0x220000
 mov r2,#3
 bl configure
 ldr r1,=0x220000
 mov r2,#4
 bl configure
 mov r0,#1                    // public Up: GENIO1 -> CTSI21
 str r0,[r10]
 ldrh r0,[r9,#2]
 tst r0,#0x20
 beq fail
 ldr r0,=0x80001000
 call 0x5041ac84
 mov r0,#0
 str r0,[r10]
 mov r0,#0x2000000            // public Music: GENIO28 -> CTSI22
 str r0,[r10]
 ldrh r0,[r9,#2]
 tst r0,#0x40
 beq fail
 ldr r0,=0x80001000
 call 0x5041ac84
 ldrh r0,[r9,#2]
 tst r0,#0xee
 bne fail
 ldr r0,=0x50415353
 b finish
configure:
 ldr r0,=0x80001000
 ldr ip,=0x5041a3cc
 bx ip
fail:
 ldr r0,=0xfa110001
finish:
 ldr r1,=0xf0000000
 str r0,[r1]
 b .
.ltorg
