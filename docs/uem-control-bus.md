# UEM control bus and the next analog input

Current checkpoint: [status.md](status.md). Inspected 2026-10-27.
This records the former ADC frontier and the next startup stage. The default
software reference remains physical-only; the separate MMU-aware reference now
checks this device sequence too. The board implementation remains a C++ simulation
model; there is no synthesized Nokia CBUS/UEM peripheral yet.

## Actual firmware sequence

The original NEM-4 ROM, with the separate reconstructed extension and boot-I/O
hypotheses, executes the following after enabling the MMU and caches:

1. Virtual routine `0x50003138` loads command `0x239` from ROM literal `0x3198`,
   configuration `0x8f`, and payload `0x6800`, then calls `0x50003650`.
2. That helper writes halfwords at virtual `0x58150420` (configuration),
   `0x58150422` (command), and `0x58150426` (data). The physical addresses are
   `0x0c150420/22/26`. The bounded model assumes immediate completion bit `0x400`.
3. The caller runs its real delay helper `0x50003078` eleven times, with argument
   `0x68`; no delay bypass is applied.
4. It requests command `0x13a` with configuration `0x0f` via `0x50003694`, waits
   for completion, then reads virtual `0x58150426`, physical `0x0c150426`.
5. That selected upper-halfword read is where the model stops. The aligned bus
   address is `0x0c150424`, byte enables `0xc`. The last completed retirement is
   the address load at virtual `0x500036c4`; the following load needs the sample.

The caller masks the returned value to ten bits and compares against `0x3dd`
and the range `5..0x5d`. These comparisons are firmware observations. They do
not establish which analog value the real phone supplies or authenticate a
particular boot-mode interpretation.

`make inspect-boot` now includes `bsi_adc_conversion`, `cbus_register_lookup`
and `cbus_transport` disassembly in `build/sim/boot-analysis.json`. Literal pools
are identified by context; their automatically decoded mnemonics are not code.

## Why this is an ADC conversion

