# Isolated Step4G second-store preparation

Fixed passing4F is the control; the three-file overlay adds two pending bits,
using existing Issue/Shifter data lanes for exact producer ownership until data
returns. No production RTL is replaced. Original workloads and existing
memory/retirement/negative oracles remain active.

[Measured result, qualification, risks and replay](../../../docs/cpu-store-second.md).
[Audited source hashes and all192 pairs](../../../docs/evidence/cpu-store-second-20261116.json).

`run.py --control` selects exact4F; otherwise it selects4G. `--safety --stress`
composes the previous focused guests with producer/ordering/physical-bank cases.
`--arg +second_hold=1` adds a bounded test-only capacity hold; leave it disabled
for performance. Complete fixture include hashes and frozen fixture files protect
build reuse. `analyze.py` audits the named final runs and regenerates evidence.
