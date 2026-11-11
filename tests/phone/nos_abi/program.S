.syntax unified
.cpu arm920t
.arm
.section .vectors,"ax"
.global _start
_start: b reset
.rept 7
 b fail
.endr
.section .text,"ax"
reset:
 ldr sp,=0x8001f000
 ldr r4,=cases
 mov r5,#4
next_case:
 ldmia r4!,{r0-r3}
 bl run_case
 subs r5,r5,#1
 bne next_case
 bl receive_tests
 bl charger_tests
 ldr r0,=0x50415353
 b finish

// Execute the original kernel cancel loop, its completion helper, the LDD
// thunk and the original endpoint. Only the fixture callback records the ABI.
run_case:
 push {r4-r11,lr}
 mov r8,r0
 mov r9,r1
 mov r10,r2
 mov r11,r3
 ldr r4,=0x80000000
 mov r0,#0
 mov r1,#0x800
clear_fixture:
 str r0,[r4],#4
 subs r1,r1,#4
 bne clear_fixture
 ldr r4,=0x80000000
 ldr r0,=0x80000600
 str r0,[r4]
 ldr r0,=0x80000200
 str r0,[r4,#0x14]
 str r9,[r4,#0x30]
 ldr r0,=0x80000100
 str r0,[r4,#0x38]
 ldr r1,=0x5171103c
 str r1,[r0,#4]
 ldr r0,=0x80000600
 ldr r1,=cancel_callback
 str r1,[r0,#0x1c]
 ldr r0,=0x80000200
 mov r1,#3
 str r1,[r0,#0x24]
 str r1,[r0,#0x14]
 ldr r1,=0x80000300
 str r1,[r0,#0x5c]
 mov r6,#0
 mov r7,#1
init_status:
 ldr r0,=0x80000400
 add r0,r0,r6,lsl#2
 ldr r1,=0xdeadbeef
 str r1,[r0]
 tst r10,r7
 add r2,r4,#0x18
 strne r0,[r2,r6,lsl#2]
 add r6,r6,#1
 lsl r7,r7,#1
 cmp r6,#6
 bne init_status
 mov r0,r4
 mov r1,r8
 ldr r2,=0x503350e4
 mov lr,pc
 bx r2
 bl verify
 // Repeat cancel must not touch the cleared slots or signal again.
 mov r0,r4
 mov r1,r8
 ldr r2,=0x503350e4
 mov lr,pc
 bx r2
 bl verify
 pop {r4-r11,pc}

verify:
 push {r4-r7,lr}
 ldr r0,=0x80000680
 ldr r1,[r0]
 cmp r1,r11
 bne fail
 ldr r2,[r0,#4]
 ldr r3,=0x80000314
 ldr r3,[r3]
 cmp r2,r3
 bne fail
 mov r6,#0
 mov r7,#1
verify_status:
 add r0,r4,#0x18
 ldr r1,[r0,r6,lsl#2]
 ldr r0,=0x80000400
 add r0,r0,r6,lsl#2
 tst r11,r7
 bne was_cancelled
 tst r10,r7
 moveq r0,#0
 cmp r1,r0
 bne fail
 ldr r0,=0x80000400
 ldr r1,[r0,r6,lsl#2]
 ldr r0,=0xdeadbeef
 cmp r1,r0
 bne fail
 b checked
was_cancelled:
 cmp r1,#0
 bne fail
 ldr r1,[r0]
 mvn r0,#2
 cmp r1,r0
 bne fail
checked:
 add r6,r6,#1
 lsl r7,r7,#1
 cmp r6,#6
 bne verify_status
 pop {r4-r7,pc}

cancel_callback:
 push {r0-r4,lr}
 cmp r1,#6
 bhs fail
 ldr r2,=0x80000018
 ldr r2,[r2,r1,lsl#2]
 cmp r2,#0
 bne fail
 ldr r2,=0x80000400
 ldr r2,[r2,r1,lsl#2]
 mvn r3,#2
 cmp r2,r3
 bne fail
 ldr r2,=0x80000680
 ldr r3,[r2]
 mov r4,#1
 lsl r4,r4,r1
 tst r3,r4
 bne fail
 orr r3,r3,r4
 str r3,[r2]
 ldr r3,[r2,#4]
 add r3,r3,#1
 str r3,[r2,#4]
 pop {r0-r4,lr}
 ldr r2,=0x511b41e8
 bx r2

fail:
 ldr r0,=0xfa110001
finish:
 ldr r1,=0xf0000000
 str r0,[r1]
 b .
.ltorg
cases:
.word 1,7,1,1
.word 5,7,7,5
.word 3,2,3,2
.word 3,7,4,0

// Exercise the original mailbox pump with a short descriptor, cancellation
// before retry, a successful retry and an idle pump after completion.
receive_tests:
 push {r4-r11,lr}
 ldr r0,=0x8000c700
 mov r1,#0
 mov r2,#0x500
clear_mailboxes:
 str r1,[r0],#4
 subs r2,r2,#4
 bne clear_mailboxes
 ldr r4,=0x80000000
 ldr r0,=0x511b4538
 str r0,[r4]
 ldr r0,=0x80000200
 str r0,[r4,#0x14]
 mov r1,#3
 str r1,[r0,#0x24]
 str r1,[r0,#0x14]
 ldr r1,=0x80000300
 str r1,[r0,#0x5c]
 mov r2,#0
 str r2,[r1,#0x14]
 mov r1,#1
 str r1,[r4,#0x30]
 ldr r0,=0x80000100
 str r0,[r4,#0x38]
 mov r1,#5
 strb r1,[r0]
 ldr r1,=0x5171103c
 str r1,[r0,#4]
 ldr r0,=0x8000c738
 str r4,[r0]
 ldr r0,=0x8000c830
 ldr r1,=0x80001800
 str r1,[r0]
 ldr r0,=0x8000c7a0
 ldr r1,=0x80001900
 str r1,[r0]
 ldr r0,=0x8000c9b2
 mov r1,#12
 strh r1,[r0]
 ldr r0,=0x8000caf0
 ldr r1,=0x80001100
 str r1,[r0]
 ldr r2,=0x11223344
 str r2,[r1]
 ldr r2,=0x55667788
 str r2,[r1,#4]
 ldr r2,=0x99aabbcc
 str r2,[r1,#8]
 ldr r0,=0x8000ca73
 mov r1,#1
 strb r1,[r0]
 ldr r0,=0x80000700
 mov r1,#4
 str r1,[r0]                 // descriptor capacity
 mov r1,#0
 str r1,[r0,#4]              // normal-copy count
 str r1,[r0,#8]              // required-length-copy count
 ldr r0,=0x80000400
 str r0,[r4,#0x18]
 ldr r2,=0x514a10cc
 mov lr,pc
 bx r2
 ldr r0,=0x80000400
 ldr r1,[r0]
 mvn r2,#3
 cmp r1,r2
 bne fail
 ldr r0,=0x80002000
 ldrh r1,[r0]
 cmp r1,#12
 bne fail
 ldr r0,=0x80000700
 ldr r1,[r0,#4]
 cmp r1,#0
 bne fail
 ldr r1,[r0,#8]
 cmp r1,#1
 bne fail
 bl pending_retained
 // Re-arm a receive, cancel it using the original kernel, then pump.
 ldr r0,=0x80000400
 str r0,[r4,#0x18]
 mov r0,r4
 mov r1,#1
 ldr r2,=0x503350e4
 mov lr,pc
 bx r2
 ldr r2,=0x514a10cc
 mov lr,pc
 bx r2
 ldr r0,=0x80000400
 ldr r1,[r0]
 mvn r2,#2
 cmp r1,r2
 bne fail
 ldr r0,=0x80000314
 ldr r1,[r0]
 cmp r1,#2
 bne fail
 bl pending_retained
 // Sufficient capacity consumes the retained message through the original
 // TPtr8 constructor, then the real kernel completion and pending clear.
 ldr r0,=0x80000700
 mov r1,#12
 str r1,[r0]
 ldr r0,=0x80000400
 str r0,[r4,#0x18]
 ldr r2,=0x514a10cc
 mov lr,pc
 bx r2
 ldr r0,=0x80000400
 ldr r1,[r0]
 cmp r1,#0
 bne fail
 ldr r0,=0x8000ca73
 ldrb r1,[r0]
 cmp r1,#0
 bne fail
 ldr r0,=0x80002100
 ldmia r0,{r1-r3}
 ldr r0,=0x11223344
 cmp r1,r0
 bne fail
 ldr r0,=0x55667788
 cmp r2,r0
 bne fail
 ldr r0,=0x99aabbcc
 cmp r3,r0
 bne fail
 ldr r2,=0x514a10cc
 mov lr,pc
 bx r2
 ldr r0,=0x80000314
 ldr r1,[r0]
 cmp r1,#3
 bne fail
 ldr r0,=0x80000700
 ldr r1,[r0,#4]
 cmp r1,#1
 bne fail
 ldr r1,[r0,#8]
 cmp r1,#1
 bne fail
 pop {r4-r11,pc}

pending_retained:
 ldr r0,=0x8000ca73
 ldrb r1,[r0]
 cmp r1,#1
 bne fail
 ldr r0,=0x8000caf0
 ldr r1,[r0]
 ldr r0,=0x80001100
 cmp r1,r0
 bne fail
 ldr r0,=0x8000c9b2
 ldrh r1,[r0]
 cmp r1,#12
 bne fail
 bx lr

descriptor_capacity:
 ldr r2,=0x80001800
 cmp r1,r2
 bne fail
 ldr r2,=0x80000200
 cmp r0,r2
 bne fail
 ldr r0,=0x80000700
 ldr r0,[r0]
 bx lr

descriptor_write16:
 ldr ip,=0x80000200
 cmp r0,ip
 bne fail
 ldr ip,=0x80001900
 cmp r1,ip
 bne fail
 ldr r0,[r2]
 ldr r1,=0x20000001
 cmp r0,r1
 bne fail
 ldr r0,[r2,#4]
 cmp r0,#1
 bne fail
 ldr r0,[r2,#8]
 ldrh r0,[r0]
 ldr r1,=0x80002000
 strh r0,[r1]
 ldr r1,=0x80000708
 ldr r0,[r1]
 add r0,r0,#1
 str r0,[r1]
 mov r0,#0
 bx lr

descriptor_write8:
 ldr ip,=0x80000200
 cmp r0,ip
 bne fail
 ldr ip,=0x80001800
 cmp r1,ip
 bne fail
 cmp r3,#0
 bne fail
 ldr r0,[sp]
 cmp r0,#0
 bne fail
 ldr r0,[r2]
 ldr r3,=0x2000000c
 cmp r0,r3
 bne fail
 ldr r0,[r2,#4]
 cmp r0,#12
 bne fail
 ldr r0,[r2,#8]
 ldr r1,=0x80001100
 cmp r0,r1
 bne fail
 ldmia r0,{r0-r2}
 ldr r3,=0x80002100
 stmia r3,{r0-r2}
 ldr r1,=0x80000704
 ldr r0,[r1]
 add r0,r0,#1
 str r0,[r1]
 mov r0,#0
 bx lr

// Keep the original response allocator, builders and charger providers.
// The fixture substitutes only the pool allocation and reads charger state 0.
charger_tests:
 push {r4-r7,lr}
 ldr r4,=charger_cases
 mov r5,#5
charger_case:
 ldmia r4!,{r6,r7}
 ldr r0,=0x80003000
 ldr r1,=0x000008a1
 orr r1,r1,r6,lsl#16
 str r1,[r0]
 ldr r1,=0x80000710
 mov r2,#0
 str r2,[r1]
 ldr r2,=0x5159446d
 mov lr,pc
 bx r2
 ldr r1,=0x80003108
 cmp r0,r1
 bne fail
 ldr r1,[r0]
 cmp r1,r7
 bne fail
 ldr r1,=0x80003104
 ldrh r1,[r1]
 ldr r2,=0x80000710
 ldr r2,[r2]
 sub r2,r2,#6
 cmp r1,r2
 bne fail
 cmp r6,#1
 beq charger_status
 cmp r6,#2
 beq charger_raw
 cmp r6,#3
 bne charger_checked
 ldr r1,[r0,#8]
 ldr r2,=0x414
 cmp r1,r2
 bne fail
charger_status:
 ldr r1,[r0,#4]
 ldr r2,=0x00010413
 cmp r1,r2
 bne fail
 b charger_checked
charger_raw:
 ldr r1,[r0,#4]
 ldr r2,=0x414
 cmp r1,r2
 bne fail
charger_checked:
 subs r5,r5,#1
 bne charger_case
 pop {r4-r7,pc}

pool_allocate:
 ldr r1,=0x80000710
 str r0,[r1]
 ldr r0,=0x80003100
 bx lr
.ltorg
charger_cases:
.word 0,0x000209a1
.word 1,0x010109a1
.word 2,0x010109a1
.word 3,0x020109a1
.word 4,0x000209a1
