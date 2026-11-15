# F2: overlap completion consumption with the next owned request

The first F2 step reuses the existing registered completion credit. While the
CPU consumes a completed, fault-free P2 access, it can offer the following P1
access to the cache. Those stages run in parallel. No queue, pipeline register,
RAM, multiplier or clock change is added. The actual clock remains 78 MHz;
104 MHz remains the timing objective. Fitted logic and routed timing are pending.

This implements a bounded handoff, not the entire nonblocking F2 design. There
is still only one unresolved cache transaction. A delayed response still holds
the pipeline; arbitrary younger instructions cannot execute past a cache miss.
The existing register dependency checks still apply.

## Ownership and ordering

1. An unresolved P2 request holds the CPU until its data and fault context are
   captured in the existing completion register.
2. During the consume cycle, that registered response releases P2 into Memory.
   An eligible P1 packet may use the cache interface on the same edge that it
   becomes the new P2 owner.
3. An immediate next response replaces the consumed completion register. A
   waited response resumes the ordinary blocking P2 path. Each response is
   consumed once; the finished request is never replayed.

Eligibility depends on registered metadata and the registered completion, not
the live cache ACK. The older owner must be valid, fault-free, non-SWP and unable
to redirect the PC or raise an instruction exception. The next packet must be
an ordinary valid memory request without a flagged instruction exception.
Reset and writeback cancellation suppress admission. SWP retains its existing
serialized behavior, and CP15 still drains the complete pipeline.

Address, store data, byte enables, direction, effective mode, force-user flag,
load format, destination and unaligned FAR all select the same next owner.
The older Memory stage and early load forwarding continue to use the older
completion and store/nonload value. This separation matters: using the newly
multiplexed store data for the older Memory result would mix two instructions.

No cache or TLB protocol is replaced. Their existing admission, permission,
write-buffer, uncached/MMIO and maintenance boundaries remain authoritative.
The older operation has completed before a younger request is admitted.

## Measurements

Original SPMark payloads, five scored windows after two warm-ups, two exact
repeats, and synthetic I:D waits 0:0 / 2:9:

| Work | Before | Completion overlap |
| --- | ---: | ---: |
| Matrix ×16 | 56,009 | 56,082 |
| Transpose ×32 | 5,784 | 5,719 |
| Triangle edges ×16 | 27,744 | 27,667 |
| Full framebuffer, 0:0 | 87,288 | 71,269 |
| Full framebuffer, 2:9 | 201,316 | 201,314 |
| 16-bit tail | 3,015 | 2,574 |
| 8-bit tail | 3,076 | 2,624 |
| Original baseline index, 0:0 / 2:9 | 206.0389 / 179.2512 | 225.1646 / 189.3816 |

Equal-weight suite throughput gains are **9.2825% / 5.6515%**. Matrix regresses
0.13% in cycles; the delayed framebuffer remains limited by backing writes.
These are simulation indices, not official SPMark points or board speedups.

A separate matched load microbenchmark distinguishes throughput from latency.
The 128-load, four-register independent stream drops **325 → 235 clocks**,
38.30% more throughput (2.539 → 1.836 clocks per word). Its frontend and WAW
costs are included; this is not a pure cache initiation interval. The dependent
32-load/ADD test stays **259 clocks**. Both profiles and both repeats agree.

The original Thumb JPEG error-diffusion hotspot improves only **0.6265%** across
its four cases. The real-pixel 8×8 case drops **118,705 → 117,970 clocks**. Its
occupancy remains 34.76% data completion, 14.28% load dependency, 19.93% empty
operand queue and 7.00% decode sequencing. This does not pass or retest the
native ten-second JPEG deadline. Full post-change profiles reconcile all
original counters for both suites.

## Verification and remaining work

The completion scoreboard passes 10,547 clocks, including 657 consume/admit
overlaps, changing payload/fault context, waited and immediate responses, reset
and kill. Forty architectural programs pass 78 configurations with per-field
owner assertions, including faults, MMU/FCSE, privilege, SWP, CP15, block
transfers and instruction ordering. All 44 IRQ/FIQ boundary sweeps pass.

The new mixed-access guest passes waits 0 and 3. It checks narrow loads/stores,
force-user requests, stack transfers and load-to-PC wrong-path stores. Coverage
records 426 / 422 overlaps, including 100 narrow and 20 force-user requests in
each run. The maintained entry point is
`sh tests/cpu/completion_overlap/sim.sh`; outputs are isolated from unit-core.
Five exercised variants are rejected: no overlap, stale address, stale data,
stale force-user and stale format. Removing PC guards did not exercise unsafe
admission in this fixture because earlier cancellation still applied; that
experiment is explicitly not counted as guard coverage.

All twelve payload groups, exact repeats and six wrong-output controls pass.
All eight JPEG groups, unprofiled counter comparisons and eight broken
pixel/object controls pass. Patch 0067 reconstructs all 37 ZAP lexical streams
from 83 verified pristine file hashes. The noncompiled patch manifest changed
after the benchmark snapshot; all compiled HDL bytes still match it. Earlier
fixture/configuration mistakes and the stale shared upstream cache are recorded
in the qualification evidence instead of being treated as RTL failures.

Remaining F2 work needs explicit additional owner credits before relaxing the
hold on unresolved accesses, with precise oldest faults and ordered side
effects. JPEG also needs targeted Thumb load-use/frontend attribution: the
large independent-stream gain does not carry over to its dependency-heavy code.
Matrix now spends 31.88% in empty operands and 10.96% in multiply busy. The
older CPU import/arithmetic/frontend plan remains active. Physical fit/timing
and a native benchmark build are separate gates; none was launched here.

[Qualification](evidence/cache-completion-overlap-20261115.json),
[full payload](evidence/spmark-payload-completion-overlap-20261115.json),
[full profile](evidence/spmark-payload-completion-overlap-profile-20261115.json),
[JPEG](evidence/spmark-jpeg-completion-overlap-20261115.json).
