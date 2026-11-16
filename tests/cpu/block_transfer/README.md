> **Quarantined candidate, not production:** patch0070 passes these bounded
> tests but causes a deterministic original-ROM early data abort on hardware.
> Production restored the pre-fusion decoder/sequencer. The patch, test and
> measured results remain for repair; do not run its shortened-count oracle
> against the restored implementation or treat its pass as native boot proof.
> Use BLOCK_SEQUENCE_RTL/BLOCK_DECODE_RTL with a privately reconstructed candidate.

# Block-transfer sequencing

```sh
sh tests/cpu/block_transfer/sim.sh build/sim/NEW-block-unit
python3 tests/cpu/block_transfer/aborts.py --name NEW-block-aborts
```

The first test independently interprets decoded micro-ops and checks all
nonempty register lists across load/store, IA/IB/DA/DB and writeback modes.
Defined no-writeback base aliases, user-bank transfers, PC results, failed
conditions and exact shortened sequence counts are covered. Unpredictable
writeback/base-in-list combinations are excluded from the ISA oracle. There
are 786,896 sequences and 6,163,552 ordered words, plus hold, cancellation and
interrupt-priority checks. The model is an architectural-register/word model;
full CPU integration separately checks physical banks, flags, formatting and
exceptions. Advisory messages from the imported sequencer are counted/hashed
to keep logs bounded, without changing its execution or hiding fatal errors.

The second test executes the real CPU and injects external aborts at every
one of eight load/store beats in all four addressing modes, at memory delays
0/3: 128 runs. It checks restored base, original exception LR and FAR, committed
earlier transfers and suppressed faulting/later effects. Every run has isolated
program/build/log paths; existing unit-core and long simulations are untouched.

For an isolated experiment, the unit runner accepts BLOCK_SEQUENCE_RTL and
BLOCK_DECODE_RTL paths; aborts.py accepts --reference-dir for flat RTL overrides.
These are simulation controls, not production feature switches.

## Native privileged single-register regression

`python3 tests/cpu/block_transfer/privileged.py --name UNIQUE` creates an isolated
fixture under build/sim and runs privileged single IA load/store plus explicit
LDRT/STRT controls, each with memory delays0/3. The exact native PUSH/MSR/POP
shape uses protected AP1/domain1 page80422350. Ordinary block transfers must
succeed; explicit user-access instructions must fault with FAR80422350/FSR1f
and the correct abort LR. Optional `--candidate PATH` selects flat source files
without enabling the operand-reference path or modifying the working CPU.

The micro-op oracle additionally checks decoder force-user output. It rejects
original0070 specifically for changing block-transfer memory privilege; corrected
0070+0071 passes. Neither patch is active production yet. Maintained native
observer tools and hardware evidence are described in
[the topic document](../../../docs/block-transfer-sequencing.md).
