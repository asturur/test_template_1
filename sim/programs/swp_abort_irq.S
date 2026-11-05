.equ CUSTOM_ABORT, 1
.equ CUSTOM_IRQ, 1
.include "sim/programs/common.inc"
reset_entry:
    ldr r1, =RAM+0x1000
    ldr r2, =0x12345678
    mov r3, #0x5a
    mov r6, #0
    mrs r0, cpsr
    bic r0, r0, #0x80
    msr cpsr_c, r0
    swp r3, r2, [r1]
    mov r0, #0xd3
    b finish
irq_handler:
    add r6, r6, #1
    subs pc, lr, #4
data_abort:
    cmp r6, #0
    movne r0, #0xd4
    bne finish
    cmp r3, #0x5a
    movne r0, #0xd5
    bne finish
    b pass
.ltorg
