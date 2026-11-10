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
 // The real firmware reports panics through these three words. Validate the
 // whole CPU/UPP path without turning an uninitialized read into valid RAM.
 ldr r0,=0x0c0047f0
 ldr r1,=0x65637845
 str r1,[r0]
 ldr r2,[r0]
 cmp r1,r2
 bne fail
 ldr r1,=0x6f697470
 str r1,[r0,#4]
 ldr r1,=0x00010003
 str r1,[r0,#8]
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
 // Exercise the actual UPP SIMIF and separate diagnostic card on the CPU bus.
 ldr r0,=0x0c150808
 mov r1,#1
 strh r1,[r0]
 ldr r0,=0x0c150800
 ldrh r2,[r0]
 cmp r2,#16
 bne fail
 ldr r0,=0x0c15080c
 ldrh r2,[r0]
 cmp r2,#0x3b
 bne fail
 ldrh r2,[r0]
 cmp r2,#0
 bne fail
 ldr r3,=0x0c150800
 mov r1,#16
 strh r1,[r3]
 mov r1,#0xa0
 strh r1,[r0]
 mov r1,#0xa4
 strh r1,[r0]
 mov r1,#0
 strh r1,[r0]
 strh r1,[r0]
 mov r1,#2
 strh r1,[r0]
 ldrh r2,[r3]
 cmp r2,#8
 bne fail
 mov r1,#8
 strh r1,[r3]
 ldrh r2,[r0]
 cmp r2,#0xa4
 bne fail
 mov r1,#0x3f
 strh r1,[r0]
 mov r1,#0
 strh r1,[r0]
 mov r1,#8
 strh r1,[r3]
 ldrh r2,[r0]
 cmp r2,#0x9f
 bne fail
 ldrh r2,[r0]
 cmp r2,#0x16
 bne fail
 // A real CPU-configured partial LCD DMA through the shared SDRAM arbiter.
 ldr r0,=0x0a000020
 ldr r1,=0x01230abc
 str r1,[r0]
 ldr r0,=0x0c120354
 ldr r1,=0x0a000020
 str r1,[r0]
 ldr r0,=0x0c120360
 ldr r1,=0x10121208
 str r1,[r0]
 ldr r0,=0x0c12036c
 mov r1,#0
 str r1,[r0]
 ldr r0,=0x0c120348
 mov r1,#2
 str r1,[r0]
 ldr r0,=0x0c120110
4: ldr r1,[r0]
 tst r1,#0x80
 beq 4b
 ldr r0,=0x0c12010c
 mov r1,#0x80
 str r1,[r0]
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
 // The temporary 0x0d CAM must reject only its own exhausted write.
 // Keep interrupt handlers from changing loop registers during this check.
 mrs r0,cpsr
 orr r0,r0,#0xc0
 msr cpsr_c,r0
 ldr r0,=0x0d000000
 mov r1,#64
local_fill:
 str r1,[r0],#4
 subs r1,r1,#1
 bne local_fill
 str r1,[r0]
 cmp r7,#2
 bne fail
 ldr r0,=0x0d000000
 ldr r2,[r0]
 cmp r2,#64
 bne fail
 // A full temporary table must not prevent a real timer-register write.
 ldr r0,=0x0c120a24
 mov r1,#0
 str r1,[r0]
 ldr r0,=0x0c120a30
 mov r1,#42
 str r1,[r0]
 ldr r2,[r0]
 cmp r2,r1
 bne fail
 // Invalid LCD header must fault without reaching display or transport state.
 ldr r0,=0x0c121204
 mov r1,#1
 str r1,[r0]
 ldr r0,=0x0c121200
 ldr r1,=0xdeadbeef
 str r1,[r0]
 cmp r7,#3
 bne fail
 // Exercise keypad status through actual CPU/UPP transactions. The test
 // harness mailbox at SDRAM+104 drives public key bits, not MMIO state.
 mrs r0,cpsr
 orr r0,r0,#0xc0
 msr cpsr_c,r0
 ldr r0,=0x0c120108
 mov r1,#0x02000000
 str r1,[r0]
 ldr r8,=0x0a000104
 ldr r9,=0x0c150100
 ldr r10,=0x0c120114
 mov r1,#32
 str r1,[r8]                 // left softkey (matrix event)
 ldr r2,[r9]
 tst r2,#4
 beq fail
 ldr r2,[r10]
 cmp r2,#26
 bne fail
 mov r1,#4
 strb r1,[r9]
 ldr r2,[r9]
 tst r2,#4
 bne fail
 ldr r2,[r10]
 cmp r2,#0
 bne fail
 mov r1,#0
 str r1,[r8]
 mov r1,#16
 str r1,[r8]                 // OK (direct event, upper status byte)
 ldr r2,[r9]
 tst r2,#0x00040000
 beq fail
 ldr r2,[r10]
 cmp r2,#26
 bne fail
 mov r1,#4
 strb r1,[r9,#2]
 ldr r2,[r9]
 tst r2,#0x00040000
 bne fail
 ldr r2,[r10]
 cmp r2,#0
 bne fail
 mov r1,#0
 str r1,[r8]
 // Valid commands reach the panel through the registered command queue.
 ldr r0,=0x0c121200
 ldr r1,=0x09200000
 str r1,[r0]
 ldr r0,=0x0c121208
 mov r1,#0xaf
 str r1,[r0]
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
 add r7,r7,#1
 subs pc,lr,#4
fail: mov r0,#1
finish:
 ldr r1,=0x0a000100
 str r0,[r1]
3: b 3b
.ltorg
