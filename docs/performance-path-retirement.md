# Production performance paths

User policy: a proven faster equivalent replaces its slower production
implementation. Rollback and comparisons belong in historical branches and
frozen evidence. A route with a distinct required function remains; a measured
workload/resource tradeoff needs a decision based on representative evidence.

The `FAST_LCD` hierarchy parameter and `PHONE_FAST_LCD=0` CPU profile are removed.
Eligible SDRAM-to-LCD descriptors always use `ngage_lcd_stream.v`. The general
DMA engine still serves on-chip RAM LCD sources, memory copies and future MMC.
The final-response fence test now uses `0c004100`, so it tests this necessary
route without a global slow-LCD switch. Historical A/B logs remain evidence of
the 130,685 versus 306,802 full-frame clocks; production has one choice.

| Path | Next action and evidence boundary |
| --- | --- |
| Direct SDRAM | Next justified retirement: clean miss 159 to 143 clocks, dirty 108 to 90, hit 5 unchanged, with routing/reset/SWP and fresh-boot coverage. Migrate `flash_reset`, `memory_owner` and paired benchmark fixtures before deleting the indirect RAM route. |
| Legacy DMA owner | Superseded register/IRQ ownership, rather than a performance tradeoff. Remove production exposure after P2 acceptance and migrate the three legacy CPU/LCD fixtures; retain an old reader only as an isolated historical oracle if needed. |
| D1 streaming backend | Provides bulk ownership/streaming features, but is not uniformly faster than the scalar backend: uncached scalar response 4 versus 3 clocks, cache-off reuse 1,920 versus 1,664. Do not equate the already-retired full-buffer D1 experiment with the old scalar backend. |
| D2 flash cache | Reuse improves, but cold misses and scans can regress. Size and fit remain tradeoffs; do not assume every uncached access is slower. |
| D3 sector transport | Fewer transactions and lower measured save/restore time support bulk sectors. Actual production HPS/NOR/reset/media-change and fit gates precede removal of the old sector-consumer mode. Ordinary scalar clients remain necessary. |
| Whole-line refill | Selected in Template; scalar MMIO, partial operations and writes still need support. Disabled experimental builds are distinct from those required transactions. |
| Background save | Persistence policy, not a performance selector. Keep manual/automatic choice. |

`ngage_ddr_stream_legacy.v` is a scalar compatibility wrapper onto the new
stream and remains useful. Its name is not evidence that it is the slower
implementation. The old scalar backend is inside `ngage_ddr_adapter.v`.

The fresh bounded boot fixture uses the legacy adapter and omits the shared
flash adapter. It verifies the production CPU/DMA/LCD ownership change, but
does not exercise Template's D1=1, D2=8192, D3=1 and LINE_REFILL=1 chain. A
focused consumer/boot harness with that selected chain is required before
claiming full production DDR boot coverage or deleting its alternatives.
Existing cache/raw-save/controller tests remain independent evidence.

Detailed read-only audit and source anchors are retained under
`scratch/ngage2-integration/fast-path-retirement/audit.md`.
