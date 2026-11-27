# Simulation fixture recipes

The replay base is `739d3bd`. The committed source has both caches at
16 KiB. The checked 104 MHz decks use pin SDRAM, the production streaming
controller, 32 KiB flash cache, MMC divide-by-three and 64 Hz guest ticks.
Use the installed `jotego/simulator:arm64` image. The original firmware,
workload images, snapshots, trained RAM state, generated pin model and
executable outputs are local prerequisites. See the
[fixed-work fixtures](../../arm9v2-donor-frame-gap.md) and the native
preparation commands below.

When using the observer drivers in a disposable experiment tree, preserve
the source paths set by the patches and run the Python commands from the
experiment repository root. The existing prepared-baseline decks have
these names:

- `build/sim/payload-clocks/v5-104-all-four-ram-candidate`
- `build/sim/polycount/v5-104-all-four-ram-candidate`
- `build/sim/polycount-v5/native-qualified`, when preparing the native deck
- `build/sim/unit-hardware-boot-real-sdram/mt48lc16m16a2-verilator.v`

The baseline decks supply the reference guest files, Verilator invocation,
testbench and expected results for the passive and four-way replay drivers.
The [checked workload harness patch](patches/checked-workload-harness.patch)
preserves the 104 MHz driver and the public native and fixed-work source
fixtures that were local to the experiment. The usual fixed-work guest
inputs still come from checked local previews under `build/sim/`.
Use fresh output names or a freshly prepared tree for another measurement.

## Preparing the all-four replay decks

Apply the shared harness and [baseline runner fixture](patches/all-four-benchmark-fixture.patch)
on the exact base. Prepare the checked fixed-work guest decks described
above. The native capture uses original v1.10 modules and the checked
factory ROM. The harness source contains the authored capture and replay
programs. Set `SPMARK_ORIGINAL` to the local directory of original modules.

```sh
area=scratch/v5-performance-baseline
git show 739d3bd:rtl/arm9v2/arm925t_phone.v > "$area/candidate.v"
python3 tests/cpu/polycount_v5/capture.py --payload-dir "$SPMARK_ORIGINAL" \
  --output build/sim/polycount-v5/native-qualified
python3 "$area/profile.py" candidate payloads
python3 "$area/profile.py" candidate native
```

Use the four-frame capture directory above when it is already prepared.
The two baseline output directories reuse the exact names expected by the
observer recipes. Their original inputs and outputs remain local.

## Store-list pairs

Apply the shared harness and the [store-pair census fixture](patches/store-pair-census-fixture.patch).
The census derives eligibility from the original ARM/Thumb store sequence,
physical line membership, writable resident state, and the adjacent
queue-owned request. The archived driver uses a separately extracted
exact CPU netlist and wrapper.

```sh
area=scratch/v5-ipc-overlap
git show 739d3bd:rtl/arm9v2/arm925t_phone.v > "$area/base.v"
git show 739d3bd:rtl/ngage_cpu.sv > "$area/ngage_cpu.sv"
python3 "$area/profile.py" candidate payloads
python3 "$area/profile.py" candidate native
```

## Refill pairs and staged D admission

Apply the [refill-pair and admission fixture](patches/refill-pair-and-admission-fixture.patch).
The bench names and observed signals are the same as the measured study.
Preparing a private simulation copy saves the D-side request address behind
the `+delay_d_refill` switch. The [wrapper-only patch](../../evidence/v5-104-d-refill-admission-sim.patch)
can be used independently by callers already preparing the instrumented
bench. `prepare.py` derives the same wrapper directly from the pinned commit.

```sh
area=scratch/refill-issue-739d3bd
mkdir -p "$area/leg"
git archive 739d3bd rtl tests/phone/sdram tests/phone/hardware_boot/d2_measure.vh |
  tar -x -C "$area/leg"
python3 "$area/prepare.py"
python3 "$area/run.py" payload
python3 "$area/run.py" native
python3 "$area/summarize.py"
docker run --rm --pull=never --network none --platform linux/arm64 \
  -v "$PWD/$area:/work" -w /work --entrypoint /bin/sh jotego/simulator:arm64 -ec '
    iverilog -g2012 -s stage_tb -o leg/stage leg/rtl/ngage_cpu.sv stage_tb.sv
    vvp leg/stage
    vvp leg/stage +delay_d_refill
  '
```

