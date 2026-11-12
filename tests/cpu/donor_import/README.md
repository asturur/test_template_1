# CPU import benchmarks — first test batch

The source order is pinned by the user:

1. **H0:** `ce8d2c902724a59e7537b845bc841dbd82d5bbf7`.
2. **H1:** `3f5e8aeae3260562a814eacdd8d8aa505c044af8`, H0's direct child.
3. **Working:** a frozen current source snapshot, including pending controller work.
4. **Working previous SDRAM:** the identical working snapshot with only the six
   saved pre-native-controller files restored **inside the isolated snapshot**.

The runner uses Git object reads, not checkouts, branches, worktrees, stashes or
patching the user's working tree. The historical CPU/cache sources are complete
per-revision snapshots. New test binaries are assembled once and reused across
all versions. Every source/program/harness has a recorded SHA256; run refuses
mutated frozen sources. Current private configurations/media are excluded.

## Scope

Fifteen ARM kernels currently cover dependent ADD, independent arithmetic,
carry/flags, dependent shifts, multiply/accumulate, signed long multiply, dependent
and independent loads, signed/byte/halfword formats, store/reload, block copy,
direct branches, calls/returns, CP15 reads and cold cache-line-stride reads.
Each kernel has guest result assertions, two warm-ups and three measured windows.
Block copy also checks the copied memory. Section tables are set up by the guest.

This is the **first batch**, not completion of the full import plan. Thumb/BL
interrupt fixtures, the full ISA/fault matrix, compiled C, realistic LCD/MMC
contention, physical SDRAM comparisons and gameplay remain to be added. No CPU
RTL import has been made. No performance or architectural-correctness result
exists until real HDL execution passes.

`tb.sv` uses synthetic scalar/line backing responses. In `scalar` mode all
versions use the existing scalar CPU port. In `line` mode H1/current enable
their line ports while H0 retains its original scalar path. The responder is
shared and has independent I/D-class waits plus reproducible address/seed
jitter; page-table traffic follows its exported scalar code/data classification.
Line-port waits use the physical address class (ROM versus RAM). This is an
explicit model convention, not proof of phone memory timing. Lines share the
modeled backing resource with scalar requests and return sixteen halfwords.

**These tests do not instantiate the physical SDRAM controller.** They can
measure CPU/cache/refill-interface effects, but cannot measure SDRAM command
timing, the new native write schedule or a board frequency. Working versus
working-previous-SDRAM is a negative control here: CPU results must be identical.
Use/add the physical-controller benchmark separately before attributing speed
to the uncommitted SDRAM work. H0→H1 and H1→working are distinct comparisons;
the latter contains intervening work and is not controller-only.

## Measurement convention

`body_begin` and `body_end` are distinct NOP instructions resolved from ELF
symbols. A window is the difference between their ordinary ZAP retirement-edge
cycle counters: it excludes the opening edge and includes the closing edge.
Warm-up windows remain in raw logs but are excluded from the median score.
Cycle samples do not include initial section-table setup or result checks.
Cache-line-stride invalidates/cleans D-cache before every sample, outside its
measured window; other kernels have warmed-data/code interpretation.

`retire_proxy` uses the existing ZAP ordinary-uop-last predicate, which excludes
CP15/exception events. **It is not an architectural instruction count or CPI.**
The first batch scores cycles per explicitly defined useful operation instead.
The optional software oracle counts kernel ISA instructions; it does not count
speculative/microarchitectural events. Future whole-CPU imports must adapt and
requalify the observer when internal hierarchy/retirement contracts change.

Counter validation rejects missing/duplicate windows, missing completion,
negative/zero cycle windows and inconsistent whole-run totals. A zero process
exit code or a PASS substring is insufficient. Comparisons require matching
binary, harness, memory model, simulator image, waits, seed, sample count and
operation count. Cycle savings and throughput gain are reported separately.

## Commands

Run from the repository root. Preparation uses installed ARM binutils/GCC only:

```sh
python3 -m unittest discover -s tests/cpu/donor_import -p 'test_*.py' -v
python3 tests/cpu/donor_import/run.py prepare my-cpu-baseline
python3 tests/cpu/donor_import/check_programs.py my-cpu-baseline
```

