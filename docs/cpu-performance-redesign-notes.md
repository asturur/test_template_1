# CPU performance redesign notes

2026-11-09. Future work only. The current build candidate contains the measured
ROM-buffer, handshake and direct-SDRAM improvements. It does not implement the
redesign below. A substantial rewrite, including ZAP if needed, is acceptable;
select the scope from measurements rather than assuming the execution core is
the main remaining problem.

## Baseline to preserve

The current implementation uses ZAP execution/MMU integration with our custom
ARM920-shaped I/D caches. The serialized cache in `rtl/arm920/cache_access.sv`
is our implementation, not an architectural requirement for a five-cycle hit.
The target remains104MHz; the current hardware bring-up clock remains78MHz.
A104MHz period is approximately9.615ns. No new fit has established closure.

| Measurement | Earlier | Current | Scope |
| --- | ---: | ---: | --- |
| Warm ROM delay iteration |1713|1020|79 retired instructions,99 fetches; current loop makes no DDR reads|
| Clean32-byte D-cache miss |159|143|Median65 directed cases, modeled memory waits|
| Dirty-victim miss example |108|90|Includes overlapping writeback and bus contention|
| Serialized D-cache hit |5|5|Caller samples on fifth edge; response visible after four|
| DDR ROM buffer resident lookup |3|1|Separate1KiB instruction-only backing buffer,64-bit lines|

The dirty example is not intrinsically cheaper than a clean miss. In the
current directed program, the clean sample has85 instruction-port-active clocks;
the dirty sample has9. The modeled RAM backend is active for48 and60 clocks,
respectively. These are end-to-end CPU workload costs, not physical SDRAM access
times. Establish isolated memory costs and representative cached-code workloads
before making performance promises.

Current direct-SDRAM boot verification: `direct-sdram-final2-50m`,50M cycles,
3869533 retired instructions,zero data faults and12 unchanged early fetch
faults. It is still in the first firmware delay, not a complete logo/phone boot.
The original12B run remains on its frozen executable. More detail and commands:
[direct SDRAM path](direct-sdram-path.md), [uncached fetch](uncached-fetch.md),
and the earlier [104MHz architecture plan](cpu-cache-sdram-104mhz-plan.md).

Compact reproducible baseline: [performance evidence](evidence/performance-subset-2026-11-09.json).
The final precommit formatting adjustment changes only whitespace in a simulation
assertion; token equivalence against the50M-tested source was verified.

## Problems to redesign together

1. **Serialized demand lookup.** Acceptance captures an owner, then tag read,
   registered compare/way selection, data read and registered completion run in
   sequence. The controller accepts one demand at a time. Useful104MHz pipeline
   registers have become serialized waits instead of overlapped work.
2. **Word-oriented line refill.** One32-byte cache line uses eight independently
   handshaken32-bit requests. Each repeats routing, grant and completion. A dirty
   victim adds queued writes and ordering/hazard work.
3. **CPU memory coupling.** Load completion and global pipeline stall/hold rules
   can prevent useful overlap even if the cache itself is pipelined. Measure
   dependent load-use latency as well as independent access throughput.
4. **Shared external transport.** Instruction requests, data and page-table walks
   share a registered merger. Keep necessary arbitration, but avoid repeatedly
   releasing/reacquiring the entire path for each word of one line.
5. **Timing-driven patches lack a common latency budget.** Retain register seams
   needed for104MHz, but define their packet ownership and throughput explicitly.
   Do not trade correctness or routed timing for a lower zero-delay sim count.

## Candidate redesign scope

Start with the custom cache/refill and CPU load/store interface while retaining
ARM execution initially. Expand to the LSU, translation/completion interface or
whole ZAP pipeline if measurements show those prevent the required performance.
A replacement ARM core must still satisfy the existing ARMv4T/Thumb, banked
register, exception, CP15, MMU and cache-maintenance behavior needed by firmware.

The cache interface should carry an owned request and context through a
pipeline, with an ordered/tagged response and explicit capacity. Admission
should depend on registered capacity rather than a long completion-ready chain.
Evaluate one accepted hit per clock as a throughput objective; choose the hit
latency from actual FPGA RAM/compare/routing budgets. Do not promise one-cycle
L1 latency on Cyclone V before a fit. Reduce dependent-load latency too, rather
than merely adding queues around the old serialized FSM.

