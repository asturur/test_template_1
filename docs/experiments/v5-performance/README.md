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
commit where one exists, and checks measured wrapper hashes for the local
D-cache A/B variants.

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
invocation. See [the generator notes](../../arm9v2-phone.md) and
[the historical catalog](historical.md).

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
| Launch the ordinary redirect independently of queue rescue | `e6c352c` from `27bd8bf`. [Implementation and extended test](patches/thumb-ordinary-redirect.patch) | The redirect and BTB always launch the actual upper-half PC. Two stage bits mark the duplicate so it cannot predict, enqueue or retry after the head already received the checked halfword. The 213-clock fixture covers changed ownership, wrong-path faults and held duplicates. Fifteen workload outputs, four native frames, ordered data/MMIO and mixed replay match. The extra lookup gives up almost all Sega gain: 2,395,766 clocks versus 2,377,506 with original Thumb and 2,395,767 on all-four. Routed results are pending. [Functional replay](thumb-ordinary-redirect-replay.json) · [Routed evidence when published](../../evidence/v5-104-thumb-independent-redirect-fits.json) |

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

## Passive opportunity studies

The census patches add simulation observers and source fixtures. They keep
the measured CPU pipeline and memory scheduling intact. The figures are
upper bounds and may overlap.

| Study | Git fixture and prerequisite | Measured opportunity |
| --- | --- | --- |
| Paired stores from one register list | [Observer and runner](patches/store-pair-census-fixture.patch) plus [checked workload harness](patches/checked-workload-harness.patch) on `739d3bd` | 911,218 disjoint resident, writable store pairs across four native frames, or 1.58% if every pair saved one exposed clock. JPEG 2.04% and Sega scan 0.76% at that ceiling. Eleven fixed workloads had no pairs. [Counts](../../evidence/v5-104-parallel-store-census.json) |
| Deliver two refill words on one ACK | [Refill observer and runner](patches/refill-pair-and-admission-fixture.patch) on `739d3bd`, with the stage flag off | 66,320 I and 3,064 D candidate pairs, all on wide beats. At most 0.121% of native clocks if every removed delivery edge reached retirement. The observer saw zero first pair ACKs in the exposed-wait class. [Counts](../../evidence/v5-104-d-refill-admission.json) |
| Prepare the next sequential I-line | [Passive fixture](patches/sequential-i-line-census-fixture.patch) on `739d3bd` | 359,405 hints joined later verified misses. A hindsight idle-run model gives a 1.50% native ceiling. Restricting frame zero to same 1 KiB permission subpage and preparing only after the checked miss gives 0.54%. No fixed-work window had an eligible narrow I fill. [Evidence](../../evidence/v5-104-sequential-instruction-hints.json) |
| Recover an instruction already available at redirect | [Redirect observer](patches/frontend-redirect-census-fixture.patch) plus [checked workload harness](patches/checked-workload-harness.patch) on `739d3bd` | The Sega scan had 18,305 retiring Thumb same-word candidates per timed window. Native had zero. One ARM same-line snapshot gave a two-clock ceiling of 0.207% native, and ready queue/reply/decode candidates gave 0.054%. Earlier A direct-target selection gave a 0.483% one-clock native ceiling with a new late decision path. Only the narrow Thumb design above was implemented in this study. |

[Fixture setup and commands](fixtures.md) · [Earlier 78/104 MHz timing experiments](historical.md)
