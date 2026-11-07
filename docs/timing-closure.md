# MiSTer timing closure

## Third measured result; registered bus iteration (2026-11-07)

Completed **42379146118 / cc89013** fits but fails setup. Reports:
`scratch/timing-closure/pass3-cc89013/`. CAM change saves area but does not
improve timing in this fit:

| Metric | Before CAM 4040395 | After CAM cc89013 |
| --- | ---: | ---: |
| Core setup slack at 104 MHz | -9.582 ns | **-10.644 ns** |
| Core slow-model Fmax | 52.09 MHz | **49.36 MHz** |
| Core setup TNS | -117903.504 ns | **-123805.311 ns** |
| ALMs | 33,857 | **33,589 (80%)** |
| Registers | 45,783 | **45,643** |
| M10Ks | 457 | **457 (83%)** |

Setup regresses 1.062 ns / 2.73 MHz, while ALMs fall 268. Worst other reported
metrics: hold +0.249, recovery +2.639, removal +1.088, pulse +0.961 ns. Keep
the functional CAM simplification for the next structural experiment; do not
claim it closed paths. The worst path starts in timer/peripheral logic and
passes shared claim/ACK into SIM FIFO space/address logic (20.103 ns max data).

Actual detailed-path coverage: **946/1,000** traverse shared fault/ACK;
**912/1,000** continue through CPU/cache next-request combinational logic after
that predicate. These 912 cross the response boundary being registered.
**36** paths involve SIM FIFO and **727** traverse sparse lookup; these are
traversal groups, not disjoint totals or promised timing passes. The worst
shared ACK -> SIM FIFO path is not removed in full by a CPU response register.
SIM multiwrite address/bypass logic is a clear follow-up after measuring this
isolated change. No SIM protocol/queue change is mixed into this iteration.

User authorized option 2 after measurement. `ngage_upp_bus_bridge`, a leaf
module in the existing `rtl/ngage_upp.v`, is enabled in the internal-CPU branch.
The external-master test interface retains its behavior. Existing QIP already
includes this file; no new source dependency or Quartus source entry is needed.
This is an explicitly transaction-level UPP integration boundary, not a claim
about physical Nokia bus pins, clocks or wait-state configuration.

One outstanding classic beat follows IDLE -> ACTIVE -> RESPONSE -> IDLE.
Request address/data/mask/write/code are captured before downstream decode.
Downstream ACK/error/data are captured before CPU completion. Downstream
requests drop during RESPONSE, so side effects commit once on successful
ACTIVE completion and cannot repeat while the CPU receives the delayed ACK.
Error wins over simultaneous ACK/error. Reset masks/cancels request and response;
CYC withdrawal cancels an unfinished request. Upstream response does not depend
on CPU STB, avoiding ZAP's combinational STB suppression on ERR. The production
master's contract remains holding CYC through completion except on shared reset;
non-reset cancellation is not a target-controller flush/recovery protocol.
SWP LOCK remains
direct from the CPU and spans response/idle bubbles; it is not tied to ACTIVE.

This adds external-access latency (two extra edge intervals for an isolated
immediately acknowledged beat), affecting **memory misses/uncached traffic as
well as MMIO**. Warm cached execution remains one ADD per clock in the measured
CPU test. Timer/RTC/SDRAM clock rates, firmware and SDC exceptions are unchanged.
A fresh simulator lineage is required; old frozen checkpoints are untouched.

Validation: focused 200-beat bridge test checks zero/variable waits, captured
fields/data/errors, back-to-back beats under continuous CYC, exact-once writes,
CYC cancellation and reset during wait/response. CPU tests can exercise this
same bridge with `CPU_BUS_BRIDGE=1` in `tests/cpu/core/sim.sh`; this is opt-in
bench wiring and does not alter the standalone CPU module. Run
`sh tests/phone/upp_bus_bridge/cpu.sh` for the focused CPU matrix and
`sh tests/phone/upp_bus_bridge/run.sh` inside the simulator image for the bridge
unit test.

