# Matched 5L and banked-TLB physical fits

Retain the banked candidate for its measured 3,882 ALM saving and 39 remaining M10Ks, subject to the recorded cold/mutation latency costs and timing limits. It does not close 78 MHz timing, so it is not a timing-qualified hardware release. The 104 MHz objective remains unmet.

Both builds used Quartus 17.0.2, seed42 and DDR debugger on. The production PLL stays at 78 MHz; the same routed designs were also analyzed at 104 MHz. No hardware deployment was performed.

| Variant | Immutable source | Build | Timing gate |
|---|---|---|---|
| 5l | `0c380ab9bae92916d297b72d6a303d251f1d49d9` | [run](https://github.com/asturur/test_template_1/actions/runs/44155992918) (failure) | failure |
| banked | `613a3d62abee103660a2475df4abec89e64b1542` | [run](https://github.com/asturur/test_template_1/actions/runs/44160843231) (failure) | failure |

## Whole design resources

| Metric | 5L | 5L + banked TLB | Delta |
|---|---:|---:|---:|
| ALMs | 40,955 | 37,073 | -3,882 |
| placed_ALMs | 40,927 | 38,899 | -2,028 |
| occupied_LABs | 4,190 | 4,135 | -55 |
| registers | 44,898 | 41,892 | -3,006 |
| design_registers | 41,453 | 38,506 | -2,947 |
| routing_registers | 3,326 | 3,267 | -59 |
| M10Ks | 502 | 514 | +12 |
| block_memory_bits | 2,760,495 | 2,763,567 | +3,072 |
| MLABs | 40 | 40 | +0 |
| DSPs | 41 | 41 | +0 |

Capacity: 41,910 ALMs, 4,191 LABs and 553 M10Ks. Banked headroom is 4,837 ALMs, 56 LABs and 39 M10Ks. Registers include routing optimization; implementation and routing are reported separately above.

## Main TLB hierarchy

Subtree and direct values are alternative views, never added together. Direct values are the parenthesized Quartus hierarchy values.

| Bank / metric | 5L | Banked | Delta |
|---|---:|---:|---:|
| I subtree_ALMs | 2080.5 | 573.7 | -1506.8 |
| I direct_ALMs | 2080.5 | 573.7 | -1506.8 |
| I placed_ALMs | 2099.9 | 579.9 | -1520 |
| I registers | 2047 | 353 | -1694 |
| I M10Ks | 1 | 7 | +6 |
| D subtree_ALMs | 2082.6 | 542.9 | -1539.7 |
| D direct_ALMs | 2082.6 | 542.9 | -1539.7 |
| D placed_ALMs | 2095.2 | 550.1 | -1545.1 |
| D registers | 2003 | 344 | -1659 |
| D M10Ks | 1 | 7 | +6 |

## Physical RAM proof

The following are fitted RAM Summary rows, rather than source inference.

| Variant | RAM | Implemented dimensions A / B | M10Ks |
|---|---|---|---:|
| 5l | I entries | 64 × 37 / 64 × 37 | 1 |
| 5l | D entries | 64 × 38 / 64 × 38 | 1 |
| banked | I entries | 64 × 37 / 64 × 37 | 1 |
| banked | I tag_rows | 8 × 192 / 8 × 192 | 6 |
| banked | D entries | 64 × 38 / 64 × 38 | 1 |
| banked | D tag_rows | 8 × 192 / 8 × 192 | 6 |

## Routed timing

Setup and hold slacks are nanoseconds; negative setup means timing does not close.

| MHz / corner | 5L setup | Banked setup | Delta | 5L hold | Banked hold |
|---|---:|---:|---:|---:|---:|
| 78 / name: 7_slow_1100mv_100c
display_name: Slow 1100mV 100C Model
model: slow
temperature: 100
voltage: 1100 | -1.517 | -0.558 | +0.959 | 0.250 | 0.243 |
| 78 / name: 7_slow_1100mv_-40c
display_name: Slow 1100mV -40C Model
model: slow
temperature: -40
voltage: 1100 | -1.636 | -0.639 | +0.997 | 0.146 | 0.113 |
| 78 / name: MIN_fast_1100mv_100c
display_name: Fast 1100mV 100C Model
model: fast
temperature: 100
voltage: 1100 | 2.959 | 2.816 | -0.143 | 0.135 | 0.130 |
| 78 / name: MIN_fast_1100mv_-40c
display_name: Fast 1100mV -40C Model
model: fast
temperature: -40
voltage: 1100 | 3.491 | 3.447 | -0.044 | 0.112 | 0.062 |
| 104 / name: 7_slow_1100mv_100c
display_name: Slow 1100mV 100C Model
model: slow
temperature: 100
voltage: 1100 | -4.722 | -3.763 | +0.959 | 0.250 | 0.243 |
| 104 / name: 7_slow_1100mv_-40c
display_name: Slow 1100mV -40C Model
model: slow
temperature: -40
voltage: 1100 | -4.841 | -3.844 | +0.997 | 0.146 | 0.113 |
| 104 / name: MIN_fast_1100mv_100c
display_name: Fast 1100mV 100C Model
model: fast
temperature: 100
voltage: 1100 | 1.586 | 1.938 | +0.352 | 0.135 | 0.130 |
| 104 / name: MIN_fast_1100mv_-40c
display_name: Fast 1100mV -40C Model
model: fast
temperature: -40
voltage: 1100 | 2.587 | 2.623 | +0.036 | 0.112 | 0.062 |

Worst setup endpoints are retained in the machine evidence. Existing unconstrained external SDRAM delay/forwarded-clock coverage limitations remain; this is not full board timing verification.

## Attribution and functional limits

Both actual checkout SHAs match their publication receipts. All 178 selected input paths match, and only the following seven hashes differ:

- `rtl/arm/zap_cache.sv`
- `rtl/arm/zap_core.sv`
- `rtl/arm/zap_cp15_cb.sv`
- `rtl/arm/zap_dcache.sv`
- `rtl/arm/zap_top.sv`
- `rtl/arm920/tlb.sv`
- `rtl/arm920/tlb_bank.sv`

The effective QSF, seed/debugger settings, production BRAM, physical PLL and unique module definitions match exactly. All 60 qualified CPU/integration RTL/header hashes were checked before publication. ZAP patches0081 and0082 replay byte for byte. The normal remote name and `asturur/test_template_1` resolve to the same repository. Both artifacts pass all 16 SDRAM DQ input/output/OE register checks.

The original warmed workloads, JPEG, spans and 224-start/224-clock load stream remain unchanged from qualified 5L. Banked late-row lookups and misses take 2–9 sampled edges; cold wrappers and mutations cost more. The short data-ordering diagnostic regresses 381→455 clocks (+19.42% at zero wait). These measured costs remain relevant despite the fitted area result. See [functional evidence](tlb-area.md) and [5L qualification](cpu-late-operand.md).

## Retained artifacts

| Variant | Bytes | RBF SHA256 |
|---|---:|---|
| 5l | 4,579,072 | `c8aaaa0621a16758455ee3032055c98cd130f4214bec009e3bdd6c3b7c0be046` |
| banked | 4,512,724 | `61a12540fbe3891eb8196bb94cf8035e394e95cc212349be995a85fd55dc43de` |

Full source manifests, artifact paths, eight timing corners, RAM rows and resource values are in [machine evidence](evidence/tlb-matched-fit-20261117.json). Complete downloaded reports and bitstreams remain under `build/fit/tlb-matched-20261117/{5l,banked}/`. Reusable preparation/publication/collection helpers are in `tools/tlb_matched_fit/`. No 5M or unrelated optimization was included.

The published banked third-slot fit follows the same seed and clock
settings. [Third-slot resource and timing delta](tlb-banked-third-fit.md)
