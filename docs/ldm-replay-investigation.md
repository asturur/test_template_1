# Cold-cache LDM replay: focused wait/forward experiment

## 2026-10-28 section translation timing

The bounded trace in `build/sim/runs/cache-divergence-trace/` identified the
V7 checksum failure: VA 0x00100120 was accepted as PA 0x00000120; the next
cycle produced the correct PA 0x00100120. At t=56574983 request identity and
cache index matched, but the registered TLB output still reflected the previous
section; request identity alone was one cycle too early. The bus then returned
0xe59f105c instead of the expected 0xf001a88d.

Scratch V13 delays acceptance until the matching lookup is observed on two
consecutive cycles during an outstanding request; its previous-match flag is
cleared on acknowledgement. `scratch/ldm-tlb-handshake-tests/run-v13.py`
passed 70 cases, and `build/sim/runs/md5-sweep-v13-1048576/result.json` reports
pass at 29,784,745 cycles. V11 and V12 also passed this checksum; V13 adds
the pending-request and acknowledgement guards. This is a conservative timing
experiment, not proof that every TLB/cache pipeline transition is correct.
Reiterate with back-to-back different request contexts, translation faults,
interrupts, reset, and synthesis/resource checks before production promotion.
A 2 MiB MD5 test failed V13 with completion 0x31 at cycle 58,453,970,
while the seven-patch baseline passed the same ROM and expected digest at
cycle 31,491,248. Compare first divergent block states to isolate the remaining
candidate bug. See `scratch/cache-md5-length-sweep/results-{v13,baseline}-2m.json`.
The V13 full firmware run was stopped because repeated Verilator warnings
produced an unbounded log; details are in `status.md`. It used modified ROM and
provisional devices, so passing it is not proof of an authentic phone boot.

## V14: track the TLB RAM lookup address

V13 fails the 2 MiB checksum at block 16576. At t=60229245 the current
translation is correct; at t=60229247 checked request identity still matches
but PA becomes 0x0000c020, and that wrong value is latched. The section TLB tag
omits index bits, so matching the checked VA does not prove the RAM output is
for that index. The pipeline needs to track the lookup address itself.

In scratch V14, two address pipeline stages track TLB RAM lookup, with the
checked lookup registered alongside the translation. The pending request can
only accept a matching checked lookup. It passed 70 directed tests across
five latencies and the previously failing 2 MiB firmware MD5 test, plus a
4 MiB checksum crossing additional sections. This is
experimental: validate pipeline timing across hold, invalidation, page sizes,
faults, back-to-back contexts and real firmware before production promotion.
The ongoing full firmware test and current resume information are recorded in `status.md`.

## V14 firmware first late data abort

The bounded replay `build/sim/runs/boot-cache-abort-probe/` stopped at cycle
724,314,325 on data abort PC 0x503a2760, loading a byte through R1. At cycle
724,314,246 PC 0x503218e4 loads R1 from literal VA 0x50321938, then calls
through 0x503453e8; the function at 0x503a275c reads R1=0xffff0031 and its
next byte load aborts. The literal is 0x50346070 in both firmware images,
and at cycles 724,312,981–988 the cache fill fetched the corresponding PA
0x00321938 as 0x50346070. R1=0xffff0031 is observed by the later MOV, not
just the potentially stale value shown at asynchronous load retirement.
The bad access walks L1 entry 0x0a077ffc, which is zero. The immediately
preceding adjacent literal loads at 0x50321930 and 0x50321934 supplied
0x50346050 and 0x50346060 correctly. The exact corruption mechanism remains
unproven; distinguish tag/data pipeline alignment, refill/eviction, and
register completion with a focused short reproducer. The earlier LDM abort
at PC 0x503313c8 was a different execution path; do not conflate them.

## V15: background store acknowledges an unrelated load

The focused `scratch/literal-cache-probe/dependent-push.S` executes PUSH
{r4,lr}, a PC-relative load into r4, and a dependent MOV. Baseline passes at
latencies 0/3/7 while V14 fails 0x63; a plain stack adjustment instead of PUSH
passes both. The original-firmware routine `firmware.S` also fails V14 0x62
and passes baseline at 0/3/7. V15 passes both tests at 0/3/7/15/31.

