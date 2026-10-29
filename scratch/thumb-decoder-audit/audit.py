#!/usr/bin/env python3
"""
Differential audit of third_party/zap/src/rtl/zap_mode16_decoder.sv.

Ports the RTL case statement to Python bit-for-bit, feeds representative
16-bit Thumb opcodes through it, disassembles:
  - the original Thumb opcode with capstone (ground truth, ARMv4T semantics)
  - the emitted 32-bit "ARM-like" word o_instruction[31:0] with capstone ARM
and prints them side by side, plus decoded P/U/B/W/L fields for memory ops.

Branches (bit34 set) are decoded manually since the 24-bit offset uses a
<<1 convention downstream (zap_decode.sv:570) instead of ARM's <<2.
"""
import capstone

# ---- localparams (zap_localparams.svh) ----
AND,EOR,SUB,RSB,ADD,ADC,SBC,RSC,TST,TEQ,CMP,CMN,ORR,MOV,BIC,MVN = range(16)
AL = 0xE
ARCH_SP = 13
LSL,LSR,ASR,ROR = 0,1,2,3

def b(v,hi,lo=None):
    if lo is None: lo = hi
    return (v >> lo) & ((1 << (hi-lo+1)) - 1)

def cat(*fields):
    """fields = (value,width)...; concatenate MSB-first like SV {}"""
    v = 0
    for val,w in fields:
        v = (v << w) | (val & ((1<<w)-1))
    return v

def match(v, pat):
    pat = pat.replace('_','')
    assert len(pat) == 16, pat
    for i,c in enumerate(pat):
        bit = (v >> (15-i)) & 1
        if c == '?': continue
        if int(c) != bit: return False
    return True

# ---- pattern localparams ----
T_BRANCH_COND        = "1101????????????"
T_BRANCH_NOCOND      = "11100???????????"
T_BL                 = "1111????????????"
T_BLX1               = "11101???????????"
T_BLX2               = "010001111????000"
T_BX                 = "010001110????000"
T_SWI                = "11011111????????"
T_SHIFT              = "000?????????????"
T_ADD_SUB_LO         = "00011???????????"
T_MCAS_IMM           = "001?????????????"
T_ALU_LO             = "010000??????????"
T_ALU_HI             = "010001??????????"
T_GET_ADDR           = "1010????????????"
T_MOD_SP             = "10110000????????"
T_PC_REL_LOAD        = "01001???????????"
T_LDR_STR_5BIT_OFF   = "011?????????????"
T_LDRH_STRH_5BIT_OFF = "1000????????????"
T_LDRH_STRH_REG      = "0101????????????"
T_SP_REL_LDR_STR     = "1001????????????"
T_LDMIA_STMIA        = "1100????????????"
T_POP_PUSH           = "1011?10?????????"
T_BKPT               = "10111110????????"

M24 = (1<<24)-1

