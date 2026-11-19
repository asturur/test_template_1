    .macro begin_phase number
    mov r5,#\number
    str r5,[r7,#12]
    .endm
    .macro end_phase
    mov r5,#0
    str r5,[r7,#12]
    .endm

    begin_phase 1                  // Clean the remaining resident dirty lines.
    mcr p15,0,r11,c7,c10,0
    end_phase
    begin_phase 2                  // Scan the now-clean cache.
    mcr p15,0,r11,c7,c10,0
    end_phase

    add r10,r11,#0x40
    ldr r4,[r10]
    mov r4,#0x33
    strb r4,[r10,#3]
    begin_phase 3                  // Low dirty half, newer high backing half.
    mcr p15,0,r10,c7,c10,1
    end_phase
    mov r4,#0x66
    strb r4,[r10,#19]
    begin_phase 4                  // High dirty half, newer low backing half.
    mcr p15,0,r10,c7,c10,1
    end_phase
    mov r4,#0x44
    strb r4,[r10,#3]
    mov r4,#0x55
    strb r4,[r10,#19]
    begin_phase 5                  // Both halves dirty, with adjacent stores.
    mcr p15,0,r10,c7,c10,1
    end_phase

    mcr p15,0,r11,c7,c6,0
    ldr r12,=(16384 / ASSOC_WAYS)
    add r10,r11,r12
    sub r10,r10,#32                // Highest set for this geometry.
    ldr r4,[r10,#-32]              // A resident line from the neighboring set.
    .macro data_set phase
    begin_phase \phase
    mov r6,r10
    mov r9,#ASSOC_WAYS
1:  ldr r4,[r6]
    cmp r4,r6
    bne fail
    add r6,r6,r12
    subs r9,r9,#1
    bne 1b
    end_phase
    .endm
    data_set 6                     // Demand exactly W conflicting lines.
    data_set 7                     // All W hit on the second pass.
    begin_phase 8
    ldr r4,[r10,#-32]
    add r6,r10,#0x4000
    ldr r4,[r6]                    // Overflow the set by one line.
    ldr r4,[r10]                   // First line was selected by LRU/PLRU.
    end_phase

    // Load ordinary ARM functions into the same set and publish their
    // instructions to backing RAM before the I-cache sees them.
    mov r6,r10
    mov r9,#1
    ldr r4,=0xe12fff1e             // bx lr
    ldr r3,=0xe3a00000             // mov r0,#0
9:  ldr r5,[r6]
    orr r5,r9,r3                   // mov r0,#ordinal
    str r5,[r6]
    str r4,[r6,#4]
    add r6,r6,r12
    add r9,r9,#1
    cmp r9,#(ASSOC_WAYS+1)
    bls 9b
    mcr p15,0,r11,c7,c10,0
    b 3f
    .balign 256
3:
    mcr p15,0,r11,c7,c5,0

    .macro instruction_set phase
    b 3f
    .balign 256                    // Keep the loop out of the tested set.
3:
    begin_phase \phase
    mov r6,r10
    mov r9,#1
2:  mov lr,pc
    bx r6
    cmp r0,r9
    bne fail
    add r6,r6,r12
    add r9,r9,#1
    cmp r9,#ASSOC_WAYS
    bls 2b
    end_phase
    .endm
    instruction_set 9
    instruction_set 10
    begin_phase 11
    add r6,r10,#0x4000
    mov lr,pc
    bx r6
    cmp r0,#(ASSOC_WAYS+1)
    bne fail
    mov lr,pc
    bx r10
    cmp r0,#1
    bne fail
    end_phase
