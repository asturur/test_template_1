# Split GPIO and EUART read data in UPP lane 13

The [exact production patch](patches/peripheral-lane13.patch) applies to
public control `e9552bd`. Trial `e02c236` leaves the analog raster,
peripheral cadences and request/response edges in place.

The two worst 100 °C routes on control seeds 43 and 13 end at UPP
`local_results[13]`. Seed 43 launches from a captured UPP address bit
through the NOS timer's decode and the shared unkeyed data mux before
reaching the GPIO/keypad response. Seed 13 launches from a captured
address bit through EUART1 register selection. The matched top-1,000
hot exports contain 15, seven and zero paths ending at lane 13.

## Why the timing paths run at 104 MHz

`Template.sv` supplies the physical 104 MHz `clk_sys` clock to the
phone core, board and UPP. The packet, EUART1, GPIO storage, keypad
and peripheral response registers all use that clock. Keypad logic
samples pin state and updates its edge detector each system clock.
EUART1 models parallel byte streams. Its FIFO head counters allow RAM
settling on the same clock. This model does not generate baud-rate
serial pins or run its software-facing interface at a divided clock.

The directed trace uses the production registered bridge, packet stage
and peripheral responder, with the selected board error registered as
in the top level. It exercised adjacent transactions while the master
held CYC high. E0 is the edge that captures the offered request.

| Operation | Request held | Data sample and authorized effects | CPU response visible | Consumption |
| --- | --- | --- | --- | --- |
| Immediate EUART config/status or GPIO write | E0 | E1 | E2 | E3 |
| GPIO storage read | E0 | E2, after the BRAM sampled the address at E1 | E3 | E4 |
| Immediate rejected EUART access | E0 | E1 | E3, after the board error register | E4 |

An immediately adjacent request can capture on the next edge after
consumption. Both odd and even capture/sample phases occur across
immediate reads, GPIO reads and legal stalls. Dividing the device
interface clock by two or three would move some of those sample
edges and would require a different handshake. Even a slower external
protocol or internal enable still leaves a one-system-clock path to
the software-visible response.

## The data path change

GPIO and keypad reads in lane 13 apply the existing keypad replacement
bits directly to GPIO data. The keypad has one state machine. The NOS
and GPIO-loopback owners still apply the same overlay to their original
selected base words. Those higher-priority claims are already false
when lane 13 is selected. This removes an unrelated source-selection
path into the GPIO lane without changing how ownership is chosen.

The request stage captures EUART1's seven static register word-select
bits alongside the selected CPU or local-DMA address. The byte lanes,
request and direction still qualify the operation at the peripheral.
Read data comes from live UART registers and FIFO state at the
original response edge, including the UART contribution to SIMIF's
shared status word. Claim, priority, valid-lane checks, busy, side
effects and error capture retain their original behavior. Legacy
immediate masters still decode their live address.

## Checked work

Two directed configurations matched 614 registered replies and 4,070
cycle-stamped trace records. Tests covered every UART word and mask in
both directions, byte aliases, invalid accesses, held back-to-back
requests, coincident RX status sampling, SIMIF backpressure and
combined status, live keypad sampling, shared NOS and loopback
overlays, TX saturation/cancellation, response hold and warm reset.
The standalone EUART, keypad, board keypad and request-stage tests
also passed.

The 15 fixed workloads matched all 105 windows and their negative
output checks. All four native PolyCount frames matched, including
guest outputs and architectural and valid-write digests. Four ARM9v2
contract profiles matched with the half-writeback fixture enabled.
The 104 MHz mixed replay matched 171,496 pin-model trace records over
1,201,547 clocks, with LCD, PCM, MMC persistence and both UPP DDR
banks active. No measured workload or peripheral access added a wait.
The ARM9v2 contract models the upstream bus peer. The pin-model
replay supplies the full board coverage. [Qualification receipt](peripheral-lane13-replay.json)

## Reapply and verify

In the repository root, with the existing ARM GNU tools and offline
Jotego image, prepare the exact snapshots and run the directed test.

```sh
area=scratch/v5-fit-loop/peripheral-lane13
catalog=docs/experiments/v5-performance
mkdir -p "$area/reference" "$area/source"
git archive e9552bd | tar -x -C "$area/reference"
git archive e9552bd | tar -x -C "$area/source"
git apply --directory="$area/source" "$catalog/patches/peripheral-lane13.patch"
absolute_area="$PWD/$area"
docker run --rm --pull=never --network none --platform linux/arm64 \
  -v "$absolute_area:/bench" -w /bench/source --entrypoint sh \
  jotego/simulator:arm64 tests/phone/upp_lane13/run.sh ../reference
```

For the original fixed and native comparisons, first make the
[prepared write-data](prepared-wb-write-data.md#reapply-and-verify)
`candidate` receipts and pin logs. Apply the
[replay helper patch](patches/peripheral-lane13-replay.patch) and copy
the three unchanged observers from the previous fixture.

```sh
git apply "$catalog/patches/peripheral-lane13-replay.patch"
git show e9552bd:rtl/ngage_cpu.sv > "$area/ngage_cpu.sv"
cp scratch/v5-fit-loop/prepared-wb-write-data/{architectural_trace.vh,wb-write-trace.vh,sdram-pin-trace.vh} "$area"/
python3 -B "$area/replay.py" fixed --output candidate
python3 -B "$area/replay.py" native --output candidate
```

For the pin-model replay, run the
[DMA predecode pin replay commands](dma-command-predecode.md#reapply-and-verify)
with both `peripheral-lane13-control-pin` and `peripheral-lane13-pin`
and this experiment's `area`. For both sources, run the normal board
contract with `ARM9V2_ASSOC_WAYS=2`, `ARM9V2_SECTION_INDEX=xor`,
`ARM9V2_ICACHE_BYTES=16384`, `ARM9V2_REGISTER_SHIFT_TEST=1` and
`ARM9V2_HALF_WRITEBACK=1`.

The physical 104 MHz production fits pin `e02c236` with DDR debugging
disabled. Preflight matched all 132 selected source hashes per seed,
with only the four intended phone RTL files changing, and matched
the effective QSF and seed.
[Seed 43](https://github.com/asturur/test_template_1/actions/runs/45444020154) ·
[Seed 13](https://github.com/asturur/test_template_1/actions/runs/45444025138) ·
[Seed 31337](https://github.com/asturur/test_template_1/actions/runs/45444030096)

## Routed results

Park `e02c236` as a standalone timing change. The 100 °C lane 13
endpoint counts fell from 15, seven and zero to three, zero and zero.
The worst listed lane 13 path on seed 43 gained 0.850 ns. Seed 13's
lane 13 is outside the candidate export. Median whole-core setup
worsened by 0.052 ns. Median core setup TNS improved by 319.078 ns,
and the median fit used 459 more ALMs. Every candidate missed setup
and passed the other checks at all four corners. The best candidate
reached −2.404 ns, compared with the best control's −2.061 ns.

The four checked ARM9v2 contract profiles use the half-writeback
fixture. Both initial default runs hit the same dirty-clean assertion
before that fixture was enabled. Forward revert `e7f1e31` restores the
exact `e9552bd` tree. [Matched fits and archived bitstream](../../v5-alm-storage-results.md#peripheral-gpio-and-euart-read-response) ·
[Routed evidence](../../evidence/v5-104-peripheral-read-fits.json)
