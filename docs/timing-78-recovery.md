# 78 MHz timing recovery: build43083011635

Build4969d77 fits at40,145/41,910 required ALMs,47,294 registers,501/553 M10Ks and42 DSPs. Core setup is−1.276 ns/TNS−302.002 ns, reported Fmax70.94 MHz. Core hold is+0.247 ns; recovery/removal and other constrained clock domains pass. Actual PLL/SDC stay78 MHz (12.820 ns reported relationship);104 MHz remains the RTL design objective. Diagnostics remain enabled.

## All1,000 paths accounted for

Both the CSV and full routed report were parsed and crosschecked by exact from/to node pair and slack. There are1,000 unique sampled endpoints,881 negative and119 positive. This is one worst path per endpoint in the exported subset, not every timing path or a complete count of every failing endpoint. Every row is classified in [the annotated CSV](evidence/timing-78-43083011635-paths.csv); report identity/hashes and statistics are in [JSON](evidence/timing-78-43083011635.json).

| Family | Paths | Negative | Worst slack ns | Mean cell ns | Mean route ns |
| --- | ---: | ---: | ---: | ---: | ---: |
| SWP lock admission | 785 | 690 | -1.276 | 3.773 | 8.729 |
| UPP owner packet decode | 206 | 187 | -0.884 | 4.092 | 8.306 |
| I-cache fast word to fetch | 2 | 2 | -0.437 | 4.006 | 8.258 |
| D-cache checked owner | 2 | 2 | -0.098 | 3.793 | 8.330 |
| Cache completion positive margin | 5 | 0 | 0.040 | 3.527 | 8.410 |

Routing is roughly two-thirds of these data-path delays. The repeated launch register is CP15 translation-base bit15, not an RF register:785 paths/690 failures. Changing the RF again would target the wrong source. RF-to-operand margin is+1.481 ns, CP15 read+1.530 ns, and the reported operand-stage minima are positive (queue feedback+1.138 ns). The RF hierarchy now costs910.7 inclusive ALMs, including400 memory ALMs and298 registers; hierarchy comparisons are not a controlled whole-core savings experiment.

## Root causes and selected fixes

1. **SWP lock admission (690 failures).** CP15 base -> TLB owner equality -> cache request/readiness -> speculative SWP lock -> UPP block_cpu -> DMA selection or peripheral admission. The worst path has11 logic levels and13.314 ns data. Its routed common chain is TLB owner~40/owner~45, request_ack~1, adapter comb~4, block_cpu and DMA bus_engine/descriptor selection. The board-wide lock now uses the existing swp_lock_active register, set on accepted uncached-SWP cache requests. cache_access issues the bypass read only from a subsequent state, so lock is registered before the first bus beat. No CPU stage is added; already accepted DMA still drains. Test locked reads/writes, read-write gaps, competing DMA, IRQ/FIQ, abort and reset.

2. **UPP owner packet decode (187 failures).** Registered dma_local_active selects wide CPU/DMA fields, followed by lane/address/command decoding and device state enables. The worst is NOR state−0.884 ns; other destinations include UPP RAM/config, CBUS and C: NOR. The physical mapper shares lane-decode cells across entities (e.g. a CBUS-named comparator appears on a NOR path); that name does not prove CBUS is functionally driving flash. A request register now captures the selected slow-bus fields before decode. It holds one owner through the transaction, cancels immediately on CYC/STB withdrawal and clears during the existing response/gap. This adds one admission clock only on this bus. Dedicated CPU SDRAM, refill transport and native fast LCD streams bypass it. Measure real LCD/MMC fixture cost, preserve accepted-owner drain and reset.

3. **I-cache fast word to fetch (two failures,−0.437 ns).** Writeback PC bit29 traverses L0 result-hit/stream-line selection and the variable word/data mux before the fetch abort endpoint. Select the requested32-bit word from each candidate line in parallel, then choose the word using the late result/stream selector. Keep line/token validity and original completion timing. An assertion compares the new word against the old selected-line expression; compare whole-CPU effects/cycles.

