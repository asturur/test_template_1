.syntax unified
.cpu arm920t
.arm
.equ RAM, 0x80000000
.equ MAILBOX, 0xf0000000
.section .vectors, "ax"
.global _start
_start:
 b reset_entry
 b fail
 b fail
 b fail
 b fail
 b fail
 b fail
 b fiq_handler
.section .text, "ax"
reset_entry:
 ldr r1, =RAM+0x1000
 ldr r2, =0x12345678
 mov r3, #0x77
 mov r6, #0
 mov r7, #0
 mrs r0, cpsr
 bic r0, r0, #0x40
 msr cpsr_c, r0
 swp r3, r2, [r1]
 mov r9, #200
1: cmp r6, #1
 beq 2f
 subs r9, r9, #1
 bne 1b
 mov r0, #0xd6
 b finish
2: cmp r7, #0
 bne fail
 cmp r3, #0
 bne fail
 ldr r0, =0x50415353
 b finish
fiq_handler:
 ldr r4, [r1]
 cmp r4, r2
 movne r7, #1
 cmp r3, #0
 movne r7, #2
 add r6, r6, #1
 subs pc, lr, #4
fail:
 mov r0, #0xd7
finish:
 ldr r12, =MAILBOX
 str r0, [r12]
3: b 3b
.ltorg
