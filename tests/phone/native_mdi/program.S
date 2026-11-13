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
 ldr r0,=0x0c100000
 str r0,[r10,#4]
 ldr r0,=0x0c1001f4
 str r0,[r10,#8]
 ldr r0,=0x0c1003e8
 str r0,[r10,#12]
 add r0,r0,#2
 str r0,[r10,#16]
 add r0,r0,#2
 str r0,[r10,#20]
 add r0,r0,#2
 str r0,[r10,#24]
 mov r0,#250
 strh r0,[r10,#0x42]
 strh r0,[r10,#0x44]
 ldr r0,=0x0c1003e8
 mov r1,#0
 str r1,[r0]
 str r1,[r0,#4]
 ldr r0,=0x0c14b004
 mov r1,#0x500
 str r1,[r0]
 // Native availability helper and native ring reader consume link startup.
 mov r8,#4
 bl receive
 ldr r0,=0x80003000
 ldr r1,[r0]
 ldr r2,=0xd07c0000
 cmp r1,r2
 bne fail
 ldr r1,[r0,#4]
 ldr r2,=0x00040100
 cmp r1,r2
 bne fail
 // Exact RF query captured from native startup on91045a6: media12,
 // object01/24 and untouched allocation padding55.
 ldr r1,=0x80002000
 ldr r0,=0xf1007c12
 str r0,[r1]
 ldr r0,=0x24010600
 str r0,[r1,#4]
 ldr r0,=0x5502a020
 str r0,[r1,#8]
 mov r0,r10
 mov r2,#6
 ldr r4,=0x515bf551
 mov lr,pc
 bx r4
 mov r8,#6
 bl receive
 // Native RX reader byte-swaps the response into normal Phonet order.
 ldr r0,=0x80003000
 ldr r1,[r0]
 ldr r2,=0xf17c0012
 cmp r1,r2
 bne fail
 ldr r1,[r0,#4]
 ldr r2,=0x01240600
 cmp r1,r2
 bne fail
 ldr r1,[r0,#8]
 ldr r2,=0x0301a120
 cmp r1,r2
 bne fail
 ldr r0,=0x50415353
 b finish
receive:
 push {lr}
1:
 mov r0,r10
 ldr r4,=0x515bf475
 mov lr,pc
 bx r4
 cmp r0,r8
 blo 1b
 mov r0,r10
 ldr r1,=0x80003000
 mov r2,r8
 ldr r4,=0x515bf65d
 mov lr,pc
 bx r4
 pop {pc}
fail:
 ldr r0,=0xbadf00d
finish:
 ldr r1,=0xf0000000
 str r0,[r1]
park: b park
