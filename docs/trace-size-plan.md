# Plan: smaller, useful boot traces

Do not change the active `c4-reset-12b` run. First measure the completed trace and keep its provenance. A live sample at ~4.1B cycles contained 4,725,025 complete rows: keypad/GPIO 91 MB, C: flash 71 MB, timer 43 MB, NOS peripheral 31 MB, reconstructed flash tail 25 MB. The current TSV is readable by existing LCD composite, render and oracle comparison tools; the run also writes CP15 traffic separately. Exact sizes vary by moment.

## Proposed modes

1. **Long boot (default after validation):** compact machine-readable summary with periodic cycle/PC progress, interrupt/timer counters, device access counts, C: read/program/erase totals and last error, NOS debug text, exception/panic details, and explicit dropped/suppressed counts. Retain an exact rolling tail of recent full bus and CP15 rows. Keep every unmodeled/failing access and its immediate context. Preserve LCD commands, DMA trigger/source/destination/length, full pixel payload and timing losslessly in a dedicated file; save live snapshots without waiting for the process to finish. Capture checkpoints so a fault can be replayed before it happens. No silent filtering of important device writes.
2. **Targeted investigation:** opt-in exact address/device filters and cycle/instruction windows, with full ordered rows and no sampling inside the chosen window. Run from a compatible earlier checkpoint; record firmware, binary, C: and checkpoint hashes, options and trace settings. Expose when the relevant checkpoint is not available.
3. **Full trace:** current behavior for short reproductions and HDL/C++ lockstep. Maintain its existing TSV schema; filtered summaries must never be fed into an exact-order comparison as full traces.

Count and summarize repetitive polling rather than saving every row in long mode, but keep first/last cycle, value changes, totals and a recent exact tail; do not merge read sequences where timing or ordering is required. Preserve writes, including C: command/data sequences, at least in a focused recent tail; record aggregation limitations explicitly. Firmware may depend on read counts and timing. Capture an explicit marker for trace truncation.

## Validate before switching defaults

Implement modes opt-in; run identical firmware from the same checkpoint in full and reduced modes. Compare status, cycle, failures, device and C: counts, NOS text and every LCD frame; replay a known stopping point from an earlier checkpoint using a targeted window and compare its exact ordered rows with full mode. Test trace consumers for each declared format. Measure file sizes and simulation speed on representative segments; set a budget only after results, not by deleting evidence silently. Check that checkpoints preserve needed peripheral state and inputs; rolling last-10 retention alone cannot replay an old event after it expires.

Tool output is a separate allowance cost: inspect result summaries and filtered slices, not entire trace files. A large file on disk is not itself 300 MB of model context.
