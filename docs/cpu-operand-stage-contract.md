# Operand acquisition slice: implementation contract

2026-11-08, baseline `ef9b7621fa2ca90af250ce8d988260ebbc5e59d6`.
This is the exact slice-1 implementation contract; measured evidence follows below.
The whole-system proposal remains in `cpu-cache-sdram-104mhz-plan.md`.
The parent reviewed the measured uncached-workload penalty and accepted this as a
fit candidate pending complete functional checks, not final performance acceptance.

## Ownership and interface

`zap_operand_read` owns two ordered packets: head R0 and reserve R1. It is
instantiated by `zap_issue_main`, which no longer owns the old skid replay.
A packet contains the complete existing decode context (including debug text),
four physical source indices and four committed RF base words. Special/immediate
kinds remain in the original 33-bit source fields. Source addresses sent to the RF
come directly from D, independent of queue selection, locks, or upstream stop.

`o_full` depends only on registered occupancy. It replaces `o_stall_from_issue`
for upstream D/P/T/FIFO stopping. `o_valid` identifies the R0 head;
`o_busy` (either occupied slot) participates in CP15's pipeline-empty test.
Issue consumes R0 only when !data_stall && !shifter_stall && !hazard. Capacity stop
must NOT mask issue outputs at the shifter: that old core gating is removed.
Issue itself emits NV/no exception/no flag update/no SWP on hazard or empty R0.

D advances and R accepts together on !data_stall && !shifter_stall && !o_full.
A D packet is meaningful when condition != NV or any IRQ/FIQ/abort/SWI/UND tag is
set. Bubbles consume no capacity. D holds a third, unaccepted instruction when
full; this is existing D storage, not an additional queue entry. There is no
combinational downstream-ready -> upstream-ready path.

| Pre-edge occupancy | Pop | Meaningful D accepted | Post-edge state |
| --- | --- | --- | --- |
|0|0|0/1|empty / D in R0|
|1|0|0/1|hold R0 / hold R0, D in R1|
|1|1|0/1|empty / D replaces R0|
|2|0|0|hold both; D stopped|
|2|1|0|R1 moves to R0; D remains stopped for this edge|

A full queue cannot accept on its pop edge: readiness is deliberately conservative.
The remaining R0 lets D resume on the following edge without a throughput bubble.
With a continuously ready consumer, occupancy stays one and pop+push sustains one
uop/clock. Hazard delays can consume the one reserved extra slot before D stops.

## Stop, kill, flags and forwarding

Reset or either existing issue clear input kills both slots and I validity on the
same edge, with priority over all holds/capture. No delayed clear is added. This
preserves issue's existing unconditional ALU-clear behavior; D retains its existing
ALU-clear qualification by !data_stall. data_stall or shifter_stall holds packet
ownership and I, but MUST NOT stop committed-write snooping. Hazard holds R0,
allows bounded D admission, and bubbles I while older execution advances.
Writeback redirects/mode changes cancel younger physical bank mappings immediately.

The packet's committed base is refreshed on EVERY clock by the exact effective RF
writes. Expose writeback's `wen,wa1,wa2,wdata1,wdata2`, after its exception/CP15/load
selection; C is the existing background one-hot write mask/data. Per source, C wins
B wins A; A/B require wen; C needs its source bit and physical index <40. Capture
uses this same effective-write override of the asynchronous RF read. R1->R0 moves
the snooped R1 value, not its pre-edge stale base. The issue-edge base uses the same
combinational write override, so a concurrent write is visible before the clock.
No producer-forwarded value is cached as a committed base.

Late forwarding priority is unchanged: immediate, RAZ, PC, live ALU CPSR,
combinational A, registered A, P0, P1, P2, M ALU result, refreshed committed base.
The nearer in-flight producers are older than this in-order consumer but newer
than commits. Loads keep all existing I/S/A/P0/P1/P2/M and background locks;
M's ALU/base result never stands in for its load write. Shift/multiply/flag locks
and shifter `resolve_conflict` remain. Legacy background WAW locking remains.
Exception-dependent background-load locking must use R0 tags, not the unrelated
live D packet (the old skid code used live D here). PC alignment still uses the
packet's load/store/force-align controls; CPSR is read live at issue.

CP15 sees either R slot as nonempty, in addition to the existing upstream/backend
stages and background locks. Its stolen RF read port0 therefore cannot overlap a
meaningful R acquisition. No cache, translation, memory, interrupt tagging, uop
sequencer or architectural writeback behavior is redesigned.

## Cycles and measurement gates

