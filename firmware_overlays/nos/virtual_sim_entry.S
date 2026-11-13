// SPDX-License-Identifier: GPL-3.0-or-later
.syntax unified
.thumb
.section .entry,"ax"
.global virtual_sim_indication
.thumb_func
virtual_sim_indication:
    bx pc
    nop
.arm
    b virtual_sim_broadcast
.thumb
.section .entry,"ax"
.global virtual_selftest_send
.thumb_func
virtual_selftest_send:
    bx pc
    nop
.arm
    b virtual_selftest_trace
