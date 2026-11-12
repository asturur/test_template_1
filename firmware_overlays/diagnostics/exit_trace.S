// SPDX-License-Identifier: GPL-3.0-or-later
// NEM-4 diagnostic hooks. Original entry instruction is PUSH {lr}; replay
// it after logging and continue at entry+4. Calls retain their original ABI.
.syntax unified
.arm
.section .text, "ax"
.global exit_trace
exit_trace:
.macro hook label, format, resume
.global \label
\label:
    stmdb sp!, {r0-r3, r12, lr}
    sub sp, sp, #8
    add r12, sp, #32         // Original SP; never dereference caller memory.
    str r12, [sp]
    mrs r12, cpsr
    str r12, [sp, #4]
    ldr r0, =\format
    ldr r1, [sp, #8]         // Original r0.
    ldr r2, [sp, #12]        // Original r1.
    ldr r3, [sp, #28]        // Original LR (including Thumb bit).
    bl debug_print
    ldr r12, [sp, #4]
    msr cpsr_f, r12
    add sp, sp, #8
    ldmia sp!, {r0-r3, r12, lr}
    stmdb sp!, {lr}          // Displaced original entry instruction.
    b \resume
.endm
hook trace_exit, fmt_exit, 0x503b471c
hook trace_panic, fmt_panic, 0x503b46e4
hook trace_kill, fmt_kill, 0x503b7fbc
hook trace_terminate, fmt_terminate, 0x503b7fe8
hook trace_thread_panic, fmt_thread_panic, 0x503b8014
.ltorg
.include "formats.inc"
