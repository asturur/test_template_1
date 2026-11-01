import sys, capstone
d=open('build/firmware/nem4-factory/digest-probe-core-nosstub/SYM.ROM','rb').read()
BASE=0x50000000
def dis(va, n, thumb=False):
    md=capstone.Cs(capstone.CS_ARCH_ARM, capstone.CS_MODE_THUMB if thumb else capstone.CS_MODE_ARM)
    for i in md.disasm(d[va-BASE:va-BASE+n], va):
        print(f"{i.address:08x}: {i.bytes.hex():10s} {i.mnemonic} {i.op_str}")
if __name__=='__main__':
    dis(int(sys.argv[1],16), int(sys.argv[2],16) if len(sys.argv)>2 else 0x80, len(sys.argv)>3)
