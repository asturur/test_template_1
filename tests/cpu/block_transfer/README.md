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