| Enabled edge relative to D@0 | Baseline | Candidate |
| --- | --- | --- |
|1|I|R|
|2|S|I|
|3|A|S|
|4|P0|A|
|5|P1|P0|
|6|P2|P1|
|7|M|P2|
|8|RF commit|M|
|9|—|RF commit|

Expected: +1 initial enabled edge, warm independent/dependent unshifted ADD interval
exactly1. Branch resolution from D +1; redirect-to-target-I +1; fetch-old-branch to
execute-target can total +2. P predecode redirection unchanged. Load-use issue
spacing should remain unchanged because both producer and consumer move together
and same-edge commits bypass. Exception delivery/recovery can gain the same stages;
no fixed wall-clock offset is assumed through stalls or interrupt sampling.

Small explicit diagnostic mix: existing `cpu_timing` ALU/branch/load/store markers
plus `ldm_base_coldcache`, `cache_drain`, and `swp_basic`, at waits0/3 (and timing
fixture at7/15/31). Record absolute cycles and accepted I/architectural uop-last
retirement, excluding debug decompile-message counts. Fixed-program total cycle
comparison and per-kind spacing are separate. The proposal's5% aggregate/10%
memory thresholds are review triggers; cold-start/tiny programs may exceed them.
Any loss of warmed ADD CPI1 or unexplained architectural effect is a stop condition.

Reference sources/board trace are preserved under
`scratch/timing-closure/slice1-operand/reference/`. A test-only frozen original
issue module and independent RF/operand oracle will remain selectable without
adding duplicate CPU/cache hardware to production. Full regression, actual-phone,
fresh5M real-SDRAM boot, source/lint/provenance gates follow coherent implementation.
Physical D->R/R->I/W->R/A->S timing and resources require the parent's later fit;
include RF capture plus A/B committed-write bypass and CP15 read-port mux paths
in the targeted inventory. These remain potential critical cones.
this contract and simulation cannot establish104MHz closure.

## Measured candidate evidence

The RTL implements the contract above. `CPU_BUS_BRIDGE=1 sh tests/cpu/run.sh`
passes161 checks plus1 expected legacy direct-map XFAIL, including36 IRQ/FIQ SWP
arrival cases across D/R/I/S/A/P0/P1/P2/write-half at waits0/3. Existing SWP faults,
IRQ/FIQ, banking, MMU/TLB, alignment/LDM/PC, maintenance/lockdown/coherence pass.
CP15 assertions reject an owned packet omitted from drain or a meaningful capture
while it steals RF port0. Actual CPU phone integration, top structural lint,
ONLY_CORE/legacy elaboration,173-file/9-QIP source preflight and exact45-patch
reproduction pass. A separate legacy direct-map CPU smoke also passes at0/3
waits (135782/234446 cycles), exercising the background-completion fallback.
Structural lint retains the preexisting board `bus_access`
UNOPTFLAT warning; no new operand combinational loop is reported. Patch0045 reproduces the owned R queue, issue integration,
selected writeback snoop interface and core drain changes. The RF tree itself,
ALU/shifter, cache, MMU, transports, clock/SDC and firmware are unchanged.
No new clear delay exists. The former `stall_from_issue` now means only R capacity;
I bubbles itself on a hazard. Reset/redirect also explicitly clears I's uop-last.

The independent queue/RF/priority scoreboard passes27,451 clocks:16,738 captures,
16,388 pops,5,088 full-pop transitions and259 kill/reset cases. It checks committed
values independently from a40-word architectural RF model, including every write
collision, same-edge issue/capture, long holds after a producer retires, promotion,
PC/CPSR/RAZ/immediate, and exception/SWP/uop context. The original17160-clock oracle
is retained in `tests/cpu/operands/reference-test.sv`; `reference.sh` reconstructs
the four baseline modules from the pinned commit in scratch. Production contains
one CPU and no reference selection. `CPU_REFERENCE_DIR` is a test-runner option.

`operand_timing` compares21,118 ordered effective RF writes and backend retirement
PC/CPSR records exactly at3 external waits. It checks10 iterations of16 dependent
ADDs, dependent load/add/store, ADDS/ADC/SBC, multiply/register shift and branches.
The warm120 ADD intervals are1 at waits0/3/7/15/31 in both implementations. Counters
read actual stage transfers and writeback uop-last completion, not decompile text.
The initial `fetch` metric counts response-valid observations; the final observer
also reports separately qualified F-stage accepts (excluding sleep/clear/stall).
The mixed diagnostic completes12,656 ordinary architectural instructions, plus its
four serialized CP15 instructions (12,660 total); the original ADD diagnostic has
12,496+4=12,500. CP15 instructions do not traverse ordinary backend retirement.

