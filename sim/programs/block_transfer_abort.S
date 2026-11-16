.equ CUSTOM_ABORT, 1
.include "sim/programs/common.inc"
#ifndef BLOCK_MODE
#define BLOCK_MODE 0
#endif
#ifndef FAULT_WORD
#define FAULT_WORD 0
#endif
.equ DATA, RAM+0x1000
reset_entry:
    // Real external aborts with no cache/write buffering: every transfer must
    // keep the architectural base unchanged until the whole block succeeds.
    mrc p15,0,r8,c1,c0,0
    bic r8,r8,#0x1000
    bic r8,r8,#0x300
    bic r8,r8,#15
    mcr p15,0,r8,c1,c0,0
    ldr r9,=DATA
#ifndef BLOCK_STORE
    mov r8,#0x20
    str r8,[r9,#0]
    add r8,r8,#1
    str r8,[r9,#4]
    add r8,r8,#1
    str r8,[r9,#8]
    add r8,r8,#1
    str r8,[r9,#12]
    add r8,r8,#1
    str r8,[r9,#16]
    add r8,r8,#1
    str r8,[r9,#20]
    add r8,r8,#1
    str r8,[r9,#24]
    add r8,r8,#1
    str r8,[r9,#28]
#endif
    mov r0,#0x10
    mov r1,#0x11
    mov r2,#0x12
    mov r3,#0x13
    mov r4,#0x14
    mov r5,#0x15
    mov r6,#0x16
    mov r7,#0x17
#if BLOCK_MODE == 0
    ldr r10,=DATA
#elif BLOCK_MODE == 1
    ldr r10,=DATA-4
#elif BLOCK_MODE == 2
    ldr r10,=DATA+28
#else
    ldr r10,=DATA+32
#endif
    mov r11,r10
block_instruction:
#ifdef BLOCK_STORE
#if BLOCK_MODE == 0
    stmia r10!,{r0-r7}
#elif BLOCK_MODE == 1
    stmib r10!,{r0-r7}
#elif BLOCK_MODE == 2
    stmda r10!,{r0-r7}
#else
    stmdb r10!,{r0-r7}
#endif
#else
#if BLOCK_MODE == 0
    ldmia r10!,{r0-r7}
#elif BLOCK_MODE == 1
    ldmib r10!,{r0-r7}
#elif BLOCK_MODE == 2
    ldmda r10!,{r0-r7}
#else
    ldmdb r10!,{r0-r7}
#endif
#endif
    mov r0,#0x81
    b finish

data_abort:
    cmp r10,r11
    movne r0,#0x82
    bne finish
    ldr r8,=block_instruction+8
    cmp lr,r8
    movne r0,#0x83
    bne finish
    mrc p15,0,r8,c6,c0,0
    ldr r9,=DATA+FAULT_WORD*4
    cmp r8,r9
    movne r0,#0x84
    bne finish
#ifndef BLOCK_STORE
    .macro check_loaded reg, index
    .if \index < FAULT_WORD
        cmp \reg,#0x20+\index
    .else
        cmp \reg,#0x10+\index
    .endif
        movne r0,#0x85
        bne finish
    .endm
    check_loaded r0,0
    check_loaded r1,1
    check_loaded r2,2
    check_loaded r3,3
    check_loaded r4,4
    check_loaded r5,5
    check_loaded r6,6
    check_loaded r7,7
#else
    ldr r9,=DATA
    .set word,0
    .rept 8
        ldr r8,[r9,#word*4]
        .if word < FAULT_WORD
            cmp r8,#0x10+word
        .else
            cmp r8,#0
        .endif
        movne r0,#0x86
        bne finish
        .set word,word+1
    .endr
#endif
    b pass
.ltorg
