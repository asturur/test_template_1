# CPU unit benches

Run `tests/cpu/run.sh` from the repository root. These short standalone SystemVerilog benches follow the directed CPU-test style in `jtpublicfork/modules/jtframe/ver/cpu`; they use the existing `jotego/simulator:arm64` image and need no phone firmware or checkpoints. Individual benches have `sim.sh` runners.

The production ARM920T instruction/data caches and64-entry mixed-page-size I/D TLBs are the only maintained memory-system path. There is no legacy-cache build switch or expected-failure cache geometry test. Keep hardware timing verification separate from functional simulation, and never restore a checkpoint from a different executable without an explicitly audited diagnostic migration.

The suite covers:

- Four asynchronous physical-register reads against an independent write scoreboard and operand priority oracle: all40 registers, all64 forwarding-valid combinations, immediate/PC/CPSR/RAZ overrides, banked/SPSR values, write-port collisions, reset, clear and pipeline stalls.

- Separate demand and idle-housekeeping completions, exact global-stall equivalence on every CPU test cycle, waited transfers, maintenance exact-once handshakes and reset cancellation.
- CP15 control and lockdown registers, write-buffer drain, prefetch and WFI handshakes; IRQ, FIQ and masked-IRQ wake and handler ordering.
- TLB C/B attributes, domain/AP permissions, FCSE, page-table walks ordered behind buffered writes, and section/small-page external abort FSR/FAR.
- Cache tags, line storage, 64-way placement, dirty half-lines, write-back/through, no write allocation, cache disable/re-enable, MVA/index maintenance, lockdown, instruction prefetch (including unaligned MVA and nonidentity translation), instruction coherency and 65th-line eviction.
- A four-address/16-word write buffer, grouping, full/backpressure, ordered reads and fills, transient bus errors, and IRQs during refill and dirty eviction.
- CPU load widths, multiple-load cases, alignment and selected Thumb return dependencies, at several synthetic memory delays.

Dirty eviction/maintenance is still synchronous; exact ARM920 buffering, replacement randomness, prefetch fault/cancellation, persistent bus errors, interrupt races, EmbeddedICE debug wake and physical bus timing remain unverified. The ADD benchmark asserts one-cycle warmed dependent-ADD throughput under the synthetic memory model; it does not establish cycle-accurate ARM920 timing. Verilator `SYNTHESIS` lint checks syntax, not FPGA resource inference or timing.
