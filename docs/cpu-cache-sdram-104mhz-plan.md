# CPU, cache and memory architecture for 104 MHz

Review and implementation proposal, 2026-11-08. The review below describes the
pinned baseline. Slice1 implementation/evidence is recorded separately in
[cpu-operand-stage-contract.md](cpu-operand-stage-contract.md). The first owned-R
fit is reviewed in status.md; its read/refresh/forward follow-up is patch0046,
awaiting a new routed measurement.
Reference: `ef9b7621fa2ca90af250ce8d988260ebbc5e59d6`, pinned ZAP plus patches 0001–0044,
Quartus 17.0.2, Cyclone V `5CSEBA6U23I7`. Line references below refer to this revision.
The existing uncommitted pass16 analysis in `status.md` and `timing-closure.md` is retained.

## Decision

Retain the validated execution semantics, architectural register file, cache geometry,
physical memory transports and firmware/storage contracts. Repartition **ownership and
pipeline stages**, starting with register acquisition versus operand forwarding. Replace
the overlapping cache/TLB adaptation protocols with explicit transaction records as a
separate migration. Do not preserve today's internal module interfaces merely because
they already exist. Conversely, neither a replacement CPU nor wholesale BRAM conversion
is justified by the evidence.

The recommended architecture has:

1. A registered operand-read packet before issue, a current committed-register snapshot
   maintained across stalls, and late forwarding at issue/shifter. One extra frontend
   stage; one warmed dependent ADD per clock remains a required throughput target.
2. A registered cache lookup owner/address before the tag/flag read, distinct resident
   instruction lookahead, and coherent hit/victim/mutation records. Retain the two-line
   instruction stream buffer, 16 KiB I/D caches and 64-way organization.
3. An explicit translation transaction and response, replacing address-equality/recovery
   glue after the first two changes have attributable results. Preserve early translation
   scheduling in the existing postALU slots and blocking data completion initially.
4. Registered write-buffer allocation decisions with capacity reservation and exact
   completion accounting; retain four groups/sixteen words and physical-line ordering.
5. The existing registered UPP boundary and captured NOR/SDRAM owner. Close the SDRAM
   falling-to-rising path physically, preserving DDIO and both capture registers. Treat
   board I/O timing constraints and hardware memory validation as separate gates.

This is a coherent target, not a prediction that five edits guarantee timing closure.
All latency/resource estimates below are design budgets until measured. No slower CPU
clock, false path, multicycle exception or reduced memory specification is proposed.

## Evidence, budgets and what is actually required

Pass16/run42471100156 fits but fails 104 MHz: Fmax 83.52 MHz, setup −2.358 ns,
TNS −2151.000 ns; 33,006/41,910 ALMs, 42,873 registers, 465/553 M10Ks.
HDMI setup +0.182 ns; global hold/recovery/removal/pulse minima
+0.249/+1.544/+1.000/+0.961 ns. Thus only 8,904 ALMs and 88 M10Ks remain,
and congestion matters before either count reaches 100%.

The worst-1000 selection ends at −0.697 ns. It contains CPU 292, buffer 208,
cache metadata 160 and other cache controller/refill 73 endpoints: **733/1000**.
LCD 94, sparse 94, MDI 47 and smaller families remain. Absence from this ranked
subset does not prove timing passes. Evidence:
`scratch/timing-closure/pass16-42471100156/output_files/` and its `analysis/`.

| Measured path | Relationship / effective data budget | Consequence |
| --- | --- | --- |
| Path #1: decode memory source index → skid/read selection → RF port D → issue memory operand | 9.615 ns period, −0.564 ns reported clock skew, −0.300 ns uncertainty, uTsu 0.000 in this report; effective data allowance **8.751 ns**, measured 11.109 ns | Seven logic levels; 3.244 ns cell and 7.866 ns routing. Logical balancing alone does not address long routing and late address selection. |
| Path #533: `read_falling.dq_in[11]` → `sdram_ctrl.dout[11]` | 4.808 ns relationship, −0.995 ns skew, −0.300 ns uncertainty, uTsu 0.000; allowance **3.513 ns**, measured 4.404 ns | Zero logic levels; 0.712 ns cell, 3.692 ns routing. This is a physical transfer problem, not a missing ALU/cache stage. |
| Path #707: SDRAM command/mask family → `sdram_a[12]` | Full 9.615 ns relationship; −0.793 ns slack | Distinct from DQ capture; inspect command/mask generation, output-register placement and external timing. |

These use the report's skew convention, which already includes clock-path/device
terms. Path #1 removes 0.960 ns clock pessimism; #533 removes 1.303 ns. Do **not**
subtract those twice or assume all future endpoints have zero setup cost. Use each
new report's required/arrival times. A practical initial target is ≤7.5 ns **routed
register-to-register data delay** for new full-cycle seams and ≤2.8 ns for the DQ
half-cycle transfer, leaving approximately 1.25/0.71 ns relative to these examples.
These are engineering margins, not new constraints. A 3–4 ns logic estimate is
insufficient if routing again costs 7.9 ns. Locality, banked enables and narrow
control distribution are part of the architecture.

Pass15's 79.42 MHz limit was consistent with a −1.489 ns **half-cycle** SDRAM path.
Pass16's worse absolute CPU slack and better Fmax are therefore not contradictory.
No Fmax number substitutes for all constrained checks or external SDRAM sign-off.

Architectural requirements versus implementation choices:

- Preserve ARMv4T instruction/Thumb behavior, banked registers, PC operand semantics,
  condition flags, CPSR/SPSR transfers, ordered memory effects, precise exception
  state, alignment behavior and the implemented CP15/MMU/cache contract. The local
  ARM920T manual, especially chapters 3–4, is the specification reference; passing
  current tests is necessary but does not certify every manual feature.
- The ARM920T-shaped cache contract is 16 KiB each, eight segments ×64 ways,
  32-byte lines, MVA tags, physical writeback addresses, two dirty halves,
  replacement and lockdown. Do not trade away associativity/capacity or lie in CP15
  identification to make the fit easier. ZAP's separate direct-indexed section/
  large/small/tiny TLB arrays are not a demonstrated silicon-identical ARM920 TLB.
  TLB lockdown and untested coprocessor/debug behavior remain conformance work.
- ZAP's pipeline depth, Wishbone, skid implementation, three address-lookahead
  inputs, background-load port and the `NGAGE_ASSOC_EXPERIMENT` name are not ARM
  requirements. The associative path is **enabled in `files.qip:75`**, despite stale
  comments saying it is unused. In that path `zap_dcache.sv:239` ties background
  loads/locks off. Keep the legacy configuration for reference testing, not as a
  timing solution.
