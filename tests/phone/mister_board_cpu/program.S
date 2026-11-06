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
 // Reach the separate UEM and audio-DSP models through the UPP bus.
 ldr r0,=0x0c150420
 mov r1,#7
 strh r1,[r0]
 mov r1,#0x2a
 strh r1,[r0,#2]
 mov r1,#8
 strh r1,[r0,#6]
 mov r1,#7
 strh r1,[r0]
 ldr r1,=0x12a
 strh r1,[r0,#2]
 ldrh r2,[r0,#6]
 cmp r2,#8
 bne fail
 ldr r0,=0x0c14b004
 mov r1,#0x500
 str r1,[r0]
 ldr r2,[r0]
 cmp r1,r2
 bne fail
 ldr r0,=0x0c1003e8
 mov r1,#2
 str r1,[r0]
 ldr r2,[r0]
 cmp r1,r2
 bne fail
 // Execute a tiny routine from both modeled writable on-chip regions.
 ldr r0,=0x0c004748
 ldr r1,=0xe3a0302a
 str r1,[r0]
 ldr r1,=0xe12fff1e
 str r1,[r0,#4]
 adr lr,scratch_return
 bx r0
scratch_return:
 cmp r3,#42
 bne fail
 ldr r0,=0x0c030220
 ldr r1,=0xe3a03019
 str r1,[r0]
 ldr r1,=0xe12fff1e
 str r1,[r0,#4]
 adr lr,upload_return
 bx r0
upload_return:
 cmp r3,#25
 bne fail
 ldr r0,=0x0c000001
 adr lr,asic_return
 bx r0
asic_return:
 ldr r0,=0x08000000
 ldr r2,[r0]
 cmp r7,#1
 bne fail
 ldr r0,=0x50415353
 b finish
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
fail: mov r0,#1
finish:
 ldr r1,=0x0a000100
 str r0,[r1]
3: b 3b
.ltorg
