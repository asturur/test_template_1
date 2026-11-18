# Step 5M — registered demand permission/admission

**Reject this 5M boundary; keep the exact retained 5L overlay.** The isolated
experiment removes the identified live translation-context cone from resident
ACK selection at source level, but adds substantial measured waits. It does not
preserve the favorable one-start-per-clock stream or the game span gains.
There is no new fit, clock-frequency gate, production change or public commit.

## First: exact 5L broad qualification

The missing six-original-workload campaign completed before 5M implementation.
All 60 retained 5L RTL/header hashes match its prior game, stream, JPEG and
safety receipts. Both wait profiles, five scored windows, two equal repetitions,
original program/payload/ROM/harness identities, independent output oracles,
retirement checks and all six corrupted-output controls pass.

| Canonical original workload | Promoted ccba54f | Exact 5L |
| --- | ---: | ---: |
| Matrix, both profiles | 45,073 | 45,073 |
| Transpose, both profiles | 3,560 | 3,560 |
| Triangle, both profiles | 23,568 | **23,520** |
| Frame, 0:0 | 71,259 | 71,259 |
| Frame, 2:9 | 201,302 | 201,302 |
| Halfword tail, both | 1,332 | 1,332 |
| Byte tail, both | 1,647 | 1,647 |

Six-case geometric throughput is **1.000339847×** relative to promoted 5K
in either profile. This is separate from the game-span gain. No material
regression needed investigation before stacking the experiment. Existing exact
5L JPEG84,353, span34,995/34,920 and stream/safety evidence is reused by source
hash, not rerun under a different wrapper. The guarded transpose below is a
different wrapper from the canonical six-kernel transpose above.

[Independent 5L broad receipt](evidence/cpu-late-operand-six-20261117.json).

## Routed path traced before selecting the cut

The saved seed42/debug-on 5K fit44123116917 has slow100C 78MHz setup−1.069ns.
Its precise launch/capture pair is CP15 `o_baddr[16]~DUPLICATE` to the
Quartus-created `late_p1_ready~9_OTERM19055` register: **13.073ns, 11 logic
levels, approximately8.309ns interconnect**. The release report rounds routing
to8.308ns; individual report totals are retained in the path receipt.

The actual path traverses TLB `shared_context` equality, `second_match`,
`o_busy`, adapter `fast_hit`, `request_ack`, completion capture logic named
`o_far[0]~1`, and optimized `late_p1_ready` control. The original RTL already
registers completion; the endpoint is physically optimized/retimed logic, not
evidence of a newly discovered combinational RTL ACK-to-issue bypass.

During a held P2 demand the CPU holds its exact request, but the old adapter
continues to gate fast hit, fault and retry with live permission/busy signals.
A steady held address therefore does not remove the table-base comparison
from ACK's capture cone. Registering only a reusable token and then checking
TTBR/DACR against live context at consumption would recreate that same path.
[Exact launch/capture and per-element path](evidence/cpu-load-admission-path-20261117.json)
was extracted before implementation.

## The single experiment

The reproducible overlay starts with the exact 5L Core/Issue implementation.
It adds a permission register in D-cache before the unchanged cache adapter.
The record captures **one actual demand's** MVA, direction, mode, byte enables,
SWP identity, alignment/fault context, physical address, cacheability,
bufferability and permission/busy outcome. A matching registered record is
required before either read or write is presented to the adapter. Capturing a
hint is never sufficient. An old record is consumed on ACK rather than reused
for the next dynamic instruction, even at the same address.

Consumer ownership checks only the current request's address/class/mode/byte
and SWP selectors plus a registered revoke event. There is **no live wide
TTBR/DACR/SR/MMU equality check in `admitted`, ACK or adapter permission inputs**.
The TLB and retained-translation machinery still validate current context;
their result terminates at the new permission register.

CP15 produces one new context-change register on the same edge as its exported
TTBR, DACR, SR, MMU/cache/alignment and FCSE controls change. Wide equality
comparisons terminate at that register. It revokes an unconsumed admission
alongside the existing registered TLB/cache mutation strobes and writeback kill.
The adapter's fast hit, error/retry and physical payload consume registered
permission fields. Legacy idle ACK is prevented from completing a CPU request
that is still waiting for permission.

Both successful and faulting responses retain the ordinary CPU completion
register. Variable-latency requests hold their owner. A killed demand cannot
retain its admission record. Faults/IRQs/retries preserve the original in-order
register/flag and MMIO rules. Once a cache/external transaction has been accepted,
its existing adapter owner drains it; the new token is not permission to cancel
an already-issued device transaction or to issue another one. Actual CPU CP15
changes remain serialized by the existing pipeline.

The first context-negative run exposed an old retained-translation/resync record
that was not cleared with admission revocation. The same experiment was fixed
by clearing those existing records on the revoke event; no second optimization
was stacked. The subsequent remap test initially expected new physical data
without invalidating the ARM920 virtual-tag cache. The fixture was corrected
to perform both cache and TLB maintenance; that test correction changes no RTL.

## Actual costs versus 5L

All rows below pass both0:0/2:9 with five equal scored windows, two equal full
repetitions and the original wrong-output controls. No result is extrapolated
from the earlier 1,536-clock scenario or from the routed clock objective.

