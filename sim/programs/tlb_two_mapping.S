.equ CUSTOM_ABORT, 1
.include "sim/programs/common.inc"
.equ TABLE, RAM + 0x4000

reset_entry:
    ldr r4, =TABLE
    mov r0, #0
    mov r1, #4096
1:  str r0, [r4], #4
    subs r1, r1, #1
    bne 1b
    ldr r4, =TABLE
    ldr r0, =0x00000c02
    str r0, [r4]                 @ Identity code, AP3.
    ldr r0, =0x80000c02
    ldr r5, =0x2000
    str r0, [r4, r5]             @ Identity RAM, AP3.
    ldr r0, =0x8000080e
    ldr r5, =0x1400
    str r0, [r4, r5]             @ 50000000 -> RAM, AP2, cached/buffered.
    ldr r0, =0x80000c0e          @ Second VA/PA, AP3, same User context.
    ldr r5, =0x1404
    str r0, [r4, r5]
    ldr r0, =0xf0000c02
    add r5, r4, #0x3c00
    str r0, [r5]
    ldr r1, =RAM + 0x30100
    ldr r2, =0x12345678
    str r2, [r1]
    ldr r1, =RAM + 0x31100
    ldr r8, =0x87654321
    str r8, [r1]
    mcr p15, 0, r4, c2, c0, 0
    mov r0, #1
    mcr p15, 0, r0, c3, c0, 0   @ Domain zero is client, never manager.
    mrc p15, 0, r0, c1, c0, 0
    orr r0, r0, #5
    mcr p15, 0, r0, c1, c0, 0
    nop
    nop
    ldr r4, =0x50030100
    ldr r5, =0x50131100
    ldr r3, =0xbad0bad0
    mov r6, #32
    mov r7, #0
2:  ldrt r1, [r4], #0            @ Warm user read must not authorize a write.
    cmp r1, r2
    bne fail
    ldrt r1, [r5], #0            @ Alternate mapping with AP3.
    cmp r1, r8
    bne fail
    strt r3, [r4], #0
    ldrt r1, [r4], #0            @ Denied write must not poison the next read.
    cmp r1, r2
    bne fail
    add r8, r8, #1
    strt r8, [r5], #0            @ Opposite slot allows writes, exact own PA.
    ldrt r1, [r5], #0
    cmp r1, r8
    bne fail
    subs r6, r6, #1
    bne 2b
    cmp r7, #32
    bne fail
    ldr r1, [r4]                 @ Privileged AP2 write is still permitted.
    str r3, [r4]
    ldr r1, [r4]
    cmp r1, r3
    bne fail
    b pass

data_abort:
    mrc p15, 0, r10, c5, c0, 0
    cmp r10, #0x0d              @ Section permission fault, domain zero.
    bne fail
    mrc p15, 0, r10, c6, c0, 0
    cmp r10, r4
    bne fail
    add r7, r7, #1
    subs pc, lr, #4             @ Skip faulting STRT, preserving User-access class.

fail:
    mov r0, #0xd7
    b finish
.ltorg