The bridge tests, warm timing, SWP/basic/cached/bufferable and DMA competition,
IRQ/FIQ, read/write/IRQ aborts, cache refill/writeback interrupts, alignment,
cache external abort and SDRAM-adapter SWP checks pass at memory delays 0/3.
Integrated ARM board/SIMIF/LCD DMA/fault/IRQ/FIQ/SDRAM-wait checks and synthesis/
structural lint pass. Fresh cold 5M smoke: modeled memory PC **00006164**, 328479
bus transfers, 12 fetch faults, zero data faults; actual SDRAM-controller/Micron
model PC **00006160**, 326761 transfers, 12 fetch faults, zero data faults.
Both have no LCD yet. Different fixed-cycle PCs/counts reflect the changed
latency; they are not an instruction-by-instruction equivalence claim.

Logs: `scratch/timing-closure/pass4-bridge/`. Next compile must measure new
slack/Fmax/resources and remaining path groups against **49.36 MHz / -10.644
ns**. User monitors the build; do not poll it. Registering CPU responses is not
physical timing closure until measured, and external SDRAM constraints still
need their separate board-validation work.

## Third iteration: sparse CAM/full split (2026-11-07)

User selected candidate 1, then one measurement build; candidate 2 (registered
bus boundary) must wait for those results. `ngage_sparse_regs.v` now derives
full directly from `req && we && !any_hit && all_valid`. The shared fault/ACK
predicate no longer depends on encoded signed-integer hit/free indices.
Independent balanced lowest-index trees select the hit and free slots for
payload and tag writes. Padding leaves are absent in both trees for non-power-
of-two capacities. Each tag/valid slot has a fixed write enable, preserving
lowest-free allocation without a dynamic integer-index write.

Payload remains the same byte-enabled M10K, with the same address width, reset,
new-word zeroing, hit-byte merge and synchronous read latency. Full tables can
still update existing addresses and must refuse unrelated new addresses.
No bus pipeline, timing exception, PLL/clock/timebase or firmware change.

The original sparse-store test and a new independent queue/table scoreboard
cover capacities 1, 2, 3, 5 and 64; full-table updates/refusal; all byte masks;
full address identity; lowest-free allocation; read latency; reset; and
withheld requests/commits. Same-address mixed-port RAM collision data remains
unspecified, so the scoreboard checks those updated bytes on subsequent reads.
Each capacity receives 4,000 randomized cycles plus directed fill/update/read.

Validation and new physical timing results are recorded in `status.md`.
Compare the next build against **52.09 MHz / -9.582 ns / 33,857 ALMs / 457
M10Ks**, then decide the registered-bus experiment from the measured paths.
Do not attribute all 929 prior traversals to proven timing passes.

## Second measured result and decision point (2026-11-07)

Completed **42375426237 / 4040395** fits and fails only the required timing
step. Reports: `scratch/timing-closure/pass2-4040395/`. No new RTL or build
was requested at this review/decision point.

| Metric | Baseline 697f598 | First 2bcac9d | Second 4040395 |
| --- | ---: | ---: | ---: |
| Core setup slack, 104 MHz target | -43.702 ns | -10.023 ns | **-9.582 ns** |
| Core slow-model Fmax | 18.76 MHz | 50.92 MHz | **52.09 MHz** |
| Core setup TNS | -215405.214 ns | -138677.094 ns | **-117903.504 ns** |
| ALMs | 33,832 | 34,214 | **33,857 (81%)** |
| Registers | 44,523 | 45,346 | **45,783** |
| M10Ks | 457 | 457 | **457 (83%)** |

Last step gains 0.441 ns worst setup slack / 1.17 MHz Fmax (~2.3%); TNS
magnitude falls ~15%. It saves 357 ALMs and adds 437 registers. All 1,000 newly
selected paths still fail. Other worst metrics remain positive: hold +0.184,
recovery +3.721, removal +0.952, minimum pulse +0.961 ns. HDMI setup is only
+0.079 ns on its own clock; do not overlook this small margin in future fits.

**969 prior paths traversed code we changed, not 969 paths guaranteed fixed.**
The new worst path still ends at SIM FIFO address capture, but now starts at
shared WB address bit 17 and goes through sparse-register lookup/full logic,
shared unmodeled/ACK, then SIM pop/space checks and FIFO address/write muxes.
The representative CPU feedback path continues from sparse decode/fault ->
WB ACK -> instruction-cache next state -> merger address mux -> sparse CAM.
**929/1,000 detailed paths traverse both sparse CAM and shared unmodeled.**
Maximum data delay in this subset is 18.536 ns, versus a 9.615 ns core period;
small local decode changes alone are unlikely to close every such path.

Concrete candidates, pending user selection:

