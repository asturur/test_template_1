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
