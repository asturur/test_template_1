// Self-contained reproduction of the early timer setup's cached return.
.include "sim/programs/common.inc"
.equ PRAM, 0x0a000000
.equ TABLE, PRAM + 0x4000
reset_entry:
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
    add r5, r4, #0x1400
    str r0, [r5]
    ldr r0, =0x0a000c02
    add r5, r4, #0x2000
    str r0, [r5]
    ldr r0, =0x0c100c02
    ldr r5, =TABLE + 0x581*4
    str r0, [r5]
    ldr r0, =0x0ba00c02
    str r0, [r4, #0x2e8]
    mov r8, #5
    b train_alias
after_training:
    mcr p15, 0, r4, c2, c0, 0
    mov r0, #1
    mcr p15, 0, r0, c3, c0, 0
    mrc p15, 0, r0, c1, c0, 0
    bic r0, r0, #2
    orr r0, r0, #5
    orr r0, r0, #0x1000
    mcr p15, 0, r0, c1, c0, 0
    ldr sp, =0x80020000
    ldr r0, =0x200000d3
    msr cpsr_fsxc, r0
    ldr r4, =call_site + 0x50000000
    bx r4
.ltorg
.org 0x810 // .text follows the 32-byte vector section: file offset 0x830.
    .word 2, 1
    .word 0, 0x4000, 1, 0
    .word PRAM, 0x01000000, 2, 0
.org 0x2a28
train_alias:
    subs r8, r8, #1
    bne train_alias // 0x2a4c aliases the BTB index of return 0x324c.
    b after_training
.org 0x31e0
helper:
    ldr r1, [pc, #0x48]
    ldr r2, [pc, #0x48]
    mov r3, #2
    str r3, [r2]
    ldr r3, [pc, #0x40]
    str r1, [r3]
    ldr r3, [pc, #0x3c]
    str r1, [r3]
    ldr r2, [pc, #0x38]
    mov r3, #0
    str r3, [r2]
    ldr r2, [pc, #0x30]
    mov r3, #1
    str r3, [r2]
    stmdb sp!, {r1}
    mrs r1, cpsr
    bic r1, r1, #0x80
    msr cpsr_fsxc, r1
    ldmia sp!, {r1}
    mov pc, lr
    .word 0x0115b5c0, 0x58120a04, 0x58120a18, 0x58120a10, 0x58120a08, 0x58120108
.org 0x3598
call_site:
    blne helper
    ldr r0, =0x0bad0000
    str r0, [r0]
    b .
.ltorg
.org 0x3fe0
