# Original SPMark04 payload on current CPU RTL

This runs original ARM instructions from the qualified SPMark04 card on the
production N-Gage CPU,16KiB I/D caches, MMU/TLB and line-refill RTL in Verilator.
It is a bounded kernel suite, not the full Symbian application or the official
SPMark score. No CPU/phone HDL, SD card or hardware state is changed.

| Case | Original entry (preferred VA) | Fixed measured work |
| --- | --- | --- |
| matrix4 |3DTEST.DLL1000216C |16 signed16.16 matrix4×4 products, including its original SMULL helper |
| transpose4 |3DTEST.DLL10002644 |32 in-place matrix4×4 transposes |
| triangle_edges |libGLES_CM.dll10002BE0 |16 triangle edge/scanline setups, including original firmware signed division |
| fill16_frame |libGLES_CM.dll10002AB4 |176×20816-bit framebuffer pixels |
| fill16_tail |libGLES_CM.dll10002AB4 |1023pixels with halfword alignment and odd-count tail |
| fill8_tail |libGLES_CM.dll100029F8 |2051bytes with unaligned start and tail |

## Execute

Run from the N-Gage repository with Python3/Unicorn, ARM GNU binutils and Docker.
Use the already installed jotego/simulator:arm64 image; no network/pull/Quartus.

```sh
python3 tests/cpu/spmark_payload/run.py --name baseline-UNIQUE
python3 tests/cpu/spmark_payload/run.py --name candidate-UNIQUE \
  --baseline build/sim/spmark-payload/baseline-UNIQUE/result.json
```

A unique name creates build/sim/spmark-payload/NAME and refuses overwrites.
The runner freezes the actual working-tree CPU sources, including dirty RTL,
into that directory and never uses shared unit-core or donor-import outputs.
Changed RTL is recompiled in Verilator; no RBF build is needed. For unchanged
RTL, --reuse-build RUN_DIRECTORY validates all source/harness/container/binary
hashes before reusing its executable. It refuses reuse after an RTL change.

Place the locally extracted `3DTEST.DLL`, `libGLES_CM.dll` and original
`TEST.JPG` in the Git-ignored `tests/cpu/spmark_payload/local/` directory.
The historical timeout test also reads `SPMark.app` here.
The JPEG fixture has SHA-256 `333e8e841fe8870a28959b4b0d80acf5e7500c9426bea8e31160a32c70bdfb47`. Use --payload-dir
for another local copy, or --mmc LOCAL_IMAGE to extract just the two qualified
modules into the new output directory. Original hashes are required. The ROM
is build/firmware/nem4-factory/core.bin, or --rom PATH. Binaries and extracted
firmware stay local; do not add them to Git or distribute them with the skill.

Defaults: all6 cases, synthetic I:D extra-wait profiles0:0 and2:9, two complete
identical runs, two warm-up windows and five scored windows. --case and
--profile may repeat to select a smaller suite. --jobs defaults4. The full-frame
case spends significant time on untimed guest setup/full-buffer checks; a quick
iteration suite can select matrix4, transpose4 and triangle_edges. Establish
its own matching baseline and retain the same selected members for comparisons.

## What is verified

Original E32 code is loaded at its preferred10000000 base. The single necessary
GLES IAT word is normally linked to original EUSER ordinal1514,503A2F6C; ordinal,
native export and complete original-image hashes are checked. No rendering,
division or memory operation is replaced with host code. Other unlinked OS
imports remain unused; reaching unexpected code/data fails the harness.

Before RTL execution, Unicorn runs each actual function and its real helpers.
Its output must match independent mathematical matrix/transpose, geometric
scanline or full-buffer byte models, including fill guards; callee-saved
registers and stack are checked. The RTL guest checks every output word after
every measured window. It does not merely run a failure-return wrapper. All
scored windows must execute original payload instructions; current runner also
matches payload/helper ordinary-retirement totals to the independent oracle.
The ordinary-retirement monitor is a ZAP-specific proxy, not a generic CPI.

A deliberately wrong expected output per case must fail at the guest result
mailbox. Default repeated runs must match every raw window and whole-run counter.
Parsing requires exactly seven paired start/end windows and checked completion;
missing, duplicate or unfinished windows fail. --skip-qualification is only a
local smoke option; use the default controls for a recorded acceptance baseline.

Setup and output checks are outside the retired-PC timing boundaries. Timed
work includes argument setup, original function calls, returns and loop control.
Both I and D caches/MMU are enabled. Warm-ups are retained but excluded from
reported medians. Report each raw scored window/range as well as the median if
it varies. Modeled line responses transfer sixteen16-bit beats; scalar/line
traffic share a backend. Scalar waits use exported code/data classification;
line waits classify wrapper/payload/firmware as code regions and RAM as data.
These are explicit synthetic profiles, not physical SDRAM timing measurements.
There is no Symbian scheduler, LCD/MMC DMA, IRQ traffic or autosave contention.

## Results and comparison

result.json includes source/tool/input hashes, all raw counters and oracle
output hashes; report.md contains median cycles and cycles per useful operation.
manifest.json pins executable, original image and linked payload identities.
oracle.json records original-code execution and checked buffer hashes. Logs
are bounded by max_cycles; failures record FAIL (or INCOMPLETE if interrupted)
and are not baselines.

A new suite baseline has index100 per memory profile. Comparison index is
100×the equal-weight geometric mean of baseline_cycles/candidate_cycles across
exactly the same case group. Program, payload, harness, ROM, simulator image
and group membership must match. Different subsets are different indices;
this is never the phone's84-point SPMark result, FPS or an inferred full-game
speedup. Physical controller changes cannot be assessed with this responder.

The marker observer uses current ZAP internals. Requalify it before testing a
replacement integer pipeline. Raw --savable checkpoints are not portable across
CPU changes. Preserve the separate FPGA fit/timing and real-phone acceptance
steps in docs/cpu-donor-import-plan.md.

## Profile cycle pressure before choosing an optimization

```sh
python3 tests/cpu/spmark_payload/profile.py \
  --base build/sim/spmark-payload/ACCEPTED_RUN --name UNIQUE
```

This separate runner instruments a copy of an accepted run's frozen harness/RTL.
The ordinary benchmark and its baseline hashes stay unchanged. It records data
completion/cache-state waits, load/shift dependencies, multiply busy, redirect
edges, decode sequencing and empty-queue/advance clocks, plus held-owner PCs.
Default: all six cases,0:0 waits, two exact repeats. Every original raw counter
must remain identical. Bucket sums and owner histograms must reconcile; an
instrumentation change cannot silently become a faster/slower benchmark.

Outputs are under `build/sim/spmark-profile/NAME/`. The priority buckets describe
blocking signals, not additive recoverable loss, and raw bus/fetch counters can
overlap. Cache-state labels and ZAP hierarchy are checked/adapted rather than
assumed portable. This currently profiles the qualified ARM kernels.
[First measured bottlenecks and optimization priority](../../../docs/spmark-payload-profile.md).

## Accepted 5F integrated scorecard

`python3 tests/cpu/spmark_payload/scorecard_5f.py` audits saved qualified5F,
review and stock-ngage2 results, the newly measured triangle and separateJPEG.
Use `--triangle RUN_DIRECTORY` to select a fresh qualified triangle replay.
It checks all60 compiled RTL hashes against acceptedfae4016, original inputs,
outputs, counts, repeats and negative receipts, then writes the durable
[machine scorecard](../../../docs/evidence/cpu-integrated-5f-20261117.json).
[Assessment and limits](../../../docs/cpu-integrated-5f.md).
