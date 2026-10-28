# BTB tag collision and cached return

Checkpoint: [status.md](status.md). Reproduced and fixed 2026-10-27.

## Failure and isolation

After the explicit ADC sample, the original NEM-4 code sets up a timer and
unmasks IRQ. The old FPGA then requests physical `0x0c120100`, while the native
MMU-aware software CPU returns normally and continues the ROM integrity check.
IRQ/FIQ inputs are held low in the HDL harness. This was not evidence for an
unmodeled timer interrupt or a reason to invent another register response.

The bounded branch trace showed virtual `0x5000324c` (`MOV PC,LR`) with actual
target `0x500035bc`, prediction `0x500035bc`, state 3 (strongly taken), and
redirect 0. Fetches nevertheless continued at `0x50003274`. The following literal
pool began to execute, including an LDM from the interrupt-controller area.
The before-fix immediate run stopped at cycle 115,513,898, delayed at 160,264,449.

Cold cached-return tests and an initially untrained copy of the timer routine
both passed. The decisive reproducer is `sim/programs/btb_return.S`: it trains
a conditional branch at physical `0x2a4c`, whose BTB index collides with return
`0x5000324c` but whose tag differs. It then makes a conditional call to the
self-contained timer/return sequence. The old CPU incorrectly stops at
`0x0c120100` with both memory timings. This reproducer includes no Nokia payload.
The earlier cold controls are retained in `scratch/adc-bringup/`.

## Root cause and patch

Upstream `zap_btb.sv` qualified its redirect with tag match and valid state, but
always emitted the raw RAM prediction state, including on a tag miss. A taken
state from an unrelated entry could therefore travel with stale predicted-PC
metadata. A later PC-writing instruction could conclude that the required jump
had already happened and omit its redirect.

Patch 0006 emits `SNT` on a tag miss or invalid entry, while retaining the learned
state on a valid match. The predicted-PC comparison can no longer trust an
unrelated entry's taken state. Valid predictions and their targets are unchanged.
The pinned vendor remains untouched; the patch applies only to the build copy.

`make sim-compat` now requires both collision cases to reach the intended terminal
write at `0x0bad0000`. Before the patch they stopped at `0x0c120100` after
78,391 / 119,593 cycles; after the patch they reach the intended stop after
86,618 / 119,660 cycles. The full acceptance suite, original ARM32/Thumb seed-1
regressions, and synthesis-path lint pass with all six patches.

The diagnostic files are `build/sim/timer-return-trained-before-fix.json`, its
matching run folders, and current `btb_return-latency{0,3}` runs. Full firmware
runs retain the last 128 branch decisions in `branch-tail.tsv`, alongside the
existing memory/retirement tails. These are simulation-only observations.

## Remaining limits

The BTB fix changes cycle counts. Historical five-patch measurements are not
current CPU timing and never represented ARM920T/Nokia timing.

A separate source observation is that the predecoder's commented MOV-PC-LR RAS
pattern names register 15 in its last field, rather than LR/14. That optimization
has not been changed: the demonstrated functional failure is isolated to invalid
BTB state. Any later RAS optimization needs its own tests rather than being mixed
into this correctness patch. No complete ARM920T or 104 MHz claim follows.
