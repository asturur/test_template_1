# Use the A stage for all ARM multiply products

This experiment starts at the exact timer source `9f16d1a5b5bd5b255eb8f0b1a131399b7dcfb56e`, tree `0ccd13d8cd502bc14d3b89c6431ff0ebe4745612`. The phone generator omits its early SMULL transform. The helper remains available to the existing experimental callers. The regenerated CPU changes only `ngage2_arm9v2_execute`, and the pinned generator check passes. The archived local fit manifests examined during staging contained no instance of this candidate CPU hash.

## Donor and routed baseline

The donor `ngage2` master snapshot `bb05197cb97abe3066d2db9fe5e2b9144efe723d` feeds its signed DSP operands from latched `A.right` and `A.special` during the private `product_phase`. The retained phone execute unit also lets a qualified unconditional non-accumulating ARM SMULL launch on the S-to-A edge. That case selects live forwarded and decoder operands in front of the same DSP. The candidate uses the original private A product phase for those operations. Both multiplicands now come from the existing non-retimed A packet. The phone's direct accumulate transform remains active and consumes the registered product on the existing finishing phase.

| Timer seed | Decoder to execute paths below −1.5 ns | Ending at `Mult0` | Worst multiplier slack | Detailed launch and path |
| --- | ---: | ---: | ---: | --- |
| 13 | 39 | 36 | −1.634 ns | `o_forward_grant[28]` → `w_take` → `product_left[3]` → low partial product |
| 43 | 37 | 34 | −1.558 ns | `o_forward_grant[27]` → forwarded operand → `shift_input_nw[0]` → `product_left[0]` → cross-product adder |
| 31337 | 65 | 64 | −1.699 ns | `values[56]` → `operand1_nw` → `shift_input_nw[24]` → `product_left[24]` → high partial product |

These are hot TimeQuest paths from production physical 104 MHz with DDR debug off. The RTL removes the live operand connection to the multiplier. The candidate's routed slack and area await a fit.

## Measured cycles

All 105 fixed windows passed the guest and architectural digest checks, including all 15 repeated workloads and wrong-output controls. Fourteen windows change, all from the two cases below. Every game window and the other fixed cases match cycle for cycle. The equal-weight fixed-work throughput index is 99.596 with timer baseline 100. All fixed Wishbone trace digests match.

| Fixed workload | Timer warm median | A-only warm median | Change |
| --- | ---: | ---: | ---: |
| Matrix4 | 16,946 | 17,945 | +999 clocks, +5.895% |
| Triangle edges | 12,226 | 12,268 | +42 clocks, +0.344% |

Native PolyCount output and all four architectural digests match. The timing-sensitive Wishbone trace differs, and both legs acknowledge 278,165 writes with zero write errors.

| PolyCount | Timer clocks | A-only clocks | Clocks added |
| --- | ---: | ---: | ---: |
| Frame 0 | 14,391,395 | 14,571,509 | 180,114 |
| Frame 1 | 14,467,552 | 14,648,548 | 180,996 |
| Frame 2 | 14,346,201 | 14,526,176 | 179,975 |
| Frame 3 | 14,303,223 | 14,482,866 | 179,643 |
| Total | 57,508,371 | 58,229,099 | 720,728 |

The total cost is +1.253%. The warm median goes from 14,346,201 to 14,526,176 clocks, +1.255%.

The four directed board profiles cover signed and unsigned multiply, direct accumulate and carry, condition failure, flags, warm and cold forwarding, an LDM operand pair, and a precise abort before a dependent multiply. Both legs match the architectural write digest in the multiply windows. The timer control executes five private product clocks and ten early products, two with a W-forwarded operand. The candidate executes fifteen private product clocks. The complete guest adds six to eight clocks across the four profiles.

The candidate has known benchmark costs and requires a substantive gain in routed timing for retention. [Measurement receipt](../../evidence/v5-104-arm9-a-only-product.json)

The [combination with TLB victim and MMC FIFO RAM](arm9-a-only-product-ram-combined.md)
reproduces the same benchmark cycle costs and matches the joint RAM
control in both pin traces.

## 104 MHz fit

The joint RAM change was parked. Standalone A-stage candidate `9229940`
builds above exact timer restore `b9d8609`, with physical 104 MHz and DDR
debug off. The matched control is timer-only `9f16d1a`. [Seed 13](https://github.com/asturur/test_template_1/actions/runs/45874467913) · [Seed 43](https://github.com/asturur/test_template_1/actions/runs/45874473714) · [Seed 31337](https://github.com/asturur/test_template_1/actions/runs/45874483394)

## Reproduction

Use the existing timer-base objects and receipts, frozen fixed and PolyCount decks, cached Jotego ARM64 image, and ARM GNU tools. The directed test reuses the multiply blocks from the archived early-shift fixture patch. Run from the repository root.

```sh
area=scratch/v5-fit-loop/arm9-a-only-product
timer=scratch/v5-fit-loop/timer-live-trust-combined/dispatch-20261126
patches=docs/experiments/v5-performance/patches
for leg in reference source; do
  mkdir -p "$area/$leg"
  env GIT_OBJECT_DIRECTORY="$PWD/$timer/objects" \
    GIT_ALTERNATE_OBJECT_DIRECTORIES="$(cat "$timer/alternate-objects.txt")" \
    git archive 9f16d1a5b5bd5b255eb8f0b1a131399b7dcfb56e rtl tools \
      tests/cpu/arm9v2_board tests/cpu/spmark_payload sim/programs/link.ld | tar -x -C "$area/$leg"
done
git apply "$patches/arm9-a-only-product-replay.patch"
git apply --directory="$area/source" "$patches/arm9-a-only-product.patch"
cp "$patches/arm9-a-only-product.patch" "$patches/arm9-a-only-product-replay.patch" "$area"
cp "$area/source/rtl/ngage_cpu.sv" "$area/ngage_cpu.sv"
for leg in reference source; do
  python3 -B "$area/$leg/tools/gen_arm9v2_phone.py" \
    --stock build/arm9v2-assoc/stock-pinned.v --check
done
sh "$area/board.sh"
for kind in fixed native; do
  python3 -B "$area/replay.py" "$kind" --output qualification
done
python3 -B "$area/record.py"
```