At t=172629 in `build/sim/runs/literal-cache-trace/simulator.log`, the
background store is finishing in UNLOCK_REG while the current pending request
is the unrelated load at 0x5032192c; its translation has not completed. The
store branch unconditionally sets o_ack=1, overriding the pending request's
wait, so the CPU consumes zero without the literal cache line being fetched.
V15 removes that unconditional acknowledgement. All 70 prior directed checks,
the 2 MiB, 4 MiB and 8 MiB checksums, and IRQ/FIQ/reset-during-refill probes at latencies 0/3/7
pass. Review the inherited `zap_hit_under_miss` macro separately: it checks
`!i_cache_en`, and does not explicitly gate on translation or alignment wait.
Its reachability and semantics during cache disable are unproven; this is an
audit item, not a demonstrated V15 fault. The full firmware run will determine whether this
fix also resolves the later R1 corruption; that connection remains unproven.

## Result

The isolated `scratch/ldm-wait-probe/` candidate passes the original cold-cache
reproducer and load-width diagnostic at memory latencies 0 and 3, plus fourteen
other focused checks. It **is rejected as a general CPU fix**: moving the same
LDM to cross a 32-byte cache-line boundary fails at both latencies (completion
`0x22`, wrong LR). No production patch, pinned vendor source or firmware was
changed. No firmware run or authentic cache-enabled boot is claimed.

## Confirmed cause and additional timing trap

The retained cycle trace `build/sim/runs/ldm-replay-cycle-trace/simulator.log`
shows a first LDM load at t=173585 acknowledged with no error and the second
load at t=173587 acknowledged with err2. Pipeline clear follows at t=173589.
The asynchronous port writes r5=4 at t=173605. Replay at t=173671 starts from
base 4. ZAP commits a micro-op asynchronously but restarts the complete ARM
instruction; the predecode MOV recopies the now changed architectural base.
A retry must preserve the instruction's original base and committed progress,
or avoid this whole-instruction replay while a multi-transfer is in progress.

The RAM primitives gate writes and their three read stages with `i_clken`, and
`zap_dcache.sv` feeds them `hold || i_stall`. Correction: in this project
`zap_top.sv` connects data-cache `i_stall` to zero, so a CPU data stall does
not itself gate these RAM writes. The cache FSM can assert its separate `hold`
on other paths. Previous prototype failures are not proven to be discarded
refill writes; see the new trace below.

## Isolated experiments

1. Keep original first-miss acknowledgement, register lock and asynchronous
   completion. In CLEAN_SINGLE, FETCH_SINGLE and UNLOCK_REG replace the
   non-hit `ack=1, err2=1` response with `ack=0, err2=0`. Smoke passes; cold
   LDM keeps r5 correct but fails LR (`0x22`) at both timings. This isolates
   whole-instruction replay from correct stalled-request/cache completion.
2. In UNLOCK_REG forward the completed line to a pending same-line load, and
   present refill tag/data writes again on the release edge. Cold LDM and
   load-widths pass both timings. Warm smallpage fails `0x22` at latency 0:
   UNLOCK of an already acknowledged store mistakenly acknowledges a pending
   second store. Latency 3 passes.
3. Keep pending stores unacknowledged unless accepted explicitly. Same-line
   pending stores merge their byte enables/data into the completed line and
   mark it dirty. All eighteen focused checks below pass. The cross-line
   control still fails both timings. The candidate has no demonstrated correct
   mechanism to commit a refill while a different-line request remains stalled.
   It is a diagnostic proof of the same-line sequence, not an acceptable fix.

The final runner is `scratch/ldm-wait-probe/run.py`, with source diff
`candidate.patch`, results `results-focused.json` and `results-crossline.json`.
`run-v1.py` retains step 2. `crossline.S` changes only the two virtual/physical
base constants in the original reproducer from c4 to dc, making word two e0.
`crossline.py` expects failure explicitly; its printed PASS means the
**expected diagnostic failure**, not successful architectural execution.
All builds use existing `jotego/simulator:arm64`, without Quartus. Result JSON
files contain simulator input/binary hashes and source provenance.

## Exact final results

