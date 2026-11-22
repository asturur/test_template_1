.syntax unified
.arm
.text
.global _start
_start:
    mrc p15, 0, r4, c1, c0, 0
    bic r4, r4, #1
    mcr p15, 0, r4, c1, c0, 0

    ldr r0, =0x0c030000
    ldr r1, =0x5adc2918
    str r1, [r0]
    ldr r2, [r0]
    cmp r1, r2
    bne fail
    ldr r0, =0x0c03fffc
    strh r1, [r0, #2]
    ldrb r2, [r0, #3]
    cmp r2, #0x29
    bne fail

    ldr r0, =0x0c1003f0
    str r1, [r0]
    ldr r2, [r0]
    cmp r1, r2
    bne fail
    ldr r0, =0x0c10fffc
    strh r1, [r0, #2]
    ldrb r2, [r0, #3]
    cmp r2, #0x29
    bne fail

    ldr r0, =0x0c030008
    ldr r1, =0xe12fff1e /* BX LR, executed using the upload RAM. */
    str r1, [r0]
    mov lr, pc
    bx r0
    ldr r0, =0x0c1003f8
    str r1, [r0]
    mov lr, pc
    bx r0

    ldr r1, =0x50415353
    b finish
fail:
    ldr r1, =0x4641494c
finish:
    ldr r0, =0x0a021000
    str r1, [r0]
forever:
    b forever
