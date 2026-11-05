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
    mcr p15, 0, r0, c1, c0, 0
    nop
    nop
    ldr r6, =0x60030000
    ldr r7, =0x70030000
    ldr r8, =0x40030100
    ldr r9, =0x70030100
    ldr r1, =0x12345678
    str r1, [r6]              @ write-through miss reaches memory
    ldr r2, [r7]
    cmp r1, r2
    movne r0, #1
    bne finish
    ldr r2, [r6]              @ populate line
    ldr r1, =0x1122aabb
    str r1, [r6]              @ write-through hit reaches memory
    ldr r2, [r7]
    cmp r1, r2
    movne r0, #2
    bne finish
    ldr r2, [r6]              @ and cached view sees updated value
    cmp r1, r2
    movne r0, #3
    bne finish
    ldr r1, =0x00005678
    strh r1, [r6, #2]         @ byte enables and high halfword
    ldr r2, [r7]
    ldr r3, =0x5678aabb
    cmp r2, r3
    movne r0, #4
    bne finish
    ldr r2, [r8]              @ bring WB line into cache
    ldr r1, =0x55aaff00
    str r1, [r8]
    ldr r2, [r8]
    cmp r1, r2
    movne r0, #5
    bne finish
    ldr r2, [r9]
    cmp r1, r2                @ WB hit remains dirty in cache
    moveq r0, #6
    beq finish
    ldr r6, =0x50000000
    ldr r7, =0x70032000
    ldr r1, =0xcafebabe
    str r1, [r6]
    ldr r2, [r7]
    cmp r1, r2
    movne r0, #7
    bne finish
    b pass
.ltorg
