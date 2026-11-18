# Routed third D-side mapping on the banked TLB

Worst 78 MHz setup slack changes from **-0.639 ns** to **-0.743 ns**.
The routed candidate misses the 78 MHz timing gate and needs timing work before deployment.

Both runs used Quartus 17.0.2 with seed 42 and the DDR debugger enabled. The two builds match on all 178 effective input paths. The hashes differ for the D-cache instance and its translation controller. The physical 78 MHz PLL, production BRAM and source module definitions match. Both artifacts pass all 16 SDRAM DQ input, output and output-enable register checks. The eight scenarios match on clock inventories and constraints.

[Banked control](https://github.com/asturur/test_template_1/actions/runs/44160843231) · [Banked third-slot fit](https://github.com/asturur/test_template_1/actions/runs/44258633306)

## Resources

| Metric | Banked | Third slot | Delta |
| --- | ---: | ---: | ---: |
| ALMs | 37,073 | 37,529 | +456 |
| placed_ALMs | 38,899 | 39,246 | +347 |
| occupied_LABs | 4,135 | 4,165 | +30 |
| registers | 41,892 | 42,138 | +246 |
| design_registers | 38,506 | 38,856 | +350 |
| routing_registers | 3,267 | 3,163 | -104 |
| M10Ks | 514 | 514 | +0 |
| block_memory_bits | 2,763,567 | 2,763,567 | +0 |
| MLABs | 40 | 40 | +0 |
| DSPs | 41 | 41 | +0 |

Direct TLB hierarchy values show local controller and main-bank rows. The whole-design deltas also include placement and routing effects throughout the fit.

| Row | Direct ALMs A → B | Direct registers A → B | M10Ks A → B |
| --- | ---: | ---: | ---: |
| I | 238 → 238.1 | 461 → 459 | 7 → 7 |
| I bank | 573.7 → 557.5 | 353 → 356 | 7 → 7 |
| D | 317.9 → 427.1 | 479 → 571 | 7 → 7 |
| D bank | 542.9 → 565.8 | 344 → 338 | 7 → 7 |

## Routed timing

Slacks are in nanoseconds. The 104 MHz entries use the same routed netlist with the alternate clock constraint.

| MHz and model | Setup A → B | Δ setup | Hold A → B | Recovery A → B | Removal A → B | Min pulse A → B |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 78 Slow 1100mV 100C Model | -0.558 → -0.743 | -0.185 | +0.243 → +0.198 | +2.061 → +2.923 | +1.097 → +1.094 | +0.641 → +0.641 |
| 78 Slow 1100mV -40C Model | -0.639 → -0.547 | +0.092 | +0.113 → +0.079 | +2.476 → +3.260 | +1.029 → +1.028 | +0.641 → +0.641 |
| 78 Fast 1100mV 100C Model | +2.816 → +3.013 | +0.197 | +0.130 → +0.131 | +5.308 → +5.113 | +0.535 → +0.552 | +0.641 → +0.641 |
| 78 Fast 1100mV -40C Model | +3.447 → +3.478 | +0.031 | +0.062 → +0.060 | +5.523 → +5.381 | +0.462 → +0.467 | +0.641 → +0.641 |
| 104 Slow 1100mV 100C Model | -3.763 → -3.948 | -0.185 | +0.243 → +0.198 | -1.144 → -0.282 | +1.097 → +1.094 | +0.480 → +0.480 |
| 104 Slow 1100mV -40C Model | -3.844 → -3.752 | +0.092 | +0.113 → +0.079 | -0.729 → +0.055 | +1.029 → +1.028 | +0.480 → +0.480 |
| 104 Fast 1100mV 100C Model | +1.938 → +1.963 | +0.025 | +0.130 → +0.131 | +3.375 → +4.144 | +0.535 → +0.552 | +0.480 → +0.480 |
| 104 Fast 1100mV -40C Model | +2.623 → +2.955 | +0.332 | +0.062 → +0.060 | +4.324 → +5.007 | +0.462 → +0.467 | +0.480 → +0.480 |

## Interpretation

The fit adds **456 whole-design ALMs**, while the directly attributed D translation controller adds **109.2 ALMs and 92 registers**. Both fits use 514 M10Ks. The candidate leaves 26 LABs and 39 M10Ks available.

The slow-corner worst path shifts from the CPU data-cache fast-hit path into UPP block control to the reset-drain path into D-cache MVA storage. The worst 78 MHz path data delays are 12.663 ns and 12.831 ns. The candidate's path has 11 levels and 8.567 ns of routing delay. The 1,000-path export includes 0 paths with explicit third-record signal names. This counts names in the exported paths and has limited visibility into logic merged by the fitter.

Keep the third slot as a measured performance candidate and address timing before release. The RBF is retained with its negative timing evidence.

## Artifacts

| Run | RBF SHA-256 |
| --- | --- |
| 44160843231 | `61a12540fbe3891eb8196bb94cf8035e394e95cc212349be995a85fd55dc43de` |
| 44258633306 | `110ae84d226bf0a6cd5e963cb8b884a72df4d9de44ed8b0d18391a3e96047ded` |

[Machine evidence and routed endpoints](evidence/tlb-banked-third-fit-20261118.json.gz) · [Combined-source functional qualification](cpu-thumb-early-load.md)
