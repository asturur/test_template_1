#!/usr/bin/env python3
"""Build build/firmware/thc-verbatim/SYM.ROM: the real-phone THC ROM dump adopted
VERBATIM, with ONLY the 16-byte core expected-digest recomputed over the dump so
the self-check passes (disclosed digest-probe approach). Chosen over the
reconstructed factory assembly because the dump has real content the
reconstruction dropped (populated comms DB cdbv2.dat at file 0x243c40). Run with
scratch/boot-v15-nosprobe/run-thc-verbatim.py. (made with Claude 2026-10-31)"""
import hashlib, struct, json
from pathlib import Path
thc=bytearray(open('firmware/THC N-Gage ROM Dump/ngage-rom-0x50000000.dmp','rb').read())
before=bytes(thc[0x8f20:0x8f30]).hex()
thc[0x8f20:0x8f30]=hashlib.md5(bytes(thc[0x9000:0x11b5000])).digest()
Path('build/firmware/thc-verbatim').mkdir(parents=True,exist_ok=True)
Path('build/firmware/thc-verbatim/SYM.ROM').write_bytes(bytes(thc))
print('digest', before, '->', bytes(thc[0x8f20:0x8f30]).hex())
