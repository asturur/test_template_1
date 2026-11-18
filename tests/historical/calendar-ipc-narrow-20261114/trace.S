.syntax unified
.arm
.section .text,"ax"
.global sync_slot,sync_trace
sync_slot: .word sync_trace
sync_trace:
    stmdb sp!,{r0-r12,lr}
    sub sp,sp,#8
    mrs r12,cpsr
    str r12,[sp]
    mov r4,r0
    mov r5,r1
    mov r6,r2
    mov r7,lr
    mov r8,#0
    bl log_begin
    add r12,sp,#8
    ldmia r12,{r0-r3}
    ldr r12,[sp]
    msr cpsr_f,r12
    bl original_sync
    mrs r12,cpsr
    str r12,[sp]
    str r0,[sp,#8]
    cmp r8,#0
    beq restore
    mov r3,r0
    mov r1,r5
    ldr r2,[r4]
    ldr r0,=fmt_end
    bl debug_print
restore:
    ldr r12,[sp]
    msr cpsr_f,r12
    add sp,sp,#8
    ldmia sp!,{r0-r12,lr}
    bx lr
original_sync:
    stmdb sp!,{lr}
    b 0x503bab3c
log_begin:
    stmdb sp!,{lr}
    mov r8,#1
    mov r1,r5
    ldr r2,[r4]
    mov r3,r7
    ldr r0,=fmt_begin
    bl debug_print
    ldmia sp!,{lr}
    bx lr
.balign 4
fmt_begin: .word 0x10000000+(end_begin-str_begin)/2,str_begin
str_begin:
.hword 75,32,66,69,71,73,78,32,105,112,99,61,37,48,56,120,32,104,97,110,100,108,101,61,37,48,56,120,32,99,97,108,108,101,114,61,37,48,56,120
end_begin:

.balign 4
fmt_end: .word 0x10000000+(end_end-str_end)/2,str_end
str_end:
.hword 75,32,69,78,68,32,105,112,99,61,37,48,56,120,32,104,97,110,100,108,101,61,37,48,56,120,32,114,99,61,37,48,56,120
end_end:

.ltorg
