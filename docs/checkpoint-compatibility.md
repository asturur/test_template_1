# Checkpoint compatibility after integration

Checked 2026-11-11 at integration commit `908b2d34d306ee08c6454583cc72eea12be9fbe0`.
The old 10.5B checkpoint **cannot safely resume on this core**. Start a new
cold-boot lineage to test the integration changes. The old checkpoint remains
valid with its original frozen simulator.

## Evidence

The saved source manifest identifies model `6af112481fad51dd`. Against this
checkout, 26 source files differ and two old `.sv` transport paths no longer
exist (their replacements are `.v`). Renaming alone is not the incompatibility:
actual state ownership and representation changed.

- The CPU still uses ZAP, but its register file now has replicated memory banks,
  latest-writer selection and held/committed bypass state instead of the former
  register array. Cache/TLB ownership implementation also changed.
- Six programmable timers replace the old boot-delay model. Their pending,
  completion, count and reload state cannot be populated from the old layout
  by matching field offsets.
- ICU priority/masking, configured keypad edges, general DMA, LCD queues,
  local arbitration, MMC and passive BRAM storage have changed or added state.
- The board-selected DDR flash-cache/stream/bulk path has different internal
  cache and transaction state from the old instruction-only ROM buffer.

Verilator checkpoints serialize internal HDL/testbench state, including dirty
cache data and in-flight transactions. They are not portable architectural
CPU/RAM snapshots. Copying RAM/PC alone would omit dirty data, CPU pipeline and
CP15 state, kernel-visible peripheral ownership and pending interrupts. No
reviewed converter exists for this integration. The old observer-only upgrade
flags do not cover these changes.

A zero-cycle restore/resave using the exact old executable succeeded at
10,500,000,000 cycles. CPU and host outputs were byte-identical to the original
pair. PC was `5039F6E0`, LCD words 38,124, frame complete/display on, data errors
zero. This validates checkpoint readability, not boot progress on the new core.
Test-only checkpoint/input duplicates were removed. Original files remain:

`build/sim/runs/latest-keypad-fast-12b/checkpoint-10500000000.{cpu,host}`

Docker responds again; its running-container inventory was empty after the test.
No incompatible restore or new long boot was launched.
[Hashes, source differences and test result](evidence/checkpoint-compatibility-2026-11-11.json).

## Fresh simulation profile

Use the current production DDR path, general DMA/LCD/IRQ/timer logic, normal
power-up, 78MHz CPU and 26MHz timer enable, NOS64, line refills, no overlays and
unmodified core/extension/C: inputs. Enable the simulation-only fault context
observer to catch the original bad-pointer producer/caller if the panic recurs.
The runner copies C: for its own run; do not overwrite the canonical image with
simulation output. Initial bounded command (50M cycles):

```sh
python3 tests/phone/hardware_boot/run-logo.py \
  --name integration-cold-baseline-50m --cycles 50000000 \
  --powerup normal --sys-clk-hz 78000000 --timer-clock 26mhz --nos-tick-hz 64 \
  --line-refill --production-ddr --fault-context --stop-on-kernel-panic \
  --core scratch/hardware-live/service-loaded-boot/core.bin \
  --extension scratch/hardware-live/service-loaded-boot/extension.bin \
  --cdrive scratch/hardware-live/hardware-cdrive.img
```

This command is recorded, not executed. A 50M smoke is not a Symbian boot gate.
After validating the new model, continue only its own checkpoints with matching
options and executable. For a long run, retain billion-cycle checkpoints and a
latest complete resume pair; discard intermediate cadence snapshots as requested.
This harness models memory response timing and no inserted MMC card. It does
not cover physical DDR/SDRAM timing, HPS persistence or an MMC filesystem boot.
