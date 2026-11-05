.include "sim/programs/common.inc"
.section .text, "ax"
reset_entry:
    ldr r1, =RAM+0x1000
    ldr r2, =0x11223344
    str r2, [r1]
    ldr r3, =0xaabbccdd
    swp r4, r3, [r1]
    cmp r4, r2
    bne fail
    ldr r5, [r1]
    cmp r5, r3
    bne fail
    add r1, r1, #1
    mov r3, #0x5a
    swpb r4, r3, [r1]
    cmp r4, #0xcc
    bne fail
    sub r1, r1, #1
    ldr r5, [r1]
    ldr r6, =0xaabb5add
    cmp r5, r6
    bne fail
    @ Failed conditions must not generate a swap or acquire a bus lock.
    cmp r0, r0
    swpne r4, r3, [r1]
    ldr r5, [r1]
    cmp r5, r6
    bne fail
    b pass
fail:
    mov r0, #0xd2
    b finish
.ltorg