## Sequential I-line opportunity

Apply the [next-line observer and timing model](patches/sequential-i-line-census-fixture.patch).
The normal run keeps line admission untouched. The split runner models
preparation at the existing checked miss and rejects same-context hints
that cross a 1 KiB permission boundary.

```sh
area=scratch/icache-lookahead-739d3bd
mkdir -p "$area/leg"
git archive 739d3bd rtl tests/phone/sdram tests/phone/hardware_boot/d2_measure.vh |
  tar -x -C "$area/leg"
python3 "$area/run.py"
python3 "$area/run_payload.py"
python3 "$area/timing_split.py"
```

## Redirect opportunities

Apply the shared harness and the [redirect census fixture](patches/frontend-redirect-census-fixture.patch).
The observer checks the acknowledged Thumb word, the latched hit-way
I-cache line and existing ready packets. It associates the actual
registered repair edge with the surviving retired successor. Use
[the archived census](redirect-census.json) for the exact per-window and
per-frame counts.

```sh
area=scratch/v5-frontend-redirect-census
git show 739d3bd:rtl/arm9v2/arm925t_phone.v > "$area/base.v"
git show 739d3bd:rtl/ngage_cpu.sv > "$area/ngage_cpu.sv"
python3 "$area/run_profile.py" fixed
python3 "$area/run_profile.py" native
python3 "$area/score.py"
```

## Thumb and D admission together

After making the stage-only reference with the refill fixture, apply
the [four-way replay fixture](patches/thumb-and-d-admission-replay-fixture.patch).
The private variant source must contain the
[original Thumb recovery delta](../../evidence/v5-104-thumb-fallthrough.patch).
The D stage and Thumb recovery switches are independent simulation
controls. The reconstructed harness verifies actual compile paths and
tracks ordered retirements, register/CPSR updates, data completions and
MMIO alongside guest result checks.

```sh
area=scratch/v5-frontend-redirect-census
mkdir -p "$area/variant" "$area/replay"
git archive 739d3bd rtl/arm9v2/arm925t_phone.v tools/gen_arm9v2_phone.py |
  tar -x -C "$area/variant"
git apply --directory="$area/variant" docs/evidence/v5-104-thumb-fallthrough.patch
cp scratch/refill-issue-739d3bd/leg/rtl/ngage_cpu.sv "$area/replay/ngage_cpu.sv"
python3 "$area/replay.py" fixed --workers 3
python3 "$area/replay.py" native --workers 2
python3 "$area/results_table.py"
```

The archived experiment used the short helper `verify_completed_native.py`
to validate the complete native records where two log files had a trailing
fragment from a superseded invocation. New runs use the regular driver
and compare all four frames and the final native bytes.

## Registered D-return directed test

Apply either wrapper patch and the shared [test patch](../../evidence/v5-104-d-return-tests.patch).
Use its test mode to match the expected first-word edge:

```sh
sh tests/cpu/arm9v2_board/run-d-line-return.sh d-return-buffered buffered
sh tests/cpu/arm9v2_board/run-d-line-return.sh d-return-capture capture
```

These two commands correspond to separate source trees and run names.

## Thumb recovery with the ordinary redirect

Apply the [ordinary-redirect replay fixture](patches/thumb-ordinary-redirect-fixture.patch).
It uses the prepared all-four decks, the frozen board sources from the refill
fixture and the prior four-way replay's retirement and data records.
The newest benchmark compiles the exact original wrapper with the new
Thumb CPU. It compares program-visible events and allows the redundant
instruction lookup to change speculative traffic.

```sh
area=scratch/v5-fit-loop/thumb-redirect-independent
mkdir -p "$area/source" "$area/replay"
git archive 27bd8bf rtl/arm9v2/arm925t_phone.v tools/gen_arm9v2_phone.py \
  tests/cpu/arm9v2_board/thumb_recovery_tb.sv | tar -x -C "$area/source"
git apply --directory="$area/source" docs/experiments/v5-performance/patches/thumb-ordinary-redirect.patch
git show 739d3bd:rtl/ngage_cpu.sv > "$area/ngage_cpu.sv"
python3 "$area/replay.py" fixed
python3 "$area/replay.py" native
```

The [qualified comparison receipt](thumb-ordinary-redirect-replay.json)
covers the directed test, fixed/native replay, ordered board contract
and the mixed PCM/LCD/MMC test.
