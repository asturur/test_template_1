.syntax unified
.arm
.global _start
_start:
 ldr sp,=0x8000f000
 ldr r0,=0x00400000
 add r1,r0,#4
 str r1,[sp,#328]
 mov r1,#6
 str r1,[r0,#0xdd8]
 mov r1,#17
 add r2,r0,#16
 mov r3,#3
 mov r4,#4
 mov r5,#5
 mov r6,#6
 mov r7,#7
 mov r8,#8
 mov r9,#9
 mov r10,#10
 mov r11,#11
 mov r12,#12
 ldr lr,=0x50a13501
 ldr pc,=count_wrapper
 after_count:
 bl check
 ldr r0,=0x00400000
 mov r1,#17
 add r2,r0,#16
 mov r3,#3
 mov r12,#12
 adr lr,after_open
 ldr pc,=dbopen_wrapper
 after_open:
 bl check
 ldr r0,=0x00400000
 mov r1,#17
 add r2,r0,#16
 mov r3,#3
 mov r12,#12
 adr lr,after_store
 ldr pc,=store_wrapper
 after_store:
 bl check
 b success
check:
 mrs r3,cpsr
 and r3,r3,#0xf0000000
 cmp r3,#0x60000000
 bne fail
 mov r3,#7
 cmp r0,r3
 bne fail
 cmp r4,#4
 bne fail
 cmp r5,#5
 bne fail
 cmp r6,#6
 bne fail
 cmp r7,#7
 bne fail
 cmp r8,#8
 bne fail
 cmp r9,#9
 bne fail
 cmp r10,#10
 bne fail
 cmp r11,#11
 bne fail
 cmp r12,#12
 bne fail
 ldr r3,=0x8000f000
 cmp sp,r3
 bne fail
 bx lr
fullname:
 ldr r2,[r1]
 ldr r3,=0xffff8001
 cmp r2,r3
 bne fail
 ldr r2,=0x30000006
 str r2,[r0]
 mov r2,#256
 str r2,[r0,#4]
 ldr r2,=0x00680050
 str r2,[r0,#8]
 ldr r2,=0x006e006f
 str r2,[r0,#12]
 ldr r2,=0x005b0065
 str r2,[r0,#16]
 bx lr
original:
 ldr r3,=0x00400000
 cmp r0,r3
 bne fail
 cmp r1,#17
 bne fail
 add r3,r3,#16
 cmp r2,r3
 bne fail
 mov r0,#7
 mov r1,#0xab
 mov r2,#0xcd
 mov r3,#0xef
 mov r12,#0xee
 cmp r0,r0
 bx lr
debug:
 cmp r1,#1
 bne 2f
 cmp r3,#6
 bne fail
2:
 cmp r2,#7
 bne fail
debug_count:
 ldr r12,=0x80000040
 ldr r3,[r12]
 add r3,r3,#1
 str r3,[r12]
 mov r0,#0
 mov r1,#0
 mov r2,#0
 mov r3,#0
 mov r12,#0
 cmp r0,#1
 bx lr
fail:
 ldr r0,=0xf0000000
 mov r1,#0
 str r1,[r0]
 b fail
success:
 ldr r0,=0x80000040
 ldr r0,[r0]
 cmp r0,#3
 bne fail
 ldr r0,=0xf0000000
 ldr r1,=0x50415353
 str r1,[r0]
 b success
.ltorg
