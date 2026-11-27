# Speculative ARM register-shift selection

The [RTL, generator and regression patch](patches/early-shift-select.patch)
applies to the retained board integration commit `fe145b0`. The isolated
fit candidate is `7158a76`.

The 100 °C seed 43 critical path in `fe145b0` runs from execute
`holding` through `s_wait[2]`, the rotation select and the barrel
shifter into the A packet. The shifter now selects the forwarded Rs
byte with `direct_reg_eligible` before its readiness settles. Issue
and preparation retain the Rs interlock. Shifted data, carry,
carry preservation and RRX enter the A packet on acceptance. The
other shifted-data consumer is the saved scaled memory offset, and
the eligible data-processing instruction cannot take that path.
The held count still captures the original forwarded operand under
the existing preparation rules.

This cut separates the interlock from the shifter input. Earlier
[register-shift select predecode](historical/register-shift-shape.patch)
changed the select shape, and the [pipelined shifter](historical/pipelined-register-shift.patch)
added an execution cycle.

## Qualification

- A generated differential compared every execute output and the
  relevant A and hold state against `fe145b0` for 16,435 clocks.
  An independent MOVS oracle covered all 256 register counts for each
  of the four shift types, two operand patterns and both incoming
  carry values. It also checked immediate shift-zero semantics and
  RRX. The candidate and control speculated different counts during
  8,198 blocked clocks and matched 4,097 trusted forwarding releases.
- The directed tests also checked younger M load priority, backend
  backpressure, Thumb count preparation, flush on return and redirect
  from an older branch. Four ARM board profiles matched with scalar
  waits of zero and five, with and without native lines. The board
  program checked warm and cold Rs forwarding, same-register
  destination, translation abort and replay, Thumb and SWP.
- All 15 fixed payloads and all four native PolyCount frames matched
  cycles, results and ordered events. The physical 104 MHz pin-model
  replay matched all 171,496 events and 1,201,547 clocks, including
  SDRAM pin traffic, native LCD lines, PCM hash `175ee178` and
  MMC sector persistence.

[Qualification receipt](early-shift-select-replay.json)

## Reapply and verify

Run from the project root with the pinned donor netlist and installed
offline Jotego simulator.

```sh
area=scratch/v5-fit-loop/early-shift-select
mkdir -p "$area/source"
git archive fe145b0 | tar -x -C "$area/source"
git show fe145b0:rtl/arm9v2/arm925t_phone.v > "$area/reference.v"
git show fe145b0:rtl/ngage_cpu.sv > "$area/ngage_cpu.sv"
git apply --directory="$area/source" docs/experiments/v5-performance/patches/early-shift-select.patch
python3 -B "$area/source/tools/gen_arm9v2_phone.py" --stock build/arm9v2-assoc/stock-pinned.v --check
docker run --rm --pull=never --network none --platform linux/arm64 \
  -v "$PWD/$area:/stage" -w /stage/source --entrypoint sh jotego/simulator:arm64 \
  -ec 'sh tests/cpu/arm9v2_board/run-early-shift.sh ../reference.v'
```

Prepare the [DMA predecode reference decks](dma-command-predecode.md#reapply-and-verify).
Their replay script writes to `replay` by default. Use `--output final-replay`
on that recipe to make the results available to the shifter comparison.

```sh
git apply docs/experiments/v5-performance/patches/early-shift-select-replay.patch
python3 -B "$area/replay.py" fixed
python3 -B "$area/replay.py" native
for leg in early-shift-select-control-pin early-shift-select-pin; do
  python3 -B "$area/prepare-mixed.py" "$leg"
  out=build/sim/v5-104-more-ram-$leg-mixed/mixed
  docker run --rm --pull=never --network none --platform linux/arm64 \
    -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 \
    -ec "sh '$out/build.sh'; '$out/obj/Vtb' +upp_stress '+compare_trace=$out/traffic.log'"
done
cmp build/sim/v5-104-more-ram-early-shift-select-control-pin-mixed/mixed/traffic.log \
    build/sim/v5-104-more-ram-early-shift-select-pin-mixed/mixed/traffic.log
```

To rerun the focused ARM contract, copy the replay patch's
`board-fixture` overlay into `tests/cpu/arm9v2_board` of each
disposable source tree. Run the same command in each tree and
compare the four results.

```sh
ARM9V2_REGISTER_SHIFT_TEST=1 ARM9V2_SECTION_INDEX=xor ARM9V2_ICACHE_BYTES=16384 \
  sh tests/cpu/arm9v2_board/run-contract.sh early-shift-exact
```

The build preflight verified 132 selected source hashes for each seed and
the same effective Quartus settings as the control. The generated CPU
netlist is the only changed synthesis input. The three production fits
pin `7158a76` at physical 104 MHz with DDR debugging disabled.
[Seed 43](https://github.com/asturur/test_template_1/actions/runs/45392744698) ·
[Seed 13](https://github.com/asturur/test_template_1/actions/runs/45392752108) ·
[Seed 31337](https://github.com/asturur/test_template_1/actions/runs/45392904798)

## Routed results

Parked the standalone patch. The sampled 100 °C wait-to-rotate-to-A
paths went from 8, 7 and 0 to zero on all three seeds. A forwarded
Rs-to-rotate path became the limiting setup route on seed 43.
Median setup moved from −2.724 to −2.836 ns, and median core setup
TNS moved from −4,483.219 to −5,020.147 ns. The median fit used
71 fewer ALMs. Seed 13 reached −2.628 ns, the best candidate fit.
All three failed setup and passed the other four-corner checks.
Public forward revert `3363c87` restores the exact `fe145b0` board
control. [Matched fits and archived RBF](../../v5-alm-storage-results.md#speculative-arm-shifter-selection) ·
[Fit evidence](../../evidence/v5-104-early-shift-fits.json)
