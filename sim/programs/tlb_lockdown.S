.equ CUSTOM_ABORT, 1
.include "sim/programs/common.inc"
.equ TABLE, RAM+0x4000
reset_entry:
    ldr sp, =RAM+0x20000
    mrc p15,0,r0,c10,c0,0
    cmp r0,#0
    bne fail
    mrc p15,0,r0,c10,c0,1
    cmp r0,#0
    bne fail
    ldr r0,=0x08300001
    mcr p15,0,r0,c10,c0,0
    mrc p15,0,r1,c10,c0,0
    cmp r0,r1
    bne fail
    mrc p15,0,r1,c10,c0,1
    cmp r1,#0
    bne fail
    ldr r0,=0x10600001
    mcr p15,0,r0,c10,c0,1
    mrc p15,0,r2,c10,c0,1
    cmp r0,r2
    bne fail
    mrc p15,0,r2,c10,c0,0
    ldr r0,=0x08300001
    cmp r0,r2
    bne fail
    mov r0,#0
    mcr p15,0,r0,c10,c0,0
    mcr p15,0,r0,c10,c0,1
    ldr r4,=TABLE
    mov r1,#4096
1:  str r0,[r4],#4
    subs r1,r1,#1
    bne 1b
    ldr r4,=TABLE
    ldr r0,=0x00000c02
    str r0,[r4]
    ldr r0,=0x80000c02
    add r5,r4,#0x2000
    str r0,[r5]
    add r5,r4,#0x400
    str r0,[r5]              @ VA10000000 -> RAM section
    ldr r0,=0xf0000c02
    add r6,r4,#0x3c00
    str r0,[r6]
    ldr r3,=0x10001000
    ldr r6,=RAM+0x1000
    mov r0,#0x5a
    str r0,[r6]
    mcr p15,0,r4,c2,c0,0
    mov r0,#1
    mcr p15,0,r0,c3,c0,0
    mrc p15,0,r0,c1,c0,0
    orr r0,r0,#1
    mcr p15,0,r0,c1,c0,0
    mov r0,#0
    mcr p15,0,r0,c8,c6,0
    mov r0,#1
    mcr p15,0,r0,c10,c0,0     @ Preserve next entry at slot0.
    ldr r6,[r3]
    cmp r6,#0x5a
    bne fail
    mrc p15,0,r0,c10,c0,0
    ldr r1,=0x00100001
    cmp r0,r1
    bne fail
    ldr r0,=0x04100000
    mcr p15,0,r0,c10,c0,0     @ Lock slot0; replace from1 onward.
    mov r0,#0
    str r0,[r5]              @ Remove mapping from actual page table.
    mcr p15,0,r0,c7,c10,4
    mcr p15,0,r0,c8,c6,0     @ Preserved slot0 must survive all-invalidate.
    ldr r6,[r3]
    cmp r6,#0x5a
    bne fail
    mcr p15,0,r3,c8,c6,1     @ MVA-invalidate must remove preserved slot0.
    ldr r6,[r3]
fail:
    mov r0,#0xd1
    b finish
data_abort:
    mrc p15,0,r0,c5,c0,0
    and r0,r0,#15
    cmp r0,#5
    bne fail
    mrc p15,0,r0,c6,c0,0
    cmp r0,r3
    bne fail
    b pass
.ltorg
