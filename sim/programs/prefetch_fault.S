.equ CUSTOM_PREFETCH, 1
.include "sim/programs/common.inc"

reset_entry:
    ldr sp, =RAM + 0x10000
    // Return from the very last mapped RAM word. Sequential instruction
    // fetches beyond it must fault, but be discarded when BX resolves.
    ldr r4, =RAM + 0x400000 - 4
    ldr r0, =0xe12fff1e // BX LR
    str r0, [r4]
    adr lr, returned
    mov pc, r4
returned:
    ldr r12, =MAILBOX
    mov r0, #1
    str r0, [r12, #12]
    // This fetch really is executed: verify prefetch-abort entry and LR.
    ldr pc, =0x90000000
    b fail
prefetch_handler:
    ldr r12, =MAILBOX
    str lr, [r12, #4]
    mrs r1, spsr
    str r1, [r12, #8]
    ldr r2, =0x90000004
    cmp lr, r2
    bne fail
    and r1, r1, #31
    cmp r1, #0x13
    bne fail
    ldr r1, [r12, #12]
    cmp r1, #1
    bne fail
    b pass
fail:
    mov r0, #9
    b finish
.ltorg
