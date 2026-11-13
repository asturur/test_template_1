.syntax unified
.section .text,"ax"
.thumb
.global mtc_entry
.thumb_func
mtc_entry:
 bx pc
 nop
.arm
 stmdb sp!,{r0-r12,lr}
 sub sp,sp,#8
 mrs r12,cpsr
 str r12,[sp]
 ldr r7,=0x59000000
 adr r3,prefix
1: ldrb r0,[r3],#1
 cmp r0,#0
 beq 2f
 strb r0,[r7]
 b 1b
2:
 ldr r0,[sp,#8]
 bl hex
 bl space
 ldr r0,[sp,#12]
 bl hex
 bl space
 ldr r0,[sp,#60]
 bl hex
 bl space
 ldr r0,=0x80010958
 ldr r0,[r0]
 bl hex
 bl space
 ldr r0,=0x8001095c
 ldrb r0,[r0]
 bl hex
 bl space
 ldr r0,=0x8001df48
 ldr r0,[r0]
 bl hex
 bl space
 ldr r0,=0x800ca78c
 ldrb r0,[r0]
 bl hex
 mov r0,#10
 strb r0,[r7]
 ldr r0,[sp,#8]
 cmp r0,#0x64
 bne finish
 ldr r0,[sp,#12]
 cmp r0,#6
 bne finish
 adr r3,test_prefix
4: ldrb r0,[r3],#1
 cmp r0,#0
 beq dump_results
 strb r0,[r7]
 b 4b
dump_results:
 ldr r4,=0x80024388
 mov r5,#6
5: ldr r0,[r4],#4
 bl hex
 bl space
 subs r5,r5,#1
 bne 5b
 mov r0,#10
 strb r0,[r7]
finish:
 ldr r12,[sp]
 msr cpsr_f,r12
 add sp,sp,#8
 ldmia sp!,{r0-r12,lr}
 // AAPCS r12 is scratch, no native arguments or stack words changed.
 ldr r12,=0x5159a199
 bx r12
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
prefix: .asciz "M MTC msg/action/lr/0958/095c/df48/sim "
.balign 4
test_prefix: .asciz "M TESTS "
.balign 4
.ltorg