| Identical work | Exact 5L | 5M | Added clocks |
| --- | ---: | ---: | ---: |
| Original forward span,512pixels | 34,995 | **39,214** | **4,219 (+12.056%)** |
| Original reverse span,512pixels | 34,920 | **39,289** | **4,369 (+12.511%)** |
| Guarded original transpose | 3,441 | 3,895 | 454 |
| Single-line independent stream | 343 | 477 | 134 |
| Eight-line independent stream | 499 | 514 | 15 |
| Dependent32-load/add checksum | 239 | 239 | 0 |

Forward is **76.58984375 clocks/pixel**, reverse **76.736328125**. Exact
original output, guards/source/stack,10,240 retirements,512 ordered actual RAM
mutations and byte counts remain checked. Both dynamic retirement PC streams
match 5L; no missing work accounts for timing differences. Final cache writes
and stores retire before the timing boundary, with no remaining store credits.

The single-line fixed interior executes **224 useful starts in336 clocks**,
versus224 in224. Its alternating gaps become112 two-clock and111 one-clock
gaps. The typical load initiation interval is2→3 clocks; useful instruction
rate is1→0.6667/clock. All256 region starts/retirements remain present. The
multiline interior changes342→344 clocks for224 starts; two existing five-clock
gaps become six-clock gaps. Full-window overhead still grows499→514.

Two concrete blocking edges explain the cost:

1. An immediately available resident hit previously completed on the first
   offered demand. It now waits for this dynamic demand's permission register.
   After consumption a new dynamic request cannot reuse the prior token.
2. Qualifying the adapter's read input also delays its existing raw P2 fallback
   probe. The early ALU/P1 hint remains private and unchanged, but certificate
   misses and following operations can need another registered selection/read.
   Admission also delays immediate store-credit starts. No added external
   traffic is hidden: all scored reads/writes/line requests remain zero.

In the first forward iteration, one byte load's dequeue→ACK changes12→13;
the next changes13→14. The halfword store changes13→14 and its following coordinate-step load
16→22. A representative P1 stack word retains4-clock offer/5-clock ACK and
its 5L late arithmetic path. Thus the new register is often hidden on the
intended prepared word load, but exposed on other operations and streaming
first-cycle hits. The complete bounded edge journals retain both cases.

Exclusive accounting reconciles every added span clock:

| Nonoverlapping bucket | Forward delta | Reverse delta |
| --- | ---: | ---: |
| Read data stall | +3,614 | +3,761 |
| Write data stall | +605 | +608 |
| Load dependency, other dependency, empty, advancing | 0 | 0 |
| **Elapsed** | **+4,219** | **+4,369** |

The 5L arithmetic benefit survives structurally, but these new waits overwhelm
it. Merely restoring raw private fallback scheduling would not remove the
single-line stream's mandatory dynamic-demand admission wait. Avoiding that
wait requires an earlier, properly owned qualification boundary; it is future
work, not an unmeasured fix credited to this run.

## Correctness checks and physical implications

The final context fixture uses the actual candidate D-cache, TLB and cache:
changed table plus proper maintenance produces the new physical data; permission
revocation causes exact domain fault and **no data read**; changed-address and
killed-token negatives reject stale ownership; TLB invalidation revokes admission.
Both complete fixture repetitions agree. The unchanged cache/adapter collision,
stale-probe, alias-store, credit-pressure and poisoned-RAM guard receipt is reused
only after checking every unchanged ARM920 module hash. This is explicitly
component reuse, not a newly executed whole-CPU collision campaign.

Actual CPU flags/predicated-writer/IRQ/fault/MMIO safety passes twice at0:0,
2:9 and0:97. Eight focused ARM/Thumb/MMU/FCSE/discarded-and-actual-prefetch-fault/
return diagnostics pass. Separate same-CPU response controls check a missing
response remains held128clocks with zero execution, and one injected retry
causes two acceptances but exactly one useful execution. The 5M JPEG and broad
six-kernel campaigns were not funded after this material regression; their
already qualified 5L results remain separate.

Incremental source-level state over5L is **165 bits**:164 for demand ownership,
permission and fault/physical payload plus one CP15 revoke event. There are
new request-identity comparisons, field muxes and valid/revoke fanout. Some
fields may be pruned/shared or physically replicated; no mapped ALM/register
prediction is claimed. No RAM/port/DSP/cache geometry is added. Only Core,
CP15, D-cache and Top differ from5L; all60frozen RTL/header inputs and51actual
compiler inputs are recorded. Cache/adapter/Issue remain byte-identical.

The source-level cut is CP15/context/TLB result→permission register, followed
by local owner→resident ACK→existing completion register. Wide CP15 changes
reach token consumption through a **registered event**, not reconstructed
live equality. The new permission-capture and revoke paths, local identity
fanout, remaining instruction-side translation paths and physical retiming need
an actual fit. The old13.073ns delay cannot be reduced by subtraction to claim
a new Fmax. **No5M fit was run; 78MHz PLL and104MHz design objective are unchanged.**
Rejection is based on measured useful work, not an artificial104MHz simulation gate.

Keep5L as the qualified offline base. Preserve the5M test/evidence as a failed
boundary worth avoiding; do not promote it. Production/master/public history,
other chats' runs and existing fit artifacts remain untouched. Completed own
compiler trees and derived private inputs are disposable after hashes; compact
logs, manifests, source generator and reusable tests remain.

[Replay and test inventory](../tests/cpu/cpu_load_admission/README.md) ·
[Machine decision](evidence/cpu-load-admission-20261117.json) ·
[Compared journals](evidence/cpu-load-admission-20261117.events.json.gz).