| Case | Latency | Status | Cycles | Completion |
| --- | ---: | --- | ---: | --- |
| `smoke` | 0 | pass | 290 | `0x50415353` |
| `smoke` | 3 | pass | 421 | `0x50415353` |
| `ldm_base_coldcache` | 0 | pass | 86,945 | `0x50415353` |
| `ldm_base_coldcache` | 3 | pass | 119,998 | `0x50415353` |
| `ldm_base_smallpage` | 0 | pass | 86,842 | `0x50415353` |
| `ldm_base_smallpage` | 3 | pass | 119,860 | `0x50415353` |
| `cache_load_widths` | 0 | pass | 88,791 | `0x50415353` |
| `cache_load_widths` | 3 | pass | 121,963 | `0x50415353` |
| `ldm_cold_base_last` | 0 | pass | 86,945 | `0x50415353` |
| `ldm_cold_base_last` | 3 | pass | 119,998 | `0x50415353` |
| `ldm_cold_base_not_loaded` | 0 | pass | 86,945 | `0x50415353` |
| `ldm_cold_base_not_loaded` | 3 | pass | 119,998 | `0x50415353` |
| `ldm_base_in_list` | 0 | pass | 95 | `0x50415353` |
| `ldm_base_in_list` | 3 | pass | 136 | `0x50415353` |
| `ldm_base_mmu` | 0 | pass | 86,835 | `0x50415353` |
| `ldm_base_mmu` | 3 | pass | 119,872 | `0x50415353` |
| `ldm_base_undmode` | 0 | pass | 86,890 | `0x50415353` |
| `ldm_base_undmode` | 3 | pass | 119,924 | `0x50415353` |
| `crossline` | 0 | diagnostic_failure | 86,863 | `0x22` |
| `crossline` | 3 | diagnostic_failure | 119,891 | `0x22` |

## Concrete next step

Do not promote the forwarding patch. Design a request/completion boundary that
separates CPU backpressure from refill RAM writes and preserves the alignment
of all three cache read stages and TLB state. Alternatively retain a complete
LDM/STM instruction replay checkpoint (base and committed micro-op progress),
including interrupt/abort cancellation semantics. Start with the failing
cross-line control and a focused trace of current VA/PA, saved refill VA/PA,
RAM write/read enables, cache tag/data/valid, and translation hold. Require both
same-line and cross-line loads/stores, base positions, abort/interrupt boundaries
and latency0/3 before upstream regression/lint or firmware. Interrupts, aborts,
STM/writeback ordering and general eviction behavior remain unverified here.


## Follow-up: cache-line and page-crossing controls

A trace of the Sol candidate in `build/sim/runs/ldm-crossline-trace-latency0/`
shows a pending VA `0x400000e0` initially translated to `0x800000e0`, then
TLB output changes to unrelated `0x00000004` while the request is held. On
release it can read the wrong physical address. An experimental translation
latch in `scratch/ldm-translation-hold-zap/` preserves the PA, but still fails:
the cached tag/data output corresponds to the previous cache index, producing
a false hit. `scratch/ldm-translation-trace-zap/` records that sequence.

An UNSAFE diagnostic (`scratch/ldm-translation-forcemiss-zap/`) forces a miss
for every held request; it passes the original and cross-line tests, but loses
a dirty line in the directed test below. Never promote it. A better diagnostic
(`scratch/ldm-lookup-align-zap/`) additionally points the RAM's lookahead at
the held VA instead of forcing a miss. It passes the prior focused cases, the
cross-line test at latencies 0/3, 24 additional MMU/alignment/fault checks,
and the following directed test at both latencies:

- `scratch/ldm-dirty-crossline/test.S`: dirty another virtual tag at the next
  line's cache index; verify the load and the victim's writeback through an
  uncacheable physical alias. Lookup alignment passes; force-miss fails `0x23`.

The lookup-alignment candidate is still **not a fix**.
`scratch/ldm-page-crossline/test.S` crosses from virtual `0x40000ffc` into a
noncontiguous mapped page at `0x40001000`; at both latencies it attempts an
unmapped physical read `0x40001000`. The warm-page control `warm.S` passes.
`build/sim/runs/ldm-page-trace-latency0/simulator.log` (`PAGE` lines) shows
the first held cycle presents raw PA `0x40001000`, cacheable=0 and busy=0;
the prototype incorrectly latches this as a valid translation. In
`zap_tlb_fsm.sv`, `o_busy` alone is insufficient: the page-table walk is gated
by cache `i_idle`, so while the first refill runs, busy=0 does not prove a
translation exists for the pending access. The next design must preserve the
request and explicitly coordinate TLB lookup/walk readiness with cache
backpressure, without assuming busy=0 means valid. Validate real page faults,
permissions, cancellation, dirty evictions and cross-page reads/writes.
All code and results are isolated under `scratch/` and `build/sim/runs/`;
production/vendor RTL is unchanged.


## TLB handshake prototype v2

`scratch/ldm-tlb-handshake-v2-zap/` preserves the pending request only during
a background refill, exposes the TLB walk request, redirects cache/TLB lookups
to the pending VA, and waits for an idle, non-walking TLB before capturing
translation. It uses a provisional four-cycle lookup-settling counter; that
constant, signal alignment, faults, cancellation, and parameter variations need
review before promotion. Its predecessor applied the handshake to ordinary
uncached stalls and failed early; `scratch/ldm-tlb-handshake-zap/` is rejected.

