.include "sim/programs/common.inc"
reset_entry:
 ldr sp,=RAM+0xaffc
 ldr r4,=RAM+0xaffc
 mov r5,#32
1:
 bl outer
 cmp sp,r4
 bne fail
 cmp r0,#0x7a
 bne fail
 subs r5,r5,#1
 bne 1b
 b pass
outer:
 stmdb sp!,{lr}
 bl leaf
 mov r0,r0,lsr #16
 and r0,r0,#255
 ldmia sp!,{pc}
leaf:
 ldr r0,=0x017ab001
 mov pc,lr
fail:
 mov r0,#0xd3
 b finish