1. **Sparse CAM lookup/full split (small, preserves latency).** Current
   `ngage_sparse_regs.v` priority-encodes hit/free indices into integers and
   derives full from their signs. Derive full directly from any matching tag
   and all-valid bits; select hit/free indices with a balanced lowest-index
   tree. Preserve exact address identity, allocation order, byte merge/zeroing,
   full-table refusal and synchronous payload latency. Test full-table update
   versus new-address refusal, reset, duplicate-free allocation and multiple
   sizes including non-power-of-two. This directly targets the newly dominant
   shared ACK predicate, but may leave the bus feedback and SIM tail long.
2. **Registered phone-bus request/response boundary (larger, structural).**
   Capture the CPU request, decode held fields, commit downstream side effects
   once, latch data/error and return a registered response. Keep response paired
   with its request across waits and reset; retain SWP lock across bridge gaps.
   This cuts the decode/ACK/next-request/decode chain. It adds external-access
   latency, so rerun CPU/cache/abort/SWP/interrupt, board and cold firmware
   checks, checking that warm cached ADD throughput stays one per clock.
   Topology needs a deliberate change at ngage_upp/ngage_mister bus ownership;
   registering ACK alone while repeatedly committing a held request is wrong.
3. **SIM FIFO write path (remaining endpoint cost).** Even after /25 serial
   increments were removed, multiple immediate byte writes still create FIFO
   address/bypass muxes after occupancy checks. Consider a staged packet writer
   or banked queue with explicit availability/busy semantics, tested against
   the full SIM byte reference and concurrent-pop/saturation behavior. Treat
   changed response visibility as a protocol change, not an equivalent rewrite.

Suggested order: try the focused CAM/full split as a small measured iteration;
then add the registered bus boundary if feedback remains dominant. Expect that
reaching 104 MHz can require both and expose new paths outside this 1,000-endpoint
subset. Slower physical flash/MMC/SIM clocks are separate evidence, not grounds
for relaxing these CPU-domain paths. Timer-rate correctness can proceed as a
separate experiment after the current decision; it does not itself fix setup.

## Measured first result and second optimization (2026-11-07)

Completed run **42372012944 / 2bcac9d** fits and exports reports correctly;
CI fails at the intended timing gate. The summary permission fix works.
Reports: `scratch/timing-closure/pass1-2bcac9d/`.

| Metric | Baseline 697f598 | First optimization 2bcac9d |
| --- | ---: | ---: |
| Core setup slack at 104 MHz | -43.702 ns | **-10.023 ns** |
| Core slow-model Fmax | 18.76 MHz | **50.92 MHz** |
| Core setup TNS | -215405.214 ns | -138677.094 ns |
| ALMs | 33,832 (81%) | 34,214 (82%) |
| Registers | 44,523 | 45,346 |
| M10Ks | 457 (83%) | 457 (83%) |

Worst reported hold +0.219 ns, recovery +3.961 ns, removal +0.930 ns and
minimum pulse width +0.961 ns remain positive. This is **still a failing
104 MHz design**; Fmax alone does not certify the board/external interfaces.
All newly exported 1,000 setup paths still fail (the selected endpoints change
as bottlenecks improve). Worst data delay is now 19.178 ns, maximum depth
18 levels in this subset; worst endpoint slack -10.023 ns has 17 levels.

The previous report's 152 SIM endpoints, 466 cache-tag endpoints and 312
write-buffer-hazard traversals formed 930 distinct affected paths. Those are
structures touched, not 930 timing passes. The measured improvement above
is the result of that combined change and placement, not per-fix attribution.

**Second optimization:** 969 of the new 1,000 detailed paths traverse boot
register `Selector`/`Mux` logic before shared `unmodeled`/ACK, then reach SIM
FIFO, CPU request generation and sparse CAM/other peripheral endpoints. The
boot module encoded an address into an integer index and selected validity
from 11 boot/45 scratch words (including subtraction for scratch indexing).
Replace this with constant address comparisons, parallel per-latch validity
checks, fixed per-latch writes and a balanced OR tree for read data. Preserve
all addresses/holes, byte-valid read faults, mask behavior (boot masked,
scratch whole word), zero-reset register 0x08000040, commit gating and latency.
Storage stays registers; this pass does not claim another BRAM conversion.

