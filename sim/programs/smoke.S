.equ CUSTOM_SWI, 1
.include "sim/programs/common.inc"

reset_entry:
    ldr sp, =RAM + 0x10000
    ldr r4, =RAM
    ldr r0, =0x11223344
    str r0, [r4]
    ldrb r1, [r4]
    cmp r1, #0x44
    movne r0, #1
    bne finish
    mov r1, #0xaa
    strb r1, [r4, #1]
    ldr r1, [r4]
    ldr r2, =0x1122aa44
    cmp r1, r2
    movne r0, #2
    bne finish
    ldr r1, =0x55cc
    strh r1, [r4, #2]
    ldr r1, [r4]
    ldr r2, =0x55ccaa44
    cmp r1, r2
    movne r0, #3
    bne finish
    mvn r0, #0
    adds r0, r0, #1
    movcc r0, #4
    bcc finish
    cmp r0, #0
    movne r0, #5
    bne finish
    mov r0, #6
    bl triple
    cmp r0, #18
    movne r0, #6
    bne finish
    adr lr, back_in_arm
    ldr r3, =thumb_entry
    bx r3
back_in_arm:
    ldr r1, [r4]
    cmp r1, #12
    movne r0, #7
    bne finish
    mov r10, #0
    swi 0
    cmp r10, #0x5a
    movne r0, #8
    bne finish
    b pass
triple:
    add r0, r0, r0, lsl #1
    bx lr
swi_handler:
    mov r10, #0x5a
    movs pc, lr
.ltorg
.thumb
.thumb_func
thumb_entry:
    movs r0, #5
    adds r0, r0, #7
    str r0, [r4]
    bx lr
