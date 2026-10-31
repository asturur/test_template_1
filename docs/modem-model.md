# NEM-4 cellular modem (NOS / ISI-Phonet) — reverse-engineered model

Written with Claude (Fable). Study of the now-decrypted baseband image; goal is a
faithful software modem model (C now, HDL later). Every claim cites a flash
physical address or VA in the image; "inferred" marks anything not read directly
from code. This document is append-only during the study; sections are updated
in place as evidence lands.

Inputs (all read-only):

- `scratch/flash-cipher-r4/window-dec.bin` — flash physical `[0xa000,0x2b3000)`
  descrambled (digest-proven: reproduces stock MD5 `2c09c86f…`).
- `scratch/flash-cipher-r4/gap1-dec.bin` = phys `[0xa000,0x6e030)`,
  `gap2-dec.bin` = phys `[0x725c0,0x9d280)` (verified: both are exact slices of
  `window-dec.bin`).
- `firmware/THC N-Gage ROM Dump/ngage-gsmstuff-0x5149D280.dll` — 96-byte
  TRomImageHeader + NOS body (plaintext we already had).
- `firmware/THC N-Gage ROM Dump/ngage-virt-phys-map.txt` — captured VA↔phys map.
- Oracle (reverse-engineered reference, NOT ground truth):
  `~/develop/n-gage/sw/kernel/chan.c` (ngvm NOSDRIVER/ISI model).

## 1. Scope and address map

### 1.1 VA ↔ flash-physical mapping (read from the captured map, byte-verified)

The captured MMU map (`ngage-virt-phys-map.txt`) contains four 1 MB section
entries that map the bottom of the flash chip linearly:

```
0x51400000|0x00000000 1024k      (map line 1093)
0x51500000|0x00100000 1024k
0x51600000|0x00200000 1024k
0x51700000|0x00300000 1024k
```

So **VA 0x51400000..0x517FFFFF ↔ flash phys 0x000000..0x3FFFFF**, and the NOS
module at VA 0x5149D280 sits at **flash phys 0x9D280**.

Byte-level verification (script `scratch/modem-model/check_map.py`):

- `window-dec.bin[0x9D280-0xa000 ..]` == `gsmstuff dll[0x60 ..]` over the whole
  overlap, 0x215D80 bytes (phys 0x9D280..0x2B3000). **The descrambled window and
  the THC-dumped NOS plaintext agree exactly.** This simultaneously proves the
  descramble and the `VA = phys + 0x51400000` base for this region.
- `gap1-dec.bin` == `window-dec.bin[0:0x64030]`, `gap2-dec.bin` ==
  `window-dec.bin[0x685c0:0x93280]` (exact slices; sanity).
- The old `firmware/MCU/nos-iat-region-0x6e030.bin` does NOT match the
  descrambled window (15251/17808 bytes differ). The digest-proven window wins:
  **use `window-dec.bin[0x64030:0x685c0]` as the real IAT**, not the old file.
  First real slots (LE words at phys 0x6e030): `503451f4 50323de0 5032b0f8
  5033abc0 5033917c 50326524 …` — all inside ekern.exe
  (VA 0x50320f9c-0x50348750 per the THC ROM directory listing).

### 1.2 The +0x500000 "remap twin"

The same captured map shows, page by page: `0x50009000|0x00009000` but
`0x5000a000|0x0050a000` … (VA 0x5000a000+ → phys +0x500000). That map was
captured at OS runtime and commit 2ab5bfe already established it is wrong for
physical reads. The digest reproduction (`scratch/flash-cipher-r4/
reproduce_stock_digest.py`) treats the service-image file offset (= VA −
0x50000000 per the digest descriptor) as the scrambler address input for
`[0xa000,0x2b3000)` and the stock MD5 matches — so for this study the operative
coordinates are **flash physical offsets**, with two VA windows onto them:

- app-ROM view: VA 0x50000000 + x ↔ ROM image offset x (modules listed in
  `ngage-rom-0x50000000-info.txt`), digest covers x ∈ [0x9000, 0x11b5000);
- baseband/NOS view: VA 0x51400000 + p ↔ flash phys p, p ∈ [0, 0x400000).

The scrambled window phys `[0xa000,0x2b3000)` therefore appears at VA
`0x5140a000..0x516b3000`. (The 0x500000-bit aliasing question is irrelevant to
the content: the digest match pins the plaintext bytes.)

### 1.3 Module geography of the baseband window

