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
 mov r0,#1
 ldr r1,=0x800004a8
 str r0,[r1]
 // Fixture cache storage used by the real CBUS field-cache helper.
 ldr r0,=0x80008000
 ldr r1,=0x80007050
 str r0,[r1]
 // Original CBUS writer/table: begin in the native clock-stop profile.
 mov r2,#15
 mov r5,#0xf0
 bl cbus_write
 mov r2,#16
 mov r5,#0
 bl cbus_write
 ldr r1,=0x0c1201c8
 mov r0,#0x04000000
 str r0,[r1]
 msr cpsr_c,#0x93
 // Original EUART RX-start initialization, including flush/masks.
 ldr r4,=0x510e876c
 mov lr,pc
 bx r4
 // Match power-up ordering: RX listening first, then release both clock controls.
 ldr r1,=0x8000500c
 ldr r0,[r1]
 cmp r0,#0
 bne fail
 mov r2,#15
 mov r5,#0
 bl cbus_write
 mov r2,#16
 mov r5,#0x20
 bl cbus_write
 mov r0,#28
 bl await_rx
 ldr r0,=link_ack
 mov r1,#14
 bl send
 // Native packet constructor's checksummed diagnostic42 fragment.
 ldr r0,=diagnostic
 mov r1,#22
 bl send
 mov r0,#62
 bl await_rx
 ldr r0,=0x80006000
 ldrb r1,[r0,#51]
 cmp r1,#0x8b
 bne fail
 ldrb r1,[r0,#56]
 cmp r1,#0
 bne fail
 ldrb r1,[r0,#57]
 cmp r1,#0
 bne fail
 ldr r0,=0x50415353
 b finish
cbus_write:
 stmdb sp!,{lr}
 sub sp,sp,#8
 mov r0,#0
 str r0,[sp]
 str r5,[sp,#4]
 ldr r0,=0x80007000
 mov r1,#1
 mov r3,#8
 ldr r4,=0x503822bc
 mov lr,pc
 bx r4
 add sp,sp,#8
 cmp r0,#0
 bne fail
 ldmia sp!,{pc}
send:
 stmdb sp!,{lr}
 ldr r2,=0x80005000
 str r0,[r2]
 str r1,[r2,#4]
 mov r0,#0
 str r0,[r2,#8]
 mov r0,r10
 ldr r4,=0x510e88c8
 mov lr,pc
 bx r4
 mov r0,r10
 ldr r4,=0x510e89cc
 mov lr,pc
 bx r4
 ldmia sp!,{pc}
await_rx:
 ldr r1,=0x8000500c
1: ldr r2,[r1]
 cmp r2,r0
 blo 1b
 bx lr
tx_callback:
 ldr r1,=0x80005000
 ldr r2,[r1,#8]
 ldr r3,[r1,#4]
 cmp r2,r3
 mvnhs r0,#0
 bxhs lr
 ldr r3,[r1]
 ldrb r0,[r3,r2]
 add r2,r2,#1
 str r2,[r1,#8]
 bx lr
rx_callback:
 ldr r0,=0x80005000
 ldr r2,[r0,#12]
 cmp r2,#100
 bhs fail
 ldr r3,=0x80006000
 strb r1,[r3,r2]
 add r2,r2,#1
 str r2,[r0,#12]
 bx lr
fail:
 ldr r0,=0xbadf00d
finish:
 ldr r1,=0xf0000000
 str r0,[r1]
park: b park
link_ack: .incbin "build/sim/unit-native-adsp-boot/link-ack.bin"
diagnostic: .incbin "build/sim/unit-native-adsp-boot/diagnostic.bin"
.align 2
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