Retained [TriX source, revision f35f8bf](https://github.com/g3gg0/TriX/tree/f35f8bfa90641e17ab4b33ba644482d303faa5cd)
provides two independently useful code paths:

- [`uem_read_adc`](https://github.com/g3gg0/TriX/blob/f35f8bfa90641e17ab4b33ba644482d303faa5cd/projects/uem_dump/uem_dump.c#L601)
  writes UEM register `0x19` with `(channel << 12) | 0x0800`, delays, then reads
  register `0x1a` and masks `0x03ff`. CBUS device 1 contributes `0x20`; direction
  flags `0x200` and `0x100` explain commands `0x239` and `0x13a`.
- [`hw_cbus_devices.c`](https://github.com/g3gg0/TriX/blob/f35f8bfa90641e17ab4b33ba644482d303faa5cd/plugins/TriX_HWemu/hw_cbus_devices.c#L33)
  labels channel 6 BSI (battery identification), write register `0x19` ADC
  control, read register `0x1a` ADC data, and write register `0x1a` watchdog.
  Its emulator receives samples from a configurable per-channel array.

Thus the observed `0x6800` sequence is consistent with a channel-6/BSI
conversion. TriX's controller addresses, configuration bits and sample defaults
are for other Nokia configurations; they are not NEM-4 hardware measurements.
The NEM-4 schematic contains UEM wiring but supplies no ADC reset/sample values.
EKA2L1 and rengage do not supply an independent sample for this cold-boot read.

## Implemented guard and next work

The bounded transport recognizes the exact observed configuration/command. Device
keys exclude direction bits. It records the selected ADC channel in result JSON
and stops with `UEM ADC channel 6 input is not supplied`. It does not return the
conversion-control payload or an earlier watchdog write as ADC data. A focused
board test writes the shared watchdog register number before starting conversion
and verifies the read still fails for the identified channel.

The next development slice is explicit simulated ADC inputs, including BSI, with
sample values recorded as assumptions. Use a channel/input configuration or
named board scenario, keep the default unknown-sample stop, and distinguish ADC
read effects from watchdog writes. First inspect the caller branches to understand
how each sample range affects startup. Then follow the next real access in HDL.
Do not add blanket zero-filled MMIO or describe a selected sample as a measured
phone value. Later CPU execution still needs MMU-aware independent validation.

## Explicit ADC input experiment now implemented

Both runners accept repeatable `--uem-adc CHANNEL=VALUE`, decimal or hexadecimal,
with channels 0..13 and samples 0..1023. The option requires boot-I/O opt-in.
Results list all values with `verified:false`; filenames separate scenarios.
Missing inputs still stop, and a configured input requires a conversion start.
The directional watchdog/ADC guard remains active. Native bridge, option parsing,
comparison mismatch, multiple-channel and unknown-channel cases are checked.

For the first experiment, channel 6 is explicitly 512 (`0x200`). It is outside
5..93 and below the shutdown threshold. The firmware returns zero, the caller
sets r4=1, and routine `0x50003200` programs the timer/interrupt registers before
unmasking IRQ. Values 5..93 instead return one and skip that setup path; values
990..1023 call `0x2f60`, write command `0x32` with zero payload and self-loop.
These are branch observations, not authenticated names for Nokia boot modes.

The exact writes now captured, without readback or generated IRQs, are:

| Physical address | Value |
| --- | --- |
| `0x0c120a04` | `2` |
| `0x0c120a18` | `0x0115b5c0` |
| `0x0c120a10` | `0x0115b5c0` |
| `0x0c120a08` | `0` |
| `0x0c120108` | `1` |

Only those word values/widths are accepted. Reads and other writes stay unknown;
a captured setup value is not a running timer or status value. The firmware wait
routine at `0x3268` polls virtual `0x58120a08`. The retained Nokia 6600 runtime
at revision `e9c6a76bd23726c4a494c0927b8f3d7b50cd343f` uses the same virtual timer
base and labels offsets as control, compare, reload and status/ack, but its
synthetic implementation is a lead rather than NEM-4 hardware ground truth.

The software/FPGA comparison first matched 36,977 events through the first timer
write. Further setup exposed a CPU [BTB collision](branch-prediction.md), now fixed
by patch 0006. Current measurements and the actual next frontier are maintained
in [status.md](status.md); do not reintroduce the erroneous read as a peripheral.

## Timer and IRQ path after the digest probes

With both explicitly derived digest fields, the software CPU reaches the word
read at virtual `0x58120a08` / physical `0x0c120a08` in routine `0x3268`.
It is not safe to return an immediate ready value just to advance: interrupts
are currently tied low, while firmware has unmasked IRQ and enabled its timer.

The original reset vector at `0x18` branches to `0x418`. For an IRQ from the
observed early ROM code at `0x5000xxxx`, the handler selects `0x3090`. That code
first reads CBUS/UEM register `0x3f`, then writes:

| Virtual address | Value | Inference |
| --- | --- | --- |
| `0x58120a18` | 0 | timer reload/control lead |
| `0x58120a10` | 0 | timer compare/control lead |
| `0x58120a08` | 1 | value later polled by startup |
| `0x58120a04` | 0 | timer control lead |
| `0x5812010c` | 1 | interrupt-controller lead |

The ordering is directly from disassembly; register meanings and hardware
clock rate remain inferred. TriX labels UEM register `0x1f` (CBUS address `0x3f`)
as power-key/charger status on another Nokia family. No NEM-4 sample is known.

A useful next hardware experiment must expose the CPU IRQ input, schedule an
explicitly assumed timer event, and let the firmware enter its actual handler.
Stop at an unknown UEM status instead of guessing it. A small independent IRQ
exception/return diagnostic and a no-event control are required before relying
on the full firmware path. FPGA cycle timing, timer divisor and IRQ latency
remain unverified; the native oracle does not yet inject an external IRQ.
The new quiescence shortcut is valid only while no asynchronous event can arrive;
revisit it before adding a timer event source.

## Staged one-shot timer/IRQ experiment

A separate experimental implementation is staged in `scratch/timer-irq-stage/`
while the previous FPGA runs use the existing board source. It is not yet copied
into the maintained `sim/` implementation. The stage exposes IRQ/FIQ on the
simulation wrapper and, when explicitly enabled, asserts an IRQ after a selected
number of CPU cycles from the observed control/reload sequence. IRQ enable and
an assumed acknowledge write gate/deassert the event. One timer tick per CPU
cycle and acknowledgement semantics are hypotheses, not measured NEM-4 timing.

The staged board test passes for a five-cycle synthetic event and retains an
unknown UEM `0x3f` data read. A separate self-contained ARM diagnostic uses a
2,000-cycle event and passes at memory latencies 0 and 3: it waits past 32 idle
branches, takes IRQ, acknowledges, executes exception return, and reaches its
terminal write. Without an event the same program reports `quiescent_loop`.
Output lives under `build/sim/runs/timer-irq-stage-delay*/`.

An isolated real-firmware stage run completed with an assumed 18,200,000-cycle
IRQ delay, ADC 6=512, and the `both` digest probe. The IRQ asserted at cycle
137,836,852; the trace enters vector `0x18`, handler `0x418`, and early handler
`0x3090`, then stops at cycle 137,837,188 on physical `0x0c150424` when the
UEM power-status value is requested. The IRQ remains pending at that stop. Its distinct result path is
`build/sim/runs/timer-irq-stage-firmware-delay18200000-latency0/result.json`.
The stage never invents the UEM power-key/charger value; it stops on that read
if the handler reaches it. This is FPGA-only: the native reference does not
inject external IRQs, and no cross-CPU agreement after IRQ is claimed.

Do not integrate staged files while another run built from the old board model
is still starting: its reported source hashes must match the actual binary.
Once previous runs finish, verify stage results, integrate carefully, rerun
focused and compatibility checks, and record source/patch provenance. The
simulator's quiescence rule must continue waiting when a scheduled event exists.

### Independent Sol review

A read-only Sol review reproduced the IRQ path, the assumed timer schedule and
cache-footprint comparison. Before integration, fix the staged idle-loop guard:
when CPSR masks IRQ but unmasks FIQ, a scheduled IRQ cannot wake the CPU; the
current test only checks whether *both* are masked. Add a focused regression for
that case. The synthetic IRQ diagnostic should assert vector entry, the IRQ
acknowledgement, restored CPSR and the exact `0x2a` terminal write at both memory
latencies, not merely any unmapped stop. Record simulation wrapper, harness and
patched CPU build provenance in addition to the board-source hashes. The
cache-aware diagnostic compares a footprint and selected device event ordering;
it does not establish architectural execution or frontier equality on its own.

The guard correction is staged separately in `scratch/timer-irq-stage-v2/` to
preserve the original real-firmware run's source provenance. Its `check.py`
passes at both memory latencies: IRQ enabled reaches the exact terminal write
with vector entry, acknowledgement, and restored CPSR; IRQ masked with FIQ
unmasked stops quiescent before the 2,000-cycle event. Results and source/image/
binary hashes are in `build/sim/timer-irq-stage-v2/`. This remains staged, not
integrated; retained compatibility-suite assertions and maintained-runner build
provenance still need to be added now that the long older run has finished.