def decode(i, offset_w=0):
    """Python port of the RTL. Returns (o_instruction 35-bit, force32, und, tag)."""
    force32 = 0
    und = 0
    o = i & 0xFFFFFFFF  # default passthrough (3'd0 on top)

    # ---------- if/else chain (priority before casez) ----------
    if match(i, T_SWI):
        o = 0x0F000000
        o = (o & ~(0xF<<28)) | (AL<<28)
        o = (o & ~0xFF) | (i & 0xFF)
        return o, force32, und, "SWI"
    if match(i, T_ADD_SUB_LO):
        rn = b(i,8,6); rd = b(i,2,0); rs = b(i,5,3); imm = rn
        sel = (b(i,9) << 1) | b(i,10)   # {i[9], i[10]}
        if sel == 0:   o = cat((AL,4),(0,2),(0,1),(ADD,4),(1,1),(rs,4),(rd,4),(0,8),(rn,4))
        elif sel == 1: o = cat((AL,4),(0,2),(1,1),(ADD,4),(1,1),(rs,4),(rd,4),(imm,12))
        elif sel == 2: o = cat((AL,4),(0,2),(0,1),(SUB,4),(1,1),(rs,4),(rd,4),(0,8),(rn,4))
        else:          o = cat((AL,4),(0,2),(1,1),(SUB,4),(1,1),(rs,4),(rd,4),(imm,12))
        return o, force32, und, "ADD_SUB_LO"
    if match(i, T_BLX2):
        o = cat((0b1110,4),(0b0001,4),(0b0010,4),(0xF,4),(0xF,4),(0xF,4),(0b0011,4),(b(i,6,3),4))
        return o, force32, und, "BLX2"
    if match(i, T_BX):
        o = 0x012FFF10 | (AL<<28) | b(i,6,3)
        return o, force32, und, "BX"
    if match(i, T_BKPT):
        o = 0b1110_0001_0010_0000_0000_0000_0111_0000
        return o, force32, und, "BKPT"

    # ---------- casez ----------
    if match(i, T_BLX1):
        off24 = (cat((b(i,10),1)*0, (0,0))) # placeholder
        # {off_w[10],off_w[10],off_w[10:0],i[10:0]}
        off24 = cat((b(offset_w,10),1),(b(offset_w,10),1),(offset_w & 0x7FF,11),(i & 0x7FF,11))
        off24 = (off24 - 1) & M24
        o = (0b1111101 << 25) | (0 << 24) | off24
        o |= (1 << 34)
        return o, force32, und, "BLX1"
    if match(i, T_BRANCH_COND):
        cond = b(i,11,8)
        off = i & 0xFF
        s = off - 256 if off & 0x80 else off
        o = (1<<34) | (cond << 28) | (0b101 << 25) | (0 << 24) | (s & M24)
        return o, force32, und, "BRANCH_COND"
    if match(i, T_BRANCH_NOCOND):
        off = i & 0x7FF
        s = off - 2048 if off & 0x400 else off
        o = (1<<34) | (AL << 28) | (0b101 << 25) | (0 << 24) | (s & M24)
        return o, force32, und, "BRANCH_NOCOND"
    if match(i, T_BL):
        if b(i,11) == 0:
            o = (0xF << 28) | (i & 0xFFF)
            return o, force32, und, "BL_half1"
        else:
            off24 = cat((b(offset_w,10),1),(b(offset_w,10),1),(offset_w & 0x7FF,11),(i & 0x7FF,11))
            off24 = (off24 - 1) & M24
            o = (1<<34) | (AL << 28) | (0b101 << 25) | (1 << 24) | off24
            return o, force32, und, "BL_half2"
    if match(i, T_SHIFT):
        o = cat((AL,4),(0,2),(0,1),(MOV,4),(1,1),(0,4),(b(i,2,0),4),
                (b(i,10,6),5),(b(i,12,11),2),(0,1),(b(i,5,3),4))
        return o, force32, und, "SHIFT"
    if match(i, T_MCAS_IMM):
        op = b(i,12,11); rd = b(i,10,8); imm = i & 0xFF
        alu = [MOV,CMP,ADD,SUB][op]
        o = cat((AL,4),(0,2),(1,1),(alu,4),(1,1),(rd,4),(rd,4),(imm,12))
        return o, force32, und, "MCAS_IMM"
    if match(i, T_ALU_LO):
        op = b(i,9,6); rs = b(i,5,3); rd = b(i,2,0)
        def dp(alu, I=0, rn=None, rdv=None, op2=None):
            return cat((AL,4),(0,2),(I,1),(alu,4),(1,1),
                       (rn if rn is not None else rd,4),
                       (rdv if rdv is not None else rd,4),
                       (op2,12))
        if op in (0,1,5,6,8,10,11,12,14,15):
            alu = {0:AND,1:EOR,5:ADC,6:SBC,8:TST,10:CMP,11:CMN,12:ORR,14:BIC,15:MVN}[op]
            o = dp(alu, op2=rs)
        elif op in (2,3,4,7):
            sh = {2:LSL,3:LSR,4:ASR,7:ROR}[op]
            o = cat((AL,4),(0,2),(0,1),(MOV,4),(1,1),(rd,4),(rd,4),
                    (rs,4),(0,1),(sh,2),(1,1),(rd,4))
        elif op == 9:
            o = cat((AL,4),(0,2),(1,1),(RSB,4),(1,1),(rs,4),(rd,4),(0,12))
        elif op == 13:
            o = cat((AL,4),(0,4),(0,3),(1,1),(rd,4),(0,4),(rd,4),(0b1001,4),(rs,4))
        return o, force32, und, "ALU_LO"
    if match(i, T_ALU_HI):
        op = b(i,9,8)
        rd = (b(i,7) << 3) | b(i,2,0)
        rs = (b(i,6) << 3) | b(i,5,3)
        if op == 0:   o = cat((AL,4),(0,2),(0,1),(ADD,4),(0,1),(rd,4),(rd,4),(0,8),(rs,4))
        elif op == 1: o = cat((AL,4),(0,2),(0,1),(CMP,4),(1,1),(rd,4),(rd,4),(0,8),(rs,4))
        elif op == 2: o = cat((AL,4),(0,2),(0,1),(MOV,4),(0,1),(rd,4),(rd,4),(0,8),(rs,4))
        else: return 0, 0, 0, "ALU_HI_X"
        return o, force32, und, "ALU_HI"
    if match(i, T_PC_REL_LOAD):
        rd = b(i,10,8); imm = (i & 0xFF) << 2
        force32 = 1
        o = cat((AL,4),(0b010,3),(1,1),(1,1),(0,1),(0,1),(1,1),(0xF,4),(rd,4),(imm,12))
        return o, force32, und, "PC_REL_LOAD"
    if match(i, T_LDR_STR_5BIT_OFF):
        rn = b(i,5,3); rd = b(i,2,0)
        imm = (b(i,10,6) << 2) if b(i,12)==0 else b(i,10,6)
        o = cat((AL,4),(0b010,3),(1,1),(1,1),(b(i,12),1),(0,1),(b(i,11),1),(rn,4),(rd,4),(imm,12))
        return o, force32, und, "LDR_STR_5BIT"
    if match(i, T_LDRH_STRH_5BIT_OFF):
        rn = b(i,5,3); rd = b(i,2,0); imm = b(i,10,6) << 1
        o = cat((AL,4),(0b000,3),(0b1110,4),(b(i,11),1),(rn,4),(rd,4),
                (b(imm,7,4),4),(1,1),(0b01,2),(1,1),(b(imm,3,0),4))
        return o, force32, und, "LDRH_STRH_5BIT"
    if match(i, T_LDRH_STRH_REG):
        X,S,H = b(i,9), b(i,10), b(i,11)
        sd = b(i,2,0); base = b(i,5,3); off = b(i,8,6)
        if X == 0:
            HS = (H<<1)|S
            Bb = [0,1,0,1][HS]; L = [0,0,1,1][HS]
            o = cat((AL,4),(0b011,3),(1,1),(1,1),(Bb,1),(0,1),(L,1),(base,4),(sd,4),(off,12))
        else:
            SH2 = (S<<1)|H
            L  = [0,1,1,1][SH2]
            sh = [0b01,0b01,0b10,0b11][SH2]
            o = cat((AL,4),(0b000,3),(1,1),(1,1),(0,1),(0,1),(L,1),(base,4),(sd,4),
                    (0,4),(1,1),(sh,2),(1,1),(off & 0xF,4))
        return o, force32, und, "LDRH_STRH_REG"
    if match(i, T_SP_REL_LDR_STR):
        sd = b(i,10,8); imm = (i & 0xFF) << 2
        # RTL line 483: U = 1'd0  <-- known bug (patch 0008 flips to 1)
        o = cat((AL,4),(0b010,3),(1,1),(0,1),(0,1),(0,1),(b(i,11),1),(ARCH_SP,4),(sd,4),(imm,12))
        return o, force32, und, "SP_REL"
    if match(i, T_LDMIA_STMIA):
        base = b(i,10,8); rl = i & 0xFF
        o = cat((AL,4),(0b100,3),(0,1),(1,1),(0,1),(1,1),(b(i,11),1),(base,4),(rl,16))
        return o, force32, und, "LDMIA_STMIA"
    if match(i, T_POP_PUSH):
        rl = i & 0xFF
        if b(i,8) and b(i,11):   rl |= 1<<15
        elif b(i,8) and not b(i,11): rl |= 1<<14
        o = cat((AL,4),(0b100,3),(1,1),(0,1),(0,1),(1,1),(b(i,11),1),(13,4),(rl,16))
        if b(i,11):  # pop: [24:23] = 01
            o = (o & ~(0b11 << 23)) | (0b01 << 23)
        return o, force32, und, "POP_PUSH"
    if match(i, T_GET_ADDR):
        rd = b(i,10,8)
        imm = (0xF << 8) | (i & 0xFF)   # rot=15 -> <<2
        force32 = 1
        base = 13 if b(i,11) else 15
        o = cat((AL,4),(0,2),(1,1),(ADD,4),(0,1),(base,4),(rd,4),(imm,12))
        return o, force32, und, "GET_ADDR"
    if match(i, T_MOD_SP):
        imm = (0xF << 8) | b(i,6,0)
        alu = SUB if b(i,7) else ADD
        o = cat((AL,4),(0,2),(1,1),(alu,4),(0,1),(13,4),(13,4),(imm,12))
        return o, force32, und, "MOD_SP"
    return 0, 0, 1, "UND"

