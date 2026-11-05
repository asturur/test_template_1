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
    ldr r0, =0x00000c0e
    str r0, [r4]
    ldr r0, =0x80000c0e
    add r5, r4, #0x2000
    str r0, [r5]
#ifdef NONIDENTITY
    add r5, r4, #0x2000
    add r5, r5, #0x170
#ifdef SMALLPAGE
    ldr r0, =RAM + 0x8000
    orr r1, r0, #1
    str r1, [r5]             @ VA 0x85cxxxxx coarse table
    ldr r1, =0x80030ffe
    str r1, [r0, #0xc0]      @ VA 0x85c30000 -> PA 0x80030000
#else
    ldr r0, =0x80000c0e
    str r0, [r5]             @ VA 0x85c00000 -> PA 0x80000000
#endif
#endif
    ldr r0, =0xf0000c02
    add r5, r4, #0x3c00
    str r0, [r5]
    ldr r7, =RAM + 0x30000
    ldr r1, =0x12345678
    str r1, [r7, #188]
    ldr r1, =0x46b46836
    str r1, [r7, #196]
    mcr p15, 0, r4, c2, c0, 0
    mov r0, #1
    mcr p15, 0, r0, c3, c0, 0
    mrc p15, 0, r0, c1, c0, 0
    orr r0, r0, #7
    orr r0, r0, #0x1000
    mcr p15, 0, r0, c1, c0, 0
    nop
    nop
#ifdef NONIDENTITY
    ldr r7, =0x85c30000
#endif
#ifdef USER_CONTEXT
    msr cpsr_c, #0xdf        @ system mode shares user stack
    ldr sp, =RAM + 0x20000
    msr cpsr_c, #0xd0        @ user mode
#endif
    adr r0, thumb_start + 1
    bx r0
.thumb
.thumb_func
thumb_start:
    movs r4, r7
    adds r4, #196
    bl helper
    ldr r0, [r4]
    movs r0, r7
    adds r0, #188
    ldr r5, [r0]
    ldr r1, =0x12345678
    cmp r5, r1
    bne fail
    ldr r0, =SUCCESS
    ldr r1, =MAILBOX
    str r0, [r1]
    b .
.thumb_func
helper:
    push {r4, r5, r6, lr}
    movs r0, #1
    pop {r4, r5, r6, pc}
fail:
    movs r0, #0x61
    ldr r1, =MAILBOX
    str r0, [r1]
    b .
.ltorg