The v2 scratch candidate passes cold and warm page crossing, cross-page LDM
translation fault with FAR check, cross-page STM readback, dirty victim
writeback, original cold LDM, crossing, and load-width checks at latency 0/3.
All 19 additional existing ARM/MMU/fault cases pass at both latencies. The
page, page-fault, store, dirty-victim and width cases also pass at latency
7, 15 and 31. `build/sim/runs/ldm-tlb-handshake-v2-*/` retains results; source
and directed-test hashes are in the scratch source manifest. This is a promising
probe, **not an approved CPU fix**; IRQ/FIQ timing, second-access permission
faults, independent oracle comparison, cache operations, dirty conflicts,
writeback modes, parameterized RAM/TLB timing and synthesis remain open. The
original ZAP regressions were started separately; see the status checkpoint
for their final result. No firmware boot with this candidate is claimed.


## Review findings and v3 guarded forwarding

Sol reviewed v2 and identified two separate access-check bypasses on same-line
UNLOCK forwarding. `scratch/ldm-permission-forward/test.S` confirms that v2
accepts a user-mode write to an AP=2 read-only page after a permitted cold read;
it fails with `0x31` at latency 0/3/7. A separate aligned-read then unaligned
read test `scratch/ldm-alignment-forward/test.S` confirms v2 bypasses alignment
at latency 0/3. The first alignment-test draft itself was invalid because the
first read was denied; its corrected version uses permitted supervisor access.

`scratch/ldm-tlb-handshake-v3-zap/` guards same-line forwarding against both
pending translation and alignment fault. Both tests pass at 0/3; the complete
`scratch/ldm-tlb-handshake-tests/run-v3.py` suite passes 55 cases at latencies
0/3/7/15/31. Original ZAP `mode32_test`, `mode16_test_onlycore` (seed 1) and
synthesis-path Verilator lint pass; only-core Thumb does not exercise D-cache.
Results are `build/sim/tlb-v3-recheck-*` and
`build/sim/tlb-handshake-v3-upstream/`.

`scratch/ldm-irq-refill/` injects a synthetic IRQ on the first data fill, holds
it until the IRQ handler writes an acknowledgement, checks LDM results and
handler execution; passes latencies 0/3/7. This shows a level asserted during
refill is handled after LDM; it does not prove mid-instruction cancellation
or all IRQ/FIQ timing. An initial 20-cycle IRQ pulse expired before acceptance
at slower latencies and is not a valid level-interrupt test.

Review still requires replacing or proving the four-cycle counter: it counts
cycles, not actual TLB lookup advances or request identity, and pending VA,
access type and privilege/context stability are not enforced. Verify CPU flush
and cancellation, CP15 invalidation, uncacheable and faulting operations,
independent oracle comparison, STM/writeback, and differing TLB/cache
parameters. This is scratch RTL only, not a production patch. The experimental
full firmware run is described in [status.md](status.md).


## V4 request stability and interrupts

`scratch/ldm-tlb-handshake-v4-zap/` extends v3 by advancing the provisional
settling counter only when the TLB/cache lookup is clock-enabled, and asserts
that the pending VA, read/write direction and CPSR mode remain stable while
stalled. These are simulation checks, not a complete request-valid protocol;
the counter, CP15 context and cancellation still require a design proof.
`scratch/ldm-tlb-handshake-tests/run-v4.py` passes 55 directed checks at
latencies 0/3/7/15/31; 18 additional MMU/fault cases pass at 0/3. Original
ARM and only-core Thumb benches plus synthesis-path lint also pass. The
corrected unaligned load AND store reproducers fail v2 (completion 0x31) and
pass v3/v4 at both timings. The user-mode read-only page store test fails v2
and passes v3/v4. See `build/sim/runs/tlb-*` and
`build/sim/tlb-handshake-v4-upstream/`.

Synthetic level IRQ during refill, acknowledged by the handler, passes on v4
at latencies 0/3/7/15/31; a separate level FIQ version passes at 0/3/7. Both
are accepted after the LDM rather than proving mid-instruction cancellation;
see `scratch/ldm-irq-refill/` and `scratch/ldm-fiq-refill/`. Neither validates
real Nokia interrupt timing. V4 is not used by the currently running firmware
experiment: that uses unchanged v3 scratch inputs.


