# TLB victim RAM and MMC host FIFO RAM on the 104 MHz timer source

Both hunks in the [design patch](patches/tlb-victims-mmc-fifo.patch) apply directly to timer commit `9f16d1a5b5bd5b255eb8f0b1a131399b7dcfb56e`, tree `0ccd13d8cd502bc14d3b89c6431ff0ebe4745612`. The joint tree is `6ce1695c169affd9c1b9c1d8033724cd49cff637`. The patch changes only the generated CPU, its generator and `rtl/ngage_mmc_host.v`. The generated CPU changes only `ngage2_zap_tlb`. Its victim block and generator transform match the fitted `723e2b7` implementation. The complete MMC host matches the fitted `d790e96` blob. Each cache stays at 16 KiB and two ways. The 256-set, two-way small-page I/D TLBs both select the victim RAM. The pinned donor regenerates the timer and joint netlists exactly.

The TLB bank stores each victim bitmap in 16 RAM rows with resettable row validity. The existing captured walk address supplies the read and update edge. The MMC substitution uses four byte banks, a prefetched card payload and byte-level forwarding when host/card operations collide.

## Matched simulation

| Check | Result |
| --- | --- |
| Small-page collisions and walker | 7,765 clocks in each of the I/D-style walker configurations. Each resolves 1,132 accesses and issues 592 small-page fills, with the original register implementation checked before and after each edge. Covers same-set replacement, invalidation, held transactions and warm reset. |
| MMC host and FIFO | 28 card peer cases each at divider/depth 2/16, 3/16, 4/16 and 12/8. Register-reference pins match cycle for cycle. The bank fixture forces undefined cross-port collisions and passes all masks, 260 wrapped accesses, 939 forwarded cases, 331 simultaneous TX cases and 312 simultaneous RX cases. Verilog-2001 elaboration, 33 CMD16 probes and the divide-by-3 pin clock pass. |
| CPU board | Four burst/wait combinations match the timer reference, including cache line writeback and section walks. |
| Fixed work | All 15 workloads and 105 windows match exact cycles, retire/data/MMIO digests and ordered Wishbone write evidence. All repeat runs match and 15 deliberately wrong outputs are rejected. |
| Native POLYCOUNT | Four matching frames at 14,391,395, 14,467,552, 14,346,201 and 14,303,223 clocks. Same guest output and architectural and Wishbone evidence. |
| Production physical-SDRAM model | Normal replay is byte-exact at 171,496 records and 1,201,547 clocks. Timer/MMC/LCD overlap is byte-exact at 171,497 records and 1,201,528 clocks. Both include CMD24 persistence to the actual card model/backing and PIO readback. |

The fixed, native and physical executables include both substituted RTL files. The physical source manifest matches the timer model on the other 112 files. The test log and source identities are in the [qualification receipt](../../evidence/v5-104-tlb-victims-mmc-fifo.json). Replay output lives in `build/sim/v5-104-tlb-victims-mmc-fifo`. The cached Jotego simulator is `sha256:df6f55924d5fab96083d01332e45cd734f22277c4dd3b34f55a09cd8dbc3eb8d` for Linux ARM64.

## Earlier area measurements

These are separate historical fits against `739d3bd`, measured in the Fitter's `[A] ALMs used in final placement` field. Runs and exact report data are preserved in the receipt.

| Variant | Occupied ALM delta, seed 13 | Seed 43 | Seed 31337 | Median | M10K delta per seed |
| --- | ---: | ---: | ---: | ---: | ---: |
| TLB victim RAM | −511 | −629 | −536 | −536 | +2 |
| MMC host FIFO RAM | −82 | −206 | −212 | −206 | +4 |

Area and setup for the joint timer tree await a routed run. This experiment is staged for the existing 104 MHz DDR configuration with the debugger disabled.

The [configuration with the native refill word-ready flag](tlb-fifo-refill-combined.md)
uses the same RAM implementations. The exact candidate passes the directed
RAM tests and matches all workloads and both physical pin-model replays.

## 104 MHz fit