- Nokia documents MCU up to104 MHz, SDRAM104 MHz and main flash104/3 MHz. It does
  not establish our internal UPP timing or all clock-divider semantics. The local
  model is not cycle-equivalent to the phone. See `phone-clocks.md`.
- Keep `ngage_upp` as D100, the board's chip composition, the separate logical NOR
  die states, unimplemented chip boundaries, stock service firmware loader and raw
  writable C:/PMM save contracts. DDR is backing storage for NOR, not the phone's
  SDRAM. No synthetic peripheral completion or firmware patch belongs in this plan.

Historical introductions in `bringup.md`, `cache-implementation-decision.md` and
`arm920-manual-audit.md` predate integration. The source graph and latest status take
precedence; their earlier "not connected"/"direct mapped default" claims are not the
current baseline.

## Existing CPU: actual enabled-edge map

The often quoted "17 stages" is not a sufficient timing description. Fetch lookahead,
FIFO occupancy, Thumb conversion, micro-operations and memory stalls make a single
fixed fetch-to-retire number misleading. The following is the actual register sequence;
an enabled edge means an edge on which that stage can advance.

| Boundary | Current work and ownership | Source anchors |
| --- | --- | --- |
| Fetch address/TLB/cache | Writeback owns PC and three delayed PCs, BTB/shelve/retry; I-TLB read/check and I-cache response determine fetch acceptance | `zap_writeback.sv:211,475`; `zap_cache.sv:149,330`; `zap_core.sv:565–603` |
| F | On valid response, capture instruction, real PC, PC+8 ARM / PC+4 Thumb, prediction and speculative abort. A redirected or discarded fault cannot become an executed abort | `zap_fetch_main.sv:88` |
| FIFO / T | Fetch FIFO has synchronous output register; Thumb conversion has its own enabled register and can expand instructions. FIFO depth is16 in `zap_top`; buffering breaks a fixed latency count | `zap_fifo.sv:100`; `zap_mode16_decoder_main.sv:114`; `zap_core.sv:683,707` |
| P | Coprocessor filter, uop sequencer (LDM/STM/SWP and other expansions), RAS/branch predecode, IRQ/FIQ tagging and registered outputs. CP15 waits for the downstream pipeline and data locks to drain | `zap_predecode_main.sv:162,237,330`; `zap_core.sv:574` |
| D | Decode instruction controls and translate four architectural source indices/destination into physical bank indices, then register | `zap_decode_main.sv:230,273`; `zap_functions.svh:93` |
| I | Select live D or saved skid from registered `o_stall_from_issue`; asynchronous four-port RF read; choose immediate/RAZ/PC/CPSR/forwarded/RF data; detect load/shift hazards; register operands or bubble | `zap_issue_main.sv:325,439,625,633,748,942,1080` |
| S | Barrel shift or multicycle multiplier; late correction for adjacent producer ALU result on Rn, unshifted Rm and store source. Nontrivial dependent shifts interlock. Registers output plus exception/uop context | `zap_shifter_main.sv:208,228,389,456` |
| A | Arithmetic, condition evaluation and active flags, effective address/byte enables, branch resolution and exception tagging. Combinational ALU result feeds I and S; registered A result also forwards | `zap_alu_main.sv:416,522,692,964,1028` |
| P0 → P1 → P2 | Three separate postALU registers carry all controls/payloads. Address lookahead comes from A, check address/privilege from P1, actual demand from P2 | `zap_core.sv:549–603,1264,1338,1410`; `zap_postalu_main.sv` |
| M → W | M samples completion/data/fault and carries load format; combinational byte/halfword/sign/rotation transform feeds W. W writes ALU/base result and load result together or LR/SPSR on exception, and redirects PC | `zap_memory_main.sv:132,227,244`; `zap_writeback.sv:337` |

For a single ordinary uop with D valid after edge0 and no stalls: I@1, S@2,
A@3, P0@4, P1@5, P2@6, M@7, RF write@8. Memory demand can extend P2 arbitrarily.
This is a concrete backend edge count, not a claim of eight-cycle whole-instruction
latency from external fetch. For an ordinary ARM instruction, empty FIFO and no
stalls, the frontend register schedule from an accepted F@0 is FIFO write@1,
FIFO output@2, Thumb/ARM conversion register@3, P@4, D@5; the coprocessor and
uop blocks pass that ordinary instruction combinationally within P. Occupancy,
fetch response waits and expanded instructions extend this schedule. CP15 and LDM
instruction retirement can span many uops.

The RF has40×32 FF storage, four asynchronous read ports and three effective write
sources (`zap_register_file.sv:55`). Two normal writes share `i_wen`; B wins an
A/B same-address collision. Background one-hot C writes after both and wins their
collisions. Reset zeros all40. CP15 steals read port0 inside writeback and accesses
it only under its serialization contract. Physical15/16/17 are PC/RAZ/CPSR special
indices; FIQ banks r8–r14, IRQ/SVC/ABT/UND bank r13/r14 and SPSR, user-bank LDM/STM
aliases and temporary uop registers also require preservation. The actual operand
priority is immediate, RAZ, PC, CPSR, combinational A, registered A, P0, P1, P2,
M ALU result, RF. Load results are not interchangeable with those ALU/base results.

`data_stall = demand_cyc & demand_stb & !request_ack` (`zap_core.sv:565`) freezes
upstream execution. M bubbles its valid/exception outputs while stalled so an older
completion cannot retire repeatedly; W can still commit older work. Issue's hazard
stall is registered and its skid catches the instruction that crossed before the
stall became visible. Shifter stall has a different bubble/hold contract. ALU clears
are qualified differently during data stall; W clear has highest cancellation
priority. A replacement must preserve **transfer, hold, bubble and kill separately**,
not replace all of them with a delayed global enable.

ALU flags are speculative pipeline state; W owns committed CPSR/exception state.
Mode-changing operations cause resynchronization. Memory privilege is carried from
P1 (`o_data_cpsr`), not taken from an unrelated younger ALU mode. W priority includes
retry (`data_abt[1]`), data abort, FIQ, IRQ, prefetch abort, SWI, undefined instruction,
load-PC and branch redirects. Retry is not an architectural data abort. LR offsets,
T-state and mask updates must remain those of the interrupted instruction. SWP tags
span read/write uops and suppress early interrupt exposure; a failed read is retained
until the write-half response reports the precise fault and releases reservation.

