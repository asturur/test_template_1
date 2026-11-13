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
 ldr r10,=0x80001000
 ldr r0,=0x80002000
 str r0,[r10,#4]
 ldr r1,=0x80003000
 str r1,[r0]
 ldr r2,=tx_callback
 str r2,[r1,#0x30]
 ldr r2,=rx_callback
 str r2,[r1,#0x2c]
 // Native polling leaf5033C134 reads this RTOS-running flag.
 mov r0,#1
 ldr r1,=0x800004a8
 str r0,[r1]
 // Native mask writes at00E enable the shared CTSI RX/TX sub-sources.
 mov r0,#0x18
 ldr r1,=0x5815000e
 strh r0,[r1]
 mov r0,r10
 ldr r4,=0x510e8be8
 mov lr,pc
 bx r4
 ldr r1,=0x581500ba
poll:
 ldrh r0,[r1]
 tst r0,#8
 beq poll
 // Authored IRQ envelope calls the original receive interrupt handler.
 ldr r0,=0x80004000
 str r10,[r0,#0x14]
 ldr r4,=0x510e8d58
 mov lr,pc
 bx r4
 ldr r1,=0x80005000
 ldr r0,[r1,#4]
 cmp r0,#3
 bne fail
 ldr r0,[r1,#8]
 ldr r2,=0x002b827e
 cmp r0,r2
 bne fail
 ldr r0,=0x50415353
 b finish
// Authored logical-channel callbacks, not replacements for driver/HAL code.
tx_callback:
 ldr r1,=0x80005000
 ldr r2,[r1]
 cmp r2,#3
 mvnhs r0,#0
 bxhs lr
 ldr r3,=bytes
 ldrb r0,[r3,r2]
 add r2,r2,#1
 str r2,[r1]
 bx lr
rx_callback:
 ldr r0,=0x80005000
 ldr r2,[r0,#4]
 cmp r2,#3
 bhs fail
 add r3,r0,#8
 strb r1,[r3,r2]
 add r2,r2,#1
 str r2,[r0,#4]
 bx lr
fail:
 ldr r0,=0xbadf00d
finish:
 ldr r1,=0xf0000000
 str r0,[r1]
park: b park
bytes: .byte 0x7e,0x82,0x2b
.align 2
