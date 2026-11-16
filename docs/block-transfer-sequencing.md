> **Production adoption withdrawn — native boot regression (2026-11-16).**
> Both ec6ef3c/seed43 and timing-closed cd858fd/seed43 reach the exact same early
> data-abort loop0x60c, with24,651,807ACKs,12bus errors and last address0a077ffc.
> Original ROM SHA matches stock. Pre-fusion6f3baa2 with identical C:/PMM/MMC
> passes this point and reaches the expected50384d60deferred-erase wait.
> Patch0070 is therefore quarantined. Its source patch, tests and experiments
> remain; production decoder/sequencer are restored byte-for-byte to6f3baa2.
> The active bounded tests missed the privileged single-register IA case.
> Root cause and isolated correction are documented below.
> The measurements below describe the experiment, not the shipping CPU.

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

## Native privilege fault and isolated correction

A fresh-Hold, save-Off first-abort observer caught the original fault before
its recursive terminal abort. Native PC50003248 is `LDMIA SP!,{R1}` in the
kernel interrupt-enable helper, after PUSH/MRS/BIC/MSR. FAR80422350, FSR1f,
SPSRlow53 identify a privileged access to a domain1 protected small page.
The later low-vector faultPC23c8/FARfffffffc is recursive abort-stack failure,
not the original cause. Observer was removed and full stock ROM hash verified.

The fused one-register IA/writeback branch emitted P=0,W=1: the ARM LDRT/STRT
encoding, which forces user permissions. Ordinary post-index writeback is
implicit, so patch0071 clears W as well as P. This correction is retained as
a **quarantined delta after0070**; neither patch is active production. No
permission checks or TLB policy are weakened. No storage/stage is added.

`sim/programs/block_transfer_privileged.S` reproduces the exact native instruction
shape and virtual address using AP1/domain1 (privileged RW, user none). Original
candidate fails with independently checked FAR80422350/FSR1f and exception LR.
Corrected candidate passes load/store at delays0/3. Explicit LDRT and STRT to
the same page must still generate that permission abort, and both do. A new
unit assertion observes decoder force-user output: the original candidate fails
specifically "block transfer changed memory privilege"; corrected786896sequence
oracle passes. Earlier AP3/user-mode benchmark mappings could not reveal this.

Use the isolated real-CPU regression without overwriting another core fixture:

```sh
python3 tests/cpu/block_transfer/privileged.py --name UNIQUE
python3 tests/cpu/block_transfer/privileged.py --name UNIQUE-candidate \
  --candidate build/sim/block-fusion-native-investigation-20261116/candidate-fixed
```

Full candidate architecture/abort suites, repeated benchmark measurements and
original-firmware native boot remain required before re-adoption. Previously
measured0070 performance and fitted area do not qualify corrected0071.