### Timing dependencies to break or retain deliberately

- **Break:** D/skid control → RF address decode → wide RF data → wide forwarding.
  Port-D worst slack −2.358 and issue-stall launch −2.292 prove that this entire seam
  matters. Rebalancing only one data tree moved the critical path among four ports.
- **Retain and measure:** A combinational result → S correction → S registers. This
  is an edge-to-edge recurrence, not an unclocked combinational loop: A consumes
  the previous S register. It permits adjacent dependent unshifted ADDs. Adding a
  register here blindly creates a dependency bubble even if independent IPC stays1.
- **Control reconvergence:** demand completion/translation fault/fast hit → global
  stall → many enables; issue hazard → registered skid choice; mode/branch clear
  meets those enables late. Patch0043 removed idle maintenance from demand ACK,
  not all global-stall fanout. Do not reconnect its housekeeping ACK to core stall.
- **Avoid reintroducing real feedback:** external ACK → next bus request → peripheral
  decode → ACK has already been cut by the UPP bridge. Cache-buffer physical hazard
  → refill choice → enqueue enables has a registered conservative snapshot. Preserve
  both cuts. The present source does not establish an intentional unclocked loop;
  run synthesis/lint loop checks after each seam change.

## Existing translation, caches and ordering

`zap_tlb.sv:238–446` uses independent4-section/8-large/16-small/32-tiny entry arrays
per I/D side (defaults in `zap_top.sv:70–83`). `zap_mem_inv_block` plus
`zap_ram_simple` pipeline data/valid with explicit read/write forwarding. The
`*_nxt`, `*_check` and actual addresses have different epochs. `zap_tlb_check.sv:80`
compares page tags, registers PA, C/B, FSR/FAR and walk request, checks domain/AP/S/R
and captured privilege; MMU-disabled accesses produce identity and uncached/
unbuffered attributes. `zap_tlb_fsm` walks first-level then coarse/fine second-level
descriptors and writes the selected TLB; walk external faults and permission faults
are distinct. Alignment faults are checked before a data access can side-effect.
FCSE transformation occurs in CPU address generation, not in cache indexing alone.

The current D integration (`zap_dcache.sv:161–266`) retains stalled translation
with `pending_request`, `pending_translation`, `lookup_resync`, `checked_request_prev`
and a full address/control comparison; two stable checked observations precede
capture. This guards real past stale-translation/LDM bugs, but mixes ownership with
pipeline recovery. I-cache CP15 prefetch borrows the I-TLB and uses explicit restore/
resync states and stable-observation counters (`zap_cache.sv:149–188`). These are
prime candidates for a transaction-level rewrite, not deletion of waits in isolation.

| Storage / operation | Current implementation |
| --- | --- |
| Tags |64 parallel8×24 M10K tag banks/cache. Edge1 samples MVA segment, valid/dirty/victim and physical victim RAM; edge2 registers comparisons, MVA and metadata; balanced lowest-way selection follows. `cache_tags.sv:44–184` |
| Data |Eight512×32 memories/cache, each four byte enables; one synchronous read and one writer, full256-bit line available.16 M10Ks/cache fitted. `cache_lines.sv:18` |
| Physical metadata |512×27 dual-port RAM, fill versus scan on A, victim read on B; standalone hit-PA copy is optimized away when unused. Valid512bits/dirty1024bits stay FFs. `cache_tags.sv:93` |
| Replacement / lockdown |Per-segment victim and pseudo-random state; RR or random selection advances only on committed fill; lock base limits replacements. Preserve indexed way/segment semantics and lowest duplicate-hit priority |
| Mutation |Capture line data/byte mask and selected metadata together, commit both next edge; reset/invalidation/lock/index maintenance suppress both. Fresh lookup after collision/commit; no dependence on primitive `DONT_CARE` read-during-write |
| Demand |One serialized request per cache. Accept in IDLE, LOOKUP_WAIT, LOOKUP, READ_LINE or STORE_HIT/BUFFER_STORE, then response/STORE_COMMIT. Adapter tracks launched/inflight and one response. D fast-hit is disabled |
| I fast path |Two256-bit streaming line slots, tags and valid bits; background resident tag/data lookahead +12bytes hides three lookup edges for sequential ARM. Current request still needs TLB permission/cacheability. Lookahead never fills or issues a speculative external read |
| Store policies |C=1/B=1 hit: dirty cache update; miss: buffer without write allocation. C=1/B=0: write-through buffer and update on hit, no allocation on miss. C=0/B=1: buffered. C=0/B=0: drain older buffer then direct access |
| Miss |Read miss selects victim, reads line, queues4/8 dirty-half words, then fetches8words and installs coherently. Unrelated refill reads may overlap buffered drain; physical same-line hazard prevents stale alias refill. Full CPU demand remains blocking |
| Maintenance |Serialize demand/lock/maintenance, scan512 slots or selected MVA/index, send only dirty halves, then clean/invalidate. Clean completion means writes **enqueued**; drain completion means buffer empty, not equivalent events |

Source: `cache_access.sv:94–236,327–408`, `cache_refill.sv:40–112`,
`cache_transfer.sv`, `cache_maintenance.sv:44–111`, `write_buffer.sv:19–93`,
`zap_dcache_adapter.sv:28–87`. Cached/refill and buffered bus errors retry without
architectural external abort; persistent errors can stall indefinitely. Uncached
unbuffered errors do report faults. Preserve this existing policy, separately audit
its complete ARM/manual coverage rather than silently changing it during timing work.

Instruction fetch and table walks wait for the older D write buffer to drain before
starting external traffic; once offered, the walk keeps its grant through completion
(`tlb_bus_gate.sv`). The four-group buffer records physical first/last line tags;
refill hazard snapshots include **offered enqueue**, not just yesterday's stored
entries. Group retire and tail merge races are handled explicitly. Current critical
buffer path is tail → last-slot metadata → merge/new-group → fanout404 storage enables,
not the removed physical-hazard loop.

Self-modifying code requires the actual clean/drain/I-invalidate sequence, stream
invalidation and correct TLB/FCSE context. There is no automatic D→I snooping or DMA
cache coherence. DMA software must satisfy its cache-maintenance contract. The
retained warmed no-NOP descriptor-store/I-walk reproducer in
`scratch/timing-closure/pass9-cache-pipeline/order-prefetch-abort.S` fails the old
baseline too. The passing ordering fixture adds four NOPs to ensure an older write
is actually enqueued before the walk. This leaves an **open synchronization/ordering
question**, not proof that arbitrary descriptor-store→branch sequences are correct.
Resolve it from the ARM synchronization contract and a request-age trace; neither
hide it in a new wait count nor describe the whole baseline as fully conformant.

