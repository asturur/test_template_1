.syntax unified
.cpu arm920t
.arm
.section .vectors,"ax"
.global _start
_start: b reset_entry
 b fail
 b fail
 b fail
 b data_abort_handler
 b fail
 b irq_handler
 b fiq_handler
.section .text,"ax"
reset_entry:
 mov r5,#0
 mov r6,#0
 mov r7,#0
 ldr r0,=0x0c120108
 mov r1,#2
 str r1,[r0]
 ldr r0,=0x0c120a30
 mov r1,#30
 str r1,[r0]
 ldr r0,=0x0c120a24
 mov r1,#1
 str r1,[r0]
 mrs r0,cpsr
 bic r0,r0,#0x80
 msr cpsr_c,r0
1: cmp r5,#1
 bne 1b
 ldr r0,=0x0c1201c8
 mov r1,#8
 str r1,[r0]
 ldr r0,=0x0c120a64
 mov r1,#2
 str r1,[r0]
 mrs r0,cpsr
 bic r0,r0,#0x40
 msr cpsr_c,r0
2: cmp r6,#1
 bne 2b
 ldr r1,=0x0de00000
 mov r2,#65
 strb r2,[r1]
 mrs r0,cpsr
 orr r0,r0,#0xc0
 msr cpsr_c,r0
.global good
good: b good
irq_handler:
 ldr r0,=0x0c12010c
 mov r1,#2
 str r1,[r0]
 mov r5,#1
 subs pc,lr,#4
fiq_handler:
 ldr r8,=0x0c1201cc
 mov r9,#8
 str r9,[r8]
 ldr r8,=0x0c120a68
 mov r9,#0
 str r9,[r8]
 mov r6,#1
 subs pc,lr,#4
data_abort_handler:
 mov r7,#1
 subs pc,lr,#4
fail:
 mrs r0,cpsr
 orr r0,r0,#0xc0
 msr cpsr_c,r0
 b fail
.ltorg
