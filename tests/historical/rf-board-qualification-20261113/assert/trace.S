.syntax unified
.arm
.section .text,"ax"
.global assert_entry
assert_entry:
 stmdb sp!,{r0-r12,lr}
 sub sp,sp,#8
 mrs r12,cpsr
 str r12,[sp]
 ldr r7,=0x59000000
 adr r4,prefix
 bl literal
 ldr r0,[sp,#8]
 bl hex
 bl space
 ldr r0,[sp,#12]
 bl hex
 bl space
 ldr r0,[sp,#16]
 bl hex
 bl space
 ldr r0,[sp,#60]
 bl hex
 bl space
 ldr r4,[sp,#8]
 bl bounded
 bl space
 ldr r4,[sp,#16]
 bl bounded
 mov r0,#10
 strb r0,[r7]
 adr r4,result_prefix
 bl literal
 ldr r4,=0x80024388
 mov r5,#6
4: ldr r0,[r4],#4
 bl hex
 bl space
 subs r5,r5,#1
 bne 4b
 mov r0,#10
 strb r0,[r7]
 ldr r12,[sp]
 msr cpsr_f,r12
 add sp,sp,#8
 ldmia sp!,{r0-r12,lr}
 ldr r12,=0x514a2804
 bx r12
bounded:
 ldr r0,=0x51400000
 cmp r4,r0
 bxlo lr
 ldr r0,=0x51716900
 cmp r4,r0
 bxhs lr
 mov r5,#160
1: ldrb r0,[r4],#1
 cmp r0,#0
 bxeq lr
 strb r0,[r7]
 subs r5,r5,#1
 bxle lr
 ldr r0,=0x51716900
 cmp r4,r0
 blo 1b
 bx lr
literal:
2: ldrb r0,[r4],#1
 cmp r0,#0
 bxeq lr
 strb r0,[r7]
 b 2b
space:
 mov r0,#32
 strb r0,[r7]
 bx lr
hex:
 mov r2,#28
3: mov r1,r0,lsr r2
 and r1,r1,#15
 cmp r1,#10
 addlo r1,r1,#48
 addhs r1,r1,#87
 strb r1,[r7]
 subs r2,r2,#4
 bpl 3b
 bx lr
.balign 4
prefix: .asciz "A NOS file/line/expr/lr "
.balign 4
result_prefix: .asciz "A RESULTS "
.balign 4
.ltorg
