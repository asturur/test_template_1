.syntax unified
.cpu arm920t
.arm
.section .vectors,"ax"
.global _start
_start:
 b reset
 b fail
 b fail
 b fail
 b abort_handler
 b fail
 b fail
 b fail

.section .text,"ax"
reset:
 msr cpsr_c,#0xd3
 ldr r4,=0x0a01c000
 mov r0,#0
 mov r1,#4096
zero_table:
 str r0,[r4],#4
 subs r1,r1,#1
 bne zero_table
 ldr r4,=0x0a01c000
 ldr r0,=0x00000c0e
 str r0,[r4]
 ldr r0,=0x0a000c0e
 ldr r5,=0x2000
 str r0,[r4,r5]
 ldr r0,=0xf0000c02
 ldr r5,=0x3c00
 str r0,[r4,r5]
 mcr p15,0,r4,c2,c0,0
 mov r0,#1
 mcr p15,0,r0,c3,c0,0
 mrc p15,0,r0,c1,c0,0
 orr r0,r0,#5
 orr r0,r0,#0x1000
 mcr p15,0,r0,c1,c0,0
 ldr sp,=0x80001800
 ldr r0,=0x80001000
 ldr r2,=0x7fffffff
 str r2,[r0]
 mvn r2,#0
 str r2,[r0,#4]
 mov r2,#0
 str r2,[sp]
 mov r5,#0x24
 str r5,[sp,#4]
 ldr r1,=0x80005000
 mov r10,#0
 ldr r7,=finish_arm
 ldr r2,=thumb_entry+1
 bx r2

.thumb
.balign 4
thumb_entry:
imm_low:
 ldr r2,[r0]
imm_low_use:
 adds r2,#1
 bvc thumb_fail
 bpl thumb_fail
.balign 4
 nop
imm_high:
 ldr r2,[r0,#4]
imm_high_use:
 adds r2,#1
 bne thumb_fail
 bcc thumb_fail
.balign 4
sp_low:
 ldr r3,[sp]
sp_low_use:
 cmp r3,#0
 bne thumb_fail
 bcc thumb_fail
.balign 4
 nop
sp_high:
 ldr r3,[sp,#4]
sp_high_use:
 adds r3,#1
 cmp r3,#0x25
 bne thumb_fail

cold_load:
 ldr r2,[r1]
cold_use:
 adds r2,#1
 cmp r2,#1
 bne thumb_fail

literal_load:
 ldr r2,=0x12345678
 movs r1,#4
register_load:
 ldr r2,[r0,r1]
byte_load:
 ldrb r2,[r0]
half_load:
 ldrh r2,[r0]
 movs r1,r0
macro_ldm:
 ldmia r1!,{r2,r3}
macro_pop:
 pop {r2}
 ldr r6,=0x90000000
 movs r4,#0x5a
 cmp r0,r0
 nop
 nop
fault_load:
 ldr r4,[r6,#4]
fault_use:
 adds r4,#1
 b thumb_fail
thumb_resume:
 bne thumb_fail
 bcc thumb_fail
 cmp r4,#0x5a
 bne thumb_fail
 bx r7
thumb_fail:
 ldr r6,=fail
 bx r6
.ltorg

.arm
.balign 4
finish_arm:
 cmp r4,#0x5a
 bne fail
 cmp r10,#1
 bne fail
 ldr r0,=0x50415353
 b finish
abort_handler:
 mrc p15,0,r8,c6,c0,0
 ldr r9,=0x90000004
 cmp r8,r9
 bne fail
 mrc p15,0,r8,c5,c0,0
 and r8,r8,#255
 cmp r8,#5
 bne fail
 mrs r8,spsr
 tst r8,#0x20
 beq fail
 and r8,r8,#0xf0000000
 cmp r8,#0x60000000
 bne fail
 add r10,r10,#1
 cmp r10,#1
 bne fail
 ldr r12,=thumb_resume
 movs pc,r12
fail:
 ldr r0,=0x4641494c
finish:
 ldr r1,=0xf0000000
 str r0,[r1]
 b .
.ltorg
