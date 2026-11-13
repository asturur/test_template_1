.syntax unified
.section .text,"ax"
.macro entry name,tag
.thumb
.global \name
.thumb_func
\name:
 bx pc
 nop
.arm
 mov r12,#\tag
 b observe
.endm
entry rf_send,1
entry mdi_write,2
entry rf_receive,3
entry rf_start,4
entry info_mgr,5
entry rf_builder,6
entry rf_route,7
entry rf_client,8
observe:
 stmdb sp!,{r0-r12,lr}
 sub sp,sp,#8
 mrs r0,cpsr
 str r0,[sp]
 ldr r7,=0x59000000
 mov r0,#82
 strb r0,[r7]
 ldr r0,[sp,#56]
 add r0,r0,#48
 strb r0,[r7]
 bl space
 mov r4,#8
1: ldr r0,[sp,r4]
 bl hex
 bl space
 add r4,r4,#4
 cmp r4,#24
 bne 1b
 ldr r0,[sp,#60]
 bl hex
 bl space
 ldr r4,[sp,#12]
 ldr r0,[sp,#56]
 cmp r0,#1
 ldreq r4,[sp,#16]
 cmp r0,#4
 ldreq r4,[sp,#16]
 mov r5,#4
 cmp r0,#2
 bne 6f
 ldr r5,[sp,#16]
 mov r5,r5,lsl #1
 cmp r5,#12
 movhi r5,#12
6: cmp r0,#6
 movhs r5,#0
2: cmp r5,#0
 beq 4f
3: ldrb r0,[r4],#1
 bl bytehex
 subs r5,r5,#1
 bne 3b
4: bl space
 ldr r4,=0x581003e8
 ldr r0,[r4]
 bl hex
 bl space
 ldr r0,[r4,#4]
 bl hex
 bl space
 ldr r0,=0x5814b004
 ldr r0,[r0]
 bl hex
 bl space
 ldr r0,=0x8000c0fe
 ldrb r0,[r0]
 bl hex
 mov r0,#10
 strb r0,[r7]
 ldr r12,[sp]
 msr cpsr_f,r12
 add sp,sp,#8
 ldmia sp!,{r0-r12,lr}
 cmp r12,#1
 beq send
 cmp r12,#2
 beq ring
 // Restore flags once more after choosing the tail target.
 cmp r12,#3
 ldreq r12,=0x515920d1
 beq tail
 cmp r12,#4
 beq send
 cmp r12,#5
 ldreq r12,=0x5164ae79
 beq tail
 cmp r12,#6
 ldreq r12,=0x5164b3a5
 beq tail
 cmp r12,#7
 ldreq r12,=0x5164b20d
 beq tail
 ldr r12,=0x516a60c1
 b tail
send: ldr r12,=0x514ba3f1
 b tail
ring: ldr r12,=0x515bf551
tail:
 // Saved flags remain at original SP-64; only ABI-scratch IP changes.
 stmdb sp!,{r0}
 ldr r0,[sp,#-60]
 msr cpsr_f,r0
 ldmia sp!,{r0}
 bx r12
space:
 mov r0,#32
 strb r0,[r7]
 bx lr
hex:
 mov r2,#28
 b digits
bytehex:
 mov r2,#4
digits:
5: mov r1,r0,lsr r2
 and r1,r1,#15
 cmp r1,#10
 addlo r1,r1,#48
 addhs r1,r1,#87
 strb r1,[r7]
 subs r2,r2,#4
 bpl 5b
 bx lr
.balign 4
.ltorg
