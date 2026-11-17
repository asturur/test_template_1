# Step5D paired registered-product delivery

Control is exact accepted5C `78d53d4`. One local FSM state retains the already
registered64-bit result after low-half consumption. An immediately following
high micro-op uses it without restarting the multiplier. Reset/older kill/hold
priority is unchanged; an unrelated instruction/bubble expires the fast owner,
and a delayed high request keeps the existing serialized fallback. No payload
register, DSP operation, predictor or bypass network is added.

`bench.py --control --name UNIQUE --case matrix4 --case transpose4 --jobs 1`
selects control; default selects the isolated candidate. `paired.vh` records
pre-edge actual advancement, qualified operand holds, both physical register
writes and the complete measured retirement-PC sequence. Original bytes,
independent math/Unicorn outputs, scored windows, repeats and wrong-output
checks remain. Generated sources/executables/logs live in distinct build paths.

`unit.py UNIQUE` reuses independent signed/unsigned/accumulating integer vectors,
checks immediate paired and expired-owner paths, random holds,18 owned-stage
clear/reset cases,16 held kills, paired flags and a wrong-result negative.
`jpeg.py --name UNIQUE`, `run.py UNIQUE --safety`, `diagnostics.py UNIQUE --build
BUILD` and `irq.py UNIQUE --build BUILD` reuse the existing5C guests/oracles.
IRQ covers capture and paired-ready states without changing the existing guest.
`profile.py UNIQUE --build BUILD` reuses the ARMv4T profile, including scalar
MUL/MLA and long-multiply controls. `analyze.py` audits the recorded final runs.

All builds are serial (one compiler job), use the existing offline simulator
image without pulling/network access, and freeze master sources without branch
or worktree changes. No new benchmark payload, CI, fit or hardware command.
[Schedule, opportunity and measured decision](../../../docs/cpu-paired-delivery.md).
