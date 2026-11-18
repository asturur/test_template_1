---
name: spmark-payload-bench
description: Run extracted original SPMark04 and GLES ARM kernels on the N-Gage CPU/cache RTL in offline Verilator, verify outputs, and compare fixed-work cycle baselines. Use for N-Gage CPU performance experiments; this does not run the full Symbian app or produce its official SPMark score.
---

# SPMark payload CPU benchmark

Use the maintained runner in Andrea's N-Gage repository, normally
`/Users/andreabogazzi/develop/NGage_MiSTer`. Read its `docs/status.md` checkpoint
and `tests/cpu/spmark_payload/README.md` before selecting inputs or interpreting
results. Run commands from that repository; use the currently authorized checkout.

## Run and compare

```sh
python3 tests/cpu/spmark_payload/run.py --name NEW_UNIQUE_NAME

# After an RTL change, compile and measure the candidate against a saved run:
python3 tests/cpu/spmark_payload/run.py --name NEW_CANDIDATE \
  --baseline build/sim/spmark-payload/BASELINE_NAME/result.json

# For another run with unchanged RTL, reuse only the verified compatible build:
python3 tests/cpu/spmark_payload/run.py --name NEW_REPLAY \
  --reuse-build build/sim/spmark-payload/BASELINE_NAME \
  --baseline build/sim/spmark-payload/BASELINE_NAME/result.json
```

Default is all six original-byte workloads, synthetic I:D waits0:0 and2:9,
two warm-ups/five checked samples per workload/profile, and two identical runs.
It also rejects deliberately wrong expected outputs. `--case ID` and
`--profile I:D` select a subset; compare only identically selected groups.
`--jobs` controls Verilator compilation parallelism (default4).

The input modules default to the local test fixtures under
`tests/cpu/spmark_payload/local/`. Override with
`--payload-dir DIRECTORY`. If missing, use `--mmc LOCAL_SPMARK04_MMC` to extract
the hash-qualified modules without modifying the card image. The decoded
original firmware defaults to `build/firmware/nem4-factory/core.bin`; override
with `--rom PATH`. The runner checks the original hashes, normal E32 import
linking and native EUSER export before executing. A different game/version/ROM
requires a separately validated workload, not bypassing the hash checks.

Requirements: installed Python Unicorn, ARM GNU assembler/linker/binutils,
Docker and the existing `jotego/simulator:arm64` image. Do not pull another image
or install Quartus. Docker runs with networking disabled. CPU/cache sources are
frozen from the actual working tree, including dirty RTL; other threads' build
outputs, running simulations and checkpoints are untouched. Build reuse checks
source, harness, image and executable hashes and refuses changed RTL.

## Read the outcome

Outputs live under `build/sim/spmark-payload/NAME/`: `result.json`, `report.md`,
`manifest.json`, `oracle.json`, exact guest inputs, frozen RTL and bounded logs.
Require `status=PASS`, every expected workload/profile, repeated-counter equality,
checked guest completion and passing wrong-output controls. A zero process exit
or a PASS substring alone is insufficient. Failures remain failed runs with
logs; use a new name after correcting the cause.

Report median cycles and cycles per matrix/triangle/pixel/byte. The equal-weight
geometric throughput index is100 for a new baseline; comparisons use baseline
cycles/candidate cycles. It is **not SPMark points, board FPS or a prediction of
whole-phone speed**. State the memory profile. The harness uses production
CPU/cache/MMU RTL and a synthetic scalar/16-bit-line responder; it does not
model physical SDRAM timing, LCD/MMC contention, HPS autosave or the OS.

Original matrix, transpose, triangle-edge and fill code runs on the RTL CPU.
Division in triangle setup runs original firmware ARM code too. Do not replace
timed math/memory/rendering work with host stubs or weaken output checks.
Simulation-only import linking and setup do not authorize firmware/SD changes.
The ZAP retirement marker hierarchy must be adapted and requalified before
using this runner with a replacement CPU pipeline. Raw Verilator checkpoints
are not portable restart states across RTL changes.

Use this baseline alongside the existing CPU donor import plan. FPGA area,
routed timing and occasional complete hardware SPMark runs remain separate
acceptance gates. Running this skill does not authorize commits, CI, deployment
or changes to the phone.