Choose a new experiment name every time preparation/harness/programs change.
The prepared `cpu-donor-baselines-20261112-a` had a testbench syntax issue and
is superseded by `cpu-donor-baselines-20261112-b`; no HDL result came from either.
Do not edit a frozen snapshot to repair its provenance.

The optional `check_programs.py` uses already-installed Unicorn to execute only
the kernels with explicit register/memory/CP15 preconditions, then executes their
guest checks. It also corrupts a result and requires the guest to fail. It does
not qualify startup, MMU, cache, ZAP, HDL or timing. A native-library initialization
failure is recorded as BLOCKED rather than mistaken for a guest failure.

Start HDL execution with a small historical-pair smoke run:

```sh
python3 tests/cpu/donor_import/run.py run my-cpu-baseline \
  --variant h0 --variant h1 --case add_dependent --mode scalar --profile 0:0
```

Then run all prepared variants/cases, both transport modes and the three default
I:D profiles (0:0,0:3,2:9), or select a focused matrix:

```sh
python3 tests/cpu/donor_import/run.py run my-cpu-baseline
python3 tests/cpu/donor_import/run.py run my-cpu-baseline \
  --variant h0 --variant h1 --profile 0:7 --profile 0:15 --profile 0:31 \
  --seed 1 --seed 17 --seed 29 --jitter 7
python3 tests/cpu/donor_import/run.py compare my-cpu-baseline 0001
```

Each run creates a new numbered attempt, never overwrites an earlier result.
Compiles/runs use only `jotego/simulator:arm64` with `--pull=never` and no network.
No Docker access produces a BLOCKED report before any compilation. Existing
long simulations, media, production source and checkpoints are not modified.

Snapshots: `scratch/cpu-donor-import/<name>/`.
Binaries/manifests/results: `build/sim/cpu-donor-import/<name>/`.
The full 15-case/four-variant/two-mode matrix takes multiple CPU builds; begin
with the smoke test, and keep failures/diagnostics intact before broadening it.

## HDL qualification and result tables

After an attempt finishes, replay its binaries and exercise deliberately broken
guest comparisons and marker settings without changing frozen inputs:

```sh
python3 tests/cpu/donor_import/qualify.py my-cpu-baseline 0002
python3 tests/cpu/donor_import/report.py my-cpu-baseline 0002
```

`qualify.py` creates append-only `qualification-NNNN/` directories. Each contains
separate mutated program copies, exact commands, executable/build-log hashes and
raw logs. The first checked guest comparison is changed to a deliberately wrong
expectation (255), preserving its conditional branch to the failure mailbox.
The original CPU must reject it. ADD replays must match the original counters,
retire 128 ADDs plus the closing NOP, and report 129 warmed body clocks. Missing
begin/end and equal markers must fail. These checks qualify the observer and
assertion path, **not** a complete ISA oracle or uninstrumented-equivalence test.
All completed windows are also checked against ordinary-retirement counts derived
from each explicit instruction stream (including loop/call paths and the closing
NOP). For example, block copy produces33 ordinary last-uop events, the branch
loop194, and CP15 reads only1: its64 MRCs are excluded by the observer contract.
Cold-stride measured windows must reconcile65 refills:520 scalar32-bit reads,
or65 line requests/1,040 halfwords, with zero writes.
`--variant` and `--case` can narrow the runtime checks; available cases must have
a successful `0:0` observation in the selected attempt.
`--completed-only` captures the observations already finished while a longer
matrix continues; its report explicitly lists this captured subset.

For deterministic repeats, run two seeds with jitter disabled, for example
`--seed 1 --seed 17`. The seed has no effect at jitter zero. Qualification compares
every raw window and whole-run counter, including warm-ups, rather than merely
comparing reported medians. Working versus working-previous-SDRAM must likewise
match every raw counter: this is the synthetic model's controller negative control.

`report.py` writes `report.json`, `report.csv`, and `report.md` beside the attempt.
It requires every prepared kernel and all four variants at the selected traffic
settings. Failed/missing observations and unequal repeats remain FAIL/BLOCKED.
It lists each seed separately, and exports cycle savings separately from throughput
gain. It deliberately supplies no overall score for this incomplete benchmark
suite; full group weights still need to be frozen before CPU imports.
