# Prepare W completion eligibility beside W

The exact comparison starts at `ab75a622a80a5aedae347f63ae195f3da965815a`, tree `57cc1a796acc9b15a61522ccf2397230f38e9799`, on the 104 MHz DDR configuration with debugging disabled. The private candidate tree is `16e1167f14b7d08012d73a3615481f7e0445918c`. The [Git patch](patches/w-completion-prepare.patch) changes the pinned generator and only `ngage2_arm9v2_core` in the emitted CPU. The prepared version uses five additional bits. Standalone `W_CLASS=0` uses the original live classifier. The optional `--hinted-ldm` generator retains its exact original output, including its two-beat LDM override.

## Routed timing witness

The two-cut seed 13 hot worst setup is −2.006 ns with core TNS −2674.880 ns. Independent detailed hot and cold paths identify the same launch and destination.

| Seed and slow corner | Path | Slack |
| --- | --- | ---: |
| 13 hot rank 1 | `w[541]` through `complete_class[0]` and `ready_if_hit` to `a[241]` | −2.006 ns |
| 13 cold rank 1 | Same W validity and preparation path | −1.994 ns |
| 13 hot rank 3 | Decode `o_forward_grant[25]` through operand selection and rotate to `a[233]` | −1.943 ns |
| 13 cold rank 3 | W load-owner `w[527]` through direct register shift to `a[233]` | −1.946 ns |
| 43 hot rank 1 | W destination `w[93]` through `s_wait_w_nohit` and `ready_if_nohit` to `a[239]` | −2.636 ns |
| 43 cold rank 1 | Same destination wait path | −2.570 ns |

The three A endpoints are bits 23, 15 and 21 of the same 32-bit right-operand slot. The preparation cuts the class dependence on W validity that qualifies the successful hit release through `wb_valid`. In each of seed 13's slow top-100 detailed samples, four paths launch from `w[541]` and touch `complete_class`. They include two right-operand destinations and two check-record bits. Three of those four are below −1.5 ns in the hot sample and two in the cold. The direct data shift and same-destination no-hit comparator are separate paths. Seed 43 has 13 hot and 16 cold sampled routes through `s_wait_w_nohit`. The new staging targets the W completion class, while the six-bit destination compare and raw W-valid use in vacancy and older-writer guards remain active.

## Exact edge and feedback behavior

On the same edge that clocks `w_next` and `memory_state_next`, the new register clocks five static eligibility terms. The static exception, CP and SWP bits come from `w_cls_next[5:3]`. A W replacement installs those bits from the incoming M record. A held record preserves them. The SWP transition updates a different classification bit, and clearing W validity zeroes the new mask.

The original priority yields immediate ABORT completion, exception after all locks clear, CP after the coprocessor finishes, saved-load completion after the owner unlocks with SWP excluded, or ordinary RUN/HOLD completion. Ordinary non-memory records get an immediate term. The original live completion term still evaluates request done, retry, response error and fast PC hit, or deferred load in the alternate setting. A regular non-memory record can also have the memory-event arm evaluated. That preserves the original Boolean behavior when a memory bit or response is unknown in simulation.

The current `wb_flush` still masks the result before it can feed architectural completion. A live block transfer error retains the higher-priority restoration override. The same completion bits feed writeback, forwarding and vacancy, with the original three consumers and untouched exception decoding. The simulation-only check compares all three bits with the original logic on every active core clock.

The eligibility register samples every normal clock, including those where W holds but the memory state changes. There is no new functional hold or pipeline edge. There is a new synchronous feedback path from eligibility Q through completion and `done` to W and memory next-state selection and back to eligibility D. Live ACK, retry and defer can also reach eligibility D through next-state selection. The pre-existing W-valid contribution to `done` can reach that D-side path. This is a new registered destination for late effects. Its routed setup and physical hold have yet to be measured.

## Replay results

- The extracted miter matched 4,231,172 comparisons across both values of `W_CLASS` and `COMPLETE_FLAT`. It exhausts 512 W/state packets against 2,048 live flag patterns, including reset and 4,096 four-state samples. The full core assertion also checks the held packet and precise completion in the timed replays.
- Four burst/wait board profiles passed exact traces, with two SWP beats, two walks, a clean write and the prefetch abort in each. The additional four alignment and external-abort profiles check the preserved destination, CP15 status, and a successful younger load to the same destination.
- All 105 fixed windows, 15 repeats, 15 rejected wrong-output tests and four native frames match cycles, architectural and Wishbone digests and guest output. The native frame clocks are 14,391,395, 14,467,552, 14,346,201 and 14,303,223.
- The four mixed pin replays match byte for byte. Normal has 171,496 records. Timer/MMC/LCD has 171,497. CPU block eviction has 172,060 and includes both expected full masks, written payloads and guest readback. Warm CPU Hold during active MMC/HPS has 171,518 and preserves the warm hold PCM reference and CMD24 persistence.
- Both normal generators match the pinned donor outputs. Both hinted-LDM outputs match each other exactly. The actual fixed, native, board and pin model executable manifests carry the exact candidate generated CPU.