The v3 firmware run's flushed data-bus prefix matched the previous cache-disabled
baseline byte for byte through cycle 119,630,382. The baseline's next 10 KB of
bus records extends to approximately cycle 428,789,993, explaining a long period
with no newly flushed output. The short independent two-million-cycle run retired
instructions and stopped at its limit; it does not establish later progress.
The permission test was extended to check that the denied store leaves the
cached value unchanged; v3/v4 pass at 0/3.


## Cache-enabled firmware test: integrity failure

The full v3 cache-enabled run finished (`firmware_loop`, cycle 398,990,758)
in the same comparison-failure self-loop `0x50003290` described in
[firmware-integrity.md](firmware-integrity.md). The derived test image expects
`1784c17a6fd17b0841226546434db048` at ROM file offset 0x8f20; firmware writes
its computed digest `f92e2e386422faeaeedde006063cd464` to physical scratch
`0x0c004748..0x0c004757`, then compares first byte 0xf9 with 0x17 and enters
the failure loop. Compare uses a cached byte load; the retired trace initially
prints a stale register value, so use the final CMP result and memory trace,
not the LDR retirement annotation alone. The prior cache-disabled FPGA and
Python independently agree on `1784...` for the ROM range. The image remains
a digest-modified input with synthetic extension and assumed board devices;
we have not identified which CPU/cache behavior or other cause produced the
new digest. No cache-enabled full boot has been demonstrated.

Outputs and source hashes: `build/sim/runs/boot-cache-candidate-v3/`; screen
`build/sim/screens/boot-cache-candidate-v3/screen.png` is only the assumed
white clear at cycle 106,379,209. No simulation is active. Next isolate the
first divergence in the digest computation or streamed reads in a smaller
cache-enabled test, using the old seven-patch and cache-disabled runs as
controls. Do not simply patch the expected digest to this incorrect value.


A separate `scratch/cache-stream-stress/test.S` fills 64 KiB through an
uncacheable RAM alias, then checks every byte through a cacheable section
(exceeding the 16 KiB cache). The existing seven-patch CPU and v3/v4 each pass
at latencies 0 and 3. Results are in `build/sim/runs/cache-stream-*`. This
limits but does not eliminate cache-read causes of the firmware digest mismatch;
the pattern and address mapping are not the firmware MD5 workload.


## MD5 regression isolated: zero initialization constants

The incorrect full-run digest is explained precisely by an all-zero MD5 initial
state: independent OpenSSL MD5, overriding only A/B/C/D to zero, computes
`f92e2e386422faeaeedde006063cd464` over the original `[0x9000,0x11b5000)` ROM
range. Standard OpenSSL agrees with Python hashlib on `1784c17a6fd17b0841226546434db048`.
This is a diagnostic explanation, not an alternate valid expected digest.
The reproducible calculation and original-ROM SHA-256 are saved in
`scratch/md5-short-probe/zero-iv.py` and `zero-iv-results.json`.

A short harness copies unchanged MD5 code/literals from original ROM offsets
`0x3b00..0x6ebf` into their original logical addresses and calls wrapper
`0x5334`, hashing only 64 or 1024 original bytes starting at 0x9000. Stack and
output are cacheable RAM; no board initialization, LCD, timers or boot occurs.
All four seven-patch cases pass, whereas all four v3 cases fail their first
output word (`0x31`):

| Bytes | RTL | Latency 0 cycles | Latency 3 cycles | Result |
| ---: | --- | ---: | ---: | --- |
| 64 | v3 | 94,912 | 130,261 | failure 0x31 |
| 64 | seven-patch | 95,211 | 130,707 | pass |
| 1024 | v3 | 109,031 | 144,756 | failure 0x31 |
| 1024 | seven-patch | 109,525 | 145,547 | pass |

In the 64-byte trace, MD5 initializer LDR at 0x3b0c reads its constant into
r3; the following STR at 0x3b10 writes zero to state+8 under v3, versus
0x67452301 in the seven-patch run. The other initialization constants likewise
become zero. First arithmetic divergence is MOV r0,r9 at 0x3d48: zero versus
0x67452301. The v3 output first word `0xecec4611` matches the independently
computed zero-IV 64-byte digest `1146ececa63de70a18226c22ac00956c`.