4. **D-cache checked owner (two failures,−0.098 ns).** token_va bit15 -> owner -> checked-VA mux -> repeated context/address equality -> pending_pa. Export the exact checked-owner predicate from TLB instead of reconstructing it via selected checked-address buses. With MMU disabled all checked fields are live inputs; with MMU enabled the old conjunction is true exactly when the permission token owns the request. Preserve all context/request comparisons and existing pending-translation gating. A simulation assertion compares the new predicate with the complete old conjunction. No stage, token granularity or permission rule changes.

5. **Five remaining sampled cache-completion endpoints pass**, worst+0.040 ns. They are close enough to remain explicit next-fit watch items. Removing the earlier chains changes placement, so the fixes above do not establish routed closure by themselves.

## Destination coverage

| Launch block | Destination block | Paths | Negative | Worst ns |
| --- | --- | ---: | ---: | ---: |
| zap_cp15_cb | ngage_dma_channels | 169 | 130 | -1.276 |
| zap_cp15_cb | ngage_lcd_bus_queue | 64 | 64 | -1.057 |
| zap_cp15_cb | ngage_lcd_stream | 7 | 7 | -1.033 |
| zap_cp15_cb | ngage_dma_engine | 55 | 53 | -1.010 |
| zap_cp15_cb | ngage_debug_video | 16 | 16 | -0.984 |
| ngage_upp | ngage_am29n643_state | 11 | 11 | -0.884 |
| zap_cp15_cb | ngage_mister | 3 | 3 | -0.704 |
| zap_cp15_cb | ngage_timers | 77 | 69 | -0.694 |
| zap_cp15_cb | ngage_sparse_regs | 162 | 158 | -0.676 |
| zap_cp15_cb | ngage_mdi_stub | 12 | 11 | -0.636 |
| zap_cp15_cb | ngage_upp_peripherals | 117 | 91 | -0.618 |
| zap_cp15_cb | ngage_cbus_uem | 2 | 2 | -0.613 |
| ngage_upp | ngage_codeflash | 1 | 1 | -0.595 |
| ngage_upp | ngage_cflash | 24 | 24 | -0.590 |
| ngage_upp | ngage_upp_peripherals | 74 | 70 | -0.521 |
| ngage_upp | ngage_cbus_uem | 68 | 53 | -0.511 |
| zap_cp15_cb | ngage_dma_ram_mux | 37 | 34 | -0.455 |
| zap_writeback | zap_fetch_main | 2 | 2 | -0.437 |
| ngage_upp | altsyncram_6gs2 | 28 | 28 | -0.427 |
| zap_cp15_cb | ngage_upp | 30 | 23 | -0.408 |
| zap_cp15_cb | ngage_debug_monitor | 3 | 2 | -0.407 |
| zap_cp15_cb | ngage_icu | 12 | 12 | -0.278 |
| zap_cp15_cb | ngage_ddr_stream | 4 | 4 | -0.254 |
| zap_cp15_cb | ngage_sdram_arbiter | 9 | 7 | -0.144 |
| arm920_tlb | zap_dcache | 2 | 2 | -0.098 |
| zap_cp15_cb | ngage_dma_route | 2 | 2 | -0.095 |
| zap_cp15_cb | ngage_boot_regs | 2 | 2 | -0.032 |
| zap_cp15_cb | zap_wb_merger | 1 | 0 | 0.005 |
| zap_cp15_cb | ngage_diagnostics | 1 | 0 | 0.030 |
| zap_cache | arm920_cache_access | 2 | 0 | 0.040 |
| zap_cache | zap_writeback | 3 | 0 | 0.044 |

## Physical limits still open

