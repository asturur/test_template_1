# Separate DMA programming commit from UPP response qualification

The [single-file RTL patch](patches/upp-two-edge-dma.patch) applies to
`4c02fda`, the original [two-edge UPP bridge](upp-two-edge.md). Corrected
trial `174ed5e` retains that bridge's data and response timing contract.

The initial route verified the new aperture, but the fast UPP bypass
fed unrelated single-cycle DMA logic. Seed 43's hot and cold worst
paths were −3.261 and −3.374 ns from the held address through
ICU/extra ownership, fast-lane selection, and DMA command logic to
engine 1. Seed 31337’s hot worst path was −3.664 ns through MDI and
GPIO priority, LCD stream, and DMA route to the same engine. Its
cold path went through boot scratch recognition and DMA command
valid into the SDRAM arbiter at −3.649 ns. Seed 13 also ended in DMA
engine 1 at −3.666 ns.

When the separate DMA programming port claims a packet, that claim
already overrides both slow-peripheral gates in the shared commit.
The correction uses the existing live bus authorization and the
captured DMA claim directly. Program and selector writes require the
claim. Legal START and STOP decode only the known DMA offset 0x08,
so they also imply the claim. MMIO and raw-memory priorities retain
the original shared authorization. The packet stage, protected data
registers, SDC and timing audits retain their exact implementation.

## Comparative checks

The real 104 MHz mixed fixture matches all 171,501 cycle-stamped
records, all 128 PCM sample values, and the completion at 1,202,156
clocks against `4c02fda`. The first trial's PCM startup difference
from `e9552bd` remains present. The correction adds no change to that
sample or to DMA, persistence, raw DDR, or LCD scheduling.

The authored ARM alias probe reads both ends of the ASIC ROM stub
page. It writes and reads the first and last boot scratch words and
their adjacent comm-RAM words. It also runs the 2,050 GPIO/EUART
accesses. All 326 pin-model records match at 126,242 clocks.

The DMA miter compares identical staged decoders and independent
old and new commit equations over 32,978 clocks. Its 5,658 requests
cover 5,549 rejects, four starts and three stops. There are 32
clocks with differing unused commit inputs while a physical command
is offered. Valid offers, accepts, owned drains, same-edge stop and
restart, rejected or cancelled writes, and reset behavior match.
[Qualification receipt](upp-two-edge-dma-replay.json)

## Replay

Apply the production and [fixture](patches/upp-two-edge-dma-replay.patch)
patches to the exact control and reuse the
[two-edge bridge recipe](upp-two-edge.md#reapply-and-verify).
The fixture packages the existing workload comparison runner,
the `dma_commit_miter` top and the authored GPIO/boot alias guest.
Use the same staged DMA test sources as
`tests/phone/dma_channels/run-predecode.sh` and omit its older reference
module. Both miter instances use the current staged decoder.
For the alias probe, build `fixtures/gpio-alias.S` as `gpio.hex`
with the original GPIO/EUART linker script in the retained mixed
fixture. The fixed and native workload runner compares the 15 fixed and four
native frames to the prepared `4c02fda` results.

## Corrected production fits

Preflight compares all 132 selected sources against the original
two-edge routed manifests. Only `rtl/ngage_upp.v` changes.
The QSF, physical 104 MHz PLL, SDC and debugger-off setting match.
The corrected routed results are below.
[Seed 43](https://github.com/asturur/test_template_1/actions/runs/45476439302) ·
[Seed 13](https://github.com/asturur/test_template_1/actions/runs/45476444009) ·
[Seed 31337](https://github.com/asturur/test_template_1/actions/runs/45476448187)

## Corrected routed results

The correction improved all three seeds over the first bridge trial.
Median setup moved from −3.664 to −2.645 ns. The retained control
reached −2.471 ns median and used 598 fewer median ALMs. The
two-edge constraint audit passed in every corner. All corrected
builds missed whole-core setup and the best reached −2.509 ns.

Park the bridge and correction. Public restore `e7beaf2` matches
the retained `e9552bd` production tree.
[Matched results and archived bitstreams](../../v5-alm-storage-results.md#two-edge-upp-register-bridge) ·
[Corrected fit evidence](../../evidence/v5-104-half-rate-dma-fits.json)
