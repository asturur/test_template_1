.equ CUSTOM_IRQ, 1
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
    orr r0, r0, #0x4000      @ ARM920T round-robin replacement
    mcr p15, 0, r0, c1, c0, 0
    nop
    nop
    ldr r8, =0x40030100
    ldr r9, =0x70030100
    ldr r7, =0x76543210
    str r7, [r9]
    mov r6, #0
    mrs r0, cpsr
    bic r0, r0, #0x80
    msr cpsr_c, r0
    ldr r2, [r8]             @ interrupt is injected during this linefill
    cmp r2, r7
    movne r0, #0xd2
    bne finish
    ldr r3, =1000
1:  cmp r6, #1
    beq 2f
    subs r3, r3, #1
    bne 1b
    mov r0, #0xd3
    b finish
2:  nop
    nop
    cmp r6, #1
    movne r0, #0xd4
    bne finish
    b pass
irq_handler:
    add r6, r6, #1
    subs pc, lr, #4
.ltorg
