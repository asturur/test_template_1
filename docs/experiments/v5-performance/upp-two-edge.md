# Two-edge UPP register response

The [RTL, SDC and test patch](patches/upp-two-edge.patch) applies to public
`e7f1e31`, which has the exact `e9552bd` tree. Trial `4c02fda` gives
the held packet address, direction and select bits two full 104 MHz
periods to reach the ordinary registered UPP response data bank.
That is the 19.231 ns setup budget of 52 MHz. The actual clock remains
104 MHz, with no fixed global phase wait.

## Request and timing boundary

The stage accepts one packet at E0 and keeps its fields immutable.
The token becomes available after the first held edge, E1. Protected
data flops cannot capture before E2. The gate also applies to
unclaimed, cancelled and fast-path packets. If the device can respond, the authorized ordinary
effects and valid bit use that same edge. For an immediate access,
the registered CPU reply appears at E3 and is consumed at E4.
Adjacent successful immediate UART issues move from four to five
system clocks apart. GPIO BRAM reads already take E1 for the backing
read and keep their four-clock offer-to-reply schedule.

The shared result bank covers the GPIO/keypad, UART, timer/ICU, NOS,
SIMIF, MMC and other UPP register lanes. Shared local DMA requests
honor the same aperture. Native LCD/SDRAM transfers, separate DMA
programming and PCM ports, flash, and the physical MMC clock retain
their original timing. Lane 10 is excluded from the exception and
keeps the fast comm-RAM and ASIC ROM stub path. The two external
UPP DDR RAM requests launch on their existing edge and return only
after maturity. The device state machines advance every system clock,
including when software is not requesting a register.

The SDC uses only the held address, select and direction registers as
launches and the explicitly marked ordinary data flops as destinations.
Owner, error, valid, phase gating, peripheral effects, live data,
SRAM and the returned packet all keep their single-cycle relationships.
The [post-fit audit in the patch](patches/upp-two-edge.patch) exports the
matched cell inventory and connected setup/hold pairs, even when slack
is positive. It checks the two-period setup and original zero-period
hold edge relationships, plus single-cycle live UART, keypad, timer,
MMC, control, fast RAM and bridge-return witnesses at each native
corner. Missing or mismatched witnesses fail the audit and leave the
global corner exports available. [TimeQuest multicycle reference](https://www.intel.com/programmable/technical-pdfs/683068.pdf)

## Simulation

| Checked guest work | Control clocks | Trial clocks | Change |
| --- | ---: | ---: | ---: |
| Stock keypad, zero other memory waits | 7,302 | 7,338 | +36, 0.493% |
| Stock keypad, three other memory waits | 12,660 | 12,696 | +36, 0.284% |
| Authored GPIO/EUART, 2,050 accesses | 91,443 | 92,981 | +1,538, 1.682% |
| Mixed MMC, LCD, PCM and UPP DDR | 1,168,777 | 1,169,386 | +609, 0.0521% |

The directed test matched 636 completions and 638 owner/effect samples.
With each keypad setting, 223 even and 98 odd first-held edges showed
no protected data-register changes. It covers a warm reset, killed
and unclaimed requests, byte lanes, SRAM bypass, MMC register access,
Timer0 expiry and acknowledgment, live keys and UART, and SIMIF overlap.
The stock caller used the SHA-verified factory keypad instructions and
matched all 44 MMIO results and nine checked key events.

The mixed model matched all 1,290 accepted DMA command tuples and all
1,290 response tuples. The 1,032 MMC FIFO transfers each took one
additional clock from command to response, from four to five.
Card data, readback and persistence matched, including four HPS reads
and one write. Both raw UPP DDR banks, their SWPs and instruction
fetches, all LCD lines and the active MMC period passed. The third
PCM sample changed from `f415/05f5` to `f887/03bc`; the other 127 samples
and cadence matched, with zero underruns and overwrites.

All 15 fixed workloads and four native PolyCount frames matched their
checked outputs, architectural events, valid writes and cycle counts.
Their measured windows contain no MMIO. The four CPU contract profiles
also match. [Detailed fixture receipt](upp-two-edge-replay.json)

## Reapply and verify

```sh
area=scratch/v5-fit-loop/upp-two-edge
catalog=docs/experiments/v5-performance
mkdir -p "$area/reference" "$area/source"
git archive e7f1e31 | tar -x -C "$area/reference"
git archive e7f1e31 | tar -x -C "$area/source"
git apply --directory="$area/source" "$catalog/patches/upp-two-edge.patch"
(
  cd "$area/source"
  sh tests/phone/upp_two_edge/run.sh ../reference
  tclsh tests/phone/upp_two_edge/endpoints.tcl
)
```

Use the offline Jotego toolchain. The
[replay fixture patch](patches/upp-two-edge-replay.patch) keeps the
fixed/native runner, bounded stock keypad harness, GPIO/EUART guest
and exact mixed observer. Prepare the
[retained write-data decks](prepared-wb-write-data.md#reapply-and-verify)
and the [fixed/native input fixtures](fixtures.md). Copy the previous
three HDL observers and `e7f1e31:rtl/ngage_cpu.sv` as `$area/ngage_cpu.sv`.
Run `replay.py fixed --output candidate` and
`replay.py native --output candidate`.

For the mixed peer, copy the complete prepared `e9552bd` mixed build
inputs into `$area/mixed`. Update the paths in its build script,
substitute only `ngage_upp.v`, `ngage_upp_peripherals.v` and the archived
mixed testbench, then run with `+upp_stress +characterize_pcm` and
`+compare_trace=<output-file>`. The authored GPIO stress uses that
same peer with `+gpio_stress` and `gpio.hex` built from archived
`gpio.S` with `sim/programs/link.ld`. For the stock keypad harness,
use the retained phone files with the original caller and the
SHA-verified factory core 0x50320000–0x5041ffff slice.
Its external board fixture enables the registered response and passes
the held request's maturity token to `ngage_upp_peripherals`.
The main mixed test enables the actual production path.

## Matched production builds

The 104 MHz debugger-off fits are pinned to `4c02fda`. Preflight
checked 132 selected source hashes per seed and matched the effective
QSF. The changed fit inputs are the two UPP RTL files and `Template.sdc`.
The initial routed relationship and slack checks are below.
[Seed 43](https://github.com/asturur/test_template_1/actions/runs/45468211620) ·
[Seed 13](https://github.com/asturur/test_template_1/actions/runs/45468217182) ·
[Seed 31337](https://github.com/asturur/test_template_1/actions/runs/45468222028)

## Initial routed coverage

All three builds verified 13,378 connected held-to-data pairs at
every corner. The reports use 19.230 ns of setup relationship and
0.000 ns for hold at TimeQuest's precision. Live data, control,
fast RAM and bridge returns each retained their single-clock
relationship.

| Seed | Lowest held-data setup | Lowest held-data hold | Worst whole-core setup |
| --- | ---: | ---: | ---: |
| 43 | +3.458 ns | +0.265 ns | −3.374 ns |
| 13 | +2.003 ns | +0.418 ns | −3.666 ns |
| 31337 | +3.103 ns | +0.470 ns | −3.664 ns |

The unrelated slow-bypass authorization reached DMA programming
control in each limiting route. The [corrected trial](upp-two-edge-dma.md)
isolates that port while preserving the validated two-edge bank.

Both versions are parked. [Matched results and archived bitstreams](../../v5-alm-storage-results.md#two-edge-upp-register-bridge) ·
[Initial fit evidence](../../evidence/v5-104-half-rate-peripheral-fits.json)
