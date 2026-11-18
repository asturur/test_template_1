.syntax unified
.cpu arm920t
.arm
.section .vectors,"ax"
.global _start
_start:
    b start
    b fail
    b fail
    b prefetch_abort
    b data_abort
    b fail
    b irq_handler
    b fiq_handler

start:
    mrc p15,0,r4,c0,c0,0
    ldr r5,=0x54029252
    cmp r4,r5
    bne fail
    mrc p15,0,r4,c0,c0,1
    ldr r5,=0x0514a14a
    cmp r4,r5
    bne fail

    ldr r8,=0x0a000000
    ldr r7,=0x0c000000
    ldr r4,=0x11223344
    str r4,[r8]
    mov r5,#0xaa
    add r6,r8,#1
    swpb r9,r5,[r6]
    cmp r9,#0x33
    bne fail
    ldr r9,[r8]
    ldr r4,=0x1122aa44
    cmp r9,r4
    bne fail

    mov r6,#0
    ldr r4,[r7,#32]
    cmp r6,#1
    bne fail
    mrc p15,0,r4,c5,c0,0
    and r4,r4,#15
    cmp r4,#8
    bne fail
    mrc p15,0,r4,c6,c0,0
    add r5,r7,#32
    cmp r4,r5
    bne fail

    msr cpsr_c,#0x13
    mov r5,#1
    str r5,[r7]
wait_irq:
    cmp r0,#1
    bne wait_irq
    str r5,[r7,#4]
wait_fiq:
    cmp r0,#2
    bne wait_fiq
    msr cpsr_c,#0xd3

    ldr r4,=0x0a004000
    ldr r5,=0x00000c0e
    str r5,[r4]
    ldr r5,=0x0a000c0e
    str r5,[r4,#0x280]
    ldr r5,=0x0c000c02
    str r5,[r4,#0x300]
    ldr r5,=0xf0000c02
    add r6,r4,#0x3c00
    str r5,[r6]
    mcr p15,0,r4,c2,c0,0
    mov r4,#1
    mcr p15,0,r4,c3,c0,0
    mcr p15,0,r4,c8,c7,0
    mrc p15,0,r4,c1,c0,0
    orr r4,r4,#0x1000
    orr r4,r4,#0x000d
    mcr p15,0,r4,c1,c0,0
    nop
    nop
    nop

    ldr r5,[r8]
    ldr r4,=0x1122aa44
    cmp r5,r4
    bne fail
    ldr r4,=0x55667788
    str r4,[r8]
    mcr p15,0,r8,c7,c10,1
    mcr p15,0,r8,c7,c6,1
    ldr r5,[r8]
    cmp r5,r4
    bne fail

    mov r6,#0
    mov r9,#0x0b000000
    ldr r5,[r9]
    cmp r6,#1
    bne fail
    mrc p15,0,r4,c5,c0,0
    and r4,r4,#15
    cmp r4,#5
    bne fail
    mrc p15,0,r4,c6,c0,0
    cmp r4,r9
    bne fail

    mov r6,#0
    adr r12,after_prefetch
    mov pc,#0x1000
after_prefetch:
    cmp r6,#2
    bne fail

    // Read-allocate both ways before dirtying them. With W enabled the
    // donor can post a store miss without installing a line.
    ldr r11,=0x0a008000
    add r12,r11,#0x4000
    mov r10,r11
warm_capacity:
    ldr r4,[r10]
    str r10,[r10]
    add r10,r10,#32
    cmp r10,r12
    bne warm_capacity
    mov r5,#1
    str r5,[r7,#8]
    mov r10,r11
check_capacity:
    ldr r4,[r10]
    cmp r4,r10
    bne fail
    add r10,r10,#32
    cmp r10,r12
    bne check_capacity
    mov r5,#0
    str r5,[r7,#8]
    add r10,r11,#0x1000
    mcr p15,0,r10,c7,c14,2          // Clean and invalidate upper-half set by index.

    ldr r0,=0x50415353
    b finish
fail:
    ldr r0,=0x4641494c
finish:
    mov r1,#0xf0000000
    str r0,[r1]
    b .

data_abort:
    mov r6,#1
    subs pc,lr,#4
prefetch_abort:
    mov r6,#2
    movs pc,r12
irq_handler:
    mov r0,#0
    str r0,[r7]
    mov r0,#1
    subs pc,lr,#4
fiq_handler:
    mov r0,#0
    str r0,[r7,#4]
    mov r0,#2
    subs pc,lr,#4
.ltorg

.org 0x1000
    // the responder rejects the third word of this cacheable instruction fill
    b fail
    nop
    nop
    nop
