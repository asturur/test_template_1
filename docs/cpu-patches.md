# CPU compatibility fixes

Current checkpoint and resume tasks: [status.md](status.md).

## Registered line-refill transport (0055)

Patch0055 adds an optional post-MMU line channel to the existing cache wrappers
and a registered I/D owner. Scalar Wishbone behavior is retained for commands,
peripherals, mutable flash and rejected line requests. The owner checks bus/
write-buffer ordering both before capture and while waiting for acceptance.
The replacement engine streams into its existing line register and installs
BRAM only after completion. No cache size, permission rule or core operand
pipeline change. See [cache-line-refill.md](cache-line-refill.md) for backend
contracts,50M measurements and the remaining physical timing limits. Pin/patch
reconstruction and180CPU-suite passes verified; no hardware build requested.

## Data-request privilege ownership (0054)

Patch0054 takes data privilege and force-user(LDRT/STRT) from the registered
P2 request, alongside its address, direction, byte lanes and payload. Previously
those two fields came from P1. An exception return can already put user mode in
P1 while an older privileged FIQ flash store remains in P2. That produced the
phone's false section permission fault at5038524C/59893FE0 despite AP1 allowing
privileged writes. No permission table, firmware or C: input was changed.

The exact old close replay shows P1mode10/P2mode11 and aborts after1209clocks;
its CPU state is byte-identical to the original first-abort capture. Fixed HDL
passes the store, updates the simulated flash and returns to startup. The
source-code request registers and timing boundaries are retained; no extra wait
or unregistered CPU-to-memory chain was introduced.

`data_privilege_owner.S` covers warm protected stores before exception return,
then LDRT inside SVC which MUST get an unprivileged permission abort. Identical
program bytes fail the original wiring (LDRT wrongly allowed), and pass fixed
wiring at memory delays0/3. Full CPU suite180PASS, no XFAIL. Patch reconstruction
through0054 passes. Phone verification details: [symbian-startup.md](symbian-startup.md).

## Production ARM920T TLBs and cache (0053)

Patch0053 removes the ZAP cache fallback and split TLB modules, selects the
production cache unconditionally, and connects actual CP15c8/c10 I/D controls.
The replacement lookup/table-walk implementation is maintained in rtl/arm920/
with the existing cache. TLB slots share page sizes, use staged associative
lookup/BRAM metadata, and implement round-robin/base/victim/P behavior. See
[arm920-tlb.md](arm920-tlb.md) for the contract and verification. The old cache
selection macro and legacy expected-failure test are removed. Patch application
now uses -E because deleted upstream files must disappear rather than remain
empty. The complete pinned-upstream reconstruction passes with0053 applied.

## MMU lookup ownership and refill recovery (0052)

The TLB's registered check and RAM lookup must both belong to the current
request before admitting a page-table walk or a permission fault. Ownership
includes MMU enable, read/write direction, mode, S/R bits, DAC and TTBR.
Address matching uses the smallest ARM920 permission granule, 1KiB, so adjacent
instruction hits keep their one-clock throughput. The live low ten address
bits supply the physical offset; MMU-disabled accesses use the identity address.
ARM DDI0151C section3.1/3.1.1 defines tiny1KiB mappings and small-page1KiB
permission subpages; matching an entire4KiB page would be incorrect.

A local recovery path clocks the existing RAM/check registers for an unowned
request, even when the CPU is stalled. After installation or invalidation,
three lookup clocks let the RAM/check pipeline observe the new entry. A held
CPU cannot suppress an already-returned refill installation. In-flight walks
invalidated or superseded by a TTBR change drain their bus transaction but
cannot repopulate the TLB with a stale descriptor.

Instruction lookup waiting is distinct from the existing miss-retry indication:
`o_lookup_wait` suppresses the adapter's err2 redirect while a lookup is being
aligned. Treating that wait as a real miss retry made the CPU repeatedly clear
fetch and never stabilize its lookup owner (cpu_timing stuck at000000FC).
Address qualification alone also repeated real misses until post-fill settling
was added. Both failed approaches are recorded under scratch/mmu-handshake/.

