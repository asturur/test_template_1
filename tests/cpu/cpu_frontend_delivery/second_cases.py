"""New architectural producer/order cases on top of the passing 4F guest."""
def qualify(text):
 block='''
 // Distinct producer values; ordinary independent store bases.
 ldr r12,=0x80001840
 ldr r0,=0x11223344
 str r0,[r12]
 ldr r0,=0x55667788
 str r0,[r12,#4]
 ldr r5,=0x80001040
 ldr r0,[r5]
 mov r0,r5
 .balign 32
 ldr r6,[r12]
 ldr r7,[r12,#4]
.global second_first_ok
second_first_ok: str r7,[r5]
.global second_distinct
second_distinct: str r6,[r5,#4]
 ldr r0,[r5]
 ldr r1,=0x55667788
 cmp r0,r1
 bne fail
 ldr r0,[r5,#4]
 ldr r1,=0x11223344
 cmp r0,r1
 bne fail
 // A younger ALU writer must win over the older load.
 .balign 32
 ldr r6,[r12]
 mov r6,#0x55
 str r0,[r5]
.global second_overwrite_alu
second_overwrite_alu: str r6,[r5,#4]
 ldr r0,[r5,#4]
 cmp r0,#0x55
 bne fail
 // Same physical Rd: choose the younger load, never the older R6 owner.
 .balign 32
 ldr r6,[r12]
 ldr r6,[r12,#4]
 str r0,[r5]
.global second_overwrite_load
second_overwrite_load: str r6,[r5,#4]
 ldr r0,[r5,#4]
 ldr r1,=0x55667788
 cmp r0,r1
 bne fail
 // Already committed data uses the existing operand/commit path.
 ldr r6,[r12]
 mov r0,r6
 nop
 nop
 nop
.global second_committed
second_committed: str r6,[r5,#4]
 ldr r0,[r5,#4]
 ldr r1,=0x11223344
 cmp r0,r1
 bne fail
 // Banked FIQ R8/R9 use physical identities; SVC R8/R9 must survive.
 msr cpsr_c,#0xd1
 ldr r12,=0x80001840
 mov r0,r12
 .balign 32
 ldr r8,[r12]
 ldr r9,[r12,#4]
 str r9,[r5]
.global second_banked
second_banked: str r8,[r5,#4]
 msr cpsr_c,#0x53
 cmp r8,#0
 bne fail
 cmp r9,#1
 bne fail
 ldr r0,[r5,#4]
 ldr r1,=0x11223344
 cmp r0,r1
 bne fail
 // Intervening source load faults: neither younger store may publish.
 ldr r0,=0xaabbccdd
 str r0,[r5]
 str r0,[r5,#4]
 mov r8,#3
 ldr r4,=0x70000000
 mov r0,r4
 .balign 32
 ldr r6,[r12]
 ldr r7,[r4]
.global second_intervening_first
second_intervening_first: str r7,[r5]
.global second_intervening_second
second_intervening_second: str r6,[r5,#4]
 b fail
.global after_second_intervening
after_second_intervening:
 ldr r0,[r5]
 ldr r1,=0xaabbccdd
 cmp r0,r1
 bne fail
 ldr r0,[r5,#4]
 cmp r0,r1
 bne fail
 // First store's AP fault kills the prepared second store.
 ldr r4,=0x80010000
 ldr r0,=0x12345678
 str r0,[r4]
 ldr r4,=0x81010000
 mov r0,r4
 mov r8,#4
 .balign 32
 ldr r6,[r12]
 ldr r7,[r12,#4]
.global second_permission_first
second_permission_first: str r7,[r4]
.global second_permission_second
second_permission_second: str r6,[r5,#4]
 b fail
.global after_second_permission
after_second_permission:
 ldr r0,[r5,#4]
 ldr r1,=0xaabbccdd
 cmp r0,r1
 bne fail
 ldr r4,=0x80010000
 ldr r0,[r4]
 ldr r1,=0x12345678
 cmp r0,r1
 bne fail
 // Actual redirect flushes both wrong-path store owners.
 .balign 32
 ldr r6,[r12]
 b after_second_redirect
.global second_redirect_first
second_redirect_first: str r0,[r5]
.global second_redirect_second
second_redirect_second: str r6,[r5,#4]
after_second_redirect:
 ldr r0,[r5,#4]
 ldr r1,=0xaabbccdd
 cmp r0,r1
 bne fail
 mov r8,#0
 ldr r1,=0x11111111
 ldr r2,=0x22222222
 ldr r3,=0x33333333
 ldr r4,=0x44444444
 ldr r0,[r10]
 ldr r0,[r10,#32]
 ldr r0,[r10]
 ldr r0,[r10,#32]
'''
 text=text.replace(' mov r11,#7\nsample_loop:',block+' mov r11,#7\nsample_loop:')
 text=text.replace('abort_handler:\n cmp r8,#1','''abort_handler:
 cmp r8,#3
 beq second_intervening_handler
 cmp r8,#4
 beq second_permission_handler
 cmp r8,#1''')
 handlers='''second_intervening_handler:
 mrc p15,0,r0,c6,c0,0
 ldr r4,=0x70000000
 cmp r0,r4
 bne fail
 mrc p15,0,r0,c5,c0,0
 and r0,r0,#15
 cmp r0,#5
 bne fail
 mov r8,#0
 ldr r4,=after_second_intervening
 movs pc,r4
second_permission_handler:
 mrc p15,0,r0,c6,c0,0
 ldr r4,=0x81010000
 cmp r0,r4
 bne fail
 mrc p15,0,r0,c5,c0,0
 and r0,r0,#15
 cmp r0,#13
 bne fail
 mov r8,#0
 ldr r4,=after_second_permission
 movs pc,r4
'''
 text=text.replace('late_fault_handler:\n',handlers+'late_fault_handler:\n')
 names=['second_banked','second_first_ok','second_distinct','second_overwrite_alu','second_overwrite_load','second_committed','second_intervening_first','second_intervening_second','second_permission_first','second_permission_second','second_redirect_first','second_redirect_second']
 text=text.replace('for repeat in range(2):',"a.arg += ['+second_safety=1'] + ['+'+key+'='+format(symbols[key],'x') for key in "+repr(names)+"]\nfor repeat in range(2):")
 return text
