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
four physical source indices and four RF base words with an owned commit journal.
Special/immediate kinds remain in the original 33-bit source fields. Source addresses sent to the RF
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

Patch0046 retimes the representation of committed bases without adding a pipeline
edge. Each slot stores a raw base and a three-bit one-hot pending selector per
source; shared `commit_a/b/c` registers hold the preceding edge's exact effective
writeback data. At any pre-edge observation, applying the slot's pending selector
to its base gives the architectural RF contents through the preceding edge.
Current effective writes remain visible combinationally at issue. A/B use the
exact selected writeback `wen,wa1,wa2,wdata1,wdata2` after exception/CP15/load
selection; C uses its existing background mask and source index <40. C wins B
wins A both within an edge and in the journal; a current edge beats the previous
edge. No producer-forwarded value is cached as a committed base.

On every clock (including data/shifter holds), old pending data folds into the
base and the new pending selector matches the current write against the slot's
**post-edge owner**. Capture stores the pre-edge asynchronous RF read and records
current matches for the incoming packet. Promotion folds the tail's old pending
data into head base and records current matches for that promoted owner. Reset
or clear kills both valid bits and both pending selectors on the same edge;
journal data need not reset because it has no valid owner after a kill.

The reserve payload/index/control captures every accepted D packet, including a
head replacement when the reserve stays invalid. This speculative invalid payload
is never promoted: reserve validity is unchanged, and a live reserve implies full,
which prohibits acceptance. Thus reserve data capture/refresh selection depends
only on capacity-qualified push, removing the measured load-lock→pop→tail-data
feedback. Head ownership and promotion continue to use the original pop rule.

The R→I interface exports raw head bases, head pending selectors and the shared
journal words. Issue selects special values, in-flight producers, current C/B/A,
previous C/B/A and raw base in **one** narrow-priority/masked-word reduction.
It does not serially select current commits and then pass that word through a
second forwarding mux. Current formatted commit data still reaches issue on this
edge; this path is retained, not waived or presumed closed.

| Transition on edge t | Base after edge t | Pending selector after edge t |
| --- | --- | --- |
| Empty→push, or head-only pop+push | Pre-edge RF for incoming source | Current t write matches incoming source |
| Held head/reserve | Own old base with own t−1 journal applied | Current t write matches held source |
| Full→pop | Tail old base with tail t−1 journal applied | Current t write matches tail source |
| Push while head held | Head refreshes; reserve gets pre-edge RF | Each owner's current t write matches |
| Reset/clear | Payload irrelevant | Both slots invalid, selectors zero |

Inductive freshness proof: capture's raw read already contains all writes through
t−1; applying pending t therefore represents the RF through t. A held/promoted
packet first folds its t−1 pending write into the base, then records t, giving the
same invariant. Current combinational t+1 overrides that representation at issue,
and nearer in-flight producers retain their existing higher priority. Kill removes
ownership before reuse; every new capture supplies a fresh base and selector.
All write pulses may vanish on the following edge without losing their values.

Late forwarding priority is unchanged: immediate, RAZ, PC, live ALU CPSR,
combinational A, registered A, P0, P1, P2, M ALU result, current C/B/A commit,
previous C/B/A journal, raw committed base.
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

## Patch0045 measured candidate evidence (before journal retiming)

Patch0045 implemented the original immediate-refresh representation.
`CPU_BUS_BRIDGE=1 sh tests/cpu/run.sh`
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

The subsequent run42482648381 fit reports83.89MHz, setup−1.634ns and
TNS−2680.821ns,33,156ALMs/464M10Ks. The read stage improved worst setup but still
fails104MHz; its D→R, commit→R, queue and late issue paths motivated patch0046.
The reported domain Fmax is limited by the separate half-cycle SDRAM path.
See status.md/timing-closure.md for the full routed analysis. No later architecture
slice should start before this operand follow-up's attributable fit is reviewed.

## Patch0046 physical intent and validation

The compact original indexed FF RF reads replace the forced masked reduction;
storage/write priority and all four asynchronous ports are unchanged. With the
same owned R contract, the original27,451-clock oracle passed this RF-only change
before journal/issue edits. This establishes functional equivalence, **not** a
physical A/B winner: only the masked version has a routed measurement so far.
The next integrated fit measures the indexed-read/journal candidate together.

