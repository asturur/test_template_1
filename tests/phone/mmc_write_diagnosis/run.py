#!/usr/bin/env python3
"""Bounded authored-ARM CMD24 -> TX DMA -> real card -> modeled backing probe.
Copies selected HDL before compiling; uses no user card or phone. Run in the
existing jotego/simulator:arm64 container from /work. Generated files stay in
this investigation's build directory; production and other test outputs untouched.
"""
from pathlib import Path
import hashlib,json,re,shlex,subprocess,sys
root=Path.cwd(); out=root/'build/sim/mmc-write-diagnosis-20261117';out.mkdir(parents=True,exist_ok=True)
base=root/'tests/phone/mmc_mister'
s=(base/'program.S').read_text()
a=s.index(' // Read-only production media rejects writes');b=s.index(' // Filesystem sector reads:',a)
s=s[:a]+s[b:]
marker=' ldr r0,=0x0a000100\n put r0,0,0x50415353'
assert s.count(marker)==1
s=s.replace(marker,(root/'tests/phone/mmc_write_diagnosis/tx.S').read_text()+marker)
(out/'program.S').write_text(s)
def run(argv):
 r=subprocess.run(argv,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
 if r.returncode: print('\n'.join(r.stdout.splitlines()[-12:]));raise SystemExit(r.returncode)
 return r.stdout
if '--sim' not in sys.argv:
 run(['arm-none-eabi-gcc','-c','-mcpu=arm920t','-marm',str(out/'program.S'),'-o',str(out/'program.o')])
 run(['arm-none-eabi-ld','-T','sim/programs/link.ld',str(out/'program.o'),'-o',str(out/'program.elf')])
 run(['arm-none-eabi-objcopy','-O','binary',str(out/'program.elf'),str(out/'program.bin')])
prep=(base/'prepare.py').read_text().replace("out = root / 'build/sim/unit-mmc-mister'",f'out = Path({str(out)!r})')
prep=prep.replace("(1 << 77)","(1 << 77) | (9 << 22)")
exec(compile(prep,str(base/'prepare.py'),'exec'),{'__file__':str(base/'prepare.py')})
t=(base/'tb.v').read_text().replace('build/sim/unit-mmc-mister','build/sim/mmc-write-diagnosis-20261117')
t=t.replace('integer hstate=0','integer persisted=0; reg outgoing=0;\n integer hstate=0')
t=t.replace('   if(hps_write)$fatal(1,"read-only MMC emitted HPS write");','')
t=t.replace('if(hps_read)begin','if(hps_read || hps_write)begin\n      outgoing<=hps_write;')
t=t.replace('hps_reads<=hps_reads+1;','hps_reads<=hps_reads+(!hps_write);')
t=t.replace('if(!hps_read || hps_lba', 'if(!(outgoing ? hps_write : hps_read) || hps_lba')
t=t.replace('hps_ack<=1;hps_wr<=0;','hps_addr<=0;hps_ack<=1;hps_wr<=0;')
needle='      hps_addr<=hword;hps_data<=image[saved_lba*256+hword];hps_wr<=1;hdelay<=2;'
replacement='''      if(outgoing)begin
       if(saved_lba!=3 || hwords!=256)$fatal(1,"write extent/direction");
       if(hps_din !== {8'((hword*2+1)*37+'h69),8'((hword*2)*37+'h69)})
        $fatal(1,"persist mismatch word%0d got%h",hword,hps_din);
       image[saved_lba*256+hword]<=hps_din ^ (($test$plusargs("corrupt_persist") && hword==255) ? 16'd1 : 16'd0);
       hps_addr<=hword+1;hps_wr<=0;
       if(hword==255) persisted<=persisted+1;
      end else begin
       hps_addr<=hword;hps_data<=image[saved_lba*256+hword];hps_wr<=1;
      end
      hdelay<=5;'''
assert needle in t;t=t.replace(needle,replacement)
t=t.replace('reg [15:0] image[0:1279];','reg [15:0] image[0:1279], original_image[0:1279];')
t=t.replace('repeat(4)@(negedge clk);cold=0;', 'for(i=0;i<1280;i=i+1)original_image[i]=image[i];\n  repeat(4)@(negedge clk);cold=0;')
t=t.replace("if(saved_sa==25'h100)begin", """if(saved_sa==25'h100)begin
       for(j=0;j<1280;j=j+1)begin
        if(j>=768 && j<1024)begin
         if(image[j] !== {8'(((j-768)*2+1)*37+'h69),8'(((j-768)*2)*37+'h69)})
          $fatal(1,"independent persisted oracle mismatch halfword%0d",j);
        end else if(image[j] !== original_image[j])$fatal(1,"adjacent/footer changed%0d",j);
       end
""")
t=t.replace('|| !mmc_wp ||','|| mmc_wp || persisted!=1 ||')
t=t.replace('$display("PASS authored ARM production MMC identify/exact CID, DMA5+3padding, odd PIO, full512-byte DMA/PIO sectors, ICU21/23/24, read-only rejection cycles=%0d HPSreads=%0d hold=%0d",cycles,hps_reads,held_once);', '$display("PASS authored ARM CMD24 TX2-DMA actual card/backing persisted512bytes+PIOreadback cycles=%0d reads=%0d writes=%0d",cycles,hps_reads,persisted);')
(out/'tb.v').write_text(t)
# Preserve every HDL input before the release chat can promote unrelated CPU work.
command=(base/'run.sh').read_text().split("-c '",1)[1].split(" > build/sim/unit-mmc-mister/build.log",1)[0]
tokens=shlex.split(command)
files=[]
for token in tokens:
 if token.endswith(('.v','.sv')):
  files.extend(sorted(root.glob(token)) if '*' in token else [root/token])
# Includes are not command arguments.
files.extend(sorted((root/'rtl/arm').glob('*.svh')))
manifest={}
for p in files:
 rel=p.relative_to(root); dest=out/'source'/rel;dest.parent.mkdir(parents=True,exist_ok=True)
 data=(out/'tb.v').read_bytes() if p==base/'tb.v' else p.read_bytes()
 dest.write_bytes(data);manifest[str(rel)]=hashlib.sha256(data).hexdigest()
(out/'source-hashes.json').write_text(json.dumps(manifest,indent=2)+'\n')
if '--prepare' in sys.argv: raise SystemExit(0)
args=['verilator','--binary','--timing','--assert','-j','2','-Wno-fatal','-Wno-lint','-I'+str(out/'source/rtl/arm'),'--top-module','tb','--Mdir',str(out/'obj')]
args += [str(out/'source'/p.relative_to(root)) for p in files if p.suffix!='.svh']
with (out/'build.log').open('w') as log:
 result=subprocess.run(args,stdout=log,stderr=subprocess.STDOUT)
if result.returncode: raise SystemExit(result.returncode)
receipts=[]
for label, extra in [('normal',[]),('corrupt-persist',['+corrupt_persist'])]:
 result=subprocess.run([str(out/'obj/Vtb')]+extra,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
 (out/(label+'.log')).write_text(result.stdout)
 lines=[line for line in result.stdout.splitlines() if 'PASS authored ARM CMD24' in line or 'independent persisted oracle mismatch' in line]
 print('\n'.join(lines),flush=True)
 if not extra: assert result.returncode==0 and any('PASS' in line for line in lines)
 else: assert result.returncode!=0 and any('oracle mismatch' in line for line in lines)
 receipts.append(dict(case=label,exit_code=result.returncode,evidence=lines))
(out/'receipt.json').write_text(json.dumps(receipts,indent=2)+'\n')
