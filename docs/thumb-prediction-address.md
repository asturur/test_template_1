# Thumb call/return prediction addresses — 2026-11-16

Patch0069 removes false redirects caused by comparing Thumb's state bit as an
instruction-address bit. It changes only ALU branch-address capture/comparison;
no new state, RAM, stage, predictor capacity, cache protocol or clock setting.
Actual PLL remains78MHz;104MHz is the timing objective.

## Observed failure

In an unchanged original JPEG bitmap block, the RAS predicts505A9E46 while
`BX LR` reads505A9E47. Both refer to the same Thumb instruction. Writeback
already clears PC[0] before fetching, but ALU compares all32bits and incorrectly
reports a different target. Its raw odd target also trains the BTB, so later
predecode comparisons against even RAS addresses can redirect unnecessarily.

A first-scored-window observer on the accepted P0-trim CPU counts257such actual
ALU redirects. After the fix the same257raw bit0 differences occur, with
**zero false redirects**. The2327branches/1099exchange instructions and22508
retirement markers are unchanged. Decode clears fall1084→1028. Both observation
runs match every corresponding accepted guest counter, not just the final output.
The initial observer used the wrong MOV opcode filter; corrected opcode13 and
an explicit actual-redirect counter are the accepted evidence.

## Address and mode contract

- Capture the branch fetch target with bit0zero, matching existing writeback.
- Compare ADD/MOV prediction addresses at bits31:1. Bit1 remains significant.
- Preserve the raw ALU result and raw BX bit0. The existing state-change test
  runs first and forces a real ARM/Thumb transition to redirect and update T.
- Preserve condition-failed fallthrough, exception-return SPSR restoration,
  faults, cancellation, holds and BTB feedback ownership.

The masked bit is a constant/address convention, not a new ready/advance path.
No extra target copy or formatter is added. Actual area/timing benefits are
unmeasured. Full RAS rollback, Thumb BL-half semantics and general fetch/decode
separation remain separate work.

## Measurements

All results are offline fixed-work cycles, not official SPMark or board speed.
Both synthetic0:0/2:9 profiles repeat exactly.

| Work | Before | After | Throughput gain |
| --- | ---: | ---: | ---: |
| Original JPEG8×8mode10 |113957|111449|2.2504%|
| Original JPEG8×8random mode10 |113973|111465|2.2500%|
| Original JPEG8×8random mode8 |112956|110320|2.3894%|
| Original JPEG16×8mode10 |224845|219849|2.2725%|
|32Thumb calls, BL crosses words |1014|984|3.0488%|
|32Thumb calls, BL within words |844|812|3.9409%|

The four-case JPEG geometric gain is **2.2906%**. Empty operand-queue clocks
fall23248→21245; data waits stay41008 and load dependencies stay13161. These
are overlapping/priority occupancy measurements, not independent recoverable
budgets. Cache/translation-state counts and original work remain unchanged.

All six ARM-heavy SPMark kernels are exactly unchanged, so their original
baseline indices remain **228.5393/192.2189**. Do not include new Thumb microcases
in the original index or claim a full native JPEG deadline pass.

## Qualification and reproduction

92architectural runs and44IRQ/FIQ/SWP boundary cases pass, including mixed ARM/
Thumb returns, memory faults, WFI, privilege, alignment and TLB maintenance.
773directed control cases check target bit0/bit1, both modes, real mode changes,
ADD carry/wrap, conditional outcomes, prediction states and SPSR restoration.
The previous ALU ownership/hold/reset/exception fixture also passes.

Six exercised controls reject the predecessor, full-width comparison, raw odd
BTB targets, ignored address bit1, ignored mode transitions and lost raw T bit.
These distinguish the new prediction contract and real state/address failures;
the predecessor's false redirect is a performance defect, not a claimed wrong
architectural result.

The full six-kernel suite passes12groups, two exact repeats and six corrupted
output controls. Original JPEG passes8groups/two repeats,8unprofiled counter
matches and8corrupted object/pixel controls. The Thumb microbench checks32actual
increments and returns to its ARM caller at both BL alignments, with four
case/profile comparisons and two identical runs. It is a separate fixed-work
benchmark. Final compiled CPU/cache bytes match both frozen benchmark builds;
only noncompiled UPSTREAM metadata is updated afterward.

Patch0069 reconstructs37ZAP lexical streams from83verified pristine hashes.
Preexisting comment/format differences remain; no strict byte reconstruction
claim. No other simulation/checkpoint, board/media/firmware, timer deadline,
PLL, build run or deployment was changed by this work.

```sh
sh tests/cpu/thumb_predict/alu.sh build/sim/NEW-unit
python3 tests/cpu/thumb_predict/micro.py --name NEW-calls --reference 2a04502
python3 tests/cpu/spmark_payload/run.py --name NEW-payload \
  --baseline build/sim/spmark-payload/p0-trim-20261115/result.json
```

Use unique output names and the existing offline simulator image. Original JPEG
runner/qualification sources and all experiment scripts are retained in
`scratch/thumb-frontend-20261116/`; results are under
`build/sim/jpeg-payload/thumb-target-20261116/`,
`build/sim/spmark-payload/thumb-target-20261116/`,
`build/sim/thumb-target-cpu-20261116/` and
`build/sim/cpu-donor-import/thumb-calls-20261116/`.
[Qualification and counters](evidence/thumb-prediction-address-20261116.json).