The prior worst D→R path traversed two address-decode cells, four RF reduction
cells, current-commit bypass and queue selection (−1.634ns). Indexed reads leave
mux mapping to synthesis; raw capture removes current-commit data selection from
that cone. The old M/load-format→commit override→head-data path (−1.213ns) now
terminates first in the unconditional `commit_a/b/c` journal registers. Journal
folding and head promotion use registered data with narrow masks resolved before
word selection. Live backend write address/control still reaches pending-match
registers; it is not a timing exception. The measured pop→tail-data path
(−.674ns) has been structurally removed by invalid-reserve speculative capture.

The issue priority network includes all previous producers plus both commit ages,
so it is wider. Mask/routing locality, new pending-selector paths, journal fanout,
remaining head pop/selection and current formatted-write→issue routes are explicit
physical risks. The previous fit's issue/shifter and ALU→shifter recurrence
violations remain unverified. No clock/SDC/cache/translation/SDRAM/peripheral change
or extra frontend edge accompanies this retiming. Fmax104MHz is not established
until a routed fit checks these paths and the separate SDRAM half-cycle limit.

The extended independent oracle passes50,491 clocks,29,485 captures,24,017 pops,
7,670 full-pop events and5,379 kills. Every valid slot's base+journal representation
is compared against an independent40-word architectural RF before current writes;
issue outputs compare against that RF after current writes and newer forwards.
Directed tests exhaust all64 pairs of consecutive write-port masks at every40
physical index, with capture, held commit, reserve acquisition, promotion, issue,
kill and immediate reuse; random independent ports/producer masks and live CPSR
continue. Evidence lives in `scratch/timing-closure/slice1-finish/`.

The final full regression passes161 checks plus1 expected legacy direct-map XFAIL,
including all36 IRQ/FIQ SWP edge/wait cases. All144 CPU fixture outcomes retain
exact absolute cycle counts relative to patch0045. The mixed diagnostic at
waits0/3/7/15/31 has identical TIMING/PHASES/METRICS lines, including setup/body
counts, load-use18 minimum, branch-target14 minimum and warm ADD1. The3-wait
ordered effective RF/retirement-PC/CPSR trace matches all21,118 baseline effects.
The existing11.917% fixed-mix cost from inserting R remains unchanged.

High-wait runs require `CPU_MAX_CYCLES=2000000`; the default500k bound expires
inside the known631890-clock15-wait setup. The first high-wait attempt used that
insufficient default and was rerun with the explicit bound, without an RTL change.
Use `CPU_BUS_BRIDGE=1` when comparing the saved timing and legacy baseline;
the direct-bus fixture has different absolute counts.

Actual phone CPU integration, top structural lint, ONLY_CORE (parameter1) and
legacy elaboration,173-source/9-QIP preflight and exact46-patch reproduction pass.
The existing board bus_access lint warning remains. Fresh real-SDRAM5M is
byte-identical to patch0045's848-event board trace, including all timestamps,
121 ordered writes,12 known fetchfaults and all reads. PC00006154,289152transfers,
zero data faults and no LCD/DDR writes are unchanged. No old checkpoint was
restored into the changed executable; this is bounded early boot evidence.

Legacy direct-map smoke with the matching UPP bus bridge retains135782/234446
cycles at0/3waits; an additional direct-bus smoke passes86415/189126cycles.

## Patch0047: owned data completion and registered forwarding inputs

The next fit (42492307815 /738e6a7) proved RF→R+.495ns,
commit→journal+.659ns and journal→R+3.540ns, while exposing a different path:
D-TLB FSR/alignment fault→request ACK→global data stall→R capture. It also
measured M load-format→issue−1.291ns, dynamic producer matching−.983ns and
R source selection−.951ns. Patch0047 addresses completion ownership first,
then the registered inputs of late forwarding; it does not delay a bare stall.

In the selected associative configuration, P2 retains the entire request and
instruction context while `zap_data_completion` captures exactly one response
`{data, abort/retry, FSR, FAR}` on an offered request's ACK. The CPU remains
stalled on that capture edge. During the following cycle `completion_valid`
releases the pipeline, while external STB/CYC are suppressed so the held P2
request cannot replay an acknowledged store. P2/M consume the record together
on the next edge; the record then clears. The next P2 request can offer immediately
after that edge. Stall is now a function of registered P2 ownership and registered
completion validity; live ACK/fault decoding ends at the completion registers.

