    .syntax unified
    .arch armv4t
    .text
    .thumb
    .balign 4
    .global nos_reset
    .thumb_func
nos_reset:
    bx pc
    nop
    .arm
    strb r5, [r0]
    stmdb sp!, {r1-r4, r12, lr}
    mrs r4, cpsr
    mov r0, #'N'
    mov r1, r5
    ldr r2, [sp, #32]
    bl emit
    msr cpsr_f, r4
    ldmia sp!, {r1-r4, r12, lr}
    ldr r0, =0x516cecf4
    bx lr

    .global plat_reset
plat_reset:
    stmdb sp!, {r1-r4, r12, lr}
    mrs r4, cpsr
    mov r1, r0
    mov r0, #'P'
    mov r2, lr
    bl emit
    msr cpsr_f, r4
    ldmia sp!, {r1-r4, r12, lr}
    mov r0, #0x20
    ldr pc, =0x50324dc8

    .thumb
    .balign 4
    .global nos_poweroff
    .thumb_func
nos_poweroff:
    bx pc
    nop
    .arm
    stmdb sp!, {r1-r4, r12, lr}
    mrs r2, cpsr
    stmdb sp!, {r2}
    mov r0, #'S'
    mov r1, r4
    ldr r2, [sp, #32]
    bl emit
    ldmia sp!, {r2}
    msr cpsr_f, r2
    ldmia sp!, {r1-r4, r12, lr}
    movs r0, #0
    strb r0, [r1]
    bx lr

    .global nos_rtc_call
nos_rtc_call:
    stmdb sp!, {r0-r4, r12, lr}
    mrs r4, cpsr
    ldr r2, [sp, #28]
    ldr r1, =0x514c2163
    cmp r1, r2
    bne 1f
    mov r0, #'R'
    mov r1, r12
    bl emit
1:
    msr cpsr_f, r4
    ldmia sp!, {r0-r4, r12, lr}
    ldr lr, =0x514a642c
    bx r12

    .thumb
    .balign 4
    .global nos_mtc
    .thumb_func
nos_mtc:
    bx pc
    nop
    .arm
    stmdb sp!, {r0-r4, r12, lr}
    mrs r4, cpsr
    and r1, r1, #255
    mov r0, r0, lsr #24
    orr r1, r1, r0, lsl #8
    mov r0, #'T'
    ldr r2, [sp, #32]
    bl emit
    msr cpsr_f, r4
    ldmia sp!, {r0-r4, r12, lr}
    movs r2, r0, lsr #24
    movs r1, r1, lsl #24
    bx lr

emit:
    stmdb sp!, {lr}
    mov r3, #0x59000000
    mov r12, #'@'
    strb r12, [r3]
    strb r0, [r3]
    mov r0, #':'
    strb r0, [r3]
    bl hex
    mov r0, #':'
    strb r0, [r3]
    mov r1, r2
    bl hex
    mov r0, #10
    strb r0, [r3]
    ldmia sp!, {pc}

hex:
    mov r12, #8
1:
    mov r0, r1, lsr #28
    cmp r0, #10
    addlo r0, r0, #'0'
    addhs r0, r0, #('a' - 10)
    strb r0, [r3]
    mov r1, r1, lsl #4
    subs r12, r12, #1
    bne 1b
    bx lr
    .ltorg
