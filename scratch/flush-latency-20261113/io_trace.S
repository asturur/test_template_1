.syntax unified
.arm
.section .text,"ax"
.global flush_slot,write_slot,flush_wrapper,write_wrapper
flush_slot: .word flush_wrapper
write_slot: .word write_wrapper
.macro wrapper name,op,target
\name:
    stmdb sp!, {r0-r12,lr}
    sub sp,sp,#8
    mrs r12,cpsr
    str r12,[sp]
    mov r4,#\op
    mov r5,r0
    mov r6,lr
    mov r7,#0
    mov r8,#0
    mov r9,#0
    mov r10,r2
    .if \op == 32
    mov r7,r1
    ldr r8,[r2]
    bic r8,r8,#0xf0000000
    .endif
    bl log_begin
    add r12,sp,#8
    ldmia r12,{r0-r3}
    ldr r12,[sp]
    msr cpsr_f,r12
    ldr r12,=\target
    mov lr,pc
    bx r12
    mrs r12,cpsr
    str r12,[sp]
    str r0,[sp,#8]
    cmp r9,#0
    beq 8f
    mov r3,r0
    mov r1,r4
    mov r2,r5
    ldr r0,=fmt_end
    bl debug_print
8:
    ldr r12,[sp]
    msr cpsr_f,r12
    add sp,sp,#8
    ldmia sp!,{r0-r12,lr}
    bx lr
.endm
wrapper flush_wrapper,36,0x503df58d
wrapper write_wrapper,32,0x503df3e9
open_slot: .word open_wrapper
replace_slot: .word replace_wrapper
.global open_slot,replace_slot,open_wrapper,replace_wrapper
wrapper open_wrapper,121,0x503df0ed
wrapper replace_wrapper,151,0x503df11d
log_begin:
    stmdb sp!,{lr}
    sub sp,sp,#544
    ldr r0,=0xffff8001 // Native User::Exit/Panic current-thread handle.
    str r0,[sp,#536]
    add r0,sp,#16     // FullName hidden output TBuf<256> (520 bytes).
    add r1,sp,#536
    bl full_name
    // Only Phone's main process: avoid concurrent clients interleaving records.
    ldr r0,[sp,#24]
    ldr r1,=0x00680050
    cmp r0,r1
    bne 9f
    ldr r0,[sp,#28]
    ldr r1,=0x006e006f
    cmp r0,r1
    bne 9f
    ldr r0,[sp,#32]
    ldr r1,=0x005b0065
    cmp r0,r1
    bne 9f
    mov r9,#1
    cmp r4,#121
    beq 7f
    cmp r4,#151
    bne 6f
7:
    mov r1,r5
    mov r2,r10
    ldr r0,=fmt_path
    bl debug_print
6:
    str r7,[sp]
    str r8,[sp,#4]
    str r6,[sp,#8]
    add r0,sp,#16
    str r0,[sp,#12]
    mov r1,r4
    mov r2,r5
    ldr r3,[r5,#4]
    ldr r0,=fmt_begin
    bl debug_print
9:
    add sp,sp,#544
    ldmia sp!,{lr}
    bx lr
.balign 4
fmt_begin: .word 0x10000000+(end_begin-str_begin)/2, str_begin
str_begin: .hword 81,32,66,69,71,73,78,32,111,112,61,37,48,56,120,32,102,105,108,101,61,37,48,56,120,32,104,97,110,100,108,101,61,37,48,56,120,32,111,102,102,115,101,116,61,37,48,56,120,32,98,121,116,101,115,61,37,48,56,120,32,99,97,108,108,101,114,61,37,48,56,120,32,116,104,114,101,97,100,61,37,83
end_begin:
.balign 4
fmt_end: .word 0x10000000+(end_end-str_end)/2, str_end
str_end: .hword 81,32,69,78,68,32,111,112,61,37,48,56,120,32,102,105,108,101,61,37,48,56,120,32,114,99,61,37,48,56,120
end_end:
.balign 4

.balign 4
fmt_path: .word 0x10000000+(end_path-str_path)/2, str_path
str_path: .hword 81,32,80,65,84,72,32,102,105,108,101,61,37,48,56,120,32,110,97,109,101,61,37,83
end_path:
.balign 4
