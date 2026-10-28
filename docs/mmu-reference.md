# MMU-aware independent CPU reference

Checkpoint: [status.md](status.md). Implemented 2026-10-27.

The original software runner still stops at MMU enable by default. The separate
`--mmu-reference` option lets pinned Unicorn 2.1.4 TI925T execute its own MMU while
continuing to validate accesses against the bounded C++ board. This does not
substitute a synthetic virtual-memory map or the EKA2L1 kernel handoff.

## Address conventions and validation

An isolated probe in `scratch/adc-bringup/unicorn_mmu_probe.py` establishes the
native engine's conventions: code hooks report virtual PCs, data hooks report
physical addresses, and the native memory backing uses physical addresses.
A load through virtual `0x30001000` reaches the mapped physical data correctly.

For instruction validation, the runner resolves the virtual PC using guest CP15
TTBR/FCSE state and section/coarse/fine descriptors, then checks the code bytes
against the physical board and native backing. This host fetch checker does not
drive Unicorn's execution translation or replace native permissions/fault checks.
Data accesses continue through the physical hook and the shared board.

The focused native test executes nonidentity code and data through both section
and coarse small-page mappings. Descriptor parsing also covers large/tiny pages,
but those formats and MMU fault/exception equivalence are not comprehensively
tested. TI925T is an ARMv4T reference, not a cycle-exact physical ARM920T.

Repeated fetch mappings are cached in 1-KiB units. Guest CP15 writes clear them;
writes to recorded descriptor words invalidate the mapping cache. Every code
fetch and data operation is still checked. This is a host-side optimization,
not a model of Nokia cache/TLB timing or all stale-TLB corner cases.

`--compact-bus` omits ordinary RAM/ROM data log rows; `--no-instruction-trace`
omits the per-instruction text file. Both retain access validation and original
firmware execution, including LCD waits and the later ROM integrity check.
All modeled I/O and its order remain recorded for comparison.

## Comparison scope

The first MMU-aware run matched all **36,977** modeled device events, including
the channel-6 ADC result, through the first timer write at `0x0c120a04`, under
both FPGA memory timings. That intermediate model/run is preserved under
`build/checkpoints/adc-first-timer-write/`, with a hash manifest.

After accepting the exact timer setup writes, the software exposed an FPGA-only
read at `0x0c120100`. The [BTB collision fix](branch-prediction.md) addresses that
CPU failure. Do not label the later 50-million-instruction software limit a boot,
or compare its entire event stream as if it stopped at that old hardware access.
Final current-run measurements belong in [status.md](status.md).

The comparator still verifies firmware/model/extension hashes, board switches,
and the full explicit ADC-input configuration. With default physical-only
software it compares only the recorded pre-MMU prefix. With `--mmu-reference`
it compares through the first unknown access and does not apply that prefix cut.
A limit or a mismatching frontier is not a successful full-path comparison.

## Reproduction

```sh
make sim-oracle-check
build/oracle/venv/bin/python sim/oracle.py --ideal-clocks --lcd-probe \
  --rom-extension --boot-io-probe --uem-adc 6=512 --mmu-reference \
  --compact-bus --no-instruction-trace --max-instructions 500000000
```

The explicit sample is an assumption. This reference provides independent CPU
execution, while peripheral behavior remains shared and unverified against a
phone. Symbian boot, hardware timing and complete instruction-state agreement
are not implied by matching device accesses.

## Optional immutable-ROM fast path

`--fast-rom-reference` additionally requires MMU reference, compact bus and no
instruction text. It still executes the original guest instructions, including
MD5. It validates immutable ROM basic-block bytes once, uses the synchronized
native backing for ordinary core-ROM/RAM reads, and keeps C++ checks for all
writes, MMIO, reconstructed-tail reads and holes inside native allocations.
RAM starts identically zeroed and every write stays mirrored. It refuses flash
commands/writes, requires array-mode flash and alignment checking, and stops if
a CP15 block boundary is unsupported. These are explicit scope restrictions.

Instruction counts become a basic-block upper bound at the final stop. Reported
I/O order/address/data and stop PC remain directly comparable. Repeated self-
branches are detected without calling an IRQ-enabled loop a masked failure.
The comparator can establish the same loop from the HDL's last 32 retirements
at a cycle limit; it labels that scope and does not relabel timeout as boot.

The slow 500-million-instruction experiment was interrupted to avoid repeated
host checks. Its absent result is not a completed test. The fast run completed,
matching 36,982 I/O events and the FPGA's rejection loop. See
[firmware-integrity.md](firmware-integrity.md). The latest oracle suite has
twenty tests, including section/coarse execution in both reference modes,
unknown-MMIO checking, ADC configuration and quiescent-loop comparison.
