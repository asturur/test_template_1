.syntax unified
.arm
.section .text,"ax"
.global count_slot,dbopen_slot,store_slot,count_wrapper,dbopen_wrapper,store_wrapper
count_slot: .word count_wrapper
dbopen_slot: .word dbopen_wrapper
store_slot: .word store_wrapper
.macro wrapper name,id,target
\name:
 stmdb sp!,{r0-r12,lr}
 sub sp,sp,#16
 mrs r12,cpsr
 str r12,[sp,#4]
 add r12,sp,#16
 ldmia r12,{r0-r3}
 ldr r12,[sp,#4]
 msr cpsr_f,r12
 ldr r12,=\target
 mov lr,pc
 bx r12
 mrs r12,cpsr
 str r12,[sp,#4]
 str r0,[sp,#16]
 mov r2,r0
 mov r1,#\id
 mvn r3,#0
 ldr r12,[sp,#68]
 str r12,[sp]
 .if \id == 1
 ldr r0,=0x50a13501
 cmp r12,r0
 bne 1f
 // Native CountL caller50a134a8 keeps CProfileDb+4 at its SP+328.
 ldr r0,[sp,#400]
 cmp r0,#0x00400000
 blo 1f
 cmp r0,#0x00ff0000
 bhs 1f
 ldr r3,[r0,#0xdd4] // Expected profiles at original object+0xdd8.
1:
 .endif
 ldr r0,=fmt
 bl debug_print
 ldr r12,[sp,#4]
 msr cpsr_f,r12
 add sp,sp,#16
 ldmia sp!,{r0-r12,lr}
 bx lr
.endm
wrapper count_wrapper,1,0x5044e4e9
wrapper dbopen_wrapper,2,0x504527f1
wrapper store_wrapper,3,0x508b88e5
.balign 4
fmt: .word 0x10000000+(end_fmt-str_fmt)/2,str_fmt
str_fmt: .hword 80,32,65,80,73,32,105,100,61,37,48,56,120,32,114,99,61,37,48,56,120,32,101,120,116,114,97,61,37,48,56,120,32,99,97,108,108,101,114,61,37,48,56,120
end_fmt:
.balign 4
