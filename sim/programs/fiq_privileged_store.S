.syntax unified
.cpu arm920t
.arm
.equ RAM,0x80000000
.equ TABLE,RAM+0x4000
.equ MAILBOX,0xf0000000
.section .vectors,"ax"
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
.section .text,"ax"
reset_entry:
 ldr r4,=TABLE
 mov r0,#0
 mov r1,#4096
1: str r0,[r4],#4
 subs r1,r1,#1
 bne 1b
 ldr r4,=TABLE
 ldr r0,=0x00000c02
 str r0,[r4]
 ldr r0,=0x80000c02
 str r0,[r4,#0x800]
 ldr r0,=0x8000043a  @ section, domain 1, privileged read/write, write-through
 ldr r5,=0x1660      @ first-level index 0x598
 str r0,[r4,r5]
 ldr r0,=0xf0000c02
 add r5,r4,#0x3c00
 str r0,[r5]
 mcr p15,0,r4,c2,c0,0
 mov r0,#5            @ domains 0 and 1 client
 mcr p15,0,r0,c3,c0,0
 mrc p15,0,r0,c1,c0,0
 orr r0,r0,#5
 mcr p15,0,r0,c1,c0,0
 nop
 nop
 mrs r0,cpsr
 bic r0,r0,#0x5f
 orr r0,r0,#0x10      @ user mode, FIQ unmasked
 msr cpsr_c,r0
2: b 2b
fiq_handler:
 ldr r8,=0x59800100
 mov r9,#0xa0
 strh r9,[r8]
 ldrh r10,[r8]
 cmp r10,r9
 bne fail
 ldr r0,=0x50415353
 b finish
fail:
 mov r0,#0xd1
finish:
 ldr r12,=MAILBOX
 str r0,[r12]
3: b 3b
.ltorg
