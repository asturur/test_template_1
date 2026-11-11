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
.macro put base, offset, value
 ldr r3,=\value
 str r3,[\base,#\offset]
.endm
start:
 ldr r8,=0x0c120600
 ldr r9,=0x0c120300
 ldr r10,=0x0c120100
 mov r12,#1
 // CMD0, then retry CMD1 while the retained mounted image is admitted.
 mov r0,#0
 mov r1,#0
 mov r2,#1
 bl command
 mov r7,#32
identify:
 mov r0,#1
 ldr r1,=0x00ff8000
 mov r2,#0x49
 bl command
 tst r4,#0x40
 bne retry
 ldr r4,[r8,#0x20]
 tst r4,#0x80000000
 bne identified
retry:
 subs r7,r7,#1
 bne identify
 b fail
identified:
 mov r12,#2
 mov r0,#2
 mov r1,#0
 mov r2,#13
 bl command
 tst r4,#0x42
 bne fail
 // Original CID response is four big-endian words, preserved byte-for-byte.
 ldr r4,[r8,#0x20]
 ldr r3,=0x00112233
 cmp r4,r3
 bne fail
 ldr r4,[r8,#0x20]
 ldr r3,=0x44556677
 cmp r4,r3
 bne fail
 ldr r4,[r8,#0x20]
 ldr r3,=0x8899aabb
 cmp r4,r3
 bne fail
 ldr r4,[r8,#0x20]
 ldr r3,=0xccddee91
 cmp r4,r3
 bne fail
 mov r0,#3
 mov r1,#0x10000
 mov r2,#5
 bl command
 bl response_ok
 mov r0,#7
 mov r1,#0x10000
 mov r2,#5
 bl command
 bl response_ok
 mov r12,#3
 mov r0,#16
 mov r1,#5
 mov r2,#5
 bl command
 bl response_ok
 put r8,8,5
 mov r0,#17
 mov r1,#0
 mov r2,#33
 bl command
 bl response_ok
 // Selector 2, fixed byte FIFO -> incrementing 32-bit RAM. EPBUS rounds5 to8.
 ldr r0,=0x0c120064
 put r0,4,15
 put r0,0,2
 put r9,4,1
 put r9,0x14,0x10120624
 put r9,0x18,0
 put r9,0x1c,8
 put r9,0x20,0x0a000200
 put r9,0x24,1
 put r9,0x28,32
 put r9,0x2c,7
 put r9,8,3
wait_dma:
 ldr r4,[r9,#8]
 cmp r4,#0
 bne wait_dma
 ldr r0,=0x0a000200
 ldr r4,[r0]
 ldr r3,=0x02ddb893
 cmp r4,r3
 bne fail
 ldr r4,[r0,#4]
 cmp r4,#0x27
 bne fail
 ldr r4,[r0,#8]
 ldr r3,=0xa5a5a5a5
 cmp r4,r3
 bne fail
 put r10,8,0x40
 ldr r4,[r10,#20]
 cmp r4,#7
 bne fail
 put r9,4,0
 ldr r4,[r10,#20]
 cmp r4,#0
 bne fail
 mov r12,#4
 // Odd-length PIO read from a different backed sector and zero tail padding.
 mov r0,#16
 mov r1,#3
 mov r2,#5
 bl command
 bl response_ok
 put r8,8,3
 mov r0,#17
 mov r1,#512
 mov r2,#33
 bl command
 bl response_ok
wait_fifo:
 ldrb r4,[r8,#0x24]
 cmp r4,#0
 beq wait_fifo
 cmp r4,#0xa4
 bne fail
 // Byte accesses wait at the real FIFO endpoint; no test-side data injection.
 ldrb r4,[r8,#0x24]
 cmp r4,#0xc9
 bne fail
 ldrb r4,[r8,#0x24]
 cmp r4,#0xee
 bne fail
 ldrb r4,[r8,#0x24]
 cmp r4,#0
 bne fail
data_idle:
 ldr r4,[r8,#0x18]
 tst r4,#4
 bne data_idle
 mov r12,#5
 // Verify evidenced idle/response IRQs; source22 is deliberately not asserted.
 put r10,8,0x01a00000
 ldr r4,[r10,#20]
 cmp r4,#22
 bne fail
 put r10,12,0x00200000
 ldr r4,[r10,#20]
 cmp r4,#24
 bne fail
 put r10,12,0x01800000
 mov r12,#6
 // Read-only production media rejects writes with R1 WP_VIOLATION.
 mov r0,#24
 mov r1,#0
 mov r2,#5
 bl command
 ldr r4,[r8,#0x20]
 tst r4,#0x04000000
 beq fail
 ldr r0,=0x0a000100
 put r0,0,0x50415353
park: b park

// r0 command, r1 argument, r2 control. Returns status in r4.
command:
 str r0,[r8,#0x1c]
 str r1,[r8,#0x20]
 str r2,[r8,#4]
command_wait:
 ldr r4,[r8,#0x18]
 tst r4,#8
 bne command_wait
 bx lr
response_ok:
 tst r4,#0x42
 bne fail
 ldr r4,[r8,#0x20]
 ldr r3,=0xfdffa020
 tst r4,r3
 bne fail
 bx lr
fail:
 ldr r0,=0x0a000100
 str r12,[r0,#8]
 put r0,4,0xbadf00d
 b fail
