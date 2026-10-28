.syntax unified
.cpu arm920t
.arm
.equ RAM, 0x80000000
.equ MAILBOX, 0xf0000000
.equ SUCCESS, 0x50415353

.section .vectors, "ax"
.global _start
_start:
    b reset_entry
    b undefined_handler
    b swi_handler
    b prefetch_handler
    b data_abort
    b reserved_handler
    b irq_handler
    b fiq_handler

.section .text, "ax"
undefined_handler:
    mov r0, #0xe1
    b finish
.ifndef CUSTOM_PREFETCH
prefetch_handler:
    mov r0, #0xe3
    b finish
.endif
reserved_handler:
    mov r0, #0xe5
    b finish
irq_handler:
    mov r0, #0xe6
    b finish
fiq_handler:
    mov r0, #0xe7
    b finish
.ifndef CUSTOM_SWI
swi_handler:
    mov r0, #0xe2
    b finish
.endif
.ifndef CUSTOM_ABORT
data_abort:
    mov r0, #0xe4
    b finish
.endif
finish:
    ldr r12, =MAILBOX
    str r0, [r12]
1:  b 1b
pass:
    ldr r0, =SUCCESS
    b finish
.ltorg
