# N-Gage ARM and firmware bring-up

Current checkpoint and resume tasks: [status.md](status.md).

The project now has a shared CPU RTL module, ARM920T compatibility patches,
a standalone ARM64 simulator, and a bounded experimental N-Gage startup model.
Firmware reaches flash identification/configuration and early board-control
initialization under documented assumptions. An independent software ARM reference
now checks its device-access sequence; a separate LCD experiment reaches display
initialization and a full screen-clear transfer. The separate reconstructed-ROM/
boot-I/O experiment enables the MMU and caches and executes virtual startup code,
reaching a UEM ADC read. Symbian has not booted.

The CPU is not yet connected to `Template.sv`, an SDRAM controller, or video.
No FPGA synthesis, resource fit, 104 MHz timing, or hardware execution is claimed.
The stock MiSTer `sys/` files are unchanged.

## CPU source and integration boundary

`third_party/zap/` retains unmodified [upstream ZAP](https://github.com/krevanth/ZAP)
commit `fc7bd75f0e5049535f0774b3bd0ee20787f9a6fa`, its GPL-3.0-or-later license,
and an `UPSTREAM.json` manifest of retained files and hashes.

The default `ngage` variant applies `patches/zap/` to a generated build copy;
`--cpu-variant upstream` provides the unmodified comparison. Patch provenance
and the measured fixes are described in [cpu-patches.md](cpu-patches.md).

`rtl/ngage_cpu.sv` exposes clock, reset, IRQ/FIQ, and a 32-bit little-endian
Wishbone interface with byte enables, burst tags, acknowledgement, and error.
Its MMU/cache configuration selects ARMv4T Thumb compatibility, 16 KiB I/D caches,
and 32-byte lines. The caches remain ZAP's direct-mapped implementation.
The memory backend must keep requests stable until ACK/ERR and honor byte enables.

`sim/ngage_cpu_sim.sv` uses this same module and adds simulation-only retirement,
CP15, and bus-channel observations. MCR trace data is sampled when CP15 consumes
it, before the register-file read port changes.

## Running

Requirements: Python 3, Docker, Make, and host `arm-none-eabi-gcc`, `ld`, `objcopy`,
and `objdump`. ARM diagnostics target `-mcpu=arm920t`. The simulator uses the
already prepared `jotego/simulator:arm64` image with `--platform linux/arm64` and
network access disabled during builds/runs. Image identity is recorded in results.
No Quartus installation or download is part of this workflow.

```sh
make sim
make sim-compat
make sim-unmodified
make sim-upstream-patched
make sim-upstream
make sim-rtl-lint
make sim-firmware
make sim-firmware-explore
make sim-firmware-ideal-clocks
make sim-firmware-lcd
# Optional native software CPU reference:
make oracle-setup
make sim-oracle-lcd
# Separate reconstructed extension and boot-I/O experiment:
make prepare-rom-extension
make check-rom-extension
make sim-oracle-extension
make sim-firmware-extension
# Select another local ROM path:
make sim-firmware FIRMWARE=/absolute/path/to/SYM.ROM
# Reproduce the inspected tables and MMIO literal pairs (requires Capstone):
make inspect-boot
```

`make sim` runs the baseline, board-model guardrails, and compatibility probes.
`make sim-compat` requires the focused compatibility probes to pass. Both pass
with the current patched CPU. `make sim-unmodified` deliberately reports the
original CPU gaps while checking that the ordinary baseline still works.
These are focused checks, not a certification of full ARM920T compatibility.

## Diagnostics

| Diagnostic | Coverage |
| --- | --- |
| `smoke` | Memory widths, byte enables, arithmetic, branches/subroutines, ARM/Thumb switching, SWI entry/return |
| `mmu_fcse` | Nonidentity section mappings, CP15 controls, FCSE PID and distinct physical storage |
| `prefetch_fault` | Discarded speculative fetch faults and actual prefetch-abort entry/return address |
| `alignment_cases` | 32 aborts across MMU/cache configurations, load/store widths, signed accesses, fault priority and side effects |
| `mmu_fetch` | Nonidentity code mapping with both caches disabled |
| `btb_return` | A colliding trained BTB entry must not suppress a cached return or execute literal data |
| `cache_load_widths` | Cache miss/hit byte and halfword selection, sign extension, word rotation, and adjacent-load dependencies |
| `firmware_loop` | Stop a permanent masked self-loop while allowing an IRQ-enabled idle loop to time out normally |
| `flash_return` | Code in RAM resets flash then returns into ROM, with immediate and delayed acknowledgements |
| `board_fetch_guard` | The board harness stops when a fetch fault reaches architectural execution |
| `alignment_probe` | Nokia's actual c1=0x1272 request, A-bit readback, data abort and fault registers |
| `mmu_cache_disabled_probe` | Nonidentity data/FCSE mapping with caches disabled |

The ordinary diagnostics run with immediate memory and deterministic 0-3 cycle
delays. `flash_return` also uses 0-7 cycle delays. The original upstream ARM32
and Thumb tests pass on the patched source with seed 1.

## Diagnostic map and firmware models

| Address | Diagnostic device |
| --- | --- |
| `0x00000000` | ROM reset alias, padded to at least 64 KiB |
| `0x50000000` | Alias of the same ROM bytes |
| `0x80000000..0x803fffff` | 4 MiB diagnostic RAM |
| `0xf0000000..0xf000003f` | Completion/result mailbox |

This is a harness map. A write of `0x50415353` to mailbox zero means a diagnostic
passed. The mailbox is not Nokia hardware.

`make sim-firmware` preserves the original strict trace: the inspected N-Gage
4.03 ROM reaches a write of `0x7037f800` to `0x08000000` after 126 harness cycles.
Its reset alias is still an assumption, not a verified silicon reset sequence.

The opt-in startup model uses candidate physical ROM banks, RAM, narrow scratch
storage, and explicit flash/register behavior. The default experimental run now
stops on unknown clock status at `0x0c120020`. A separately labeled ideal-clock
experiment reaches an unknown halfword register read at `0x0c14f008`.
A further opt-in LCD experiment reaches a missing flash payload at `0x046c001c`.
The separate `--rom-extension --boot-io-probe` experiment gets past that boundary,
then reaches a UEM battery-identification ADC read with the MMU and caches enabled;
see [extension-reconstruction.md](extension-reconstruction.md) and
[uem-control-bus.md](uem-control-bus.md).
See [boot-model.md](boot-model.md) for assumptions and exact measured frontiers
and [software-reference.md](software-reference.md) for the software/HDL comparison.
The [reference report](references.md) distinguishes virtual maps, board evidence,
and runtime dump semantics.

Unknown data operations stop before acknowledgement. Unknown instruction reads
return bus faults so the CPU can discard speculative fetches. The board harness
stops if a prefetch abort actually reaches execution. Bus logs distinguish code
and data, record FETCH_ERROR responses, and identify the modeled device.

## Results

Ignored `build/sim/` contains result JSON, source/patch/image provenance, assembly
and simulator logs, and per-case instruction, CP15, and bus traces under `runs/`.
`results.json` is the patched acceptance report; `results-unmodified.json` is the
comparison. `upstream-ngage-results.json` records patched upstream regressions.
Firmware reports add the selected option suffixes, for example
`firmware-amd16-latency0-ideal-clocks-lcd-probe-extension-boot-io-results.json`.
`boot-analysis.json` records the inspected ROM tables and MMIO address pairs.

Cycles describe this abstract memory model. Retirement messages can represent
micro-operations, so their count is not a certified architectural instruction count.

The runner clears the result file before each invocation and rejects empty output.
It retains a host-created output inode because Docker Desktop bind mounts have
intermittently returned ENOENT after unlinking/recreating that path. This harness
issue is distinct from a CPU stop; failed runs do not count as verified results.

The latest native reference can also execute after MMU enable with the separate
`--mmu-reference` option; see [mmu-reference.md](mmu-reference.md). The ADC scenario
adds `--uem-adc 6=512`. `branch-tail.tsv` records bounded simulation-only branch
decisions for return/control-flow debugging. The cold-return failure and patch
0006 are documented in [branch-prediction.md](branch-prediction.md).
