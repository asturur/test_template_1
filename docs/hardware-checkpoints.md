# Hardware-to-simulator checkpoints

This is recovered historical evidence from `d751692`. The diagnostic-disk
transport mentioned below has since been retired; use [DDR diagnostics](ddr-diagnostics.md)
and [the JTAG/DDR plan](jtag-diagnostics-plan.md) for current interfaces. This
reconciliation adds no full hardware checkpoint/export implementation.

## Verified capability at the historical checkpoint (2026-11-10)

The present RBF cannot export a resumable whole-phone checkpoint. This conclusion
comes from the maintained HDL interfaces, not an on-board save-state experiment:

- `rtl/ngage_save_manager.sv` restores/flushes C:/PMM sectors. It does not read
  ARM registers, caches, TLBs, SDRAM or peripheral execution state.
- `rtl/ngage_diag_export.v` captures512 diagnostic words and writes two sectors.
  Its `freeze_trace` pauses trace insertion, not phone execution.
- `rtl/ngage_cpu.sv` and `rtl/arm/zap_top.sv` expose fetch PC/CPSR/instruction
  observations, not a precise halt, register scan or execution-state restore.
- Template's CPU Hold keeps the phone in reset. It is not a non-destructive
  pause and must not be used to take an execution checkpoint.
- Verilator `--savable` serializes generated C++ state, including simulator-only
  fields. Those serialization functions do not exist in FPGA hardware.

Consequently an SD diagnostic export or working-save image cannot be imported
as a CPU/host checkpoint. A running board cannot provide missing internal state
retrospectively with the current RBF. Reading only SDRAM is insufficient: dirty
D-cache lines may contain the newest data, and live CPU/peripheral state matters.

## Feasible implementation, not implemented

A hardware capture path could export a versioned, model-independent phone state
to a dedicated pre-created checkpoint image on SD using the existing block-I/O
mechanism. A host converter would then construct a compatible Verilator state.
The existing diagnostic-sector transport proves the small-file write mechanism,
not whole-state capture, halt correctness or simulator restoration.

Required work:

1. Add a precise CPU stop handshake. Stop issuing new work, establish a documented
   retirement/pipeline boundary, and drain or serialize outstanding cache/MMU,
   write-buffer, SDRAM/DDR and flash transactions. Current reset is unsuitable.
2. Quiesce LCD DMA and each peripheral at a defined boundary; freeze phone time
   and input consumption consistently. Keep system clocks, SDRAM refresh and
   the HPS/SD capture transport running. Do not gate the complete clock tree.
3. Export banked ARM registers, CPSR/SPSRs, architectural resume PC and CP15;
   I/D cache data/tags/valid/dirty/replacement state; both TLBs and lookup state;
   any remaining pipeline/queue state demanded by the chosen stop contract.
   Invalidating or flushing everything is not an exact capture and may hide
   the very bug being investigated.
4. Export16MiB phone SDRAM, writable C:/PMM contents, chip registers/FIFOs/IRQ
   state, LCD GRAM/controller state, timers/NOS and input edge history. Immutable
   firmware can be identified by hashes plus overlay settings instead of copied.
   A size estimate around21MiB plus metadata is not a finalized format.
5. Add registered readout paths to internal register/BRAM state. Multiplexing
   debug access must preserve normal104MHz timing and BRAM mapping. Header must
   include format/model versions, clock profile, firmware identities, complete
   marker, section lengths and checksums; never silently accept partial files.
6. Implement canonical-state import into the simulator, mapping physical SDRAM
   into its backing model and preserving all guest-visible state. Native
   `.cpu/.host` files are build-specific outputs, not the interchange format.
7. Verify simulation freeze/export/import/resume round trips, pending operations,
   dirty caches, IRQs, reset and failed SD writes before on-board deployment.
   Then capture a board checkpoint and compare deterministic trace/state after
   restoration. Hardware-to-Verilator compatibility remains unverified until
   that round trip succeeds.

This would be valuable for the hardware screensaver/UI stop: capture it within
seconds on the board, then trace keys in simulation. It is a substantial new
feature, not an OSD switch that can be enabled in the existing build. A smaller
first step is a non-destructive halt plus register/RAM/cache diagnostic dump;
that can diagnose a wait but must not be labelled resumable until import works.
