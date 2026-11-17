"""Targeted real-CPU additions outside the unchanged measured store stream."""
def qualify(text):
 text=text.replace(' ldr r12,=0x70000000', ' ldr r7,=0x76543210\n ldr r12,=0x70000000')
 text=text.replace(' ldr r0,[r12]\n.global forbidden_fault_store', ' ldr r0,[r12]\n.global forbidden_fault_load\nforbidden_fault_load: ldr r7,[r10,#4]\n.global forbidden_fault_store')
 text=text.replace('after_fault:\n', '''after_fault:
 ldr r6,=0x76543210
 cmp r7,r6
 bne fail
.global safety_same_rd
safety_same_rd: ldr r6,[r10,#4]
 ldr r6,[r10,#24]
 cmp r6,#0x106
 bne fail
 ldr r6,=0x80001004
 str r6,[r10,#40]
.global safety_address_dep
safety_address_dep: ldr r6,[r10,#40]
 ldr r7,[r6]
 cmp r7,#0x101
 bne fail
.global safety_same_address
safety_same_address: ldr r6,[r10,#4]
 ldr r7,[r10,#4]
 cmp r6,r7
 bne fail
.global safety_ldm
safety_ldm: ldmia r10,{r6,r7}
 cmp r6,#0x100
 bne fail
 cmp r7,#0x101
 bne fail
.global safety_writeback
safety_writeback: ldr r6,[r10],#4
 sub r10,r10,#4
 cmp r6,#0x100
 bne fail
 cmp r6,r6
.global safety_wrong_path
safety_wrong_path: ldrne r7,[r10,#24]
 cmp r7,#0x101
 bne fail
.global safety_pair
safety_pair: ldr r6,[r10,#4]
 ldr r7,[r10,#24]
 cmp r6,#0x101
 bne fail
 cmp r7,#0x106
 bne fail
''')
 for reg,value in [('r7','0x101'),('r6','0x101'),('r6','0x106'),('r7','0x106')]:
  text=text.replace(' cmp '+reg+',#'+value, ' ldr r12,='+value+'\n cmp '+reg+',r12')
 text=text.replace('for repeat in range(2):', '''a.arg += ['+load_safety=1'] + ['+'+key+'='+format(symbols[key],'x') for key in ['forbidden_fault_load','safety_same_rd','safety_address_dep','safety_same_address','safety_ldm','safety_writeback','safety_wrong_path','safety_pair']]
for repeat in range(2):''')
 return text
