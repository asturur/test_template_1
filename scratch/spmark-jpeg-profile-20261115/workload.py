from pathlib import Path
import struct,random,hashlib,json
from PIL import Image
BASE=0x50500000
ROM_SHA='be8b2ecdf5ff81f424b58838a8b93a1d1f65c0ae74890d2b96df8d5a7189b524'
JPEG=Path('scratch/spmark-benchmark-20261114/files/System/Apps/SPMark/TEST.JPG')
def words(v):return struct.pack('<%dI'%len(v),*(x&0xffffffff for x in v))
def make(mode=10,width=8,height=8,random_input=False):
 obj,conv,err,extra,src,dst=0x80000100,0x80000200,0x80001000,0x80002000,0x80004000,0x80003000
 rng=random.Random(151115)
 if random_input:pixels=[rng.randrange(1<<24) for _ in range(width*height)]
 else:
  im=Image.open(JPEG).convert('RGB');pixels=[r|(g<<8)|(b<<16) for r,g,b in im.crop((200,180,200+width,180+height)).get_flattened_data()]
 ob=bytearray(0xac)
 for off,val in {0:0x505af55c,0x18:0,0x1c:0,0x20:0,0x28:width,0x30:width,0x34:height,0x78:conv,0x88:dst+16,0x90:err+12,0x94:extra,0xa4:0,0xa8:0}.items():struct.pack_into('<I',ob,off,val)
 initial=[0]*(3*(width+3));cols=[[0,0,0] for _ in range(height)];line=[[0,0,0] for _ in range(width+3)];outputs=[];last_error=[0,0,0]
 for y in range(height):
  carry=[cols[y][i]+line[1][i] for i in range(3)];cols[y]=list(last_error)
  for x in range(width):
   p=pixels[y*width+x];rgb=[min(255,max(0,((p>>(8*i))&255)+(carry[i]>>4))) for i in range(3)]
   if mode==10:
    index=((rgb[0]>>4)<<8)|((rgb[1]>>4)<<4)|(rgb[2]>>4);quant=[(a>>4)*17 for a in rgb]
   elif mode==8:index=(rgb[0]<<16)|(rgb[1]<<8)|rgb[2];quant=list(rgb)
   else:raise ValueError(mode)
   outputs.append(index);e=[rgb[i]-quant[i] for i in range(3)];last_error=list(e)
   if x>0:line[x]=[line[x][i]+3*e[i] for i in range(3)]
   else:line[x+1]=[3*e[i] for i in range(3)]
   line[x+1]=[line[x+1][i]+5*e[i] for i in range(3)]
   carry=[7*e[i]+line[x+2][i] for i in range(3)];line[x+2]=list(e)
  cols[y]=[cols[y][i]+carry[i] for i in range(3)]
 expected=bytearray(ob);struct.pack_into('<I',expected,0xa4,width)
 guards=[0xa5a5a5a5]*4
 vtable={10:0x505af604,8:0x505af670}[mode]
 writes=[(obj,bytes(ob)),(conv,words([vtable])),(err,words(initial)),(extra,bytes(height*12)),(src,words(pixels)),(dst,words(guards+[0xa5a5a5a5]*(width*height)+guards))]
 checks=[(obj,bytes(expected)),(conv,words([vtable])),(err,words([v for row in line for v in row])),(extra,words([v for row in cols for v in row])),(src,words(pixels)),(dst,words(guards+outputs+guards))]
 return dict(id=f'diffuse_m{mode}_{width}x{height}'+('_random' if random_input else '_jpeg'),module='ROM505',entry=0xa9e0d,iterations=1,unit='pixels',operations=width*height,regs=[obj,src],strides=[0,0],writes=writes,checks=checks,warmups=2,samples=5)
def cases():return [make(),make(10,8,8,True),make(8,8,8,True),make(10,16,8)]
def oracle(c,rom):
 from unicorn import Uc,UC_ARCH_ARM,UC_MODE_ARM,UC_HOOK_CODE
 from unicorn.arm_const import UC_ARM_REG_R0,UC_ARM_REG_SP,UC_ARM_REG_LR,UC_ARM_REG_PC,UC_ARM_REG_CPSR,UC_CPU_ARM_926
 from collections import Counter
 u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.ctl_set_cpu_model(UC_CPU_ARM_926);u.mem_map(0x50000000,0x1400000);u.mem_write(0x50000000,rom);u.mem_map(0x80000000,0x20000);pc=Counter()
 for a,b in c['writes']:u.mem_write(a,b)
 def run(cpu,a,n,d):
  if a==0x80000000:cpu.emu_stop();return
  pc[a]+=1
 u.hook_add(UC_HOOK_CODE,run);u.reg_write(UC_ARM_REG_CPSR,0x10);u.reg_write(UC_ARM_REG_SP,0x8001b000);u.reg_write(UC_ARM_REG_LR,0x80000000)
 for i,v in enumerate(c['regs']):u.reg_write(UC_ARM_REG_R0+i,v)
 saved=[u.reg_read(UC_ARM_REG_R0+i) for i in range(4,12)]
 u.emu_start(BASE+c['entry'],0,count=2000000);assert u.reg_read(UC_ARM_REG_PC)==0x80000000,'did not return';assert u.reg_read(UC_ARM_REG_SP)==0x8001b000
 assert [u.reg_read(UC_ARM_REG_R0+i) for i in range(4,12)]==saved
 for a,b in c['checks']:
  got=bytes(u.mem_read(a,len(b)))
  if got!=b:
   i=next(i for i,(x,y) in enumerate(zip(got,b)) if x!=y);raise AssertionError((c['id'],hex(a),i,got[i:i+12].hex(),b[i:i+12].hex()))
 assert all((0x50300000<=a<0x50400000 or BASE<=a<BASE+0x100000) for a in pc),'unexpected service/code'
 return dict(status='PASS',instructions=sum(pc.values()),pcs={hex(a):n for a,n in pc.items()},checks=[dict(address=hex(a),bytes=len(b),sha256=hashlib.sha256(b).hexdigest()) for a,b in c['checks']])
if __name__=='__main__':
 rom=Path('build/firmware/nem4-factory/core.bin').read_bytes();assert hashlib.sha256(rom).hexdigest()==ROM_SHA
 out={}
 for c in cases():out[c['id']]=oracle(c,rom);print('PASS',c['id'],out[c['id']]['instructions'],flush=True)
 Path(__file__).with_name('oracle.json').write_text(json.dumps(out,indent=2)+'\n')
