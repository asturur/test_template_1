# Completed EUART1 / shared CTSI integration — 2026-11-13

The UART controller is now selected in files.qip and instantiated in production
UPP, replacing generic storage and forced TX-idle for its implemented registers.
This completes the **host byte-transport/interrupt boundary**, not the external
DSP protocol responder or original-firmware Phone/Menu boot.

## Wiring and ownership

* EUART1 resides inside ngage_upp_peripherals.v. Board/UPP expose transaction-
  level adsp_tx/rx byte handshakes. Names describe the modeled transport; physical
  AMA/McBSP/UEM pin and baud timing are not claimed.
* Original kernel table50322FE8 contains8-byte rows: row26 is FiqCTSI_FIQ,
  row25 FiqCTSI_IRQ. EUART RX/TX status masked by its native00C/00E enables
  joins SIMIF on existing FIQ26. No additional ICU source is invented.
* SIM low and EUART high halfword status share0C1500B8 without suppressing each
  other on a32-bit read. UART data/control uses its own claim, error and ready
  checks, excluded from generic GPIO storage. Existing response slot13 is reused;
  no seventeenth wide response snapshot is added.
* UART effects obey commit and response_pending, including destructive RX reads,
  full TX backpressure, cached BRAM prefetch and TX-idle only after drain.
* MiSTer explicitly ties the not-yet-implemented external D550 peer inactive.
  It backpressures TX, rather than silently discarding it or claiming a reply.
  **Do not deploy this as a DSP boot fix.** Completing the D550 peer is still
  necessary before a useful hardware startup result.

Resource inventory: two16x8 synchronous M10K FIFOs plus existing UART controller
state. Shared response storage and existing FIQ26 are reused. No DSP CPU, video
renderer, PCM engine or additional wide message queue. No fitted ALM/BRAM or
routed timing result is claimed; preserve78MHz PLL and104MHz design objective.

## Completed validation

* native_euart_board: unchanged original TX/RX/HAL/poll instructions through the
  full board bus, actual CPU FIQ vector/source26, authored wrapper and device
  byte loopback.78/104MHz schedules, waits0/3 pass in27001/31140 cycles.
* ctsi_board: simultaneous real SIMIF ATR and UART RX, full/halfword status
  lanes, independent enables/ACKs, FIQ26, held/destructive reads, exact-once TX,
  backpressure/idle/drain and warm reset; immediate/registered board profiles pass.
* Existing four SIM present/card combinations,33 registered peripheral-response
  checks,132 retained-address ownership checks, exhaustive regional ownership,
  and isolated EUART saturation/wrap/flush/IRQ/reset checks pass.
* Existing MiSTer internal-CPU integration also passes SIMIF, LCD/DMA,
  diagnostics, IRQ/FIQ and SDRAM with waits.
* Regional ownership oracle now explicitly includes the newly dedicated UART
  owner. Source lists were extended to resolve the selected submodule; no other
  test assertions were weakened. Verible formatting passes.

The first attempted native registered-profile override was rejected by Verilator
as a duplicate parameter assignment. It was removed, not worked around in RTL:
registered admission is tested by the dual-board fixture, while unchanged-driver
FIQ execution uses the supported external-bus profile. Neither substitutes for
a complete production internal-CPU boot. No firmware patches or hardware writes.

Next DSP boundary is the original ADSP server startup/ACK/retry protocol feeding
ngage_adsp_diagnostic and the N501 model, with actual reset/clock/flash ownership.
Native SIM/MTC readiness remains a distinct unresolved boot dependency. See
sim-adsp-native-progress.md and adsp-rom-investigation.md.