## Existing external memory path and resets

```text
CPU I/D + walkers → registered ZAP merger (SWP reservation)
    → UPP captured request → held board request → captured memory owner
       ├─ SDRAM owner → CPU/DMA arbiter → 32/16 adapter → JTFRAME banks/refresh
       │                                               → DDIO clock / SDRAM pins
       └─ NOR owner → code/C: flash command engines → captured DDR response owner
                      → phone/aux DDR arbiter → DDR adapter → MiSTer DDR port
                           ↑ loader/save auxiliary arbiter
    ← UPP registered {data,error,completion} ← selected owner's response
```

`ngage_upp.v:284–365`: IDLE captures fields, ACTIVE holds them until ACK/ERR or CYC
withdrawal, RESPONSE returns registered payload/error and then goes IDLE. STB is
not used to qualify the returned error because ZAP can suppress STB on error.
Side effects use selected-device validation and exact-once controls. LOCK bypasses
beat bubbles as a reservation, not a one-cycle request property.

`ngage_mister.v:213–240`: disjoint `{PMM,C:,codeNOR,SDRAM}` owner captured once
adds one clock; stays valid until request-low/reset. Payload is currently held by
the bridge, so duplicating it here buys no ownership safety by itself. If the bridge
is later pipelined, this becomes a full address/data/control/owner packet. Keep
NOR/SDRAM launch/return out of the aggregate peripheral-claim tree.

`Template.sv:209–272`, `ngage_sdram_arbiter.v:31–58`: arbitration captures the whole
32-bit request and owner; round-robin preference advances at selection, CPU lock
blocks new DMA grants across SWP gaps. An already accepted DMA operation finishes.
The adapter captures address/data/mask, issues low then high16-bit beats, waits
for **rdy** (ack only accepted the bank command), inserts the existing gap,
responds once and waits for request drop (`ngage_sdram_adapter.v:34–111`). Even
masked writes currently traverse both halves. Do not change this transport and
its throughput in the CPU/cache slice.

JTFRAME uses HF=1, AW=22, BA0/BA1 writable,16-bit length, SHIFTED=0. Bank ACT,
READ/WRITE, precharge and data-busy states plus refresh debt arbitrate the pin
commands (`jtframe_sdram64_bank.v:62–145`, `jtframe_sdram64_rfsh.v:22–98`). The adapter
requests refresh every6800 clocks; default RFSHCNT is9 distributed commands with
forced service as debt grows. Refresh arbitration, direction turnaround, DQM and
DQ tri-state are protocol constraints, not arbitrary idle clocks to delete.

`jtframe_sdram64.v:196–226` samples DQ on falling edge then transfers to rising-edge
`dout` alongside registered rdy. `ngage_sdram_clock.v` forwards an inverted clock
through ALTDDIO_OUT. Keep both capture registers: delaying rdy or sampling only
rising edges previously captured Z. The four-state Micron model passes with original
tAC/tOH and0/0.25/0.5/1ns clock-pin delays, including372 refresh commands. Those
ideal model windows are not FPGA setup/hold margin or a verified module speed grade.

The DDR path is a separate32-bit-client/64-bit-port adapter, lane selected by held
address. It captures in IDLE, holds ISSUE through busy, acknowledges a write on
acceptance and a read on data-ready, including same-cycle ready. Two arbitration
levels retain response ownership (`Template.sv:394–489`, `ngage_ddr_arbiter.sv`,
`ngage_ddr_adapter.sv:32–94`). NOR state engines retain accepted operations across
phone reset; `mem_owner_user` retains whether completion belongs to C: or code/PMM.
DDR write acceptance does not mean a host save was flushed to disk.

Reset domains are intentionally different:

1. PLL/transport cold reset initializes controller/loader state and SDRAM scrub;
   phone release also waits for loaded firmware, mounted save and board init.
2. Phone reset cancels CPU/bridge/cache state and clears request ownership, but
   an accepted SDRAM beat drains with its response discarded and RAM retained.
   A one-clock phone reset followed by a new request must not misattribute old data.
3. Accepted NOR/DDR work drains while phone reset is asserted. `reset_drain`
   (`ngage_mister.v:81–91`) asserts immediately and releases on a clock after both
   flash engines idle. Never gate accepted backing traffic off with core reset.
4. Transport DDR reset cancels an unaccepted command; an accepted read is drained
   and discarded before accepting another. Save/dirty obligations and warm-reset
   flash semantics remain in their current owners.

## Proposed architecture in detail

### A. Separate RF acquisition from forwarding; retain execution recurrence

Introduce `zap_operand_read` between D and the existing issue output, and rewrite
issue's skid/selection ownership around it. Names are proposed, not existing files.
Use explicit Verilog-2001 ports and packed vectors/localparams for new maintained
modules; preserve imported style and record imported changes in the patch series.

```text
D {physical indices, immediate/special kinds, uop/control/PC/exception context}
  → R {four RF base values + exact same context, valid}
  → I {late-forwarded operands, hazard accepted/bubble}
  → S {shift/multiply + adjacent-A correction} → A → P0 → P1 → P2 → M → W
                    ↑ combinational A result                    │
R committed bases ← effective RF write snoop (A,B,and legacy C) ←─┘
```

R consumes **registered D addresses directly**, never the live issue-stall skid
mux before the RF. Maintain a two-entry operand packet buffer if the existing
registered upstream-stop contract needs one extra captured uop: one issue head and
one skid slot, with explicit valid/occupancy and simultaneous pop/push rules. No
combinational ready chain through RF/forwarding. D only advances when a reserved
slot exists; a hazard at I bubbles I and holds its packet, while R/D stop on local
capacity. This buffer replaces the old whole-control skid; it must not coexist as
a second hidden replay interface. Occupancy belongs in `pipeline_is_not_empty`.

A packet carries four source kinds/indices/base values, immediate values, destination,
store/load format, original PC/PC+8, prediction, condition, flag/shift controls,
exception tags, uop-last and SWP phase. Physical bank mapping occurs at D under the
correct mode; a mode-changing redirect invalidates younger packets. PC/RAZ/immediate
and live CPSR forwarding are resolved at I exactly as today; do not snapshot CPSR
as an ordinary RF word and later execute with stale flags.