| flash phys | VA (0x514… view) | content | evidence |
| --- | --- | --- | --- |
| 0x0000–0x9000 | 0x51400000– | core ROM header + bootstrap (digest descriptor starts at VA 0x50009000) | reproduce_stock_digest.py |
| 0x9000–0xa000 | | zero fill (service image bytes are 0x00) | hexdump nem440-3c1-linear.bin @0x9000 |
| 0xa000–0x6e030 | 0x5140a000–0x5146e030 | "gap1": NOS-side code/data, previously unknown, now decrypted | window-dec.bin |
| 0x6e030–0x725c0 | 0x5146e030–0x514725c0 | import address table: LE words pointing at app-ROM exports (ekern etc.); referenced from gap2 code (e.g. pointer 0x5146e800 at phys 0x725f0 area) | window slots; gap2 head |
| 0x725c0–0x9d280 | 0x514725c0–0x5149d280 | "gap2": more NOS-side code/data incl. pointer tables into app ROM (0x503f4e40… = epbus.dll range 0x503f3de0–0x503fd7f0) | window-dec.bin; THC dir listing |
| 0x9d280–0x316900 | 0x5149d280–0x51716900 | **gsmstuff NOS module body** (TRomImageHeader'd DLL, UID1 0x10000079/UID2 0x1000afaf); scrambler stops at 0x2b3000, the tail is plaintext flash | dll==window proof above |

gsmstuff TRomImageHeader (dll file bytes 0x00–0x5F; the header itself is NOT at
phys 0x9D220 — gap2's last 0x60 bytes differ — so THC's tool recovered it from
the ROM directory, not from in-front-of-code):

```
iEntryPoint    0x5149d284      iCodeAddress 0x5149d284   iCodeSize 0x273ecc
iDataAddress   0x51711138      iDataSize    0x5790       iBssSize  0xc27a8
iHeapSizeMin/Max 0x1000/0x100000   iStackSize 0x2000
iDllRefTable   0x517168e0      iExportDirCount 6         iExportDir 0x517168c8
iUid1 0x10000079 (KDynamicLibraryUid)  iUid2 0x1000afaf  iUid3 0
```

First code word at 0x5149d280 is 0x01000000 (data); entry 0x5149d284 is an ARM
`B` (0xEA00262F). The bulk of the image is Thumb (prologue byte patterns
`46 5x`/`B5 xx` throughout).

### 1.4 App-side counterpart modules (for cross-reference only)

From the THC ROM directory (`ngage-rom-0x50000000-info.txt`, offsets = VA −
0x50000000): `nosstarter.ext` 0x3504a0, `pnmsg.dll` 0x3505a0, `isimsg.dll`
0x350ac0, `phonet.dll` 0x36b480, `phonetsy.tsy` 0x926200, `Nokia.dsy` 0xfc5450,
`nosdriver.ldd` 0x11b4040 (last file in the ROM, code 1248 bytes + 47840
trailing), `ETel.dll` 0x4a3b70, `epbus.dll` 0x3f3de0.

### 1.5 Architecture: the "modem" is in-process software (read from code)

There is no separate modem CPU behind `nosdriver.ldd`. The chain, read from
disassembly:

- `nosdriver.ldd` (VA 0x511b4040 header, code 0x511b40a4, 1248 bytes) is a thin
  EKA1 LDD. Its import stubs resolve to ekern (10), euser (14) — and **two
  pointers straight into gsmstuff**: IAT word 0x511b4028 = 0x514a0a50
  (gsmstuff ord4) and 0x511b4030 = 0x514a13cc (gsmstuff ord6). Read from the
  dump at file offset 0x11b4028/0x11b4030; stubs at 0x511b4458/0x511b4464.
- `DLogicalDevice::Create` (0x511b42d0) allocates a 0x3C-byte channel;
  `DoCreate` (0x511b412c) allocates an **8-byte endpoint object
  {u8 obj_id; const iface* at +4}**, constructs it with gsmstuff ord6
  (`Open(endpoint, id)`), stores it at channel+0x38, then calls gsmstuff ord4
  (`RegisterChannel`): `ram_0x8000c724[id] = channel` for id ≤ 0x19 (panic
  category "NOSDRIVER" reason 0x0B if id > 0x19; code 0x514a0a50-0x514a0a84,
  table literal 0x8000c724 at 0x514a0a7c).
- The channel's virtuals are thin thunks into the endpoint's gsmstuff vtable
  **0x5171103c** (initialized data of gsmstuff): entries
  `[2]=0x514a14cc (ord5, Close)`, `[3]=0x514a183c (ord1)`,
  `[4]=0x514a1654 (ord3)`, `[5]=0x514a1554 (ord2)`.
  Thunks: 0x511b41e8→vt[3], 0x511b41d0→vt[4], 0x511b41b8→vt[5], each passing
  r1-r3 through untouched; destructor 0x511b40dc calls vt[2] with r1=3.
- gsmstuff ord5 (`Close`, 0x514a14cc): if id != 0xFE, deregisters — calls
  0x514a0ed0(1,id,k) for k=0,1,2, 0x514a0fc8(id,3), then ord4(0, id) to zero
  the channel slot.
- gsmstuff ord6 (`Open`, 0x514a13cc): id==0xFE is a special "control" unit that
  performs one-time global init (allocates a 0x10-byte object via
  0x516c71c8/0x516c6f50, panic reason 0x20 if a global at [0x514a1458-area] is
  unset, sets a flag, calls 0x514a1880).

So: **the cellular modem of the N-Gage is the gsmstuff NOS DLL executing on the
same ARM core; ISI/Phonet frames written to NOSDRIVER are handed synchronously
to gsmstuff, whose internal NOS tasks produce the responses.** A faithful MiSTer
model therefore reproduces what gsmstuff's handlers answer, exactly as ngvm's
chan.c attempts.

Secondary RAM table: 0x8000c7f4 (literal at 0x514a0ae0), indexed `[id*3+k]`,
id ≤ 0x19, k ≤ 2, written by 0x514a0aa0 (panic reason 0x0C) — three hooks per
object id (used by ord5's triple 0x514a0ed0 calls; exact semantics below).

## 2. ISI/Phonet framing as the code implements it

### 2.1 Frame header (read from the router entry 0x514bce38 and resend path 0x51530b18)

Byte layout of a frame as the NOS router handles it:

| off | field | evidence |
| --- | --- | --- |
| 0 | media (bit7 = "already copied/owned" flag: `ldrb r1,[r5]; movs r0,#0x80; ands` at 0x514bce72; cleared to media&0x7F before routing) | 0x514bce72-0x514bce82 |
| 1 | receiver device (checked `rxdev & 0xFC == own_dev` where own_dev = RAM byte 0x800c828c; low 2 bits are a sub-address) | 0x514bce96-0x514bcea2; 0x51530c30-0x51530c3e |
| 2 | sender device (patched on entry when frame unowned: `tx = (tx&3) | (own_dev&0xFC)`) | 0x514bce84-0x514bce94 |
| 3 | resource id | 0x514bcea4 |
| 4-5 | **length, little-endian u16, counting bytes from offset 6** — the code allocates `ldrh r0,[r5,#4]; adds r0,#6` for the copy | 0x514bce46-0x514bce4a; 0x51530b44 |
| 6 | receiver object | 0x51530c40-0x51530c4a (`rxobj == (rxdev&3)<<8 \| obj` check) |
| 7 | sender object | 0x514ba352 area (reply builder writes [7]) |
| 8+ | ISI body (transaction id, message id, ...) | consumers |

The receiver "address" is the 10-bit value `(rxdev&3)<<8 | rxobj` compared
against the routing table's u16 `dev<<8|obj` entries (0x51530c40-0x51530c6c).

### 2.2 Router pipeline (addresses)

1. **Entry** `nos_route(msg)` 0x514bce38 (reached from the Symbian side via
   DoControl fn 4 → work-ring closure → callback 0x514a1794 case 4 → thunk
   0x516c7ab8). If the frame isn't an owned NOS buffer (0x516c74fc returns 0),
   it is copied into a NOS pool buffer of size `len+6` (alloc 0x516c750c, copy
   0x516c74f4).
2. Resource class split at 0x514bceb6: resources 0xD0-0xDF and 0x10 are Phonet
   control resources handled specially (0x10 → 0x515305c4; 0xD0 → put on queue
   8 via 0x516c7564; 0xD2 media msg; 0xD7 → 0x5158d424; 0xD9 → 0x5158c668;
   other 0xDx → queue via 0x516c751c). **Everything else → resource dispatch
   0x51530c2c.**
3. **Resource dispatch** 0x51530c2c:
   - if `rxdev&0xFC != own_dev(0x800c828c)` → off-device forward 0x51530db4;
   - else if `rxobj != (rxdev&3)<<8` expected-object form → local object
     delivery 0x51530ea0(msg,1);
   - else (frame addressed to the device, object 0): look up
     `addr16 = res_to_addr(resource)` via **0x51530558**; if 0 → error 5; if it
     maps back to own dev obj 0 → assert; else rewrite rxdev/rxobj from the
     table and re-enter 0x51530c2c. So **0x51530558 holds the
     resource → (device,object) routing table** used to find each service's
     object id.
4. **Local delivery** 0x51530ea0: matches rxobj against the registered-object
   array at RAM 0x80009cf0 (entries: ptr → {u8 obj_id @0; u8 flags @1; handler
   fn ptr @8}); calls the object's handler with the message (0x51530d44-
   0x51530d58 shows the same array walk for broadcast).

### 2.3 Symbian↔NOS bridge mechanics (read from code)

- DoControl(4, desc) posts a 5-word closure {fn=0x514a1794, 4, msgptr, objid, 0}
  into a **0x21-entry ring at RAM 0x8000cbfc** (head u16 at +0x294), marshal fn
  0x514a2724, then wakes the NOS scheduler (0x516c7bfc(0x403)). Ring overflow
  asserts at "line 0x2f8".
- Replies travel back via per-object **mailboxes**: buffer ptr table
  0x8000cab4[obj][k], length u16 0x8000c994[obj][k], pending flag
  0x8000ca64[obj][k] (k = 0..2 = request fn number), user descriptor
  0x8000c7f4[obj][k] registered by DoRequest, channel object 0x8000c724[obj].
  The **pump 0x514a10cc** (run after every marshal via 0x514a1880, and from the
  DFC 0x514a18d4) copies mailbox k to the user descriptor with
  ThreadDesWrite-style ekern calls (thunks 0x516c6f14=ekern!ord478,
  0x516c6f20=ord144 GetDesMaxLength, 0x516c6f2c=ord480, 0x516c6f38=ord479) and
  completes the request (0x516c6f44=ekern!ord64) with 0, or KErrOverflow(-4)
  when the user buffer is smaller than the message (0x514a0be0).
- LDD request fns (nosdriver DoRequest): fn0/1/2 = receive into mailbox 0/1/2
  (fn0 also stores a status ptr at 0x8000c78c[obj]); fn3 = 1-byte
  connection-state notify (state byte 0x8000ca4a[obj], user des 0x8000c714[0..3],
  only objects 0-3 may use it). Evidence: ord3 jump table 0x514a16d4-0x514a1764.
- DoControl fn 6 = send with an 8-byte headroom header built by 0x514ba2f8
  from the per-object send-queue object 0x8000c92c[obj] (set by LDD control
  fn 6 → 0x514a17e0 path... see 0x514a1794 switch: fn 4 = plain send of a raw
  Phonet frame; fn 6 = header-building send; fn 5 = panic reason 9).

### 2.4 NOS task send primitive and the DSP hardware mailbox (read from code)

`os_send(task_id, msgptr)` = **0x514a77f8**:
- task_id ≤ 0x2D: per-task ring: array base [global], entry 12 bytes
  (+9 = ring size), slot write at [taskdesc+0xC][head], head byte at +0x10;
  wakes the scheduler; overflow path sends an error frame.
- task_id > 0x2D (and the wake path at 0x514a7814): the message pointer is
  written to a **hardware FIFO at 0x58210000** with a tag sequence (halfword:
  byte from global; bytes 0x36, 0x8C/0x83/0x9E; word task_id; word msgptr;
  word 0), then **strb 0x10 to 0x58200000** triggers the doorbell. This is the
  MCU→DSP mailbox of the NEM-4 (addresses are physical MMIO; HDL-relevant).
- The work queue id used by the Symbian bridge closures is **0x21**
  (0x514a1d18: `mov r0,#0x21; bl 0x514a77f8`).

### 2.5 Resource → object: the Phonet name table (read from code)

`res_to_addr` 0x51530558 → search 0x5152fe48 / entry accessor 0x5152fdc4
(assert strings at 0x516d8e10: `../../ENOS/CMT_SW/CORESW/CL/PN/Pn_name.c`).
Entries are 8 bytes `{u32 name, u8 dev, u8 obj, u8 flags, u8 pad}` in two
banks: dynamic RAM entries at 0x80011394 (counts at RAM 0x800113e4/0x800113e6)
and the **static ROM table at 0x516f4a9c** (46 entries, terminated by
flags=0x80 entry):

```
name 0x0101d9→obj 01   0x0103d9→obj 40   0x0104d9→obj 34      (media 0xD9 subchannels)
res 0x38→1b  0x43→1c  0x23→1d  0x1c→1e  0x17→1f  0x35→23  0x1b→24  0x15→27
res 0x3a→28  0x0b→29  0x54→2a  0x3e→2b  0x53→2e  0x1f→2f  0x01→30  0x08→31
res 0x06→32  0x03→33  0x31→34  0x14→35  0x19→36  0x5a→37  0x58→38  0x59→39
res 0x5e→3a  0x62→3b  0x82→3c  0x8a→3d  0x8b→3e  0x6e→3f  0x16→40  0x0a→41
res 0x02→42  0x32→43  0x3c→03  0x60→44  0x07→45
res 0xf0,0xf3,0xf1,0xf2,0xe8 → dev 0x7C obj 01      (DSP device 0x7C!)
```

Boot-gating mappings: **energy mgmt 0x17 → obj 0x1F; phone info 0x1B → obj
0x24; network 0x15 → obj 0x27; call 0x01 → obj 0x30; SS 0x06 → obj 0x32; SMS
0x02 → obj 0x42**. **SIM (0x09) is NOT in the static table** — the SIM server
registers its name at runtime into the RAM bank (name-service resource 0x10,
handler 0x515305c4, "name add" msg 0x10). Audio resources 0xE8/0xF0-0xF3
route to device 0x7C (the ADSP), not to an MCU object.

### 2.6 Object → NOS task (read from code)

Local delivery 0x51530ea0: `obj = (rxdev&3)<<8 | rxobj`; bounds-checked against
u16 count; **task id = byte table 0x516f49e0[obj]** (104 entries).
0xFF = invalid (error 6 → COMMON error reply); 0xFE = direct-call handler from
table 0x516f4a4c `{u16 obj, fn}`: obj 0x20 → 0x515306dc, obj 0x25 → 0x514af758,
obj 0x26 → 0x51685154. Otherwise the message is queued to the task with
`os_send` (0x514a77f8); requests with flag arg 2 use the alternate queue fn
0x514a7d74.

Boot-gating task assignments (table 0x516f49e0):

| resource | object | task |
| --- | --- | --- |
| energy 0x17 | 0x1F | **0x0F** |
| phone info 0x1B | 0x24 | **0x0E** |
| network 0x15 | 0x27 | **0x0D** |
| accessory-ish 0x1C | 0x1E | 0x0C |
| call 0x01 | 0x30 | 0x23 |
| SMS 0x02 | 0x42 | 0x1B |
| tones 0x1F | 0x2F | 0x22 (MCU task — tones are NOT on the DSP device) |
| SIM 0x09 | dynamic | (task of the registering server; code region 0x5153xxxx–0x51540xxx) |

(The full obj→task byte table is in the image at 0x516f49e0; copy verbatim
when implementing.)

### 2.7 The router's error reply — exact bytes (read from 0x51530fa0)

When no object matches (error 6), the router builds a **16-byte** reply from
the request `m[]`:

```
r[0]=0x00 (media)        r[1]=m[2]  r[2]=m[1]   (devices swapped)
r[3]=m[3] (resource)     u16 LE @4 = 0x000A     (10 bytes follow offset 6)
r[6]=m[7]  r[7]=m[6]     (objects swapped)
r[8]=m[8] (transaction id)
r[9]=0xF0 (COMMON_MESSAGE)
r[10]=0x14 (COMM_ISA_ENTITY_NOT_REACHABLE_RESP)
r[11]=m[9] (the request's message id)
r[12]=0x01   r[13..15]=0 (memset of 8 bytes at r[8..15] first)
```

then re-enters the router 0x514bce38 (so it goes back out the way it came).
**The length field is a little-endian u16 at offset 4** (`strh #0xA,[r4,#4]`;
the router also reads it `ldrh [r5,#4]`). This contradicts ngvm chan.c, which
writes big-endian `r[4]=0, r[5]=len` — see section 5.

## 3. Per-resource message handlers (boot-gating first)

Convention used below: a Phonet frame `m[]` has the ISI body at `m[8..]`:
`body[0]=m[8]` = transaction id (utid), `body[1]=m[9]` = message id,
and for responses `body[2]=m[10]` = status, `body[3]=m[11]` = subblock count,
then subblocks `{id, len, data...}` (len includes the 4/8/12-byte header).
All read from the energy server's builders (below); this matches ngvm's layout.

### 3.1 Energy management server (resource 0x17) — fully reversed

**Dispatcher** 0x515937ac (Thumb): takes the 16-bit key
`(resource << 8) | message_id` as its 5th argument and compares against
literals. Handled keys (key → handler):

```
0x1700→0x51593fdc  0x1702→0x51594094  0x1704→0x51594244  0x1706→0x51594300
0x1708→0x5159446c  0x170A→0x515944ec  0x170C→0x515945b8  0x170F→0x515945e4
0x1711→0x51594648  0x1713→0x51594824  0x1715→0x51594848  0x1717→0x5159486c
0x1719→0x51594884  0x171B→0x515948ac  0x171D→0x515948d8  0x171F→0x515948fc
0x1722→0x515946c4  0x1724→0x5159471c  0x1726→0x515947e0
0x17E0→0x5159500c  0x17E2→0x51595064  0x17E4→0x515950dc  0x17F0→0x51594a58
0x15C0→0x51593f28  0x1564→0x51593f8c  0x1566→0x51593f4c   (res 0x15 inputs)
default→ common not-identified (0x51593a3c path)
```

**Response primitives** (shared by this server):
- builder 0x51594c7c(req, count, nbytes): alloc(nbytes+4) via 0x514b9a44,
  writes `{req[0](utid), req[1]+1 (RESP ID = REQ ID + 1), 0x01 (status OK),
  count}`. Status-fail variant 0x51594c00: `{utid, id+1, 0x02, 0}`; empty-OK
  variant 0x51594bdc: `{utid, id+1, 0x01, 0}`.
- subblock appenders: 1-byte 0x51594d1c → `{id, 4, v, 0}`; 2-byte 0x51594d38 →
  `{id, 4, v1, v2}`; u16 0x51594d54 → `{id, 4, hi, lo}` (big-endian); u32
  0x51594d70 → `{id, 8, 0, 0, be32}`.
- per-server "not identified" 0x51594c44: 8 bytes
  `{utid, 0xF0, 0x01, req_id, 0, (flag? req[2]:0), 0, 0}` —
  COMMON_MESSAGE / COMM_SERVICE_NOT_IDENTIFIED_RESP.

**Charger status request 0x08 → response 0x09** (handler 0x5159446c):
`flags = body[2]`; if `flags == 0` or `flags & ~3` → status-fail
`{utid, 0x09, 0x02, 0}`. Else response `{utid, 0x09, 0x01, popcount(flags)}`:
- flags bit0 → subblock `{0x13, 4, charger_status, 0}` where charger_status =
  0x515c1dc0: a 16-way switch on the UEM charger state byte ([glob+0x49], read
  by 0x515c1e4c): returns **5**, or raw byte [glob+0x4B], or **4/2** (picked by
  byte [glob+0x52] != 0 → 4 else 2), default **1**.
  (ngvm's "1 = not connected, 2-4 connected, 5 not charging" is consistent.)
- flags bit1 → subblock `{0x14, 4, raw_charger_byte([glob+0x49]), 0}`.

**Battery status request 0x0A → response 0x0B** (handler 0x515944ec):
`flags = body[2]`; if 0 or `flags & ~0x1F` → `{utid, 0x0B, 0x02, 0}`. Else
`{utid, 0x0B, 0x01, popcount(flags)}` with, per bit:
- bit0 → `{0x15, 4, battery_status, 0}`; battery_status = 0x515c49e8:
  3 if byte[g+0x2D], else 2 if u16[g+0x1A], else 4 if measured value
  (0x515c68f4) ≤ a constant, else **1**.
- bit1 → `{0x16, 4, 0x07, bars}` — **first data byte is the constant 7 (max
  bars), second is the current level** (byte [g2+0x22] via 0x515c4a28).
- bit2 → `{0x17, 4, u16be}` (value derived from bars via 0x515c4a34: computed
  from (bars-1) scaled by 0x516c7594 then +5, clamped by 0x515c68b8 — looks
  like a per-bar voltage/percentage).
- bit3 → `{0x18, 4, u16be}` (0x515c4764).
- bit4 → `{0x25, 4, 0xFF, 0xFF}`.

Boot relevance: Nokia.dsy only needs bit0-style charger info (sb 0x13) and the
bars (sb 0x16); the exact bytes above are what a faithful model must produce.

### 3.2 Router-level error (any unroutable frame)

0x51530fa0, exact bytes in §2.7: COMMON_MESSAGE **0xF0 0x14**
(COMM_ISA_ENTITY_NOT_REACHABLE_RESP) + req msg id + 0x01. This fires when no
object matches (unregistered resource, e.g. SIM before its server starts).
Distinct from the per-server **0xF0 0x01** default for an unknown message id
on a live server.

### 3.3 Startup manager (the servers' client)

Function 0x515040ec (Thumb) is a response/indication consumer keyed the same
`(res<<8)|id` way: handles 0x1703/0x1714/0x1716/0x1718 (energy indications),
0x1B01/0x1B03/0x1B06 (phone-info responses: 0x00→0x01 serial-number resp
confirmed as an id the firmware itself consumes), 0x1C11/0x1C12 (accessory
responses to 0x10/0x12), 0x0965 (SIM 0x65), 0x0B01/0x0B02/0x0B15/0x0B16,
0x3200/0x320B/0x32F0 (PMM, permanent memory), with a server-A style ISI entry
at 0x51504188 and its own task main at 0x51504380 (ring receive via
0x516c756c, internal ids 0xC0..0x1BC handled at 0x5152b0a4). This confirms
request/response id pairing (req, req+1) across resources 0x17/0x1b/0x1c.

### 3.4 SIM server (resource 0x09) — partial

Not in the static name table: the SIM server registers its Phonet name at
runtime (name-service resource 0x10, handler 0x515305c4, add = msg 0x10). Its
code region is 0x5153xxxx–0x51540xxx: the key `(0x09<<8)|0x1D` (read SIM data /
IMSI) is consumed around 0x5153fad4; the task's retry logic (0x514d8750 area,
a different task that *sends* SIM requests) tracks pending ids
{0x05, 0x10, 0x1A, 0x1D, 0x1E, 0x20, 0x22, 0x2D, 0x37, 0x50, 0x61, 0x6A} —
so 0x1D (req) and 0x1E (resp) and service type 0x2D are real protocol values,
as ngvm assumed. **Exact IMSI response bytes not yet extracted from the SIM
server code** (it round-trips through the physical SIM card reader state
machine; the response is built asynchronously).

### 3.5 Phone-info server (resource 0x1B, INFO) — IMEI response read

Dispatcher 0x51591bd0 (Thumb), same `(res<<8)|id` keying (switch at
0x51591bfc): key **0x1B00** (serial-number read req; literal built as
`0xD8<<5`) → case 0x51591cd4 → handler **0x5164bbd8**. Also handled:
0x1B01/0x1B02/0x1B04/0x1B07/0x1B09/0x1B0B/0x1B0D/0x1B0F/0x1B11/0x1B13/0x1B15
(version/product-info read pairs) and DSP-related keys.

Handler 0x5164bbd8: jump table on **target type = body[2] − 0x41** (0x41..0x5A,
table at 0x5164bc14). The 0x41 (IMEI, plain) case at 0x5164bc80:
- reads the stored serial via 0x514bf528 (must return 1 = present),
  formats it with 0x514bfc7c(0x10, raw, out16) into a 16-byte buffer,
  validates with 0x5164c274(raw, 0x41, 7);
- on success builds (alloc 0x18 via 0x514b9a44): sets piece[2] = 0 (OK),
  piece[3] = 1 (one subblock), and the subblock at +4:
  **`{0x41, 0x14, 0x00, 0x10, <16 bytes IMEI string>}`** —
  id 0x41, length 20, filler 0, string length 16, then 16 characters
  (15 digits + NUL). The caller wraps it as response id 0x01.
This **matches ngvm's phone-info reply byte-for-byte** (`r[12]=0x41, r[13]=20,
r[14]=0, r[15]=16, 16 chars`); only the digits themselves differ (real device
reads them from permanent memory).

### 3.6 Accessory-ish server (resource 0x1C) — partial

Key-switch at 0x515953c4-0x515954c0 (same `(res<<8)|id` style, handlers
0x516544b8/0x516544ec/...). Keys include 0x1C10 (lit at 0x5159541c). Response
builder not yet walked; ngvm's `0x10 → 0x11 with one byte 0` is plausible
(the startup manager consumes 0x1C11) but the byte content is unverified.

### 3.7 App-side cross-check: Nokia.dsy (ROM, Thumb)

Nokia.dsy's energy message consumer is reached via a function pointer
(literal 0x50fc7b99 stored at 0x50fcbd18): dispatcher **0x50fc7b98** with a
jump table over message id − 8 (ids 0x08..0x1C):
- id 0x09 → 0x50fc8104 (sub-switch on 0x2C/0x3C/...),
- id 0x0A → 0x50fc85c4, id 0x08 → 0x50fc8688,
- id **0x18** → 0x50fc7d88 (the fn ngvm's comment cites): sub-switch on a byte
  ∈ {0x09, 0x0B, 0x21}; the 0x09 branch locates **subblock 0x13** (cmp #0x13 at
  0x50fc7ed2) and maps its first data byte 0..4 through a 5-way switch into
  System Agent states (0x50fca194) — i.e. the charger states ngvm models;
- id 0x1C → 0x50fc7c4c: sub 0x11 → 0x50fc7d00 (value 0x10/0x20/0x11/0x21→1,
  0→0, 1→2), sub 0x12 → 0x50fc7c68 (value−0x10 ≤ 1 or ∈{0x20,0x21,0x40,0x41,4}
  → 1, 0→0, 1→2).
Argument semantics (which frame byte feeds the jump) are not fully pinned;
inferred: Nokia.dsy consumes both direct responses (0x09/0x0B) and the server's
indications (0x18 = charger/battery indication carrying the same subblocks).

## 4. Modem model spec table

"Read" = read from disassembly at the cited address; "inferred" = consistent
with code but not byte-verified.

| resource | request | real response (ISI body from utid) | evidence | status |
| --- | --- | --- | --- | --- |
| any (no such object) | any | 16-byte frame, body `{utid, 0xF0, 0x14, req_id, 0x01, 0,0,0}`, length u16 LE @4 = 0x000A | 0x51530fa0 | read |
| any live server | unknown msg id | `{utid, 0xF0, 0x01, req_id, 0, 0, 0, 0}` | 0x51594c44, 0x51504658 | read |
| energy 0x17 | 0x08 flags(≤3) | `{utid, 0x09, 0x01, n}` + bit0 `{0x13,4,chg_status,0}` + bit1 `{0x14,4,chg_raw,0}`; bad flags → `{utid,0x09,0x02,0}` | 0x5159446c, 0x51594c7c, 0x515c1dc0 | read |
| energy 0x17 | 0x0A flags(≤0x1F) | `{utid, 0x0B, 0x01, n}` + bit0 `{0x15,4,batt_status,0}` + bit1 `{0x16,4,7,bars}` + bit2 `{0x17,4,u16be}` + bit3 `{0x18,4,u16be}` + bit4 `{0x25,4,0xFF,0xFF}` | 0x515944ec | read |
| energy 0x17 | 0x00,0x02,0x04,0x06,0x0C,0x0F,0x11,0x13,0x15,0x17,0x19,0x1B,0x1D,0x1F,0x22,0x24,0x26,0xE0,0xE2,0xE4 | resp id = req+1, status 1/2, handlers listed in §3.1 | 0x515937ac table | read (ids), bodies not walked |
| SIM 0x09 | 0x1D (svc 0x2D) | resp id 0x1E; exact body not yet extracted | 0x5153fad4, 0x514d8750 | partial |
| phone info 0x1B | 0x00, target 0x41 | `{utid, 0x01, 0x00(ok), 1}` + sb `{0x41, 0x14, 0x00, 0x10, 16-char IMEI}`; other targets 0x42..0x5A via table 0x5164bc14 | 0x51591bd0, 0x5164bbd8, 0x5164bc80 | read |
| accessory 0x1C | 0x10, 0x12 | resp ids 0x11/0x13? (mgr consumes 0x1C11/0x1C12); body unverified | 0x515953c4 | partial |
| tones 0x1F | — | served by MCU task 0x22 (obj 0x2F), NOT the DSP | 0x516f49e0 | read (routing) |
| PCM 0xE8, audio 0xF0-0xF3 | — | routed to device 0x7C (ADSP) via the HW mailbox 0x58210000/0x58200000 | name table 0x516f4bdc+, 0x514a77f8 | read (routing) |

## 5. Diffs vs the ngvm oracle (sw/kernel/chan.c)

1. **Length field endianness.** Real NOS reads/writes the Phonet length as a
   **little-endian u16 at offset 4** (`ldrh/strh [r,#4]`: router 0x514bce46,
   error reply 0x51530fce). ngvm writes big-endian (`r[4]=0; r[5]=len`). Since
   ngvm's replies are ≤ 255 bytes and clients appear not to check the length
   against the descriptor, this hasn't bitten — but a faithful model should
   write byte 4 = low byte, byte 5 = high byte. (App-side isimsg.dll read not
   yet verified.)
2. **Charger reply confirmed.** ngvm's `{0x13, 4, 1, 0}` with status r[10]=1,
   one subblock, matches the real builder exactly for flags=1 and charger
   state "default/not connected" (= 1). Real device also emits subblock 0x14
   when flags bit1 is set — ngvm ignores flags and always sends sb 0x13 only;
   PHONETSY/Nokia.dsy appear to request bit0 only, so this is benign but worth
   matching.
3. **Battery subblock 0x16 data bytes differ.** Real: `{0x16, 4, 0x07, bars}`
   (first data byte = constant 7 = full-scale, second = current level). ngvm:
   `{0x16, 4, 0, 7}` — i.e. real[14]=7 vs ngvm 0, and the level lives at [15]
   in both (ngvm pins it to 7 = full). A model should send `{0x16,4,7,level}`.
4. **Two different "unknown" replies.** ngvm answers every unknown service
   with 0xF0 0x01. Real behaviour: 0xF0 **0x01** only from a live server for
   an unknown message id; a frame to an **unregistered object/resource** gets
   0xF0 **0x14** (not reachable) + trailing 0x01 from the router. EStart-era
   requests to not-yet-registered servers would really see 0xF0 0x14.
5. **Response id = request id + 1** is a structural rule in the real code
   (builder adds 1 unconditionally), supporting ngvm's 0x08→0x09, 0x0A→0x0B,
   0x1D→0x1E, 0x10→0x11 pairs.
6. **Status byte is per-server**: the energy server uses 1 = OK, 2 = FAIL
   (0x51594c7c/0x51594c00) — ngvm's r[10]=1 matches; the INFO server uses
   0 = OK (0x5164bd1a) — ngvm's phone-info r[10]=0 also matches. Do not assume
   one convention across resources.
7. **IMEI reply layout confirmed; IMSI still open.** The real INFO server's
   serial-number subblock `{0x41, 20, 0, 16, 16 chars}` matches ngvm exactly
   (0x5164bc80); only the digits are device-specific (ngvm's made-up IMEI is
   fine). Note the INFO status byte here is **0 = OK** (piece[2]=0), where
   ngvm sends r[10]=0 too — agreement. The SIM IMSI (0x1E) body remains
   unverified.
8. **Tones (0x1F)** are handled on the MCU (task 0x22), and PCM (0xE8) goes to
   the DSP device 0x7C — consistent with ngvm's modelling split.

## 6. Open questions

- SIM server response construction (0x1E body, IMSI encoding) — requires
  walking the SIM task state machine in 0x5153xxxx–0x51540xxx (async via the
  physical SIM interface). ngvm's ofono-style layout is unconfirmed.
- Phone-info: remaining target types (0x42..0x5A) and version/product-info
  responses (keys 0x1B07/0x1B15, handlers 0x5164bafc/0x5164b8d4) not walked.
- Accessory server response bodies (keys 0x1C10/0x1C12 handlers at
  0x516544xx).
- Nokia.dsy dispatcher argument semantics (which frame bytes are the jump id
  and sub-id); and whether the energy server's *indication* 0x18 (consumed by
  Nokia.dsy at 0x50fc7d88) carries the same `{0x13,...}`/`{0x15/0x16,...}`
  subblocks as the 0x09/0x0B responses — the subblock-0x13 search in the app
  suggests yes.
