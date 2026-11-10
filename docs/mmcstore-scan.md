# mmcstore startup scan, 2026-11-10

Hardware must reach UI within 20 seconds; an observed hour without UI is an
unresolved failure. These replay results establish local progress, not full boot.

## ARM920T64-entry replacement

The cache is now the production-only implementation and the split ZAP TLB
banks have been replaced with mixed-size64-entry associative I/D tables.
[Architecture and verification](arm920-tlb.md) describe the CP15 and pipeline
contracts. The final corrected source completed the full50M comparison:

|50M clocks from the same quiescent state|Prior handshake-only8877|ARM920T64-entry2753|
|---|---:|---:|
|Complete reads|3748|4484|
|Median clocks/read|11430|9512|
|Min / max clocks/read|11300 /33835|9389 /30618|
|Unique scan entries|3748|4484|
|Repeated / backwards positions|0 /0|0 /0|
|Block exits|8|9|
|Bus errors at end (unchanged)|12|12|
|Data faults|0|0|

Throughput increases19.64%; median latency falls16.78%. Main-table lookups:
1,225,255D /769,505I, with only33D /24I actual walks. Remaining token churn and
CPU/cache load/store latency dominate; changing C: backing transfers is not the
next large opportunity. A bounded comparison matches56 C-bus address/data pairs.
The terminal fetch address0 had instr_valid=0, last trace503393F8; it was an
inactive frontend sample. Restoring the saved pair and running another100k
clocks completes7 more reads with no new faults or repeated positions.

The full final CPU suite passes177 checks with no XFAIL. The initial candidate
0238 had the same scan result but failed translated-prefetch restoration in a
CPU test. Its result is retained as a failed intermediate, not relabeled as final
proof. Corrected2753 was rebuilt, cold-booted50M and benchmarked50M independently.
[Machine-readable final evidence](evidence/tlb64-2026-11-10.json).

Both arms start from a quiescent diagnostic copy at2,000,000,027, advanced27
clocks from the earlier audited2B copy using frozen8877. No CPU/cache/walker
or external-bus transaction is outstanding. The explicit migration preserves
CPU/cache/memory state and imports20valid D/19I mappings, including AP/domain/
C/B, into the new tables. There are no overlapping imported mappings. New local
permission tokens start invalid; RR starts after the imported entries. Serialized
cache names map experimental_cache -> cache_adapter. Whitelists, field audit,
source/target hashes and import records live in scratch/tlb64/scan-final.migration.json.
Original checkpoints, firmware and C: input files remain untouched. Both runs
keep the prior78MHz/timers26MHz/NOS64/ROM64bit1KiB/direct-SDRAM configuration.
The final observer saves a terminal diagnostic pair; its host scanout is not
updated and it is not a maintained runner lineage. The cold50M run saves normal
checkpoints/screens under build/sim/runs and build/sim/screens.

## Implemented fix: completed50M comparison

Ownership/recovery is now implemented in zap_tlb and its I/D wrappers; see
[cpu-patches.md](cpu-patches.md) for the stage contract. Both arms use the same
stock firmware/C inputs,78MHz CPU,26MHz timers, experimental NOS64,64bit1KiB ROM
buffer and direct SDRAM route. No overlays or frequency changes between arms.

| Checkpoint2B +50M clocks | Before (65ea) | Fixed (8877) |
| --- | ---: | ---: |
| Complete one-byte read calls | 2626 | 3748 |
| Median read latency, clocks | 16165 | 11430 |
| Minimum / maximum latency | 15965 / 40852 | 11300 / 33835 |
| Unique metadata records | 2626 | 3748 |
| Repeats / backwards positions | 0 / 0 | 0 / 0 |
| Scan block exits | 6 | 8 |
| Bus errors at end (unchanged from start) | 12 | 12 |
| Data faults | 0 | 0 |

This is42.73% greater completed-read throughput and29.29% lower median read
latency. The first40 C-bus address/data pairs match exactly in an additional
bounded comparison. More work is completed; the improvement does not come from
skipping scan entries. A separate2M fixed-model residency probe completes151
reads:7006 data walks, only1 resident (inherited old in-flight walk at restore,
conservatively discarded);5936 instruction walks,0 resident. Remaining real
misses/direct-map conflicts and kernel work are separate optimization targets.
The new busy signal also includes lookup recovery, so its aggregate busy clocks
cannot be compared directly to old walk-only busy clocks.

