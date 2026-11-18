.syntax unified
.arm
.global _start
_start:
 ldr sp,=0x8000f000
 ldr r0,=0x80000000
 ldr r1,=0x24681357
 str r1,[r0,#4]
 ldr r1,=0x10000003
 str r1,[r0,#16]
 mov r10,#0
again:
 ldr r0,=0x80000000
 mov r1,#17
 add r2,r0,#16
 mov r3,#3
 mov r4,#4
 mov r5,#5
 mov r6,#6
 mov r7,#7
 mov r8,#8
 mov r9,#9
 mov r11,#11
 mov r12,#12
 tst r10,#1
 ldreq lr,=flush_wrapper
 ldrne lr,=write_wrapper
 mov r10,#10
 mov r10,r10
 adr lr,after_call
 // Flush call first; write and Thumb calls below use same check body.
 ldr pc,=flush_wrapper
 after_call:
 bl check
 ldr r0,=0x80000000
 mov r1,#17
 add r2,r0,#16
 ldr lr,=write_wrapper
 mov r12,#12
 adr lr,after_write
 ldr pc,=write_wrapper
 after_write:
 bl check
 ldr r0,=0x80000000
 mov r1,#17
 add r2,r0,#16
 mov r12,#12
 adr lr,after_open
 ldr pc,=open_wrapper
 after_open:
 bl check
 ldr r0,=0x80000000
 mov r1,#17
 add r2,r0,#16
 mov r12,#12
 adr lr,after_replace
 ldr pc,=replace_wrapper
 after_replace:
 bl check
 // Real Thumb caller and returned Thumb LR.
 ldr r0,=thumb_caller+1
 bx r0
check:
 mrs r3,cpsr
 and r3,r3,#0xf0000000
 cmp r3,#0x60000000
 bne fail
 ldr r3,=0x13572468
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
 ldr r3,=0x80000000
 cmp r0,r3
 bne fail
 cmp r1,#17
 bne fail
 add r3,r3,#16
 cmp r2,r3
 bne fail
 ldr r0,=0x13572468
 mov r1,#0xab
 mov r2,#0xcd
 mov r3,#0xef
 mov r12,#0xee
 cmp r0,r0
 bx lr
debug:
 ldr r12,[r0,#4]
 ldrh r12,[r12,#4]
 cmp r12,#66 // BEGIN third character.
 bne debug_end
 ldr r12,=0x24681357
 cmp r3,r12
 bne fail
 b debug_count
debug_end:
 cmp r12,#80
 beq debug_count
 cmp r12,#69
 bne fail
 ldr r12,=0x13572468
 cmp r3,r12
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
 cmp r0,#12
 bne fail
 ldr r0,=0xf0000000
 ldr r1,=0x50415353
 str r1,[r0]
 b success
.ltorg
.thumb
.thumb_func
thumb_caller:
 ldr r0,=0x80000000
 movs r1,#17
 movs r2,r0
 adds r2,#16
 movs r3,#12
 mov r12,r3
 ldr r3,=flush_wrapper
 bl thunk
 ldr r3,=check
 bl thunk
 ldr r3,=success
 bx r3
thunk:
 bx r3
.balign 4
