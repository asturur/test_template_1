.syntax unified
.arm
.section .text,"ax"
.global start_trace
start_trace:
 stmdb sp!,{r0-r12,lr}
 sub sp,sp,#8
 mrs r4,cpsr
 str r4,[sp]
 and r4,r4,#31
 cmp r4,#16
 bne start_restore
 mov r5,r0
 mov r6,r1
 mov r7,r2
 ldr r4,=0x50833d44
 cmp r6,r4
 blo start_restore
 ldr r4,=0x5089495c
 cmp r6,r4
 blo start_log
 ldr r4,=0x5099ec44
 cmp r6,r4
 blo start_restore
 ldr r4,=0x509b30f8
 cmp r6,r4
 bhs start_restore
start_log:
 ldr r0,=fmt_start
 mov r1,r5
 mov r2,r6
 mov r3,r7
 bl debug_print
start_restore:
 ldr r4,[sp]
 msr cpsr_f,r4
 add sp,sp,#8
 ldmia sp!,{r0-r12,lr}
 .word 0xe92d4010
 b 0x50399d74
.global run_trace
run_trace:
 stmdb sp!,{r0-r12,lr}
 sub sp,sp,#8
 mrs r4,cpsr
 str r4,[sp]
 and r4,r4,#31
 cmp r4,#16
 bne run_restore
 mov r5,r0
 ldr r6,[r5,#0x18]
 ldr r7,[r5,#0x1c]
 ldr r4,=0x50833d44
 cmp r6,r4
 blo run_restore
 ldr r4,=0x5089495c
 cmp r6,r4
 blo run_log
 ldr r4,=0x5099ec44
 cmp r6,r4
 blo run_restore
 ldr r4,=0x509b30f8
 cmp r6,r4
 bhs run_restore
run_log:
 ldr r0,=fmt_run
 mov r1,r5
 mov r2,r6
 mov r3,r7
 bl debug_print
run_restore:
 ldr r4,[sp]
 msr cpsr_f,r4
 add sp,sp,#8
 ldmia sp!,{r0-r12,lr}
 .word 0xe92d4010
 b 0x50399db0
.global ready_trace
ready_trace:
 stmdb sp!,{r0-r12,lr}
 sub sp,sp,#8
 mrs r4,cpsr
 str r4,[sp]
 and r4,r4,#31
 cmp r4,#16
 bne ready_restore
 ldr r5,[sp,#24]
 ldr r6,[r5,#0x18]
 ldr r7,[r5,#0x1c]
 ldr r4,=0x50833d44
 cmp r6,r4
 blo ready_restore
 ldr r4,=0x5089495c
 cmp r6,r4
 blo ready_log
 ldr r4,=0x5099ec44
 cmp r6,r4
 blo ready_restore
 ldr r4,=0x509b30f8
 cmp r6,r4
 bhs ready_restore
ready_log:
 ldr r0,=fmt_ready
 mov r1,r5
 ldr r2,[r5,#4]
 ldr r3,[r5,#0x14]
 bl debug_print
ready_restore:
 ldr r4,[sp]
 msr cpsr_f,r4
 add sp,sp,#8
 ldmia sp!,{r0-r12,lr}
 .word 0xe8bd4010
 b 0x50399da8
fmt_start: .word 0x1000002c,str_start
str_start: .hword 73,32,83,84,65,82,84,32,111,98,106,101,99,116,61,37,48,56,120,32,99,97,108,108,98,97,99,107,61,37,48,56,120,32,112,97,114,97,109,61,37,48,56,120
.balign 4
fmt_run: .word 0x1000002a,str_run
str_run: .hword 73,32,82,85,78,32,111,98,106,101,99,116,61,37,48,56,120,32,99,97,108,108,98,97,99,107,61,37,48,56,120,32,112,97,114,97,109,61,37,48,56,120
.balign 4
fmt_ready: .word 0x1000002d,str_ready
str_ready: .hword 73,32,82,69,65,68,89,32,111,98,106,101,99,116,61,37,48,56,120,32,115,116,97,116,117,115,61,37,48,56,120,32,112,114,105,111,114,105,116,121,61,37,48,56,120
.balign 4
.ltorg
