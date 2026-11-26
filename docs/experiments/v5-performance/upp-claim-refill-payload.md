# UPP claim presence on either two-cut outcome

The standalone UPP claim patch and its reset qualification are in the [standalone experiment notes](upp-claim-presence.md). The timing experiment changes only `rtl/ngage_upp_peripherals.v`, SHA-256 `9dac7a372428e6e422eaf8e57894febe415fc9d65a76fb0a17667621df0db80c` in either candidate. Both private lineages are forward descendants of `ab75a622a80a5aedae347f63ae195f3da965815a`.

| Selected control | Forward parent | Candidate | Candidate tree |
| --- | --- | --- | --- |
| Timer only | `63bb12f3486bb46000825b85542253c270653dee` | `af86e9674613a1a09ce081e8e8135ae66a52aff9` | `dd90394f2bbd952eb8df84fc7df09efcc40b517d` |
| Two-cut refill and SDRAM capture | `ab75a622a80a5aedae347f63ae195f3da965815a` | `96d108d2e44b3e3b630820fe2fa43f9e13cce702` | `f39825ce22645805f4176bba4fd19d244ef046dc` |

The timer forward restore reproduces tree `0ccd13d8cd502bc14d3b89c6431ff0ebe4745612`. The candidate then reproduces the exact qualified standalone tree. The two-cut candidate matches the independently qualified refill wrapper, block payload arbiter and Template opt-in, with the same UPP bytes as the standalone patch. The target remains 104 MHz DDR with debugging disabled. Local preflight checks all 133 selected inputs at seeds 13, 43 and 31337, confirming the sole UPP delta versus each selected control. The timer control runs are 45824513460, 45824520116 and 45824525843. The two-cut reference is `ab75a62` on runs 45879015397, 45879019116 and 45879022396. When its routed manifests are unavailable, the script verifies the exact previously sealed two-cut preflight manifests.

## Combined replay

All 105 fixed windows and four native frames matched the exact two-cut replays on cycles, guest outputs, architectural and Wishbone-write digests. All 15 repeats and 15 wrong-output controls passed. The frame clocks were 14,391,395, 14,467,552, 14,346,201 and 14,303,223.

| Model run | Matched records | Guest clocks |
| --- | ---: | ---: |
| Normal physical | 171,496 | 1,201,547 |
| Timer/MMC/LCD | 171,497 | 1,201,528 |
| CPU block eviction | 172,060 | 1,204,706 |
| Warm CPU Hold during active MMC/HPS transfer | 171,518 | 1,203,504 |

The block eviction case checks both full 128-bit masked CPU commands and ARM readback. The warm hold has five HPS reads, one persisted write, no audio underflow and the exact matched held PCM signature `015ec64f`. The RTC/timer and playback settings are unchanged. The two workload executables enable native CPU lines and the combined arbiter option. The mixed pin executables reuse the validated scalar CPU and native LCD pin deck. The exact three modified RTL fingerprints are checked in both workload executables and the mixed/hold pair. The independently qualified UPP claim test includes warm and cold reset, overlap priority and unauthorized/unsupported response handling.

[Fit preflight](../../evidence/v5-104-upp-claim-refill-payload-preflight.json) · [Replay receipt](../../evidence/v5-104-upp-claim-refill-payload.json) · [Replay patch](patches/upp-claim-refill-payload-replay.patch)

## 104 MHz fit

The combined refill and SDRAM tree stays as an experimental base because
seed 13 improves to −2.006 ns. Its median result remains behind timer-only.
The UPP candidate `96d108d` is its direct child, with 104 MHz production and
DDR debug off. The corresponding three `ab75a62` fits are the controls.
[Seed 13](https://github.com/asturur/test_template_1/actions/runs/45883742970) · [Seed 43](https://github.com/asturur/test_template_1/actions/runs/45883746480) · [Seed 31337](https://github.com/asturur/test_template_1/actions/runs/45883749964)

## Reproduce both lineages and the combined replay

Use the standalone sealed patch and proof, the private two-cut object chain, and the exact archived two-cut replay under `build/sim/v5-104-refill-payload-combined`. The timer hold workload and the original pin guests come from that common pin lineage. The block eviction and timer-overlap program overlays live under `build/sim/v5-104-sdram-block-payload`.

```sh
set -eu
area=scratch/v5-fit-loop/upp-claim-refill-payload
out=build/sim/v5-104-upp-claim-refill-payload
patches=docs/experiments/v5-performance/patches
git apply "$patches/upp-claim-refill-payload-replay.patch"
cp "$patches/upp-claim-refill-payload-replay.patch" "$area"
python3 -B "$area/prepare-fit.py"
sh "$area/stage.sh"
mkdir -p "$out"
docker image inspect -f '{{.Id}} {{.Os}}/{{.Architecture}}' jotego/simulator:arm64 > "$out/image.id"
for variant in fixed native; do
    python3 -B "$area/replay.py" "$variant" --output qualification
done
sh "$area/pins.sh"
sh "$area/hold.sh"
python3 -B "$area/record.py"
```

The command below exposes both staged histories locally from the repository root.

```sh
area=scratch/v5-fit-loop/upp-claim-refill-payload/dispatch-20261126
export GIT_OBJECT_DIRECTORY="$PWD/$area/objects"
export GIT_ALTERNATE_OBJECT_DIRECTORIES="$(cat "$area/alternate-objects.txt")"
git log --oneline --max-count=3 "$(cat "$area/claim-on-timer.sha")"
git log --oneline --max-count=2 "$(cat "$area/claim-on-two-cut.sha")"
```