No RAM/check stage is removed, and this change does not alter CPU operands,
cache geometry or SDRAM/DDR clocks. Warm ADD throughput remains one clock in
cpu_timing at memory delays0/3. Quartus timing has not been measured for this
change; retaining register boundaries is not proof of104MHz timing closure.
Directed coverage: tests/cpu/tlb_lookup_owner/sim.sh. Boot/scan comparison and
remaining regression limitations are in docs/mmcstore-scan.md and status.md.

Patch0051 records the already-committed abandoned instruction-refill discard
fix, which had not yet been included in the upstream-relative patch series.
Applying0001–0048,0050,0051,0052 reproduces rtl/arm byte-for-byte; the verifier
uses the pinned local upstream checkout without a network fetch.

`rtl/arm/` is the ONLY ZAP copy in the project: pinned upstream krevanth/ZAP
`fc7bd75` plus the ordered series in `patches/zap/`. The Verilator boot
simulations (`scratch/*/build.py`, `sim/run.py`) and the Quartus build
(`files.qip`) all compile it. Edit files there, record each edit as the next
numbered upstream-relative patch, and run `patches/zap/verify.sh`: it downloads
the original upstream to `scratch/zap-upstream/` (git-ignored, reference only),
checks it against the hashes in `rtl/arm/UPSTREAM.json`, applies the series and
requires a byte-identical match. `make sim-upstream`/`sim-unmodified` use the
same download. `rtl/ngage_cpu.sv` is the shared RTL integration boundary.

History (2026-11-01): before this, `third_party/zap` held upstream + Quartus
fixes only, while every simulation used an untracked scratch copy
(`scratch/boot-v15-quiet-zap`) carrying 0001-0009 plus three unrecorded changes,
so the FPGA build was not the CPU the boot evidence came from. The unrecorded
changes were extracted as 0010-0012 (upstream + 0001-0012 reproduced that copy
byte-for-byte), then 0013/0014 were added. A from-reset authentic run to 150M
cycles was cycle-identical between the old scratch copy and the consolidated
tree (same bus/instruction traces, 41,013,833 transactions); checkpoints made
with the old copy may not restore (Verilator state layout differs). The patched
tree then moved from `third_party/zap/src/rtl` to `rtl/arm` and `third_party/`
was removed (file contents unchanged).

## Translated accesses when caches are disabled

The unmodified instruction and data cache FSMs use the virtual address for the
cache-disabled external request. This bypasses a successful MMU translation.
Patch 0001 selects the translated physical address in both paths. With the MMU
disabled, the translation unit already supplies the identity address.

The nonidentity data/FCSE test passes with caches enabled and disabled. A separate
code-fetch test maps virtual `0x30000000` to physical ROM at zero, leaves both
caches disabled, jumps to the translated code, and checks the visible PC.

## ARM920T alignment checking

Patch 0002 preserves CP15 c1.A and detects misaligned data accesses using the
full modified virtual address before ZAP drops its low address bits. Halfword
and word accesses fault at their respective alignment; bytes remain valid.
The early check prevents a misaligned access from initiating a page-table walk.
The data cache returns an abort with FSR `0x01` and the original fault address,
with priority over translation/domain/permission errors and without a target
memory write. The implementation is for the cache/MMU CPU configuration used
by this project; it does not add an abort controller to ZAP's ONLY_CORE mode.

