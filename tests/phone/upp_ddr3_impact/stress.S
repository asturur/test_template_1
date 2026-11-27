 // Read/copy/partial-write round trips while LCD DMA and PCM are active.
 // Exercise first unclaimed NOS word groups and first upload page separately.
 mov r12,#80
 ldr r0,=0x0c030100
 ldr r1,=0x0c100400
 ldr r2,=0x41223344
 ldr r3,=0x55667788
 mov r4,#128
 mov r5,#0x7f
 mov r6,#0x55
 mov r7,#0x7700
 orr r7,r7,#0x88
upp_round_trip:
 ldr r10,[r0]
 cmp r10,#0
 bne fail
 ldr r10,[r1]
 cmp r10,#0
 bne fail
 str r2,[r0]
 str r3,[r1]
 strb r5,[r0,#1]
 strh r7,[r1,#2]
 ldr r10,[r0],#4
 eor r10,r10,r2
 cmp r10,#0x4c00
 bne fail
 ldr r10,[r1],#4
 eor r10,r10,r3
 ldr r11,=0x22ee0000
 cmp r10,r11
 bne fail
 subs r4,r4,#1
 bne upp_round_trip
 ldr r10,=0x0c1003e8
 ldrh r11,[r10]
