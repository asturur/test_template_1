# Step5C — zero-addend product delivery

A single general state transition on the retained5B source reduces the original
matrix workload from **50,033 to47,887 cycles (−2,146,−4.2892%)**. Transpose
stays3,591, original Thumb JPEG84,353 and the drained64-store sequence71.
Both0:0/2:9 synthetic profiles, five scored samples, two repeats and original
output/negative controls pass. This is fixed-work RTL simulation, not a board score.

## Actual owner and changed edge

Original helper entry100011c4 contains SMULL at100011c8. All1,024 executions
have resolved zero addends: decode supplies zero operands for non-accumulating
MUL/UMULL/SMULL. The general zero-addend test also safely handles an accumulating
instruction whose actual addend is zero; it does not inspect guest PC or code.
Signed33-bit factors and registered66-bit DSP product remain byte-identical.
S1 still captures the low64-bit product into the existing x register. Only its
next state changes fromS2 toS3 when both addend halves are zero. Nonzero
accumulation keepsS2 and its64-bit sum. No state, result bypass or DSP arithmetic
is added; low/high ownership, flags and clear/hold priority remain unchanged.

The product atPOST_IDLE is still the preceding factors' product; the exact
current product first exists inS1. Keeping that stage is required. The removed
S2 adds zero to an already registered correct product. All1,024 independent
Python signed products, low/high emitted data, actual register writes and first
consumer inputs match between variants. All14,353 retirement PCs stay ordered.

First helper, relative to its actual low-owner start (control233955, candidate231081):

| Event | Control | Candidate |
| --- | ---: | ---: |
| S1 registered DSP product ready | 2 | 2 |
| Low result available | 4 | 3 |
| High result available | 7 | 6 |
| Actual low register write | 9 | 8 |
| Actual high register write | 12 | 11 |
| First consumer issue | 8 | 7 |
| First consumer receives low result | 9 | 8 |

Example operandsfffd412f×fffcf9dc produce000000084d4ebb64; both write
4d4ebb64/00000008 and forward the exact low word. Every local write/consumer
offset moves one clock earlier across all1,024 helpers, rather than summing
overlapping interval savings. [All paired schedules and source hashes](evidence/cpu-product-bypass-20261117.json).

## Measured accounting and qualification

| Disjoint matrix bucket | Control | Candidate | Delta |
| --- | ---: | ---: | ---: |
| read_stall | 5567 | 5551 | -16 |
| write_stall | 2550 | 2550 | +0 |
| load_lock | 114 | 114 | +0 |
| other_lock | 3088 | 3088 | +0 |
| empty | 15871 | 14765 | -1106 |
| other | 22843 | 21819 | -1024 |

The buckets sum exactly−2,146. Multiply busy6144→5120 accounts for−1024
within “other”; the rest is observed empty−1106/read-stall−16 as the earlier
result changes later fetch/operand schedules. Those empty clocks are not
additional deleted multiplier stages. The actual remaining busy count is5120,
including2048 clocks restarting the high-half owner. Shift-lock bucket3088
does not improve; helper heads at100011d4/100011d8/100011dc each show1024
held observations. These overlapping high-owner/consumer observations are not
additive recoverable-cycle promises.

Independent arithmetic checks cover2048 signed/unsigned vectors (1024 zero
addends and1024 random nonzero addends),4096 ordered results and paired zero
flags under random holds. Sixteen held WB cancellations and15 owned-stage
reset/WB/deferred-ALU-clear priority cases pass. A real IRQ asserted inS1
allows only the whole pre-instruction or post-instruction destination pair;
the returned program verifies signed/unsigned products, accumulating fallback,
predication and flags at both memory delays. Eight real-CPU ARM/Thumb/FCSE/
fetch-fault checks and the existing held/load/store/IRQ/abort/device/dirty-byte
oracles pass; wrong physical bytes are rejected. No game extraction or phone
commands occur. The candidate has no independent physical fit.

## Next broader action

1. General paired long-multiply result/operand delivery: preserve one owned
   64-bit result through both destinations and the first consumers. The current
   high-half restart contributes2048 busy clocks and the three dependent helper
   heads3072 hold observations; trace their shared critical interval before
   changing ownership. They must not be added as guaranteed savings.
2. General frontend target/fetch-to-operand replenishment remains the larger
   measured bucket (14765 empty clocks), with no claim all are avoidable.
   Prefer a traced handoff over another predictor or a wide queue at current area.

Replay: `bench.py --control` or default candidate with `--case matrix4 --case
transpose4`; `jpeg.py`, `run.py --safety`, `unit.py UNIQUE`, `irq.py UNIQUE --build
BUILD`, and `diagnostics.py UNIQUE --build BUILD` under
`tests/cpu/cpu_product_bypass/`. `analyze.py` audits the named final runs and
all1024 schedules; raw logs underbuild/sim are losslessly compressed with hashes.
5B is retained after matched physical improvement; the qualified one-file5C
payload is promoted on master with patch0076 and pristine upstream replay.
Accepted5A/5B sources and artifacts remain preserved. The collected5B bitstream
does not include5C; no second fit or deployment is performed.