- isimsg.dll's reading of the length field (LE vs BE) — decides how strictly
  ngvm's BE length matters.
- Own-device id: the router compares `m[1]&0xFC` against RAM byte 0x800c828c
  (set at init, 0x5149d654 reads it for a trace); its concrete value (0x00?
  0x6C?) was not pinned — a boot-time trace or further init reading would
  settle it. The DSP is device 0x7C (from the name table).
- The NOS "internal message" ids (0xC008 etc., ring at 0x8000cbfc, DFC drain
  0x514bdf00 handling 0xC0..0x1BC) — enough was read to route frames, but a
  complete internal-id map wasn't built.
- The old `firmware/MCU/nos-iat-region-0x6e030.bin` disagrees with the
  digest-proven window over 85% of bytes — supersede it with
  `window-dec.bin[0x64030:0x685c0]` (not modified here; study is read-only).
- What exactly lives in gap1 (phys 0xa000–0x6e030)? Vector-ish data at its head
  (halfword pairs `0x6a01/0x6a04` + offsets, 0x2020 fill); the stride-8 fn
  tables at 0x5147xxxx suggest a separate runtime module (DSP loader or ISA
  platform code) — unidentified.

### Next steps (suggested order)

1. Walk the SIM server task to extract the 0x1E (read-IMSI) response bytes.
2. Locate the phone-info server via its PMM (res 0x32) reads; extract the
   serial-number response (sb 0x41) layout.
3. Confirm isimsg.dll's length-field handling (one targeted disasm).
4. Fold §4 into ngvm chan.c (separate change): `{0x16,4,7,bars}`, LE length,
   0xF0 0x14 for unregistered resources.
