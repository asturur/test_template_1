import json,random
from pathlib import Path
m=json.loads(Path('build/firmware/thc/scrambler-model.json').read_text())
def plain(pa,c):
 out=0
 for i in range(16):
  b=m[str(i)]; v=b['const'] ^ ((b['cmask']&c).bit_count()&1) ^ ((b['amask']&pa).bit_count()&1)
  for _,j,k in b['prods']: v ^= ((pa>>j)&1)&((pa>>k)&1)
  out|=(v&1)<<i
 return out
r=random.Random(920); rows=[]
for address in [0x9ffc,0xa000,0x2b2ffc,0x2b3000]+[r.randrange(0xa000,0x2b3000)//4*4 for _ in range(512)]:
 raw=r.getrandbits(32)
 for array,code in [(1,1),(0,1),(1,0)]:
  result=plain(address,raw&65535) | plain(address+2,raw>>16)<<16 if array and code and 0xa000<=address<0x2b3000 else raw
  rows.append(f'{address:08x} {raw:08x} {array:x} {code:x} {result:08x}\n')
Path('build/sim/unit-flash-decode').mkdir(parents=True,exist_ok=True)
Path('build/sim/unit-flash-decode/vectors.txt').write_text(''.join(rows))
