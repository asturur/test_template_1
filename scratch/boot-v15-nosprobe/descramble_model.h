// Flash read-side descrambler: 16 per-halfword GF(2) formulas (model.json).
// P_i = const ^ parity(C&cmask) ^ parity(A&amask) ^ sum(A_j & A_k). A=byte PA.
// Generated from build/firmware/thc/scrambler-model.json (made with Claude 2026-10-31).
struct DescrBit { unsigned char cst; unsigned short cmask; unsigned int amask; signed char p0j,p0k,p1j,p1k; };
static const DescrBit kDescr[16] = {
  {0,0x101,0x20102,4,10,8,17}, // P0 = C0 ^ C8 ^ A1 ^ A8 ^ A17 ^ A4*A10 ^ A8*A17
  {0,0x202,0x0,3,13,9,17}, // P1 = C1 ^ C9 ^ A3*A13 ^ A9*A17
  {0,0x44,0x102628,9,10,5,13}, // P2 = C2 ^ C6 ^ A3 ^ A5 ^ A9 ^ A10 ^ A13 ^ A20 ^ A9*A10 ^ A5*A13
  {1,0x108,0x40008,11,12,5,14}, // P3 = 1 ^ C3 ^ C8 ^ A3 ^ A18 ^ A11*A12 ^ A5*A14
  {0,0x12,0x4c84,7,11,10,14}, // P4 = C1 ^ C4 ^ A2 ^ A7 ^ A10 ^ A11 ^ A14 ^ A7*A11 ^ A10*A14
  {1,0x8020,0x240188,3,8,7,18}, // P5 = 1 ^ C5 ^ C15 ^ A3 ^ A7 ^ A8 ^ A18 ^ A21 ^ A3*A8 ^ A7*A18
  {1,0x840,0x41042,6,12,4,15}, // P6 = 1 ^ C6 ^ C11 ^ A1 ^ A6 ^ A12 ^ A18 ^ A6*A12 ^ A4*A15
  {1,0xa0,0x10802,2,5,11,16}, // P7 = 1 ^ C5 ^ C7 ^ A1 ^ A11 ^ A16 ^ A2*A5 ^ A11*A16
  {1,0x140,0x202204,9,13,7,16}, // P8 = 1 ^ C6 ^ C8 ^ A2 ^ A9 ^ A13 ^ A21 ^ A9*A13 ^ A7*A16
  {0,0x2200,0x88012,4,15,8,16}, // P9 = C9 ^ C13 ^ A1 ^ A4 ^ A15 ^ A19 ^ A4*A15 ^ A8*A16
  {0,0x401,0x2280,5,11,7,13}, // P10 = C0 ^ C10 ^ A7 ^ A9 ^ A13 ^ A5*A11 ^ A7*A13
  {1,0x800,0x84980,-1,-1,-1,-1}, // P11 = 1 ^ C11 ^ A7 ^ A8 ^ A11 ^ A14 ^ A19
  {1,0x5000,0x8122,3,6,8,15}, // P12 = 1 ^ C12 ^ C14 ^ A1 ^ A5 ^ A8 ^ A15 ^ A3*A6 ^ A8*A15
  {1,0x2004,0x1004,6,11,-1,-1}, // P13 = 1 ^ C2 ^ C13 ^ A2 ^ A12 ^ A6*A11
  {0,0x4400,0x6,4,15,6,16}, // P14 = C10 ^ C14 ^ A1 ^ A2 ^ A4*A15 ^ A6*A16
  {0,0x8008,0x100444,6,10,12,17}, // P15 = C3 ^ C15 ^ A2 ^ A6 ^ A10 ^ A20 ^ A6*A10 ^ A12*A17
};
