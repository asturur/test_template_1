# Compact D-cache lock fit candidates behind MMC HPS owner

The compact-lock patch's SHA-256 is `abab9bfe0e0a7bb369e52baa3f7d8654d48d2ef0199f9646658283403e61e530`. It reproduces the qualified generated CPU and generator hashes in both lineages. The archived MMC owner patch reconstructs the active `efc761a0d84e99d477336f54b87b07b15f5b343a` tree from the timer baseline. Applying the lock and owner patches in either order gives the same combined tree.

| Owner decision | Parent or forward restore | Candidate | Candidate tree |
| --- | --- | --- | --- |
| Keep | `efc761a0d84e99d477336f54b87b07b15f5b343a` | `d7a702f49026e8f27663c2479b6ba06d50d2b9dc` | `f2285b52db18da6967043c59628b1086a9024078` |
| Park | `2d69c26c84e15742a718aff97b2e898918cfb39b` | `aaeef9ef24dc089255f7d41d0c7c4d32c2ba9179` | `4a94c0ca329df97af27cdd74131a722ff52d0a16` |

The park restore is a child of the owner commit with the exact timer `9f16d1a` tree `0ccd13d8cd502bc14d3b89c6431ff0ebe4745612`. Both candidate commits change only `rtl/arm9v2/arm925t_phone.v` and `tools/gen_arm9v2_phone.py` relative to their parent.

All six effective production preflights reproduced the 133 inputs at physical 104 MHz with DDR debug off on seeds 13, 43 and 31337. Against the timer controls 45824513460, 45824520116 and 45824525843, the compiled input delta is the generated CPU on both lineages and the MMC adapter on the keep lineage. The generated QSF hashes match by seed.

## Combined qualification

- The direct MMC HPS suite matched 48 cases. The three-slot test with actual `hps_io` and the native card matched 20 reads, four writes and 604,018 clocks. The owner miter exercised 448 event cases, including 49 owner wraps and 7,168 random edges across 379,781 comparisons.
- The three-FSM lock differential matched 1,281 cycles including two coincident return/install cases and an error at the cached critical beat. The four ARM9v2 board profiles matched the timer reference. The pinned generator check passed on both legs.
- The physical model executes the compact CPU, native card and candidate HPS backing with a simulated HPS peer. Both pin traces matched the owner baseline, with 171,496 events over 1,201,547 clocks and 171,497 events over 1,201,528 clocks in the timer/MMC/LCD overlap. The compiled HPS, timer and generated CPU fingerprints are pinned. The generated CPU is the sole input delta across 114 selected sources versus the qualified owner deck.
- The 105 fixed windows and four native frames matched exact owner-baseline results, including cycles, constrained guest outputs and architectural and valid-write digests. The frozen workload benches include the HPS source in Verilator's manifest and leave the adapter uninstantiated. The HPS and pin suites exercise the adapter.

[Combined qualification receipt](../../evidence/v5-104-dcache-compact-owner-combined.json)

## Reproduction

Restore the helpers from the [replay patch](patches/dcache-compact-owner-combined-replay.patch) at the repository root. The inputs are the archived owner and lock designs and receipts, the private owner dispatch object chain, the existing owner/timer mixed decks, the compact and owner fixture helpers, the established cross-toolchain and the cached Jotego image.

```sh
area=scratch/v5-fit-loop/dcache-compact-owner-combined
git apply docs/experiments/v5-performance/patches/dcache-compact-owner-combined-replay.patch
python3 -B "$area/prepare-fit.py"
sh "$area/stage.sh"
sh "$area/qualify.sh"
python3 -B "$area/record.py"
```

The preflight receipt records the private object directory and all required alternate directories. Use those with `GIT_OBJECT_DIRECTORY` and `GIT_ALTERNATE_OBJECT_DIRECTORIES` to inspect the candidate objects while leaving the working checkout and index intact.
