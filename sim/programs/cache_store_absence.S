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
    str r0, [r4]
    ldr r0, =0x80000c02
    ldr r5, =0x2000
    str r0, [r4, r5]
    ldr r0, =0x8000080e          @ AP2, client domain: User reads only.
    ldr r5, =0x1400
    str r0, [r4, r5]
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
    ldr r4, =0x50030000
    ldr r2, =0x12345678
    ldr r9, =0x31415926
    ldr r3, =0xbad0bad0
    mov r6, #8
    mov r7, #0
2:  str r2, [r4]                @ Cold WB miss establishes absence.
    str r9, [r4, #4]            @ Ordinary SVC store can reuse the absence.
    strt r3, [r4], #0           @ Warm absence must never authorize User write.
    ldrt r1, [r4], #0           @ Drain older writes and refill the absent line.
    cmp r1, r2
    bne fail
    add r8, r4, #4
    ldrt r1, [r8], #0
    cmp r1, r9
    bne fail
    str r9, [r4]               @ Refill revoked absence: update resident data.
    ldrt r1, [r4], #0
    cmp r1, r9
    bne fail
    add r4, r4, #32
    add r2, r2, #1
    subs r6, r6, #1
    bne 2b
    cmp r7, #8
    bne fail
    b pass

data_abort:
    mrc p15, 0, r10, c5, c0, 0
    cmp r10, #0x0d
    bne fail
    mrc p15, 0, r10, c6, c0, 0
    cmp r10, r4
    bne fail
    add r7, r7, #1
    subs pc, lr, #4
fail:
    mov r0, #0xd6
    b finish
.ltorg
