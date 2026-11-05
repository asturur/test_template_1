.syntax unified
.cpu arm920t
.arm
.equ MAILBOX, 0xf0000000
.section .vectors, "ax"
.global _start
_start:
 b reset_entry
 b fail
 b fail
 b fail
 b fail
 b fail
 b irq_handler
 b irq_handler
.section .text, "ax"
reset_entry:
 mov r5, #0
 mov r6, #0
 mov r7, #0
 mrs r0, cpsr
#ifdef WFI_FIQ
 bic r0, r0, #0x40      @ FIQ enabled
#elif !defined(WFI_MASKED)
 bic r0, r0, #0x80      @ IRQ enabled
#endif
 msr cpsr_c, r0
 mov r0, #0
 mcr p15, 0, r0, c7, c0, 4 @ WFI
 add r5, r5, #1
 cmp r5, #1
 bne fail
#ifdef WFI_MASKED
 cmp r6, #0             @ masked IRQ wakes, but does not enter handler
#else
 cmp r6, #1
#endif
 bne fail
 cmp r7, #0
 bne fail
 ldr r0, =0x50415353
 b finish
irq_handler:
 cmp r5, #0              @ handler must precede post-WFI instruction
 movne r7, #1
 add r6, r6, #1
 subs pc, lr, #4
fail:
 mov r0, #0xd1
finish:
 ldr r12, =MAILBOX
 str r0, [r12]
1: b 1b
.ltorg
