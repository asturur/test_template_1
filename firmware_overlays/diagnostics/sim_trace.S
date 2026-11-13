// SPDX-License-Identifier: GPL-3.0-or-later
// Native NEM4 fallback observation; no synthetic replies or state changes.
.syntax unified
.arm
.section .text,"ax"
.global sim_trace
sim_trace:
    b nonserving
    b starting
.macro entry label, kind, original
\label:
    stmdb sp!, {r0-r7, r12, lr}
    mrs r6, cpsr
    ldr r7, =0x59000000      // Existing kernel debug59 VA, physical0DE00000.
    .irp c,89,32,83,73,77,32,\kind,32
    mov r0, #\c
    strb r0, [r7]
    .endr
    ldr r3, [sp, #12]       // Original native method body pointer (r3).
    ldrb r0, [r3]
    ldrb r1, [r3, #1]
    orr r0, r0, r1, lsl #8
    ldrb r1, [r3, #2]
    orr r0, r0, r1, lsl #16
    ldr r1, =0x800ca78c     // Original SIM_Server state byte.
    ldrb r1, [r1]
    orr r0, r0, r1, lsl #24
    bl hex_word
    mov r0, #10
    strb r0, [r7]
    msr cpsr_f, r6
    ldmia sp!, {r0-r7, r12, lr}
    // IP is ABI scratch; original method does not consume its entry value.
    ldr r12, =\original
    bx r12
.endm
entry nonserving, 78, 0x5165ed25
entry starting, 80, 0x5165ecd1
hex_word:
    mov r2, #28
1:
    mov r1, r0, lsr r2
    and r1, r1, #15
    cmp r1, #10
    addlo r1, r1, #48
    addhs r1, r1, #87
    strb r1, [r7]
    subs r2, r2, #4
    bpl 1b
    bx lr
.ltorg
