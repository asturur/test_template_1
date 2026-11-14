// Thumb LDMIA suppresses writeback when Rn is in its register list.
// Includes libGLES_CM's original C903/1845 pair captured during SPMark04.
.include "sim/programs/common.inc"
reset_entry:
    ldr sp, =RAM + 0x20000
    ldr r4, =RAM + 0x200
    ldr r0, =RAM + 0x1000
    str r0, [r4]
    mov r1, #0x40
    str r1, [r4, #4]
    adr r0, thumb_test + 1
    bx r0
.thumb
.thumb_func
thumb_test:
    movs r1, r4
    .hword 0xc903             // ldmia r1,{r0,r1}: loaded r1 must win.
    .hword 0x1845             // adds r5,r0,r1: original GLES pointer arithmetic.
    ldr r7, =MAILBOX + 4
    str r1, [r7]
    str r5, [r7]
    cmp r1, #0x40
    bne fail_loaded_base
    ldr r6, =RAM + 0x1040
    cmp r5, r6
    bne fail_pointer
    // Base first in the list, not last.
    movs r0, r4
    ldmia r0, {r0,r1}
    ldr r6, =RAM + 0x1000
    cmp r0, r6
    bne fail_base_first
    cmp r1, #0x40
    bne fail_base_first
    // Base absent: retain implicit writeback.
    movs r2, r4
    ldmia r2!, {r0,r1}
    movs r6, r4
    adds r6, #8
    cmp r2, r6
    bne fail_writeback
    // STMIA continues to write back (base excluded from list).
    movs r3, r4
    adds r3, #0x10
    stmia r3!, {r0,r1}
    movs r6, r4
    adds r6, #0x18
    cmp r3, r6
    bne fail_store
    // Return to ARM without changing the successful register values.
    ldr r0, =arm_pass
    bx r0
fail_loaded_base: movs r0, #0x11
    b thumb_fail
fail_pointer: movs r0, #0x12
    b thumb_fail
fail_base_first: movs r0, #0x13
    b thumb_fail
fail_writeback: movs r0, #0x14
    b thumb_fail
fail_store: movs r0, #0x15
thumb_fail:
    ldr r7, =MAILBOX
    str r0, [r7]
    b .
.balign 4
.arm
arm_pass:
    b pass
.ltorg
