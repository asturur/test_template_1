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
 // Unmodified original NEM-4 setup and start: 16-byte SDRAM copy.
 mov r0,#0
 mov r1,#0
 ldr r2,=0x0a000100
 ldr r3,=0x0a000400
 call 0x5032130c
 mov r0,#0
 ldr r1,=0x0a000100
 ldr r2,=0x0a000400
 mov r3,#16
 call 0x503213c4
 ldr r4,=0x58120308
 bl idle
 mov r0,#1
 bl checked
 // Original type-5 MMC-style transmit, test-only FIFO endpoint.
 mov r0,#1
 mov r1,#5
 call 0x50321444
 mov r0,#1
 mov r1,#5
 ldr r2,=0x0a000100
 mov r3,#16
 call 0x50321568
 ldr r4,=0x58120348
 bl idle
 mov r0,#2
 bl checked
 // Original type-5 receive, test-only FIFO endpoint.
 mov r0,#2
 mov r1,#5
 call 0x503215e8
 mov r0,#2
 mov r1,#5
 ldr r2,=0x0a000440
 mov r3,#16
 call 0x5032170c
 ldr r4,=0x58120388
 bl idle
 mov r0,#3
 bl checked
 // The original setup chooses a 16-bit source inside on-chip RAM.
 mov r0,#3
 mov r1,#0
 ldr r2,=0x0c004100
 ldr r3,=0x0a000480
 call 0x5032130c
 mov r0,#3
 ldr r1,=0x0c004100
 ldr r2,=0x0a000480
 mov r3,#16
 call 0x503213c4
 ldr r4,=0x581203c8
 bl idle
 mov r0,#4
 bl checked
 ldr r0,=0x50415353
 b finish
idle:
 ldr r0,[r4]
 cmp r0,#0
 bne idle
 bx lr
checked:
 push {lr}
 ldr r1,=0xe0000000
 str r0,[r1]
 // Original stop waits for idle and disables/acknowledges this channel.
 sub r0,r0,#1
 call 0x503212c0
 pop {pc}
fail:
 ldr r0,=0xfa110001
finish:
 ldr r1,=0xf0000000
 str r0,[r1]
 b .
.ltorg
