# Native refill candidates after the SDRAM payload trial

The [native-refill word-ready patch](patches/refill-line-word-ready.patch) changes `rtl/ngage_cpu.sv`, whose qualified SHA-256 is `ffd3ec6e88d3f7671e9a0c31efdaef5a6d6d204c41505966a2eae86df8efae11`. Both private candidates follow the public SDRAM payload commit `b7cf9fcef0bf2ea2c1d29ec569b3c0d0a0dcf120`. Applying the two patches in either order reproduces the combination.

| Payload result | Parent or forward restore | Refill candidate | Paired controls for seeds 13, 43, 31337 |
| --- | --- | --- | --- |
| Keep | `b7cf9fcef0bf2ea2c1d29ec569b3c0d0a0dcf120` | `8d72c2b5df2f1ea371ed23a234c930c5e5a1e6dc` | 45856840289, 45856845012, 45856850190 |
| Park | `85b21a4ce143ea09110f7fa9bda0809caf3fbc3b` | `99299836993ad77d812d314c78134ef6727d913e` | 45824513460, 45824520116, 45824525843 |

The forward restore has the exact prepared timer tree `0ccd13d8cd502bc14d3b89c6431ff0ebe4745612`. Preflight verified 104 MHz production with DDR debug off and all 133 effective input hashes for each seed. The only difference from the corresponding selected control in each prepared comparison is the CPU wrapper. The keep comparison uses the payload control's effective-input preflight while its new routed reports are pending. [Preflight receipt](../../evidence/v5-104-refill-payload-preflight.json)

## Combined replay

Candidate `8d72c2b` compiles the exact qualified refill wrapper alongside the production payload opt-in and arbiter. The normal, timer/MMC/LCD and dirty eviction pin traces match the payload control at 171,496, 171,497 and 172,060 events. The eviction case includes both expected full-mask CPU blocks. The wrapper is the sole difference across 114 mixed source hashes. The mixed pin deck exercises scalar CPU SDRAM transactions and native LCD traffic.

All 105 fixed windows and four native frames match the payload control's cycles, architectural events, write digests and guest output. Both frozen guest fixtures enable native CPU refill and production arbiter capture. The independent four-mode refill differential also exercises wide, narrow, error, reject and reset paths. The wrapper and arbiter fingerprints match across fixed, native and mixed decks. [Qualification receipt](../../evidence/v5-104-refill-payload-combined.json)

## 104 MHz fit of both changes

Both isolated changes were parked. The combined trial `ab75a62` has the
exact qualified tree of `8d72c2b`. It builds above an exact timer restore
`6c7ccec`, at physical 104 MHz with DDR debug off. Compare the combination
against timer-only `9f16d1a`. [Final Git and input preflight](../../evidence/v5-104-refill-payload-combined-launch-preflight.json) · [Seed 13](https://github.com/asturur/test_template_1/actions/runs/45879015397) · [Seed 43](https://github.com/asturur/test_template_1/actions/runs/45879019116) · [Seed 31337](https://github.com/asturur/test_template_1/actions/runs/45879022396)

## Reproduction

Restore the helpers from the [replay patch](patches/refill-payload-combined-replay.patch). The preflight uses both sealed design patches and the public payload run receipt with its private object chain. Replays use the cached Jotego simulator and the existing payload benchmark, pin and targeted eviction inputs.

```sh
area=scratch/v5-fit-loop/refill-payload-combined
python3 -B "$area/prepare-fit.py"
sh "$area/stage.sh"
sh "$area/qualify.sh"
python3 -B "$area/record.py"
```
