from pathlib import Path
import random
out=Path('build/sim/unit-multiply-mapping/vectors.hex')
out.parent.mkdir(parents=True, exist_ok=True)
rng=random.Random(0x44535033);mask=(1<<64)-1
edges=[0,1,2,0x7fff,0x8000,0xffff,0x10000,0x10001,0x7fffffff,0x80000000,0xffffffff,0xfffffffe,0xffff0000,0x7fff0000,0x80010001,0x40000000]
acc=[0,1,mask,1<<63,(1<<63)-1,0xffffffff,0x100000000]
rows=[]
def add(a,b,signed,c):
    sa=a-(1<<32) if signed and a>>31 else a
    sb=b-(1<<32) if signed and b>>31 else b
    expected=(sa*sb+c)&mask
    rows.append((signed<<192)|(a<<160)|(b<<128)|(c<<64)|expected)
for signed in [0,1]:
    for a in edges:
        for b in edges:add(a,b,signed,acc[len(rows)%len(acc)])
while len(rows)<2048:add(rng.getrandbits(32),rng.getrandbits(32),rng.getrandbits(1),rng.getrandbits(64))
assert len(rows)==2048
out.write_text(''.join(f'{v:049x}\n' for v in rows))
