#!/usr/bin/env python3
"""Reproduce the NEM-4 v4.03 stock boot-MD5 (2c09c86ff047484fdcc0e226f49c44a9)
from the Nokia service files by descrambling the flash read-side window.

This demonstrates authentic verification: the firmware's own digest descriptor
(core file 0x8f18: VA 0x50009000..0x511B4FFF) is satisfied with NO digest
replacement, once the scrambled window [0xa000,0x2b3000) is descrambled to the
bytes the CPU actually reads.

Descramble model (16 per-halfword GF(2) formulas, from model.json): for each
16-bit halfword at even byte address pa, with ciphertext C = img[pa]|img[pa+1]<<8
and A = pa (absolute byte physical address), plaintext bit i =
   const_i  XOR  (sum of C bits in cmask_i)  XOR  (sum of A bits in amask_i)
            XOR  (sum of A_j AND A_k over the quadratic products prods_i).

Run: python3 -I scratch/flash-cipher-r4/reproduce_stock_digest.py
(made with Claude, 2026-10-31; cipher cracked from an external researcher's
bit-9/bit-10 anchors, full 16-bit solve verified by this very digest match.)
"""
import hashlib, json, struct
from pathlib import Path

ROOT = Path("/Users/andreabogazzi/develop/NGage_MiSTer")
LINEAR = ROOT / "scratch/nem440-flash-extract/out/nem440-3c1-linear.bin"   # VA-linear service assembly
MODEL  = ROOT / "build/firmware/thc/scrambler-model.json"
WIN_LO, WIN_HI = 0xa000, 0x2b3000          # scrambled read-side window (CS0)
DIG_LO, DIG_HI = 0x9000, 0x11b5000         # digest range file offsets (VA 0x50009000..0x511B4FFF)
STOCK = "2c09c86ff047484fdcc0e226f49c44a9"

def bit(v, i): return (v >> i) & 1

def main():
    img = bytearray(LINEAR.read_bytes())
    model = json.load(open(MODEL))
    # precompute per-bit (const, cmask, amask, product list)
    bits = []
    for i in range(16):
        m = model[str(i)]
        prods = [(p[1], p[2]) for p in m["prods"]]
        bits.append((m["const"], m["cmask"], m["amask"], prods))
    for pa in range(WIN_LO, WIN_HI, 2):
        C = img[pa] | (img[pa + 1] << 8)
        A = pa
        P = 0
        for i, (const, cmask, amask, prods) in enumerate(bits):
            b = const
            cm = cmask & C
            while cm: b ^= 1; cm &= cm - 1          # parity of selected C bits
            am = amask & A
            while am: b ^= 1; am &= am - 1          # parity of selected A bits
            for j, k in prods: b ^= bit(A, j) & bit(A, k)
            P |= (b & 1) << i
        img[pa] = P & 0xff
        img[pa + 1] = (P >> 8) & 0xff
    got = hashlib.md5(bytes(img[DIG_LO:DIG_HI])).hexdigest()
    print("descrambled window [%#x,%#x), hashed VA 0x50009000..0x511B4FFF" % (WIN_LO, WIN_HI))
    print("computed MD5 =", got)
    print("stock    MD5 =", STOCK)
    print("MATCH:", got == STOCK)
    return 0 if got == STOCK else 1

if __name__ == "__main__":
    raise SystemExit(main())
