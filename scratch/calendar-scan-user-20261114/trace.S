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
 tst r4,#31
 bne restore
 mov r5,r0
 mov r6,r2
 mov r7,r3
 mov r8,lr
 ldr r0,=fmt0
 ldr r1,[r5,#0x1c]
 ldr r2,[r5,#0x20]
 ldr r3,[r5,#0x2c]
 bl debug_print
 ldr r0,=fmt1
 ldr r1,[r6]
 ldr r2,[r6,#4]
 mov r3,r8
 bl debug_print
 ldr r0,=fmt2
 ldr r1,[r5,#0x30]
 ldr r2,[r5,#0x38]
 mov r3,r7
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
 .hword 0xb5f0,0x4657,0x464e,0x4645,0xb4e0,0xb089
 sub sp,#8
 str r3,[sp]
 ldr r3,=0x505598b1
 str r3,[sp,#4]
 ldr r3,[sp]
 add sp,#4
 pop {pc}
.arm
.balign 4
fmt0: .word 0x10000028,str0
str0: .hword 66,32,83,67,65,78,32,119,105,100,116,104,61,37,48,56,120,32,104,101,105,103,104,116,61,37,48,56,120,32,100,101,112,116,104,61,37,48,56,120
.balign 4
fmt1: .word 0x10000021,str1
str1: .hword 66,32,80,79,73,78,84,32,120,61,37,48,56,120,32,121,61,37,48,56,120,32,99,97,108,108,101,114,61,37,48,56,120
.balign 4
fmt2: .word 0x1000002f,str2
str2: .hword 66,32,77,69,84,65,32,99,111,108,111,117,114,61,37,48,56,120,32,99,111,109,112,114,101,115,115,105,111,110,61,37,48,56,120,32,108,101,110,103,116,104,61,37,48,56,120
.balign 4
.ltorg
