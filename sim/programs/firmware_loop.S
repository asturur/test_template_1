.syntax unified
.cpu arm920t
.arm
.section .vectors, "ax"
.global _start
_start:
#ifdef IRQ_ENABLED
    msr cpsr_c, #0x53
#endif
loop:
    b loop
.org 0x830
    .word 2, 1
    .word 0, 0x1000, 1, 0
    .word 0x0a000000, 0x01000000, 2, 0
.org 0x900
    .word 0
