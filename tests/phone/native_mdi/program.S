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

 // Stock game PCM START uses the captured SDRAM addresses and rate selector.
 ldr r1,=pcm_bad_start
 mov r2,#12
 bl send
 ldr r1,=pcm_open
 mov r2,#12
 bl send
 mov r8,#7
 bl receive
 ldr r9,=0x2100
 mov r7,#0
 bl check_pcm

 // Use four samples per half to test the complete native reply sequence.
 ldr r1,=pcm_first
 mov r2,#7
 bl send
 bl receive
 ldr r9,=0x2400
 bl check_pcm
 bl receive
 ldr r9,=0x2600
 mov r7,#0x100
 bl check_pcm
 ldr r1,=pcm_wrong_owner
 mov r2,#7
 bl send
 ldr r1,=pcm_refill
 mov r2,#7
 bl send
 bl receive
 ldr r9,=0x2800
 mov r7,#0
 bl check_pcm
 bl receive
 ldr r9,=0x2600
 bl check_pcm
 ldr r1,=pcm_final
 mov r2,#7
 bl send
 bl receive
 ldr r9,=0x2800
 mov r7,#0
 bl check_pcm
 bl receive
 ldr r9,=0x2b00
 mov r7,#0x800
 bl check_pcm

 // Same-boot restart and explicit stop, followed by the idle cleanup stop.
 ldr r1,=pcm_open
 mov r2,#12
 bl send
 bl receive
 ldr r9,=0x2100
 mov r7,#0
 bl check_pcm
 ldr r1,=pcm_stop
 mov r2,#5
 bl send
 bl receive
 ldr r9,=0x2b6a
 bl check_pcm
 ldr r1,=pcm_stop
 mov r2,#5
 bl send
 bl receive
 bl check_pcm

 ldr r0,=0x50415353
 b finish
send:
 mov r0,r10
 ldr r4,=0x515bf551
 bx r4
check_pcm:
 ldr r0,=0x80003000
 ldr r1,[r0]
 ldr r2,=0xe87c0012
 cmp r1,r2
 bne fail
 ldr r1,[r0,#4]
 ldr r2,=0x014c0800
 cmp r1,r2
 bne fail
 ldrh r1,[r0,#8]
 cmp r1,r9
 bne fail
 ldrh r1,[r0,#10]
 cmp r1,r7
 bne fail
 ldrh r1,[r0,#12]
 cmp r1,#0
 bne fail
 bx lr
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
.align 2
pcm_bad_start:
 .byte 0x12,0x7c,0,0xe8,0,0x12,1,0x4c,1,0x20,0x82,2
 .byte 0x15,0xe0,0x0a,6,0x10,0,0x0a,6,0x10,0,0,0x46
pcm_open:
 .byte 0x12,0x7c,0,0xe8,0,0x12,1,0x4c,0,0x20,0x82,2
 .byte 0x15,0xe0,0x0a,6,0x10,0,0x0a,6,0x3b,0xc0,0,0x46
pcm_first:
 .byte 0x12,0x7c,0,0xe8,0,8,1,0x4c,0,0x23,0,2,0,4
.align 2
pcm_wrong_owner:
 .byte 0x12,0x7c,0,0xe8,0,8,1,0x4d,1,0x27,0,1,0,4
.align 2
pcm_refill:
 .byte 0x12,0x7c,0,0xe8,0,8,1,0x4c,0,0x27,0,2,0,4
.align 2
pcm_final:
 .byte 0x12,0x7c,0,0xe8,0,8,1,0x4c,0,0x27,0,1,0,4
.align 2
pcm_stop:
 .byte 0x12,0x7c,0,0xe8,0,4,1,0x4c,0x6a,0x2a
