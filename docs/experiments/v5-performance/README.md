# V5 performance experiment library

Each entry records an exact base, a Git patch and the observed outcome. The
patches include the changed RTL or simulation source, the canonical phone
generator when used, and the checked-in tests that accompanied the measured
revision. The [manifest](manifest.json) records full commit IDs, patch SHA-256
values and the checks for each stack. This archive contains source patches
and references to test evidence. Benchmarks use separately acquired local
firmware, game captures, pin models and simulator outputs.

## Reapply and verify

Check an entry with `python3 docs/experiments/v5-performance/verify.py ID`.
Omit the ID to verify the whole catalog. The verifier uses a private index and
object directory under `scratch/`, compares affected blobs to the measured
commit where one exists, and checks recorded RTL hashes for simulation-only
variants.

For example, from the repository root:

```sh
stage=scratch/v5-replay-refill
mkdir "$stage"
git archive 739d3bd | tar -x -C "$stage"
git apply --check --directory="$stage" docs/experiments/v5-performance/patches/refill-m10k.patch
git apply --directory="$stage" docs/experiments/v5-performance/patches/refill-m10k.patch
(cd "$stage" && mkdir -p build/sim && sh tests/cpu/arm9v2_board/run-refill-ram.sh replay-refill)
```

For generated CPU variants, use `tools/gen_arm9v2_phone.py --stock <pinned
donor netlist> --check` within the staged tree. The pinned donor SHA-256 is
`087714b2a692fb949bf8a0586674742118383eb18452f1357c4b4e786a69ab4c`.
The generator can also build from the imported SystemVerilog with its pinned
sv2v version. Historical paired-LDM variants use their original generator
invocation. See [the generator notes](../../arm9v2-phone.md),
[the historical catalog](historical.md) and
[the recovered early backend prototypes](historical.md#early-backend-simulation-variants).

## Storage and the all-four control

The matched physical fits in this section run at 104 MHz with 16 KiB I and D
caches, DDR debug disabled, and seeds 43, 13 and 31337. Setup is the median
of the worst path at each seed over four corners. The ALM column is whole-core
fitted area. The original storage variants matched fixed-work cycles and
native output, and the all-four combination matched the mixed LCD, PCM and
MMC replay. The [storage report](../../v5-alm-storage-results.md) links seed,
path and RBF provenance.

| Experiment | Measured source and replay base | Design and verification | Fitted result |
| --- | --- | --- | --- |
| [UPP RAM in HPS DDR](patches/upp-ddr.patch) | `61d51fe` from `87b076a` | Replaces two UPP backing banks with reserved DDR. Cold reset clears both banks and warm reset drains and retains them. Tests cover byte lanes, SWP, reset, DDR transport and board glue. [Qualification](../../peripheral-ram-ddr-assessment.md#integrated-ddr-backing) | Frees 128 M10Ks, leaving 310 used. Median 37,931 ALMs, −2.919 ns. |
| [Return-address stack](patches/ras-m10k.patch) | `0965372` from `29479fe` | Moves eight return links behind the existing registered top. Call forwarding preserves the pop and repair edge. Runs `tests/cpu/arm9v2_ras/run.sh`, with 129,126 differential edges per configuration. | 37,849 ALMs, 311 M10Ks, −2.907 ns. All three matched seeds improve. |
| [MMC stream-cache tags](patches/mmc-stream-tags.patch) | `341a454` from `0965372` | Three RAM copies serve current, next and prefetch tag reads. The four associative metadata tags stay in logic. Forwarding covers mixed-port collisions. The pin and HPS fixtures cover remount, write invalidate and EOF. Runs `tests/phone/mmc_card/run-stream-tags.sh`. | With the stack, 36,961 ALMs, 314 M10Ks, −3.350 ns. Lowest median area of the initial storage series. |
| [Posted-store FIFO](patches/posted-store-queue.patch) | `5700837` from `341a454` | Parity banks prepare both head and successor, with one 68-bit pushed-packet hold for collisions. Differential test covers 251,347 production-depth clocks. The ordered CPU contract checks mixed byte enables, dependent refills and drain. Runs `tests/cpu/arm9v2_store_queue/run.sh` and `run-ordering.sh`. | 37,451 ALMs, 318 M10Ks, −2.706 ns. Seed 31337 reached −2.591 ns. |
| [Fetch queue](patches/fetch-queue.patch) | `d127eb3` from the source-equivalent `341a454` | Moves the eight 112-bit fetch payloads behind the existing head, retaining broadcast fill status in logic. The historical `dc1903f` implementation is reused exactly. Runs `tests/cpu/arm9v2_board/run-fetch-ram.sh`, including 8,504 differential clocks. | 37,481 ALMs, 317 M10Ks, −2.973 ns. |
| [All four together](patches/all-four.patch) | `739d3bd` from `29479fe` | Installs stack, stream tags, fetch and posted writes as one source delta. All four directed tests, 15 fixed workloads, four native frames and the mixed replay passed. | 37,364 ALMs, 321 M10Ks, −2.851 ns. |

The posted-only and fetch-only patches each start at the same stack-plus-MMC
base. Applying the components in stack, MMC, fetch, then posted-store order
reproduces the affected blobs of `739d3bd`. The all-four patch provides the
same source in one application.

## Independent bank substitutions

Each patch below starts from the all-four source at `739d3bd`. Under the
original sequence the intermediate inverse commits restored the compiled
source before the next trial. All four individually matched the 15
fixed-work request traces, four native frames and mixed replay, and missed
104 MHz setup in all three fits. [Directed checks and source identities](../../evidence/v5-104-bram-mix-qualification.json) · [Timing and area](../../evidence/v5-104-bram-mix-fits.json)

| Experiment and measured commit | Design and directed test | Median ALMs / M10Ks / worst setup |
| --- | --- | ---: |
| [CPU refill words](patches/refill-m10k.patch), `13a471b` | Odd/even four-word banks accept both halves of a wide beat. Pre-read and bypass preserve first-word and streaming ACKs. `run-refill-ram.sh` checks ordinary and forced-unknown collisions, narrow and wide beats, rejection fallback, errors and reset in flight. | 36,166 / 323 / −2.895 ns |
| [ICU probe latches](patches/icu-probe-m10k.patch), `fa1b2f1` | Places five byte-writable words in existing low ICU block RAM. Early lookup and warm-reset scrub preserve the response and zero contract. `tests/phone/register_ram/run-probe.sh` checks 8,330 cycle comparisons, masks and pre-unlock cancellation. | 36,304 / 321 / −2.932 ns |
| [MMC host byte FIFO](patches/mmc-host-fifo-m10k.patch), `d790e96` | Four byte banks preserve aligned and wrapped four-byte access, with prefetched payload and collision forwarding. `tests/phone/mmc_host/run-fifo.sh` covers wrap, masks and simultaneous host/card operations. Seed 13 is the best single fit in this group at −2.713 ns. | 37,079 / 325 / −2.980 ns |
| [I/D small-page TLB victims](patches/tlb-victims-m10k.patch), `723e2b7` | Each active 256-set two-way TLB packs its victim bitmap into 16 RAM rows. First-touch clear uses resettable row-valid flags. The existing walk capture and write-through keep the victim edge. `run-tlb-victim.sh` checks 53,523 victim clocks and two 7,765-clock full-walker legs. | 35,645 / 323 / −3.088 ns |

## Data admission, data return and Thumb recovery

| Experiment | Exact base and patches | Observed result and qualification |
| --- | --- | --- |
| Stage D-cache **line admission** one clock later | `739d3bd`. [Simulation RTL](../../evidence/v5-104-d-refill-admission-sim.patch) · [Bench and replay](patches/refill-pair-and-admission-fixture.patch) | One executable uses `+delay_d_refill` to hold the D-line offer and save its address. Scalar and I-line admission stay direct. The directed fixture checks first and following ACK spacing. Native frames cost 30,030 clocks (+0.0522%), Sega scan +5,101 (+0.213%) and full-frame 16-bit fill +176 (+0.144%). Routed setup is open. [Per-case evidence](../../evidence/v5-104-d-refill-admission.json) |
| Register D return from buffered words | `739d3bd`. [Buffered implementation](../../evidence/v5-104-d-return-buffered.patch) · [Directed test](../../evidence/v5-104-d-return-tests.patch) | Registers valid, error, terminal, trust and data for D-line replies. Reading from the completed buffer introduces an edge. Native cost +0.057%, Sega scan +0.216% and full-frame 16-bit fill +2.834%. The 400-case directed fixture checks the delayed control. Simulation qualified, with no routed fit. [Comparison](../../evidence/v5-104-native-d-line-return.json) |
| Capture D return on the arriving beat | `25e1208` from `739d3bd`. [Same-edge implementation](../../evidence/v5-104-d-return-same-edge.patch) · [Directed test](../../evidence/v5-104-d-return-tests.patch) | Keeps the response register and feeds the completing narrow word, selected wide-beat half or an already buffered word. First and following ACKs retain their existing edge. All checked cycles, request traces and mixed replay match. Median 36,401 ALMs, 321 M10Ks and −3.242 ns. The old ACK/beat-select path disappears from the named seed-13 export, and the whole-core limit moves to the scheduler. [Fitted evidence](../../evidence/v5-104-d-return-thumb-fits.json) |
| Reuse the checked upper Thumb halfword | `27bd8bf` from `739d3bd`. [Implementation](../../evidence/v5-104-thumb-fallthrough.patch) · [Exact fitted tests](patches/thumb-fallthrough-fit-tests.patch) · [Original simulation tests](../../evidence/v5-104-thumb-fallthrough-tests.patch) | Saves a 47-bit record and inserts it on the winning registered fall-through correction. Handshake, ISA, cache, interrupt and context guards preserve the original repair. Sega scan saves 18,261 clocks (0.762%), while all other checked cycles tie. With simulated D admission the scan still saves 13,419 clocks vs base. Median 37,126 ALMs, 321 M10Ks and −3.083 ns. Predictor validity gains a recovery-dependent path. [Four-way evidence](../../evidence/v5-104-thumb-recovery-stage-comparison.json) · [Fitted evidence](../../evidence/v5-104-d-return-thumb-fits.json) |
| Prepare normal and recovered predictor validity in parallel | `f7d5746` from `27bd8bf`. [Parallel validity and test](patches/thumb-parallel-valid.patch) | The measured parent `e86bd00` recreates the original Thumb source and directed tests. Samples both validity choices, including same-edge forwarding, before selection. A 30,006-clock differential and all workload checks matched Thumb. Median 36,977 ALMs, 321 M10Ks and −3.130 ns. The former local endpoint improves and the median whole-core path moves elsewhere. [Fitted evidence](../../evidence/v5-104-thumb-parallel-valid.json) |
| Launch the ordinary redirect independently of queue rescue | `e6c352c` from `27bd8bf`. [Implementation and extended test](patches/thumb-ordinary-redirect.patch) | The redirect and BTB always launch the actual upper-half PC. Two stage bits mark the duplicate so it cannot predict, enqueue or retry after the head already received the checked halfword. The 213-clock fixture covers changed ownership, wrong-path faults and held duplicates. Fifteen workload outputs, four native frames, ordered data/MMIO and mixed replay match. The extra lookup gives up almost all Sega gain: 2,395,766 clocks versus 2,377,506 with original Thumb and 2,395,767 on all-four. Median setup was −2.974 ns, 0.123 ns behind all-four, with 705 fewer median ALMs and the same 321 M10Ks. Preserve for an area-constrained combination. [Functional replay](thumb-ordinary-redirect-replay.json) · [Routed evidence](../../evidence/v5-104-thumb-independent-redirect-fits.json) |

The two registered D returns are alternative implementations. The refill RAM
conversion, D admission trial and D return trials share the wrapper. Merge
overlapping changes deliberately and repeat first-word, collision, stall and
full-workload checks on the combined source. The manifest includes clean
source-level stacks for the four later BRAM conversions, original Thumb
with either predictor alternative, Thumb plus the same-edge D return, and Thumb plus
simulated D admission. Measurements belong to the separately recorded legs.
The two Thumb predictor alternatives each start at the original Thumb variant.
Their combined behavior has no measurement. The Thumb and D admission
combination has its own 15-case and native replay.
[Four-way replay fixture](patches/thumb-and-d-admission-replay-fixture.patch)

## DDR burst bounds

The [final-window check](ddr-burst-bounds.md) replaces the wide end-address
adder on the all-four control. All 15 fixed workloads and four native
PolyCount frames match cycle for cycle. The three 104 MHz fits at
`b6d8981` removed the sector carry chain from the reported result paths
and improved those endpoints at both slow corners on all three seeds.
Whole-core median setup moved from −2.851 to −2.978 ns. Seed 13 reached
−2.742 ns. Keep the DDR change for the next combination and `739d3bd`
as the matched timing control.
[Routed evidence](../../evidence/v5-104-ddr-burst-bounds-fits.json)

## Execute operand readiness

The [parallel readiness experiment](execute-ready.md) computes two
complete execute admission decisions and selects once with the live W
load hit. It preserves the finish and admit edge on a same-cycle hit.
The 20,000-cycle direct comparison, four board profiles, all 15 fixed
workloads, four native PolyCount frames and mixed LCD/PCM/MMC replay
match the DDR control. Median setup improved 0.310 ns to −2.668 ns.
Paths through named readiness logic into execute packets fell from 44,
111 and 7 to 13, 18 and zero across the hot exports. Keep `c492853`
active. [Routed evidence](../../evidence/v5-104-execute-ready-fits.json)

## CP15 AP=0 permissions

The [CP15 predecode trial](cp15-ap0.md) registers the two AP=0 permission
modes on the existing CP15 S/R update edge. The I-side and D-side
differential checked 786,554 lookups. All 15 fixed workloads, four
native frames, four board profiles and the mixed replay matched
`c492853`. Seed 31337 gained 0.980 ns on the hot FSR endpoint family,
and all seeds saved ALMs. Median whole-core setup worsened 0.251 ns.
Park the patch for a later combination.
[Routed evidence](../../evidence/v5-104-cp15-permission-fits.json)

## D1 opcode class

The [D1 class trial](d1-opcode-class.md) captures the opcode class in
the same queue slot as its instruction. The direct test exhausts
Thumb halfwords and register lists and checks four queue configurations.
All 15 fixed workloads, four native PolyCount frames, four board
profiles and mixed LCD/PCM/MMC replay matched `c492853`.
All three fits saved area, with 925 fewer median ALMs, and median
setup regressed 0.504 ns. Seed 31337 saved 983 ALMs at a 0.100 ns setup
cost. Park `4b2c114` for area-constrained combinations.
[Routed evidence](../../evidence/v5-104-decode-class-fits.json)

The [DMA command predecode trial](dma-command-predecode.md) moves
immutable UPP programming checks to the existing packet capture edge,
ahead of the DMA offer and SDRAM address selection. The retained timing
control and trial matched 171,496 events in the physical-pin model,
15 fixed workloads and four native frames. The trial removed all but
two targeted paths from the three 100 °C top-1,000 exports. Median
setup moved from −2.668 to −2.724 ns, and median core setup TNS
improved by 1,277.025 ns. Retain it for board integration.

The [speculative register-shift trial](early-shift-select.md) removes
the Rs wait from shift-amount selection and preserves the issue interlock.
An independent shift oracle, the 15 payloads, four native frames and
104 MHz mixed pin replay all matched the control. The sampled wait-to-rotate
paths disappeared, and median setup moved from −2.724 to −2.836 ns.
The standalone patch was parked and `fe145b0` restored.

The [W auxiliary count trial](wb-rs-prep-aux.md) prepares ARM Rs
from the W auxiliary lane before issue. Across 105 fixed-work windows
and four native frames the retained control accepted zero auxiliary
counts. The auxiliary-only trial matched every measured cycle. The
both-lane prototype removed the primary W fast path too and added
0.133% to the native frame clocks in simulation. The fitted auxiliary-only
trial improved every seed and saved 602 median ALMs. Keep `a846b87`.

The [live-load shift-count trial](live-rs-prep.md) reuses that held count
only when a returning W load supplies Rs. All 105 fixed windows, four
native frames, four board profiles and the 171,496-event mixed replay
match. The narrower path topped one parked fit. The three retained hot
exports prioritize posted SDRAM acceptance. The shift-count patch has
simulation evidence and awaits a routed fit.

The [scalar D-cache lock trial](dcache-lock-valid.md) updates the pending
load's valid bit directly from miss admission and the tagged return.
All 105 fixed windows, four native PolyCount frames, four directed board
profiles and the 171,496-event mixed trace match the retained design.
The lock-valid endpoint drops out of the sampled top-1,000 paths at all
four corners. Median worst setup moves from −2.471 to −2.552 ns and
median area rises 762 ALMs. The trial is parked.

The [ALU zero predecode trial](alu-zero-predecode.md) captures the zero
operation with the existing execute packet and selects between single-bit
predicates. The directed test and all workload, native frame and mixed
replays match. Median worst setup moves from −2.471 to −2.983 ns and
median area saves 363 ALMs. The trial is parked. Public `bbed9e4`
restores the exact retained tree after both fits.

The [prepared Wishbone write-data trial](prepared-wb-write-data.md)
captures both tag-maintenance words and registers the existing advance
decision. It keeps address and request timing on the original path.
Ten directed profiles matched the control, and workload write traces
covered 330,252 successful writes. The named ACK-to-write-data paths
disappeared from the hot exports. Median setup improved 0.094 ns and
median core setup TNS worsened 993.367 ns. Keep `e9552bd`.

The [peripheral lane 13 trial](peripheral-lane13.md) keeps the existing
104 MHz MMIO response edges, separates GPIO/keypad read data from
NOS and loopback data, and carries static EUART word selects in the
request packet. All checked workload cycles and mixed pin events
matched. The named lane 13 paths shortened, while median setup
worsened by 0.052 ns and area grew by 459 ALMs. Park the trial.
Forward revert `e7f1e31` restores `e9552bd`.

The [two-edge UPP register trial](upp-two-edge.md) extends the held
packet-to-data setup budget to two 104 MHz clocks and keeps live
and control paths single-cycle. Stock keypad replay added 36 clocks.
The mixed run added 609 clocks and changed one PCM startup sample.
The initial fits verified the held relationships at all corners.
The [DMA commit correction](upp-two-edge-dma.md) takes the fast
UPP ownership tree out of unrelated DMA programming control and
matches every checked cycle. The corrected median setup reached
−2.645 ns against −2.471 ns for the retained control. Park both.
Public restore `e7beaf2` matches `e9552bd`.

The [Wishbone address trial](wb-id-address.md) uses the cache address
registers and selects the address with the registered I/D owner. All
checked workload cycles and the physical pin replay matched. Median
setup regressed on the three matched seeds, from −2.471 to −3.057 ns.
The ten-seed median was −2.819 ns. Park the trial. Public `d87216a`
restores the retained source.

The [I-cache strobe trial](icache-strobe.md) prepares the hold and
advance cases before ACK/ERR and simplifies request qualification
using the cache producers' shared CYC/STB invariant. It saves 355
median ALMs and moves matched median setup from −2.471 to −2.942 ns.
The ten-seed median was −2.802 ns to three decimals. Park the trial
for area. Public `a58c77b` restores the retained source.

The [combined I/D cache strobe trial](idcache-strobe.md) builds on that
I-cache trial by checking the D-cache hold and advance results before
ACK/ERR, including the native writeback block limit. Six of ten seeds
beat I-cache alone, and the matched comparison against retained
production lost 0.073 ns of median setup and added 422 ALMs. Park the
combination. Public `606ff0d` restores the retained source.

The [posted SDRAM write reply trial](cpu-posted-sdram-ack.md) captures
the CPU's posted-write completion after physical acceptance. The mixed
replay took 1.577% more clocks and changed one startup PCM sample.
The named posted paths disappeared, while median whole-core setup
moved from −2.471 to −2.823 ns. Public `e11a637` restores the retained
source.

The [posted SDRAM capacity trial](sdram-post-capacity.md) drives the
posted ACK from the existing slot's registered occupancy. A full slot
waits for the dequeue edge before accepting its successor. The 104 MHz
physical stream test and the 171,496-event mixed trace match the retained
control. The sampled posted ACK paths into the merger disappear. Median
setup moves from −2.471 to −2.588 ns while median core setup TNS improves
822.484 ns. The candidate adds 677 median ALMs and no M10Ks. Seed 31337
reaches −2.310 ns. All three RBFs are saved.

The [Wishbone reply split](wb-reply-class.md) keeps SDRAM writes out
of the I-cache ACK path and preserves the D-cache response edge.
The directed checks, 105 fixed windows, four native frames and
171,496 mixed pin events match. Named posted-write ACK paths through
I-cache fall to zero in the hot exports, while median setup moves from
−2.471 to −2.566 ns and median ALMs increase by 685. Park the trial.

The [prepared MMC counter](mmc-count-prepare.md) removes the wide
byte-count carry after late FIFO acceptance. The 4 KiB directed tests,
mixed replay, fixed and native workloads match. Median area drops 429 ALMs
and median setup moves from −2.471 to −2.811 ns. Park for area combinations.

The [separate lane 13 result captures](lane13-register-sources.md) reuse
the existing keypad sample and let the UART word register independently.
The directed responses, 105 fixed windows, four native frames and mixed
pin trace match the retained design. The named lane paths disappear
from the hot exports. Median setup moves from −2.471 to −3.029 ns
and median area grows by 801 ALMs. Park the trial.

The [D-cache live-trust trial](dcache-live-trust.md) removes the wide
next-fill decode from the trust register's update. The exact transition
differential and all board and workload regressions match. The sampled
retained trust endpoint misses by more than 1.5 ns at all ten hot corners.
Median setup moves from −2.471 to −2.703 ns and median area grows by
711 ALMs. Park the trial.

The [trusted D-cache hit ACK trial](dcache-trusted-hit-ack.md) removes
uncached completion from the W-load ordering fast path, the worst path
on the audited tuner pilot. Directed alignment and uncached abort tests,
the extracted equivalence checks and all workload replays matched.
Routed timing is pending.

The [conservative W-load ordering trial](conservative-w-load-order.md)
lets an older same-destination load retire before the younger load
issues. Native frames add 0.1011% clocks. Twelve fixed medians match,
and triangle edges, JPEG and Asphalt table add 0.082%, 0.566% and
1.186%. Ordered guest, memory and output checks match. Routed timing
is pending.

The [HDMI tuner clock model](lltune-generated-clock.md) declares a
generated clock for the existing low-latency scaler feedback path.
The retained global clock uses the gated branch's uncertainty. The
separate clock and uncertainty passed all twelve native corner audits.
Median setup fell to −2.733 ns from −2.471 ns and median ALMs rose by
153. Park the fit and retain the verified constraint patch.

The [prepared timer writes](timer-write-prepare.md) capture the
count-write and stop predicates with the held UPP packet. Directed tests
and the full workload suites match, including a timer-expiry trace
with MMC and LCD DMA busy. The reset-to-count route drops out of the
hot exports. Median setup improves from −2.471 to −2.403 ns and median
physical ALMs occupied fall by 412. Estimated ALMs needed rise by 568.
Keep as the next base.

The [MMC footer CRC trial](mmc-footer-crc-direct.md) removes 240 bits
of duplicate storage and reads the captured bytes during the existing
CRC window. The expanded footer checks, all workload windows and the
physical replay with the real backing adapter match. It uses 165–182
fewer fitted registers in the backing adapter. Whole-core timing and
physical occupancy worsen on all three seeds. Park the trial.
[Matched ALM accounting](fitter-alm-accounting.md)

The [MMC HPS owner trial](mmc-hps-cancel-owner.md) removes two redundant
32-bit generation registers and uses the existing cancellation state.
The equivalence bench covers wrap and malformed events, and the actual
HPS peer and full byte traces match. Its backing adapter saves about
98 occupied ALMs at the paired median. Median setup and all three
TNS results worsen. Park for area combinations.

The [compact D-cache lock](dcache-compact-lock.md) stores the sole load
lock as a tag and a valid bit in the phone configuration. The existing
tag/return edge is preserved, and the exact state and workload replays
match the timer baseline. Routed timing is pending.

The [dirty-clear descriptor trial](dcache-dirty-clean-descriptor.md)
preselects the held maintenance address before Wishbone completion.
The dirty write retains its original edge. The eight added CP15 profiles,
all workload windows and both timer pin replays match. Routed timing is
pending.

The [SDRAM block-payload trial](sdram-block-payload.md) stages the CPU's
128-bit payload on the arbiter's free edge. The request retains its owner,
lock and block qualification. The full cold scrub, queued reset drain,
real ARM dirty writeback and workload traces match. Routed timing is pending.

The [native refill word-ready trial](refill-line-word-ready.md) registers
line occupancy so the ACK no longer compares the received and consumed
counters. Narrow and wide assembly, same-edge ACK, error and scalar fallback
match the control in all workloads and both physical traces. Routed timing
is pending.

## Passive opportunity studies

The census patches add simulation observers and source fixtures. They keep
the measured CPU pipeline and memory scheduling intact. The figures are
upper bounds and may overlap.

| Study | Git fixture and prerequisite | Measured opportunity |
| --- | --- | --- |
| Paired stores from one register list | [Observer and runner](patches/store-pair-census-fixture.patch) plus [checked workload harness](patches/checked-workload-harness.patch) on `739d3bd` | 911,218 disjoint resident, writable store pairs across four native frames, or 1.58% if every pair saved one exposed clock. JPEG 2.04% and Sega scan 0.76% at that ceiling. Eleven fixed workloads had no pairs. [Counts](../../evidence/v5-104-parallel-store-census.json) |
| Deliver two refill words on one ACK | [Refill observer and runner](patches/refill-pair-and-admission-fixture.patch) on `739d3bd`, with the stage flag off | 66,320 I and 3,064 D candidate pairs, all on wide beats. At most 0.121% of native clocks if every removed delivery edge reached retirement. The observer saw zero first pair ACKs in the exposed-wait class. [Counts](../../evidence/v5-104-d-refill-admission.json) |
| Prepare the next sequential I-line | [Passive fixture](patches/sequential-i-line-census-fixture.patch) on `739d3bd` | 359,405 hints joined later verified misses. A hindsight idle-run model gives a 1.50% native ceiling. Restricting frame zero to same 1 KiB permission subpage and preparing only after the checked miss gives 0.54%. No fixed-work window had an eligible narrow I fill. [Evidence](../../evidence/v5-104-sequential-instruction-hints.json) |
| Buffer the next physical SDRAM line | [Passive fixture](patches/physical-next-line-census-fixture.patch) on `b6d8981` | With a 24-clock baseline idle slot, 10,979 I → I and 439 D → D native demands matched the modeled physical tag, or 1.57% of all narrow full-line demands. Sega scan accounts for 3,192 of the 3,210 same-slot fixed-work matches. The census does not measure savings or allocate a bus slot. [Method and replay](physical-next-line.md) · [Counts](../../evidence/v5-104-physical-next-line.json) |
| Recover an instruction already available at redirect | [Redirect observer](patches/frontend-redirect-census-fixture.patch) plus [checked workload harness](patches/checked-workload-harness.patch) on `739d3bd` | The Sega scan had 18,305 retiring Thumb same-word candidates per timed window. Native had zero. One ARM same-line snapshot gave a two-clock ceiling of 0.207% native, and ready queue/reply/decode candidates gave 0.054%. Earlier A direct-target selection gave a 0.483% one-clock native ceiling with a new late decision path. Only the narrow Thumb design above was implemented in this study. |

[Fixture setup and commands](fixtures.md) · [Earlier 78/104 MHz timing experiments](historical.md)
