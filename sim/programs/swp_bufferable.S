.include "sim/programs/common.inc"
.equ TABLE, RAM + 0x4000
reset_entry:
    ldr sp, =RAM + 0x20000
    ldr r4, =TABLE
    mov r0, #0
    mov r1, #4096
1:  str r0, [r4], #4
    subs r1, r1, #1
    bne 1b
    ldr r4, =TABLE
    ldr r0, =0x00000c02
    str r0, [r4]
    ldr r0, =0x80000c02
    str r0, [r4, #0x800]
    add r5, r4, #0x1c00
    str r0, [r5]              @ VA 70000000: uncached alias
    ldr r0, =0x80000c0a
    sub r5, r5, #0x400
    str r0, [r5]              @ VA 60000000: C=1 B=0
    ldr r0, =0x80000c0e
    sub r5, r5, #0x800
    str r0, [r5]              @ VA 40000000: C=1 B=1
    ldr r0, =RAM + 0x10000
    ldr r1, =0x80032ffa    @ small page C=1 B=0, full access
    str r1, [r0]
    orr r0, r0, #1
    add r5, r4, #0x1400
    ldr r0, =0x80000c06
    str r0, [r5]              @ VA 50000000: noncached bufferable section
    ldr r0, =0xf0000c02
    add r5, r4, #0x3c00
    str r0, [r5]
    mcr p15, 0, r4, c2, c0, 0
    mov r0, #1
    mcr p15, 0, r0, c3, c0, 0
    mrc p15, 0, r0, c1, c0, 0
    orr r0, r0, #5
    mcr p15, 0, r0, c1, c0, 0
    nop
    nop
    ldr r1, =0x50030000
    ldr r2, =0x12345678
    swp r3, r2, [r1]
    cmp r3, #0
    bne fail
    ldr r1, =0x70030000
    ldr r3, [r1]
    cmp r3, r2
    bne fail
    b pass
fail:
    mov r0, #0xd8
    b finish
.ltorg
