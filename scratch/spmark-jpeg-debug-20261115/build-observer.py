from pathlib import Path
import subprocess,struct,inspect,json,hashlib,sys
sys.path.insert(0,'tools');import prepare_native_observer as native
p=Path(__file__).resolve().parent
hooks=[dict(name='after',address=0x503b356c,old=0xe92d4070,replay='push {r4,r5,r6,lr}',callers=[0xfff02cac,0xfff02d1c,0xfff02da8],arg='ldr r2,[sp,#16]'),dict(name='cancel',address=0x50399b90,old=0xe92d4010,replay='push {r4,lr}',callers=[0xfff02b64,0xfff02c00,0xfff02e28,0xfff02ef8,0xfff02f48,0xfff02f70,0xfff02fc0,0xfff02fe4,0xfff02ff4],arg='ldr r2,[r1,#8]'),dict(name='close',address=0x503b7484,old=0xe92d4000,replay='stmdb sp!,{lr}',callers=[0xfff02c08,0xfff02c28],arg='ldr r2,[r1]'),dict(name='stop',address=0x5039a268,old=0xe92d4010,replay='push {r4,lr}',callers=[0xfff02c2c],arg='ldr r2,[sp,#12]')]
asm='''.syntax unified
.cpu arm920t
.arm
.section .text,"ax"
.macro save
 stmdb sp!,{r0-r12,lr}
 sub sp,sp,#8
 mrs r12,cpsr
 str r12,[sp]
.endm
.macro restore
 ldr r12,[sp]
 msr cpsr_f,r12
 add sp,sp,#8
 ldmia sp!,{r0-r12,lr}
.endm
'''
for h in hooks:
 name=h['name'];asm+=f'.global jpeg_{name}\njpeg_{name}:\n save\n ldr r3,[sp,#60]\n'
 for caller in h['callers']:asm+=f' ldr r12,={caller:#x}\n cmp r3,r12\n beq emit_{name}\n'
 asm+=f' b done_{name}\nemit_{name}:\n ldr r1,[sp,#8]\n {h["arg"]}\n ldr r0,=fmt_{name}\n bl debug_print\ndone_{name}:\n restore\n {h["replay"]}\n b {h["address"]+4:#x}\n'
for h in hooks:
 name=h['name'];s=f'J {name.upper()} obj=%08x value=%08x caller=%08x';asm+=f'.balign 4\nfmt_{name}: .word {0x10000000|len(s):#x},str_{name}\nstr_{name}: .hword '+','.join(str(ord(c)) for c in s)+'\n'
asm+='\n.balign 4\n.ltorg\n';(p/'trace.S').write_text(asm)
(p/'trace.ld').write_text('debug_print = 0x503b409c; SECTIONS { .text 0x511bc000 : { *(.text*) } /DISCARD/ : { *(.ARM.attributes) *(.comment) *(.note*) } }')
for cmd in [['arm-none-eabi-gcc','-c','-mcpu=arm920t',str(p/'trace.S'),'-o',str(p/'trace.o')],['arm-none-eabi-ld','-T',str(p/'trace.ld'),str(p/'trace.o'),'-o',str(p/'trace.elf')],['arm-none-eabi-objcopy','-O','binary',str(p/'trace.elf'),str(p/'trace.bin')]]:subprocess.run(cmd,check=True)
blob=(p/'trace.bin').read_bytes();assert len(blob)<4096 and len(blob)%4==0
symtext=subprocess.check_output(['arm-none-eabi-nm',str(p/'trace.elf')],text=True);(p/'symbols.txt').write_text(symtext);syms={a[2]:int(a[0],16) for l in symtext.splitlines() if len(a:=l.split())==3}
rom=Path('build/firmware/nem4-factory/core.bin').read_bytes();extra=[(0x11bc000+i,0xffffffff,struct.unpack_from('<I',blob,i)[0]) for i in range(0,len(blob),4)]
for h in hooks:
 a=h['address'];assert struct.unpack_from('<I',rom,a-0x50000000)[0]==h['old'];target=syms['jpeg_'+h['name']];extra.append((a-0x50000000,h['old'],0xea000000|(((target-a-8)//4)&0xffffff)))
s=inspect.getsource(native.prepare).replace("payload = (ROOT / 'build/firmware-overlays/exit-trace/trace.bin').read_bytes()",'payload = payload_bytes').replace('records = runtime.exit_records(payload, slow_wait=slow_wait)','records = list(extra_records)').replace('observer_sha256=runtime.EXIT_TRACE_SHA','observer_sha256=hashlib.sha256(payload).hexdigest()')
ns=dict(vars(native),extra_records=extra,payload_bytes=blob);exec(compile(s,'prepare_jpeg_observer','exec'),ns);r=ns['prepare'](p/'prepared',False)
r.update(scope='SPMark JPEG-only original RTimer After/CActive Cancel/handle Close/scheduler Stop; observation only, no changed deadlines/results/firmware behavior',hooks=hooks,trace_base=0x511bc000)
(p/'observer-manifest.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r,indent=2))
