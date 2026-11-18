#!/usr/bin/env python3
"""Actual CPU stalls, IRQ, precise abort and flushed MMIO-load exclusion."""
import argparse,json
from pathlib import Path
from bench import ROOT,IMAGE,cp,call,assemble,save,sha,smb


def program():
    prefix=smb.assembly(smb.fixture('forward')).split(' mov r11,#7',1)[0]
    prefix=prefix.replace(' b reset_entry\n .rept 7\n b fail\n .endr',
                          ' b reset_entry\n b fail\n b fail\n b fail\n b data_abort\n b fail\n b irq_handler\n b fail')
    text=prefix+'''
 ldr r0,=0x80001000
 ldr r1,=0x11223344
 str r1,[r0]
 ldr r8,=0x80001200
 mov r9,#0
 str r9,[r8]
 str r9,[r8,#4]
 ldr r2,[r0]
 ldr r1,=0x11223344
 cmp r2,r1
 bne fail
 msr cpsr_c,#0x53
 .rept 16
 nop
 .endr
.global irq_load
irq_load:
 ldr r2,[r0,#4]
 add r3,r2,#1
 .rept 48
 nop
 .endr
 ldr r1,=0x102
 cmp r3,r1
 bne fail
 ldr r8,=0x80001200
 ldr r9,[r8]
 cmp r9,#1
 bne fail
 msr cpsr_c,#0xd3
 ldr r4,=0xabc12345
 ldr r5,=0xdef67890
 ldr r6,=0xf0000004
 ldr r0,=0x90000000
 nop
.global fault_load
fault_load:
 ldr r4,[r0]
.global forbidden_fault_load
forbidden_fault_load:
 ldr r5,[r6]
 b fail
after_fault:
 ldr r1,=0xabc12345
 cmp r4,r1
 bne fail
 ldr r1,=0xdef67890
 cmp r5,r1
 bne fail
 ldr r8,=0x80001200
 ldr r9,[r8,#4]
 cmp r9,#1
 bne fail
 ldr r0,=0xf0000004
 ldr r6,=after_flush
 mov pc,r6
.global forbidden_flush_load
forbidden_flush_load:
 ldr r5,[r0]
 nop
after_flush:
 ldr r1,=0xdef67890
 cmp r5,r1
 bne fail
 mov r0,#0
 mcr p15,0,r0,c7,c14,0
 ldr r0,=0x50415353
 b finish
data_abort:
 mrc p15,0,r8,c6,c0,0
 ldr r9,=0x90000000
 cmp r8,r9
 bne fail
 mrc p15,0,r8,c5,c0,0
 and r8,r8,#15
 cmp r8,#5
 bne fail
 ldr r8,=0x80001200
 mov r9,#1
 str r9,[r8,#4]
 ldr r12,=after_fault
 movs pc,r12
irq_handler:
 ldr r8,=0x80001200
 mov r9,#1
 str r9,[r8]
 subs pc,lr,#4
fail:
 ldr r0,=0x4641494c
finish:
 ldr r1,=0xf0000000
 str r0,[r1]
 b .
.ltorg
'''
    # Keep each failed assertion at its own observable terminal PC.
    index=0
    while ' bne fail\n' in text:
        text=text.replace(' bne fail\n',f' bne fail_{index}\n',1)
        index+=1
    text+='\n'+''.join(f'fail_{i}:\n ldr r0,=0x4641494c\n ldr r1,=0xf0000000\n str r0,[r1]\n b .\n' for i in range(index))+'.ltorg\n'
    return text


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--build',type=Path,required=True);a=p.parse_args()
    out=(ROOT/a.build).resolve();manifest=json.loads((out/'manifest.json').read_text())
    exe=ROOT/manifest['executable'];assert sha(exe)==manifest['executable_sha256']
    raw,symbols=assemble(out,'safety',program())
    docker=['docker','run','--rm','--pull=never','--network','none','--platform','linux/arm64','-v',str(ROOT)+':/work','-w','/work','--entrypoint']
    rows=[]
    for iw,dw in [(0,0),(2,9)]:
        totals=[]
        for repeat in range(2):
            log=out/f'safety-{iw}-{dw}-{repeat}.log'
            call(docker+[cp(exe),IMAGE,'+program='+cp(out/'safety.hex'),'+payload='+cp(out/'empty.hex'),
                         '+firmware='+cp(out/'empty.hex'),'+begin_pc=1','+end_pc=2',f'+i_wait={iw}',
                         f'+d_wait={dw}','+inject_irq=1','+max_cycles=3000000','+ngage-compact-trace'],log)
            result=[l for l in log.read_text().splitlines() if l.startswith('RESULT ')]
            assert len(result)==1 and result[0].startswith('RESULT windows=0 ')
            totals.append(result[0])
        assert totals[0]==totals[1]
        rows.append(dict(profile=f'{iw}:{dw}',repeats_equal=2,result=totals[0]))
    save(out/'safety.json',dict(status='PASS',program_sha256=smb.digest(raw),symbols=symbols,rows=rows,
                               checks=['cold delayed load and dependent add','IRQ during offered load',
                                       'section translation fault exact FAR/FSR','fault destination unchanged',
                                       'younger fault-path MMIO load excluded','flushed MMIO load excluded']))
    print('PASS actual CPU stalls, IRQ, precise fault, destination sentinel and flushed MMIO exclusion')


if __name__=='__main__':main()
