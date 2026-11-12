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

## N-Gage-specific controller assessment (2026-11-12)

Scope: original ngage1 integration core, not ngage2 donor. Source assessment
only; no controller RTL, clock, branch or running simulation changed. User
instruction: do not create branches unless explicitly requested.

### Why two128-bit reads

The physical bus is16 bits; the ARM cache line is256 bits /32 bytes. The
installed JTFRAME mode isBL8, so each READ transfers8 halfwords /128 bits.
SDR parts in the checked chip model/datasheet family offer fixed bursts1/2/4/8
or full-page, not fixedBL16. The Winbond W9825G6KH datasheet section7.5 lists
those modes (vendor document mirrored at
https://datasheet.lcsc.com/lcsc/1809291411_Winbond-Elec-W9825G6KH-6_C62246.pdf).
This is not DDR3's burst/interface width.

The source confirms it: Template sets BA0_LEN/BA1_LEN=128;
`jtframe_sdram64` clamps its physical BURSTLEN to at most128 and the init
module programs mode bits011. `ngage_sdram_adapter` waits for selected_rdy,
advances its address by16 bytes, then returns to ISSUE for the second read.
The bank latch/grant/capture path is entered again. That causes an avoidable
inter-half bubble beyond the16 unavoidable physical halfword beats.

Setting BA*_LEN=256 alone is invalid: physical mode remainsBL8 while consumer
state lengths would exceed the existing burst schedule. The chip does not
produce another8 halfwords automatically inBL8 mode.

Two worthwhile schedules:

| Physical implementation | Data beats | Command strategy | Consequence |
| --- | ---: | --- | --- |
| Planned pair ofBL8s |16 | READ at columnC and another atC+8, spaced for contiguous returns | Can remove the adapter restart bubble without changing burst mode |
| Full-page terminated at16 |16 | READ then correctly timed BURST TERMINATE | One sustained transfer; changes short-read/termination/mode scheduling too |

Both can deliver16 consecutive data beats after initial latency. A continuous
256-bit logical transfer does not require fixedBL16. Full-page READ+STOP and
twoBL8 READs each use two command slots; a one-command-count reduction is not
a reason to choose full-page. Their scheduling and turnaround behavior matter.
A second READ can be issued before the first data burst finishes, so CAS
latency need not be paid as an extra gap in the returned stream.

### Actual geometry and bank pruning

Current Template is AW=22, and adapter bank=address[23]: BA0/BA1 are each8MiB
under the32MiB module geometry, for16MiB of phone RAM. Scalar and line clients
cover that same16MiB; they are logical request classes, not extra physical
banks. There is no implemented move to16MiB physical banks in this source.
AW=23 implies a different chip column geometry; it cannot be selected just to
rename the existing banks. A larger module can have other geometry, but that
needs an explicit installed-module configuration and matching tests.

Only physical banks0/1 receive requests. BA2/3 addresses, data and requests
are tied inactive; programming port is tied off; BAPRIO=1 makes random-priority
logic unused. Quartus can prune these constant paths. Removing their source
interfaces is useful specialization but does not prove large area savings.
Using half the banks also does not justify halving the chip's refresh rate.

### Where the removable overhead actually is

The scalar path contains similar captured packets in `ngage_dma_ram_mux`,
`ngage_sdram_arbiter` and `ngage_sdram_adapter`, followed by JTFRAME's registered
bank addresses/row checks. Each outer word packet includes25 address bits,
32 data bits,4 byte enables and a write flag (62 declared bits). These are
not all redundant: accepted ownership and timing boundaries must remain.
But one shared admission register can potentially replace successive copies
and request/drop/ACK state machines when the producer/owner holds the packet.
Avoid making that optimization a long combinational route through all clients.

There is already NO second256-bit SDRAM line buffer:16-bit results stream to
`arm920_cache_transfer.refill_line`, the cache's existing installation buffer.
The adapter carries a16-bit beat register/counters. Preserve that streaming
contract; do not introduce donor-style128-bit payload assembly just to adapt
interfaces. The cache's retained dirty victim and refill-install buffer remain
separate semantic owners until writeback/refill succeeds; their removal would
be a different cache correctness change.

The clearest controller/adapter costs to remove are:

1. **Second-half read restart.** Accept one32-byte owner, plan bothBL8 commands
   inside the controller, and emit sixteen16-bit beats plus last. Reuse one
   beat counter rather than re-entering the external request handshake.
2. **Two full transactions per32-bit write.** Current adapter uses ISSUE ->
   WAIT_READY -> GAP for each halfword, including a gap countdown. A native
   word operation can issue the two masked WRITE commands consecutively and
   complete after real recovery requirements, reusing the captured32-bit word.
   Uncached byte/halfword stores still need exact per-byte DQM.
3. **Repeated scalar packet captures.** Merge arbitration/admission/adapter
   ownership where safe, retaining CPU SWP reservation, fairness, reset drain
   and response matching. The timing-friendly registered pin boundary stays.
4. **Unused generality.** Limit normal request scheduling/row state to the two
   active banks and remove the unused programmer/mode alternatives from the
   specialized implementation, checking mapped evidence for actual savings.

Do not remove DDIO input resynchronization, registered command/DQ outputs,
required SDRAM waits, row-age/open-row state, refresh deadlines or accepted-
request drain as if they were spare buffering. They serve timing/correctness.
Cold scrub and warm-reset RAM preservation are existing system behavior;
retain them with their current ownership unless separately changed.

### Which existing controller is the better starting point?

Ngage2's controller offers a cleaner single req/busy owner, ns-derived timing,
open-row hit handling and consecutive masked writes. Those ideas suit the
original core. It is not a drop-in replacement: four-bank interleaved mapping,
rising-edge read capture/output staging and128-bit write payload storage differ
from this core's two-bank mapping, ALTDDIO_IN path and streaming refill.
A verbatim port could reintroduce payload storage we do not need.

Local JTFRAME's newer `jtframe_burst_sdram` is also relevant. Its documented
single runtime port uses full-page bursts with termination, but the checked
`jtframe_burst_ctrl` precharges after every transaction and its runtime port
has no byte-mask input (burst DQM defaults00). It also lacks this core's input
DDIO parameter. Therefore it needs open-row, byte-mask and IO adaptations;
choosing it solely because it says burst is not an established optimization.

Recommended first implementation: an N-Gage-specialized JTFRAME path with one
registered owner, two active-bank row records, planned2xBL8 line streaming,
native two-halfword masked writes, and existing IO capture. Borrow the donor's
single-operation/timing organization; no new full-line payload buffer. Evaluate
full-page mode afterwards if it simplifies the resulting state or improves
measured mixed-traffic performance beyond the planned pair ofBL8s.

### Required measurements after implementation

Use existing SDRAM chip-model/short-read/refill, full16MiB scrub, CPU/DMA lock,
all byte masks, dirty writeback, cancellation/reset and78/104MHz IO tests.
Add a command/data timeline proving sixteen correct consecutive line beats,
row-hit/conflict and refresh cases. Report first-beat and whole-line latency,
word-write latency, mixed CPU/LCD wait distribution, controller/admission
register/ALM counts and routed setup/hold. Keep a controller result distinct
from complete cache-miss latency or a gameplay FPS claim. No baseline-fit-first
requirement is introduced by this assessment.


## Native SDRAM service implementation checkpoint (2026-11-12)

Runtime validation is now complete for the bounded gates: see
[measured results below](#native-sdram-runtime-validation-and-latency-2026-11-12).
The pending statements in this implementation checkpoint record the earlier state.

This supersedes the assessment's implementation status above. Changes are in
original-core production RTL on the existing `codex/ngage2-integration` branch;
no new branch, clock change, commit, push, fit or board deployment.

### Implemented behavior

- Template now explicitly selects two active bank FSMs and no programmer,
  BA0/BA1 logical service256 bits, DYNAMIC_LINE=1 and existing SHORT_READS=1.
  Unused bank2/3/programmer outputs are tied inactive in generate branches.
  The physical chip mode remains CL2/BL8, with single-location writes.
- A line is one accepted operation. The bank schedules READ C then READ C+8
  eight clocks apart, reserves the second command grant, and retains ownership
  for16 consecutive halfwords. Adapter restart/address increment between BL8s
  is gone; the adapter still streams16-bit beats directly to cache installation.
- Native32-bit writes use two consecutive single-location WRITE commands,
  independent low/high DQM pairs and one terminal response after recovery.
  `ba_line` now marks either a long read or native word write. ACK after the
  first launch selects the upper halfword for the reserved following command.
  Existing scalar inputs remain aligned32-bit words with four byte enables.
  The adapter's former per-halfword ISSUE/WAIT/GAP sequence is removed.
- DMA/LCD mux captures only response ownership/fairness. Its62-bit duplicate
  payload packet is removed: the real outer arbiter captures those same fields
  on the common acceptance edge and retains them for the adapter. Payload
  outputs at the mux boundary are now meaningful at acceptance, rather than a
  second retained packet. Tests connect the actual outer arbiter and mutate
  source payloads after acceptance to check physical packet retention.
- Short scalar reads, open-row records, SWP lock handling, refresh cadence,
  cold scrub, accepted-transfer reset drain and registered/DDIO IO remain.
  No new line payload buffer, LCD FIFO or panel-memory change. The LCD reader
  still makes scalar32-bit requests; this change does not add LCD prefetch.

The62 removed mux state bits are a source-level count, not a fitted ALM saving.
Line and write scheduling changes can reduce latency, but no measured speedup,
Fmax or total area result is available. Explicit exclusion of unused controller
logic may duplicate pruning Quartus already performed.

### Geometry decision

Retain AW22, address[23] selecting physical bank0/1, each8MiB, total16MiB.
A32MiB SDRAM module has four8MiB physical banks. Changing bank count cannot
turn one of those into16MiB. A64MiB part with larger column geometry could
support16MiB per bank, but actual module geometry and matching mapping need
verification first. No unverified single-bank16MiB configuration was enabled.

### Validation checkpoint and resume

The 2026-11-12 validation retry remains blocked by Docker socket sandbox access.
`docker image inspect jotego/simulator:arm64 --format '{{.Id}}'` and
`docker ps --format '{{.Names}} {{.Status}} {{.Command}}'` fail with `operation
not permitted`; the documented `sh tests/phone/sdram/run-native.sh` exits 126
before any test starts. No image identity or running-container inventory could
be verified, and permission escalation is disabled. Shell syntax for 13 relevant
runners and `git diff --check` pass. Default firmware/C: inputs exist; sizes,
SHA256 hashes and exact check output are retained in
`scratch/sdram-native-validation-20261112/attempt.json`. No RTL or source media
changed, no runtime results or measured cycle deltas obtained, and no existing
simulation/checkpoint accessed. All runtime, formatter/top-lint and fit/board
gates below remain pending.

New physical-model assertions check consecutive two-halfword writes, per-half
payload/masks, eight-clock READ spacing,16 gap-free line beats and correct last.
Existing all16 byte masks, row/bank endpoints, SWP, refresh and reset-drain
coverage is retained. Full scrub fixture now models both native write halves;
other idealized CPU fixtures still use full-word logical completion and do not
establish physical timing. BENCH output includes aggregate word-write and line
wait clocks; those counters have not been run. The Verilator diagnostic script's
stale parameter replacement was repaired and its split-DQ monitor is supported.

Local Icarus elaboration passed for native adapter/controller + Micron model,
scrub, mux unit/outer capture, old128-bit concurrent-bank fixture and optional
four-bank/programmer hierarchy. Shell syntax and whitespace checks pass.
Docker socket denied with escalation disabled: no HDL runtime tests, benchmark,
full top Verilator lint, Quartus or hardware validation. Cached Verible is Linux
ARM64 and fails to execute on macOS; its formatting/check run remains pending.
Do not equate elaboration with timing-model or functional validation.

Run `sh tests/phone/sdram/run-native.sh` from a session with Docker access;
[validation handoff](sdram-native-validation.md) contains the exact new-chat
prompt, formatting/top checks, DMA/LCD/CPU integration commands and benchmark
requirements. Pre-change implementation copies are retained under
`scratch/sdram-specialize-20261112/before/`; do not restore them over concurrent
working-tree changes. Long simulations and checkpoints were not touched.


## Native SDRAM runtime validation and latency (2026-11-12)

This supersedes the earlier Docker-blocked checkpoint. All documented runtime
commands completed using the existing `jotego/simulator:arm64` image,
`sha256:df6f55924d5fab96083d01332e45cd734f22277c4dd3b34f55a09cd8dbc3eb8d`,
with `--pull=never`, network disabled, on `codex/ngage2-integration`.
No production logic failure was found. The formatter changed only layout in
`ngage_sdram_adapter.v` and `ngage_dma_ram_mux.v`; top structural lint passes.

### Regression results and corrected negative control

The first native wrapper run stopped because its wrong-edge negative control
unexpectedly passed. Its inherited default now uses physical BL8, leaving DQ
valid through the rising sample for the two consumed scalar words. It no longer
exercised the short-read release window. The corrected negative control enables
production `LINE_REFILL=1, SHORT_READS=1` and still requires a four-state Z-data
failure: first read gets `zzzz0000`, expected `00000000`. No Micron timings,
DDIO boundaries, data checks or expected-failure criteria were relaxed.

Final `run-native.sh` passes:

- Original Micron four-state functional/mask/boundary/reset/SWP checks.
- Sixteen DDIO cases: full BL8 and production short/line profiles, each at
  78/104 MHz with clock-pin delays 0/.25/.5/1 ns, plus the failing negative control.
- Scalar short reads transfer exactly two halfwords; long lines use two READs
  eight clocks apart and sixteen uninterrupted correct halfwords with last.
- Concurrent-bank coverage now includes both legacy 128-bit and native 256-bit
  services at both rates, with/without terminated short reads. Native cases
  issue 900 READs, 0/300 STOPs and 7200/5400 physical halfwords; all data and
  refresh checks pass. This directly exercises reserved second-READ slots
  against another bank's requests, rather than testing only the old service size.
- Full 16 MiB adapter scrub covers 8,388,608 halfwords and 3,084 scheduled
  refresh pulses. This fixture models the controller handshake; physical-model
  functional/timing coverage comes from the other tests, not this full-size scrub.
- DMA/LCD mux unit and actual outer-arbiter packet-retention tests, 32 alternating
  requests each; LCD legacy/fast comparisons remain bit-exact for all 18,304 words.

DMA concurrency passes all nine engine/mode combinations. DMA handover passes
normal, held, physical-reset tail and CPU Hold logical-reset cases. Line-refill
integration passes stream/stall/fallback/dirty-writeback/error/reset, registered
owner, DDR stream and both physical SDRAM clock-rate cases.

Both default 5,000,000-cycle real-controller firmware runs pass:

| Rate | Acknowledged bus transactions | Instruction faults | Data faults | LCD words | Last accepted fetch |
| --- | ---: | ---: | ---: | ---: | --- |
| 78 MHz | 327791 | 12 | 0 | 0 | 00006178 |
| 104 MHz | 327792 | 12 | 0 | 0 | 00006178 |

All twelve faults are instruction fetches at peripheral addresses `0c0047e4` /
`0c0047e8`, not SDRAM data failures. The bounds include real SDRAM startup
read/write patterns, but do not prove complete Symbian startup or LCD gameplay.
Profile: default factory core/extension, C: `scratch/overnight/cdrive-11b.img`,
`PHONE_LINE_REFILL=1`, `PHONE_SHORT_READS=1`, default ROM cache disabled.
Input sizes/hashes are in the evidence JSON; all three source inputs were
rehashed unchanged after the boots. Each rate's build/runtime logs were copied
before reusing the runner's output directory.

### Matched physical-controller measurements

New `tests/phone/sdram/latency_tb.sv` and `run-latency.sh` compare saved
pre-change adapter/controller/mux sources in
`scratch/sdram-specialize-20261112/before/` against current sources. No worktree
source swapping or Git HEAD whole-project baseline is used. Identical traffic,
AW22 mapping, CL2/BL8, short-read/cache configuration, clock polarity and original
Micron timings are used; logical bank service changes from 128 to 256 bits as
required by the respective adapter. No ideal RAM fixture is used for these numbers.

All values are system clocks, measured from a source's falling-edge offer to
its sampled consumer response. Lines use the direct streaming interface;
scalar operations include the actual outer arbiter, and mixed LCD requests
also include the actual old/new DMA/LCD mux. These are service latencies,
not complete CPU cache-miss times. Both 78 and 104 MHz yield identical cycle
results. Thus the row-hit line's six-clock saving is 76.92 ns / 57.69 ns,
respectively; a row-hit write's nine-clock saving is 115.38 ns / 86.54 ns.

| Probe | Old first / whole | Native first / whole | Whole change |
| --- | ---: | ---: | ---: |
| Line, open-row hit (2 samples) | 8 / 29 | 8 / 23 | -6 (-20.7%) |
| Line, same-bank row conflict (2) | 12 / 33 | 12 / 27 | -6 (-18.2%) |
| Line offered during refresh (2) | 16 / 46 | 16 / 31 | -15 (-32.6%) |
| Masked word write, row hit (16 masks) | 21 / 21 | 12 / 12 | -9 (-42.9%) |
| Masked word write, row conflict (16) | 25 / 25 | 16 / 16 | -9 (-36.0%) |
| Masked word write during refresh (16) | 33 / 33 | 18 / 18 | -15 (-45.5%) |

First-beat line latency is unchanged; the restart gap disappears between the
BL8 halves. During the refresh probes the old implementation permits a second
refresh between its restarted halves; native ownership retains the whole
operation, hence the larger completion saving. Both eventually pay the same
refresh debt; this is a measured scheduling effect, not reduced chip timings.
The benchmark explicitly schedules refreshes and keeps automatic timer expiry
outside isolated probe windows to avoid accidental old/new phase differences.
Production periodic refresh is covered by the regressions above.

Mixed workload: 64 masked CPU writes + 64 CPU reads against 128 LCD scalar
reads, with eight response-gap clocks per producer; sixteen identical refresh
requests spaced 200 clocks apart, each adding nine refreshes of debt.

| Consumer | Old mean / p95 / max | Native mean / p95 / max |
| --- | ---: | ---: |
| CPU write | 34.1875 / 40 / 45 | 22.625 / 25 / 28 |
| CPU read | 21.140625 / 23 / 28 | 23.734375 / 29 / 29 |
| LCD read | 27.5390625 / 38 / 38 | 23.0546875 / 29 / 29 |

Mixed completion is 4693 -> 4119 clocks, -574 (-12.2%). CPU read mean increases
2.59375 clocks (+12.3%) as the faster writers change refresh/arbitration phase;
this is not a uniform latency improvement. This synthetic finite workload
establishes neither panel FPS nor gameplay speed. Full distributions' min/mean/
p95/max, input/source hashes, commands and boot summaries are in
[`evidence/sdram-native-validation-2026-11-12.json`](evidence/sdram-native-validation-2026-11-12.json).
Raw old/new logs and initial dirty-source snapshots are preserved in
`scratch/sdram-native-runtime-20261112/`; 62 runtime logs were scanned with no
unexpected error/warning/timing diagnostics. The expected negative control is
retained separately. Build warnings are not physical-model timing results;
top lint is structural with HPS/PLL stubs.

### Reproduce and remaining gates

Run the existing formatting/top check and all commands in
[`sdram-native-validation.md`](sdram-native-validation.md). Additional benchmark:

```sh
docker run --rm --pull=never --network none --platform linux/arm64 \
  -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 \
  -c 'sh tests/phone/sdram/run-latency.sh'
```

`SDRAM_LEGACY_DIR` selects the saved pre-change directory;
`SDRAM_LATENCY_OUT` selects the output directory inside the container.
Defaults preserve logs in `build/sim/unit-sdram-latency/` by version and rate.
Do not substitute current native assertions for the old implementation's legal
gapped line/two-transaction write behavior.

The current branch, unrelated dirty files, source media, original
`frosty_neumann` long simulation and every checkpoint were preserved. No
commit/push/deployment or Quartus run. Routed setup/hold, 104 MHz closure,
fitted ALMs, board IO/installed geometry and full Symbian/gameplay validation
remain unverified. Mapping remains two physical 8 MiB banks / AW22.


## Shared scalar write payload follow-up (2026-11-12)

The [request-ownership cleanup](sdram-request-ownership.md) now removes the
adapter's duplicate 32-bit write-data and four-bit byte-enable registers. The
existing outer arbiter holds them; `owner_ready` blocks a new owner while a
logically canceled physical operation drains. Address, operation identity and
physical command/IO registers remain. This removes 36 declared state bits;
fitted area and routed timing remain unmeasured.

A frozen pre-sharing native baseline and candidate have identical 310 physical
latency samples plus mixed completion at each of 78/104 MHz: row-hit line remains
8/23 first/whole clocks, masked write 12, mixed workload 4119. All 16 mask and
post-admission mutation cases pass with controller grant waits 0/3/7. Bypassing
the reset admission guard fails as intended. Normal latencies are unchanged;
a new response after cancellation takes two extra clocks in the directed
stalled-controller fixture. Full physical/DDIO/short/concurrent/scrub/mux/LCD/
refill regressions, top/CPU-path elaboration and both 5M-cycle real-controller
CPU/board profiles pass with zero data faults.

No cache line-storage change was made. The existing incoming 32-byte refill
buffer and registered cache commit stage remain; there is no additional full
line buffer in the SDRAM adapter. Direct RAM fill is possible with an explicit
reserved/incomplete destination and delayed valid-tag publication, but is a
separate unimplemented cache-interface experiment. Production `line_error`
remains tied low; successful completion is a protocol/timing contract, not an
ECC/checksum result. Details and evidence are in the ownership document.