[Route evidence](../../evidence/v5-104-w-completion-prepare-routes.json) · [Qualification receipt](../../evidence/v5-104-w-completion-prepare.json) · [Replay patch](patches/w-completion-prepare-replay.patch)

The [combination with UPP claim preparation](w-completion-upp.md) also matches both workloads and all four pin replays.

## 104 MHz fit

The UPP candidate was parked. The standalone W completion candidate
`e2249e4` builds above `8b09c95`, a forward restore of the exact combined
refill and SDRAM `ab75a62` tree. All three use physical 104 MHz with DDR
debug off. [Seed 13](https://github.com/asturur/test_template_1/actions/runs/45888184228) · [Seed 43](https://github.com/asturur/test_template_1/actions/runs/45888187846) · [Seed 31337](https://github.com/asturur/test_template_1/actions/runs/45888191508)

## Routed decision

Park `e2249e4`. All three builds pass hold, recovery, removal, minimum
pulse width and SDRAM pin registers. All three fail 104 MHz setup.

| Seed | Worst setup, combined base → prepared W | Core TNS delta | Occupied ALM delta | Estimated ALMs needed delta |
| ---: | ---: | ---: | ---: | ---: |
| 13 | −2.006 → −3.182 ns | −5,376.552 ns | +260 | −778 |
| 43 | −2.636 → −3.038 ns | −1,435.497 ns | +272 | −687 |
| 31337 | −2.902 → −3.021 ns | −2,055.177 ns | +279 | −782 |

All 16 sampled hot routes from W-valid through `complete_class` on
seed 13 disappear. The new eligibility endpoint appears in seed 43 at
−1.672 ns hot and −1.349 ns cold. Whole-core median setup and TNS regress
by 0.402 and 2,929.802 ns respectively. The paired median TNS delta is
−2,055.177 ns. The estimated ALMs-needed reduction accompanies 272 more
occupied ALMs at the paired median. Other paths now limit the chip,
including UPP lane decode into Wishbone error and two SDRAM/DMA routes.
[Matched fits and hot routes](../../evidence/v5-104-w-completion-prepare-fits.json)

## Reproduction

Use the cached Jotego ARM64 simulator, pinned `build/arm9v2-assoc/stock-pinned.v`, the two-cut object chain and its archived build inputs. The frozen fixed/native workloads are under `build/sim/{payload-clocks,polycount}/v5-104-all-four-ram-candidate` with the compile deck `scratch/refill-issue-739d3bd/leg`. The two-cut builds under `build/sim/v5-104-refill-payload-combined` provide exact comparison rows and physical inputs. The timer overlap and block eviction guest overlays come from `build/sim/v5-104-sdram-block-payload`.

Run from the repository root. The design and replay patches reconstruct an empty trial area.

```sh
set -eu
area=scratch/v5-fit-loop/w-completion-prepare
prior=scratch/v5-fit-loop/refill-payload-after-a-only/dispatch-20261126
base=ab75a622a80a5aedae347f63ae195f3da965815a
out=build/sim/v5-104-w-completion-prepare
patches=docs/experiments/v5-performance/patches
git apply "$patches/w-completion-prepare-replay.patch"
cp "$patches/w-completion-prepare.patch" "$patches/w-completion-prepare-replay.patch" "$area"
mkdir -p "$area/objects" "$area/reference" "$area/source" "$out"
printf '%s:%s\n' "$PWD/$prior/objects" "$(cat "$prior/alternate-objects.txt")" > "$area/alternate-objects.txt"
(
    export GIT_INDEX_FILE="$PWD/$area/design.index"
    export GIT_OBJECT_DIRECTORY="$PWD/$area/objects"
    export GIT_ALTERNATE_OBJECT_DIRECTORIES="$(cat "$area/alternate-objects.txt")"
    test "$(git rev-parse "$base^{tree}")" = 57cc1a796acc9b15a61522ccf2397230f38e9799
    git read-tree "$base"
    git apply --cached "$area/w-completion-prepare.patch"
    git write-tree > "$area/design-tree.sha"
    test "$(cat "$area/design-tree.sha")" = 16e1167f14b7d08012d73a3615481f7e0445918c
    for leg in reference source; do
        tree="$base"
        if [ "$leg" = source ]; then tree="$(cat "$area/design-tree.sha")"; fi
        git archive "$tree" Template.sv rtl tools files.qip .rules.verible_format tests sim/programs/link.ld \
            | tar -x -C "$area/$leg"
    done
)
cp "$area/source/rtl/ngage_cpu.sv" "$area/ngage_cpu.sv"
docker image inspect -f '{{.Id}} {{.Os}}/{{.Architecture}}' jotego/simulator:arm64 > "$out/image.id"
sh "$area/check-generator.sh"
sh "$area/proof.sh"
sh "$area/board.sh"
sh "$area/board-phase.sh"
for measure in fixed native; do
    python3 -B "$area/replay.py" "$measure" --output qualification
done
sh "$area/pins.sh"
sh "$area/hold.sh"
python3 -B "$area/routes.py"
python3 -B "$area/record.py"
```
