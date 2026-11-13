.syntax unified
.arm
.global _start
_start:
 ldr sp,=0x800cf000
 mov r0,#0
 ldr r1,=0x007f4000
 ldr r12,=0x5167ef29
 mov lr,pc
 bx r12
 cmp r0,#0
 bne fail
 // Native routine must clear its in-flight owner and return to array mode.
 ldr r1,=0x800cae14
 ldr r0,[r1]
 cmp r0,#0
 bne fail
 ldr r1,=0x007f4000
 ldr r0,[r1]
 cmn r0,#1
 bne fail
 // Exercise the native AMD sector eraser as well. The fixture supplies
 // only chip base0 and a104MHz delay calibration; instructions stay original.
 mov r0,#0
 ldr r1,=0x007f8000
 ldr r12,=0x5167f1c5
 mov lr,pc
 bx r12
 cmp r0,#0
 bne fail
 // Follow with the original AMD single-halfword program routine, including
 // its trailing20 command. Do not leave the controller armed for an erase.
 mov r0,#0
 ldr r1,=0x007f4000
 adr r2,payload
 mov r3,#1
 ldr r12,=0x5167f095
 mov lr,pc
 bx r12
 cmp r0,#0
 bne fail
 ldr r1,=0x007f4000
 ldr r0,[r1]
 ldr r1,=0xffff1234
 cmp r0,r1
 bne fail
 ldr r0,=0xf0000000
 ldr r1,=0x50415353
 str r1,[r0]
 b .
fail:
 ldr r0,=0xf0000000
 mov r1,#0
 str r1,[r0]
 b .

.balign 4
payload: .hword 0x1234,0
