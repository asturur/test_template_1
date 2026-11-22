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
