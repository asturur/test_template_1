 // ARM SWP on both raw DDR banks with the LCD transfer active.
 mov r12,#81
 ldr r0,=0x0c038000
 ldr r1,=0x0c108000
 mov r2,#0x5a
 mov r3,#0x9c
 str r2,[r0]
 str r2,[r1]
 swp r10,r3,[r0]
 cmp r10,r2
 bne fail
 swp r10,r3,[r1]
 cmp r10,r2
 bne fail
 ldr r10,[r0]
 cmp r10,r3
 bne fail
 ldr r10,[r1]
 cmp r10,r3
 bne fail

 // Both ranges retain ordinary instruction readback. The first word
 // updates a scratch register and the second returns to code flash.
 mov r12,#82
 ldr r2,=0xe3a0a05a
 ldr r3,=0xe12fff1e
 str r2,[r0]
 str r3,[r0,#4]
 str r2,[r1]
 str r3,[r1,#4]
 mov r10,#0
 mov lr,pc
 bx r0
 cmp r10,#0x5a
 bne fail
 mov r10,#0
 mov lr,pc
 bx r1
 cmp r10,#0x5a
 bne fail