The [ARM920T manual](https://documentation-service.arm.com/static/5e8e2a5b88295d1e18d381bb)
sections 2.3.5, 3.5, and 3.7.1 define these controls and fault semantics.
Other reserved/read-only CP15 bits remain ZAP's implementation, so the entire
control readback is not asserted to match a physical ARM920T.

`alignment_cases` checks 32 expected aborts across MMU-off, MMU-on/cache-off,
cache-on/uncacheable RAM, and cache-on/cacheable RAM configurations. It checks
word and halfword loads/stores, signed halfwords, fault addresses/status,
exception return addresses, unchanged memory after aborted stores, priority over
an unmapped access, byte operations, and unaligned word rotation after disabling A.

## Ordering a return from RAM into flash

Firmware runs identification/configuration routines from scratch memory. Its last
flash-reset store is immediately followed by a return into the flash array.
With delayed memory, ZAP's deeper pipeline can start the return fetch while the
flash is still in identification mode. The measured failure was a fetch at ROM
`0x5954` before the reset store acknowledged.

Patch 0003 holds the instruction front end while the instruction cache is
disabled and an older store is in the post-ALU/memory stages. The existing FIFO
write-inhibit honors that hold. Data execution still advances so the store can
complete. Branch prediction remains unchanged; disabling it alone did not fix
the ordering problem and is not part of the maintained patch set.

The firmware now reaches the same peripheral frontier with immediate and delayed
memory. An independent synthetic `flash_return` program copies its helper to RAM,
enters flash identification mode, reads the manufacturer ID, issues reset, and
returns to ROM. It reaches its expected completion stop with delays of 0, 0-3,
and 0-7 cycles. The flash array is never modified by this test.

## Optional simulation console suppression

Patch 0004 adds the `+ngage-compact-trace` switch around the duplicate retirement
console print. Retirement outputs, assertions, CPU state, and synthesis paths
are unchanged. The harness still checks architectural fetch aborts and records
its last retirement. This keeps long firmware delay loops from producing several
gigabytes of duplicate text; the runner's `--compact-trace` also filters ordinary
memory/instruction logs while retaining device I/O and faults.

Only the standalone harness defines `NGAGE_RUNTIME_TRACE` and initializes
Verilator's command arguments. Other benches retain the default console print
without evaluating runtime plusargs. The first upstream recheck exposed that
bench-initialization requirement; the current patch passes both original benches.

## Correctly completing nonblocking data-cache loads

Patch 0005 carries six bits of original load metadata from the core through the
D-cache and captures them alongside the missed register index. Its background
completion now selects the byte/halfword, sign-extends when requested, or rotates
an unaligned word before writing the asynchronous register port. Later requests
that hit under the miss cannot replace those captured controls.

The original miss path wrote a whole cache word directly into the destination,
bypassing `zap_memory_main`'s ordinary load transform. Real firmware exposed this
at virtual `0x500034f0`: cached hits read the register table correctly, but a miss
for byte `0x6da0` ultimately supplied `0x0026003b` where byte `0x3b` was required.
The lookup then entered its permanent failure loop at `0x50003524`.

`cache_load_widths` isolates the bug without Nokia firmware. Before the patch,
it returned `0x80ff7f01` for an unsigned byte expected to be `0x01`, with both
immediate and delayed memory. The fixed diagnostic checks misses and hits across
all byte lanes, signed/unsigned halfwords, unaligned-word rotation with A clear,
and the real adjacent-LDRB/ORR dependency pattern. It is part of `make sim-compat`.
The configured little-endian path is the tested scope.

## Qualifying branch state on a BTB tag miss

Patch 0006 reports strongly-not-taken for an invalid or mismatched predictor
entry. Previously the raw prediction state could claim a taken branch from an
unrelated tag, despite no redirect having occurred. The real firmware then fell
through a cached return into its literal pool and requested `0x0c120100`.

`btb_return` trains an aliased BTB entry and reproduces the wrong access without
Nokia payload. With the fix, immediate and delayed cases reach their intended
terminal write. See [branch-prediction.md](branch-prediction.md) for exact evidence,
failed cold reproducers, measured cycles, and the six-patch verification.

## Patches 0007-0009

0007 sets the terminal-exception FSR only when the Wishbone transfer actually
errored, so an acknowledged transfer no longer overwrites CP15 fault state.
0008 fixes the Thumb format-11 SP-relative LDR/STR offset sign (upstream
subtracted). 0009 makes the CP15 cache type register report ARM920T
associativity (64-way) and ctype 6: EKA1's clean-by-index loop derives its way
increment from the assoc field, and upstream's 0 made it run 2^32 iterations
(commit 0164a87). The physical caches stay direct mapped.

## 0010: retain D-cache translation across a background refill

Recovered from the `scratch/ldm-*` experiment chain (identity-v6..v15,
tlb-handshake v1-v4) that fixed LDM/cached-load corruption during boot. While a
CPU request is stalled behind a background line refill, the D-cache keeps the
TLB result it already obtained (`pending_translation`) instead of re-looking up
with a pipeline address that has moved on; the refill FSM holds the micro-op
(no ack/err2) on a background miss, forwards the completed line to a waiting
load or store in the same line, and commits the refill on the release edge.
`zap_tlb`/`zap_cache_tag_ram` export the checked lookup context used to decide
when the retained translation is valid. The simulation-only `assert`/`$fatal`
checks that the pending request context never changes are ignored by synthesis.
This is the CPU every boot milestone since 2026-10-28 ran on, but it has no
standalone reproducer yet (unlike 0005/0006).

## 0011: Thumb hi-register op with SBZ bits traps as UND

`decode_alu_hi()` reached `$fatal` for op=11 halfwords that are neither BX nor
BLX. Wrong-path fetches of literal-pool data after an unconditional branch
decode such halfwords without executing them (apmime 0x50603bc8, word
0x506047ec, 2026-10-31). They now decode to the UND trap. Also rewords the 0008
comment.

## 0012: silence simulation info floods

Comments out the UNPREDICTABLE PC-as-shift-operand `$info` in `zap_decode`
(N-Gage frame-drawing code hits it in hot loops; 186MB of log) and empties
three section-descriptor `$info` messages in `zap_tlb_fsm`. No datapath change.

## 0013: Quartus 17.0.2 compatibility

Formerly repo commits 446a44a/7fd435b. No logic change: typed localparams/struct
typedefs moved out of parameter lists (BTB, CP15), `foreach`/`inside` replaced,
explicit `generate` regions, sized enum literals, simulation-only assertion
blocks guarded with `SYNTHESIS`.

## 0014: byte-lane cache data RAM

`zap_ram_simple_ben` (cache data RAM, 256 bits wide with 32 byte enables) is
stored as one 8-bit memory per lane. Quartus 17 did not infer block RAM from
the looped byte-enable slice and built each 16KB cache from ~135K registers
(CI run 41263284904: the CPU alone was 122,721 ALUTs / 275,049 registers).
Behavior is identical: 400,000 random cycles including same-address
write/read collisions matched the original module on both outputs.

## 0039: synchronous BRAM instruction lookahead

The associative tag/data path now has two synchronous RAM stages. Look ahead
two instructions while a current read completes, allowing the cache's two-line
streaming buffer to maintain one warm ARM instruction per clock. Translation,
permissions and cacheability still qualify the current request; lookahead only
reads resident tags/data and never initiates a speculative linefill. The existing
`cpu_timing`, branch, maintenance and prefetch regressions remain required.

## 0040: synthesis-safe board diagnostic observations

Expose fetch virtual PC, ALU CPSR, raw fetch word and accepted-fetch pulse
through explicit ZAP core/top ports. These are read-only and remain available
under synthesis; no hierarchical signal references or simulation trace strings
are used by hardware. The phone UPP/board forwards them to the host diagnostic
screen. Upstream-reference builds disable these connections explicitly via
`NGAGE_NO_CPU_DEBUG`, because pristine upstream lacks the observation ports.
Fetch observations are not an architectural retirement trace.

## 0041: registered cache comparison lookahead

The shared associative bank adds a comparison register between tag and data
reads. Advance resident-line lookahead from eight to twelve bytes (three ARM
words) to cover the three-stage lookup. Keeping eight bytes caused a five-cycle
warm ADD interval at a line boundary in `cpu_timing`; that failed approach is
retained in `scratch/timing-closure/pass9-cache-pipeline/cpu-first-attempt.log`.
Current-request translation and permission checks still qualify completion;
lookahead only reads cache storage and cannot initiate bus traffic or allocation.

## 0042: balanced asynchronous register reads and operand forwarding

Each of the four register reads uses local physical-address comparisons and a
balanced masked-word reduction. The original synchronous reset, two ordered
normal write ports and highest-priority asynchronous-load write port are unchanged
(the latter still writes on a clock edge). Unimplemented physical indices retain
an X read value. No register banking or read/write latency changes.

Issue builds priority-qualified selection bits independently of the wide data
and merges selected values with masked ORs. The exact order is immediate, RAZ,
PC, CPSR, combinational ALU, registered ALU, postALU0, postALU1, postALU, memory,
then register file. The existing final alignment mask, skid storage, instruction
controls, clear/reset/stall priorities and issue output registers are unchanged.
This targets pass15's seven-level register-file/forwarding path without a new
pipeline stage or synchronous RAM read.

`tests/cpu/operands/sim.sh` compares the real RF/issue against an independent
scoreboard and priority oracle over17160 cycles; the same fixture passes the
pre-change implementation. It covers all40 physical addresses, every combination
of six forwarding valid bits, colliding special operands, random ports, three-port
write collisions, reset, both clear sources and both stall sources. The CPU ADD
fixture retains one-cycle warmed throughput at0/3 waits. Physical timing remains
unmeasured until the next fit; see status.md for combined integration evidence.

## 0043: separate demand completion from idle housekeeping ACK

The associative adapter exposes `request_ack` for faults, TLB retry, a registered
cache response, or an instruction fast hit. Its existing `ack` still includes the
original maintenance-qualified idle term and retains the exact original equation.
`zap_dcache.o_request_ack` carries only the demand term to the core's existing
`i_data_wb_ack` input. Legacy direct-mapped and ONLY_CORE configurations alias
that new signal to their original ACK. Instruction-cache/prefetch logic still
uses its original adapter ACK; the shared adapter's new output is unused there.

Source audit/proof:

- `zap_top` constructs D-cache `rd = !cpu_dc_we && cpu_dc_stb` and
  `wr = cpu_dc_we && cpu_dc_stb`, so `rd | wr = cpu_dc_stb`.
- `zap_core` uses `i_data_wb_ack` only in
  `data_stall = o_data_wb_stb & o_data_wb_cyc & ~i_data_wb_ack`.
  The idle ACK term requires `!(rd | wr)` and therefore cannot affect an active
  CPU stall. The D-cache permanently disables the adapter's instruction fast-hit
  input, so its demand term has no combinational `active_maint` dependency.
- D-cache translation retention, checked-request history and lookup resynchronizing
  still consume the unchanged `o_ack`; their unqualified idle semantics remain.
  TLB walking/holding, cache data, fault metadata, background ports and bus
  ownership/ACK routing are unchanged. Memory-stage result/abort/clear controls
  see the same data-stall clock, and CP15 still consumes the original clean/invalidate
  done signals. No completion register or extra pipeline cycle is introduced.

This removes the redundant maintenance-idle path from the global stall input
locally, without postponing stall assertion or releasing a request before its
result is ready. It targets the162 pass15 maintenance-origin endpoints while
leaving the existing high-fanout stall distribution itself unchanged. A new fit
must establish the mapped path, fanout and timing result.

`tests/cpu/demand_completion/sim.sh` checks the retained ACK against the original
expression and demand/stall equivalence over4741 clocks, including waited
read/write transfers, fault/TLB combinations, exact-once clean/invalidate,
lockdown and reset. Its bus model follows the enclosing ZAP mux's accepted-request
boundary; an initial direct combinational ACK-from-STB model caused a simulation
convergence loop and was corrected in the fixture (no hardware fix was needed).
The full CPU fixture additionally compares new demand ACK with original ACK on
every strobed transfer and verifies original-vs-new global stall each clock.
Combined verification completes122 PASS plus1 expected legacy direct-map XFAIL;
actual CPU phone integration and synthesis-path lint pass. Fresh real-SDRAM5M
boot is byte-identical to pass15's881-event board trace, including all121 writes
and12 known fetch faults (zero data faults). See status.md and
`scratch/timing-closure/pass16-cpu/validation-summary.json` for the retained evidence.

## Verification and limits

```sh
make sim-compat             # All focused acceptance checks must pass
make sim-unmodified         # Reproduce the two original CPU compatibility gaps
make sim-upstream-patched   # Original ARM32 and Thumb regressions, patched CPU
make sim-upstream           # Original regressions, unmodified source
make sim-rtl-lint           # ARM64 Verilator syntax check, SYNTHESIS paths
```

The focused acceptance suite and original upstream ARM32/Thumb regressions pass
on the patched CPU. The unmodified comparison reproduces the original alignment
and cache-disabled data-translation failures. Synthesis-path lint passes with
ARM64 Verilator; this is not an FPGA resource, timing, or placement result.

ZAP retains its execution pipeline and ARMv5TE-capable decoder; patch0045 adds
one owned operand-acquisition edge before issue. The project default
uses the local ARM920-shaped associative cache adapters; the legacy direct-mapped
configuration remains available for reference tests. Passing these checks does not
establish a complete ARM920T implementation, original Nokia execution timing, or
Symbian compatibility.

## Quartus17 register-read generate declarations

Patch0044 moves the balanced register-file read tree's three genvar declarations
to module scope. Quartus17 rejected the inline declarations in run42468961226
with10170, despite SystemVerilog source selection and successful Verilator lint.
The tree, forwarding and pipeline behaviour are unchanged. The operand oracle
passes17160 cycles, all44 patches reproduce the imported source exactly, and
the compiled-source preflight now catches that specific unsupported syntax.

## Owned operand acquisition before issue

Patch0045 replaces the old issue skid with a two-entry `zap_operand_read` owner.
Registered D indices feed the unchanged four-read FF RF directly; registered bases
feed late issue forwarding. Selected effective writes refresh both slots on every
edge (including holds), with C>B>A collision priority and capture/issue-edge bypass.
Capacity-only upstream stop is independent of current hazard/forwarding. CP15 drain
counts owned packets; the shifter receives issue's own bubble/valid controls.
ALU/S late bypass, physical banks, memory/exception and legacy load locks remain.

This adds one enabled D-to-I edge and preserves warm dependent ADD interval1.
Cached mixed-body costs are small in the measured diagnostic, but the fixed mix
has an11.917% aggregate cycle increase dominated by uncached setup loops. That is
an explicit review trigger, not an accepted universal CPI budget. Exact contract,
cycle tables, reference selection and measured penalties are in
[cpu-operand-stage-contract.md](cpu-operand-stage-contract.md). Physical104MHz
closure/resource cost is unmeasured until the separate whole-project fit.

## Operand commit journal and compact FF reads

Patch0046 preserves patch0045's two-entry ordered acquisition queue and cycle
contract. Indexed RF reads replace the forced masked tree. A shared one-edge
commit-data journal plus per-owner C/B/A selectors keeps both packet bases fresh
without live formatted write data entering queue storage. Issue sees current
writes, previous journal and base in the same priority reduction as all newer
in-flight producers. An invalid reserve may capture accepted packet payload while
its unchanged validity rule prevents replay/promotion; this removes pop/hazard
from reserve word enables. Kill clears both ownership and pending selectors.

See [the operand contract](cpu-operand-stage-contract.md) for the inductive
freshness proof and targeted tests. This is a functional retiming candidate for
physical measurement, not a claim of104MHz closure. No additional pipeline cycle,
clock constraint or other architecture slice is introduced.

## Owned demand completion and registered load formatting

Patch0047 adds the selected associative CPU's `zap_data_completion` boundary:
ACK captures data, abort/retry and FSR/FAR together while P2 stays held; registered
validity releases the pipeline on the next edge and suppresses request replay.
WB-clear/reset gate offers and kill pending completion. Legacy background cache
retains its original completion protocol. The added demand-completion clock is
measured explicitly; warmed dependent ALU throughput remains1.

The same patch moves load formatting before M's existing result register and
captures static source classes with R ownership. Current-edge writes, producer
priority, bank/PC/CPSR behavior and queue capacity/kill semantics stay intact.
See the operand contract for edge ownership, fault/CP15 and test evidence.

## Stationary operand owners and dedicated CP15 RF read (0048)

Patch0048 gives CP15 a fifth asynchronous read mux on the existing40×32 FF
storage. Its registered response and pre-write collision semantics are unchanged;
normalport0 no longer selects CP15's address. CP15 drain/serialization remains.
The two-entry operand queue now stores each packet in a stationary physical bank.
Push captures only the bank selected by `write_slot`; pop selects the next head
with `read_slot` and changes occupancy, without copying wide payload/context.
Each bank continuously folds its own commit journal with unchanged C>B>A priority.
Current-edge writes and newest in-flight forwarding remain unchanged.

The output selector holds its last logical head when empty and through clear.
This preserves bubble-PC observations in the existing BTB, whose feedback-index
invalidation also runs on invalid cycles. A conventional last-pop pointer toggle
was rejected after adding53/77 clocks to the mixed0/3-wait body. Corrected0/3
runs match all baseline phases/counters; a1415-clock warmed schedule and21,118
architectural effects match exactly. The independent oracle checks both physical
owner association and held empty/clear PC. Full validation is recorded in status
and the operand-stage contract. No added pipeline cycle or clock/constraint edit.


## Rejected late owner selection after forwarding priority (0049)

Patch0049 computes source matches and priority grants for both stationary operand
owners before selecting the active owner. It removes the early read-pointer mux
from the measured−1.438ns match/priority path. The RF fallback is an explicit
17th grant resolved before selection; one wide forwarding datapath remains shared.
No new state, stage, hazard rule, write priority or cycle is introduced. Per-owner
mask/grant checks reconstruct captured indices, classes and current/previous write
events independently; existing architectural/cycle and fresh-boot checks remain.
The operand contract records proof, validation and the area/fanout fit risks.

Fit42520603079 regressed timing despite functional equivalence. Patch0049 is
archived under `patches/zap/rejected/`, removed from active provenance, and its
RTL reverted exactly to patch0048. The independent directed collision scenarios
remain valid and retained; mask observers tied to removed internals are removed.
Active ARM provenance is48patches. Revert is a new commit; history/evidence remain.


## Owned cache lookahead context (0050;49 active patches)

Patch0050 changes only the associative I-cache wrapper's lookahead offer: four
ARM words ahead, independent of current ACK, with fast-path cancellation on MMU/
permission/cache context changes. Its registered L0 owner, one-hot segment reads
and token epochs live in maintained `rtl/arm920` modules. No extra lookahead
register is added before L0. Active provenance applies0001–0048 then0050;
rejected0049 remains archived, not reapplied. See the cache lookup contract for
acceptance/response association, precise latency measurements and validation.

## MLAB register file (0057)

Two writer banks replicated for five asynchronous reads replace the FF read
muxes. Held and committed bypass preserves the original write/read edge and
masks undefined RAM collisions; reset invalidates metadata, not physical RAM.
Generic C multi-bit writes/priority and architectural debug taps remain. Explicit
Intel altdpram wiring is checked against the installed model; unsupported donor
sclr/outdata_sclr settings are omitted. Independent five-port, CP15/operand,
whole-core cycle/effect and IRQ/FIQ evidence is in
[RF audit](register-file-area-audit.md). Verilog-2001; no new CPU cycle or clock
change. Actual area/routed timing is pending the next build.

## Direct checked translation owner (0058)

D-cache now consumes TLB's exact checked-owner predicate rather than selecting
checked VA/context fields and comparing them back to the request. No extra
cycle, permission change or token-granularity change; the original conjunction
remains as a simulation equivalence assertion. The associated maintained ARM920
backend changes register SWP ownership before bypass bus issue and select fast
instruction words before the late line-source selector. See
[78 MHz audit and tests](timing-78-recovery.md). Physical closure remains open.

## Thumb LDM loaded-base preservation (0059)

Suppress implicit writeback for Thumb LDM when Rn is in its load list. The
old unconditional writeback corrupted a native GLES allocator offset and
caused SPMark FillRate's unmapped64-byte fill. STM and base-absent LDM retain
writeback; ARM decoding is unchanged. No new state, RAM or pipeline stage.
Original C903/1845 replay fails on old RTL and passes on corrected production
CPU at delays0/3; exhaustive4096 decoder and3311 independent defined-ISA oracle
cases pass, alongside ARM LDM and throughput controls. Hardware/fit qualification
pending. See [exact witness and limits](spmark04-benchmark.md).
