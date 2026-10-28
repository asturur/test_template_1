.syntax unified
.cpu arm920t
.arm
.section .vectors, "ax"
.global _start
_start:
    ldr pc, [pc, #-4]
    .word 0x90000000
    b .
    b .
// Synthetic table fixture for the board harness; no Nokia firmware is used.
.org 0x830
    .word 2, 1
    .word 0, 0x1000, 1, 0
    .word 0x0a000000, 0x01000000, 2, 0
.org 0x900
    .word 0
