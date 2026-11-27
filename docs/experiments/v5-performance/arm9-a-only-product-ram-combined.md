# A-stage multiply candidates after the joint RAM trial

Both candidates use the archived A-stage-only multiply behavior. The execute module is byte-identical in both branches and matches the standalone A-only qualification. The DSP launches its product from the existing A packet. The direct accumulate path remains active. No other generated module changes relative to its parent.

| Joint RAM result | Parent or forward restore | A-only candidate | Controls for seeds 13, 43, 31337 |
| --- | --- | --- | --- |
| Keep | `ae3654c75c4ff5027d0bd146baf3c8f5f2280cde` | `441063e7ce20556f092d8fe51ad444cc8225ea93` | 45869671440, 45869675764, 45869680539 |
| Park | `b9d860982456bdb2b5ee925b35c99f3d26315008` | `9229940ac0cd68e10613a624a8d03673bc6b6f9e` | 45824513460, 45824520116, 45824525843 |

The restore has the exact timer tree `0ccd13d8cd502bc14d3b89c6431ff0ebe4745612`. Verified all 133 effective sources at 104 MHz production with DDR debug off across all six manifests. The generated CPU is the sole selected delta versus the appropriate control. For the combined branch, the archived Verilog hunk applies directly and the known generator invocation is deleted in its new TLB context. The [exact combination patch](patches/arm9-a-only-product-on-ram.patch) records that new context. The pinned generator reproduces both exact archives. [Preflight receipt](../../evidence/v5-104-arm9-a-only-product-ram-preflight.json)

## Exact combined replay

The directed multiply guest compares signed and unsigned results, direct accumulate, flags, conditional execution, operand forwarding and a precise abort. All four profiles match architectural writes and move the ten early SMULL products to the existing A-stage product phase. The normal and overlap SDRAM replays match the joint RAM reference at 171,496 and 171,497 records, with actual MMC persistence and PIO readback. The compiled MMC host fingerprint agrees with the prior joint RAM qualification.

The 105 fixed windows and four native frames match guest outputs and ordered architectural digests. Matrix4 adds 5.895% to its warm median and Triangle edges adds 0.344%. The other 91 fixed windows keep their exact cycles. The equal-weight fixed throughput index is 99.596 with joint RAM at 100. The four native frames add 720,728 clocks, or 1.253%. The native Wishbone trace timing changes while both legs acknowledge 278,165 writes with zero write errors. The cycle costs match the standalone A-only replay. [Qualification receipt](../../evidence/v5-104-arm9-a-only-product-ram-combined.json)

These builds measure the timing of the decoder-to-DSP cut. The cycle cost requires a substantive routed WNS and TNS improvement for retention.

## Reproduction

Restore the scripts from the [replay patch](patches/arm9-a-only-product-ram-combined-replay.patch). Use the archived standalone product and joint RAM qualifications, the exact joint RAM dispatch object chain, the pinned ARM donor and cached Jotego image. The frozen workloads and pin deck are from the joint RAM qualification.

```sh
area=scratch/v5-fit-loop/a-only-product-ram-combined
python3 -B "$area/prepare-fit.py"
sh "$area/stage.sh"
sh "$area/qualify.sh"
python3 -B "$area/record.py"
```
