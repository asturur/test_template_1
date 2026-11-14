.syntax unified
.cpu arm920t
.arm
.section .text,"ax"
.global mmc_begin,mmc_end
.macro save
 stmdb sp!,{r0-r12,lr}
 sub sp,sp,#8
 mrs r12,cpsr
 str r12,[sp]
 ldr r7,=0x59000000
 mov r0,#0xc0
 strb r0,[r7]
.endm
.macro restore
 mov r0,#10
 strb r0,[r7]
 ldr r12,[sp]
 msr cpsr_f,r12
 add sp,sp,#8
 ldmia sp!,{r0-r12,lr}
.endm
.macro emit base,offset
 ldr r0,[\base,#\offset]
 bl hex
 bl space
.endm
mmc_begin:
 save
 ldr r4,=prefix_begin
 bl literal
 emit r6,4
 emit r6,8
 emit r6,0x14
 emit r6,0x2c
 mov r0,r6
 bl hex
 bl space
 mov r0,r5
 bl hex
 bl space
 emit r5,0x8b4
 restore
 ldr r3,[r5,#0x8b8]
 b 0x503f470c
mmc_end:
 save
 ldr r4,=prefix_end
 bl literal
 emit r6,4
 emit r5,0x8c8
 emit r5,0x8c4
 emit r6,0x48
 emit r6,0x4c
 emit r6,0x50
 emit r6,0x54
 restore
 mov r2,#0
 b 0x503f5078

.global mmc_error
mmc_error:
 stmdb sp!,{r0-r12,lr}
 sub sp,sp,#8
 mrs r12,cpsr
 str r12,[sp]
 cmp r0,#0
 beq error_done
 ldr r7,=0x59000000
 mov r0,#0xc0
 strb r0,[r7]
 ldr r4,=prefix_error
 bl literal
 emit r6,4
 emit r5,0x8c8
 ldr r0,[sp,#8]
 bl hex
 bl space
 emit r6,0x48
 emit r6,0x4c
 emit r6,0x50
 emit r6,0x54
 mov r0,#10
 strb r0,[r7]
error_done:
 ldr r12,[sp]
 msr cpsr_f,r12
 add sp,sp,#8
 ldmia sp!,{r0-r12,lr}
 add sp,sp,#8
 b 0x503f5090

.global mmc_flags
mmc_flags:
 save
 ldr r4,=prefix_flags
 bl literal
 ldr r4,[sp,#24] // Saved original r4 = controller object.
 ldr r0,[sp,#28] // Saved original r5 = returned event flags.
 bl hex
 bl space
 emit r4,0x8a8
 emit r4,0x8c8
 emit r4,0x8b4
 emit r4,0x8cc
 restore
 mov r0,r5
 b 0x503f5570
.global mmc_status
mmc_status:
 stmdb sp!,{r0-r12,lr}
 sub sp,sp,#8
 mrs r12,cpsr
 str r12,[sp]
 ldr r12,[r7,#0x8c8]
 cmp r3,r12
 beq status_done
 mov r5,r7
 ldr r7,=0x59000000
 mov r0,#0xc0
 strb r0,[r7]
 ldr r4,=prefix_status
 bl literal
 ldr r0,[sp,#20] // Saved original r3 = new raw status.
 bl hex
 bl space
 emit r5,0x8ac
 emit r5,0x8a8
 emit r5,0x8b4
 ldr r0,[sp,#32] // Saved original r6 = requested event mask.
 bl hex
 mov r0,#10
 strb r0,[r7]
status_done:
 ldr r12,[sp]
 msr cpsr_f,r12
 add sp,sp,#8
 ldmia sp!,{r0-r12,lr}
 mov r4,r3
 b 0x503f5304

.global mmc_dma
mmc_dma:
 save
 ldr r4,=prefix_dma
 bl literal
 ldr r0,[sp,#8]
 bl hex
 bl space
 ldr r0,=0x58120064
 ldr r0,[r0]
 bl hex
 mov r0,#10
 strb r0,[r7]
 ldr r4,=0x58120300
 mov r6,#0
1:
 mov r0,#0xc0
 strb r0,[r7]
 mov r8,r4
 ldr r4,=prefix_channel
 bl literal
 mov r4,r8
 mov r0,r6
 bl hex
 bl space
 ldr r0,[r4,#4]
 bl hex
 bl space
 ldr r0,[r4,#8]
 bl hex
 bl space
 mov r5,#0x14
2:
 ldr r0,[r4,r5]
 bl hex
 bl space
 add r5,r5,#4
 cmp r5,#0x2c
 ble 2b
 mov r0,#10
 strb r0,[r7]
 add r4,r4,#0x40
 add r6,r6,#1
 cmp r6,#8
 blo 1b
 restore
 cmp r0,#0
 b 0x503f4d28
literal:
 ldrb r0,[r4],#1
 cmp r0,#0
 bxeq lr
 strb r0,[r7]
 b literal
space:
 mov r0,#32
 strb r0,[r7]
 bx lr
hex:
 mov r2,#28
1: mov r1,r0,lsr r2
 and r1,r1,#15
 cmp r1,#10
 addlo r1,r1,#48
 addhs r1,r1,#87
 strb r1,[r7]
 subs r2,r2,#4
 bpl 1b
 bx lr
.balign 4
prefix_begin: .asciz "M B "
.balign 4
prefix_end: .asciz "M E "
.balign 4
prefix_error: .asciz "M X "
.balign 4
prefix_flags: .asciz "M Q "
.balign 4
prefix_status: .asciz "M S "
.balign 4
prefix_dma: .asciz "M D "
.balign 4
prefix_channel: .asciz "M C "
.balign 4
.ltorg