A **firmware-independent** reproducer is
`scratch/md5-short-probe/next-load.S`, run by `run-next-load.py`. After normal
MMU/cache setup it loads a ROM constant, stores it to cacheable RAM, reads RAM,
then loads an equal comparison constant via a PC-relative literal. The store
and RAM read are correct; the final literal load returns zero, so CMP fails.
Do not misdiagnose this as a universally stale store operand: replacing the
comparison load with an immediate (`load-store-minimal.S`) passes v3 at both
latencies. Inserting eight NOPs before that final load (`next-load-delayed.S`)
also makes v3 pass. These controls avoid dependence on the MD5 implementation.

| Case | RTL | Latency 0 cycles | Latency 3 cycles | Result |
| --- | --- | ---: | ---: | --- |
| next load | v3 | 86,337 | 119,269 | failure 0x31 |
| next load | seven-patch | 86,364 | 119,308 | pass |
| eight-NOP spacing | v3 | 86,371 | 119,308 | pass |
| eight-NOP spacing | seven-patch | 86,387 | 119,343 | pass |
| immediate comparison | v3 | 86,354 | 119,279 | pass |
| immediate comparison | seven-patch | 86,362 | 119,306 | pass |

The likely remaining mechanism is restoring lookahead after a held request:
v3 redirects cache/TLB lookups to current `i_address` while pending, then
immediately clears `pending_request` on ACK and restores `i_address_nxt`.
The held request can be correct while the following request's tag/data/read
pipeline is out of phase. The spacing control supports a pipeline hazard;
this particular internal mechanism still needs a focused cycle trace and is
not yet proven. Trace the short next-load case around ACK and the final
literal: current/lookahead VA, RAM read-address stages, tag/data/valid outputs,
PA, pending flags and async result. Ensure completion validity covers the
transition back to ordinary requests, not only the stalled request itself.

The initial harness draft had an incorrect RAM section-table offset and
aborted on its first push on both CPUs; that harness error was corrected
before the results above. `results*.json`, simulator run manifests and
`source-manifest.json` retain exact outputs and hashes. Tests used existing
binaries and `jotego/simulator:arm64`; no production RTL or firmware edits and
no long firmware rerun occurred. V4 also fails next-load and both short MD5 tests at latencies 0/3; the delayed and immediate controls pass.


## Lookup resynchronization experiment v5

The focused v4 trace `build/sim/runs/ldm-next-load-trace-latency0/` shows the
held RAM read acknowledged at t=172567, immediately followed by a ROM load at
t=172569 whose VA is 0x124 but TLB output still describes 0x80001000. This
confirms a lookup/translation mismatch at the release edge, not merely an
assumption inferred from instruction spacing.

`scratch/ldm-tlb-resync-v5-zap/` adds an experimental resynchronization on the
next request and prioritizes translation wait over stale translation faults.
`scratch/ldm-tlb-handshake-tests/run-v5.py` passes 60 directed cases at five
timings, including the isolated next-load test. However the unchanged firmware
MD5 harness still fails for both 64 and 1024 bytes at all five timings (10
failures), so v5 is rejected as a complete fix. In the v5 short MD5 trace the
first three initial constants are stored correctly but the fourth remains zero;
`build/sim/runs/ldm-md5-v5-trace-latency0/` captures the transition. Investigate
repeated pending/recovery requests and cache/TLB stage identity before another
firmware run. No production files were modified.


## Identity-based lookup prototype v6/v7

The prior v5 failure trace showed a just-completed held store followed by a ROM
load whose VA was 0x3b3c but whose TLB PA still described 0x800222c4. V6 tags
TLB lookup output with checked VA, direction and translation context; cache
lookup reports its read-pipeline index. It holds a pending request until those
identities match the current request and TLB walk has finished, instead of
waiting a fixed number of cycles. After a held request, it conservatively
validates subsequent requests; the data/tag geometry and inferred RAM remain
unchanged. V7 adds assertions for pending address, direction, write data/byte
enables, load destination/width and MMU context, and removes the obsolete
settling counter. These assertions check while a request stays asserted; they
do not establish all cancellation/flush cases or real hardware timing.

`scratch/ldm-tlb-handshake-tests/run-v7.py` passes 70 cases at latencies
0/3/7/15/31, including the original cold LDM, following load, both unchanged
short firmware MD5 tests, fault/permission, page/line crossings, dirty victim
and store checks. Another 38 existing ARM/MMU/fault tests pass at 0/3. The
64 KiB cacheable stream passes at 0. Original ZAP mode32 and only-core mode16
benches and synthesis-path Verilator lint pass. Synthetic level IRQ at
0/3/7/15/31 and FIQ at 0/3/7 asserted during refill are accepted after LDM;
this does not prove mid-instruction cancellation. No production patch has been
made. A full firmware run is active; see [status.md](status.md). The candidate
serializes subsequent requests after a stall, so performance and 104 MHz FPGA
timing are unproven. Preserve all input hashes and original firmware.