Validation: original boot test and a new independent 12,000-cycle scoreboard
exercise all 56 latches, all masks, unaligned aliases, holes, absent requests,
withheld commits and reset. Integrated ARM board and fresh cold 5M smoke pass
at unchanged PC 00006178, 18 known speculative fetch faults, zero data faults;
shared RTL lint passes. New fitted timing/resource effect is pending CI.

The user also requested the phone's actual slower buses/timebases. ARM920T
has separate fast CPU/bus clock modes, and Nokia documents several slower
reference/pin clocks. See `phone-clocks.md` for primary evidence, current
model assumptions and the registered peripheral bridge investigation. Do not
infer all phone blocks run at 104 MHz, or relax today's paths merely because
the corresponding physical serial interface is slower. No PLL, SDC, CPU clock,
timer rate or firmware change in this optimization.

## First path-driven optimization (2026-11-07)

Run **42368700686**, source **697f598**, successfully exported the full 1,000
paths. Local artifact: `scratch/timing-closure/baseline-697f598/`. All exported
setup paths fail. The report script works with real Quartus 17; the subsequent
host summary failed with `PermissionError` because Docker created its output
directory as root. CI now creates `output_files/timing` as the runner before
starting Quartus. The timing gate remains enabled.

Measured baseline groups (one worst path per endpoint):

| Path group | Endpoints | Worst slack | Longest data delay | Maximum logic levels |
| --- | ---: | ---: | ---: | ---: |
| LCD DMA -> SIM FIFO address/control | 152 | -43.702 ns | 52.857 ns | 37 |
| Cache access -> sparse registers | 158 | -28.092 ns | 36.906 ns | 23 |
| Cache access -> boot registers | 42 | -26.917 ns | 35.696 ns | 25 |
| Cache tags -> cache tags | 464 | -19.285 ns | 28.101 ns | 16 |

The worst detailed path starts at `lcd_dma.source[2]`, passes through the DMA
range check, shared `wb_ack`, SIM pop accounting and a long sequence of SIM
`Add*` nodes, then reaches the inferred FIFO write address. The SIM `emit` task
previously advanced tail/occupancy after every byte, serializing as many as
25 conditional increments in one clock. It now uses offsets from the original
tail and parallel room checks, then caps the accepted response length and
updates occupancy/tail once. The byte protocol, immediate response visibility,
simultaneous pop-before-enqueue, saturation and sticky overflow are preserved.
This is still a multiwrite response queue; no new single-port BRAM claim is made.

Rank 113 starts at the data write-buffer head, passes through rotating queued
address/length selection, `query_line_pending`, cache bus eligibility and the
Wishbone merger before reaching the sparse CAM. Hazard detection now compares
the four physical slots in parallel and qualifies each by its distance from
head. It still includes already-retired words within a live group conservatively
and handles groups crossing a cache-line/address-wrap boundary.

The cache tag loop's lowest-way priority is expressed as a balanced six-level
tree instead of serial `!hit` selection. Lowest matching way, associated dirty
bits, no-hit outputs, synchronous BRAM reads and lookup latency are unchanged.

**These are structural RTL fixes, not measured timing closure.** Keep 104 MHz,
timer constants, SDRAM configuration, firmware and timing constraints unchanged.
Compare the next fitted 1,000 paths, Fmax, slack, ALMs and M10Ks before choosing
further changes. Remaining candidates include the cache/Wishbone request and
response boundaries and sparse CAM selection; the current artifact does not
establish how much each change improves the next fit.

Validation passes: SIM C++ fixture and absent/present board comparison, new
600-response FIFO scoreboard, cache tags/bank/access, write-buffer ordering and
all-head-position/address-wrap hazard checks, integrated ARM board test, CPU
warm ADD timing at memory delays 0/3, fresh cold 5M-cycle hardware-bound smoke
(PC 00006178, known 18 speculative fetch faults, zero data faults), shared RTL
lint and seven timing-tool tests. These simulations do not model physical
setup/hold failures; the next Quartus build supplies that evidence.

## Observed baseline and current scope

Completed build **d068883**, action **42365167112**, fits the device but fails
setup timing: **-43.702 ns** core-clock slack, **18.76 MHz** reported Fmax,
**-215405.214 ns** setup TNS. The PLL is still **104 MHz**. Resource use is
33,832/41,910 ALMs and 457/553 M10Ks. Reports are retained locally under
`scratch/hardware-bringup/build-d068883/`.

