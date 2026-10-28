.include "sim/programs/common.inc"

reset_entry:
    ldr sp, =RAM + 0x8000
    ldr r0, =RAM + 0x10000
    mov r1, #4096
    mov r2, #0
clear_table:
    str r2, [r0], #4
    subs r1, r1, #1
    bne clear_table
    ldr r0, =RAM + 0x10000
    ldr r2, =0x00000c02
    str r2, [r0]
    mov r1, #0xc00
    str r2, [r0, r1] // VA 0x30000000 -> physical ROM 0
    ldr r1, =0x800 * 4
    ldr r2, =0x80000c02
    str r2, [r0, r1]
    ldr r1, =0xf00 * 4
    ldr r2, =0xf0000c02
    str r2, [r0, r1]
    mcr p15, 0, r0, c2, c0, 0
    mov r0, #3
    mcr p15, 0, r0, c3, c0, 0
    mov r0, #1 // MMU on, both caches off
    mcr p15, 0, r0, c1, c0, 0
    ldr r4, =translated_target + 0x30000000
    bx r4
translated_target:
    adr r0, translated_target
    ldr r1, =translated_target + 0x30000000
    cmp r0, r1
    movne r0, #0xb1
    bne finish
    ldr r12, =MAILBOX
    str r0, [r12, #4]
    b pass
.ltorg
