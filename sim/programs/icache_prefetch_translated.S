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
    ldr r0, =0x00000c02
    str r0, [r4, #0x400]      @ run driver code in uncached high alias
    ldr r5, =TABLE + 0x1400
    ldr r0, =0x00000c0e      @ VA 50000000 maps to physical ROM
    str r0, [r5]
    mcr p15, 0, r4, c2, c0, 0
    mov r0, #1
    mcr p15, 0, r0, c3, c0, 0
    mrc p15, 0, r0, c1, c0, 0
    orr r0, r0, #5
    orr r0, r0, #0x1000
    orr r0, r0, #0x4000      @ ARM920T round-robin replacement
    mcr p15, 0, r0, c1, c0, 0
    nop
    nop
    adr r0, high_code
    add r0, r0, #0x10000000
    bx r0
high_code:
    mov r0, #0
    mcr p15, 0, r0, c9, c0, 1 @ set I-cache victim to way zero
    ldr r4, =icache_function_a + 0x50000000
    add r0, r4, #3           @ manual permits unaligned MVA
    mcr p15, 0, r0, c7, c13, 1 @ prefetch the line into way zero
    mcr p15, 0, r0, c7, c13, 1 @ a resident line must not be fetched twice
    mov r0, #0x04000000
    mcr p15, 0, r0, c9, c0, 1 @ lock way zero
    mov r5, r4
    add r5, r5, #0x100
    mov r6, #64
2:  mov lr, pc
    bx r5
    add r5, r5, #0x100
    subs r6, r6, #1
    bne 2b
    mov lr, pc
    bx r4
    b pass
.ltorg
.org 0x2000
.global icache_function_a
icache_function_a:
    bx lr
.rept 64
    .space 252
    bx lr
.endr