V8 (`scratch/ldm-identity-v8-zap/`) adds reset-aware validity alongside the
TLB result and a three-enabled-cycle validity pipeline for cache lookup index.
It passes the same 70 directed cases at 0/3/7/15/31, including short firmware
MD5 and cold LDM (`scratch/ldm-tlb-handshake-tests/run-v8.py`). It is a separate
scratch candidate, not the V7 firmware run. Another 38 ARM/MMU/fault cases pass at 0/3. Original ZAP ARM and only-core
Thumb benches and synthesis-path lint pass; IRQ at 0/3/7/15/31 and FIQ at
0/3/7 pass, with exceptions taken after LDM. Full firmware and actual synthesis
remain untested on V8, and invalidation/flush/cancellation require further tests.

Additional V7 controls: `scratch/cache-fault-return/test.S` verifies data-abort
return after a denied store and a later successful read (baseline and V7 pass
0/3); `scratch/cache-maintenance-control/` checks dirty clean/invalidate with
and without overlapping fills (baseline and V7 pass 0/3). Details and limits of
CP15 operation coverage are in [cache-maintenance-audit.md](cache-maintenance-audit.md).


Cache/TLB remap control `scratch/cache-remap-control/test.S` passes baseline,
V7 and V8 at latencies 0/3. It verifies remap after the tested operations and
invalidation; it does not prove cancellation during an active lookup.


`scratch/cache-reset-refill/main.cpp` injects a one-time reset during the ROM
line refill at physical 0x3b20, clears the testbench's pending bus request,
and checks the restarted next-load program. V8 passes latencies 0/3/7 and the
runner verifies `REFILL_RESET` is present in each log. An initial draft targeted
a bus address that this test never accessed; its apparent passes are invalid
and retained only as historical outputs (`cache-reset-identity-v8-*`). This is
a synthetic CPU/bus reset test, not proof of arbitrary flush cancellation.


V9 (`scratch/ldm-identity-v9-zap/`) builds on V8 with an additional simulation
assertion that pending address, access direction, write data, byte enables,
load destination/width and translation context still match on the final ACK
cycle. `scratch/ldm-tlb-handshake-tests/run-v9.py` passes all 70 directed
cases at 0/3/7/15/31. V9 also passes 38 extra ARM/MMU/fault cases at 0/3, original ARM and
only-core Thumb benches, and synthesis-path lint. IRQ/FIQ, actual FPGA synthesis
and firmware have not been tested on V9; it does not replace the active V7 run.


V9 also passes the verified reset-during-ROM-refill control at latencies 0/3/7
(`build/sim/runs/cache-reset-trigger-v9-*`). The bus testbench explicitly
discards pending bus traffic on reset; this does not prove arbitrary pipeline
flush or asynchronous bus behavior.


The first full V7 firmware run reached 520,000,000 cycles and stopped at its
limit in the MD5 calculation; the retired trace shows a ROM data pointer around
0x50cf95ac, inside the checked core range. It neither passed nor failed the
digest. It captured the assumed white clear at cycle 106,379,209. User asked
for a new run from reset with a much larger limit, so
`scratch/firmware-cache-candidate/run-v7-long.py` starts the same simulator
with 1,000,000,000 cycles; see `status.md` for live state. This conservative
prototype adds CPU cycles and the host simulation is not real-time. FPGA speed
and timing remain unmeasured. A separate checkpoint experiment was started but
the user chose a fresh full run; do not treat it as the current run.


## Digest workload performance control

`scratch/cache-md5-performance/test.S` invokes the unchanged firmware digest
routine on 32 KiB of original local ROM bytes and compares against an independent
hashlib result. It passes at latency 0 on baseline (780,269 cycles), V7
(1,038,626), and V8 (1,038,626): the candidate takes approximately 33% more
simulated cycles on this workload. Host wall times vary with concurrent Docker
work and are not used as a timing claim. The original phone is not running at
this host simulator's speed; the MiSTer candidate's 104 MHz timing is unmeasured.

A V7 quiet scratch build suppressed only three repetitive TLB informational
messages. It matched the first two million firmware cycles' bus, CP15, and
instruction traces byte-for-byte against the earlier control and passed the
short MD5 and next-load cases at 0/3. Its 32 KiB digest cycle count matched V7;
the short test produced no relevant message volume and measured no speedup.
This does not prove equivalent behavior for the full firmware or justify
replacing the already running V7 test. The warnings and their source should
not be discarded as hardware evidence; full test remains on the original V7.


