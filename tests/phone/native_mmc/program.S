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
 ldr r8,=0x80001000 // Original MMC controller object.
 ldr r9,=0x80002000 // Original context, request and state-machine records.
 str r9,[r8,#0x56c]
 mov r0,#0
 str r0,[r9,#0x58]
 str r0,[r9,#0x174]
 mov r0,#3
 str r0,[r9,#0x17c] // Original state3 waits for the first R2 word.
 mov r0,#2
 str r0,[r9,#0x60]  // Request command = CMD2.
 mov r0,#4
 str r0,[r9,#0x88]  // Original response kind = R2.
 mov r0,#10
 str r0,[r8,#0x8a8] // Kernel wait registered for CmdIdle OR CmdRdy.
 ldr r10,=0x58120600
 mov r0,#2
 str r0,[r10,#0x1c]
 mov r0,#0
 str r0,[r10,#0x20]
 mov r0,#13
 str r0,[r10,#4]
 ldr r11,=0x58120100
 mov r0,#0x01800000
 str r0,[r11,#8]
 // Bounded late IRQ delivery: both events coexist with the old host.
 // Interrupt envelope is authored; original MMC event/FSM code is unchanged.
 mov r0,#250
1: subs r0,r0,#1
 bne 1b
 ldr r0,[r11,#20]
 cmp r0,#24 // source23 CmdIdle wins on the old host.
 moveq r1,#2
 beq 2f
 cmp r0,#25 // source24 CmdRdy must arrive before CmdIdle for R2.
 bne fail
 mov r1,#8
2: mov r0,r8
 ldr r12,=0x503f5574 // Original event handling/status extraction.
 mov lr,pc
 bx r12
 mov r0,r8
 ldr r12,=0x503f4614 // Original unmodified EPBUS transfer state machine.
 mov lr,pc
 bx r12
 ldr r1,=0xf0000000
 str r0,[r1,#4] // Baseline must report native8000, corrected host returns0.
 cmp r0,#0
 bne fail
 ldr r0,[r9,#0xa4] // Request response offset48, first CID word.
 ldr r1,=0x33221100
 cmp r0,r1
 bne fail
 ldr r0,[r9,#0xa8]
 ldr r1,=0x77665544
 cmp r0,r1
 bne fail
 ldr r0,[r9,#0xac]
 ldr r1,=0xbbaa9988
 cmp r0,r1
 bne fail
 ldr r0,[r9,#0xb0]
 ldr r1,=0x91eeddcc
 cmp r0,r1
 bne fail
 ldr r0,[r9,#0x174]
 cmn r0,#1
 bne fail
 ldr r0,=0x50415353
 b finish
fail:
 ldr r0,=0xbad00001
finish:
 ldr r1,=0xf0000000
 str r0,[r1]
 b finish
// Explicit kernel scheduler/interrupt boundary spies. No MMC code substitutes.
.global kernel_return
kernel_return:
 mov r0,#0
 bx lr
