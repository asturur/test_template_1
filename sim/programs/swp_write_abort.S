.equ CUSTOM_ABORT, 1
.include "sim/programs/common.inc"
reset_entry:
    ldr r1, =RAM+0x1000
    ldr r2, =0x12345678
    swp r3, r2, [r1]
    mov r0, #0xd3
    b finish
data_abort:
    ldr r4, [r1]
    cmp r4, #0
    movne r0, #0xd4
    bne finish
    b pass
.ltorg
