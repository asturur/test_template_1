.equ CUSTOM_ABORT, 1
.include "sim/programs/common.inc"
.equ TABLE, RAM + 0x4000

reset_entry:
    ldr sp, =RAM + 0x20000
    mrc p15, 0, r0, c1, c0, 0
    bic r0, r0, #0x1000
    bic r0, r0, #0x300
    bic r0, r0, #7
    mcr p15, 0, r0, c1, c0, 0
    ldr r4, =TABLE
    mov r1, #4096
    mov r0, #0
clear_table:
    str r0, [r4], #4
    subs r1, r1, #1
    bne clear_table
    ldr r4, =TABLE
    ldr r0, =0x00000c02
    str r0, [r4]
    str r0, [r4, #0x80]
    ldr r0, =0x80000c02
    str r0, [r4, #4]
    str r0, [r4, #0x800]
    ldr r6, =RAM + 0x8000
    ldr r7, =0x8000055e // cacheable small page, same descriptor flags as firmware
    str r7, [r6]
    ldr r7, =0x8000155e
    str r7, [r6, #4]
    orr r6, r6, #1 // coarse page table
    add r5, r4, #0x1000
    str r6, [r5] // map VA 0x40000000 through a small page
    add r5, r4, #0x2000
    str r0, [r5]
    ldr r0, =0x80100c02
    str r0, [r4, #0x84]
    str r0, [r5, #4]
    ldr r0, =0xf0000c02
    add r5, r4, #0x3c00
    str r0, [r5]
    mcr p15, 0, r4, c2, c0, 0
    mov r0, #1
    mcr p15, 0, r0, c3, c0, 0
    mov r0, #0
    mcr p15, 0, r0, c13, c0, 0
    mcr p15, 0, r0, c8, c7, 0
    mrc p15, 0, r0, c1, c0, 0
    orr r0, r0, #1
#ifndef DISABLE_CACHES
    // The descriptors remain uncacheable. Enable the cache units so the
    // baseline exercises ZAP's working translated-access path.
    orr r0, r0, #0x1000
    orr r0, r0, #4
#endif
    mcr p15, 0, r0, c1, c0, 0
    nop
    nop
    nop
    ldr r1, =0x20000000
    ldr r2, =0x13579bdf
    str r2, [r1]
    ldr r3, =RAM
    ldr r0, [r3]
    cmp r0, r2
    movne r0, #0x11
    bne finish
    ldr r1, =0x00100000
    ldr r2, =0x11111111
    str r2, [r1]
    mov r0, #0x02000000
    mcr p15, 0, r0, c13, c0, 0
    nop
    nop
    nop
    mrc p15, 0, r2, c13, c0, 0
    cmp r0, r2
    movne r0, #0x12
    bne finish
    ldr r2, =0x22222222
    str r2, [r1]
    mov r0, #0
    mcr p15, 0, r0, c13, c0, 0
    nop
    nop
    nop
    ldr r0, [r1]
    ldr r2, =0x11111111
    cmp r0, r2
    movne r0, #0x13
    bne finish
    ldr r3, =RAM + 0x100000
    ldr r0, [r3]
    ldr r2, =0x22222222
    cmp r0, r2
    movne r0, #0x14
    bne finish
    // Match the firmware: base R0 is also the first destination, first
    // value is -1, and the six-word load crosses a small-page boundary.
    ldr r0, =0x40000ff8
    mvn r1, #0
    str r1, [r0]
    mov r1, #3
    str r1, [r0, #4]
    mov r1, #4
    str r1, [r0, #8]
    mov r1, #5
    str r1, [r0, #12]
    mov r1, #6
    str r1, [r0, #16]
    mov r1, #12
    str r1, [r0, #20]
#ifdef COLD_CACHE
    // Commit both lines then evict them and invalidate translations so that
    // the load encounters cold cache and small-page walks on both sides.
    mcr p15, 0, r0, c7, c14, 1
    add r1, r0, #8
    mcr p15, 0, r1, c7, c14, 1
    mcr p15, 0, r1, c7, c10, 4
    mcr p15, 0, r1, c8, c7, 0
#endif
    msr cpsr_c, #0xdb
    ldmia r0, {r0, r3, r4, r5, r6, r12}
    cmn r0, #1
    bne failure
    cmp r3, #3
    bne failure
    cmp r4, #4
    bne failure
    cmp r5, #5
    bne failure
    cmp r6, #6
    bne failure
    cmp r12, #12
    bne failure
    msr cpsr_c, #0xd3
    b pass
data_abort:
    mrc p15, 0, r0, c6, c0, 0
    b finish
failure:
    mov r0, #0x21
    b finish
.ltorg
