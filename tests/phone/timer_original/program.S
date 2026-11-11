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
.macro call address
 ldr ip,=\address
 mov lr,pc
 bx ip
.endm
.macro control unit,value
 mov r0,#\unit
 mov r1,#\value
 call 0x50324958
.endm
.macro acknowledge unit,value
 mov r0,#\unit
 mov r1,#\value
 call 0x50324a20
.endm
reset:
 ldr sp,=0x8001f000
 // Execute the ORIGINAL bootstrap initialization, including CPSR operation.
 call 0x00003200
 mov r0,#1
 bl checked
 control 0,0
 acknowledge 0,1
 // The kernel tick's original setup helpers, with its actual 406250 reload.
 control 0,2
 mov r0,#0
 ldr r1,=406250
 call 0x503249d0
 mov r0,#0
 mov r1,#64
 call 0x503249f4
 // Tick already 10 and callback registered: exercise full original ISR
 // without scheduling its first-ever tick DFC. The callback is test-owned.
 ldr r0,=0x80000010
 mov r1,#10
 str r1,[r0]
 ldr r0,=0x8000000c
 mov r1,#1
 str r1,[r0]
 ldr r0,=0x8000030c
 adr r1,callback
 str r1,[r0]
 mov r1,#0
 str r1,[r0,#4]
 ldr r4,=0x58120a08
 bl wait_status
 mov r0,#0
 call 0x503225b0
 mov r0,#2
 bl checked
 control 0,0
 acknowledge 0,0
 // Original high-resolution init's three MMIO helper calls. Its scheduler
 // object registration is outside this timer fixture and has no substitute.
 control 0x20,1
 mov r0,#0x20
 ldr r1,=0x7fffffff
 call 0x503249f4
 acknowledge 0x20,0
 // Execute the complete original high-resolution start/reprogram routine.
 ldr r0,=0x80001000
 ldr r1,=1000
 call 0x50322b10
 ldr r4,=0x58120a28
 bl wait_status
 // ISR state: a DFC is already queued, so the original ACK path returns.
 ldr r0,=0x80001000
 mov r1,#1
 str r1,[r0,#0x14]
 call 0x50322ac0
 mov r0,#3
 bl checked
 // Reprogram after one-shot completion, then stop through original helper.
 ldr r0,=0x80001000
 ldr r1,=10000
 call 0x50322b10
 control 0x20,0
 mov r0,#0x20
 call 0x503249e8
 mov r4,r0
 mov r6,#30
1: subs r6,r6,#1
 bne 1b
 mov r0,#0x20
 call 0x503249e8
 cmp r0,r4
 bne fail
 mov r0,#4
 bl checked
 // Full original synchronous timer2 delay. No patch or scheduler stub.
 mov r0,#256
 call 0x50323f4c
 mov r0,#5
 bl checked
 // Re-enter the unchanged delay immediately: stale completion must not make
 // the second call return while its newly programmed count is still running.
 mov r0,#256
 call 0x50323f4c
 mov r0,#6
 bl checked
 // Original medint arm imports and FIQ ACK instructions are in retained ROM.
 // Program reload through its real import, then arm ctrl/count/ACK helpers.
 mov r0,#0x60
 ldr r1,=390
 call 0x50387e18
 control 0x60,2
 mov r0,#0x60
 ldr r1,=390
 call 0x50387d4c
 mov r0,#0x60
 mov r1,#0
 call 0x50387d58
 ldr r4,=0x58120a68
 bl wait_status
 acknowledge 0x60,0
 mov r0,#7
 bl checked
 ldr r0,=0x50415353
 b finish
wait_status:
 ldr r1,[r4]
 cmp r1,#0
 beq wait_status
 bx lr
callback:
 ldr r0,=0x80001040
 ldr r1,[r0]
 add r1,r1,#1
 str r1,[r0]
 bx lr
checked:
 ldr r1,=0xe0000000
 str r0,[r1]
 bx lr
fail:
 ldr r0,=0xfa110001
finish:
 ldr r1,=0xf0000000
 str r0,[r1]
 b .
.ltorg
