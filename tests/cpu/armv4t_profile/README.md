# ARM920T instruction profile

Run the production CPU/cache integration bench in a fresh isolated directory:

```sh
python3 tests/cpu/armv4t_profile/run.py --out build/sim/armv4t-profile-UNIQUE
```

Uses the existing offline `jotego/simulator:arm64` image and installed ARM GNU
binutils. It compiles once, then reuses that exact executable with each guest
program, at memory delays0/3. Other simulation directories are untouched.
`--profile-only` selects only the profile guest. `--reference-dir DIRECTORY`
selects saved pre-change RTL through the existing core bench for a negative
control. Programs and logs, generated instruction tables and `result.json`
stay under the selected output directory. A failure stops the suite.

The generated matrix checks nineteen unsupported ARM extension/coprocessor
encodings under all fifteen conditions and sixteen NZCV states. Condition
expectations are independently computed in Python. It checks trap counts,
unchanged argument registers, unchanged memory and restored flags after UND.
Seven cond1111 cases check this implementation's deterministic UND policy;
ARMv4 defines that condition space as UNPREDICTABLE, so this policy is not a
claim that the architecture mandates UND there. User-mode CP15 MRC/MCR get
the same complete condition matrix. Thumb BLX register/immediate, BKPT and
reserved condition1110 branch must trap and return to Thumb. Legal Thumb BL and SWI return,
ARM MUL/MLA/UMULL/SMULL/UMLAL/SMLAL and privileged CP15 ID reads must survive.

Additional existing programs cover ARM/Thumb calls, LDM writeback, flags and
operand dependencies, IRQ/FIQ/exception returns, SWP, MMU permissions, cache
load widths and interrupt/refill/writeback interactions. SPMark original-byte
payload performance is measured separately by `tests/cpu/spmark_payload/run.py`.
This is local RTL acceptance; FPGA fit, routed timing and phone boot still
require a subsequent build/hardware run.
