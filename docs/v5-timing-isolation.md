# Where the round-three core misses 104 MHz

The CPU and the board fabric both miss setup when fitted independently. The limiting endpoints in all six isolated fits are within the production logic being measured. The integrated build loses a further 0.638–1.137 ns relative to the slower of the two isolated fits on each matched seed. Removing logic changes placement and routing, so that difference cannot be assigned entirely to the bus interface.

### Matched physical fits

The table gives the worst 104 MHz setup slack over all four operating corners, followed by the lowest Quartus-reported Fmax for that clock. Fmax describes the fitted routing at the modeled corners. These are static timing results without board measurements.

| Fit | Seed 42 | Seed 43 | Seed 44 |
| --- | ---: | ---: | ---: |
| Round-three integrated core | [−3.039 ns / 79.03 MHz](https://github.com/asturur/test_template_1/actions/runs/44971720604) | [−2.744 ns / 80.91 MHz](https://github.com/asturur/test_template_1/actions/runs/44971720752) | [−2.689 ns / 81.27 MHz](https://github.com/asturur/test_template_1/actions/runs/44971720739) |
| CPU, caches, TLBs and refill adapter | [−1.821 ns / 87.44 MHz](https://github.com/asturur/test_template_1/actions/runs/45021656324) | [−1.919 ns / 86.70 MHz](https://github.com/asturur/test_template_1/actions/runs/45021658621) | [−1.864 ns / 87.12 MHz](https://github.com/asturur/test_template_1/actions/runs/45021660946) |
| Board fabric with registered CPU traffic source | [−1.902 ns / 86.83 MHz](https://github.com/asturur/test_template_1/actions/runs/45021663162) | [−2.106 ns / 85.32 MHz](https://github.com/asturur/test_template_1/actions/runs/45021665510) | [−1.619 ns / 89.02 MHz](https://github.com/asturur/test_template_1/actions/runs/45021667761) |

The worst isolated CPU path was at slow 100 °C on each seed. At this corner all three start at data-cache or TLB state and pass through the writeback and issue interlock. Their destinations are decode packet storage, execute packet storage and decode packet storage, respectively. The fitted logic named `s_held_load_writer` occurs on each. The underlying RTL allows a younger load to the same destination to advance when the older load returns a trusted hit in that cycle. On seed 44 at slow −40 °C the worst path instead stays within instruction classification and decode.

The board's limiting route on seed 42 runs from the UPP request address through peripheral owner selection into the response-valid register at slow −40 °C. On seeds 43 and 44, the worst path at slow 100 °C ends at the LCD DMA stream's `line_available` register. Reset or PCM control goes through request selection and arbitration before updating the LCD's available transfer count. The integrated seed 44 also has an LCD arbitration path at −2.687 ns, just 0.002 ns behind its worst CPU path.

### What to test first

1. In the CPU-only fit, test releasing the younger same-destination load on a registered completion of the older writer. Preserve ordinary cache-hit latency. Measure the consecutive same-destination loads, faults and interrupt replay together with PolyCount and the game kernels. The diagnostic identifies this timing path; its performance cost remains unmeasured.
2. In the board-only fit, decouple the LCD stream's next request and count update from the shared DMA grant using a registered request or reservation. Verify one completion per grant, cancellation, LCD/PCM fairness, the physical raster cadence and the mixed peripheral replay. Continue tracking the UPP address-to-response path on seed 42.
3. Refit successful changes together in the integrated design. The isolated results establish the two independent timing deficits, while the shipping board is the final test.

### Coverage and reproduction

The diagnostics ran at commit `08f79f8` with the same physical 104 MHz PLL, FPGA, Quartus version and three seeds as round three, with DDR debugging off. The CPU-only fit took 38% of ALMs and retained the same 82 M10Ks as the CPU hierarchy in the integrated core, including both 16 KiB caches and both TLB instances. The board-only fits took 53% of ALMs, retained 356 M10Ks and kept all 16 SDRAM DQ input, output and output-enable registers in I/O cells. Their fitted inventories include DMA, LCD, MMC, flash, PCM and the SDRAM scheduler.

The diagnostic workflows succeeded when the inventory, constraints and timing exports passed. Negative setup slack is recorded as a measurement. The fixture tests exercised registered scalar and line traffic, backpressure, locks and rejected-line fallback. CPU-only used a fixture pin constraint file. Board-only used the production board constraints. No diagnostic bitstream was published. [Harness and workflow instructions](../tools/fit_isolation/README.md)

### Results of the interlock and LCD experiments

Worst setup slack in ns for the 104 MHz clock, across all four corners. The internal rows include only paths between endpoints in the production logic under test.

| Isolated fit | Seed 42 | Seed 43 | Seed 44 | Median |
| --- | ---: | ---: | ---: | ---: |
| Round-three CPU, internal | −1.821 | −1.919 | −1.864 | −1.864 |
| Registered same-destination load release, internal | [−2.581](https://github.com/asturur/test_template_1/actions/runs/45041293138) | [−2.538](https://github.com/asturur/test_template_1/actions/runs/45041295444) | [−2.331](https://github.com/asturur/test_template_1/actions/runs/45041297651) | −2.538 |
| Round-three board, internal | −1.902 | −2.106 | −1.619 | −1.902 |
| LCD reservation, internal | [−1.846](https://github.com/asturur/test_template_1/actions/runs/45040988640) | [−1.896](https://github.com/asturur/test_template_1/actions/runs/45040990857) | [−1.940](https://github.com/asturur/test_template_1/actions/runs/45040993192) | −1.896 |

The CPU trial (`eb2abbc`) allowed the younger load to reserve its issue slot early and delayed execution until the older writer retired. It removed the old same-cycle release, which appeared in 62, 48 and 22 of the 100 detailed hot paths before this change. Seeds 42 and 43 were subsequently limited by translation to D-cache lock, and seed 44 by the TLB walker's address to the Wishbone address register. The four native frames used 57,572,942 cycles against round three's 57,514,786 (+0.101%). Twelve fixed-work medians were unchanged; triangle edges increased 0.213%, JPEG 0.929% and Asphalt table lookup 1.186%. The directed 32-load same-destination chain increased from 104 to 128 clocks. The CPU trial was dropped before the full-core test.

The LCD trial (`cd609b2`) reserves the next address and transfer size locally before the shared arbiter grants it. All 18 pin-model cases matched their reference cycle, traffic and contention records. Mixed LCD/MMC/PCM took 1,189,662 clocks on both legs, and raster timing matched. The median internal setup slack changed by just +0.006 ns. Seed 42's overall deficit was 2.054 ns on a path from the traffic generator's lock output into the real DMA engine. The other two seeds' worst paths were internal. This justified checking the LCD change on the integrated design with the original CPU. Local simulation records are in `build/sim/v5-104-writer-reservation-comparison.json` and `build/sim/v5-104-lcd-reservation-comparison.json`.

### Full-core decision at 104 MHz

Keep the LCD reservation with the round-three CPU. Worst setup slack across all four operating corners improved for two of three matched seeds. The median gained 0.112 ns and the best fit gained 0.146 ns. All three passed hold, recovery, removal and minimum pulse width. All three missed setup.

| Seed | Round three | LCD reservation on round-three CPU | Change | Worst path on the new fit |
| --- | ---: | ---: | ---: | --- |
| 42 | −3.039 ns | [−3.130 ns](https://github.com/asturur/test_template_1/actions/runs/45043484955) | −0.091 ns | SDRAM locked-write state to CPU Wishbone write-data register |
| 43 | −2.744 ns | [−2.543 ns](https://github.com/asturur/test_template_1/actions/runs/45043488050) | +0.201 ns | Decode write-through data to the execute packet |
| 44 | −2.689 ns | [−2.632 ns](https://github.com/asturur/test_template_1/actions/runs/45043490523) | +0.057 ns | TLB physical address to CPU Wishbone address register |

Seed 43 at `5f8fae0` is the best of these full-core fits. Quartus reports 82.25 MHz for its core clock at the limiting slow 100 °C corner. The seed spread and different endpoints make this a modest timing gain. A future experiment could register the CPU-facing memory response or request at the Wishbone merger. First measure the resulting cycles on cache hits, refills and mixed DMA, since the seed 43 hot path stays within the CPU.

The integrated simulation also exercised the LCD's native 16-byte reads with scalar CPU traffic and a modeled SDRAM. Both RTL versions completed 4,576 native requests, matched all 18,304 checked words, observed 726 LCD/MMC overlaps and served 128 PCM reads without underrun. MMC write/readback passed and deliberate corruption was detected. The comparison is in `build/sim/v5-104-lcd-integrated-comparison.json`. These are simulation results. The 104 MHz bitstream has no hardware validation in this experiment.

### Comparing Jake's master with v5

Upstream release `9210fa2` reached −1.148 ns at slow 100 °C and −1.321 ns at slow −40 °C. Its CI accepted −2.0 ns. The subsequent master commits changed a board tool and then CI and documentation. At master `09837fe`, the published release is still the relevant RTL measurement. [Release fit](https://github.com/jakesjews/NGage_MiSTer/actions/runs/44777214314) · [Strict CI change](https://github.com/jakesjews/NGage_MiSTer/commit/09837fe597)

| At physical 104 MHz | Jake's release | v5 with LCD reservation |
| --- | ---: | ---: |
| Best worst-corner setup | −1.321 ns | −2.543 ns |
| Median worst-corner setup | −1.572 ns (16 seeds) | −2.632 ns (3 seeds) |
| Core-clock total negative setup slack in the selected STA summary | −179.142 ns | −7,902.842 ns |
| ALMs in the selected fit | 33,938 (81%) | 37,452 (89%) |
| M10Ks in the selected fit | 490 (89%) | 438 (79%) |
| D-cache / I-cache | 8 / 16 KiB | 16 / 16 KiB |

The last upstream release changed the seed with the same RTL. Its predecessor at seed 5 reached −1.478 ns worst corner. Across the November 20 sweep the worst corners spanned −1.321 to −1.988 ns. Jake's separate four-seed trial with a 16 KiB D-cache on an earlier netlist reported −1.923, −2.335, −1.644 and −1.855 ns. Cache size, seed sets and board integration differ. Utilization alone cannot assign a timing penalty to any one difference. [Upstream sweep](https://github.com/jakesjews/NGage_MiSTer/commit/9210fa2620) · [16 KiB D-cache trial](https://github.com/jakesjews/NGage_MiSTer/commit/e810dddf6f)

Quartus attributes about 15,094 ALMs to the v5 CPU including caches and 14,157 to Jake’s, a difference of 937 out of the 3,514 total. The execution core itself is 8,629 versus 8,719. Most of the whole-chip difference therefore sits outside the CPU/cache hierarchy. The per-entity ALM numbers are fitter estimates with shared logic apportioned across hierarchy.

Several upstream changes are present in the fitted v5 design, including placement effort 4, generation-based TLB validity, victim-line selection and store merging after registers, and compact held-write flags and indices in the register file. The upstream placement change gained 0.263 ns on the eight-seed mean. Upstream's later SDRAM read-ahead raised measured board PolyCount from 28.41 to 29.67 Ktriangles/s by serving adjacent fills sooner. [Placement measurements](https://github.com/jakesjews/NGage_MiSTer/commit/b18f27a9e3) · [Timing RTL](https://github.com/jakesjews/NGage_MiSTer/commit/a182204f87) · [SDRAM read-ahead](https://github.com/jakesjews/NGage_MiSTer/commit/5473d464b4)

Jake's merger also registers each source's write data and selects between them by registered ownership. Eighteen of his 30 detailed hot paths go from the D-cache to that merger. His worst hot path has seven logic levels and 6.622 ns of interconnect. In v5 seed 44, a TLB-to-merger address path has ten levels and 7.555 ns of routing. In seed 43, the internal decode-to-execute path has nine levels and 9.371 ns of routing. This supports testing a local change at the merger while tracking the CPU forwarding paths across all three seeds. Upstream's diagnostic removal of cache-response timing paths left several other failing CPU stages. [Upstream diagnostic](https://github.com/jakesjews/NGage_MiSTer/commit/f560481594)

Upstream also used a two-cycle constraint from registered peripheral payloads to specific interrupt-enable and audio registers. Its peripheral write strobe cannot fire on the first clock of that transaction. This removed 103 reported failing endpoints on a historical seed. It does not apply to the same-cycle CPU or Wishbone paths above. Any equivalent exception on v5 would need the same timing guarantee in the v5 peripheral RTL. [Upstream peripheral timing rationale](https://github.com/jakesjews/NGage_MiSTer/commit/282a9e949d)

The memory target provides another architectural difference. Jake's `upp_bus` registers ACK, error and read data **in the target**. Its two-master arbiter routes the registered reply by its saved grant. The target anticipates incrementing bursts and begins fetching the next beat while answering the current one. In v5, the scalar locked-write response depends on the SDRAM stream state and memory busy in the same cycle, which put a board-to-CPU path first on seed 42. Our earlier experiment `d4edf9b` added a completion stage, increased mixed replay clocks by 7.27%, and worsened median slack. A closer analogue to Jake's design would generate completion at the memory target on the existing response edge and preserve the overlap. [Upstream target](https://github.com/jakesjews/NGage_MiSTer/blob/9210fa2620/rtl/upp/upp_bus.sv) · [Upstream arbiter](https://github.com/jakesjews/NGage_MiSTer/blob/9210fa2620/rtl/upp/wb_arb2.sv)

### Wishbone address and write-data experiment

Candidate `9d2e76c` captures the instruction, D-cache, tag-maintenance, TLB and posted-store payloads on the existing request edge. A registered owner selects the output address and data. The retained build uses the LCD reservation and selects the final address before that edge. The three production trials used a physical 104 MHz clock, both 16 KiB caches, DDR debugging off, and the original bus, raster and guest timer settings.

| Seed | Retained setup | Trial setup | Difference | ALMs, retained → trial | Limiting trial path at worst corner |
| --- | ---: | ---: | ---: | ---: | --- |
| 42 | −3.130 ns | [−2.884 ns](https://github.com/asturur/test_template_1/actions/runs/45057263937) | +0.246 ns | 37,517 → 37,128 | CPU flush to Wishbone cycle |
| 43 | −2.543 ns | [−2.496 ns](https://github.com/asturur/test_template_1/actions/runs/45057266581) | +0.047 ns | 37,452 → 37,186 | Board reset drain to LCD stream ownership |
| 44 | −2.632 ns | [−2.985 ns](https://github.com/asturur/test_template_1/actions/runs/45057269463) | −0.353 ns | 37,493 → 37,213 | Multiply result to the CPU memory-stage register |
| Median | −2.632 ns | −2.884 ns | −0.252 ns | | |

The full-core median regressed despite two improving seeds and lower ALM use on every seed. Seed 44's core-clock total negative setup slack at the hot corner grew from −6,161 to −10,257 ns. All three remained at 438 M10Ks and passed hold, recovery, removal and minimum pulse width. The new selection logic exposed downstream paths. Seed 42's registered source address to boot-register decode ranked 10th at 100 °C (−2.527 ns). Seed 43's registered payload owner to bridge read data ranked 27th there (−2.128 ns). The LCD accept/response logic was on the worst path on seed 43 at both slow corners and on seed 44 at the hot corner. The best single trial gained just 0.047 ns. Retain the original LCD baseline on the branch and preserve the new seed 43 RBF separately as a measured alternative. Neither image meets 104 MHz setup.

All 15 fixed workloads and their request traces matched the baseline. The four native PolyCount frames matched output and elapsed time (57,514,786 cycles). Four CPU contract modes, 256 D-cache arbitration combinations and the mixed SDRAM-pin replay also passed. The mixed replay took 1,189,662 clocks on both versions. The comparison is saved in `build/sim/v5-104-wb-request-banks-comparison.json`. The two seed 43 bitstreams are archived under `build/fit/v5-104mhz-5f8fae0-seed43/` and `build/fit/v5-104mhz-9d2e76c-seed43/`. The trial was verified in simulation and static timing only.

The next experiment worth testing on the retained branch is a grant and response owned by the SDRAM target. Start with scalar locked writes and the competing LCD request. Establish when the target knows completion and ownership, then test whether it can generate the existing reply edge locally. Measure scalar latency, burst spacing, locking and mixed DMA before fitting. A further cycle on every scalar reply was already measured and rejected.
