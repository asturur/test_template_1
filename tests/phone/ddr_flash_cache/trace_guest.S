.syntax unified
.cpu arm920t
.arm
.section .vectors,"ax"
.global _start
_start:
    b start
    .rept 7
    b fail
    .endr

start:
    // Read both 32-bit halves of each beat with the MMU/cache off.
    .irp index,0,1,2,3,4,5,6,7
    ldr r0,=scalar\index
    ldr r2,=(0x5aca4ab0 + \index)
    ldr r1,[r0]
    cmp r1,r2
    bne fail
    ldr r1,[r0]
    cmp r1,r2
    bne fail
    .endr

    ldr r4,=0x0a004000
    ldr r0,=0x00000c0e   // Cacheable ROM section.
    str r0,[r4]
    ldr r0,=0x0a000c02   // Uncached RAM for the result.
    str r0,[r4,#0x280]
    mcr p15,0,r4,c2,c0,0
    mov r0,#1
    mcr p15,0,r0,c3,c0,0
    mrc p15,0,r0,c1,c0,0
    orr r0,r0,#1
    orr r0,r0,#0x1000
    mcr p15,0,r0,c1,c0,0
    nop
    nop

    // Enter eight distinct lines at every word offset.
    .irp index,0,1,2,3,4,5,6,7
    ldr r3,=func\index
    mov lr,pc
    bx r3
    cmp r1,#(0x41 + \index)
    bne fail
    // Run the same function again. The CPU I-cache must now own it.
    mov lr,pc
    bx r3
    cmp r1,#(0x41 + \index)
    bne fail
    .endr

    ldr r0,=0x50415353
    b complete
fail:
    ldr r0,=0x4641494c
complete:
    ldr r2,=0x0a000100
    str r0,[r2]
1:  b 1b
    .ltorg

    .irp index,0,1,2,3,4,5,6,7
    .org (0x5000 + 64 * \index + 4 * \index)
scalar\index:
    .word (0x5aca4ab0 + \index)
    .endr

    .irp index,0,1,2,3,4,5,6,7
    .org (0x6000 + 64 * \index)
    .rept \index
    nop
    .endr
func\index:
    mov r1,#(0x41 + \index)
    bx lr
    .endr
