#!/usr/bin/env python3
"""Generate $readmemh vectors for tb_descramble.v from the solved model.
Each vector = 4 hex words: addr_hi(6), addr_lo(15+padding), cipher(16), expected_plain(16).
Covers: directed corners + random sweep inside the scrambled window.
"""
import json, random

ROOT = "/Users/andreabogazzi/develop/NGage_MiSTer"
model = json.load(open(ROOT + "/build/firmware/thc/scrambler-model.json"))

def bit(v, i): return (v >> i) & 1

bits = []
for i in range(16):
    m = model[str(i)]
    bits.append((m["const"], m["cmask"], m["amask"], [(p[1], p[2]) for p in m["prods"]]))

def descramble(pa, C):
    A = pa
    P = 0
    for i, (const, cmask, amask, prods) in enumerate(bits):
        b = const
        cm = cmask & C
        while cm: b ^= 1; cm &= cm - 1
        am = amask & A
        while am: b ^= 1; am &= am - 1
        for j, k in prods: b ^= bit(A, j) & bit(A, k)
        P |= (b & 1) << i
    return P

random.seed(42)
WIN_LO, WIN_HI = 0xa000, 0x2b3000

# directed: window boundaries, all-zeros cipher, all-ones cipher
addrs = [WIN_LO, WIN_LO + 2, WIN_HI - 2, 0x10000, 0x100000, 0x200000]
for pa in addrs:
    for C in [0x0000, 0xffff, 0x5555, 0xaaaa]:
        P = descramble(pa, C)
        hw = pa >> 1
        print("%04x" % ((hw >> 15) & 0x3f))
        print("%04x" % ((hw & 0x7fff) << 1))
        print("%04x" % C)
        print("%04x" % P)

# random sweep: 4000 vectors
for _ in range(4000):
    pa = random.randrange(WIN_LO, WIN_HI, 2)
    C = random.randint(0, 0xffff)
    P = descramble(pa, C)
    hw = pa >> 1
    print("%04x" % ((hw >> 15) & 0x3f))
    print("%04x" % ((hw & 0x7fff) << 1))
    print("%04x" % C)
    print("%04x" % P)

print("ffff")  # terminator