**Long-stall/writeback invariant:** a held R value is a committed RF base, not a
snapshot assumed to remain fresh. It must survive an older producer leaving every
forwarding stage. For each valid slot/source, snoop all effective committed writes
on every clock even if data/shift/issue stall holds the packet. Resolve collisions
C over B over A; B/A require actual RF write enable and C its one-hot bit. Capture
and snoop on the same edge uses the same priority over the pre-edge RF read.
Reset/kill overrides packet validity. At issue, a matching current-edge committed
write overrides the stored base; a matching **younger in-flight producer older than
the consumer** still has priority over that commit bypass. Load values cannot be
substituted for ALU/base writeback values with the same destination tag by accident.

Only older instructions can commit while an in-order packet is waiting; assert
that age invariant in the fixture. Retain legacy background-load/WAW locks for the
reference build and verify its C-write priority even though the selected associative
build has C tied off. If snooping's fanout fails, fallback is a recorded dirty-base
bit plus explicit reread/revalidate before issue, with a measured extra release
cycle; simply rereading once when stall begins is incorrect. A fallback must not
silently add one bubble to every ordinary instruction.

At I retain newest-valid producer priority and load/shift interlocks, but its base
source is now a **registered**128-bit packet. Narrow source match controls can be
partitioned by operand and physically local; avoid a shared all-operand grant net.
Do not register forwarding selects without their producer identity/age: a held
packet must recompute against producers that advance. Retain `zap_shifter_main`
late `resolve_conflict` for Rn, unshifted Rm and store value and the existing flag/
nontrivial shift restrictions. Adjacent dependent ADDs reach S one clock apart and
use A's same-cycle result, so the new R stage need not change steady-state CPI.

| Enabled edge relative to D@0 | Current | Proposed |
| --- | --- | --- |
|1|I|R|
|2|S|I|
|3|A|S|
|4|P0|A|
|5/6/7|P1/P2/M|P0/P1/P2|
|8/9|RF write / next instruction|M / RF write|

Latency/throughput contract for this slice alone:

- Independent and dependent warmed unshifted ARM ADD: IPC1/CPI1 target, +1 cycle
  initial pipeline fill. Nontrivial dependent shifts/multiply retain existing stalls.
- ALU-resolved taken/mispredicted branch: resolution +1 enabled cycle from D;
  target first issue also traverses R. In a redirect-to-execute measurement that
  starts at the **old branch's fetch**, the added penalty can total **+2 cycles**
  (one to resolve, one to refill). From redirect edge to next issue: **+1**. Early
  P-stage branch redirection itself is unchanged. Loaded-PC/exception resolution
  similarly gains one backend cycle; do not collapse these different counters.
- A load from D to W gains1 before considering cache changes. A consumer immediately
  behind it also gains the same R stage, so the **issue-to-issue load-use spacing**
  need not increase if current load locks and release are retained. Conservatively
  budget **0–1 additional release cycles** until the same-edge load write/snoop case
  is checked. Memory waits remain blocking; no new nonblocking speculation.
- IRQ/FIQ recognition preserves architectural instruction/uop boundary and priority;
  delivery can move by one enabled backend cycle plus frontend recovery. Absolute
  simulation timestamps may differ. Test interrupts swept across every added edge,
  not by requiring old timestamps or assuming a constant wall-clock interrupt delay.

The first fit must report D→R read, R→I forward, W→R refresh, I→S, A→S, hazard/ready
and clear/enable paths separately. If RF acquisition alone still exceeds the budget,
predecode one-hot source selects at D and distribute local groups before the R tree;
that is a measured follow-up, not four replicated RFs by default. If A→S fails, a
larger shifter/execute repartition is warranted: move nearest-producer selection
closer to ALU input and reconsider the S/A recurrence as a unit. An extra ALU-result
register alone changes a dependent ADD chain toward CPI2 and is a **no-go** for this
recommended architecture. Do not assert that retaining the recurrence guarantees
it will close; it remains a specific fit gate.

### B. Make cache lookup ownership explicit, then simplify translation glue

Add `arm920_cache_lookup` ownership to the existing bank interface: registered
`lookup_valid, lookup_kind, mva, epoch` plus captured segment selection. Kinds are
demand, resident lookahead and maintenance. Demand and maintenance have precedence;
lookahead is cancelable and never causes memory traffic. Local replicas of the
three-bit registered segment, or registered eight-way segment select, feed small
way groups; no live `stream_hit`, TLB ACK or maintenance decode fans into all flag
snapshots. Preserve64 parallel ways initially; group8ways for physical locality
with balanced inter-group reduction.

For an already translated read hit accepted at edge0:

| Edge | Existing serialized path | Proposed path |
| --- | --- | --- |
|0|Accept and prime tag/flag read|Accept registered lookup record L0|
|1|Compare register (LOOKUP_WAIT ends)|Tag RAM/flags from L0: L1|
|2|Select way and line RAM read (LOOKUP ends)|Compare record L2|
|3|Registered response (READ_LINE ends)|Select way and line RAM read L3|
|4|Caller consumes existing response|Registered response L4|
|5|—|Caller consumes proposed response|

Thus **+1 clock serialized read-hit latency**, not four new stages; the existing
read/compare/data stages are retained. Write-through/buffer/store-hit acknowledge
only after the corresponding commit/reservation; budget +1 for lookup, plus any
buffer allocation stage below. Clean miss budget +1 initial lookup and +1 post-fill
relookup = **+2 internal clocks**; eight external read beats remain unchanged.
A dirty miss adds queue allocation cost per dirty word, bounded below. MVA
maintenance adds1 initial lookup; indexed/all scan can use its own registered index
and retain current per-slot timing. If a common scan port needs an extra capture,
budget1 per visited line (up to512 clocks) and make that cost explicit before merge.

The stream path still supplies one accepted warm instruction/clock. Its RAM lookahead
now needs four clocks. Generate an independently registered lookahead PC from the
fetch sequencing record (this record is L0, not an additional fifth lookup stage),
nominally **+16 bytes for sequential ARM**, rather than
feeding current hit/ACK through the whole bank address mux. Retain the two-line
buffer; do not add a third line without a measured need. Validate Thumb increments,
line/page crossings, branches, stalls and prefetch cancellation separately: +16 is
an ARM design starting point, not a universal hardcoded prediction. The lookahead
result carries its own address and epoch through every stage. A maintenance/reset/
context change cancels old results; current TLB permission and C-bit still qualify
stream completion. A wrong-path resident read is harmless; using its old permission
or allocating a speculative line is not.

