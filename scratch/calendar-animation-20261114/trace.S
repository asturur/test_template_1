.syntax unified
.arm
.section .text,"ax"
.global scan_trace
scan_trace:
 ldr r3,[sp],#4
 stmdb sp!,{r0-r12,lr}
 sub sp,sp,#8
 mrs r4,cpsr
 str r4,[sp]
 ldr r4,[r2,#4]
 cmp r4,#0
 bne restore
 ldr r4,[r2]
 cmp r4,#0
 bne restore
 ldr r4,[r0,#0x1c]
 cmp r4,#30
 beq size30
 cmp r4,#120
 bne restore
 ldr r4,[r0,#0x20]
 cmp r4,#10
 bne restore
 b log
size30:
 ldr r4,[r0,#0x20]
 cmp r4,#40
 bne restore
log:
 mov r5,r0
 mov r6,r3
 mov r7,lr
 ldr r4,=0x5055969b
 cmp r7,r4
 ldreq r7,[sp,#120] // Caller50559600 has60-byte frame, savedLR at+56.
 ldr r0,=fmt
 mov r1,r5
 mov r2,r7
 mov r3,r6
 bl debug_print
restore:
 ldr r4,[sp]
 msr cpsr_f,r4
 add sp,sp,#8
 ldmia sp!,{r0-r12,lr}
 stmdb sp!,{r12}
 ldr r12,=replay+1
 bx r12
.thumb
.balign 2
replay:
 push {r3}
 ldr r3,[sp,#4]
 mov r12,r3
 pop {r3}
 add sp,#4
 .hword 0xb5f0,0x4657,0x464e,0x4645,0xb4e0,0xb085
 sub sp,#8
 str r3,[sp]
 ldr r3,=0x50559235
 str r3,[sp,#4]
 ldr r3,[sp]
 add sp,#4
 pop {pc}
.arm
.balign 4
fmt: .word 0x10000025,string
string: .hword 68,32,66,73,84,77,65,80,61,37,48,56,120,32,112,97,114,101,110,116,61,37,48,56,120,32,108,101,110,103,116,104,61,37,48,56,120
.balign 4
.ltorg
