.include "sim/programs/common.inc"
.equ TABLE, RAM+0x4000
reset_entry:
 ldr sp, =RAM+0x20000
 ldr r4, =TABLE
 mov r0,#0
 mov r1,#4096
.global measure_init_target
.global measure_init_branch
measure_init_target:
1: str r0,[r4],#4
 subs r1,r1,#1
measure_init_branch:
 bne 1b
 ldr r4,=TABLE
 ldr r0,=0x00000c0e
 str r0,[r4]
 ldr r0,=0x80000c0e
 add r5,r4,#0x2000
 str r0,[r5]
 ldr r0,=0xf0000c02
 add r5,r4,#0x3c00
 str r0,[r5]
 mcr p15,0,r4,c2,c0,0
 mov r0,#1
 mcr p15,0,r0,c3,c0,0
 mrc p15,0,r0,c1,c0,0
 orr r0,r0,#5
 orr r0,r0,#0x1000
 mcr p15,0,r0,c1,c0,0
 nop
 nop
 mov r5,#0
 mov r6,#10
.global timing_first
.global timing_last
.global measure_load
.global measure_use
.global measure_branch
.global measure_target
timing_first:
.rept 16
 add r5,r5,#1
.endr
timing_last:
measure_load:
 ldr r10,[r4]
measure_use:
 add r11,r10,#1
 str r11,[r4,#4]
 mov r8,#3
 adds r8,r8,#1
 adc r8,r8,#2
 sbc r8,r8,#1
 mul r9,r8,r8
 mov r9,r9,lsl r8
 cmp r8,#4
 bne fail_measure
 cmp r9,#256
 bne fail_measure
 cmp r11,#0
 beq fail_measure
 subs r6,r6,#1
measure_branch:
 bne measure_target
 b measure_end
measure_target:
 b timing_first
measure_end:
 cmp r5,#160
 movne r0,#0x62
 bne finish
 b pass
fail_measure:
 mov r0,#0x63
 b finish
.ltorg
