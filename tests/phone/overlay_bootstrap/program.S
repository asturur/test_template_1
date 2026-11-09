.syntax unified
.arm
.global _start
_start:
    ldr sp, =0x8000f000
    ldr r4, =0x12345678
    ldr r12, =0x50320860
    adr lr, initialized
    mov pc, r12
initialized:
    ldr r0, =0x80006bc4
    ldr r0, [r0]
    ldr r1, =0x80006f00
    cmp r0, r1
    bne fail
    ldr r5, =0x800004ac
    ldr r12, [r5]
    mov r0, #0
    adr lr, null_returned
    mov pc, r12
null_returned:
    cmp r0, #0
    bne fail
    ldr r1, =0x12345678
    cmp r4, r1
    bne fail
    ldr r0, =0x80002000
    ldr r1, =0xdeadc0de
    str r1, [r0, #4]
    ldr r12, [r5]
    adr lr, object_returned
    mov pc, r12
object_returned:
    ldr r1, =0x80002000
    cmp r0, r1
    bne fail
    ldr r2, [r1, #4]
    ldr r1, =0xdeadc0de
    cmp r1, r2
    bne fail
    ldr r0, =0x80006f64
    mov r1, #0
    ldr r2, =0x50324598
check_table:
    ldr r3, [r0, r1, lsl #2]
    cmp r1, #18
    beq next
    cmp r2, r3
    bne fail
next:
    add r1, r1, #1
    cmp r1, #128
    bne check_table
    ldr r6, [r0, #72]
    mov r3, #0
    adr lr, cleared_null
    mov pc, r6
cleared_null:
    ldr r3, =0x80003000
    mvn r0, #0
    str r0, [r3]
    adr lr, cleared_word
    mov pc, r6
cleared_word:
    ldr r1, [r3]
    cmp r1, #0
    bne fail
    mvn r0, #0
    str r0, [r3, #4]
    add r3, r3, #6
    adr lr, cleared_half
    mov pc, r6
cleared_half:
    sub r3, r3, #2
    ldr r0, [r3]
    ldr r1, =0xffff
    cmp r0, r1
    bne fail
    // Repeat initialization must return without rebuilding existing state.
    ldr r0, =0x80006f18
    mov r1, #99
    str r1, [r0]
    ldr r12, =0x50320860
    adr lr, repeated
    mov pc, r12
repeated:
    ldr r0, =0x80006f18
    ldr r1, [r0]
    cmp r1, #99
    bne fail
    ldr r0, =0xf0000000
    ldr r1, =0x50415353
    str r1, [r0]
1:  b 1b
fail:
    ldr r0, =0xf0000000
    ldr r1, =0x4641494c
    str r1, [r0]
2:  b 2b
