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
    ldr r0, =0x80000c02
    str r0, [r4, #0x800]
    ldr r0, =0xf0000c02
    add r5, r4, #0x3c00
    str r0, [r5]
    mcr p15, 0, r4, c2, c0, 0
    mov r0, #1
    mcr p15, 0, r0, c3, c0, 0
    mrc p15, 0, r0, c1, c0, 0
    bic r0, r0, #2
    orr r0, r0, #5
    orr r0, r0, #0x1000
    mcr p15, 0, r0, c1, c0, 0
    nop
    nop
    adr r4, data_lines
    ldr r7, =0x80ff7f01
    mov r8, #0
    mov r6, #0
    mov r11, #0
prepare:
    lsl r10, r6, #3
    mov r5, r7, lsr r10
    cmp r8, #2
    blo expect_byte
    cmp r8, #4
    beq expect_word
    lsl r5, r5, #16
    cmp r8, #3
    moveq r5, r5, asr #16
    movne r5, r5, lsr #16
    b ready
expect_byte:
    and r5, r5, #255
    cmp r8, #1
    lsleq r5, r5, #24
    asreq r5, r5, #24
    b ready
expect_word:
    mov r5, r7, ror r10
ready:
    mov r9, #0
repeat:
    cmp r8, #0
    beq load_ub
    cmp r8, #1
    beq load_sb
    cmp r8, #2
    beq load_uh
    cmp r8, #3
    beq load_sh
    ldr r1, [r4, r6]
    mov r2, r1
    b check
load_ub:
    ldrb r1, [r4, r6]
    mov r2, r1
    b check
load_sb:
    ldrsb r1, [r4, r6]
    mov r2, r1
    b check
load_uh:
    ldrh r1, [r4, r6]
    mov r2, r1
    b check
load_sh:
    ldrsh r1, [r4, r6]
    mov r2, r1
check:
    cmp r2, r5
    bne failed
    add r11, r11, #1
    add r9, r9, #1
    cmp r9, #2
    blo repeat
    add r4, r4, #32
    cmp r8, #2
    blo byte_step
    cmp r8, #4
    beq byte_step
    add r6, r6, #2
    b next_lane
byte_step:
    add r6, r6, #1
next_lane:
    cmp r6, #4
    blo prepare
    mov r6, #0
    add r8, r8, #1
    cmp r8, #5
    blo prepare
    cmp r11, #32
    bne failed
    // The real firmware pattern: two adjacent byte loads, followed by
    // an ORR that consumes the first miss's asynchronous completion.
    adr r4, paired_line
    ldrb r1, [r4]
    ldrb r2, [r4, #1]
    orr r2, r1, r2, lsl #8
    mov r5, #0x3b
    cmp r2, r5
    bne failed
    b pass
failed:
    ldr r12, =MAILBOX
    str r8, [r12, #4]
    str r6, [r12, #8]
    str r1, [r12, #12]
    str r2, [r12, #16]
    str r5, [r12, #20]
    mov r0, #0xef
    b finish
.ltorg
.balign 32
data_lines:
.rept 16
    .word 0x80ff7f01
    .space 28
.endr

.balign 32
paired_line:
    .word 0x0026003b
    .space 28