The source2B CPU/host pair is unchanged. The fixed arm uses an explicitly audited
named-field migration COPY, preserving17709 common fields and byte-identical
host state; new recovery state is initialized conservatively. Four new I-TLB
forwarding buffer registers recover old optimized aliases. Generated combinational
scratch is recalculated. Exact whitelists, hashes and alias recovery are in
`scratch/mmu-handshake/scan-2b.migration.json`. This is a diagnostic comparison,
not arbitrary checkpoint compatibility or cold-boot equivalence.

A separate cold reset with the fixed executable completed50M clocks at00006154,
with the same12 known early bus faults and0 data faults. It remains in the known
pre-LCD boot loop: no logo/UI completion is claimed at50M. Maintained checkpoint
pair/results/screens: `build/sim/runs/mmu-owner-cold-50m/` and
`build/sim/screens/mmu-owner-cold-50m/`. The drive-scan observer itself does not
save a maintained terminal checkpoint.

Focused lookup-ownership tests pass; original policy fails the warm translation
control (4 table reads instead of2). CPU timing keeps warm ADD at1clock for
memory delays0/3. Regression has38 PASS lines before the pre-existing
fiq_store_return D1 failure, and132 PASS lines in the separately completed
suffix, including prefetch, SWP, MMU/cache ordering and maintenance; the legacy
direct-map associativity control retains its expected XFAIL. The full suite is
therefore not all-passing. Upstream-relative patch verification passes.

All RAM/check stages remain registered.104MHz timing closure requires a future
Quartus report; no hardware build was launched. Original long sims and firmware/
C input files were untouched. [Measured evidence](evidence/mmu-handshake-2026-11-10.json)
records profiles, source models, limits and input hashes.

## Follow-up: redundant MMU walks dominate device access

An isolated, observer-only replay of reduced checkpoint2B through2.002B
completed105 reads (106 started), with105 unique records and no backwards or
repeated scan positions. Median one-byte call remains16165 clocks. Original
firmware, C: source image and running long simulations were not changed.

| Complete-read attribution | Clocks / count | Share of read-call clocks |
| --- | ---: | ---: |
| Total | 1,724,159 | 100% |
| C: backing bus pending | 8,832 | 0.51% |
| D-TLB busy | 581,177 | 33.71% |
| I-TLB busy | 272,846 | 15.82% |
| Walk intervals starting with a resident small-page translation, I/D union | 624,262 | 36.21% |
| Accepted D-cache requests | 47,087 / 105 reads | 448.45 requests/read |

Busy and walk categories overlap; do not add them. The union includes walker
setup/completion states, rather than just bus-pending clocks. Its36.21% is
occupied time, not a measured speedup or a promise that all of it is recoverable.
No cache maintenance, TLB invalidation or TTBR changes occur in this window.

Over the full2M sample,36,627 D-side walks start;31,696 (86.54%) already have
a matching valid small-page entry in the actual TLB RAM. I-side:10,682 of16,002
(66.75%). This tests stored tag+valid at the walk address; it does not infer
residency from a software shadow alone. Direct-map conflicts also exist, but
cannot explain walks for translations that are still resident. D-side refill
writes were not suppressed by hold; that alternative was checked and rejected.

Concrete example at cycle2,000,000,000: current data request80601868 has a
resident translation; lookup/check pipeline instead contains00010000 and a
registered miss. `zap_tlb_fsm` captures the current request address and starts
a walk using that earlier lookup's miss. In `zap_tlb.sv`, the checker uses
`i_address_check`, RAM lookups use `i_address_nxt`, while the walker captures
`i_address`. Walk admission uses only `i_idle` and `walk`; it does not qualify
the result's address ownership. The associative D-cache wrapper already checks
lookup ownership before accepting a translated data request, but the walker
can run earlier and waste two external table reads. Instruction-side lookup
ownership needs separate review; do not simply reuse the data-side pending
request logic there.

A small standalone full-TLB test reproduces this without any Nokia firmware:
warm80601000, advance lookup/check to a different address while current request
stays, then permit walker admission. Existing RTL issues redundant table reads
(4 beats during warm-up,24 after the stale lookup interval). Source/log:
`scratch/startup-fault-audit/tlb-stale-lookup.sv` / `tlb-stale-test.log`.
The bus model registers next-cycle requests as the enclosing ZAP cache does.
This is a mechanism reproducer, not a new passing performance regression.

Address qualification alone still repeats the genuine miss (warm-up4 beats,
final8 instead of6); retain `tlb-qualified-test.log` as a failed approach.

