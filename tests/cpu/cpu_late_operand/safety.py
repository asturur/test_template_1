#!/usr/bin/env python3
"""Extend the existing real-CPU fault/IRQ guest with late arithmetic hazards."""
from setup import ROOT
path=ROOT/'tests/cpu/cpu_load_pipeline/safety.py'
s=path.read_text()
s=s.replace("'+inject_irq=1'", "'+inject_irq=1','+pipeline_trace=2'")
s=s.replace('after_flush:\n', '''after_flush:
 ldr r0,=0x80020000
 .rept 16
 nop
 .endr
.global late_cold_load
late_cold_load:
 ldr r2,[r0]
.global late_cold_consumer
late_cold_consumer:
 add r3,r2,#1
 cmp r3,#1
 bne fail
 ldr r0,=0x80001000
 ldr r1,=0x7fffffff
 str r1,[r0,#16]
 ldr r2,[r0,#16]
 add r2,r2,#1
 ldr r1,=0x80000000
 cmp r2,r1
 bne fail
 ldr r2,[r0,#16]
 cmp r2,#0
 movgt r3,#77
 movle r3,#88
 cmp r3,#77
 bne fail
 ldr r2,[r0,#16]
 mov r2,#5
 add r3,r2,#1
 cmp r3,#6
 bne fail
 ldr r2,[r0,#16]
 moveq r2,#11
 add r3,r2,#1
 cmp r3,#12
 bne fail
 ldr r2,[r0,#16]
 movne r2,#11
 add r3,r2,#1
 ldr r1,=0x80000000
 cmp r3,r1
 bne fail
 ldr r2,[r0,#16]
 cmp r2,#0x80000000
 movlt r3,#1
 movge r3,#2
 cmp r3,#2
 bne fail
''')
# A faulting producer must kill a younger dependent register write AND flags.
s=s.replace('forbidden_fault_load:\n ldr r5,[r6]', 'forbidden_fault_load:\n adds r5,r4,#1\n ldr r5,[r6]')
s=s.replace('fault_load:\n ldr r4,[r0]', 'fault_load:\n mov r7,#1\n cmp r7,r7\n .rept 16\n nop\n .endr\n ldr r4,[r0]')
s=s.replace('data_abort:\n', 'data_abort:\n mrs r8,spsr\n and r8,r8,#0xf0000000\n cmp r8,#0x60000000\n bne fail\n')
s=s.replace("'flushed MMIO load excluded'", "'flushed MMIO load excluded','CMP conditional flags including signed overflow','read-modify-write destination','second writer and true/false predicated writer','fault kills dependent register and flags'")
s=s.replace('[(0,0),(2,9)]','[(0,0),(2,9),(0,97)]')
exec(compile(s,str(path),'exec'))
