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

`rtl/arm/` is the CPU: [upstream ZAP](https://github.com/krevanth/ZAP) commit
`fc7bd75f0e5049535f0774b3bd0ee20787f9a6fa` with `patches/zap/` applied, its
GPL-3.0-or-later license, and an `UPSTREAM.json` pin (hashes of the pristine
upstream files). Quartus and all simulators compile `rtl/arm/` directly. The
original upstream is not kept in the repository; `patches/zap/verify.sh` and
`--cpu-variant upstream` download it to `scratch/zap-upstream/` on demand. Patch provenance
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

For milestone 7.5's resumable **actual HDL phone** run, from the project root:

```sh
python3 tests/phone/hardware_boot/run-logo.py --name my-logo-run --cycles 700000000
# Continue only a checkpoint from the exact same executable/source/image lineage:
python3 tests/phone/hardware_boot/run-logo.py --name my-logo-extension --cycles 1000000000 \
  --restore build/sim/runs/my-logo-run/checkpoint-700000000
```

This runner builds/caches a `--savable` Verilator executable inside the existing
`jotego/simulator:arm64` image. It extends the maintained hardware-boot testbench,
with C++ driving clocks, backing-memory testbench arrays, observation and
serialization; phone CPU/peripherals are HDL. The fast path currently uses
100 MHz clocking and the bounded harness's modeled memory response delays,
preloads the stock core/extension and a disposable C: copy, starts PMM erased,
and selects phone video with no SIM/no ATR. It does not simulate HPS Linux,
mount/flush, vendor PLL or physical SDRAM. Keep `run-real-sdram.sh` as the
separate actual-controller conformance regression. This is a headless simulator
using the Jotego toolchain image, not an interactive JTFRAME video window.

Run names must be new. `--cycles` is a 64-bit absolute terminal cycle. The driver
uses serialized 64-bit host ticks to extend the HDL observation counter across
its 32-bit rollover; device counters retain their actual HDL widths. Manifests record source/executable,
container and input hashes, profile and restore ancestry. CPU/host checkpoint
pairs include the testbench memories and HDL display state; billion-cycle pairs
are retained. Terminal framebuffer and sampled scanout PNGs are written under
`build/sim/screens/<name>/`; `result.json` contains validity/display-on flags
and hashes. A generated PNG does not by itself establish a logo or a valid frame.
The five-million-cycle save/restore check matched an uninterrupted run byte for
byte for both checkpoint files. The 64-bit driver upgrade also matches the old
driver byte for byte after a 5M -> 6M continuation; a separate synthetic
observer-counter fixture passed rollover and restore above 2^32 (not a firmware
boot claim). `--driver-upgrade` permits this reviewed observer-only upgrade with
unchanged HDL serialization; use normal strict restores once upgraded. Do not import historical C++-peripheral research
checkpoints into this executable. See newest status for actual boot progress.

Storage: old checkpoints may now be stored as paired `.cpu.gz`/`.host.gz`
with `<prefix>.archive.json` hashes. Pass the original prefix to the RTL runner;
it verifies and expands the pair into a temporary run directory, restores, then
removes that temporary copy. A plain-versus-archived continuation produced
byte-identical CPU and host states. Older C++ tools can first use
`gzip -dk <prefix>.cpu.gz <prefix>.host.gz` (no overwrite).

The runner retains a bounded live `run.log` and a small `progress.log`; complete
console output is losslessly streamed to `run.log.gz`. Large compiler `.gch`
caches are discarded after building. Cleanup inventories and archive hashes are
under `scratch/cleanup-2026-11-06/` and `scratch/cleanup-deep-2026-11-06/`.
The unused SDK extraction is archived as `build/sdk-extract.tar.gz`; restore it
with `tar -xzf build/sdk-extract.tar.gz -C build` if a research tool needs it.

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

### Reset cause for logo runs

`run-logo.py --powerup normal` (default) performs a power-key reset-profile boot. `--powerup alarm` selects the historical UEM 3F=1 profile. The power-key profile uses 3F=2, clearing bit 1 after the modeled key release; these are staged software-reference assumptions. The manifest records the profile and restore rejects a different reset cause, including diagnostic forks. Legacy checkpoint manifests imply alarm; source/build compatibility checks still apply. Never resume an alarm state as normal or patch the boot-reason RAM. The bounded historical comparison harness explicitly keeps its alarm profile.

### Continuing a frozen build after workspace edits

Edits to HDL do not change an already running executable. To resume the exact checkpoint model while the workspace has newer HDL, explicitly select the saved executable:

```sh
python3 tests/phone/hardware_boot/run-logo.py --name frozen-followup --cycles 13000000000 --powerup normal --use-saved-build --restore build/sim/runs/logo-normal-12000m/checkpoint-12000000000
```

Use only a checkpoint that actually exists. This option requires the cached executable and container to match their saved hashes, preserves the original compiled-source manifest, checks reset profile/inputs, and forbids model-upgrade flags. It never compiles current HDL or applies fixes. Default restore checks remain strict; use a separate cold boot to validate HDL changes. The original normal-logo compiled sources were also archived under `scratch/logo-bringup/frozen-normal-12b/`.

### Bounded LCD diagnostics in new logo builds

The HDL logo harness logs command/header/parameter writes after the initial clear, suppresses bulk `8924` pixel-port writes, and samples the first 32 `LCD_UNKNOWN` events with header/opcode/data/PC. `progress.log` retains those lines; the sticky unsupported flag and latest context remain in model state after console sampling stops. `tests/phone/lcd_display/startup_commands.hex` replays the first 125 address/data writes from the original normal cold boot. A static direct-write counter cannot establish absence of DMA updates: inspect a checkpoint's framebuffer or capture actual DMA events. A zero-cycle saved-build observation at 7B verified the long run was still at the Nokia logo.

### Native scanout after the HDMI active-area correction

New-build phone `scanout.png` is 176x208 and samples actual CE+DE-qualified video. The phone remains centered in a larger 400x262 timing raster, with black around it for analog output; those blanking intervals are excluded from the HDMI source image and PNG. Diagnostic mode remains 320x240. Older frozen-build screenshots retain their historical 320x240 bordered format. `tests/phone/lcd_display/run-native.sh` verifies coordinate patterns, DE/sync counts, analog black padding and an explicitly labeled display-only Nokia-frame replay.
