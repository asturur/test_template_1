# JPEG input preparation: measured performance profile

## Findings

The blocking request is successful input loading/decode after its10-second
deadline; compression has not started. [Native ordering](spmark-jpeg-hang.md).
The complete request's48periodic last-PC samples break down as follows:

| Original code | Samples | Share |
| --- | ---: | ---: |
| MediaServerVideo: bitmap conversion/error-diffusion helpers |30 |62.5% |
| MediaServerJpeg: JPEG codec |14 |29.2% |
| EUser, Gdi and kernel/other |4 |8.3% |

These are coarse samples, not exact service durations or a proof that MMC costs
zero. They point to output conversion as the first target rather than assuming
Huffman/IDCT, multiplication or disk throughput dominates.

The hot original Thumb block routine505A9E0D belongs to CMdaErrorDiffuser. It
calls many small three-component error add/subtract/shift helpers. The8×8 JPEG
pixel case executes22,500original instructions, including905BL calls. A useful
benchmark must cover this Thumb/stack/load-use behavior; the older six original
SPMark/GLES kernels do not cover JPEG or this conversion path.

## Isolated original-code RTL measurement

Original ROM code runs at native505xxxxx addresses, with native Gdi helpers and
unmodified virtual-method tables. Only untimed object/buffer setup is supplied;
there are no timed host conversion/math, allocation or OS service replacements.
The native constructor identifies mode10 as12-bit RGB index conversion and
mode8 as a24-bit control. No modern enum-name assumption is needed.

An independent mathematical error-diffusion/quantization model checks every
output pixel, row/column error buffer and object state, plus input and guards.
Four cases cover actual TEST.JPG-derived8×8/16×8 crops and fixed random pixels
with12-bit and24-bit conversion. Pillow only supplies representative decoded
input colours; it is not an oracle for the complete native JPEG decoder.
All four original-code Unicorn cases pass with stack/callee-saved preservation.

Current CPU/cache snapshotf1791df (CPU code1abf0db) takes **118,705clocks per8×8
JPEG-derived block**, or1854.77clocks/pixel. Both0:0/2:9 profiles have identical
warm medians, with no external read/write/line request during measured windows.
The old pre-store reference takes122,793clocks: current is **3.444%faster** on
this case. The only compiled RTL source differing in that reference is
cache_access.sv. This is a CPU-source comparison, not artifact identification
or a measured speedup of the already-running RBF.
[Dedicated baseline table](spmark-jpeg-results.md).

## Current-cycle occupancy

| Priority category | Share |
| --- | ---: |
| Data completion wait |35.27% |
| Operand queue empty |19.79% |
| Load dependency |14.19% |
| Decode sequencing |6.96% |
| Shift dependency |2.03% |
| Redirect event |1.52% |
| Other advancing cycles |20.25% |

Multiply busy is zero in this bitmap workload. Raw fetch-wait overlaps16.54%
of clocks; external wait is zero. Data wait splits into21,191read clocks and
20,677write clocks per measured block. Relevant cache states as a share of all
clocks: IDLE12.83%, LOOKUP_CAPTURE6.53%, STORE_HIT3.67%, STORE_COMMIT3.67%,
LOOKUP_WAIT2.86%, LOOKUP2.86%, READ_LINE2.85%. Translation wait overlaps3.08%.

Categories measure blocked-signal occupancy, not independently recoverable
cycles. The held-PC histogram frequently lands around stack POP/BX return
sequences and vector loads/stores. It groups adjacent Thumb halfwords into
four-byte words and observes a held pipeline stage, which may be younger than
the memory producer; do not assign those cycles to the displayed BX alone.

## Recommended next experiment

Keep the earlier cache/CPU plan. **F2 owned request/completion overlap is now
supported by a second workload**, with particular attention to Thumb PUSH/POP,
LDM/STM and immediate load consumers. Measure completion latency separately
from independent-request throughput. Preserve oldest-fault ordering, captured
owners, RAW/WAW, MMIO, SWP, CP15, interrupts and reset; track ALM/timing cost.
No queue/global-hold redesign is implemented by this profiling task.

After that, investigate frontend starvation and Thumb call/return prediction;
IDCT/Huffman arithmetic is a later separately measured target. Do not bypass
error diffusion with a firmware patch, stretch native timers or infer a required
DDR bandwidth upgrade from this warm workload. The already-qualified store
change's3.4%hotspot gain alone cannot guarantee closing the whole request's
~20%throughput gap. Full native JPEG/System Tests remain the final deadline gate.
Keep78MHz PLL;104MHz remains the implementation timing goal.

## Qualification and reproduction

Eight current case/profile groups pass two exact repeats and seven windows.
Every window's original-code retirement equals the independent oracle (plus
eight ARM wrapper instructions). Eight unprofiled runs match every raw profiled
counter; sixteen repeated pre-store comparisons pass. Four corrupt-object and
four corrupt-output-pixel controls fail at the checked guest result. No other
thread's simulation or checkpoint was changed. No production RTL/PLL, MiSTer,
SD-card, new RBF or CI action was changed/run for this profile.

Reproduce from the active integration checkout with the existing offline Docker
image and native Unicorn/binutils. Use a fresh unique output name:

```sh
python3 scratch/spmark-jpeg-profile-20261115/run.py --name jpeg-NEW
python3 scratch/spmark-jpeg-profile-20261115/qualify.py --base build/sim/jpeg-payload/jpeg-NEW
python3 scratch/spmark-jpeg-profile-20261115/pixel-controls.py --base build/sim/jpeg-payload/jpeg-NEW
```

Unicorn native JIT and the Docker socket need the previously documented sandbox
escalation when invoked by the agent. Do not overwrite the accepted baseline.
Original ROM/game assets remain local. [Evidence](evidence/spmark-jpeg-profile-20261115.json)
pins source, input and raw-result hashes. Full generated files remain under
build/sim/jpeg-payload/error-diffusion-20261115-v2.

Fixture corrections retained in scratch: native factory mode9 correctly returns
null; use tested modes8/10. The independent model initially needed the native
first-column and cross-row error-carry rules. The first RTL observer rejected
505xxxxx PCs because its old payload map only covered100xxxxx; v2 fixes only
the copied simulation address map. None of those failures establishes an RTL
or phone defect. Final compiled/source/harness identities are recorded in the
accepted manifest.