Evaluate resident tag/data reads in parallel with translation. Reading BRAM
speculatively is different from issuing a physical device access: completion,
refill, stores and side effects must remain qualified by the correct permission
and context token. Include FCSE/PID, privilege, TTBR/DACR/S/R, memory attributes,
CP15 invalidation/context changes and cancellation. Do not reintroduce the old
live request/abort/writeback qualification cone onto a high-fanout bank address.

Use a line-oriented memory interface: one owned32-byte request with a stream of
returned words, rather than eight CPU-level bus round trips. This need not mean
one unsupported physical32-byte SDRAM burst: schedule groups supported by the
chosen JTFRAME controller internally. Measure open-row behavior, refresh,
CPU/LCD fairness, critical-word latency and whole-line completion separately.
Early restart/critical-word-first is a later option with explicit partial-line
and error/retry rules, not permission to mark an incomplete line valid.

Dirty eviction, refill, maintenance and write-buffer ownership should form one
coherent design. Preserve overlapping-address ordering, dirty data until safe
writeback, and precise uncached faults. Existing cached-transfer retry semantics
must be reviewed against the ARM920 contract, not silently replaced. Preserve
SWP reservation across both halves, IRQ/FIQ behavior and flash command ordering.
DMA remains noncoherent unless independent hardware evidence justifies otherwise.

## Execution and acceptance gates

1. Freeze this build as a reference. Add latency/throughput counters at the
   public cache and memory interfaces. Benchmark cached and uncached code,
   dependent loads, independent hits, clean/dirty misses, write-buffer pressure,
   page-table walks and simultaneous LCD reads. Separate instruction contention
   from intrinsic memory service time.
2. Write a concrete cycle/ownership contract and104MHz register budget before
   implementation. Compare cache/LSU alternatives. Replace the old serialized
   design rather than layering another generic bridge or queue in front of it.
3. Implement hit-pipeline and line-transport changes in separately reviewable
   slices. Keep a functional reference and compare architectural results,
   memory effects, fault addresses/reasons and ordering under variable stalls.
4. Run CPU/chip/board regressions, real-controller SDRAM tests and fresh stock
   firmware runs of at least50M cycles. Add cache-enabled runtime coverage:
   another50M of the initial flash delay alone does not verify the redesign.
   Continue to the logo/later firmware frontier before claiming a working phone.
5. Fit each meaningful architecture slice and examine targeted paths, worst1000,
   resource use and load/branch throughput together. Keep useful pipeline stages;
   reject changes that only move the bottleneck or inflate latency excessively.

All new simulations need new executable/state lineage. Preserve billion-cycle
checkpoint pairs; do not restore old serialized HDL state into redesigned RTL.
Keep stock firmware/user images unchanged and the existing long run independent.

## Peripheral clocks are separate follow-up

The dedicated SDRAM route permits a later slow peripheral island. The whole UPP
cannot be slowed because it contains the ARM. Keep CPU/cache/SDRAM and the ROM
buffer fast; split flash from ordinary MMIO before changing peripheral rates.
Use captured request/response handshakes, correct reset/drain behavior and IRQ
synchronization. A CEN alone does not relax104MHz timing checks; actual derived
clocks or narrowly proven enable-to-enable multicycle constraints need explicit
analysis. Do not invent a universal26MHz bus rate or alter timer timebases to
hide a timing problem.


## Measured follow-up after the64-entry TLB replacement

The final50M C: scan now takes9512median clocks/read,4484reads versus3748 with
prior handshake-only RTL. Main-table lookup counts remain1,225,255D /769,505I
although only33D /24I lookups need page-table walks. The small local permission
token is keyed by direction/context as well as1KiB address, so switching read/
write or mode can cause main-table lookups despite a hot translation. Consider
registered read/write permission grants for the same mapping/context, or a tiny
multi-entry token front end, before changing architectural table size/semantics.
Do not let a read grant authorize a write or cross a1KiB AP boundary.

The data wrapper also retains pending_translation/lookup_resync sequencing from
the old pipelined TLB contract. Review whether it duplicates the new controller's
owned current-request token; measure its contribution before removing captures.
Preserve LDM/SWP/interrupt/fault/FCSE ordering and104MHz stage boundaries. These
are unimplemented opportunities, not claimed speedups. See arm920-tlb.md and
evidence/tlb64-2026-11-10.json. The old cache fallback is physically removed;
future cache work targets the single production implementation.