The word-ready refill trial was parked. Standalone joint RAM candidate
`ae3654c` builds above exact timer restore `6db50ed`, with physical 104 MHz
and DDR debug off. The matched control is timer-only `9f16d1a`. [Seed 13](https://github.com/asturur/test_template_1/actions/runs/45869671440) · [Seed 43](https://github.com/asturur/test_template_1/actions/runs/45869675764) · [Seed 31337](https://github.com/asturur/test_template_1/actions/runs/45869680539)

## Routed decision

Park `ae3654c` for area combinations. All three builds pass hold,
recovery, removal, minimum pulse width and SDRAM pin registers. All three
fail 104 MHz setup.

| Seed | Worst setup, timer → RAM pair | Core TNS delta | Occupied ALM delta | Estimated ALMs needed delta |
| ---: | ---: | ---: | ---: | ---: |
| 13 | −2.214 → −3.080 ns | −2,463.443 ns | −340 | −1,316 |
| 43 | −2.403 → −2.907 ns | −2,918.024 ns | −322 | −1,240 |
| 31337 | −2.452 → −2.665 ns | −1,777.952 ns | −234 | −1,102 |

The paired median saves 322 physically occupied ALMs for six additional
M10Ks. The paired ALMs-needed estimate falls by 1,240 because estimated
recoverable packing rises by 921 at the paired median. Median setup falls
by 0.504 ns and paired median TNS worsens by 2,463.443 ns. The difference of
the control and candidate median TNS is −2,030.470 ns. Two limiting paths
end in general DMA engines. The third is execute flag feedback.
[Matched reports](../../evidence/v5-104-tlb-victims-mmc-fifo-fits.json)

## Reproduction

Use the pinned ARM9 donor at `build/arm9v2-assoc/stock-pinned.v` and the existing cached `jotego/simulator:arm64` image. The workload fixture uses the fixed and native inputs under `build/sim/{payload-clocks,polycount}/v5-104-all-four-ram-candidate`, the original compile deck `scratch/refill-issue-739d3bd/leg`, and the prepared write-data receipt under `scratch/v5-fit-loop/prepared-wb-write-data/candidate`. The timer qualification supplies exact compare receipts and the normal/overlap physical decks in `build/sim/v5-104-timer-write-prepare`. Production controls 45824513460, 45824520116 and 45824525843 and the historical Fitter reports listed in the receipt are used by the final validator.

Run from the repository root. The [replay patch](patches/tlb-victims-mmc-fifo-replay.patch) reconstructs the directed fixtures in an empty trial area.

```sh
set -eu
area=scratch/v5-fit-loop/tlb-victims-mmc-fifo
timer=scratch/v5-fit-loop/timer-live-trust-combined/dispatch-20261126
out=build/sim/v5-104-tlb-victims-mmc-fifo
base=9f16d1a5b5bd5b255eb8f0b1a131399b7dcfb56e
patches=docs/experiments/v5-performance/patches
git apply "$patches/tlb-victims-mmc-fifo-replay.patch"
cp "$patches/tlb-victims-mmc-fifo.patch" "$patches/tlb-victims-mmc-fifo-replay.patch" "$area"

# Use a private Git index and private object directory.
mkdir -p "$area/objects" "$area/reference" "$area/source" "$out"
printf '%s:%s\n' "$PWD/$timer/objects" "$(cat "$timer/alternate-objects.txt")" > "$area/alternate-objects.txt"
(
  export GIT_INDEX_FILE="$PWD/$area/combined.index"
  export GIT_OBJECT_DIRECTORY="$PWD/$area/objects"
  export GIT_ALTERNATE_OBJECT_DIRECTORIES="$(cat "$area/alternate-objects.txt")"
  git read-tree "$base"
  git apply --cached "$area/tlb-victims-mmc-fifo.patch"
  git write-tree > "$area/combined-tree.sha"
  test "$(cat "$area/combined-tree.sha")" = 6ce1695c169affd9c1b9c1d8033724cd49cff637
  for leg in reference source; do
    tree="$base"
    if [ "$leg" = source ]; then tree="$(cat "$area/combined-tree.sha")"; fi
    git archive "$tree" rtl tools .rules.verible_format tests/cpu/arm9v2_board \
      tests/cpu/spmark_payload tests/phone/mmc_host tests/phone/upp_ddr_ram/peer.v \
      tests/phone/direct_sdram tests/phone/upp_bus_bridge sim/programs/link.ld | tar -x -C "$area/$leg"
  done
)
cp "$area/source/rtl/ngage_cpu.sv" "$area/ngage_cpu.sv"
docker image inspect -f '{{.Id}} {{.Os}}/{{.Architecture}}' jotego/simulator:arm64 > "$out/image.id"
sh "$area/directed.sh"
sh "$area/board.sh"
for kind in fixed native; do
  python3 -B "$area/replay.py" "$kind" --output qualification
done
python3 -B "$area/mixed.py"
mixed="$out/mixed"
docker run --rm --pull=never --network none --platform linux/arm64 \
  -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 \
  -ec "sh '$mixed/build.sh'
       '$mixed/obj/Vtb' +upp_stress '+compare_trace=$mixed/traffic.log' > '$mixed/replay.log'"
sh "$area/coexistence.sh"
python3 -B "$area/record.py"
```
