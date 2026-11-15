.include "sim/programs/common.inc"
.equ TABLE, RAM + 0x4000
reset_entry:
    ldr sp, =RAM + 0x20000
    ldr r4, =TABLE
    mov r0, #0
    mov r1, #4096
clear:
    str r0, [r4], #4
    subs r1, r1, #1
    bne clear
    ldr r4, =TABLE
    ldr r0, =0x00000c0e
    str r0, [r4]
    ldr r0, =0x80000c0e
    add r5, r4, #0x2000
    str r0, [r5]
    ldr r0, =0xf0000c02
    add r5, r4, #0x3c00
    str r0, [r5]
    mcr p15, 0, r4, c2, c0, 0
    mov r0, #1
    mcr p15, 0, r0, c3, c0, 0
    mrc p15, 0, r0, c1, c0, 0
    orr r0, r0, #5
    orr r0, r0, #0x1000
    mcr p15, 0, r0, c1, c0, 0
    ldr r4, =RAM + 0x30000
    ldr r5, =0x80ff7f01
    ldr r6, =0x11223344
    str r5, [r4]
    str r6, [r4, #32]
    mov r10, #20
repeat:
    ldr r0, [r4]
    ldr r1, [r4, #32]
    ldrsb r2, [r4, #2]
    ldrh r3, [r4, #2]
    cmp r0, r5
    bne failed
    cmp r1, r6
    bne failed
    cmn r2, #1
    bne failed
    ldr r7, =0x80ff
    cmp r3, r7
    bne failed
    strb r0, [r4, #65]
    strh r1, [r4, #66]
    ldrb r2, [r4, #65]
    ldrh r3, [r4, #66]
    cmp r2, #1
    bne failed
    ldr r7, =0x3344
    cmp r3, r7
    bne failed
    ldr r1, [r4, #32]
    ldrt r0, [r4], #0
    ldr r1, [r4, #32]
    cmp r0, r5
    bne failed
    cmp r1, r6
    bne failed
    // Each micro-op has a distinct owner, including base/writeback handling.
    stmdb sp!, {r0-r7}
    ldmia sp!, {r0-r7}
    subs r10, r10, #1
    bne repeat
    // Never issue the younger store while an older load can redirect the PC.
    adr r7, target_pointer
    mov r0, #0
    str r0, [r4, #96]
    ldr pc, [r7]
    str r5, [r4, #96]
    str r6, [r4, #96]
redirect_target:
    ldr r0, [r4, #96]
    cmp r0, #0
    bne failed
    b pass
target_pointer:
    .word redirect_target
failed:
    mov r0, #0xd2
    b finish
.ltorg
