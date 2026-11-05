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
    @ High virtual code alias is outside FCSE's low 32 MiB window.
    ldr r0, =0x00000c0e
    str r0, [r4, #0x400]     @ VA 10000000 -> physical ROM
    ldr r5, =RAM + 0x10000
    ldr r0, =0x80030ffe      @ small page, C=B=1, full access
    str r0, [r5, #0xc0]
    orr r0, r5, #1
    str r0, [r4, #0x84]      @ MVA 021xxxxx coarse table
    ldr r5, =RAM + 0x10400
    ldr r0, =0x80031ffe
    str r0, [r5, #0xc0]
    orr r0, r5, #1
    str r0, [r4, #0x104]     @ MVA 041xxxxx coarse table
    mcr p15, 0, r4, c2, c0, 0
    mov r0, #1
    mcr p15, 0, r0, c3, c0, 0
    mrc p15, 0, r0, c1, c0, 0
    orr r0, r0, #5
    mcr p15, 0, r0, c1, c0, 0
    nop
    nop
    adr r0, high_code
    add r0, r0, #0x10000000
    bx r0
high_code:
    ldr r8, =0x00130100
    ldr r9, =0x70030100
    ldr r10, =0x70031100
    ldr r1, =0x12345678
    ldr r2, =0x87654321
    str r1, [r9]
    str r2, [r10]
    mov r0, #0x02000000
    mcr p15, 0, r0, c13, c0, 0
    nop
    nop
    ldr r3, [r8]
    cmp r3, r1
    movne r0, #0xa1
    bne finish
    mov r0, #0x04000000
    mcr p15, 0, r0, c13, c0, 0
    nop
    nop
    ldr r3, [r8]
    cmp r3, r2
    movne r0, #0xa2
    bne finish
    mov r0, #0x02000000
    mcr p15, 0, r0, c13, c0, 0
    nop
    nop
    ldr r3, [r8]
    cmp r3, r1
    movne r0, #0xa3
    bne finish
    mov r0, #0
    mcr p15, 0, r0, c13, c0, 0
    b pass
.ltorg
