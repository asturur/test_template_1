.syntax unified
.cpu arm920t
.arm
.equ RAM,0x80000000
.equ TABLE,RAM+0x4000
.section .vectors,"ax"
.global _start
_start: b reset_entry
 b fail
 b svc_handler
 b fail
 b data_abort
 b fail
 b fail
 b fail
.section .text,"ax"
reset_entry:
 ldr r4,=TABLE
 mov r0,#0
 mov r1,#4096
1: str r0,[r4],#4
 subs r1,r1,#1
 bne 1b
 ldr r4,=TABLE
 ldr r0,=0x00000c02
 str r0,[r4]
 ldr r0,=0x80000c02
 str r0,[r4,#0x800]       @ user alias20000000 -> RAM
 ldr r5,=0x2000
 str r0,[r4,r5]          @ kernel identity80000000 -> RAM
 ldr r0,=0x8000043a       @ AP1 domain1: privileged writes only
 ldr r5,=0x1660
 str r0,[r4,r5]          @ protected59800000 -> RAM
 ldr r0,=0xf0000c02
 add r5,r4,#0x3c00
 str r0,[r5]
 mcr p15,0,r4,c2,c0,0
 mov r0,#5
 mcr p15,0,r0,c3,c0,0
 mrc p15,0,r0,c1,c0,0
 ldr r1,=0x1005
 orr r0,r0,r1
 mcr p15,0,r0,c1,c0,0
 nop
 nop
 ldr r8,=0x59800100
 mov r9,#0xa0
 mov r7,#0
 mov r0,#0xd0
 msr cpsr_c,r0
 // Repeat the identical handler to cover its warm instruction-fetch path.
 swi 0
 swi 0
 swi 0
 ldr r2,=0x20000100
 ldrh r1,[r2]
 cmp r1,#0xa0
 bne fail
 ldr r0,=0x50415353
 b finish
svc_handler:
 cmp r7,#2
 beq forced_user
 add r7,r7,#1
 // Exception return restores user CPSR while the older privileged store is
 // still approaching the TLB, matching the phone's final flash-program store.
 cmp r6,r6
 strh r9,[r8]
 movseq pc,lr
forced_user:
 mov r7,#3
 // LDRT remains an unprivileged access even inside SVC. Its force-user bit
 // must not be borrowed from the following ordinary CMP.
 mov r10,#0
 ldrt r1,[r8],#0
 cmp r10,#1
 bne fail
 movs pc,lr
data_abort:
 cmp r7,#3
 bne fail
 mrc p15,0,r1,c5,c0,0
 cmp r1,#0x1d
 bne fail
 mrc p15,0,r1,c6,c0,0
 cmp r1,r8
 bne fail
 mov r10,#1
 subs pc,lr,#4
fail: mov r0,#0xd2
finish:
 ldr r12,=0xf0000000
 str r0,[r12]
3: b 3b
.ltorg
