.syntax unified
.cpu arm920t
.arm
.equ RAM, 0x0a000000
.section .text, "ax"
.global _start
_start:
    b reset_entry
    b fail
    b fail
    b fail
    b fail
    b fail
    b fail
    b fail
reset_entry:
    ldr r10, =RAM
    mov r3, r10
    adr r1, flash_stub
    adr r2, flash_stub_end
copy_stub:
    ldr r9, [r1], #4
    str r9, [r3], #4
    cmp r1, r2
    blo copy_stub
    mov r0, #0
    ldr r4, =0xaaa
    ldr r5, =0x554
    mov r6, #0xf0
    adr lr, returned
    mov pc, r10
returned:
    cmp r8, #1
    bne fail
    ldr r0, =0x0bad0000
    str r8, [r0] // Expected stop: valid return after flash reset.
    b .
fail:
    ldr r0, =0x0bad0004
    str r0, [r0]
    b .
flash_stub:
    strh r6, [r0]
    mov r7, #0xaa
    strh r7, [r0, r4]
    mov r7, #0x55
    strh r7, [r0, r5]
    mov r7, #0x90
    strh r7, [r0, r4]
    ldrh r8, [r0]
    strh r6, [r0]
    mov pc, lr
flash_stub_end:
.ltorg
// Synthetic physical map for the board model; no Nokia firmware required.
.org 0x830
    .word 2, 1
    .word 0, 0x1000, 1, 0
    .word RAM, 0x01000000, 2, 0
.org 0x900
    .word 0
