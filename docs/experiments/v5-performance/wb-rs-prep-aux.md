# Prepare ARM shift counts from the W auxiliary lane

The [auxiliary-only patch](patches/wb-rs-prep-aux.patch) applies to
`3363c87`, the exact `fe145b0` board control. The trial is `a846b87`.
The [both-lane patch](patches/wb-rs-prep-both.patch) applies separately
to the same tree and has simulation evidence.

In the earlier speculative-shifter trial, seed 43 routed the auxiliary
writeback bit `w[60]` through forwarded Rs, rotation control and the
barrel into A. An eligible ARM register shift now prepares the count
through the existing held-count registers when that producer wins.
The fast count byte combines RF or held data, both M lanes and the W
primary lane. It has no W auxiliary data input. The original operand
forwarding remains available to the shifted value Rm, and a younger M
dependency still masks W, including when the M result remains pending.
The ordinary readiness checks govern preparation and acceptance.

## Incidence and workload cost

Each timed window counts accepted S-to-A instructions once. Stalled
offer clocks count each eligible cycle without acceptance, including
the first blocked edge. Producer attribution follows the registered
one-hot data grant plus the younger M dependency check. A missing M
value can leave an older W grant visible temporarily and cannot make it
the winning dependency. W primary distinguishes ALU data from its load
owner. Counts occur at issue, before architectural retirement.

| Retained control | Eligible accepted shifts | Stalled offer clocks | W auxiliary | W primary ALU | W primary load |
| --- | ---: | ---: | ---: | ---: | ---: |
| 105 windows from 15 fixed payloads | 11,434 | 194 | 0 | 0 | 0 |
| 4 native PolyCount frames | 1,562,921 | 1,140 | 0 | 108,097 | 0 |

In the native frames, RF or held values supplied 1,168,525 counts and
M primary supplied 286,299. The observer counted 26 cycles with a
younger M match masking W. All reported W counts are actual accepted
operands, including any instructions later squashed.

Both lanes were first isolated in simulation. All 15 fixed payloads
matched all windows, including Sega Rally, Asphalt and JPEG. Native
timed frame clocks rose from 57,508,371 to 57,584,777, a cost of
76,406 clocks or 0.133%. Individual frames rose 0.128–0.140%.
Native output and ordered architectural digests matched. The auxiliary-
only trial targets the routed lane and retains the native primary fast
path. [Per-window census and both variants](wb-rs-prep-replay.json)

## Qualification

The auxiliary-only differential compared accepted packets in order
against the original execute and an independent shift result and carry
oracle. It covered 1,024 counts for each of W auxiliary, W primary ALU
and W primary load. With auxiliary Rs, the shift used one preparation clock before issue.
Primary W counts accepted on the original ready edge. The
directed cases also checked younger M priority, backpressure after
preparation, flush, RRX, and W auxiliary or W load as the shifted value.

The four ARM board profiles checked warm and cold load-to-shift,
translation fault and replay, Thumb and SWP. The mixed 104 MHz pin-model
run matched all 171,496 SDRAM and board events in 1,201,547 clocks,
including 4,576 native LCD lines, PCM hash `175ee178` and one persisted MMC
sector. Both variants matched the control in these board profiles. The auxiliary-
only candidate also matched all 105 fixed windows and four native frames
cycle for cycle, with the same outputs and ordered digests.

## Reapply and verify

Run from the repository root with the pinned donor netlist and the
installed offline Jotego image.

```sh
catalog=docs/experiments/v5-performance
git apply "$catalog/patches/wb-rs-prep-replay.patch"
for kind in both aux; do
  area=scratch/v5-fit-loop/wb-rs-prep
  if test "$kind" = aux; then area="$area-aux"; fi
  mkdir -p "$area/source"
  git archive 3363c87 | tar -x -C "$area/source"
  git show 3363c87:rtl/arm9v2/arm925t_phone.v > "$area/reference.v"
  git show 3363c87:rtl/ngage_cpu.sv > "$area/ngage_cpu.sv"
  git apply --directory="$area/source" "$catalog/patches/wb-rs-prep-$kind.patch"
  python3 -B "$area/source/tools/gen_arm9v2_phone.py" --stock build/arm9v2-assoc/stock-pinned.v --check
  docker run --rm --pull=never --network none --platform linux/arm64 \
    -v "$PWD/$area:/stage" -w /stage/source --entrypoint sh jotego/simulator:arm64 \
    -ec 'sh tests/cpu/arm9v2_board/run-wb-rs.sh ../reference.v'
done
```

Prepare the [DMA predecode reference decks](dma-command-predecode.md#reapply-and-verify)
with their `--output final-replay` option. Then run the census and
matched workload replay.

```sh
both=scratch/v5-fit-loop/wb-rs-prep
aux=scratch/v5-fit-loop/wb-rs-prep-aux
for measure in fixed native; do
  python3 -B "$both/replay.py" "$measure" --control --output census
  python3 -B "$both/replay.py" "$measure"
  python3 -B "$aux/replay.py" "$measure"
done
```

For board qualification, reuse the [focused ARM fixture and command](early-shift-select.md#reapply-and-verify)
on the same source trees. For the pin model, use the matching
`prepare-mixed.py` script with two legs named after its directory, for
example `wb-rs-prep-aux-control-pin` and `wb-rs-prep-aux-pin`. Each leg
produces the same `build.sh` and `+compare_trace` procedure as the
[DMA comparison](dma-command-predecode.md#reapply-and-verify).

Preflight verified 132 selected inputs on each seed and matched the
effective QSF to the retained control. The generated CPU netlist is
the only changed fit input. The three dispatched production fits pin
`a846b87` at physical 104 MHz with DDR debugging disabled.
[Seed 43](https://github.com/asturur/test_template_1/actions/runs/45402621937) ·
[Seed 13](https://github.com/asturur/test_template_1/actions/runs/45402627650) ·
[Seed 31337](https://github.com/asturur/test_template_1/actions/runs/45402633203)

## Routed results

Retained `a846b87`. All three matched setups improved. Median setup
moved from −2.724 to −2.565 ns, median core setup TNS improved
332.935 ns, and the median fit used 602 fewer ALMs. Seed 31337's
TNS worsened to −5,660.635 ns. The worst listed hot barrel-to-A
path improved on every seed. All three builds failed setup and
passed the other four-corner checks. Seed 43 reached −2.227 ns.
The archived image remains untested on hardware. The both-lane
patch has simulation evidence, including the 0.13286% native cost.
[Matched fits and bitstream](../../v5-alm-storage-results.md#auxiliary-writeback-shift-count-preparation) ·
[Fit evidence](../../evidence/v5-104-writeback-shift-fits.json)
