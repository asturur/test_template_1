# Original CPU versus donor ARM9V2

Source audit, 2026-11-12. Original repository HEAD `ca2b947`; donor checkout
`/Users/andreabogazzi/develop/ngage2` HEAD `542300b`. Donor CPU sources have no
diff against its local master `2904ebc`. No upstream fetch, source modification,
simulation, fit, board access, branch creation or gameplay benchmark was performed.
Only this comparison and its documentation links/checkpoint were added.

## The important distinction

Both descend from ZAP `fc7bd75`, but the donor replaced its integer pipeline.
`rtl/cpu/zap/zap_top.sv` instantiates `arm9v2_core`; `files.qip` builds the
generated `rtl/cpu/arm925t_gen.v`. Its remaining ZAP files supply memory-system,
register-file, CP15 and writeback machinery. Old ZAP execution descriptions in
donor `docs/CPU.md` and early `docs/ARM9.md` are historical.

Our `rtl/arm/zap_top.sv` still instantiates `zap_core`, which uses the Thumb
decoder, predecoder/uop sequencer, decoder, issue/owned operand queue, shifter,
ALU, three post-ALU records, memory and writeback. Additional cache/MMU and
completion boundaries make a bare stage-count comparison misleading. An
eight-stage CPU does not imply eight clocks per instruction; conversely, our
warmed dependent unshifted ADD throughput is already one per clock.

## Execution and decode

| Area | Original core now | Donor now | Assessment |
| --- | --- | --- | --- |
| Pipeline | ZAP integer pipeline with owned two-entry operand acquisition, commit journal, dedicated CP15 read and registered demand completion | F1/F2/D1/D2/S/A/M/W, distinct valid records, early/late dependencies and registered producer selection | Donor is a major rewrite, not a decode patch |
| Basic ALU | Upstream operation implementation retained | Smaller ARMv4T ALU, one add/sub path, separate logical results and carry-independent arithmetic Z calculation | Local timing/area ideas; no automatic ordinary-ADD throughput improvement |
| ARM instruction classification | Original ARMv5TE-capable ZAP decode remains active despite ARM920 identity | ARMv4T classifier rejects v5 encodings, invalid memory forms and privileged coprocessor accesses in User mode | Architectural-fidelity audit candidate; do not replace TI versus ARM920 CP15 identity |
| Thumb | Existing ZAP ARM expansion with targeted compatibility fixes; stateful BL pair | Shared derived Thumb expansion plus explicit BL-prefix/suffix architectural records | Interrupt/suffix behavior deserves directed comparison first |
| LDM/STM and SWP | Existing internal-uop expansion and conservative locks, with our accepted SWP ownership/metadata fixes | Precomputed D1 register-list count/offsets; sequenced block transfers, paired destinations and optimized final-word/PC pickup | Potentially useful for copies, stacks and graphics; precise abort/base restoration is essential |
| Shift/forward | ZAP shift and wide existing producer network, isolated by operand ownership and refreshed queued values | Common rotate network; S handles early operands and A uses a small late M/W pickup | Avoids holding an unshifted consumer as long as a shifted one; not a drop-in issue-module change |
| Multiply | `zap_shifter_multiply.sv` is byte-identical to pinned upstream; its FSM documents five clocks per32x32+64 operation | Registered DSP product, extra accumulate phase, paired long-result destinations | Bounded porting candidate; compare acceptance/occupancy and dependencies rather than headline stage counts |
| Loads | Our checked translation/cache owners and blocking P2 completion capture keep data/faults together | Registered short hit response, separate M/W load records, early/late bypass and qualified early miss returns | Largest execution-side experiment to measure alongside cache latency |
| Branches/returns | Existing ZAP BTB/RAS plus tag-miss correctness repair | New prediction/redirect integration, checkpointed return-stack state and earlier direct-branch handling | Particularly relevant to branch-heavy Thumb code; predictor rewrite is not required to fix our small return matcher |
| Register file | Donor-inspired replicated MLAB/latest-writer storage already ported as0057, preserving our five-read and generic writer semantics | Latest-writer MLAB storage and collision-safe bypass | Already adopted; do not budget its savings a second time |

Direct comparison with `scratch/zap-upstream/src/rtl/` establishes that our
`zap_shifter_multiply.sv` is identical and `zap_alu_main.sv` adds only seven
lines carrying/qualifying SWP metadata. Its arithmetic implementation was not
redesigned. `zap_decode.sv` differs only in silenced PC-shift diagnostics. The
Thumb decoder does contain functional changes. Our substantial changes are
therefore around ownership, memory completion and ARM920 cache/MMU behavior,
rather than new or faster individual ALU operations.

## Concrete correctness and predictor candidates

1. **Thumb BL halves.** Our `zap_mode16_decoder.sv` T_BL case stores the prefix
   offset, emits a dummy NV instruction and suppresses IRQ/FIQ for the halves;
   the suffix constructs a full branch using that saved offset. Donor treats
   the prefix's LR update and suffix as separately interruptible architectural
   operations, including a lone suffix. Its tests include `tbl_irq.S` and the
   standalone-suffix case in `arm9_branch_slots.S`. This is a source-level
   semantic difference, not a reproduced original-phone failure. Port the
   directed fixtures before choosing the implementation change.
