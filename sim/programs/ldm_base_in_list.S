// ARM LDM without writeback: the base register may be in the load list.
.include "sim/programs/common.inc"
reset_entry:
    ldr r5, =RAM + 0x100
    ldr r0, =0xe59ff028
    ldr r1, =0x12345678
    str r0, [r5]
    str r1, [r5, #4]
    ldmia r5, {r5, lr}
    cmp r5, r0
    movne r0, #1
    bne finish
    cmp lr, r1
    movne r0, #2
    bne finish
    b pass
.ltorg
