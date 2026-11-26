# W completion on the two-cut or UPP control

Both private candidates extend UPP commit `96d108d2e44b3e3b630820fe2fa43f9e13cce702`. The scoped [W completion report](w-completion-prepare.md) covers the routed source, unchanged completion edges, original parameter and hinted-LDM generator behavior, and the new synchronous next-state feedback to the registered class.

| Selected control | Forward parent | Candidate | Exact candidate tree |
| --- | --- | --- | --- |
| Two-cut refill and block capture | `8b09c95982da503c801dd992af4cecfc715805f8` | `e2249e46c0bd47ab85539cff9416a51214c1ea05` | `16e1167f14b7d08012d73a3615481f7e0445918c` |
| UPP claim plus two-cut | `96d108d2e44b3e3b630820fe2fa43f9e13cce702` | `df86f6bda63566eb953577e1569e2b10853b6b74` | `19c308ff842c33340b101f57bff3e07176c2b8fd` |

The first parent restores the exact `ab75a62` tree `57cc1a796acc9b15a61522ccf2397230f38e9799`. The exact two-file patch is the same on either parent. Its compiled CPU SHA-256 is `ee00c54b1bece117477a7f7ac39769567fa32a8f6b5c78edea00418f3b4cfa5f`. All six effective production manifests have 133 inputs, 104 MHz and DDR debugging off, with only the generated CPU different versus the selected controls. The two-cut leg uses routed controls 45879015397, 45879019116 and 45879022396. The UPP leg uses the sealed input manifests tied to running controls 45883742970, 45883746480 and 45883749964. The script checks the actual UPP routed manifests when those are locally available.

## Combined functional results

The candidate with UPP matches all 105 fixed windows, 15 repeated cases, 15 intentionally wrong outputs and four native frames against the exact UPP parent. Guest cycles, architectural events, ordered write digests and output match. Native clocks are 14,391,395, 14,467,552, 14,346,201 and 14,303,223. The pinned CPU generator check passes. Exact generated CPU, UPP peripheral, native refill wrapper and block capture arbiter fingerprints are present in both workload executables and the physical and warm reset pin builds.

| Combined pin run | Byte-exact records | Guest clocks |
| --- | ---: | ---: |
| Normal | 171,496 | 1,201,547 |
| Timer/MMC/LCD overlap | 171,497 | 1,201,528 |
| CPU eviction with two full block commits | 172,060 | 1,204,706 |
| Warm CPU Hold during MMC/HPS transfer | 171,518 | 1,203,504 |

[Fit preflight](../../evidence/v5-104-w-completion-upp-preflight.json) · [Qualification receipt](../../evidence/v5-104-w-completion-upp.json) · [Replay patch](patches/w-completion-upp-replay.patch)

## Reproduction

Use the sealed standalone patch and receipt from `scratch/v5-fit-loop/w-completion-prepare`, the already staged UPP private object chain and the original frozen 104 MHz decks. The comparison is `build/sim/v5-104-upp-claim-refill-payload`. The archived CPU block and timer guest overlays are under `build/sim/v5-104-sdram-block-payload`.

```sh
set -eu
area=scratch/v5-fit-loop/w-completion-upp
out=build/sim/v5-104-w-completion-upp
patches=docs/experiments/v5-performance/patches
git apply "$patches/w-completion-upp-replay.patch"
cp "$patches/w-completion-upp-replay.patch" "$area"
python3 -B "$area/prepare-fit.py"
sh "$area/stage.sh"
mkdir -p "$out"
docker image inspect -f '{{.Id}} {{.Os}}/{{.Architecture}}' jotego/simulator:arm64 > "$out/image.id"
for measure in fixed native; do
    python3 -B "$area/replay.py" "$measure" --output qualification
done
sh "$area/pins.sh"
sh "$area/hold.sh"
python3 -B "$area/record.py"
```

Inspect the two prepared histories from the repository root.

```sh
area=scratch/v5-fit-loop/w-completion-upp/dispatch-20261126
export GIT_OBJECT_DIRECTORY="$PWD/$area/objects"
export GIT_ALTERNATE_OBJECT_DIRECTORIES="$(cat "$area/alternate-objects.txt")"
git log --oneline --max-count=3 "$(cat "$area/w-on-two-cut.sha")"
git log --oneline --max-count=2 "$(cat "$area/w-on-upp.sha")"
```
