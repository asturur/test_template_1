# ARM cache line transport

This is a transaction-level performance path, not a newly identified phone bus.
The ARM920 caches remain 16KiB each, with 32-byte lines and the existing BRAM
payload/tag geometry. The MMU still authorizes the requesting process before a
cache miss requests physical memory. A line never crosses the smallest TLB
permission granule. C:, PMM and peripheral accesses retain the scalar path.

`LINE_REFILL` enables a separate physical line request from cache replacement.
The default is off in reusable CPU/board modules; Template enables it. The
full-phone runner requires explicit `--line-refill` and rejects restoring a
checkpoint from the other setting. Old running executables do not change.

A registered owner selects the instruction or data miss. Admission waits for
the ordinary CPU bus and data write buffer to drain, including writes that
become pending while an offer waits. Descriptor ownership remains stable until
acceptance, and response ownership lasts through the final beat or rejection.
Physical response data/valid are registered before the existing refill register.
The cache bank installs a line only after the whole replacement completes.
Dirty eviction, permission faults, locked swaps, redirect/discard handling and
maintenance remain in their existing owners. An unsupported line request falls
back to ordinary word transfers; it is not acknowledged with invented data.

For NOR, the provider probes the selected die's array mode. Status, identification,
command setup and PMM cases fall back to the real NOR controller. An eligible
immutable ROM line maps through the existing physical-to-backing mapping. DDR
issues one four-beat 64-bit command. Each word undergoes the same address-based
flash decoding as the old path. Raw registered beats fill the ARM's existing
256-bit `refill_line` register; the old 1KiB instruction buffer remains available
for scalar instruction reads. Reload writes still invalidate that buffer.
Accepted physical reads drain reset before their response channel can be reused.

For SDRAM, a separate logical line request and the normal word interface cover
the same contiguous 16MiB. Normal CPU/DMA arbitration and SWP reservation stay in
place. The adapter admits a line only when its normal port is idle and the CPU
is not locked. It streams raw 16-bit data directly to the ARM refill register;
it does not assemble another 32-byte cache or route each halfword through the
normal 32-bit response register.

The current `jtframe_sdram64` extension supports legal physical BL8 reads and
dynamic short-read completion. A 32-byte logical line uses two 128-bit READ
commands against the same open row. Normal reads return their first 32 bits;
with `SHORT_READS=1`, a reserved BURST TERMINATE command stops the chip after
two halfwords and releases the short transaction's DQ/mask/FSM occupancy. The
option defaults off; Template enables it. Long reads retain both full BL8s.
Physical bank
selection remains address bit23: two 8MiB banks provide the phone's 16MiB.
Simulated timing conformance does not establish FPGA placement or 104MHz closure.

Directed tests are `tests/phone/line_refill/run.sh`. They cover 16/64-bit streams,
waits, late write-buffer blocking, rejection, dirty write-back, errors and reset;
DDR four-beat admission plus normal-buffer/reset coexistence; and actual SDRAM
chip-model line reads on both banks, short reads, writes, DMA locks and refresh
with the inverted capture setup at 78 and 104MHz. Existing CPU/cache, NOR,
transport and reset/reload tests are also required. See status.md for results.

The optional `--refill-stats` observer counts only the current replay segment;
its counters do not change the CPU/host checkpoint layout. Trace observations
count micro-ops, not architectural instructions. DDR command counts use the
harness's accepted-read transition into its fixed delay; these are modeled
transport statistics, not board throughput. Cold early firmware runs mostly
with the I-cache disabled, so cache-active comparisons are needed as well.

## Follow-up: overlapping logical SDRAM ports

The user requests a long 256-bit logical port and a short 32/64-bit logical port
covering the same 16MiB. The interfaces above already separate those request
classes over that address space; logical ports need not be physical banks.
Here "physical bank" means an internal SDRAM-chip array selected by BA[1:0],
not a separate chip or a logical client port. All four share the chip's DQ bus.
On a32MiB module each is8MiB. The phone's two16MiB access ports both span the
same two physical banks.

Changing a 32MiB module's geometry to claim a 16MiB *physical* bank would alias
memory. Keeping its two real 8MiB banks is compatible with two 16MiB logical
views and does not duplicate the stored contents.

JTFRAME does support different per-bank service lengths through
`JTFRAME_BAn_LEN`. The local reference docs explicitly distinguish these from
physical burst mode and shared-bus occupancy. `jtframe_sdram64` chooses its
physical mode from the largest bank length and passes each individual length
as `BALEN`; its stock bank FSM still uses global `BURSTLEN` for `BUSY`. Thus a
shorter consumer window alone does not stop unwanted physical words.

Local references reviewed (2026-11-10) under
`~/develop/jtpublicfork/modules/jtframe/`:

- `doc/rom-caches.md`: "Four quantities to keep separate" and "Choosing settings".
- `doc/jtframe-mem.md`: bank versus cache-lane configuration and ROM bank bits.
- `doc/burst_sdram.md`: runtime termination and AW22/AW23 geometry.
- `hdl/sdram/jtframe_sdram64.v`, `_bank.v`, `_init.v`: global mode selection,
  individual `BALEN`, and global busy duration.

The newer `jtframe_burst_sdram` uses a full-page runtime burst with explicit
termination. That is a possible future controller replacement; it is not used
by this change. The existing controller now explicitly terminates normal reads
without replacing the verified register/DDIO boundary or changing geometry.

