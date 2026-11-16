# LDM/STM and PUSH/POP sequencing — 2026-11-16

Patch0070 reduces bookkeeping micro-ops for ordinary block transfers while
retaining ordered memory accesses, base-restored aborts and PC/SPSR handling.
Actual PLL stays78MHz;104MHz remains the timing target. The78MHz physical fit/timing gate now passes;
104MHz timing and native JPEG qualification remain pending.

## Changes

The first memory operation also initializes the private pointer through the
existing writeback lane. It reads the original base and writes DUMMY0, keeping
the architectural base unchanged until success. Decrementing DA/DB starts at
the lowest address, then later beats increment. This removes PUSH setup without
changing transfer order or making an early architectural SP update.

For incrementing IA/IB, the final beat already computes the correct final base.
Its ordinary load/store writeback lane can write Rn directly, removing the
separate base-copy micro-op. POP benefits from both changes. Single-register
incrementing transfers reduce to ordinary memory operations. Non-writeback
ordinary transfers also avoid an unused trailing NOP. Private extension bits
34/35 are already present in the instruction packet; no new packet/state/RAM
or pipeline stage is added. Guest instructions cannot set bit35. This is word
memory decoding only; guest long-multiply and other instruction classes retain
their meanings.

S-bit transfers, PC bases, empty lists and writeback/base-in-list combinations
keep conservative handling. Existing Thumb base-in-list writeback suppression
remains. Loads to PC still use DUMMY1 followed by the existing final PC operation;
L4 and SPSR/state restoration paths remain. IRQ/FIQ stay eligible at the first
operation and masked inside an accepted block. Holds and cancellation keep
ownership fixed. Clearing the lowest list bit uses `list & (list-1)` rather than
priority encoding and decoding the same bit again. Count generation is unchanged.

## Measurements and limits

Both synthetic I:D profiles repeat exactly with original code and outputs.
These are fixed-work CPU/cache simulation results, not official SPMark scores.

| Work | Before | After |
| --- | ---: | ---: |
| Original JPEG8×8mode10 |108853|107047|
| JPEG8×8random mode10 |108869|107063|
| JPEG8×8random mode8 |107724|105742|
| JPEG16×8mode10 |214749|211231|
| Matrix |54442|54394|
| Transpose |5337|5337|
| Triangle |26915|26739|
| Fill frame0:0 /2:9 |71263/201306|71263/201306|
| Fill16tail /fill8tail |2564/2629|2564/2629|

The four-case JPEG suite gains1.7284%. Original six-kernel indices become
230.3221/193.7181, +0.1241% over the preceding accepted change. Gains are modest;
this does not remove the larger CPU/cache pipeline bottleneck.

In JPEG, decode-sequencing clocks fall8405→4252, but data waits rise38035→39389
and load dependencies13161→13842 as the earlier transfers change overlap and
probe/translation timing. Empty operand clocks21574→21565 barely change. Total
runtime improves1806clocks; these categories are not additive recoverable losses.
The new full six-kernel profile also reconciles every original guest counter.

The original64-pixel converter executes22500Thumb instructions:5152LDR,
2360STR,905BL,1098BX,1107POP,586PUSH, plus shifts/arithmetic/block transfers.
It executes no multiply or PSR/CP15 operations. PSR flags-only writes already
avoid resync; MRS/SPSR writes are ordinary execution operations. Privileged
CP15 reads still drain the pipeline. Whole-OS/codec costs are unmeasured; no
PSR/CP15 RTL change is justified by this converter profile alone.

## Qualification

- 786896independent register/address-model sequences and6163552ordered words,
 every nonempty register list across the defined addressing/writeback classes;
 user banks, base aliases, PC, failed conditions and exact micro-op counts.
- 18hold checks, four interrupt-boundary checks, four cancellation classes.
- 92existing CPU architecture runs and44IRQ/FIQ boundary runs.
- 128real CPU external-abort cases: all eight load/store beats, four modes,
 two memory delays. Check original base, exception LR/FAR, preceding effects
 and suppression of the faulting/later transfers.
- Six exercised broken variants rejected: disabled first/tail fusion, wrong
 first destination/final source, decrement pointer mode and single-IA offset.
- Full six-kernel12groups/two exact repeats/six bad outputs. JPEG8groups/two
 repeats/8unprofiled full-counter matches/eight bad object/pixel controls.
- All51compiled source/include files byte-match both accepted benchmark builds.
 Patch0070 reconstructs37ZAP lexical streams from83verified pristine hashes;
 preexisting formatting/comment drift prevents a strict byte reconstruction claim.

Initial abstract checks incorrectly expected an address from a condition-failed
instruction; corrected to check only executed addresses. An initial abort fixture
used unencodable ARM immediate0x101; distinct small constants fix it. A negative
variant correctly failed on an architectural register before its originally
expected address assertion. Failed logs remain excluded from accepted results.

```sh
sh tests/cpu/block_transfer/sim.sh build/sim/NEW-block-unit
python3 tests/cpu/block_transfer/aborts.py --name NEW-block-aborts
```

Maintained tests and their scope: [README](../tests/cpu/block_transfer/README.md).
[Machine evidence](evidence/block-transfer-sequencing-20261116.json).
Raw frozen sources/results are under build/sim/{jpeg-payload,spmark-payload}/
block-transfer-final-20261116 and build/sim/block-transfer-final-{cpu,abort}-20261116.

## First fitted result

Build43797500563, commitcd858fd, seed43/debugOn: all constrained timing passes
at78MHz (setup+0.197ns,hold+0.174ns); all16SDRAM DQ I/O/OE registers pack.
38,809ALMs/45,220registers/503M10Ks/42DSPs. The preceding6f3baa2 build used
38,385ALMs/44,288registers with the same M10K/DSP totals and seed. The measured
increment is424ALMs/932fitted registers; "no added RTL state" does not mean zero
physical resource cost. Counts include synthesis/packing/placement effects.
No104MHz closure or board benchmark pass is implied. The later erase/refill
fix is required for native C: installation; this CPU-only artifact was retained
for comparison rather than deployed with that known admission deadlock.
