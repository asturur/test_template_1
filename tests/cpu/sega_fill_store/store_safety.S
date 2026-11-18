    ldr sp, =0x80001800
    ldr r4, =0x80001010
    ldr r5, =0xa5a55a5a
    str r5, [r4]
    ldr r0, [r4]
    ldr r5, =0x1122beef
    ldr r6, =0x9988cafe
    mov r7, #0
    mov r8, #2
warm_low:
    strh r5, [r4, r7]
warm_high:
    strh r6, [r4, r8]
    ldr r0, [r4]
    ldr r1, =0xcafebeef
    cmp r0, r1
    bne fail

    // Use a distinct high half in the producing word. The store needs
    // the ordinary halfword duplication and the older load's value.
    ldr r9, =0x80001018
    ldr r5, =0xabcdef12
    str r5, [r9]
    ldr r0, [r4]
    ldr r5, [r9]
load_data:
    strh r5, [r4, r8]
    ldr r0, [r4]
    ldr r1, =0xef12beef
    cmp r0, r1
    bne fail

    ldr r9, =0x82012000
    ldr r6, =0x33445566
    str r6, [r9]
uncached_high:
    strh r5, [r9, r8]
    ldr r0, [r9]
    ldr r1, =0xef125566
    cmp r0, r1
    bne fail

    mov r11, #0
    ldr r0, [r4]
    ldr r9, =0x90000000
    ldr r2, =0x90000000
    mov r3, #5
    ldr r12, =after_translation
older_before_abort:
    strh r6, [r4, r7]
unmapped:
    strh r5, [r9, r8]
forbidden_translation:
    strh r5, [r4, r7]
    b fail
after_translation:

    // Cache the AP0 section while the domain is manager. Switch back
    // to client before trying a store to the resident line.
    mov r0, #3
    mcr p15, 0, r0, c3, c0, 0
    ldr r9, =0x81002000
    ldr r0, [r9]
    mov r0, #1
    mcr p15, 0, r0, c3, c0, 0
    ldr r2, =0x81002000
    mov r3, #13
    ldr r12, =after_permission
denied:
    strh r5, [r9, r8]
forbidden_permission:
    strh r5, [r4, r7]
    b fail
after_permission:

    mrc p15, 0, r0, c1, c0, 0
    orr r0, r0, #2
    mcr p15, 0, r0, c1, c0, 0
    mov r7, #1
    ldr r2, =0x80001011
    mov r3, #1
    ldr r12, =after_alignment
misaligned:
    strh r5, [r4, r7]
    mov r7, #0
forbidden_alignment:
    strh r5, [r4, r7]
    b fail
after_alignment:
    cmp r11, #3
    bne fail
    ldr r0, [r4]
    ldr r1, =0xef125566
    cmp r0, r1
    bne fail
    ldr r0, =0x50415353
    b finish
abort_handler:
    mrc p15, 0, r0, c6, c0, 0
    cmp r0, r2
    bne fail
    mrc p15, 0, r0, c5, c0, 0
    and r0, r0, #255
    cmp r0, r3
    bne fail
    add r11, r11, #1
    movs pc, r12
fail:
    ldr r0, =0x4641494c
finish:
    ldr r1, =0xf0000000
    str r0, [r1]
    b .
    .ltorg
