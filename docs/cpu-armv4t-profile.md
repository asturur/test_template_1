# ARM920T instruction-profile pruning

The first authorized CPU optimization removes ARMv5/5TE execution machinery
from the ARM920T configuration. Patch0060 removes guest BLX, CLZ, saturating
arithmetic/shifts, halfword DSP multiplies and doubleword-transfer sequencing.
It retains ARMv4 MUL/MLA and signed/unsigned long multiplication, the existing
partial-product pipeline and normal instruction scheduling. The uop state
machine shrinks from21 to8 states; the multiply FSM from6 to5 states without
shortening its ordinary multiply schedule. Alternate saturation results become
constants so their downstream selection can be pruned by synthesis.

No PLL, cache geometry, memory controller or phone-peripheral change. Current
clock remains78MHz;104MHz is the timing target. This change adds no pipeline
stage or new guest memory transaction. No ALM savings or routed frequency are
claimed until Quartus measures them.

## Architectural boundary

`zap_armv4t.svh` classifies guest ARM instructions before coprocessor requests,
branch handling or CISC expansion. Unsupported guest encodings become a
canonical conditional UND operation. It rejects absent coprocessors and User
CP15 access; privileged ARM920 CP15 ID/cache/MMU controls remain. The original
condition is resolved against current execution-stage flags, so failed conditions
have no exception or memory/CP15 side effects. Internal register extensions and
Thumb-expanded micro-operations bypass guest classification; Thumb BL's internal
NV prefix is preserved.

Thumb BLX/BKPT and reserved condition1110 branch encodings take UND. The old
fetch-stage ARMv5 BKPT-to-prefetch-abort override is removed. Tests exposed
another existing gap: Thumb SWI/UND links pointed at the trapping halfword.
Both now return to the following halfword (PC+2), checked with normal exception
return instructions, without compensating guest handlers.

References already local: ARM920T TRM DDI0151C §2.2.2 and the ARM architecture
manual DDI0100E §3.2.1. ARM9TDMI extension spaces are undefined. ARMv4's
cond1111 space is UNPREDICTABLE; deterministic UND here is our documented
policy, not an architecture-mandated behavior. Full PSR reserved-bit mask and
Thumb BL prefix/suffix interrupt semantics remain separately audited work;
this is not a claim of complete phase02b/02c ISA qualification.

## Correctness and reproducibility

Run `python3 tests/cpu/armv4t_profile/run.py --out build/sim/UNIQUE`.
The maintained [fixture and runner](../tests/cpu/armv4t_profile/README.md) generate
4,567 ARM cases (nineteen representative extension/coprocessor opcodes × fifteen
conditions × sixteen NZCV states, plus seven NV-policy cases),480 User CP15
cases and four Thumb UND cases. Each matrix case checks trap count, restored
flags, unchanged argument registers and a memory sentinel. Legal ARM multiply,
long multiply, CP15 ID, Thumb BL and SWI return are controls.

The profile guest and fifteen existing integration programs pass at memory
delays0/3:32 runs, including10,102 generated unsupported-instruction checks.
Other coverage includes ARM/Thumb calls, Thumb LDM base preservation, operand
and flag dependencies, SWP with IRQ/FIQ, protected FIQ stores and force-user
permissions, MMU fetch, cache widths and IRQ during refill/writeback.
The old CPU fails the first condition-true CLZ case with signature72 instead
of trapping. A BKPT prefetch-abort failure and an incorrect test ID expectation
were resolved before acceptance; neither is a benchmark baseline.

Evidence: [preserved acceptance/provenance JSON](evidence/cpu-armv4t-profile-20261115.json),
with raw logs in `build/sim/armv4t-acceptance-qualified-20261115/`;
pre-change failure under `build/sim/armv4t-profile-before/`. Other threads'
simulations/checkpoints were untouched. CPU changes are recorded as
`patches/zap/0060-arm920t-instruction-profile.patch` and in `UPSTREAM.json`.
The pinned pristine upstream hashes and full patch chain reconstruct matching
lexical tokens in all37 SV/SVH files. Existing formatting drift predates this
change, so the strict byte verifier still fails; it was run with isolated
reference/output paths, leaving the shared reference cache untouched. The
reconstructed CPU is also compiled and exercised with the profile fixture.

## Performance measurement

The six original-byte SPMark/GLES kernels are measured against the saved
`baseline`, using exactly the same binaries, original native division helper,
synthetic0:0/2:9 memory profiles and independent output checks. Results are in
[the dedicated table](spmark-payload-results.md); no official SPMark/FPS or
whole-phone speedup is inferred from this suite. A cycle-neutral result is
expected when removing hardware for instructions that valid ARMv4T code does
not execute. Future multiply/operand/branch scheduling optimizations can change
those cycle counts separately.

Completed comparison: all12 case/profile rows,84 windows, exact repeats and six
negative controls pass. Index100.0278597 in both profiles (baseline100).
Matrix78,336, transpose12,589, triangle46,592 and fill8-tail7,507 cycles remain
unchanged. Fill16-frame238,223 and fill16-tail6,763 each save11cycles. Full run
565.406s. Scored tail windows vary as preserved in the results table; medians
follow the original measurement rule. This is effectively cycle-neutral.
[Full payload evidence](evidence/spmark-payload-armv4t-profile-20261115.json).
