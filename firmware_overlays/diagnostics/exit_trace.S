// SPDX-License-Identifier: GPL-3.0-or-later
// NEM-4 diagnostic hooks. Original entry instruction is PUSH {lr}; replay
// it after logging and continue at entry+4. Calls retain their original ABI.
.syntax unified
.arm
.section .text, "ax"
.global exit_trace
exit_trace:
// Fixed veneers keep runtime hook offsets independent of body growth.
.global trace_exit, trace_panic, trace_kill, trace_terminate
.global trace_thread_panic, trace_descriptor_bounds
trace_exit: b body_exit
trace_panic: b body_panic
trace_kill: b body_kill
trace_terminate: b body_terminate
trace_thread_panic: b body_thread_panic
trace_descriptor_bounds: b body_descriptor_bounds
.global trace_wait_request
trace_wait_request: b body_wait_request
.macro hook label, format, resume, displaced_push=1, target_name=0
.global \label
\label:
    stmdb sp!, {r0-r3, r12, lr}
    sub sp, sp, #16
    add r12, sp, #40         // Original SP; never dereference caller memory.
    str r12, [sp, #4]
    mrs r12, cpsr
    str r12, [sp, #8]
    str r6, [sp, #12]        // Thread entry in the User::Exit return wrapper.
    ldr r12, [sp, #36]       // Original LR (including Thumb bit).
    str r12, [sp]
    .if \target_name
    ldr r12, [sp, #36]
    ldr r0, =0x5064dd55
    cmp r12, r0
    bne 8f
    ldr r0, [sp, #16]
    bl print_target_name
8:
    .endif
    ldr r0, =\format
    ldr r1, [sp, #16]        // Original r0.
    ldr r2, [sp, #20]        // Original r1.
    ldr r3, [sp, #24]        // Original r2 (RThread::Panic reason).
    bl debug_print
    .if \displaced_push == 0
    // Known Nokia.dsy caller: its PUSH {lr} is exactly at original SP.
    // Only inspect the observed twelve-byte message in mapped user RAM.
    ldr r12, [sp, #36]
    ldr r0, =0x50fc9a7b
    cmp r12, r0
    bne 9f
    ldr r12, [sp, #28]       // AtC's retained descriptor length.
    cmp r12, #12
    bne 9f
    ldr r0, [sp, #16]        // AtC's computed byte-data pointer.
    cmp r0, #0x00400000
    blo 9f
    cmp r0, #0x00ff0000
    bhs 9f
    ldr r12, [sp, #4]
    cmp r12, #0x00400000
    blo 9f
    cmp r12, #0x00ff0000
    bhs 9f
    ldr r12, [r12]           // Saved LR of the verified Nokia.dsy helper.
    str r12, [sp]
    ldr r1, [r0]
    ldr r2, [r0, #4]
    ldr r3, [r0, #8]
    ldr r0, =fmt_dsy_message
    bl debug_print
9:
    .endif
    ldr r12, [sp, #8]
    msr cpsr_f, r12
    add sp, sp, #16
    ldmia sp!, {r0-r3, r12, lr}
    .if \displaced_push
    stmdb sp!, {lr}          // Displaced original entry instruction.
    .endif
    b \resume
.endm
hook body_exit, fmt_exit, 0x503b471c
hook body_panic, fmt_panic, 0x503b46e4
hook body_kill, fmt_kill, 0x503b7fbc
hook body_terminate, fmt_terminate, 0x503b7fe8
hook body_thread_panic, fmt_thread_panic, 0x503b8014, 1, 1
// Only the failing descriptor-bounds path; no cost on successful accesses.
// Its displaced B keeps LR pointing to the actual descriptor caller.
hook body_descriptor_bounds, fmt_descriptor_bounds, 0x503b1b78, 0
// Slow-wait-only trace: the observed Phone wait consumed20 notifications.
// Inspect the current thread's own stack; no cross-process dereference.
body_wait_request:
    stmdb sp!, {r0-r3, r12, lr}
    sub sp, sp, #8
    mrs r12, cpsr
    str r12, [sp]
    cmp r4, #19
    bne 6f
    cmp r5, #0x00400000
    blo 6f
    cmp r5, #0x00ff0000
    bhs 6f
    add r12, sp, #32
    cmp r12, #0x00400000
    blo 6f
    cmp r12, #0x00ff0000
    bhs 6f
    ldr r0, [r12, #8]
    ldr r1, =0x503b76c0
    cmp r0, r1
    bne 6f
    ldr r0, [r12, #32]
    ldr r1, =0x503bad7c
    cmp r0, r1
    bne 6f
    cmp r7, #0x20
    beq 5f
    cmp r7, #0x24
    bne 6f
5:
    mov r1, r7
    ldr r2, [r12, #52]      // RSubSessionBase's direct caller.
    cmp r7, #0x24
    bne 3f
    ldr r0, =0x503df597     // Verified RFile::Flush return only.
    cmp r2, r0
    bne 6f
    ldr r3, [r12, #56]
    b 4f
3:
    ldr r0, =0x503df417     // Positional Write has32byte local frame.
    cmp r2, r0
    ldreq r3, [r12, #84]
    beq 4f
    ldr r0, =0x503df32d     // Non-positional Write has20byte frame.
    cmp r2, r0
    bne 6f
    ldr r3, [r12, #72]
4:
    ldr r0, =fmt_wait_request
    bl debug_print

6:
    ldr r12, [sp]
    msr cpsr_f, r12
    add sp, sp, #8
    ldmia sp!, {r0-r3, r12, lr}
    add r4, r4, #1          // Displaced loop instruction does not set flags.
    b 0x503b2480
// RHandleBase::FullName returns a520-byte TBuf<256> via hidden r0 output.
// r1 is the valid RThread handle pointer already used by ViewSrv.
print_target_name:
    stmdb sp!, {r4, lr}
    sub sp, sp, #520
    mov r4, r0
    mov r1, r0
    mov r0, sp
    bl full_name
    mov r1, sp
    ldr r0, =fmt_target_name
    bl debug_print
    mov r0, r4
    bl suspend_thread
    mov r0, r4
    bl request_count
    str r0, [sp, #508]
    mov r0, #0x30000000      // Empty TBuf8<256>, inline data at+8.
    str r0, [sp]
    mov r0, #256
    str r0, [sp, #4]
    mov r0, r4
    mov r1, sp
    bl thread_context
    str r0, [sp, #512]
    ldr r0, [sp]
    bic r0, r0, #0xf0000000
    str r0, [sp, #516]
    mov r0, r4
    bl resume_thread         // Balance suspension before any print/branch.
    ldr r0, =fmt_view_context
    ldr r1, [sp, #512]
    ldr r2, [sp, #516]
    ldr r3, [sp, #508]
    bl debug_print
    ldr r0, [sp, #516]
    cmp r0, #72
    blo 7f
    .irp n,0,1,2,3,4
    ldr r0, =fmt_ctx\n
    ldr r1, [sp, #(8+12*\n)]
    ldr r2, [sp, #(12+12*\n)]
    ldr r3, [sp, #(16+12*\n)]
    bl debug_print
    .endr
    ldr r0, =fmt_ctx5
    ldr r1, [sp, #68]
    ldr r2, [sp, #72]
    ldr r3, [sp, #76]
    bl debug_print
7:
    add sp, sp, #520
    ldmia sp!, {r4, lr}
    bx lr
.ltorg
.include "formats.inc"