# ---- disassembly helpers ----
csT = capstone.Cs(capstone.CS_ARCH_ARM, capstone.CS_MODE_THUMB)
csA = capstone.Cs(capstone.CS_ARCH_ARM, capstone.CS_MODE_ARM)

def dis_thumb(words, addr=0x1000):
    blob = b''.join(w.to_bytes(2,'little') for w in words)
    out = []
    for ins in csT.disasm(blob, addr):
        out.append(f"{ins.mnemonic} {ins.op_str}".strip())
    return " ; ".join(out) if out else "(capstone: undefined)"

def dis_arm(word, addr=0x1000):
    out = []
    for ins in csA.disasm(word.to_bytes(4,'little'), addr):
        out.append(f"{ins.mnemonic} {ins.op_str}".strip())
    return " ; ".join(out) if out else "(capstone: undefined)"

def mem_fields(o):
    grp = b(o,27,25)
    if grp in (0b010, 0b011):
        return (f"P={b(o,24)} U={b(o,23)} B={b(o,22)} W={b(o,21)} L={b(o,20)} "
                f"Rn=r{b(o,19,16)} Rd=r{b(o,15,12)} imm/off={o & 0xFFF:#x}")
    if grp == 0b100:
        return (f"P={b(o,24)} U={b(o,23)} S={b(o,22)} W={b(o,21)} L={b(o,20)} "
                f"Rn=r{b(o,19,16)} list={o & 0xFFFF:#06x}")
    if grp == 0b000 and b(o,7)==1 and b(o,4)==1 and b(o,6,5)!=0:
        return (f"P={b(o,24)} U={b(o,23)} I={b(o,22)} W={b(o,21)} L={b(o,20)} "
                f"SH={b(o,6,5):02b} Rn=r{b(o,19,16)} Rd=r{b(o,15,12)} "
                f"imm={(b(o,11,8)<<4)|b(o,3,0):#x} Rm=r{b(o,3,0)}")
    return ""

