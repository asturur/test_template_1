.equ CUSTOM_ABORT, 1
.include "sim/programs/common.inc"

// Verify the A bit with MMU off, MMU on/cache off, and MMU/cache on,
// including both uncacheable and cacheable RAM mappings.
// Faulting stores must leave memory untouched. Alignment must win over an
// invalid translation, and byte/normal aligned accesses must remain usable.
reset_entry:
    ldr sp, =RAM + 0x8000
    ldr r4, =RAM + 0x100
    ldr r0, =0x81223344
    str r0, [r4]
    ldr r0, =RAM + 0x10000
    mov r1, #4096
    mov r2, #0
clear_table:
    str r2, [r0], #4
    subs r1, r1, #1
    bne clear_table
    ldr r0, =RAM + 0x10000
    ldr r2, =0x00000c02
    str r2, [r0]
    ldr r1, =0x800 * 4
    ldr r2, =0x80000c02
    str r2, [r0, r1]
    mcr p15, 0, r0, c2, c0, 0
    mov r0, #3
    mcr p15, 0, r0, c3, c0, 0
    mov r8, #0
    mov r6, #0
phase:
    cmp r6, #3
    bne configure_control
    ldr r0, =RAM + 0x12000
    ldr r2, =0x80000c0e
    str r2, [r0]
    mov r0, #0
    mcr p15, 0, r0, c8, c7, 0
configure_control:
    mov r0, #2
    cmp r6, #0
    orrne r0, r0, #1
    cmp r6, #2
    orrhs r0, r0, #4
    mcr p15, 0, r0, c1, c0, 0
    mrc p15, 0, r1, c1, c0, 0
    tst r1, #2
    beq fail
    add r7, r4, #1
    adr r11, after_word_load
    ldr r5, [r7]
after_word_load:
    add r7, r4, #2
    adr r11, after_word_store2
    str r5, [r7]
after_word_store2:
    add r7, r4, #3
    adr r11, after_word_store3
    str r5, [r7]
after_word_store3:
    add r7, r4, #1
    adr r11, after_half_load
    ldrh r5, [r7]
after_half_load:
    adr r11, after_signed_half_load
    ldrsh r5, [r7]
after_signed_half_load:
    adr r11, after_half_store
    strh r5, [r7]
after_half_store:
    // 0x90000000 is deliberately absent from the page table and bus map.
    ldr r7, =0x90000001
    adr r11, after_unmapped_load
    ldr r5, [r7]
after_unmapped_load:
    adr r11, after_unmapped_store
    str r5, [r7]
after_unmapped_store:
    ldr r1, [r4]
    ldr r2, =0x81223344
    cmp r1, r2
    bne fail
    ldrb r1, [r4, #1]
    cmp r1, #0x33
    bne fail
    ldrh r1, [r4, #2]
    ldr r2, =0x8122
    cmp r1, r2
    bne fail
    ldrsh r1, [r4, #2]
    ldr r2, =0xffff8122
    cmp r1, r2
    bne fail
    ldrsb r1, [r4, #3]
    cmn r1, #127
    bne fail
    // Byte stores at odd addresses must not acquire alignment faults.
    mov r1, #0x81
    strb r1, [r4, #3]
    add r6, r6, #1
    cmp r6, #4
    blo phase
    cmp r8, #32
    bne fail
    // Disabling A restores the ARMv4 unaligned-load rotation behavior.
    mov r0, #0
    mcr p15, 0, r0, c1, c0, 0
    ldr r1, [r4, #1]
    ldr r2, =0x44812233
    cmp r1, r2
    bne fail
    ldr r12, =MAILBOX
    str r8, [r12, #4]
    b pass

data_abort:
    mrc p15, 0, r9, c5, c0, 0
    mrc p15, 0, r10, c6, c0, 0
    cmp r10, r7
    bne fail
    and r9, r9, #15
    cmp r9, #1
    beq fault_status_ok
    cmp r9, #3
    bne fail
fault_status_ok:
    add r12, r11, #4
    cmp lr, r12
    bne fail
    add r8, r8, #1
    subs pc, lr, #4
fail:
    mov r0, #0xa1
    b finish
.ltorg
