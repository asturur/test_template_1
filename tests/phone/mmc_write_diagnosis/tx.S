 // Authored synthetic CMD24/TX-DMA probe; no phone firmware or user data.
 mov r12,#9
 ldr r0,=0x0a002000
 mov r5,#0
 mov r6,#0x69
fill_tx:
 strb r6,[r0,r5]
 add r6,r6,#37
 add r5,r5,#1
 cmp r5,#512
 blo fill_tx
 mov r0,#24
 mov r1,#1536
 mov r2,#21
 bl command
 bl response_ok
 put r9,4,1
 put r9,0x14,0x0a002000
 put r9,0x18,1
 put r9,0x1c,32
 put r9,0x20,0x10120624
 put r9,0x24,0
 put r9,0x28,8
 put r9,0x2c,511
 put r9,8,2
write_dma_wait:
 ldr r4,[r9,#8]
 cmp r4,#0
 bne write_dma_wait
write_card_wait:
 ldr r4,[r8,#0x18]
 tst r4,#4
 bne write_card_wait
 ldr r3,=0x4e3
 tst r4,r3
 bne fail
 put r9,4,0
 // Read back through actual card/host byte FIFO after backing completion.
 mov r12,#10
 mov r0,#17
 mov r1,#1536
 mov r2,#33
 bl command
 bl response_ok
 mov r5,#0
 mov r6,#0x69
write_verify:
 ldrb r4,[r8,#0x24]
 and r3,r6,#255
 cmp r4,r3
 bne fail
 add r6,r6,#37
 add r5,r5,#1
 cmp r5,#512
 blo write_verify
write_read_idle:
 ldr r4,[r8,#0x18]
 tst r4,#4
 bne write_read_idle
