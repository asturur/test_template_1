.syntax unified
.arm
.section .text,"ax"
.global window_trace
window_trace:
    stmdb sp!,{r0-r12,lr}
    sub sp,sp,#8
    mrs r4,cpsr
    str r4,[sp]
    mov r5,r0
    mov r6,r1
    mov r7,lr
    ldr r12,=0x59000000
    mov r0,#0xc0
    strb r0,[r12]
    ldr r0,=text_window_0
    bl emit_string
    mov r0,r5
    bl emit_hex
    ldr r0,=text_window_1
    bl emit_string
    mov r0,r6
    bl emit_hex
    ldr r0,=text_window_2
    bl emit_string
    mov r0,r7
    bl emit_hex
    ldr r4,[sp]
    msr cpsr_f,r4
    add sp,sp,#8
    ldmia sp!,{r0-r12,lr}
    .word 0xe92d4030
    b 0x50400548
.global header12_trace
header12_trace:
    stmdb sp!,{r0-r12,lr}
    sub sp,sp,#8
    mrs r4,cpsr
    str r4,[sp]
    mov r5,r0
    mov r6,lr
    mov r7,#0
    ldr r0,=0x5040184c
    cmp r6,r0
    bne 1f
    ldr r0,[sp,#24] // Original caller r4: first row.
    ldr r1,[sp,#28] // Original caller r5: DMA object.
    ldr r2,[sp,#36] // Original caller r7: row count.
    cmp r2,#0
    beq 1f
    mov r3,#60
    cmp r0,r3
    bhi 2f
    add r4,r0,r2
    cmp r4,r3
    bhi 3f
2:  mov r3,r0
3:  add r4,r3,r3,lsl #2
    add r4,r3,r4,lsl #1
    ldr r12,[r1,#0x38]
    add r12,r12,r4,lsl #5
    ldrh r7,[r12,#50] // Pixel25 in a row within the pending DMA band.
1:
    ldr r12,=0x59000000
    mov r0,#0xc0
    strb r0,[r12]
    ldr r0,=text_header12_0
    bl emit_string
    mov r0,r5
    bl emit_hex
    ldr r0,=text_header12_1
    bl emit_string
    mov r0,r6
    bl emit_hex
    ldr r0,=text_header12_2
    bl emit_string
    mov r0,r7
    bl emit_hex
    ldr r4,[sp]
    msr cpsr_f,r4
    add sp,sp,#8
    ldmia sp!,{r0-r12,lr}
    .word 0xe92d4010
    b 0x50400644
.global header16_trace
header16_trace:
    stmdb sp!,{r0-r12,lr}
    sub sp,sp,#8
    mrs r4,cpsr
    str r4,[sp]
    mov r5,r0
    mov r6,lr
    mov r7,#0
    ldr r12,=0x59000000
    mov r0,#0xc0
    strb r0,[r12]
    ldr r0,=text_header16_0
    bl emit_string
    mov r0,r5
    bl emit_hex
    ldr r0,=text_header16_1
    bl emit_string
    mov r0,r6
    bl emit_hex
    ldr r0,=text_header16_2
    bl emit_string
    mov r0,r7
    bl emit_hex
    ldr r4,[sp]
    msr cpsr_f,r4
    add sp,sp,#8
    ldmia sp!,{r0-r12,lr}
    .word 0xe92d4010
    b 0x5040066c
.global line_trace
line_trace:
    stmdb sp!,{r0-r12,lr}
    sub sp,sp,#8
    mrs r4,cpsr
    str r4,[sp]
    ldr r5,[r1]
    ldr r6,[r0,#0x70]
    ldr r7,[r1,#8]
    ldr r7,[r7,#100]
    ldr r12,=0x59000000
    mov r0,#0xc0
    strb r0,[r12]
    ldr r0,=text_line_0
    bl emit_string
    mov r0,r5
    bl emit_hex
    ldr r0,=text_line_1
    bl emit_string
    mov r0,r6
    bl emit_hex
    ldr r0,=text_line_2
    bl emit_string
    mov r0,r7
    bl emit_hex
    ldr r4,[sp]
    msr cpsr_f,r4
    add sp,sp,#8
    ldmia sp!,{r0-r12,lr}
    .word 0xe92d4070
    b 0x50400f00
emit_string:
    ldr r12,=0x59000000
4:  ldrb r1,[r0],#1
    cmp r1,#0
    strbne r1,[r12]
    bne 4b
    bx lr
emit_hex:
    ldr r12,=0x59000000
    mov r1,#8
5:  mov r2,r0,lsr #28
    cmp r2,#10
    addlo r2,r2,#48
    addhs r2,r2,#87
    strb r2,[r12]
    mov r0,r0,lsl #4
    subs r1,r1,#1
    bne 5b
    bx lr
text_window_0: .asciz "L WINDOW start="
text_window_1: .asciz " end="
text_window_2: .asciz " caller="
text_header12_0: .asciz "L HEADER12 bytes="
text_header12_1: .asciz " caller="
text_header12_2: .asciz " sample25="
text_header16_0: .asciz "L HEADER16 bytes="
text_header16_1: .asciz " caller="
text_header16_2: .asciz " sample25="
text_line_0: .asciz "L LINE row="
text_line_1: .asciz " mode="
text_line_2: .asciz " sample25="
.balign 4
.ltorg
.arm
.balign 4
.global pixel_trace
pixel_trace:
    ldr r3,[sp],#4 // Restore the Thumb entry thunk's temporary r3.
    stmdb sp!,{r0-r12,lr}
    sub sp,sp,#8
    mrs r4,cpsr
    str r4,[sp]
    ldr r4,[r2,#4]
    tst r4,#31
    bne pixel_restore
    ldr r4,[r2]
    cmp r4,#0
    bne pixel_restore
    mov r5,r0
    mov r6,r2
    mov r7,r3
    mov r8,lr
    ldr r12,=0x59000000
    mov r0,#0xc0
    strb r0,[r12]
    ldr r0,=gtext_pixel_0
    bl emit_string
    mov r0,r5
    bl emit_hex
    ldr r0,=gtext_pixel_1
    bl emit_string
    ldr r0,[r5,#0x1c]
    bl emit_hex
    ldr r0,=gtext_pixel_2
    bl emit_string
    ldr r0,[r5,#0x20]
    bl emit_hex
    ldr r0,=gtext_pixel_3
    bl emit_string
    ldr r0,[r5,#0x2c]
    bl emit_hex
    ldr r0,=gtext_pixel_4
    bl emit_string
    ldr r0,[r5,#0x30]
    bl emit_hex
    ldr r0,=gtext_pixel_5
    bl emit_string
    ldr r0,[r5,#0x38]
    bl emit_hex
    ldr r0,=gtext_pixel_6
    bl emit_string
    ldr r0,[r6]
    bl emit_hex
    ldr r0,=gtext_pixel_7
    bl emit_string
    ldr r0,[r6,#4]
    bl emit_hex
    ldr r0,=gtext_pixel_8
    bl emit_string
    mov r0,r7
    bl emit_hex
    ldr r0,=gtext_pixel_9
    bl emit_string
    mov r0,r8
    bl emit_hex
pixel_restore:
    ldr r4,[sp]
    msr cpsr_f,r4
    add sp,sp,#8
    ldmia sp!,{r0-r12,lr}
    stmdb sp!,{r12}
    ldr r12,=pixel_replay+1
    bx r12
.thumb
.balign 2
pixel_replay:
    push {r3}
    ldr r3,[sp,#4]
    mov r12,r3
    pop {r3}
    add sp,#4
    .hword 0xb5f0,0x464f,0x4646,0xb4c0,0x1c06,0x4688
    sub sp,#8
    str r3,[sp]
    ldr r3,=0x50558f99
    str r3,[sp,#4]
    ldr r3,[sp]
    add sp,#4
    pop {pc}
.arm
.balign 4
gtext_pixel_0: .asciz "G PIXEL bitmap="
gtext_pixel_1: .asciz " width="
gtext_pixel_2: .asciz " height="
gtext_pixel_3: .asciz " depth="
gtext_pixel_4: .asciz " colour="
gtext_pixel_5: .asciz " compression="
gtext_pixel_6: .asciz " x="
gtext_pixel_7: .asciz " y="
gtext_pixel_8: .asciz " arg3="
gtext_pixel_9: .asciz " caller="
.balign 4
.ltorg
.arm
.balign 4
.global scan_trace
scan_trace:
    ldr r3,[sp],#4 // Restore the Thumb entry thunk's temporary r3.
    stmdb sp!,{r0-r12,lr}
    sub sp,sp,#8
    mrs r4,cpsr
    str r4,[sp]
    ldr r4,[r2,#4]
    tst r4,#31
    bne scan_restore
    mov r5,r0
    mov r6,r2
    mov r7,r3
    mov r8,lr
    ldr r12,=0x59000000
    mov r0,#0xc0
    strb r0,[r12]
    ldr r0,=gtext_scan_0
    bl emit_string
    mov r0,r5
    bl emit_hex
    ldr r0,=gtext_scan_1
    bl emit_string
    ldr r0,[r5,#0x1c]
    bl emit_hex
    ldr r0,=gtext_scan_2
    bl emit_string
    ldr r0,[r5,#0x20]
    bl emit_hex
    ldr r0,=gtext_scan_3
    bl emit_string
    ldr r0,[r5,#0x2c]
    bl emit_hex
    ldr r0,=gtext_scan_4
    bl emit_string
    ldr r0,[r5,#0x30]
    bl emit_hex
    ldr r0,=gtext_scan_5
    bl emit_string
    ldr r0,[r5,#0x38]
    bl emit_hex
    ldr r0,=gtext_scan_6
    bl emit_string
    ldr r0,[r6]
    bl emit_hex
    ldr r0,=gtext_scan_7
    bl emit_string
    ldr r0,[r6,#4]
    bl emit_hex
    ldr r0,=gtext_scan_8
    bl emit_string
    mov r0,r7
    bl emit_hex
    ldr r0,=gtext_scan_9
    bl emit_string
    mov r0,r8
    bl emit_hex
    ldr r0,=gtext_scan_10
    bl emit_string
    ldr r0,[sp,#76]
    bl emit_hex
scan_restore:
    ldr r4,[sp]
    msr cpsr_f,r4
    add sp,sp,#8
    ldmia sp!,{r0-r12,lr}
    stmdb sp!,{r12}
    ldr r12,=scan_replay+1
    bx r12
.thumb
.balign 2
scan_replay:
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
gtext_scan_0: .asciz "G SCAN bitmap="
gtext_scan_1: .asciz " width="
gtext_scan_2: .asciz " height="
gtext_scan_3: .asciz " depth="
gtext_scan_4: .asciz " colour="
gtext_scan_5: .asciz " compression="
gtext_scan_6: .asciz " x="
gtext_scan_7: .asciz " y="
gtext_scan_8: .asciz " arg3="
gtext_scan_9: .asciz " caller="
gtext_scan_10: .asciz " data="
.balign 4
.ltorg
.arm
.balign 4
.global stretch_trace
stretch_trace:
    ldr r3,[sp],#4 // Restore the Thumb entry thunk's temporary r3.
    stmdb sp!,{r0-r12,lr}
    sub sp,sp,#8
    mrs r4,cpsr
    str r4,[sp]
    ldr r4,[r2,#4]
    tst r4,#31
    bne stretch_restore
    mov r5,r0
    mov r6,r2
    mov r7,r3
    mov r8,lr
    ldr r12,=0x59000000
    mov r0,#0xc0
    strb r0,[r12]
    ldr r0,=gtext_stretch_0
    bl emit_string
    mov r0,r5
    bl emit_hex
    ldr r0,=gtext_stretch_1
    bl emit_string
    ldr r0,[r5,#0x1c]
    bl emit_hex
    ldr r0,=gtext_stretch_2
    bl emit_string
    ldr r0,[r5,#0x20]
    bl emit_hex
    ldr r0,=gtext_stretch_3
    bl emit_string
    ldr r0,[r5,#0x2c]
    bl emit_hex
    ldr r0,=gtext_stretch_4
    bl emit_string
    ldr r0,[r5,#0x30]
    bl emit_hex
    ldr r0,=gtext_stretch_5
    bl emit_string
    ldr r0,[r5,#0x38]
    bl emit_hex
    ldr r0,=gtext_stretch_6
    bl emit_string
    ldr r0,[r6]
    bl emit_hex
    ldr r0,=gtext_stretch_7
    bl emit_string
    ldr r0,[r6,#4]
    bl emit_hex
    ldr r0,=gtext_stretch_8
    bl emit_string
    mov r0,r7
    bl emit_hex
    ldr r0,=gtext_stretch_9
    bl emit_string
    mov r0,r8
    bl emit_hex
stretch_restore:
    ldr r4,[sp]
    msr cpsr_f,r4
    add sp,sp,#8
    ldmia sp!,{r0-r12,lr}
    stmdb sp!,{r12}
    ldr r12,=stretch_replay+1
    bx r12
.thumb
.balign 2
stretch_replay:
    push {r3}
    ldr r3,[sp,#4]
    mov r12,r3
    pop {r3}
    add sp,#4
    .hword 0xb5f0,0x4657,0x464e,0x4645,0xb4e0,0xb08a
    sub sp,#8
    str r3,[sp]
    ldr r3,=0x50559f2d
    str r3,[sp,#4]
    ldr r3,[sp]
    add sp,#4
    pop {pc}
.arm
.balign 4
gtext_stretch_0: .asciz "G STRETCH bitmap="
gtext_stretch_1: .asciz " width="
gtext_stretch_2: .asciz " height="
gtext_stretch_3: .asciz " depth="
gtext_stretch_4: .asciz " colour="
gtext_stretch_5: .asciz " compression="
gtext_stretch_6: .asciz " x="
gtext_stretch_7: .asciz " y="
gtext_stretch_8: .asciz " arg3="
gtext_stretch_9: .asciz " caller="
.balign 4
.ltorg
