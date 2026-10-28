// Independent timer IRQ entry, acknowledged deassertion, and exception return.
.syntax unified
.cpu arm920t
.arm
.section .vectors, "ax"
.global _start
_start:
    b reset_entry
.org 0x18
    b irq_handler
.org 0x20
.section .text, "ax"
reset_entry:
    msr cpsr_c, #0xd2
    ldr sp, =0x0a007000
    msr cpsr_c, #0xd3
    ldr sp, =0x0a006000
    ldr r1, =0x0c120a04
    mov r0, #2
    str r0, [r1]
    ldr r1, =0x0c120a18
    ldr r0, =0x0115b5c0
    str r0, [r1]
    ldr r1, =0x0c120108
    mov r0, #1
    str r0, [r1]
#ifdef MASK_IRQ
    msr cpsr_c, #0x93
#else
    msr cpsr_c, #0x53
#endif
wait_for_irq:
    b wait_for_irq
resume_after_irq:
    ldr r1, =0x0bad0000
    mov r0, #42
    str r0, [r1]
    b .
irq_handler:
    ldr r1, =0x0c120a08
    mov r0, #1
    str r0, [r1]
    add lr, lr, #4
    subs pc, lr, #4
.ltorg
.org 0x810
    .word 2, 1
    .word 0, 0x1000, 1, 0
    .word 0x0a000000, 0x01000000, 2, 0
.org 0x900
    .word 0
