.syntax unified
.cpu arm920t
.arm
.section .vectors,"ax"
.global _start
_start: b start
.rept 6
 b fail
.endr
 b fiq_handler
.section .text,"ax"
start:
 msr cpsr_c,#0xd1
 ldr sp,=0x8001d000
 msr cpsr_c,#0xd3
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
 mov r0,#8
 ldr r1,=0x5815000e
 strh r0,[r1]
 ldr r1,=0x0c1201c8
 mov r0,#0x04000000
 str r0,[r1]
 msr cpsr_c,#0x93
 mov r0,r10
 ldr r4,=0x510e8be8
 mov lr,pc
 bx r4
 ldr r1,=0x80005000
poll:
 ldr r0,[r1,#4]
 cmp r0,#3
 bne poll
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

// Actual CPU FIQ vector; native driver retains FIFO/status/callback ownership.
fiq_handler:
 stmdb sp!,{r0-r7,lr}
 ldr r1,=0x0c1201d4
 ldr r0,[r1]
 cmp r0,#27
 bne fail
 ldr r0,=0x80004000
 ldr r1,=0x80001000
 str r1,[r0,#0x14]
 ldr r4,=0x510e8d58
 mov lr,pc
 bx r4
 ldmia sp!,{r0-r7,lr}
 subs pc,lr,#4
