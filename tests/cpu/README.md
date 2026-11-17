# CPU unit benches

Run `tests/cpu/run.sh` from the repository root. These short standalone SystemVerilog benches follow the directed CPU-test style in `jtpublicfork/modules/jtframe/ver/cpu`; they use the existing `jotego/simulator:arm64` image and need no phone firmware or checkpoints. Individual benches have `sim.sh` runners.

The production ARM920T instruction/data caches and64-entry mixed-page-size I/D TLBs are the only maintained memory-system path. There is no legacy-cache build switch or expected-failure cache geometry test. Keep hardware timing verification separate from functional simulation, and never restore a checkpoint from a different executable without an explicitly audited diagnostic migration.

The suite covers:

- [`cpu_frontend_delivery/`](cpu_frontend_delivery/) — isolated Step5A registered-target handoff; exact4G controls, original matrix/transpose/ThumbJPEG,23target cases and full frontend/cache attribution.
- [`cpu_store_second/`](cpu_store_second/) — isolated Step4G producer-owned second-store preparation; original transpose4041→3625, matrix52125/store71 unchanged; two pending bits and focused banked/fault/held-return qualification.
- [Isolated late store data](cpu_store_late/README.md): fixed corrected4E,
  early private address with exact producer data, actual write/retirement order,
  transpose/matrix/store measurements and fault/permission/MMIO checks.

- [Isolated CPU issue recovery](cpu_issue_recovery/README.md): fixed 4D,
  PC/occurrence stage alignment, saved redirect-owner handoff, transpose/matrix
  gains, FCSE carry and focused fetch/exception/held-packet checks.

- [Isolated load-pair overlap](cpu_load_overlap/README.md): fixed 4C, original
  ARM class ownership, actual early private RAM work, ordered completions/register
  writes/dependent stores, paired-loop/transpose gains and targeted safety checks.

- [Isolated load delivery](cpu_load_delivery/README.md): fixed 4B comparison,
  registered waiting-P2 probe scheduling, per-read cycle attribution, stale
  same-address/older-fault checks and preserved one-clock store stream.

- [Isolated spare store credit](cpu_store_credit/README.md): fixed 4A control,
  full CPU issue/accept/write gap histograms, simultaneous return/allocation,
  peak fault/IRQ, probed-load/full-pressure/reset cases and original transpose.

- [Isolated CPU store overlap](cpu_store_overlap/README.md): real ARM instruction
  admission with two resident-store credits, actual RAM writes, precise older
  abort/IRQ suppression, held requests, following loads and matched transpose.

- [DSP multiply mapping](multiply_mapping/README.md): independent signed/unsigned
  integer products/accumulation, low/high ownership, flags, stalls, failed
  conditions and held cancellation, compared with the frozen pre-change schedule.

- [Block transfers](block_transfer/README.md): 786896decoded-semantics sequences, precise per-beat aborts, first/final fusion, condition/hold/interrupt/cancellation coverage.

- Four asynchronous physical-register reads against an independent write scoreboard and operand priority oracle: all40 registers, all64 forwarding-valid combinations, immediate/PC/CPSR/RAZ overrides, banked/SPSR values, write-port collisions, reset, clear and pipeline stalls.

- Separate demand and idle-housekeeping completions, exact global-stall equivalence on every CPU test cycle, waited transfers, maintenance exact-once handshakes and reset cancellation.
- CP15 control and lockdown registers, write-buffer drain, prefetch and WFI handshakes; IRQ, FIQ and masked-IRQ wake and handler ordering.
- TLB C/B attributes, domain/AP permissions, FCSE, page-table walks ordered behind buffered writes, and section/small-page external abort FSR/FAR.
- Dual-direction permission reuse through real descriptor publication (3,092 hot checks), exact walk-fault ownership and idle ACKs; repeated CPU LDRT/read, denied STRT/write and read recovery with FSR/FAR and unchanged data.
- Absent-line buffered stores: real-cache 44-request/39-packet ordering and mask/refill/dirty/queue/error/reset checks; CPU warmed-record privilege denial and resident refill recovery.
- [Admission-edge pre-read](cache_admit_probe/README.md): 256 shortened resident reads, isolated full-line/way guards, exactly-once replies, fresh masked-store bytes, checked faults/translation waits, maintenance and reset.
- Indexed resident reads/stores through existing RAM, exact owned selectors and fresh dirty halves: two-result capacity/aliases, every mask/word/segment, ordered clean/writeback, revocation/reset and deliberate stale-dirty rejection.
- Cache tags, line storage, 64-way placement, dirty half-lines, write-back/through, no write allocation, cache disable/re-enable, MVA/index maintenance, lockdown, instruction prefetch (including unaligned MVA and nonidentity translation), instruction coherency and 65th-line eviction.
- A four-address/16-word write buffer, grouping, full/backpressure, ordered reads and fills, transient bus errors, and IRQs during refill and dirty eviction.
- CPU load widths, multiple-load cases, alignment and selected Thumb return dependencies, at several synthetic memory delays.

Dirty eviction/maintenance is still synchronous; exact ARM920 buffering, replacement randomness, prefetch fault/cancellation, persistent bus errors, interrupt races, EmbeddedICE debug wake and physical bus timing remain unverified. The ADD benchmark asserts one-cycle warmed dependent-ADD throughput under the synthetic memory model; it does not establish cycle-accurate ARM920 timing. Verilator `SYNTHESIS` lint checks syntax, not FPGA resource inference or timing.


## Donor import benchmarks

The separate [benchmark harness](donor_import/README.md) freezes the user-pinned
ce8d2c9 and3f5e8ae commits and current sources without changing this checkout.
It assembles one shared 15-kernel ARM batch for all variants. All 32 host
checks and the first 480 HDL observations pass, with exact deterministic repeats
and matched controller negative controls. See the [measured results](../../docs/cpu-donor-baseline-results.md). This is partial phase00/01 coverage of the
[import plan](../../docs/cpu-donor-import-plan.md), not a CPU import or a replacement
for the correctness suite above. Its synthetic memory model does not establish
physical SDRAM performance.

- [Resident-store streaming baseline](../../docs/cache-resident-stream-baseline.md): five 256-store continuous-offer streams, actual RAM commits, dirty-half/writeback checks, exact repeat and wrong-byte control. Run `sh tests/cpu/cache_resident_stream/sim.sh build/sim/resident-store-stream-rerun` with a new output path.

- [Resident-store qualification](../../docs/cache-resident-store-pipeline-qualification.md): isolated corrected overlay; lifecycle/probe/line-peer tests, real-adapter pending lock, reused regressions and fresh five-stream A/B commands.

- [Registered probe boundary](../../docs/cache-probe-admission-retime.md): explicit corrected-3A/control and retimed adapter/cache overlays, stage/identity checker, five store streams and matched original CPU six-kernel/JPEG workloads.
