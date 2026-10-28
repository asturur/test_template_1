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
    ldr r5, =0xe59ff028
    ldmia r5, {r5, lr}
    mov r0, #0x31
    b finish
data_abort:
    mrc p15, 0, r1, c6, c0, 0
    mrc p15, 0, r3, c5, c0, 0
    and r3, r3, #15
    cmp r3, #5
    movne r0, #0x33
    bne finish
    ldr r2, =0xe59ff028
    cmp r1, r2
    movne r0, #0x32
    bne finish
    b pass
.ltorg
