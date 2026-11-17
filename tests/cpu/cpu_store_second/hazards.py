"""Focused late-data guest, composed with the existing CPU fault/IRQ oracles."""
from safety import qualify as previous

def qualify(text):
 text=previous(text)
 # Descriptors are installed before enabling the MMU. Explicitly use S:R=0
 # for the AP0 store fault, and A=0 for the rotated-word fallback case.
 text=text.replace("program=prefix+'''", '''prefix=prefix.replace(' mcr p15,0,r4,c2,c0,0', ' ldr r0,=0x0a00000e\\n ldr r5,=0x2040\\n str r0,[r4,r5]\\n ldr r0,=0x0a000c02\\n ldr r5,=0x2080\\n str r0,[r4,r5]\\n mcr p15,0,r4,c2,c0,0')
prefix=prefix.replace(' orr r0,r0,#5', ' bic r0,r0,#0x300\\n bic r0,r0,#2\\n orr r0,r0,#5')
program=prefix+\'\'\'''' )
 text=text.replace(' ldr r7,=0x76543210', ' mov r8,#0\n ldr r7,=0x76543210',1)
 block='''
 // Prepare cold source and resident destination, then consume the exact load.
 ldr r12,=0x80001800
 ldr r6,=0x89abcdef
 str r6,[r12]
 ldr r5,=0x80001020
 ldr r0,=0xa5a5a5a5
 str r0,[r5]
 mov r0,#0
 mcr p15,0,r0,c7,c14,0
 ldr r0,[r5]
 .balign 32
.global late_success_load
late_success_load: ldr r6,[r12]
.global late_success_store
late_success_store: str r6,[r5]
 ldr r0,[r5]
 ldr r7,=0x89abcdef
 cmp r0,r7
 bne fail
 // A=0 word rotation cannot use the aligned raw completion: wait for B.
 .balign 32
.global late_rotated_load
late_rotated_load: ldr r6,[r12,#1]
.global late_rotated_store
late_rotated_store: str r6,[r5,#4]
 ldr r0,[r5,#4]
 ldr r7,=0xef89abcd
 cmp r0,r7
 bne fail
 // The address itself depends on the loaded register: retain the full lock.
 ldr r0,=0x80001030
 str r0,[r12,#4]
 .balign 32
.global late_base_load
late_base_load: ldr r6,[r12,#4]
.global late_base_store
late_base_store: str r6,[r6]
 ldr r0,[r6]
 cmp r0,r6
 bne fail
 // Device destination retains its checked, exactly-once external transaction.
 ldr r5,=0xf0000004
 .balign 32
.global late_device_load
late_device_load: ldr r6,[r10,#4]
.global late_device_store
late_device_store: str r6,[r5]
 ldr r0,[r5]
 ldr r7,=0x101
 cmp r0,r7
 bne fail
 // Uncacheable source is still an actual older demand, never speculative.
 ldr r5,=0x8000102c
 ldr r12,=0x82001004
 .balign 32
.global late_uncached_load
late_uncached_load: ldr r6,[r12]
.global late_uncached_store
late_uncached_store: str r6,[r5]
 ldr r0,[r5]
 ldr r7,=0x101
 cmp r0,r7
 bne fail
 // An older load faults after private store address work has begun.
 ldr r5,=0x80001028
 ldr r6,=0x76543210
 str r6,[r5]
 mov r8,#1
 ldr r12,=0x70000000
 .balign 32
.global late_fault_load
late_fault_load: ldr r6,[r12]
.global late_fault_store
late_fault_store: str r6,[r5]
 b fail
.global after_late_fault
after_late_fault:
 ldr r0,[r5]
 ldr r7,=0x76543210
 cmp r0,r7
 bne fail
 cmp r6,r7
 bne fail
 cmp r8,#0
 bne fail
 // The older load succeeds, but the younger store's own AP check fails.
 ldr r5,=0x80010000
 ldr r0,=0x55667788
 str r0,[r5]
 ldr r5,=0x81010000
 mov r7,r5
 mov r8,#2
 .balign 32
.global late_perm_load
late_perm_load: ldr r6,[r10,#4]
.global late_perm_store
late_perm_store: str r6,[r5]
 b fail
.global after_late_perm
after_late_perm:
 ldr r5,=0x80010000
 ldr r0,[r5]
 ldr r7,=0x55667788
 cmp r0,r7
 bne fail
 ldr r7,=0x101
 cmp r6,r7
 bne fail
 cmp r8,#0
 bne fail
'''
 block+=' ldr r0,[r10]\n ldr r0,[r10,#32]\n ldr r0,[r10]\n ldr r0,[r10,#32]\n'
 text=text.replace(' mov r11,#7\nsample_loop:', block+' mov r11,#7\nsample_loop:')
 old='abort_handler: ldr r12,=after_fault\n movs pc,r12'
 new='''abort_handler:
 cmp r8,#1
 beq late_fault_handler
 cmp r8,#2
 beq late_perm_handler
 ldr r12,=after_fault
 movs pc,r12
late_fault_handler:
 mrc p15,0,r0,c6,c0,0
 ldr r12,=0x70000000
 cmp r0,r12
 bne fail
 mrc p15,0,r0,c5,c0,0
 and r0,r0,#15
 cmp r0,#5
 bne fail
 mov r8,#0
 ldr r12,=after_late_fault
 movs pc,r12
late_perm_handler:
 mrc p15,0,r0,c6,c0,0
 ldr r12,=0x81010000
 cmp r0,r12
 bne fail
 mrc p15,0,r0,c5,c0,0
 and r0,r0,#15
 cmp r0,#13
 bne fail
 mov r8,#0
 ldr r12,=after_late_perm
 movs pc,r12'''
 assert old in text;text=text.replace(old,new)
 text=text.replace('for repeat in range(2):', '''a.arg += ['+late_safety=1'] + ['+'+key+'='+format(symbols[key],'x') for key in ['late_success_store','late_rotated_store','late_base_store','late_device_store','late_uncached_store','late_fault_store','late_perm_store']]
for repeat in range(2):''')
 from second_cases import qualify as second_qualify
 return second_qualify(text)