def branch_desc(o, thumb_pc_read):
    off = o & M24
    s = off - (1<<24) if off & (1<<23) else off
    sh = 1 if (o >> 34) & 1 else 2
    cond = b(o,31,28)
    L = b(o,24)
    tgt = thumb_pc_read + (s << sh)
    return f"cond={cond:X} L={L} off24={s} <<{sh} -> target={tgt:#x}"

SAMPLES = [
    # (label, [thumb halfwords])
    ("F1  lsls r0,r1,#3",      [0x00C8]),
    ("F1  lsrs r2,r3,#0(=32)", [0x081A]),
    ("F1  asrs r4,r5,#31",     [0x17EC]),
    ("F2  adds r0,r1,r2",      [0x1888]),
    ("F2  adds r0,r1,#7",      [0x1DC8]),
    ("F2  subs r0,r1,r2",      [0x1A88]),
    ("F2  subs r0,r1,#5",      [0x1F48]),
    ("F3  movs r0,#255",       [0x20FF]),
    ("F3  cmp  r1,#1",         [0x2901]),
    ("F3  adds r2,#16",        [0x3210]),
    ("F3  subs r3,#4",         [0x3B04]),
] + [
    (f"F4  op{op:02d}", [0x4000 | (op<<6) | (1<<3) | 2]) for op in range(16)
] + [
    ("F5  add r0,r8",          [0x4440]),
    ("F5  add r8,r2",          [0x44D0 & 0xFFFF]),
    ("F5  cmp r8,r1",          [0x4588]),
    ("F5  mov r9,r2",          [0x4691]),
    ("F5  mov pc,lr",          [0x46F7]),
    ("F5  bx  r3",             [0x4718]),
    ("F5  bx  r10",            [0x4750]),
    ("F5  blx r3",             [0x4798]),
    ("F6  ldr r0,[pc,#16]",    [0x4804]),
    ("F6  ldr r7,[pc,#1020]",  [0x4FFF]),
    ("F7  str  r0,[r1,r2]",    [0x5088]),
    ("F7  strb r0,[r1,r2]",    [0x5488]),
    ("F7  ldr  r0,[r1,r2]",    [0x5888]),
    ("F7  ldrb r0,[r1,r2]",    [0x5C88]),
    ("F8  strh  r0,[r1,r2]",   [0x5288]),
    ("F8  ldrsb r0,[r1,r2]",   [0x5688]),
    ("F8  ldrh  r0,[r1,r2]",   [0x5A88]),
    ("F8  ldrsh r0,[r1,r2]",   [0x5E88]),
    ("F9  str  r0,[r1,#4]",    [0x6048]),
    ("F9  ldr  r0,[r1,#124]",  [0x6FC8]),
    ("F9  strb r0,[r1,#5]",    [0x7148]),
    ("F9  ldrb r0,[r1,#31]",   [0x7FC8]),
    ("F10 strh r0,[r1,#2]",    [0x8048]),
    ("F10 ldrh r0,[r1,#62]",   [0x8FC8]),
    ("F11 str r1,[sp,#4]",     [0x9101]),
    ("F11 ldr r2,[sp,#1020]",  [0x9AFF]),
    ("F11 str r0,[sp,#0]",     [0x9000]),
    ("F12 add r0,pc,#40",      [0xA00A]),
    ("F12 add r1,sp,#1020",    [0xA9FF]),
    ("F13 add sp,#64",         [0xB010]),
    ("F13 sub sp,#64",         [0xB090]),
    ("F13 sub sp,#508",        [0xB0FF]),
    ("F14 push {r0-r3}",       [0xB40F]),
    ("F14 push {r4,lr}",       [0xB510]),
    ("F14 pop  {r0,pc}",       [0xBD01]),
    ("F14 pop  {r7}",          [0xBC80]),
    ("F15 stmia r0!,{r1,r2}",  [0xC006]),
    ("F15 ldmia r3!,{r0-r2}",  [0xCB07]),
    ("F16 beq +8",             [0xD004]),
    ("F16 bne -4",             [0xD1FE]),
    ("F16 cond=0xE (UDF)",     [0xDE00]),
    ("F17 b +100",             [0xE032]),
    ("F17 b -2",               [0xE7FF]),
    ("F18 bl +0x1000",         [0xF001, 0xF800]),
    ("F18 bl -0x100",          [0xF7FF, 0xFF80]),
    ("SWI #0x18",              [0xDF18]),
    ("BKPT #0x12",             [0xBE12]),
]

