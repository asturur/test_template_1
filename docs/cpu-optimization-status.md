# CPU/cache optimization ledger — 2026-11-16

This reconciles the original [CPU import plan](cpu-donor-import-plan.md) with
the [cache latency plan](cache-load-optimization-plan.md). Implemented below
means present in our RTL and qualified in simulation, not automatically tested
on MiSTer or closed at104MHz. Actual PLL remains78MHz.

## Measurements and current physical gate

With the original six-kernel baseline defined as100, the latest implementation
scores **230.3221 /193.7181** at synthetic I:D waits0:0/2:9. Block-transfer
setup/final-writeback fusion gains0.1241% over admission-edge pre-read reuse,
and1.7284% on the four-case JPEG bitmap suite. These are kernel throughput,
not whole-phone or donor-relative speed. Native JPEG remains unqualified.

The6f3baa2/seed43 build43785027340 packs all16SDRAM pin I/O registers and its
78MHz CPU setup passes+0.037ns. HDMI setup-0.440ns still fails the timing gate.
It fits38385ALMs/503M10Ks/42DSPs. It excludes the new block-transfer change.
Native original-firmware boot and healthy autosave are observed on this build;
new build/fit/timing/boot qualification is still required for patch0070.

## Implemented

| Original item | What is present | Remaining boundary |
| --- | --- | --- |
| Earlier foundations | Replicated MLAB/latest-writer RF0057; architectural64-entry I/D TLBs, posted write buffer, streamed32-byte line fills and direct SDRAM route | These predate baseline100; do not count their savings again |
|02b: ARMv4T profile | Remove guest ARMv5/5TE instruction hardware, retain required ARMv4T/internal uops; targeted Thumb SWI/UND links | PSR policy and broader02a/02c correctness audits remain |
|07/12b, cacheA/D | Remove redundant owned-translation handoff and extra hit-response copy | Full multi-request cache pipeline remains separate |
|12b, cacheB | Reuse separate read/write permission grants for the same checked mapping | Preserve exact privilege/AP/domain/context invalidation |
|12b, cacheC | Two checked1KiB mapping records under shared context | Main architectural TLB and real lockdown retained |
|12b, cacheE0 | Remember absent cache lines so ordinary nonallocating store misses skip repeated tag searches | This is metadata reuse, not new allocation policy |
|12b, cacheE1/E2 | Reuse selected resident way for indexed loads/stores; fresh dirty metadata ownership | Still checked against current request permissions and cache mutations |
|08: load availability | Forward registered aligned-word P2 completion; use actual formatted Memory commit; correct paired base/load priority | Narrow/unaligned/SWP/fault classes retain formatting boundaries |
|CacheF1 | Owned next-address RAM-B read while independent RAM-A write commits | Collisions interlock/forward; not arbitrary concurrent misses |
|06/timing | Late-ACK FIFO flag rewrite without extra cycles | Physical timing still requires each placed build |
|03 and bounded10b | Decoded-owner BTB feedback; correct MOV pc,lr recognition; retain confirmed targets | Full speculative RAS recovery is not implemented |
|07/store completion | Ordinary posted stores reply after durable reservation; resident stores on data/dirty commit | SWP/write-through/uncached ordering retained |
|Bounded cacheF2 | Consume old registered completion while admitting eligible next P1 request | Only one unresolved demand; global miss hold remains |
|New: execution-stage latency | Remove legacy P0 register; preserve registered P1 TLB/probe and P2 demand/completion | Routed timing and board qualification pending |
|New: Thumb prediction addresses | Canonical fetch targets avoid state-bit-only false redirects; raw BX mode changes retained | JPEG +2.2906%; full speculative RAS and general frontend gaps remain |
|New: admission-edge read | Consume an already owned matching RAM-B result one clock earlier; one metadata bit | Other cache-hit waits and full multi-request overlap remain; physical timing pending |
|09a/b, bounded block transfers | Fuse ordinary first-beat setup and incrementing final base writeback using existing lanes | No extra state/RAM; broader streaming/PC/abort optimizations remain separate |

The historical BTB tag-collision correctness fix is also present; it is not a
new performance gain to add to the table. See the [measured progression](spmark-payload-results.md).

## Remaining work before a large parallel execution redesign

The order below is a recommendation, not measured promised gains. Finish the
current physical/boot gate before qualifying another hardware revision. Address
correctness gaps when their fixtures reproduce an actual issue.

