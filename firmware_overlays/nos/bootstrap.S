/* SPDX-License-Identifier: GPL-3.0-or-later
 * Adapted from Nortido's service-table initializer; see NOTICE.md.
 */
.syntax unified
.arm
.global nos_bootstrap
.type nos_bootstrap, %function
nos_bootstrap:
    ldr r1, =0x80006bc4
    ldr r2, [r1]
    cmp r2, #0
    bne done
    ldr r3, =0x50324598
    ldr r12, =0x80006f64
    mov r0, #128
fill:
    str r3, [r12], #4
    subs r0, r0, #1
    bne fill
    ldr r0, =0x800004ac
    adr r3, bind
    str r3, [r0]
    ldr r3, =0x80006f64
    adr r0, clear
    str r0, [r3, #72]
    ldr r0, =0x80006f60
    str r3, [r0]
    ldr r0, =0x80006f00
    str r3, [r0]
    str r2, [r0, #4]
    str r2, [r0, #8]
    str r2, [r0, #12]
    add r3, r0, #16
    str r3, [r0, #16]
    str r3, [r0, #20]
    mov r3, #4
    str r3, [r0, #24]
    str r0, [r1]
    ldr r1, =0x8000038c
    ldr r1, [r1]
    cmp r1, #0
    beq done
    ldr r0, =0x80006f60
    ldr r3, [r1, #40]
    cmp r3, #0
    streq r0, [r1, #40]
    ldr r3, [r1, #52]
    cmp r3, #0
    streq r0, [r1, #52]
done:
    mov r0, #0
    mov pc, lr
    .ltorg
bind:
    ldr r3, =0x80006f64
    str r3, [r0, #4]
    mov pc, lr
clear:
    mov r0, #0
    cmp r3, #0
    moveq pc, lr
    tst r3, #3
    streq r0, [r3]
    strhne r0, [r3]
    mov pc, lr
    .ltorg
