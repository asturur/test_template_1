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
 ldr r8,=0x0c150400
 ldr r9,=0x0c15040c
 ldr r10,=0x0c150510
 mov r0,#0x1f
 strb r0,[r8,#3]       @ Make keypad rows inputs.
 mov r0,#1
 strb r0,[r9,#2]       @ Enable output on column zero.
 mov r6,#0
 mov r5,#512
loop:
 strb r6,[r9]          @ Alternate drive low/high with the key held.
 ldrh r2,[r8]
 and r2,r2,#31
 add r3,r6,#30
 cmp r2,r3
 bne fail
 str r5,[r10]          @ Write a distinct EUART configuration and read it back.
 ldr r2,[r10]
 cmp r2,r5
 bne fail
 eor r6,r6,#1
 subs r5,r5,#1
 bne loop
 ldr r0,=0x50415353
 b finish
fail:
 mov r0,#1
finish:
 ldr r1,=0x0a000100
 str r0,[r1]
1: b 1b
.ltorg