| Suggested priority | Original items | Bounded experiment and reason |
| --- | --- | --- |
|1|10a, remaining06/08|Thumb calls/returns, fetch/decode bubbles, earlier safe direct branches and late operand pickup. The JPEG routine is call/stack/load heavy; current measured empty operand queue is21565/107047clocks. Classify actual gaps before changing FIFO depth or predictor size |
|2|Remaining07/12b|The admission-edge pre-read is reused; audit other redundant short-hit/tag waits. JPEG still spends39389clocks waiting for data. Keep synchronous BRAM and precise fault capture; a full overlapped hit pipeline belongs to the heavier work below |
|3|09a/09b|First setup and eligible final base writeback are fused; consider remaining list/count and last-word/load-PC costs. Retain one ordered memory owner and precise per-beat abort/base restoration |
|4|04a/04b|Improve MUL/MLA/long-multiply DSP mapping, schedule and reuse of full products. Matrix profiles show meaningful multiply occupancy; JPEG bitmap diffusion shows none |
|5|05a/05b|Smaller shared ARMv4T ALU/flags and rotate/mask/carry logic. Primarily timing/area unless a measured shift/dependency wait disappears; ordinary dependent unshifted ADD is already one per clock |
|6|Remaining08|Other formatted load classes and consumer-specific bypass. Keep earlier/late producers ordered. Byte loads are uncommon in the measured JPEG block, so do not assume this is its largest remaining gain |
|7|09c|Avoid unnecessary serialization for safe PSR operations and CP15 reads; retain full fences for mode/MMU/cache changes and older fault-capable work. Flags-only MSR already avoids resync; the measured JPEG converter has zero PSR/CP15 operations. Whole OS/codec costs are unmeasured |
|Optional|12a/12c|Improve existing write-buffer organization and separately test cache size/associativity/banking. Extra BRAM is allowed; change geometry only if misses/ports justify it. Warm measured JPEG windows make no external requests, so larger capacity is not a demonstrated solution there |

02a/02c and remaining02b still require their explicit correctness audit:
Thumb BL prefix/suffix architectural LR and IRQ/FIQ boundaries; PSR masks;
invalid encodings; long-multiply flags; block-abort bank/base restoration; privilege.
Some cases already have our fixes. Reproduce, then mark each imported, already
present or inapplicable. These are not promised performance optimizations.

## The heavier work, still open

- Full10b speculative RAS checkpoint/rollback and recovery.
-11a critical-word-first/early load restart with partial-line validity and
  correct later-error behavior. Current streaming fills do not implement this.
-11b hit-under-fill/background miss handling, extra owned outstanding requests,
  precise ordered faults/side effects, and useful work during global miss holds.
- Fully overlapped cache tag/compare/data stages with capacity/owner credits;
  the current F1/F2 overlaps are limited steps toward this.
-13: donor ARM9V2 execution replacement, adapted to our ARM920T identity,
  cache/MMU/CP15/exception interfaces and benchmarked separately.
-14: native phone/game and cumulative fit/timing qualification. A full CPU
  replacement is an option after the smaller measured changes, not a prerequisite.

Latest block-transfer contract: [block-transfer-sequencing.md](block-transfer-sequencing.md).

Previous cache contract and measurements: [cache-admission-probe.md](cache-admission-probe.md).

Previous Thumb contract and measured witness: [thumb-prediction-address.md](thumb-prediction-address.md).

## Previous stage-removal contract and evidence

P0 was described as a tag-RAM delay, but actual TLB checks and data pre-reads
use registered P1. P0 only delayed the complete ALU packet. Its27outputs now
alias their ALU inputs, including address alignment, flags, load format, store
payload, exceptions and trace/uop metadata. Existing registered P1/P2 and the
owned completion remain. The old P0 names are compatibility aliases, not a
second owner. No ACK-to-global-advance path or extra outstanding demand is added.

Removing this copy does not concatenate two combinational compute stages:
P1 captures the same ALU-derived expressions that P0 previously captured.
P1 retains reset, writeback cancellation and older-data-fault sleep handling.
No new state/RAM/DSP/stage/clock setting.708declared FF bits disappear, including
513trace-only bits;195other declared bits are removed. Actual fitted savings
are unmeasured because constants/unused outputs may already have been optimized.

| Work | Before | Stage removed |
| --- | ---: | ---: |
|32dependent LDR/ADD iterations|259|227|
|128loads, four-register stream|235|203|
|Original JPEG8×8mode10 block|117970|113957|
|Six-kernel original index0:0 /2:9|225.1646 /189.3816|228.5393 /192.2189|

JPEG's measured data-wait count stays41008; load-dependency clocks fall
16851→13161. The change removes execution latency, not cache miss service time.
Full-frame fill barely changes71269→71264/201314→201307; fill8-tail regresses
2624→2628. The overall suite gain is not a claim every case improves.

Qualification:92architectural runs (including WFI/wakeup, alignment, privilege,
MMU, LDM, SWP and aborts);44IRQ/FIQ edge cases; full six-kernel12groups/two exact
repeats/six wrong-output controls; four JPEG cases/both waits/two exact repeats,
8unprofiled counter matches and8wrong object/pixel controls.83pristine upstream
hashes and37reconstructed lexical streams pass for patch0068. Preexisting source
formatting/comment drift means no strict byte reconstruction claim. Final core
is byte-identical to the full six-kernel frozen source. JPEG prototype differs
only in one comment; no six-kernel post-change occupancy profile was run.

Raw outputs remain under `build/sim/p0-trim-cpu-20261115/`,
`build/sim/spmark-payload/p0-trim-20261115/`,
`build/sim/jpeg-payload/p0-trim-prototype-20261115/` and
`scratch/cpu-postalu-trim-20261115/`. Two initial fixture errors (port-count
assertion and host/container absolute path) failed before RTL execution and
are retained. Other simulations and checkpoints were untouched.
[Qualification and counters](evidence/cpu-postalu-trim-20261116.json).
