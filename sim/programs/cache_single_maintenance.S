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
    str r0, [r5]              @ VA 50000000 through coarse table
    ldr r0, =0xf0000c02
    add r5, r4, #0x3c00
    str r0, [r5]
    mcr p15, 0, r4, c2, c0, 0
    mov r0, #1
    mcr p15, 0, r0, c3, c0, 0
    mrc p15, 0, r0, c1, c0, 0
    orr r0, r0, #5
    orr r0, r0, #0x4000      @ ARM920T round-robin replacement
    mcr p15, 0, r0, c1, c0, 0
    nop
    nop
    mov r0, #0
    mcr p15, 0, r0, c9, c0, 0 @ reset victim index
    ldr r8, =0x40030100
    ldr r9, =0x70030100
    ldr r10, =0x40034100
    ldr r11, =0x70034100
    ldr r1, =0x11112222
    ldr r2, [r8]
    str r1, [r8]
    ldr r3, =0x33334444
    ldr r2, [r10]
    str r3, [r10]
    mcr p15, 0, r8, c7, c10, 1 @ clean first line by MVA
    ldr r2, [r9]
    cmp r1, r2
    movne r0, #0x81
    bne finish
    ldr r2, [r11]
    cmp r2, #0                @ second dirty line must not be cleaned
    movne r0, #0x82
    bne finish
    mov r0, #0x04000000       @ way 1, segment 0
    mcr p15, 0, r0, c7, c14, 2 @ clean and invalidate by index
    ldr r2, [r11]
    cmp r3, r2
    movne r0, #0x83
    bne finish
    ldr r3, =0x55556666
    str r3, [r11]
    ldr r2, [r10]             @ invalidated, must refetch
    cmp r3, r2
    movne r0, #0x84
    bne finish
    ldr r3, =0x77778888
    str r3, [r9]
    ldr r2, [r8]              @ first clean line must stay cached
    cmp r1, r2
    movne r0, #0x85
    bne finish
    b pass
.ltorg