def main():
    print(f"{'sample':28s} | {'thumb (capstone truth)':34s} | emitted ARM32 / fields")
    print("-"*140)
    for label, words in SAMPLES:
        truth = dis_thumb(words)
        off_w = 0
        results = []
        for w in words:
            o, f32, und, tag = decode(w, off_w)
            if tag == "BL_half1":
                off_w = w & 0x7FF   # captured into i_offset via o_instruction[10:0]
            results.append((w, o, f32, und, tag))
        w, o, f32, und, tag = results[-1]
        if und:
            emitted = "UND trap"
        elif (o >> 34) & 1 or tag in ("BL_half1",):
            # branch path or BL dummy
            if tag == "BL_half1":
                emitted = f"NV dummy (offset={o & 0xFFF:#x})"
            else:
                # thumb PC read = instr addr + 4; for BL pair the 2nd halfword addr = 0x1002
                pcread = 0x1000 + 4 + (2 if len(words) == 2 else 0)
                emitted = branch_desc(o, pcread)
        else:
            emitted = dis_arm(o & 0xFFFFFFFF)
            mf = mem_fields(o)
            if mf: emitted += f"   [{mf}]"
            if f32: emitted += " +force32align"
        print(f"{label:28s} | {truth:34s} | {emitted}")

if __name__ == "__main__":
    main()
