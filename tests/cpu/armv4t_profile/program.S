.equ CUSTOM_SWI,1
.include "sim/programs/common.inc"
reset_entry:
    msr cpsr_c,#0xdb
    ldr sp,=RAM+0x1e000
    msr cpsr_c,#0xd3
    ldr sp,=RAM+0x1f000
    ldr r4,=RAM+0x1000
    ldr r0,=0x11223344
    str r0,[r4]
    ldr r5,=bad_target
    ldr r6,=cases
    ldr r7,=ARM_CASE_COUNT
    ldr r3,=user_tests
    ldr r8,=RAM+0x18000
    ldr r0,=0xe12fff1e
    str r0,[r8,#4]
    mov r10,#0
next_case:
    ldmia r6!,{r0-r2}
    str r0,[r8]
    add r11,r10,r2
    mov r2,r1
    ldr r0,=0x12345678
    ldr r1,=0x89abcdef
    msr cpsr_f,r2
    mrs r9,cpsr
    mov lr,pc
    bx r8
    mrs r2,cpsr
    eor r2,r2,r9
    tst r2,#0xf0000000
    movne r0,#0x71
    bne finish
    cmp r10,r11
    movne r0,#0x72
    bne finish
    ldr r2,=0x12345678
    cmp r0,r2
    movne r0,#0x73
    bne finish
    ldr r2,=0x89abcdef
    cmp r1,r2
    movne r0,#0x74
    bne finish
    ldr r0,[r4]
    ldr r2,=0x11223344
    cmp r0,r2
    movne r0,#0x75
    bne finish
    subs r7,r7,#1
    bne next_case
    bx r3
bad_target:
    mov r0,#0x76
    b finish
profile_undefined_handler:
    add r10,r10,#1
    movs pc,lr
swi_handler:
    mrs r12,spsr
    tst r12,#0x20
    addne r2,r2,#1
    movsne pc,lr
    b thumb_tests
user_tests:
    ldr r6,=user_cases
    ldr r7,=USER_CASE_COUNT
    ldr r3,=user_done
    msr cpsr_c,#0xd0
    b next_case
user_done:
    swi 0
    b bad_target
thumb_tests:
    mov r11,r10
    ldr r5,=bad_target
    ldr r0,=thumb_entry
    bx r0
.arm
.align 2
thumb_done:
    add r11,r11,#4
    cmp r10,r11
    movne r0,#0x78
    bne finish
    b legal_controls
.thumb
.thumb_func
thumb_entry:
    .hword 0x47a8 @ BLX r5, no branch or link
    .hword 0xbe00 @ BKPT, no prefetch abort
    .hword 0xe800 @ BLX immediate suffix, no branch
    .hword 0xde00 @ reserved conditional branch, no branch
    movs r2,#0
    swi 0
    adds r2,r2,#1
    cmp r2,#2
    beq 1f
    ldr r0,=bad_target
    bx r0
1:
    push {lr}
    bl thumb_legal_bl
    pop {r0}
    ldr r0,=thumb_done
    bx r0
.thumb_func
thumb_legal_bl:
    bx lr
.arm
.align 2
legal_controls:
    mov r0,#7
    mvn r1,#1
    mul r2,r0,r1
    cmn r2,#14
    movne r0,#0x79
    bne finish
    mov r3,#20
    mla r2,r0,r1,r3
    cmp r2,#6
    movne r0,#0x7a
    bne finish
    umull r2,r3,r0,r1
    cmn r2,#14
    cmpeq r3,#6
    movne r0,#0x7b
    bne finish
    smull r2,r3,r0,r1
    cmn r2,#14
    cmneq r3,#1
    movne r0,#0x7c
    bne finish
    mov r2,#14
    mov r3,#1
    umlal r2,r3,r0,r1
    cmp r2,#0
    cmpeq r3,#8
    movne r0,#0x7d
    bne finish
    mov r2,#14
    mov r3,#1
    smlal r2,r3,r0,r1
    cmp r2,#0
    cmpeq r3,#1
    movne r0,#0x7e
    bne finish
    mrc p15,0,r0,c0,c0,0
    ldr r1,=0x41129200
    cmp r0,r1
    movne r0,#0x7f
    bne finish
    b pass
.ltorg
cases:
.include "@CASES@"