2. **MOV pc,lr return recognition.** Our `zap_predecode_main.sv` RAS matcher,
   despite the comment naming LR, still ends its source field in `4'd15`.
   LR is r14; the pattern currently misses the intended ordinary return.
   `docs/branch-prediction.md` already recorded it without changing it. Donor's
   predictor explicitly handles MOV pc,lr/BX lr and load-to-PC returns. A narrow
   matcher fix with prediction/collision/nesting tests is a smaller first task
   than transplanting the complete donor predictor. No gain is measured.
3. **Strict ARMv4T undefined behavior.** Our raw decoder still recognizes
   BLX, CLZ, saturating arithmetic, DSP multiplies and doubleword forms from
   upstream. Donor traps unsupported encodings under the applicable condition
   and preserves ARMv4T interworking/PSR rules. Test condition-failed cases and
   existing internal uops before excluding instruction families; internal
   encodings must not be mistaken for guest instructions.

Donor documents further upstream corner-case fixes, including Thumb exceptions,
long multiply flags and aborted block-transfer base restoration. Some overlap
our fixes or are irrelevant to the replaced cache path. A fixture-by-fixture
audit is needed; neither patch count nor donor documentation proves every
corresponding issue exists in our current core.

## The memory-system differences matter as much as execution

Our production core uses16KiB I +16KiB D,64-way ARM920-shaped caches with
32-byte lines and two64-entry associative mixed-page TLBs with real lockdown.
The donor defaults to32KiB I +32KiB D, two-way,16-byte lines and per-page-size
direct-mapped TLB buffers. Its CP15 reports the TI ARM925T phone geometry
(16KiB I/8KiB D); TLB lockdown is stored without affecting allocation. These
are different software-visible identities and different implementation choices.

Donor also has hit-under-fill and critical-word background return behavior.
Its wrapper documents that cacheable-fill errors are consumed without abort,
whereas uncached/table-walk errors abort. Our transfer/installation and precise
uncached-fault ownership must be preserved deliberately. Do not copy an early
completion path while silently weakening error behavior or bypassing permission
checks. Our streaming32-byte refill and posted write buffer already remove
some costs discussed in older prospective docs; donor's benefits are not all
missing from this core.

## What the donor's measurements actually establish

These are historical same-donor ZAP-versus-V2 results from
`docs/consults/2026-10-25-codex-arm9v2-s12.md`, D16 prediction-on, not a fresh
measurement of our current core or of today's larger-cache donor defaults.
The `0:0 / 0:3 / 2:9` labels are that bench's memory-latency profiles, not clocks
or cache sizes. Values below are percent fewer clocks, not percent higher FPS.

| Fixture/scope | 0:0 | 2:9 |
| --- | ---: | ---: |
| cache, whole program |20.5% |9.7% |
| gba_arm, whole program |17.4% |5.5% |
| gba_thumb, whole program |12.8% |2.7% |
| crand1, cached body after setup |7.9% |2.6% |
| ctrand1, cached body after setup |15.4% |3.1% |

The same report's final EFile milestone used13.78% fewer clocks than its merged
ZAP reference, but it explicitly notes different retired-instruction totals in
the timed firmware boots. It is not an equal-instruction CPU comparison or a
gameplay result. The report's CPU-only104MHz fit failed at−2.951ns. That is a
historical result, not the latest whole-core donor slack or current timing.
The intended35–50% compiled-code improvement was not achieved. Memory stalls
shrink the advantage materially.

## Recommended order

First bring over behavioral regression coverage and assess the Thumb BL and
small return-recognition fixes. Then measure multiplier replacement and the
ALU/shifter timing ideas separately against our existing instruction/flag/hold
contracts. Treat donor short-hit load completion, early/late load consumers and
block-transfer sequencing as a larger cache/LSU/backend project with explicit
latency and fault ownership, rather than removing our timing registers blindly.

Consider wholesale V2 integration only as a separate, measured alternative.
Use our ARM920 CP15/cache/TLB contracts and the same caches, memory latency and
clock when isolating execution benefits. Benchmark dependent/unshifted ADD,
shifted dependencies, LDR-to-ADD versus LDR-to-address/shift, all multiply
variants, branches/returns, ARM/Thumb BL and LDM/STM including PC/abort cases.
Run mixed CPU/LCD traffic and a repeatable game scene afterward. Retired
instructions, cycles, stalls, area and routed timing must all accompany any
claim that a candidate is better.


## Benchmark-first import roadmap

The user requested an ordered plan covering every identified difference, with
benchmarks written and the original measured before any import. The actionable
[CPU donor import plan](cpu-donor-import-plan.md) supersedes the brief ordering
above. It includes the full V2 comparison, already-ported items, ARM920-specific
adaptations, per-phase tests, cumulative attribution, resource/timing gates and
Call of Duty scene requirements. Next work is baseline/harness/benchmarks only;
no CPU change was made while preparing the plan.

The subsequent [first ARM baseline results](cpu-donor-baseline-results.md) now
measure H0, H1 and frozen current work. They do not measure the donor execution
pipeline or complete phase00/01. No CPU import has started.
