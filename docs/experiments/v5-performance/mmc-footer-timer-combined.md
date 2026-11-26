# MMC footer CRC fit candidates after the timer trial

The two candidates use the sealed footer patch SHA-256 `1f41e4feed53c1345dd3a114d0a99eaf8b0e4b21cf21c354999535377200d9f2`. The timer patch and its measured hashes match the archived `timer-write-prepare` catalog entry. Applying both patches in either order gives the same combined tree.

| Timer result | Forward restore | Candidate | Candidate tree |
| --- | --- | --- | --- |
| Keep timer | Direct child of `9f16d1a5b5bd5b255eb8f0b1a131399b7dcfb56e` | `3e3dc325a809e0010c77fd1ec23216495bbd15a8` | `a32c7cce787612b6db0ec0cd7770a88f79c7350f` |
| Park timer | `8f226fa1a378fc4e4a986f34f0e49e2c901d1cb9` | `83077b593f568473e1925b404d1ab1732fc22d13` | `d278959da4ac76369a035f521b5eaf4ea4eb503a` |

The restore is a child of the timer-only tip and has retained tree `8406276acdc60d658e189d09d31b0699217717ba`. The two candidate commits each change only `rtl/ngage_mmc_hps.v` relative to their parent. Its SHA-256 is `0df16bfd82217bd5fb600ad37d472d668b98aca4fbae759c2b101651a376d342` in both candidates.

Production preflight rebuilt the effective QSF and checked the manifests at physical 104 MHz with DDR debug off for seeds 13, 43 and 31337. Against retained runs 45771268571, 45771267820 and 45771266151, the 133 selected inputs differ in the footer adapter on the footer-only lineage. The combined lineage also differs in `ngage_timers.v`, `ngage_upp.v` and `ngage_upp_peripherals.v`. The timer's two adjusted testbenches stay outside the build.

## Combined qualification

An archive of the combined candidate supplied the changed source files. The direct HPS suite matched 48 cases and the three-slot test with Verilator, retained `hps_io` and the native MMC card matched 604,018 clocks, 20 card reads and four card writes. The footer source fingerprint matches the prior 82-case expanded standalone CRC qualification.

The physical pin replay exercised the actual RTL backing adapter and native card against the simulated HPS peer. It matched 171,496 traffic records at 1,201,547 clocks, including CMD24 DMA write persistence and PIO readback. The active timer/MMC/LCD replay also matched all 171,497 records and 1,201,528 clocks. The latter verifies timer 4 expires while the MMC interrupt and LCD DMA activity are still present. Both compile the same four qualified RTL files from a 114-source deck.

The frozen workload deck matched all 105 fixed windows and four native frames, along with their guest output, architectural and valid-write digests. Those builds included all four changed files and left the MMC adapter uninstantiated. The HPS and pin-model tests observe adapter behavior directly. [Combined qualification receipt](../../evidence/v5-104-mmc-footer-timer-combined.json)

## Reproduce

Restore the helpers from the [replay patch](patches/mmc-footer-timer-combined-replay.patch) in the repository root. The script uses the archived MMC footer and timer patches and receipts, the prior timer dispatch object's complete alternate chain, the saved Wishbone observers and the existing frozen workload and mixed pin-model decks. The overlap program uses the existing ARM cross-toolchain.

```sh
area=scratch/v5-fit-loop/mmc-footer-timer-combined
git apply docs/experiments/v5-performance/patches/mmc-footer-timer-combined-replay.patch
python3 -B "$area/prepare-fit.py"
sh "$area/qualify.sh"
```

The private object directory and its alternates are recorded in `dispatch-20261126/prepare.json`. To inspect without changing the working checkout or index, set `GIT_OBJECT_DIRECTORY` to the private object directory, read `GIT_ALTERNATE_OBJECT_DIRECTORIES` from the adjacent `alternate-objects.txt`, and use `git show` with the exact candidate SHA.
