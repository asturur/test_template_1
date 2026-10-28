.equ CUSTOM_ABORT, 1
.include "sim/programs/common.inc"

reset_entry:
    ldr sp, =RAM + 0x10000
    ldr r4, =RAM
    ldr r0, =0x11223344
    str r0, [r4]
    mov r5, #0
    mov r6, #0
    mov r8, #0
    // This is the control value used by the inspected Nokia 4.03 startup.
    ldr r0, =0x00001272
    mcr p15, 0, r0, c1, c0, 0
    mrc p15, 0, r1, c1, c0, 0
    ldr r12, =MAILBOX
    str r0, [r12, #4]
    str r1, [r12, #8]
    add r1, r4, #1
    ldr r2, [r1]
    str r8, [r12, #12]
    str r5, [r12, #16]
    str r6, [r12, #20]
    b pass
data_abort:
    mov r8, #1
    mrc p15, 0, r5, c5, c0, 0
    mrc p15, 0, r6, c6, c0, 0
    subs pc, lr, #4
.ltorg
