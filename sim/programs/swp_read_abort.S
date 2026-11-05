.equ CUSTOM_ABORT, 1
.include "sim/programs/common.inc"
reset_entry:
    ldr r1, =RAM+0x1000
    ldr r2, =0x12345678
    mov r3, #0x5a
    swp r3, r2, [r1]
    mov r0, #0xd3
    b finish
data_abort:
    cmp r3, #0x5a
    movne r0, #0xd4
    bne finish
    mrc p15, 0, r4, c6, c0, 0
    cmp r4, r1
    movne r0, #0xd5
    bne finish
    b pass
.ltorg
