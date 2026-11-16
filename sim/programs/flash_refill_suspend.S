.syntax unified
.cpu arm920t
.arm
.global _start
_start: b start
 b fail
 b fail
 b fail
 b fail
 b fail
 b fail
 b fail
start:
 ldr sp,=0x0a03f000
 ldr r4,=0x0a004000
 ldr r0,=0x00000c0e
 str r0,[r4]
 ldr r0,=0x02400c06
 str r0,[r4,#0x90]
 ldr r0,=0x0a000c0e
 str r0,[r4,#0x280]
 ldr r0,=0x0a000c02
 str r0,[r4,#0x680]
 ldr r6,=0x0a008000
 mov r0,#0x20
 str r0,[r6,#8]
 ldr r0,=0x40000
 str r0,[r6,#12]
 ldr r0,=0x02400000
 str r0,[r6,#20]
 mcr p15,0,r4,c2,c0,0
 mov r0,#1
 mcr p15,0,r0,c3,c0,0
 mrc p15,0,r0,c1,c0,0
 orr r0,r0,#0x1000
 orr r0,r0,#0x4000
 orr r0,r0,#5
 mcr p15,0,r0,c1,c0,0
 nop
 nop
 mov r7,#0
again:
 ldr r8,=0x02400000
 ldr r9,=0xaaa
 ldr r10,=0x554
 // Program a real NOR halfword before each erase, so completion checks data.
 bl program_edges
 mov r0,#0xaa
 strh r0,[r8,r9]
 mov r0,#0x55
 strh r0,[r8,r10]
 mov r0,#0x80
 strh r0,[r8,r9]
 mov r0,#0xaa
 strh r0,[r8,r9]
 mov r0,#0x55
 strh r0,[r8,r10]
 ldr r11,=0x40000
 mov r0,#0x30
 strh r0,[r8,r11]
 // Original suspend instruction shape, with a cold struct-data line.
 mov r4,r6
 ldr r2,[r4,#20]
 ldr r3,[r4,#12]
 tst r7,#2
 bne poll_erase
 mov ip,#0xb0
 strh ip,[r2,r3]
 b erased
poll_erase:
 ldrh r0,[r2,r3]
 cmp r0,#8
 bne fail
 ldrh r0,[r2,r3]
 ldr r12,=0xffff
 cmp r0,r12
 bne fail
erased:
 ldr r1,[r4,#8]
 cmp r1,#0x20
 bne fail
 bl cold_call
 ldrh r0,[r8,r11]
 tst r0,#0x80
 beq fail
 // Drop the struct line before repeating; change bufferability each pass.
 mcr p15,0,r6,c7,c6,1
 ldr r5,=0x1a004090
 ldr r0,=0x02400c02
 tst r7,#1
 orreq r0,r0,#4
 str r0,[r5]
 mov r0,#0
 mcr p15,0,r0,c7,c10,4
 mcr p15,0,r0,c8,c7,0
 add r7,r7,#1
 cmp r7,#8
 bne again
 ldr r1,=0x50415353
 b report
fail:
 ldr r1,=0x4641494c
report:
 ldr r0,=0x1a000100
 str r1,[r0]
 b .
program_edges:
 mov r0,#0xaa
 strh r0,[r8,r9]
 mov r0,#0x55
 strh r0,[r8,r10]
 mov r0,#0xa0
 strh r0,[r8,r9]
 ldr r11,=0x40000
 mov r0,#0
 strh r0,[r8,r11]
 mov r0,#0xaa
 strh r0,[r8,r9]
 mov r0,#0x55
 strh r0,[r8,r10]
 mov r0,#0xa0
 strh r0,[r8,r9]
 ldr r11,=0x4fffe
 mov r0,#0
 strh r0,[r8,r11]
 bx lr
.ltorg
.balign 4096
cold_call:
 ldr r0,[r6,#8]
 cmp r0,#0x20
 bne fail
 bx lr