Possible next cleanup: specialize I-cache read-only metadata/control instead of
instantiating a writable D-shaped engine and buffer there. Preserve architecturally
visible I operations and shared drain ordering; remove dirty/writeback logic only
after proving all I mutation sources. The fit still contains I dirty snapshots and
an I write-buffer hierarchy, so constant propagation has not eliminated the whole
cost. This is a separate measurable change, not assumed free savings for the first
lookup stage.

Then replace `pending_translation/lookup_resync/checked_*` recovery with an
`arm920_translation_port` contract, shared in design but separately owned by I/D:

- Request `{valid,sequence/epoch,MVA,read/write,privilege,FCSE/CP15 context}` accepted
  once; response `{valid,same identity,PA,C,B,fault,FSR,FAR,external-FSR}` remains
  paired through a walk, wait, cancellation and cache completion. One outstanding
  demand per side initially; a small local sequence field plus valid is enough
  only if reuse is prohibited until stale responses drain. No wraparound assumption.
- Snapshot or version TTBR/DACR/S/R/MMU/PID context at acceptance. CP15 operations
  drain old contexts before update; prefetch has an explicit separate owner rather
  than borrowing live pins and waiting three matching observations to restore them.
- Use the existing A/P0/P1/P2 lead time for TLB RAM read/check. Proposed schedule:
  A address launch → P0 capture/read → P1 permission evaluation → P2 demand has
  registered translation. Prove actual RAM `_pre`/forward latency before wiring;
  if it needs one additional edge, budget +1 data-access stall, not a mismatched
  early response. Preserve the old implementation as a differential reference.
- On a miss retain the request through descriptor reads and restart lookup from
  its identity. Reject stale walk returns by owner/epoch; drain an accepted bus
  operation before reusing its response slot. Faults complete the owned demand;
  transient "translation not ready" must not replay already committed LDM work.
- Replace the old adapter/glue in one owner at a time, removing superseded states
  and interfaces in the same slice. Keep a compile-time reference selection for
  tests only. Do not build a permanent new wrapper around the old resync wrapper.

Keep the current blocking `request_ack`/data_stall interface until the explicit
translation and lookup results are stable. A later `arm920_mem_completion` register
may carry `{identity,data,fault,FSR,FAR,load-format}` and drive local advance logic;
that adds **+1 demand cycle** unless it absorbs an existing response edge. Register
payload and completion together. Arbitrarily delaying ACK or registering stall alone
is incorrect. Do not introduce a reorder buffer/nonblocking loads in this migration.

### C. Allocate buffer storage before bulk writes

Replace tail-selected merge→global-new-group→hundreds of enables with a two-step
allocation/commit inside `arm920_write_buffer`:

- Registered tail summary: last slot, next adjacent address, length, generation and
  whether it can merge. Decide merge/new-slot on narrow metadata and capture
  `{slot,word offset,mask,payload,new length,next address,line tags}`. Reserve the
  group/word immediately, so ready cannot overbook space while commit is pending.
- On the next edge, per-slot/per-word local enables commit the captured record.
  Reservation and pending record count as **nonempty and hazardous** from acceptance.
  Drain/maintenance cannot complete between reservation and commit. Keep total
  admitted capacity four groups/sixteen words, not sixteen plus a hidden queue.
- Retire/merge on the same last group must use current generation and a single
  next-state occupancy calculation. A retiring group cannot receive a late merge.
  Head bus data/address/owner remain unchanged while offered. Preserve errors/retry.

Budget +1clock before newly accepted data becomes externally issuable. Simplest
first implementation accepts at most one enqueue every2clocks; measure this against
cached store traffic and dirty4/8word writebacks. Worst added internal enqueue time
is4/8clocks for a serialized dirty half/full line, absent overlap. If this throttle
materially affects measured CPI, pipeline allocation with reserved next-tail summary
for one enqueue/clock; this is preferable to removing ordering. CPU store completion
can remain on durable reservation only if reset/drain semantics count that reservation
as accepted data; otherwise add1 store completion clock. No off-chip side effect may
be acknowledged merely because an unreserved staging register is free.

### D. Preserve transports; close and verify physical seams

Do not add another generic bridge in series with the existing UPP bridge, memory
owner and SDRAM arbiter. They already capture the fields needed for their owners.
First retain their latencies and report each edge-to-edge path. Later throughput
work could replace the whole serial32/16 adapter with a burst-line transaction
interface, but it changes arbitration/refresh/locks and is **not required to diagnose
or close the present CPU operand paths**.

For the failing zero-logic DQ path, inspect fitted location/IO packing/clock networks
and route length, then place the rising transfer registers near their falling
capture registers or give them a deliberate local output stage. Do not add an
unqualified full-cycle sample that pairs next-word data with old rdy. If placement
cannot meet the half-cycle budget, an explicit held-data/valid transfer design
sampling at a proven later edge is a larger controller change: hold each captured
word until its matching rising-domain consume, with readiness delayed identically,
then rerun four-state timing and throughput/refresh tests. Its cost is at least1
clock per halfword unless overlapped. Prefer physical closure of the existing
zero-logic transfer first; no evidence supports reverting the proven capture edge.

`Template.sdc` only derives PLL clocks/uncertainty. The full project STA reports
must also be checked for parent constraints; the current audit still identifies
unconstrained external interfaces. Explicitly establish forwarded inverted SDRAM
clock, module speed grade, PCB/connector clock/data flight time, jitter and external
input/output delays. Check capture IO register packing, command/address/DQM/DQ
setup/hold and output-enable turnaround. These are genuine interface constraints,
not exceptions to hide an internal failure. Current ideal DDIO simulation is not
a post-fit vendor primitive or PCB model.

Physical slow peripherals can be handled later by a registered command/response
mailbox and verified service enables. CEN alone leaves register-to-register paths
at104 MHz. A real new clock domain requires documented clock relationship or proper
CDC (synchronized control, held payload/handshake or async FIFO, safe reset release),
including IRQ return and video/framebuffer crossing. Defer LCD/sparse/MDI/timers/SIM
and diagnostic paths as separate work, but full-system104 MHz acceptance cannot
pass while they still violate timing. Preserve HDMI's small positive margin.

## Resource decisions and alternatives

