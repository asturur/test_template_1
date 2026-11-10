# Provisional N-Gage startup model

Current checkpoint and resume tasks: [status.md](status.md).
The original strict/clock/LCD stages below remain useful baselines. The furthest
opt-in run is now the [reconstructed extension](extension-reconstruction.md),
which enables the MMU and caches and reaches the [UEM ADC](uem-control-bus.md).

This opt-in experiment follows the original N-Gage / NEM-4 4.03 `SYM.ROM`, SHA-256
`afc1cc8b693f2b68d23ca203aa4d4eb4266baad4ab718f013a33b915d39574ef`.
The runner rejects other images for this model because the bank-table offsets
are specific to the inspected firmware. Nokia firmware remains a local input.

## Running

```sh
make sim-firmware                      # Original strict trace
make sim-firmware-explore              # Provisional amd16 physical model
make sim-firmware-ideal-clocks         # Separate clock-handshake hypothesis
make sim-firmware-lcd                  # Separate LCD/reset/ready experiment
python3 sim/run.py --firmware firmware/SYM.ROM --boot-profile amd16 --latency 3
python3 sim/run.py --firmware firmware/SYM.ROM --boot-profile amd16 --latency 3 --ideal-clocks
make inspect-boot                      # Static tables/disassembly/address pairs
```

`FIRMWARE=/absolute/path/to/SYM.ROM` selects a local image. `BOOT_PROFILE=intel8`
or `amd8` selects other exploratory CS1 identities. `--max-cycles` sets the
execution limit; the exploratory default is two million harness cycles.
No actual phone speed is established by these cycle counts.

## Memory and flash assumptions

Startup writes at ROM offsets `0xb6c..0xbc0` identify six word locations at
`0x08000000/04/08/10/14/18` and a halfword at `0x0c150004`. These are modeled as
latches; unwritten bits remain unknown. Later code uses `0x08000010 + 4*chip`
while configuring flash timing. This supports a memory-interface interpretation,
but no UPP_WD2 register manual has confirmed all field meanings or reset values.

The first flash probe at `0x95c` selects one of three memory tables at `0xb38`.
Profiles name the CS1 hypothesis and the RAM size encoded by its selected table:

| Profile | CS1 manufacturer/device | Probe result | Table | Simulated RAM |
| --- | --- | --- | --- | --- |
| `intel8` | `0x0089 / 0x8872` | 1 | `0x744` | `0x0a000000`, 8 MiB |
| `amd8` | `0x0001 / 0x22d1` | 1 | `0x744` | `0x0a000000`, 8 MiB |
| `amd16` | `0x0001 / 0x257e` | 2 | `0x830` | `0x0a000000`, 16 MiB |

The `0x638` table is the probe-result-zero fallback. Table type (`flags & 31`)
1 is treated as ROM and type 2 as RAM, matching the RAM discovery routine's
selection at `0x2444`. Type 3 windows are not automatically writable memory.

Assigning consecutive logical `SYM.ROM` bytes to type 1 banks in table order
remains an unverified physical-layout hypothesis. Missing payload reads stop.
Ideal RAM starts at zero and obeys byte enables; its power-on state is not measured.
Virtual `0x50000000`/`0x80000000` aliases and the diagnostic mailbox are not added
to this physical model.

There are independent flash states at `0`, `0x02000000`, and `0x04000000`.
CS0/CS2 use an AMD Am29N643/Am29BDS643G candidate from the NEM-4 schematic,
with ID words `0001,227e,2202,2200`. CS1 remains the selected profile hypothesis.
The selected handshake options (`0x43` for CS0/CS2, `0x42` for amd16 CS1) are
explicit model assumptions, not values read from the user's device.
CS1's extended `2502/2500` words follow the firmware's matching decoder branch;
its installed chip identity is unverified.

AMD's [Am29BDS643G datasheet](https://datasheet4u.com/pdf/564541/AM29BDS643G.pdf),
sections on autoselect and configuration plus Tables 8/10, supplies the CS0/CS2
identification protocol and the AA/55/C0 burst-configuration sequence. Burst
settings are recorded, but electrical timing is abstract. Intel/AMD identify
commands, reset, and that AMD configuration operation are modeled. Unknown
identification fields, commands, programming, and erasing stop; no flash array
bytes are changed by an accepted command.

## Executable scratch area and fetch faults

The ROM routine at `0x57f0` copies 0x6c bytes from `0x5880` to `0x0c004748`,
then 0x30 bytes from `0x58f4` to `0x0c0047b4`. The code performs flash-identification
operations and returns to ROM. Later routines overwrite part of this same area
with flash-configuration code.

`0x0c004748..0x0c0047fb` is modeled as scratch storage (45 words, including
firmware panic-report words at `0x0c0047f0/f4/f8`); writes initialize
individual bytes, and unknown reads remain unknown. Its actual backing/extent
is unverified. The surrounding device window is not converted to generic RAM.

Sequential speculative fetches past this area receive bus errors. They can be
discarded after a branch; a real instruction abort stops the board trace. The
CPU [fetch-ordering fix](cpu-patches.md) also prevents a return fetch from racing
an older flash-reset store. Independent tests cover both behaviors.

## Optional clock experiment

The default model accepts observed control writes but stops on the unknown
status read at `0x0c120020`. `--ideal-clocks` separately hypothesizes immediate
completion of only these observed sequences:

| Preconditions | Assumed status |
| --- | --- |
| `0x0c120004 = 12` | `0x0c120020 = 0x04000000` |
| `0x0c120004 = 0x27`, `0x0c120008 = 1` | `0x0c120020 = 0x08000000` |
| `0x0c149000 = 0x2210` | Readback `0x2211` (assumed lock bit) |
| `0x0c120004 = 3`, prior PLL write `0x2210` | `0x0c120020 = 0x08000000` |