That artifact contains aggregate STA panels but no detailed critical paths or
fitted database. Node-level launch/capture/routing paths cannot be reconstructed
from the summaries alone. A new post-fit analysis must run while the database
still exists on the GitHub runner.

The user explicitly chose to **keep 104 MHz unchanged** for the next baseline
and request the worst **1,000** paths. The earlier 50 MHz proposal is deferred.
No PLL, clock frequency, timer, SDRAM mode, RTL, SDC or timing exception changed
in this reporting step. Do not attribute the failure to a particular CPU/cache
or debug block before inspecting the actual paths.

## Build artifacts

After normal Quartus compilation the action runs:

```sh
quartus_sta -t tools/report_quartus_timing.tcl Template 1000
python3 tools/summarize_quartus_paths.py output_files/timing/worst-setup.csv \
  --output output_files/timing/path-summary.md
python3 tools/check_quartus_timing.py output_files/Template.sta.rpt
```

The `quartus-logs` artifact always includes `quartus_timing_details.log` and
`output_files/timing/`, even when the timing gate fails. Main outputs:

| File | Contents |
| --- | --- |
| `worst-setup-full.rpt` | Worst 1,000 slow-model setup paths, full launch/capture clock paths, cells and detailed routing |
| `worst-setup.csv` | Rank, slack, data delay, logic levels, source/destination clocks and complete node names |
| `path-summary.md` | Group counts/worst slack by source/destination block and ten worst node pairs; also shown in action summary |
| `hold-slow-full.rpt`, `hold-fast-full.rpt` | Worst 100 hold paths in each model, with routing |
| `recovery-slow.rpt`, `removal-slow.rpt` | Worst 25 reset/asynchronous recovery/removal paths |
| `clocks.rpt`, `fmax-slow.rpt` | Derived clock identities/periods and slow-model Fmax |
| `unconstrained-slow.rpt` | Unconstrained interfaces/paths, kept visible for follow-up |

The setup selection uses `-npaths 1000 -nworst 1`: the worst path to each of
up to 1,000 distinct endpoints. This spreads analysis across many bottlenecks
rather than spending all rows on alternate routes to one register. The text
report and CSV use the same selection. No full path dumps are printed to chat
or the action console; detail stays in the artifact.

The report script analyzes the existing post-fit netlist with normal slow/fast
models. The original compile's multicorner `.sta.rpt` remains the timing-gate
input. Changing or omitting constraints is not a timing fix.

## Timing gate and limits

Quartus can exit successfully and generate an RBF despite a timing failure.
The new gate rejects `Timing requirements not met`, any negative reported
setup/hold/recovery/removal/minimum-pulse slack, and missing metric summaries.
It runs **after** detailed reports are generated. A failed-timing run is
therefore expected to be red while still providing its timing artifact.
Normal RBF upload requires this gate to pass.

This gate checks reported **constrained** timing. It does not certify the
unconstrained external SDRAM/other IO paths. The current interface constraints
still need evidence-backed board-delay work; no false paths, multicycles or
asynchronous-clock exceptions were added to hide them. See
`sdram-104mhz-ddio.md` for that separate hardware gate.

Local verification: `python3 tests/timing/test_tools.py` checks positive,
negative, incomplete and contradictory timing reports, rejects the actual
failed board report, and exercises CSV ordering/grouping/escaping. A mocked
Tcl API validates control flow/output handling only, **not Quartus semantics or
physical timing**. No local Quartus installation/download is used. Real API
execution and the measured paths require the GitHub build.

After obtaining the artifact: group the 1,000 paths, inspect logic depth versus
routing and shared fan-in, identify the real critical structures and make a
measured RTL change. Run the relevant CPU/chip/video regressions and compare
new STA, resources and hardware behavior. Keep each RBF paired with its source
and timing reports. The user monitors new builds; do not watch/poll the action.

Quartus 17 command references:
[report_timing](https://resources.altera.com/quartushelp/17.0/tafs/tafs/tcl_pkg_sta_ver_1.0_cmd_report_timing.htm),
[get_path_info](https://resources.altera.com/quartushelp/17.0/tafs/tafs/tcl_pkg_sta_ver_1.0_cmd_get_path_info.htm),
[report_ucp](https://resources.altera.com/quartushelp/17.0/tafs/tafs/tcl_pkg_sta_ver_1.0_cmd_report_ucp.htm).
