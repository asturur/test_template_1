import capstone,struct,sys
d=open('../../build/firmware/thc/nos-image.bin','rb').read(); base=0x5149d280
md=capstone.Cs(capstone.CS_ARCH_ARM,capstone.CS_MODE_THUMB); md.skipdata=True
lo,hi=int(sys.argv[1],16),int(sys.argv[2],16)
def s(va):
    o=va-base
    if not 0<=o<len(d): return ''
    e=d.find(b'\0',o); t=d[o:e][:50]
    return repr(t) if t and all(32<=c<127 for c in t) else ''
for i in md.disasm(d[lo-base:hi-base],lo):
    x=''
    if i.mnemonic=='ldr' and 'pc,' in i.op_str:
        a=((i.address+4)&~3)+int(i.op_str.split('#')[1].rstrip(']'),16); v=struct.unpack_from('<I',d,a-base)[0]; x=hex(v)+' '+s(v)
    print(f"{i.address:08x}: {i.mnemonic} {i.op_str} {x}")
