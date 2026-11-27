# Where the reported ALMs increased

The audit matches 104 MHz production DDR fits with debug off by seed and checks the per-seed QSF and MMC HPS RTL hashes. The source reports are `Template.fit.rpt` and `Template.map.rpt` under each `build/timing-audit-<run>/output_files`.

| Trial | Seed 13 | Seed 43 | Seed 31337 |
| --- | ---: | ---: | ---: |
| Retained | 45771268571 | 45771267820 | 45771266151 |
| WB reply class | 45786912492 | 45786908403 | 45786907340 |
| Lane 13 reply | 45800010061 | 45800009911 | 45800009711 |
| D-cache live trust | 45818144877 | 45818145038 | 45818144548 |
| MMC prepared count | 45793456733 | 45793453000 | 45793455943 |

The Fitter reports ALMs needed as occupied ALMs minus estimated recoverable ALMs plus estimated unavailable ALMs. The identity holds for all 15 builds. Each WB, lane and trust fit occupies fewer ALMs than the matched retained fit. Their higher estimates come primarily from a reduction of 876 to 1,017 recoverable ALMs at the paired median. Retained uses 38,963, 39,015 and 39,039 occupied ALMs, of which the Fitter estimates that 3,356, 3,397 and 3,433 are recoverable.

| Trial | ALMs needed | Occupied | Recoverable | Unavailable | LUT+FF ALMs | FF-only ALMs | Logic ALUTs | Route-through ALUTs | Synthesized ALUTs | Synthesized FFs |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| WB | +701 | −166 | −876 | −3 | +815 | −956 | +910 | −1,162 | −19 | +28 |
| Lane | +801 | −214 | −992 | +43 | +805 | −989 | +1,156 | −1,047 | +161 | +2 |
| Live trust | +696 | −322 | −1,017 | +1 | +530 | −875 | +935 | −975 | +66 | −24 |
| MMC count | −432 | −259 | +103 | −55 | +110 | −65 | +35 | −55 | +15 | −38 |

The table takes the median of three matched deltas independently for each column. Accordingly, its medians may differ from the difference of the control and trial medians. The latter is +685, +801, +711 and −429 estimated ALMs, respectively. Fitter routing-optimization register duplication also falls at the paired median by 262, 201, 197 and 107 registers. All fits use 321 M10Ks and 600 ALMs for MLABs.

The first number in each Fitter entity entry includes descendants, and the parenthesized number describes the entity itself. Direct occupied ALMs and ALUTs reconcile with the top-level counts to rounding. The direct estimated-needed column has a roughly 21–33 ALM residual, so the entity comparisons below use only disjoint hierarchy rows and describe the Fitter estimate.

| Fitter entity | WB | Lane | Live trust | MMC count |
| --- | ---: | ---: | ---: | ---: |
| MMC HPS backing, direct | +74.0 | +64.9 | +138.6 | +17.1 |
| D-cache, inclusive | +126.2 | +162.6 | +140.7 | — |
| Execute, inclusive | +79.2 | +48.9 | +67.1 | — |
| WB merge, direct | +67.2 | +23.5 | +56.8 | — |
| Register file, direct | −20.7 | −9.9 | −5.2 | — |
| UPP DMA, inclusive | +90.3 | +155.8 | +95.8 | — |

The first four rows jointly account for 274–428 estimated ALMs across the nine WB, lane and trust builds. They jointly decline by 79–101 estimated ALMs in the MMC-count contrast. Changes are distributed through the design, including substantial changes in the unchanged D-cache and UPP DMA. The register file's direct area and global routing-duplicate counts move opposite to the increased needed estimate.

The unchanged `ngage_mmc_hps:mmc_backing` has the largest direct increase shared by the three higher-estimate trials. Its mapped FF count is 793 in every run and its paired-median mapped ALUT count shifts by +1, −4 and −6. Its fitted ALUT count shifts by +112, +103 and +173. It uses no MLAB or M10K. The fit reports list 15 retiming entries in each retained run and 174, 93 and 94 entries respectively in each seed of the other three trials. The names include `owned_lba` and `request_generation`, with `received_words` appearing in creation entries. These entries describe physical transformations and can refer to successive transformations of the same signal.

The fit reports do not name `cid_shift` and `csd_shift` in those transformation rows. The independently verifiable opportunity is in RTL, where the backing adapter duplicates 240 bits of existing footer storage for CRC. This is a candidate for a localized area experiment. A fit will show the actual register and packing benefit, debit the new byte selector and measure the preserved CRC cycle's slack.