Fitted evidence, not capacity arithmetic: cache data is16 M10Ks/cache, tag banks
64 M10Ks/cache, physical metadata2 M10Ks/cache; the D hierarchy has another inferred
shift-memory block in this fit. RF uses no M10Ks, about3111.4 "ALMs needed" and1419
registers; issue about793.5 and505. These hierarchy metrics are not additive with
parent rows or the headline placed-ALM total. Source RF storage itself is1280bits;
extra registers include fitter replication.

| Choice | Recommendation / resource and timing tradeoff |
| --- | --- |
| FF RF + new R packet + forwarding | **Recommended.** Preserve4reads/2normal+1legacy writes. Estimate +400–900 physical register bits for packet/elastic capacity after replacing old skid, +300–1000 ALMs for snoop/control/local replication, 0 M10Ks target. Estimate only; existing RF tree area might be recovered later. |
| Compact indexed FF reads inside owned R stage | **Explicit area-recovery experiment after slice1.** Compare the original `mem[index]` read against patch0042's masked tree with the same R/forward/hold contracts. Pass16 grew1515ALMs overall after operand and demand-ACK changes; this is not an isolated measurement of the RF rewrite. The compact tree may now meet timing because forwarding/skid selection left the stage. Select from matched whole-project fits and the independent operand oracle; retain neither mux form on principle. |
| Register source one-hot only, keep same I stage | Smaller latency change; can remove address decode/skid selection if ownership moved coherently. Still leaves RF reduction+routing+wide forwarding in one edge. Useful fallback experiment if R area/branch cost fails; not the principal closure claim. |
| Synchronous BRAM RF | Four reads require at least four replicated simple-dual copies for one writer, or banking/multipumping. Two normal writes plus background C cannot be broadcast into one-writer copies without arbitration/LVT/XOR banks or write serialization. Read-during-write bypass, reset scrub, CP15 and long stalls all change. Not selected; single BRAM alone cannot implement the interface. |
| Fully replace ZAP / collapse to a new ARM pipeline | Would reopen decode/uop/exception/MMU compatibility and long boot evidence. Justified only if measured S/A recurrence or issue area cannot meet the stated gates after repartition. Not a shortcut for this plan. |
| Retain64 parallel shallow tags | Recommended first: +roughly100–300 FFs/cache for owner/address/local enables; 0 M10Ks intended. Timing gain comes from registered/local address distribution. |
| Time-multiplex8ways across8phases | Could reduce shallow tag RAM waste but adds up to7lookup clocks, larger stream prefetch and maintenance scheduling changes. Not chosen while only pipeline ownership needs fixing. |
| Pack valid/dirty with tag RAM | Saves flag FF muxes but requires coherent byte/bit writes or read-modify-write, invalidate generation/scrub and scan-port scheduling. A larger bank rewrite if flag timing remains after L0; not a metadata attribute hint. |
| Buffer allocation packet | Approximately180–250bits plus reservation/summary state; several hundred ALMs budget, no BRAM replication. Per-slot enables should lower routing fanout; fit must confirm. |

Initial combined project budget: ≤36,000 ALMs (~86%), ≤480 M10Ks (~87%) after the
CPU/cache slices, leaving room for remaining peripherals and placement. These are
**proposed engineering stop limits to confirm during implementation planning**,
not existing user requirements or hardware facts. Stop and redesign if one slice adds >1500 ALMs, >8 M10Ks, or total exceeds
these limits without a specific measured compensating reduction. Do not reserve the
last12% of RAM blocks for a speculative RF implementation. Tiny pipeline vectors
must be checked for unintended `altshift_taps` M10K inference; no savings claim until
actual RAM summary. I read-only specialization is a plausible resource recovery,
not a prebooked discount.

## Ordered implementation and acceptance

No step below has been executed by this review. Each numbered implementation slice
gets its own reviewable commit(s), tests, patch provenance where applicable and
attributable fit. Do not bundle a peripheral rewrite into a CPU/cache timing build.
Use the existing `jotego/simulator:arm64`; no Quartus download. New simulations start
a fresh executable/source/image lineage. All paired billion-cycle checkpoints remain
untouched and usable only with their saved compatible executables.

| Order / coherent commit scope | Required evidence before proceeding | Go/no-go and fallback |
| --- | --- | --- |
|0. Freeze reference/measurement contract | Record reference SHA44patches,122PASS+1expected XFAIL and existing17160-cycle operand oracle,4741-clock demand tests/64fault-walk/2048stall cases. Add bounded scoreboard/trace hooks in the eventual implementation branch; define counters at accepted fetch/uop issue/architectural retirement, not raw decompile messages | No broad rerun solely to repeat this review. Preserve existing tests/expectations. Reference remains selectable in tests; do not compile duplicate CPU/cache hardware into production |
|**1. Operand read/hold/forward boundary** | Introduce R + explicit capacity, replace old issue skid, retain FF RF/S/A, add W snoop/clear/drain integration. Differential operand/issue oracle against frozen reference, new edge/hold cases below; fullCPU and actual-phone integration; fresh bounded boot; then one whole-project fit | All four operand families and W→R/A→S/control paths evaluated, no unplannedCPI1 loss. Target routed seams≤7.5ns; if still failing, identify remaining portion before one-hot/locality follow-up. Stop on area thresholds or unexplained branch/load penalty. This is the **first implementation slice** because it cuts the measured worst cone without entangling external memory |
|2. Cache lookup owner/address stage | L0 request+epoch, localized flag/tag address, coherent response/mutation epoch, four-edge resident lookahead. Cache/reference scoreboards and stream timing; fullCPU/fresh boot; separate fit | Serialized hit+1, clean miss+2 internal clocks budget; warm sequential ARM interval exactly1 across lines. No stale response after maintenance/branch/FCSE. If RAM fanout remains, bank locality/register replication first, then explicit metadata bank redesign |
|3. Write-buffer allocation/commit | Reserve capacity, tail summary, local word enables, include pending record in empty/hazard. Random group scoreboard and ordered bus comparison; alias/refill/maintenance/TLB cases, CPU suite; separate fit | Capacity remains4groups/16words, held beat exact, no lost merge/retire race. Bound dirty-writeback penalty4/8cycles for conservative version. If steady enqueue rate matters, pipeline reservation before accepting an extra stage or reducing capacity |
|4. Explicit I/D translation ownership | First D with existing permission/walker arithmetic, then I/prefetch; each removes its old recovery interface. Request-tagged differential trace under random stalls/walk faults/context changes; CPU/full fresh boot; fit each side when substantive | Aim no extra normal translation latency using postALU slots; tolerate at most+1 measured demand cycle for the first correct version. Resolve existing no-NOP ordering reproducer explicitly. If performance or precision regresses, retain reference side and redesign that transaction owner; never patch in another elapsed-cycle counter |
|5. Completion/stall localization only if measured | Bundle response identity/data/fault and use local valid/advance logic; propagate stop early enough through bounded buffers. Distinct demand and maintenance completions remain | No standalone delayed stall. Budget+1 demand cycle only if unavoidable; require no path shifted into M/W/clear. If current demand cone now meets timing, omit this speculative rewrite |
|6. SDRAM physical transfer and interface sign-off | Inspect DQ physical routes/IO packing; fix locality as isolated change, fullfour-stateDDIO/refresh/reset/lock tests and fresh real-SDRAM boot; fit with real clock/I/O constraints; hardware patterns later | Half-cycle transfer positive with targetmargin, all banks/masks/turnaround valid. Retain capture edges. Board constraint data must be real; internal timing pass alone cannot authorize a "104MHz hardware validated" claim |
|7. Remaining system families and final acceptance | Separate LCD/sparse/MDI/timer/diagnostic fixes with chip tests, CDC/staging where applicable; final integrated fit and fresh boot from reset | All constrainedsetup/hold/recovery/removal/pulse checks nonnegative across corners, intended clocks unchanged, unconstrained-path audit explained, resource budget met; no "CPU only" victory reported as whole-system closure |