Unwritten controls and unrecognized combinations stop. Additional exact write
locations `0x0c120014/18/34/38` retain observed values as latches. This is a
firmware-path experiment, not a measured PLL/clock controller or a 104 MHz claim.
Results explicitly record `ideal_clocks`, per-chip identities/configuration,
RAM/bank mapping, initialized scratch bytes, and written registers, with hardware
verification flags false.

## Baseline measured frontiers

| Patched CPU configuration | Harness cycles | First unknown operation |
| --- | --- | --- |
| Strict diagnostic aliases | 126 | Write to `0x08000000` |
| amd16, immediate memory | 32,068 | Word read of `0x0c120020` |
| amd16, 0-3 cycle delays | 41,858 | Same clock-status read |
| amd16 + ideal clocks, immediate memory | 37,492 | Halfword read of `0x0c14f008` |
| amd16 + ideal clocks, 0-3 cycle delays | 48,923 | Same halfword read |

The ideal-clock experiment reaches ROM helper `0x66b8`, which disables interrupts,
reads a halfword, ORs requested bits, writes it back, and restores CPSR. At this
point the supplied register value is unknown; it is not replaced with zero.
These baseline runs have not enabled the MMU; the separate extension/boot-I/O
experiment does. Symbian is not running.

The inspector records three M-bit-dependent physical/virtual literal selections
used by the startup routine at `0x617c`:

| Physical | Virtual | Operation requested by caller |
| --- | --- | --- |
| `0x0c14f008` | `0x5814f008` | Set halfword bit mask `0x0002` |
| `0x0c15020e` | `0x5815020e` | Set halfword bit mask `0x0010` |
| `0x0c14f010` | `0x5814f010` | Set halfword bit mask `0x0050` |

These are direct firmware evidence for these aliases. They do not establish all
register meanings or reset values. The separate LCD experiment below extends
these baseline runs with explicit assumptions; it does not change their strict unknown-access boundaries.


## Optional LCD probe

`--lcd-probe` requires the ideal-clock experiment and adds only the exact setup
halfwords used by the ROM, each with an explicit assumed zero reset:
`0x0c14f008`, `0x0c15020e`, and `0x0c14f010`. Neighboring halfwords remain unknown.
Two write-only-before-initialization halfword latches at `0x0c150204` and
`0x0c150202` follow the reset-toggle routines at `0x630c` and `0x62d0`.
Their electrical meanings are inferred from the surrounding display code.

The observed physical LCD interface has word accesses at `0x0c121200` (transfer
header), `0x0c121204` (control/status), and `0x0c121208` (data). Only the header
families appearing in the inspected routines are accepted. This probe assumes an
immediate sink: control 1 enables transfers after control 2 resets header state;
status bit 2 is ready, and header `0x49200000` completes with bit 30 set. These
bit interpretations follow firmware polling, not a hardware programming manual.
Data reads, unknown headers/control values, other widths, and adjacent addresses
still stop. Raw data writes are counted; no pixel-format decoder is invented.
Reports mark reset values, timing, and pixel format as unverified.

The software reference now executes the complete LCD setup and screen clear,
including the original busy-wait delays, then stops at `0x046c001c`, where the
current physical-bank hypothesis has no remaining dump bytes. Immediate-memory
HDL reaches the same read after 111,002,311 harness cycles; delayed memory reaches
it after 154,357,177 cycles. All 36,905 modeled device accesses match the software
CPU in both cases. These are exploratory results under both clock and LCD
assumptions, not a boot of Symbian.

`--compact-trace` keeps modeled I/O, fetch faults, CP15 events, and the stopping
access while omitting ordinary memory/instruction text and duplicate RTL console
messages. It changes logging only. Use a larger cycle limit for the original
LCD delays (`make sim-firmware-lcd` supplies 180 million cycles).
See [software-reference.md](software-reference.md) for the independent software
CPU, matching rules, captured LCD transfer, and next flash-layout question.


## Capacity versus dump placement

The user confirmed three 64-Mbit flash chips, consistent with the NEM-4 schematic:
24 MiB physical capacity. The supplied logical image is 17.75 MiB, while type-1
spans in selected table `0x830` total 19.9375 MiB. Their table order is not raw
chip order. The current concatenation therefore needs verification; the stop at
`0x046c001c` cannot simply be labeled the 3.4-MB user-storage area.
See [flash-layout.md](flash-layout.md) for the exact spans, capacity arithmetic,
and a type-3 window extending beyond the assumed second chip's 8-MiB extent.
No model behavior changed during this audit.

## Reconstructed extension and later boot I/O

`--rom-extension` adds only a validated, separately generated tail for the selected
type-1 banks. It preserves recovered ROOT bytes, rebuilds missing directory/header
metadata, and explicitly labels bounded erased padding. `--boot-io-probe` adds
narrow reset hypotheses, initialized software-shadow storage, and a bounded CBUS
transport. Neither option is enabled by the baseline commands above.

With both options, firmware enables the MMU/caches (`c1=0x127f`) and reaches a UEM
ADC channel-6 read at physical halfword `0x0c150426`. No sample is supplied by
default. Read/write meanings of UEM register `0x1a` differ, so a watchdog write
cannot satisfy the ADC read. Details, measured cycles, comparison scope and next
work are in [extension-reconstruction.md](extension-reconstruction.md) and
[uem-control-bus.md](uem-control-bus.md).
