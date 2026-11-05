.equ CUSTOM_ABORT, 1
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
    ldr r0, =0x80000cc2       @ section domain 6
    str r0, [r5]              @ VA 70000000: uncached alias
    ldr r0, =0x80000c0a
    sub r5, r5, #0x400
    str r0, [r5]              @ VA 60000000: C=1 B=0
    ldr r0, =0x80000c0e
    sub r5, r5, #0x800
    str r0, [r5]              @ VA 40000000: C=1 B=1
    ldr r0, =RAM + 0x10000
#ifdef PAGE_ABORT
    ldr r1, =0x80032ff2    @ small page noncacheable, nonbuffered
#else
    ldr r1, =0x80032ffa    @ small page C=1 B=0, full access
#endif
    str r1, [r0]
    orr r0, r0, #1
    orr r0, r0, #0xc0         @ page-table domain 6
    add r5, r4, #0x1400
    str r0, [r5]              @ VA 50000000 through coarse table
    ldr r0, =0xf0000c02
    add r5, r4, #0x3c00
    str r0, [r5]
    mcr p15, 0, r4, c2, c0, 0
    ldr r0, =0x00001001       @ domains 0 and 6 are clients
    mcr p15, 0, r0, c3, c0, 0
    mrc p15, 0, r0, c1, c0, 0
    orr r0, r0, #5
    mcr p15, 0, r0, c1, c0, 0
    nop
    nop
#ifdef PAGE_ABORT
    ldr r8, =0x50000000
#else
    ldr r8, =0x70030100
#endif
    ldr r0, [r8]           @ injected external read error enters data abort
    mov r0, #0xc1          @ must not execute
    b finish
data_abort:
    mrc p15, 0, r2, c5, c0, 0
    and r2, r2, #0xff
#ifdef PAGE_ABORT
    cmp r2, #0x6a
#else
    cmp r2, #0x68
#endif
    movne r0, #0xc2
    bne finish
    mrc p15, 0, r3, c6, c0, 0
    cmp r3, r8
    movne r0, #0xc3
    bne finish
    b pass
.ltorg