A first performance experiment, `scratch/ldm-identity-v10-zap/`, removed the
sticky conservative validation path and instead stalled only when the current
lookup identity appeared mismatched. `run-v10.py` passed the simple next-load
case at five timings, but both firmware MD5 controls failed at the first
timings (and the 64-byte case failed at all five). The wider test run was
interrupted once those mandatory gates failed. This variant is rejected;
naive removal of the conservative path is not a safe speed optimization.
Results are in `build/sim/ldm-identity-v10-recheck.log`.


The longer V7 firmware run completed, rather than timing out: at cycle
666,454,237 it entered digest failure loop 0x50003290. It calculated
`2d41ef51bb1576cdb457d0212f8330dd` instead of the expected
`1784c17a6fd17b0841226546434db048`. The retained 32 KiB MD5 control passes,
so investigate workload length, address changes, and cache/TLB eviction using
progressively larger deterministic inputs before another full boot. Full run
output/provenance is `build/sim/runs/boot-cache-identity-v7-long/`; the screen
is the assumed white clear. No simulation is running.


## Longer digest isolation

`scratch/cache-md5-length-sweep/run.py` invokes the unchanged firmware digest
routine with independently computed Python expected results. On V7, 64, 128,
256 and 512 KiB pass; 1 MiB fails the first comparison (completion 0x31).
Baseline seven-patch ZAP passes 1 MiB; V8 fails it. The 1 MiB input begins at
0x9000 and crosses the virtual/physical 1 MiB section boundary; this is an
association, not yet a proven root cause. A direct cached-versus-uncached byte
test crossing that same boundary (`scratch/cache-section-crossing/test.S`)
passes baseline, V7 and V8 at latencies 0/3. A separate 512 KiB digest starting
at virtual 0x50009000 (`scratch/cache-md5-virtual/test.S`) passes V7.

Sweep records and hashes: `scratch/cache-md5-length-sweep/results.json`; runs
`build/sim/runs/md5-sweep-*`, `cache-section-crossing-*` and
`cache-md5-virtual-v7/`. Next bracket the first failing input length around
the 1 MiB section boundary and inspect the digest's block-by-block state or
retirement trace, comparing baseline and candidate. Synthetic ROM mapping
differs from Nokia board flash mapping; no full-firmware result is implied.


## First divergent digest block

`scratch/md5-block-trace/main-blockstate.cpp` captures the four incoming MD5
state registers at the start of each block. Comparing complete 1 MiB baseline
and V7 runs shows the first difference entering block index 15813 (input address
0x100140); all four state words were equal entering block 15812, whose input
begins at 0x100100. Thus the first divergence is within block 15812. Recorded
outputs, binaries and hashes: `build/sim/runs/md5-blockstate-{ngage,identity-v7}/`
and `scratch/md5-block-trace/blockstate-results.json`. The offset inference
assumes the observed block iteration order; inspect its detailed trace.

The shorter boundary lengths 0xf6fc0, 0xf7000 and 0xf7040 pass; 0xf8000 stops
at physical 0x104760 as adjacent digest loads from virtual 0x1007a0 and 0x4760
received swapped/stale section translation in the retained bus trace. This
strongly suggests another translation alignment issue, but exact first error
is not yet proved. A simple consecutive alternating-section test
`scratch/cache-alternating-sections/test.S` passes V7/V8 and baseline at both
timings, so it does not reproduce the relevant timing. A bounded detailed
comparison of block 15812 is running: `build/sim/runs/md5-window-*`.


The bounded trace completed. Aligning retired instructions from the equal
state entering block 15812 gives 635 instructions per variant and the first
visible arithmetic difference at instruction index 90, PC 0x3eb0
(`ADD r6,r4,r5`): baseline 0x59824165, V7 0x4f1fa934. Immediately prior are
`LDR r4,[sp,#32]` from VA 0x00100120 and PC-relative `LDR r5` from 0x475c.
Retirement annotations for asynchronous loads can be stale: inspect actual
load completion/register-lock and bus/TLB transitions before deciding which
operand is wrong. Traces are `build/sim/runs/md5-window-{ngage,identity-v7}/`;
`main-window.cpp` and `window-results.json` record instrumentation and hashes.
Next trace only those load requests and async writebacks, then write a small
deterministic reproducer and test a fix. No full firmware rerun is needed yet.
