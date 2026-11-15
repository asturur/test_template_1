# SPMark payload simulation baseline — 2026-11-14

The ongoing comparison table is [spmark-payload-results.md](spmark-payload-results.md).

Six original SPMark/GLES kernels now execute successfully on the current
production CPU/cache/MMU RTL in the existing offline Jotego Verilator image.
This is a fixed-work payload benchmark, not full Symbian/SPMark execution,
texture/shaded scene rendering, or the phone's official84-point result.

Source HEAD555a510, actual frozen compiled closure
65e7989c5562b361870723b7f2c8981fbc1ca057350b1e7d3d3dbfe991f94463.
No production HDL change, hardware access, FPGA build or other-thread simulation
change. Original module/ROM hashes and normal E32 import resolution are pinned
in the evidence. The GLES signed divide executes original firmware ARM code;
no host math, rendering or memory implementation replaces timed work.

## Measured baseline

Fixed original-payload CPU/cache index; not official SPMark score or board FPS

| Workload | I:D waits | Operations | Median cycles | Scored range | Cycles/operation |
| --- | --- | ---: | ---: | --- | ---: |
| matrix4 | 0:0 | 16 | 78336 | 78336–78336 | 4896.000 |
| matrix4 | 2:9 | 16 | 78336 | 78336–78336 | 4896.000 |
| transpose4 | 0:0 | 32 | 12589 | 12589–12589 | 393.406 |
| transpose4 | 2:9 | 32 | 12589 | 12589–12589 | 393.406 |
| triangle_edges | 0:0 | 16 | 46592 | 46592–46592 | 2912.000 |
| triangle_edges | 2:9 | 16 | 46592 | 46592–46592 | 2912.000 |
| fill16_frame | 0:0 | 36608 | 238234 | 238234–238234 | 6.508 |
| fill16_frame | 2:9 | 36608 | 238234 | 238234–238234 | 6.508 |
| fill16_tail | 0:0 | 1023 | 6774 | 6774–6796 | 6.622 |
| fill16_tail | 2:9 | 1023 | 6774 | 6774–6798 | 6.622 |
| fill8_tail | 0:0 | 2051 | 7507 | 7507–7507 | 3.660 |
| fill8_tail | 2:9 | 2051 | 7507 | 7507–7507 | 3.660 |

Index: {"0:0": 100.0, "2:9": 100.0}

Two warm-ups, five checked samples; synthetic scalar/line memory, no physical SDRAM/LCD/OS.

Measured wall time including setup, checks and build: {result["elapsed_seconds"]:.3f}s.

## Qualification and practical use

All12 case/profile rows pass, with7checked windows each and two complete runs
matching every raw window/whole-run counter. Independent Unicorn execution
matches mathematical matrix/transpose, geometric scanline and full-buffer fill
models, including guard bytes and ABI preservation. All84 payload/helper RTL
ordinary-retirement totals match that original-code execution. Six deliberately
wrong output models fail at the checked guest mailbox. The short odd16-bit fill
has a first scored window6796cycles then6774 at0:0; the median is6774 and raw
windows are retained. This does not invalidate deterministic repeat equality.

The full baseline takes526.698s including build/setup/whole-buffer checks; its
large framebuffer case dominates. The validated three-case quick replay
(matrix/transpose/triangle,0:0) takes30.551s with an unchanged verified build
and reports exactly100.0 against its own matching quick baseline. Reuse with
stale RTL metadata is rejected before simulation. The quick subset and full
six-case suite are different indices and must not be mixed.

Use [the runner](../tests/cpu/spmark_payload/README.md) and the installed
`$spmark-payload-bench` skill, maintained under
[skills/spmark-payload-bench](../skills/spmark-payload-bench/SKILL.md).
A changed RTL snapshot requires only a Verilator compile, not Quartus/RBF.
The compile in the initial smoke took13.536s on this machine; runtimes vary.

Outputs and bytecode stay local under build/sim/spmark-payload; an optional
--mmc path extracts the hash-qualified modules programmatically. That path was
exercised by the quick baseline. Generated copyrighted DLL/ROM bytes are not
tracked. Source freezing and results use fresh unique directories, leaving
other simulations and all long checkpoints untouched. No commit, push or CI
was launched by the benchmark workflow.

This uses the current16KiB I/D cache/MMU and modeled scalar/16-bit-line memory.
There is no physical SDRAM timing, OS, LCD/MMC/IRQ traffic or autosave. All warm
medians happen to match at0:0 and2:9 waits; this establishes only the measured
behavior of these kernels/profiles, not absence of memory bottlenecks elsewhere.
Index100 is the reference; candidate index is100×equal-weight geometric mean
of baseline/candidate cycles within the exact same case/profile set. Board FPS,
area and104MHz timing remain separate qualification gates. No hardware speedup
or complete SPMark simulation is claimed.

[Full raw baseline](evidence/spmark-payload-baseline-20261114.json),
[qualification and replay](evidence/spmark-payload-qualification-20261114.json).
