# MMC HPS owner cancellation after the footer trial

Both private candidates retain the routed timer tree. The owner patch applies directly to both bases. Applying the owner and CRC patches in either order produces the same kept-footer tree. The standalone cancellation and CRC proofs still apply because the owner patch changes the validity predicate and the footer patch changes only the source of the bytes consumed during VERIFY. The exact combined miter checks both at their existing clock edges.

| Footer result | Forward restore | Candidate | Candidate tree |
| --- | --- | --- | --- |
| Park | `409fb8738cae1dc192216fe8043e2d60ede7809d` | `efc761a0d84e99d477336f54b87b07b15f5b343a` | `895944462f1cef78eb92f3cdfa5f7047fdfb46a5` |
| Keep | Direct child of `3e3dc325a809e0010c77fd1ec23216495bbd15a8` | `2fd6a88fc6e791bcfb32c8659001435afb367775` | `b4dfe33c2e1ba68e1e23ff199248d1e8d57ce848` |

The forward restore is a child of `3e3dc32` with the exact `9f16d1a` timer tree `0ccd13d8cd502bc14d3b89c6431ff0ebe4745612`. Both new candidate commits change only `rtl/ngage_mmc_hps.v` relative to their parent. The parked-footer HPS hash is the archived owner hash `1578f8fd6f8065dc9bd96e7d5cd32d426c9664f7986c17a78440cf7ac84fb13a`. The kept-footer HPS hash is `9c6ad985759d1d277cf01a7f88d6c222664a5ec8efde015ab3e6d7db387fd0c0`. Use the [standalone owner patch](patches/mmc-hps-cancel-owner.patch) or the [footer-based owner patch](patches/mmc-hps-cancel-owner-on-footer.patch).

The six production preflights match physical 104 MHz, DDR debugger off, and the effective QSF for seeds 13, 43 and 31337. Of 133 compiled inputs, only the HPS adapter differs from the measured timer controls 45824513460, 45824520116 and 45824525843. The kept-footer variant also differs from the staged parent manifest solely in the HPS adapter. The source archives used for simulation come directly from those candidate commits.

## Qualification

Each candidate was qualified separately with the pinned Jotego ARM64 image.

- The 48-case HPS directed suite and the actual three-slot `hps_io` and native card matched at 604,018 clocks. The differential owner miter compared 379,781 points, including 448 directed combinations, 49 counter wraps, 24 reserved-state recoveries, and 7,168 randomized edges. The retained leg carries the prior footer transformation when testing the kept-footer branch.
- The expanded 82-case CRC and invalid-ingress suite matched the retained 1,186 verification edges, including corrupt protected bytes, another slot's writes, and reset or remount during VERIFY. The timer held-request differential matched 8,192 selects, 6,025 responses, and 8,397 records.
- The normal physical SDRAM/HPS replay matched 171,496 records over 1,201,547 clocks. The timer, MMC, and LCD overlap replay matched 171,497 records over 1,201,528 clocks. Both exercised the native card and actual backing adapter in the pin model.
- All 105 fixed windows and four native frames matched with the same architectural, guest-output and valid-write digests. The frozen guest decks select the patched sources for compilation and leave the HPS adapter dormant. Its active coverage comes from the direct and physical tests. The replay manifests match all four changed production RTL hashes.

Both candidates await routed area and timing. [Combined qualification receipt](../../evidence/v5-104-mmc-hps-owner-timer-combined.json)

## Reproduction

Apply the [combined replay patch](patches/mmc-hps-owner-timer-combined-replay.patch) and run from the repository root. The script uses the prior footer dispatch object directory and its recorded alternate chain, the archived design patches and receipts, the frozen prepared Wishbone workloads and physical pin decks, and the existing offline simulator and ARM GNU toolchains.

```sh
area=scratch/v5-fit-loop/mmc-hps-owner-timer-combined
catalog=docs/experiments/v5-performance
git apply "$catalog/patches/mmc-hps-owner-timer-combined-replay.patch"
python3 -B "$catalog/verify.py" timer-write-prepare mmc-footer-crc-direct mmc-hps-cancel-owner
python3 -B "$area/prepare-fit.py"
for variant in owner-plus-timer owner-plus-footer-timer; do
  sh "$area/qualify.sh" "$variant"
done
```

Set `GIT_OBJECT_DIRECTORY` to `$PWD/$area/dispatch-20261126/objects` and `GIT_ALTERNATE_OBJECT_DIRECTORIES` to the contents of the adjacent `alternate-objects.txt` to read the private commits. Fit reports and replay receipts are indexed by candidate. Full compiled-source manifests and test outputs are under `build/sim/v5-104-mmc-hps-owner-timer-combined`.