A slice can have a test-contract commit followed by its implementation and imported
patch update; the fit must correspond to the final tested source, not an intermediate
commit. Baseline and candidate builds should use the same tool/device/constraints/
seed, with explicit changed-file inventory. Export global worst1000 **and targeted
path groups** for D→R, R→I, A→S, W→R, cache L0/tag/compare/data/commit, buffer allocation,
TLB/response, transport and reset. Rank cutoffs and source/end-point counts must be
recorded. Compare per-family WNS/TNS, routed delay, fanout and resources; do not credit
an unchanged peripheral's disappearance to an unrelated edit. Once a candidate
passes, a second seed is useful for robustness of small margins, not a substitute
for design. No build dispatch is authorized by this document alone.

### Functional checks required by those gates

**Operand and execution slice:** extend the independent priority oracle, not merely
a duplicate RTL expression. Cover all40physical indices/four read ports and forward
priority collisions; B/A/Csame-address writes; simultaneous capture+commit, commit
on issue edge, producer leaving M during a long stall, full-buffer pop/push, all
clear/reset/stall combinations. Test banked/user-bank operands, PC alignment/ARM vs
Thumb offsets, CPSR/SPSR read/restore/mode change, condition-failed writes, register
shifts/multiply, adjacent dependent ADD/ADC/SBC and store data. Include load widths,
signed and unaligned behavior, LDMbase-in-list/writeback/following load, STM, SWP
read/write faults, permission/alignment priority, load-PC, precise abortLR/FSR/FAR,
IRQ/FIQ priority and every edge of SWP/exception return. The reference121/122pass
suite is a floor, not permission to delete legacy-background tests.

**Cache/translation/buffer slices:** hit/miss and stream/nonstream crossing tests
with backpressure at every stage; same-address RAM collisions using Intel primitive
model, two-dirty-half eviction, all replacement/lock bases, MVA/index/all maintenance,
maintenance at accepted/inflight boundaries, exact-once store commit, reset through
mutation capture/commit, stream invalidation and self-modifying code. Verify allC/B
policies, no-write-allocate behavior, bufferfull/merge/head-tailwrap/addresswrap/
retire-error/retry combinations, same-physical/different-MVA hazards, dirty enqueue
versus refill read, drain while allocation pending and table-walk ordering. Exercise
section/coarse/fine large/small/tiny mappings, domain/AP/S/R/privilege/FCSE/context
changes, walk external aborts and canceled prefetches. Record the known no-NOP race
separately with manual interpretation; a skipped or retimed fixture is not a fix.

**Transport slices:** actual32/16adapter and JTFRAME bank/refresh plus unchanged
four-state memory model; retain rising-only negative control. All16byte masks,
both halves/banks/rows/end boundaries, continuous traffic through refresh and
read↔write turnaround; CPU/DMA fairness and SWP gaps, short/warm/cold reset before
acceptance, during each half and after ready. For NOR/DDR, held busy, immediate/delayed
read-ready, reset before/after acceptance, ownership through drain, loader/save
arbitration, writable C:/PMM persistence/dirty tracking and the original service-image
assembly. Preserve accepted work even when the CPU response is discarded.

**Integration and performance:** run `CPU_BUS_BRIDGE=1 sh tests/cpu/run.sh`, actual
CPU phone SIM/queuedLCD/DMA/fault/IRQ/FIQ/waitedSDRAM coverage, source graph/ONLY_CORE/
top synthesis lint, patches reproduction, then a fresh real-SDRAM5M boot. Baseline
is PC00006178,289197transfers,12known fetch faults/zero data faults and881board
events (121writes); it has noLCD and is not fullSymbian boot. Added latency means
PC/total transfers/timestamps need not be byte-identical at a fixed5M cutoff: compare
ordered architectural writes/fault context, explain permitted speculative-read
changes and run to the same semantic checkpoint if the bounded deadline shifts.
A later fresh logo/long boot is required before claiming the prior late firmware
behavior survived; never resume old HDL checkpoints into the new model.

Report cycles per **architectural instruction** using uop-last/retirement semantics,
plus acceptedfetch/issue and bubbles separately. Measure warmed dependent/independent
ALU, taken/not-taken/mispredict/loaded-PC branches, dependent loads, cachehit/miss,
write-through/buffered stores, LDM and dirty-maintenance loops at0/3/7/15/31waits.
The following are **proposed acceptance thresholds requiring agreement on the
benchmark mix**, not existing user requirements: ≤5% cycle increase on a fixed
diagnostic mix and≤10% on its memory/maintenance subset, while warmedADD remains
exactly1cycle;
exceeding either is a design review trigger, not silent acceptance. Publish absolute
counts and the operation mix; these limits do not imply Nokia cycle accuracy.

Before writing RTL for each slice, turn its estimates into an explicit cycle table
and scoreboard acceptance rule. Before calling the overall work complete, require
positive constrained timing and justified external interfaces on the final source,
then physical SDRAM patterns/refresh endurance and real-board boot evidence. The
current validated functional model remains the reference throughout; measured FPGA
closure and verified Nokia behavior remain separate claims.
