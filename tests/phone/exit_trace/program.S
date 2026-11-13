.syntax unified
.arm
.global _start
_start:
    ldr sp, =0x8000f000
    mov r5, #0
    ldr r6, =targets
again:
    ldr r12, [r6, r5, lsl #2]
    ldr r0, =0x11223344
    ldr r1, =0x55667788
    ldr r2, =0x99887766
    ldr r3, =0xaabbccdd
    ldr r4, =0x13579bdf
    cmp r5, r5
    adr lr, returned
    bx r12
returned:
    // Save returned values before any test clobbers them.
    stmdb sp!, {r0-r4, r12}
    mrs r0, cpsr
    and r0, r0, #0xf0000000
    cmp r0, #0x60000000
    bne fail
    ldr r0, [sp]
    ldr r1, =0x11223344
    cmp r0, r1
    bne fail
    ldr r0, [sp, #4]
    ldr r1, =0x55667788
    cmp r0, r1
    bne fail
    ldr r0, [sp, #8]
    ldr r1, =0x99887766
    cmp r0, r1
    bne fail
    ldr r0, [sp, #12]
    ldr r1, =0xaabbccdd
    cmp r0, r1
    bne fail
    ldr r0, [sp, #16]
    ldr r1, =0x13579bdf
    cmp r0, r1
    bne fail
    ldr r0, [sp, #20]
    ldr r1, [r6, r5, lsl #2]
    cmp r0, r1
    bne fail
    add sp, sp, #24
    ldr r0, =0x8000f000
    cmp sp, r0
    bne fail
    add r5, r5, #1
    cmp r5, #6
    bne again
    ldr r7, =thumb_test+1
    adr lr, finished_thumb
    bx r7
finished_thumb:
    mov r0, #7
    ldr r1, =0x80000000
    ldr r1, [r1]
    cmp r0, r1
    bne fail
    ldr r0, =0x50415353
    b stop
fail:
    mov r0, #1
stop:
    ldr r1, =0xf0000000
    str r0, [r1]
    b .
.balign 4
targets: .word 0x503b4718,0x503b46e0,0x503b7fb8,0x503b7fe4,0x503b8010,0x503a2b48
.thumb
.thumb_func
thumb_test:
    push {r4,lr}
    ldr r7, =0x503b4718
    ldr r0, =0x11223344
    ldr r1, =0x55667788
    ldr r2, =0x99887766
    bl thumb_jump
    ldr r2, =0x11223344
    cmp r0, r2
    bne thumb_fail
    ldr r2, =0x55667788
    cmp r1, r2
    bne thumb_fail
    pop {r4}
    pop {r3}
    bx r3
thumb_fail:
    ldr r3, =fail
    bx r3
thumb_jump:
    bx r7
.arm
// Checked RDebug::Print ABI stand-in. No format/string implementation is
// substituted into the experiment; this leaf only checks wrapper arguments.
.global test_debug
test_debug:
    ldr r12, [r0]
    and r12, r12, #0xf0000000
    cmp r12, #0x10000000
    bne fail
    ldr r0, [r0, #4]
    ldrh r0, [r0]
    cmp r0, #88
    bne fail
    ldr r12, =0x80000000
    ldr r0, [r12]
    add r0, r0, #1
    str r0, [r12]
    cmp r0, #6
    bhi check_thumb
    ldr r0, =returned
    ldr r12, [sp]
    cmp r0, r12
    bne fail
    ldr r0, [sp, #4]
    ldr r12, =0x8000f000
    cmp r0, r12
    bne fail
    b check_args
check_thumb:
    ldr r0, [sp]
    tst r0, #1
    beq fail
    ldr r0, [sp, #4]
    ldr r12, =0x8000eff8
    cmp r0, r12
    bne fail
check_args:
    ldr r0, =0x11223344
    cmp r0, r1
    bne fail
    ldr r0, =0x55667788
    cmp r0, r2
    bne fail
    ldr r0, =0x99887766
    cmp r0, r3
    bne fail
    ldr r0, [sp, #12]
    cmp r0, r6
    bne fail
    ldr r0, [sp, #4]
    cmp r0, #0x80000000
    blo fail
    ldr r0, [sp, #8]
    tst r0, #0x20
    bne fail
    // Volatile argument registers and condition flags may be destroyed.
    mvn r0, #0
    mov r1, #0
    mov r2, #0
    mov r3, #0
    mov r12, #0
    cmp r0, #0
    bx lr
