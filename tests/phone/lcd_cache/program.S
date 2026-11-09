.syntax unified
.cpu arm920t
.arm
.global _start
_start: b start
 b fail
 b fail
 b fail
 b fail
 b fail
 b fail
 b fail
start:
 // Memory starts clear in this fixture. Build only the used section entries.
 ldr r4,=0x0a004000
 ldr r0,=0x00000c02
 str r0,[r4]
 ldr r0,=0x0a000c0e
 str r0,[r4,#0x280]       // cacheable, bufferable SDRAM
 ldr r0,=0x0a000c02
 str r0,[r4,#0x680]       // uncached SDRAM alias for success reporting
 ldr r0,=0x0c000c02
 str r0,[r4,#0x300]       // peripheral section
 ldr r0,=0x0c100c02
 str r0,[r4,#0x304]       // DMA/IRQ registers are in physical section0x0c1
 ldr r8,=0x0a000020
 ldr r1,=0x01110222
 str r1,[r8]             // visible physical SDRAM before MMU/cache enable
 mcr p15,0,r4,c2,c0,0
 mov r0,#1
 mcr p15,0,r0,c3,c0,0
 mrc p15,0,r0,c1,c0,0
 orr r0,r0,#5
 mcr p15,0,r0,c1,c0,0
 nop
 nop
 ldr r2,[r8]
 ldr r1,=0x03330444
 str r1,[r8]             // dirty data only in the write-back cache
 bl dma
 mcr p15,0,r8,c7,c10,1  // clean data line by MVA
 mov r0,#0
 mcr p15,0,r0,c7,c10,4  // drain write buffer before DMA
 bl dma
 ldr r0,=0x50415353
 b finish
dma:
 ldr r0,=0x0c120354
 ldr r1,=0x0a000020
 str r1,[r0]
 ldr r0,=0x0c120360
 ldr r1,=0x10121208
 str r1,[r0]
 ldr r0,=0x0c12036c
 mov r1,#0
 str r1,[r0]
 ldr r0,=0x0c120348
 mov r1,#2
 str r1,[r0]
 ldr r0,=0x0c120110
1: ldr r1,[r0]
 tst r1,#0x80
 beq 1b
 ldr r0,=0x0c12010c
 mov r1,#0x80
 str r1,[r0]
 bx lr
fail: mov r0,#1
finish:
 ldr r1,=0x1a000100
 str r0,[r1]
2: b 2b
.ltorg