A scratch-only address-ownership gate plus three enabled lookup-settle clocks
following installation passes this focused case: initial warm-up2 table beats,
no redundant reads during the stale interval, then exactly2 beats for a genuine
new small-page miss. It retains the existing RAM/check pipeline. Source/log:
`zap_tlb-qualified-settle-prototype.sv` / `tlb-qualified-settle-test.log` under
`scratch/startup-fault-audit/`. This does not validate permission/context changes,
held lookups, fault/completion ownership, prefetch or full-CPU boot. Do not apply
it to the phone merely because the local test passes.

Next implementation target: qualify walker admission with aligned lookup VA,
current request VA and translation context, preserving registered pipeline
boundaries. Gate faults/completion consistently too: suppressing walks while
letting a caller consume a stale physical address would be unsafe. Preserve
real misses, permission faults, invalidations, TTBR/context changes, explicit
CP15 instruction prefetch and held requests. The scratch prototype is not a
production fix. Before adoption, add directed ownership/cancellation tests,
run relevant CPU/MMU regressions and an isolated firmware comparison of at
least50M clocks. Do not migrate or modify original long-sim checkpoints.

Increasing the drive buffer is not the priority indicated by this sample.
Even eliminating C: backing bus time entirely would remove only0.51% of these
read-call clocks. Hundreds of firmware/kernel data accesses per byte and genuine
TLB conflicts remain separate costs after redundant walks are fixed.

Machine-readable evidence: [drive-scan-tlb-2026-11-10.json](evidence/drive-scan-tlb-2026-11-10.json).
Local observer source/log: `scratch/startup-fault-audit/scan-tlb-cost.cpp` and
`scan-tlb-cost.log`, linked against exact frozen model65ea564947bfe4e4.
Returned table beats are qualified by the FSM's registered fetch-wait states;
next-cycle CYC/STB fall combinationally on ACK, so qualifying ACK with those
next outputs incorrectly counts zero beats. Simulation backing latency is not
a measured physical MiSTer DDR latency.

## Earlier scan and timer comparison

| Measurement | Original, 4B + 5M clocks | Reduced, 2B + 20M clocks |
| --- | ---: | ---: |
| Unique scan entries | 20 | 1050 |
| Repeated entries | 0 | 0 |
| Block exits | 0 | 2 |
| Complete synchronous reads | 19 | 1050 |
| Median read clocks | 174936 | 16165 |
| IRQ/NOS share of complete-read time | 71.34% | 0.45% |
| C backing bus share of complete-read time | 0.033% | 0.494% |

The reduced trace exits block34 at 2,003,325,299; enters block33 at
2,003,341,311; exits block33 at 2,012,582,179; enters block32 at
2,012,598,008. Each full block has up to486 metadata records, offset0x30
through bound0x3558 in increments28. Uniqueness keys include block number,
not just a reusable node address. A complete observed block takes9,240,868
clocks. No evidence here of a permanently stuck individual read or block scan.
A later repeated complete scan or a later startup wait remains possible.

StartupThread80409884 is waiting in RFile::Open for the firmware literal
c:\system\mmcstore (F32 function27); FileServer Main services ELocal /
RBusLocalDrive reads. Snapshots contain EKern and EFile, no UI process yet.
The original final C read position is0x00302a14 (block48); reduced2B is already
at block34. Original3B and4B were at blocks59 and51. This is progress, not UI.

Attribution uses IRQ mode and last writeback PC code regions; it is not a
perfect call-stack profile. Stall categories are exclusive; do not sum them
with overlapping PC-region attribution. Raw C timing is a simulation backing
model, not a physical DDR latency measurement. ROM buffering, direct SDRAM and
clock changes differ between builds, so the speedup cannot be assigned to NOS.

NOS counter frequency remains a hypothesis. Changing it to64Hz changes firmware
deadline units and the ADSP staged tick, not merely interrupt frequency. The
separately supported26MHz general timer /64Hz OS tick does not prove that the
NOS comparator should also be64Hz. See phone-clocks.md.

Evidence kept locally: scratch/metadata-scan-audit/original.log,
reduced-final.log, original-final.json and restore-check.log. Sources original.cpp
and reduced.cpp instrument frozen models without firmware/C edits. The invalid
overlapping replay log is excluded. Original final checkpoint at4,433,931,411
restores byte-identically with its exact binary; only reduced long run continues.

Next: observe the whole open return/restart and process creation, establish NOS
counter units, and compare a fresh hardware PC/fault capture. Screenshot API
was unreachable during this audit. Do not treat waiting to12B as a solution to
the hardware20-second requirement.
