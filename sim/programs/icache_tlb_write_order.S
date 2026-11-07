.include "sim/programs/common.inc"
.equ TABLE, RAM + 0x4000
reset_entry:
    ldr r4, =TABLE
    ldr r0, =0x00000c0e      @ cacheable ROM
    str r0, [r4]
    ldr r0, =0x80000c06      @ NCB: buffered table writes
    add r5, r4, #0x1800
    str r0, [r5]
    ldr r0, =0x80000c02      @ uncached RAM alias
    add r5, r4, #0x1c00
    str r0, [r5]
    ldr r0, =0xf0000c02
    add r5, r4, #0x3c00
    str r0, [r5]
    mcr p15, 0, r4, c2, c0, 0
    mov r0, #1
    mcr p15, 0, r0, c3, c0, 0
    mrc p15, 0, r0, c1, c0, 0
    orr r0, r0, #5
    orr r0, r0, #0x1000
    mcr p15, 0, r0, c1, c0, 0
    nop
    nop
    ldr r7, =0xe3a0002a      @ mov r0, #42
    ldr r9, =0x70030100
    str r7, [r9]
    ldr r7, =0xe12fff1e      @ bx lr
    str r7, [r9, #4]
    ldr r1, =0x80000c0e      @ cacheable section mapping VA 300 -> RAM
    ldr r8, =0x30030100
    ldr r9, =0x60004c00      @ write L1 descriptor through buffered alias
    @ Keep sequential speculation resident while the descriptor write waits.
    @ Otherwise an unrelated cold linefill drains the write before the walk.
    adr r0, buffered_branch
    mcr p15, 0, r0, c7, c13, 1
    add r0, r0, #32
    mcr p15, 0, r0, c7, c13, 1
    add r0, r0, #32
    mcr p15, 0, r0, c7, c13, 1
    add r0, r0, #32
    mcr p15, 0, r0, c7, c13, 1
    .balign 32
buffered_branch:
    str r1, [r9]             @ buffered write may still be outstanding
    @ Let the store enter the buffer before requesting the instruction walk.
    @ The slow bus keeps it pending; the test still requires actual overlap.
    .rept 4
    nop
    .endr
    mov lr, pc
    bx r8                    @ instruction TLB walk must see new descriptor
    cmp r0, #42
    movne r0, #0xd7
    bne finish
    b pass
.ltorg