| Edge/cycle | P2 ownership | External offer | CPU behavior |
| --- | --- | --- | --- |
| Request first appears | Held request | Offered unless reset/WB kill | Stall asserted immediately |
| Waiting, no ACK | Same request/context | Same request remains offered | Hold P2 and younger pipeline |
| ACK sampling edge | Same request/context | Exactly one completion captured | Still held on this edge |
| Registered response cycle | Same request/context + owned response | Suppressed | Advance/consume next edge |
| Following cycle | Next P2 packet | Next request may offer | Normal execution or next demand wait |

Normal P2 and M advancement has no shifter or instruction-cache hold: their only
stop is `data_stall`, with reset/WB-clear taking priority. Consequently a valid
response always has exactly one next-edge consume, without a second ready signal.
An older WB redirect gates a first-cycle offer immediately. Once a demand has
waited one edge, M's validity and exception tags have been cleared by the existing
stall behavior; no unrelated older WB redirect can appear later. An integrated
assertion checks this ownership invariant throughout CPU/phone regressions.
Reset and WB-clear kill the record before capture/consume; reset retains the
existing external board drain contract. ALU branch clear does not kill this older
P2 owner. CP15 drain includes completion validity; uncached instruction-fetch
ordering uses the held P2 store even during its suppressed-offer response cycle.

The abort/retry bits reach the existing ALU/P0/P1/P2 fault suppression and M from
the same owned response. CP15 sees the captured FSR/FAR event, not a new live TLB
value after offer suppression. A retry retains the existing non-retirement and
restart semantics. IRQ/FIQ arriving during either SWP response half must still
observe the whole pre-SWP or whole post-SWP state. Legacy background-cache and
normal ONLY_CORE configurations retain their original raw completion protocol;
autonomous background writes/fault context are not forced into this blocking
owner. `files.qip` and the real-SDRAM test select the associative configuration.

This boundary intentionally adds one clock to a blocking demand's completion;
it adds no ALU pipeline stage. The first0/3-wait mixed diagnostic preserves warmed
ADD1, changes load-use minimum18→19, and changes measured body1397→1414 /
1651→1668. Setup241990→241991 /332246→332235 shows why total runtime cannot be
computed by adding one for each memory instruction: fetch/pipeline phase overlap
changes too. Full absolute performance and bounded-boot comparison follow below.

After completion ownership, the unchanged load transform moves before M's existing
`o_mem_rd_data` register. In the selected configuration its raw data already comes
from the completion register and its width/address context is the held P2 owner.
Signed/unsigned byte/halfword, word rotation and nonload/store semantics remain
unchanged. The M→writeback→issue path now begins with a formatted register word;
no extra stage or forwarding-priority change accompanies this retiming. The new
completion/P2→formatter→M register seam is explicitly timed, rather than omitted.

R also captures the static immediate/RAZ/PC/CPSR classifications with each packet,
appended to its existing control word. All older control-bit positions remain
unchanged. Issue reads those registered classifications before the unchanged
newest-producer/current-commit/prior-commit/base priority. Classification has no
producer-age dependency and follows the same capture/hold/promotion/kill ownership.
The independent operand oracle still compares values using source indices, not
the new classifications. Dynamic postALU destination matching remains a physical
risk for the next fit; this change does not predict forwarding state or add stalls.

Directed checks: completion owner5546 clocks (438captures,398consumes,114kills),
independent registered formatter8192clocks, and the existing50491-clock operand
oracle pass. Completion-only CPU checks pass all36 previous SWP IRQ/FIQ edge/wait
cases, alignment and write-abort fixtures. The final sweep adds both registered
SWP read/write completion edges, making44 cases. Forwarding changes preserve the
completion-only0/3 timing results exactly. Evidence is retained under
`scratch/timing-closure/completion-forward/`.

