# DMA programming predecode at the UPP request stage

The [RTL and regression patch](patches/dma-command-predecode.patch) applies
to public parent `fc7b513`, the exact retained `c492853` production tree.
The isolated candidate is `fe145b0`.

All 70 request-stage-to-SDRAM scheduler paths in the three retained
hot top-1,000 exports pass through DMA. Seed 43's path starts at UPP
`out_sel[2]`, runs through the DMA programming error and same-edge
engine-offer cancellation logic, then through the DMA route, DMA/PCM
mux and stream address selection to scheduler `cmd_addr[23]`.
Seed 13 also starts at `out_sel[2]`. Seed 31337 starts at
`out_address[2]` and goes through DMA start decoding and readiness.
The worst slacks in this group across the two slow corners were
−2.398, −2.587 and −2.453 ns respectively.

The UPP request stage now stores the DMA register claim, packet legality,
selector and start/stop decode plus a one-hot control target when it
captures the selected CPU or local DMA packet. The channels retain
live request, commit and sampled-descriptor readiness checks. A legal
stop can withdraw an unaccepted offer on the same grant edge. A
previously accepted command remains owned through its response. The
direct-decoding configuration for external bus masters uses the same
decode. The scheduler and its existing same-edge command preview still
see the same grants and packets.

## Qualification

- Compared 32,894 clocks against the original DMA channels with a
  shared UPP request stage. The checks cover every channel, aligned
  register position and byte select, poisoned live input while a packet
  is held, canceled and uncommitted control writes, same-edge stop and
  restart, waiting response drain, partial DMA writes and reset.
- Four ARM/CPU board configurations matched cycles and ordered events
  with scalar waits of 0 and 5, with and without the line path.
- All 15 fixed payloads and four native PolyCount frames matched the
  control in cycles, outputs and ordered-event digests.
- The 104 MHz SDRAM pin-model replay matched all 171,496 records,
  including 49,043 physical pin events and 24,425 scheduler admissions.
  It completed in 1,201,547 clocks with 4,576 LCD lines, PCM hash
  `175ee178`, both UPP RAM-bank SWP tests and MMC sector persistence.
- The MMC production peer matched both transmit/receive control
  combinations with 98 cases and 669,385 clocks each. The legacy test
  used the same disposable CPU-stub port update on both legs.

[Qualification receipt](dma-command-predecode-replay.json)

## Reapply and verify

Run from the repository root using the existing offline Jotego image.

```sh
area=scratch/v5-fit-loop/dma-command-predecode
mkdir -p "$area/source"
git archive fc7b513 | tar -x -C "$area/source"
git show fc7b513:rtl/ngage_dma_channels.v > "$area/reference.v"
git apply --directory="$area/source" \
  docs/experiments/v5-performance/patches/dma-command-predecode.patch
docker run --rm --pull=never --network none --platform linux/arm64 \
  -v "$PWD/$area:/stage" -w /stage/source \
  --entrypoint sh jotego/simulator:arm64 \
  -ec 'sh tests/phone/dma_channels/run-predecode.sh ../reference.v'
```

Prepare the [execute-readiness reference decks](execute-ready.md#reapply-and-verify)
and the [local workload fixtures](fixtures.md) before replaying the fixed
and native tests. The mixed runner uses the maintained UPP DDR RAM
fixture and its hash-qualified, adapted SDRAM pin model.

```sh
git apply docs/experiments/v5-performance/patches/dma-command-predecode-replay.patch
git show fc7b513:rtl/ngage_cpu.sv > "$area/ngage_cpu.sv"
python3 -B "$area/replay.py" fixed
python3 -B "$area/replay.py" native
for leg in dma-command-predecode-control-pin dma-command-predecode-pin; do
  python3 -B "$area/prepare-mixed.py" "$leg"
  out=build/sim/v5-104-more-ram-$leg-mixed/mixed
  docker run --rm --pull=never --network none --platform linux/arm64 \
    -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 \
    -ec "sh '$out/build.sh'; '$out/obj/Vtb' +upp_stress '+compare_trace=$out/traffic.log'"
done
cmp build/sim/v5-104-more-ram-dma-command-predecode-control-pin-mixed/mixed/traffic.log \
    build/sim/v5-104-more-ram-dma-command-predecode-pin-mixed/mixed/traffic.log
```

Preflight verified the 132 selected source hashes per seed, the
effective Quartus settings and exactly the two intended changed RTL
inputs. The three production fits pin `fe145b0` at physical 104 MHz
with DDR debugging disabled.
[Seed 43](https://github.com/asturur/test_template_1/actions/runs/45378535187) ·
[Seed 13](https://github.com/asturur/test_template_1/actions/runs/45378617074) ·
[Seed 31337](https://github.com/asturur/test_template_1/actions/runs/45378624476)

## Routed results

Retained `fe145b0` for board integration. Across the three seeds, the
request-stage-to-scheduler count fell from 24, 22 and 24 to zero, zero
and two in the 100 °C top 1,000. It fell to zero on all three −40 °C
exports. The worst listed hot path in this group on seed 31337
improved 1.047 ns to −1.406 ns.

Median whole-core setup moved from −2.668 to −2.724 ns. Median core
setup TNS improved by 1,277.025 ns and the median fit used 53 fewer
ALMs. All three builds missed setup. All other four-corner checks
passed. The seed 31337 image reached −2.664 ns and remains untested on
hardware. [Matched results and bitstream](../../v5-alm-storage-results.md#dma-command-predecode-for-the-sdram-request-path) ·
[Fit evidence](../../evidence/v5-104-sdram-scheduler-fits.json)