The run reports zero unconstrained clocks, but20 unconstrained input ports/46 input paths and86 output ports/169 output paths. These board/framework IO constraints are a separate sign-off gap; this work does not silently declare them safe or relax constraints. Existing SDRAM pin-model conformance remains distinct from routed external-IO closure. A fresh Quartus fit must check all setup/hold/recovery/removal/pulse-width domains, dense packing and RAM allocation. Do not infer104 MHz closure from78 MHz tests. No CI monitoring.

## ngage1 deployment identity

CONF_STR now starts with ngage1, so MiSTer uses games/ngage1 and separate ngage1 settings. CI retains the internal Template Quartus project but packages ngage1.rbf in the ngage1-rbf artifact. Copy the existing original NEM-4 boot.rom and boot1.rom and the current C:/PMM VHD/MMC/diagnostic files to games/ngage1; reselect mounted images in the renamed core. Contents and image formats do not change. No SD-card files were moved or overwritten.

## Verification and measured cost

- Held-request fixture passes capture latency, unchanged payload, immediate
  CYC/STB withdrawal, next-owner identity and reset. Both UPP bridge modes pass
  waits, exact-once effects, captured response/error and cancellation tests.
- Mixed cached ARM CPU effects and every reported cycle/counter match4969d77
  exactly at memory waits0/3:210,644/247,890 total,1,446/1,692 body clocks. The
  direct-owner and parallel-word assertions remain active throughout these runs.
- LDM/base-writeback and mixed CPU fixtures pass at waits0/3, plus44 SWP IRQ/FIQ
  arrival/return cases. Twelve further SWP cases pass (uncached with competing
  DMA, bufferable, cached, MMU abort, read abort and write abort at both waits).
  First read is locked, lock spans the read/write gap, and exceptions terminate
  ownership. No cache capacities, MMU permission rules or SWP tags changed.
- TLB ownership/cancellation and permission/attribute oracle pass. Associative
  cache accesses/maintenance/65th-way eviction pass. Read-only-cache equivalence
  passes9,416 wide-refill and9,440 halfword-refill cycles including lookahead,
  discard, errors, lockdown and reset.
- Production ARM LCD fixture passes complete18,304-word frames, queue ordering,
  row bands, CPU interleaving, stop/restart, invalid endpoint/error and both
  transport/logical reset cases. Its measured mixed-workload frame interval is
  **128,964 vs130,685 clocks** (1.32% lower); normal/held totals149,747/149,825
  vs152,454/152,534. This is a fixture/arbitration result, not a universal pixel
  throughput claim. No transfer-beat stage was added to the fast pixel path.
- MMC bus30 cases stay132,221 clocks. The98-case UPP/DMA suite passes669,329
  vs667,186 clocks: **+2,143 /0.321%** for the new control-bus admission edge.
  Native pin lengths, all channels, selectors, blocked peers, accepted-owner
  stop/restart/reset and IRQ mask/ACK behavior pass unchanged.
- The current production ARM board fixture passes SIMIF, LCD/queue, local faults,
  diagnostics, IRQ/FIQ, SDRAM waits and DMA through shared UPP RAM/LCD/errors.
- An older external-board fixture timed out waiting for FIQ in BOTH baseline
  and candidate, at the same1163915000 ps. It started timer3 at zero without
  count/reload, which now correctly wraps after2^32 ticks. Updated its ARM
  fixture to program count/reload30, matching the already-correct production
  board program; IRQ/FIQ and invalid-register abort then pass. No timer RTL fix
  or timeout relaxation was made.
- Verilog-2001 stage test, production top elaboration,173-file/nine-QIP graph,
  formatter and exact ZAP upstream+0058 patch reproduction pass. PLL/SDC and
  diagnostics are unchanged; other-chat boot files/simulations are untouched.

Next gate is one routed Quartus78 MHz build. Pre-fit checks establish behavior
and measured simulation costs, not positive post-fit slack. In particular the
four small CPU paths and five barely-positive cache endpoints must be checked
again after placement changes. Preserve all detailed timing reports; no polling.
