.equ CUSTOM_IRQ, 1
.include "sim/programs/common.inc"
reset_entry:
    ldr r1, =RAM+0x1000
    ldr r2, =0x12345678
    mov r3, #0x77
    mov r6, #0
    mov r7, #0
    mrs r0, cpsr
    bic r0, r0, #0x80
    msr cpsr_c, r0
    swp r3, r2, [r1]
    mov r9, #200
1:  cmp r6, #1
    beq 2f
    subs r9, r9, #1
    bne 1b
    mov r0, #0xd6
    b finish
2:  cmp r7, #0
    bne fail
    cmp r3, #0
    bne fail
    b pass
irq_handler:
    ldr r8, [r1]
    cmp r8, #0
    bne 3f
    cmp r3, #0x77
    movne r7, #1
    b 4f
3:  cmp r8, r2
    movne r7, #2
    cmp r3, #0
    movne r7, #3
4:  add r6, r6, #1
    subs pc, lr, #4
fail:
    mov r0, #0xd7
    b finish
.ltorg