| Waits | Mixed setup baseline → R | Mixed measured body baseline → R | Load/use issue gaps (10 samples), baseline → R | Branch/target gaps (9 samples), baseline → R |
| --- | --- | --- | --- | --- |
|0|209230 →241990|1387 →1397|sum239 →238; min18 →18; max77 →76|sum199 →205; min13 →14; max55 →54|
|3|303604 →332246|1643 →1651|sum290 →290; min18 →18; max128 →128|sum247 →253; min13 →14; max79 →78|
|7|402095 →406201|1993 →2001|sum362 →362; min18 →18; max200 →200|sum311 →317; min13 →14; max111 →110|
|15|631889 →631890|2698 →2725|sum504 →504; min18 →18; max342 →342|sum439 →445; min13 →14; max175 →174|
|31|1091489 →1091490|4169 →4177|sum825 →825; min18 →18; max663 →663|sum695 →701; min13 →14; max303 →302|

Total mixed-program cycles per completed architectural instruction (including
setup and four CP15 completions) are16.636→19.226,24.111→26.374,31.918→32.243,
50.125→50.128,86.546→86.546 at waits0/3/7/15/31. These totals intentionally retain
the initialization cost; the body table is a separate phase comparison.

The body starts at first ADD issue and ends at the success mailbox; it includes
cold cache fills, ten loop iterations and final checks, not only warmed code.
The first load is cold; the other nine have18-clock issue spacing in both designs.
Warm branch→target increases1 clock. Nonuniform cold/fetch/exit costs mean a
single fixed timestamp offset is not a valid model. Body increases0.72%,0.49%,
0.40%,1.00%,0.19% respectively; these are diagnostic observations, not Nokia CPI.

The uncached4096-iteration table initialization is a **material regression** at
low waits. At0 waits, its4095 branch→next-store intervals increase27→35, accounting
for exactly32760 extra setup clocks. Store→SUBS sums65534→61439 cancel SUBS→branch
sums32769→36864 (4096 samples each). At3 waits, branch→store stays36; store→SUBS
sum110592→139251 adds28659 while SUBS→branch45056→45055, accounting for almost all
of the28642 setup increase (the remainder is phase entry/exit). Fetch-response observations
increase by4088 across the mixed program at3 waits. Thus added backend depth and
bounded frontend scheduling interact with uncached fetch/data stalls: the physical
one-edge insertion does NOT imply a universal one-wall-clock branch penalty.
This slice makes no cache/frontend optimization to conceal that cost.

Fixed contract mix (each program at waits0/3; all totals include setup):

| Program | Baseline cycles0 /3 | Candidate cycles0 /3 |
| --- | --- | --- |
|cpu_timing|209901 /304437|242672 /333087|
|ldm_base_coldcache|210119 /304984|242875 /333629|
|cache_drain|210216 /305084|242960 /333717|
|swp_basic|379 /553|380 /552|

Aggregate1545673→1729872 clocks (+11.917%); memory subset (last three programs)
1031335→1154113 (+11.905%). These exceed the proposal's5%/10% review triggers.
The parent must assess this explicit uncached-workload tradeoff against actual fit
results; no real-time speedup or blanket CPI acceptance is claimed. Warm recurrence
and cached mixed-body behavior remain useful, independently of the aggregate.

Fresh real-SDRAM5M reaches PC00006154,289152 bus transfers,12 known fetch faults,
zero data faults. Baseline was PC00006178/289197. All121 ordered architectural board
writes and12 fault records match; the final board write occurs at189507 versus
189735, so this semantic checkpoint has been reached. Board events848 versus881
reflect66 old versus33 new reads exclusively within executable UPP RAM
0x0c004750–0x0c0047cc; no differing side-effect MMIO read, write, or new fault.
The deeper frontend changes repeated/speculative code reads and cutoff PC phase.
No LCD/DDR writes occur at this early bound; it is not a full Symbian/logo result.
All evidence is under `scratch/timing-closure/slice1-operand/`, including the
normalized boot comparison and exact read-difference list. Old checkpoints and
frozen executables were untouched; the new boot starts from reset.

Fit remains unmeasured. Evaluate D→R including RF/CP15-port selection and selected
A/B committed-write bypass, R→I forwarding, W→R refresh, R promotion/enable, A→S
recurrence, and capacity/clear distribution. The proposed resource limits still
apply as review triggers; no extra M10K is intended, but synthesis must establish
actual area/inference. Do not proceed to a later architecture slice without this
slice's attributable whole-project fit and review.
