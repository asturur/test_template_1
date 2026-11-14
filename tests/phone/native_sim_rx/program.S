.syntax unified
.cpu arm920t
.arm
.global _start
_start: b start
.rept 7
 b fail
.endr
start:
 msr cpsr_c,#0xd1
 ldr sp,=0x800ff000
 ldr r0,=0x800ce954
 mov r1,#2
 strb r1,[r0]
 ldr r0,=0x800c9f24
 str r1,[r0]
 mov r1,#0xa4
 str r1,[r0,#4]
 ldr r0,=0x800ca15c
 mov r1,#2
 strb r1,[r0]
 ldr r0,=0xf000000c
 ldr r0,[r0]
 cmp r0,#0
 beq card_ready
 // Set up the exact observed SELECT against production SIMIF/test-card RTL.
 ldr r2,=0x5815080c
 ldr r3,=0x58150800
 mov r0,#1
 strh r0,[r3,#8]
 ldrh r0,[r2]
 cmp r0,#0x3b
 bne fail
 ldrh r0,[r2]
 cmp r0,#0
 bne fail
 mov r0,#16
 strh r0,[r3]
 mov r0,#0xa0
 strh r0,[r2]
 mov r0,#0xa4
 strh r0,[r2]
 mov r0,#0
 strh r0,[r2]
 strh r0,[r2]
 mov r0,#2
 strh r0,[r2]
 mov r0,#8
 strh r0,[r3]
 ldrh r0,[r2]
 cmp r0,#0xa4
 bne fail
 mov r0,#0x7f
 strh r0,[r2]
 mov r0,#0x20
 strh r0,[r2]
 mov r0,#8
 strh r0,[r3]
card_ready:
 // Fixture choice; source native SIM instructions are identical in both runs.
 ldr r0,=0xf0000004
 ldr r0,[r0]
 cmp r0,#0
 beq invoke
 ldr r4,=0x0a004000
 ldr r0,=0x00000c02
 str r0,[r4]
 ldr r0,=0x51600c0e
 ldr r1,=0x1458
 str r0,[r4,r1]
 ldr r0,=0x0a000c0e
 ldr r1,=0x2000
 str r0,[r4,r1]
 ldr r0,=0x58100c02
 ldr r1,=0x1604
 str r0,[r4,r1]
 ldr r0,=0xf0000c02
 ldr r1,=0x3c00
 str r0,[r4,r1]
 mcr p15,0,r4,c2,c0,0
 mov r0,#1
 mcr p15,0,r0,c3,c0,0
 mrc p15,0,r0,c1,c0,0
 orr r0,r0,#0x4000
 orr r0,r0,#0x1000
 orr r0,r0,#5
 mcr p15,0,r0,c1,c0,0
 nop
 nop
invoke:
 ldr r4,=0x51635c21
 mov lr,pc
 bx r4
 ldr r4,=0x800c9f28
 ldrh r2,[r4]
 ldr r1,=0xf0000008
 str r2,[r1]
 ldr r1,=0x169f
 cmp r2,r1
 bne fail
 ldr r4,=0x800c9f24
 ldr r2,[r4]
 ldr r1,=0x00020000
 cmp r2,r1
 bne fail
 ldr r0,=0x50415353
 b finish
fail: ldr r0,=0x0badf00d
finish:
 ldr r1,=0xf0000000
 str r0,[r1]
park: b park