Residual RF locality is **not** addressed by static class capture. The measured
D→R−1.060ns route starts at D.alu_source[1], crosses a decode output cell and the
writeback CP15-address select (fanout194), then the compact RF mux and two head-data
select cells. The CP15−.635ns route shares that selected address (fanout192).
Storage→R passes+.495ns, so replacing the compact FF read with the previous
area-heavy masked tree is not justified. This candidate changes completion/capture
control and placement but leaves the RF address-select path itself intact.
If still limiting, a dedicated CP15 asynchronous port on the same FF array can
remove address stealing from operand port0 at the cost of another read mux;
registered D bank/word predecode is a larger alternative that moves timing debt
into D. Neither is implemented or claimed validated here. Dynamic postALU matching,
RF address locality, shifter recurrence and unrelated cache/bus/peripheral paths
remain explicit next-fit residuals. No104MHz closure claim is made.

### Final patch0047 validation and costs

`CPU_BUS_BRIDGE=1 sh tests/cpu/run.sh` passes171 checks plus1 expected legacy
XFAIL:152 CPU outcomes, including44 SWP IRQ/FIQ arrival cases. The completion,
formatter and operand oracles described above pass; no late-WB-kill, request-replay,
CP15-drain or precise-fault assertion fails. The3-wait diagnostic matches all21,118
ordered effective RF/retirement-PC/CPSR effects against patch0046. Legacy CPU smoke
retains135782/234446 cycles at0/3waits. ONLY_CORE elaboration passes with and without
the associative macro. Phone CPU integration, structural lint,174-source/9-QIP
preflight and exact47-patch reproduction pass; the old bus_access warning remains.

| Waits | Setup old→new | Mixed body old→new | Total old→new | Load/use min old→new | Branch/target min |
| --- | --- | --- | --- | --- | --- |
|0|241990→241991|1397→1414|243387→243405|18→19|14|
|3|332246→332235|1651→1668|333897→333903|18→19|14|
|7|406201→406204|2001→2018|408202→408222|18→19|14|
|15|631890→631890|2725→2742|634615→634632|18→19|14|
|31|1091490→1091490|4177→4194|1095667→1095684|18→19|14|

Warm dependent ADD remains1clock at all five waits. The measured body adds17
clocks each time (+1.22%,1.03%,.85%,.62%,.41%). Each of the ten load-use gaps adds
one; the nine branch-target gaps retain min14/max and their sum decreases1.
Normal mixed retirement remains12,656 instructions plus4 serialized CP15
instructions; there is no missing architectural work. Source-class capture and
M formatting have no additional latency beyond the owned completion boundary.
High-wait runs explicitly use `CPU_MAX_CYCLES=2000000`.

| Fixed-mix program | Old cycles0 /3 | New cycles0 /3 |
| --- | --- | --- |
|cpu_timing|242672 /333087|242673 /333076|
|ldm_base_coldcache|242875 /333629|242862 /333551|
|cache_drain|242960 /333717|242957 /333681|
|swp_basic|380 /552|377 /547|

The fixed mix changes1729872→1729724 (−.0086%); memory subset1154113→1153975
(−.0120%). Every program retains identical accepted-issue and retirement counts.
Small fetch/pipeline phase changes outweigh the added completion edge in this
particular initialization-heavy mix; this is not a universal speedup claim.
The total remains11.9075% above the pre-R baseline1545673, so the earlier R-stage
cost remains an explicit tradeoff. The dependent-load penalty19 versus18 is real.

Fresh real-SDRAM5M reaches PC00006168/289114transfers,12 known fetchfaults and zero
data faults. All848 board events match patch0046 **in order** when timestamps are
removed:121writes, all reads, and the same12 fault records. There are no changed
side-effect reads. The final board write moves189507→190170 (+663clocks), reaching
the same semantic checkpoint. No LCD/DDR writes occur; this remains early boot,
not a logo/full Symbian or physical-phone result. No saved CPU/host checkpoint or
frozen executable was modified or resumed. The old two elaboration text logs were
accidentally overwritten by runner reuse; their original PASS remains recorded
and the files explicitly point to this run's logs. Board/effect/reference evidence
remains preserved.

Full evidence and tested-source hashes:
`scratch/timing-closure/completion-forward/validation-summary.json`.
The next isolated routed fit must check the new completion capture→local advance,
completion/P2→M format and formatted M→issue seams, alongside unchanged RF-address,
dynamic producer matching and shifter paths. This candidate is functionally
validated;104MHz closure is still unmeasured.
