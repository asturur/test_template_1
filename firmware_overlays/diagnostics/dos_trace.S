// SPDX-License-Identifier: GPL-3.0-or-later
.syntax unified
.thumb
.section .text,"ax"
.global dos_trace
.thumb_func
dos_trace:
    bx pc
    nop
.arm
    stmdb sp!, {r0-r3, r12, lr}
    sub sp, sp, #8
    mrs r12, cpsr
    str r12, [sp]
    ldr r1, [sp, #12]
    ldr r2, [sp, #16]       // Native wrappers pass a valid4byte stack value.
    ldr r2, [r2]
    ldr r0, =format
    bl debug_print
    ldr r12, [sp]
    msr cpsr_f, r12
    add sp, sp, #8
    ldmia sp!, {r0-r3, r12, lr}
    ldr r12, =0x50fc19bd     // Original DOS event publication; no value changes.
    bx r12
.balign 4
format:
    .word 0x10000000+26, message
message:
    .hword 68,32,69,86,69,78,84,32,105,100,61,37,48,56,120,32,118,97,108,117,101,61,37,48,56,120
.balign 4
.ltorg