On the common128MiB two-chip module, both SDRAM chips share one16-bit data
bus. Independent chip mode registers can select different burst lengths, but
only one chip can drive DQ at a time. Row preparation can be interleaved with
another chip's transfer, subject to shared command scheduling. This does not
create two simultaneous16-bit streams. Keeping long/short reads of the same
writable RAM on separate chips would require mirrored writes/coherence; no
such duplication is implemented or needed here. Two separately wired SDRAM
modules are a different, genuinely independent-bus configuration.
Primary reference checked with gh:
https://github.com/ika-musume/ikautil_SDRAM#slot-placement-and-per-chip-burst-length
(local copy scratch/short-reads/ikautil-readme.md). Its per-chip BL0/BL1 example
confirms distinct chip mode registers; it is not a controller adopted by this
core or a claim about fitted N-Gage performance.

## Short 32-bit reads (2026-11-10)

`SHORT_READS=1` plus `DYNAMIC_LINE=1` retains only two physical halfwords for
normal reads. At CL2, the bank requests a BST command two pin-command clocks
after READ. The top arbiter reserves that slot for its owner, preventing another
bank from advancing on a command that was replaced by BST. DQM, busy, `dok` and
the transaction FSM end at the short boundary. Writes never take this path.
Line refills still deliver sixteen halfwords using two BL8 READs. No extra
response buffer or write-invalidated cache is added.

`tests/phone/sdram/run-short-reads.sh` uses the original four-state Micron model
at 78/104MHz, including inverted pin clock/falling capture and 0.6ns modeled
clock-pin delay. It covers both banks, final address boundaries, all write masks,
reset/drain, line/word transitions, DMA/SWP and refresh. A separate concurrent
bank test alternates short/long reads under randomized bank arbitration and
checks all returned data, BST counts, physical beats and completion flags.

Observed: 113 ordinary reads transfer 904 -> 226 halfwords (8 -> 2 per read).
A fixed mixed workload of 600 READ commands transfers 4800 -> 3000 halfwords
and completes in 8920 -> 8173 controller clocks (~8.4% fewer), including refresh.
This is a synthetic controller workload, not measured Symbian startup speed.
First-word latency is not reduced; the original dynamic path already returned
the requested word early. The gain is freeing unused bus and bank occupancy.

A trial refresh trigger every97 clocks starved concurrent stress traffic.
Excessive refresh load is suspected; the exact cause was not investigated. The maintained test uses401 clocks, still much more frequent
than production's scaled6800-clock interval. This is not evidence of a new
phone-boot stall; the original fixed-burst path and new path use the same401
schedule for comparison.

The separate full-phone original-timing-model cold50M run passed:50,000,000
clocks,4,851,552 bus completions,12 known startup instruction-probe bus errors,
zero data errors, fetchPC0x6160 in the early delay loop. Firmware RAM pattern
writes/readbacks appear in its SDRAM samples. Exact evidence is tracked in
`docs/status.md` and `docs/evidence/sdram-short-reads-2026-11-10.json`. It is not the fast backing-array harness, which would hide
this controller change. Early cold firmware spends most cycles with ARM caches
off; it checks startup compatibility, not cache-active whole-boot speed.
The timed Micron model cannot be combined with Verilator `--savable`; the main
resumable long run retains its exact frozen executable/checkpoints unchanged.
104MHz timing-model tests do not establish Quartus timing closure.

## Measured cache-active comparison (2026-11-10)

Separate audited forks start at4,700,000,002 and each complete50,000,000 cycles.
The disabled import matches2256 common named state fields and host bytes against
the original after1000clocks. Passive statistics match CPU/host files byte for
byte. Both runs preserve unmodified source image hashes and finish with zero
CP15FSR/FAR/abort-LR/panic mask, data errors0 and no new backing-bus errors.
Both still display Nokia; this is not a whole-boot or UI completion claim.

| Metric | Scalar refill | Line refill |
| --- | ---: | ---: |
| Mean instruction refill clocks |137.37|22.87|
| Mean data refill clocks |136.84|39.92|
| Code-stall clocks /50M |36,234,874|28,939,276|
| Trace micro-op observations |4,119,132|5,824,305|
| Physical DDR read commands |722,967|252,294|
| Returned64-bit DDR beats |722,967|981,072|
| Changed C positions during interval |1,462|5,947|

Instruction refills are about6x faster; trace observations increase41.4%. The
higher returned-beat count accompanies more firmware work and full-line reads;
command overhead is reduced. Trace observations are not retired ARM instruction
counts, and C differences are not a copied-file throughput counter. Data-stall
share rises36.7%->40.7% as more work fits in the same cycles; no isolated data-hit
latency improvement is claimed. Clock closure/resources remain unmeasured.

Independent3M post-change decomposition: FIFO-only782462clocks(26.08%),
fetch-only835099(27.84%), both11331(0.38%), neither1371108. WAIT_REFILL243715
clocks(8.12% of interval), versus45.04% in the prior3M sample. This confirms
that residual code_stall is not solely ROM wait; lookup/admission/data throughput
matter. IRQ timing/work composition differ once execution speeds change.

Evidence: docs/evidence/line-refill-2026-11-10.json; exact model IDs, full stats,
checkpoint/input hashes and limitations are included. State inspection first
mislabelled RF30 as abort LR; corrected inspection uses PHY_ABT_R14=32. The
invalid-label scratch log is retained separately and is not fault evidence.
The final helper received formatting only after simulation, verified against
explicit-port-expanded tokens and rerun owner tests. No behavior edit followed
benchmark model5271ec5bedfe81c5. Source replay is not generic state compatibility.
