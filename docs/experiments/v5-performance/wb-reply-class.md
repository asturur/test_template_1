# Separate SDRAM write completions

The [design patch](patches/wb-reply-class.patch) applies to `11c4a0c`,
the retained `e9552bd` production tree. The SDRAM stream issues separate
read and write completion signals on the existing edges. The SDRAM
arbiter and board memory route carry both to the CPU under the existing
owner and cancellation rules. The instruction cache sees the common
rail, which also carries slow-bus replies and native refill beats. The
data cache and Wishbone end-of-burst arbitration use both rails. ERR
keeps its existing route. The default module interfaces use one ACK.
The cache sizes, production clocks and constraints stay as before.

## What the fit should measure

| Seed | Worst merger-address path, slow 100 °C | Worst merger-address path, slow −40 °C |
| ---: | --- | --- |
| 7 | −2.602 ns, SDRAM scheduler readiness through posted ACK and I-cache `take` | −2.905 ns, same start and destination |
| 43 | −2.495 ns, CP15 MMU enable through I-cache request | −2.428 ns, same path |
| 13 | −2.055 ns, SDRAM scheduler readiness through posted ACK and I-cache `take` | −1.950 ns, stream `seen` through the same ACK |
| 31337 | −2.278 ns, scheduler readiness through posted ACK and I-cache `take` | −2.471 ns, same path |

The patch removes the structural write-completion dependency from
I-cache ACK. The D-cache and end-of-burst owner paths still need that
completion. Seed 43 also shows genuine D-cache paths from `mem_we` at
−2.421 ns hot and `WRITE_LOCKED` at −2.340 ns cold. The native reply
and MMU/TLB paths remain relevant. The matched fits below compare these
routes, worst setup, core TNS and ALMs.

The production fits run `91ee5c456144cdba8cdf7a9112dca64d1ab6ffe5`
at physical 104 MHz with DDR debugging off. Their control is the
same-day retained `81a1b45` tree.
[Seed 13](https://github.com/asturur/test_template_1/actions/runs/45786912492) ·
[Seed 43](https://github.com/asturur/test_template_1/actions/runs/45786908403) ·
[Seed 31337](https://github.com/asturur/test_template_1/actions/runs/45786907340)

| Seed | Retained setup | Split setup | Change | Retained ALMs | Split ALMs |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 13 | −2.061 ns | −2.566 ns | −0.505 ns | 36,420 | 37,121 |
| 43 | −2.508 ns | −2.450 ns | +0.058 ns | 36,446 | 37,131 |
| 31337 | −2.471 ns | −3.122 ns | −0.651 ns | 36,461 | 37,170 |
| Median | −2.471 ns | −2.566 ns | −0.095 ns | 36,446 | 37,131 |

Park `91ee5c4`. Named posted ACK routes through I-cache to the merger
fell from 26, 17 and 46 to zero in the hot exports. Median core setup
TNS moved from −5143.651 to −5504.602 ns. The new limiting paths went
to execute feedback, the D-side section TLB and the D-cache lock.
All three built RBFs and passed hold, recovery, removal, pulse width
and SDRAM pin packing. All three failed setup and used 321 M10Ks.
Forward restore `2e410c9` matches the retained tree. The best candidate,
seed 43, is archived at
`build/fit/v5-104mhz-91ee5c4-seed43/ngage1.rbf`.
[Fit manifests and route evidence](../../evidence/v5-104-wb-reply-class-fits.json)

## Qualification

- Directed shared-versus-split checks passed burst continuation,
  immediate I-cache handoff, native refill, scalar fallback, SWP,
  cancellation, slow ERR and reset over 42 rising edges. The
  existing scalar-owner test and pinned netlist generation passed.
- All 15 fixed workloads and their 105 windows match the retained
  cycles, guest digests and cycle-stamped trace of 52,087 writes.
  Fifteen repeats and all wrong-output controls passed. The four
  native PolyCount frames match all 57,508,371 clocks, 278,165 timed
  writes and output bytes. The replay saw 280,009 D-only ACKs and
  5,944,168 native line ACKs including setup.
- Mixed 104 MHz pin replay matched 171,496 events over 1,201,547
  clocks. It saw 18,945 physical and donor write ACKs and 95,120
  common ACKs. LCD, PCM, SWP and MMC persistence passed. The first
  `tri0` prototype repeated a posted write in the mixed simulation.
  The archived version uses plain input wires and explicit opt-in
  parameters, which passed the complete replay.

[Qualification receipt](../../evidence/v5-104-wb-reply-class.json)

## Replay

Set up the physical SDRAM decks and the matching retained output in
[fixture setup](fixtures.md#preparing-the-all-four-replay-decks) and
[prepared write-data replay](prepared-wb-write-data.md#reapply-and-verify).
The fixed and native decks come from
`build/sim/payload-clocks/v5-104-all-four-ram-candidate` and
`build/sim/polycount/v5-104-all-four-ram-candidate/i16`. The refill-pair
fixture stages unchanged board files in `scratch/refill-issue-739d3bd/leg`.
The prepared write-data replay supplies the observers and retained
`{fixed,native}.json` under `scratch/v5-fit-loop/prepared-wb-write-data/candidate`.
Its mixed pin replay supplies the original source, inputs and trace under
`build/sim/v5-104-more-ram-prepared-wb-write-data-pin-mixed/mixed`.

```sh
catalog=docs/experiments/v5-performance/patches
area=scratch/v5-fit-loop/wb-reply-class
mkdir -p "$area/source"
git archive 11c4a0c | tar -x -C "$area/source"
git apply --directory="$area/source" "$catalog/wb-reply-class.patch"
git apply --directory="$area/source" "$catalog/wb-reply-class-directed-fixture.patch"
git apply "$catalog/wb-reply-class-replay-tools.patch"
python3 -B "$area/source/tools/gen_arm9v2_phone.py" \
  --stock build/arm9v2-assoc/stock-pinned.v --check
python3 -B "$area/source/build/reply-class/replay.py" fixed --output qualify-fixed
python3 -B "$area/source/build/reply-class/replay.py" native --output qualify-native
python3 -B "$area/source/build/reply-class/prepare_mixed.py" \
  "$catalog/wb-reply-class-mixed-fixture.patch"
(
  cd "$area/source"
  out=build/reply-class
  iverilog -g2012 -s reply_class_tb -o "$out/reply-class" \
    tests/cpu/arm9v2_board/reply_class_tb.sv rtl/ngage_cpu.sv \
    rtl/ngage_upp.v rtl/arm9v2/arm925t_phone.v
  vvp "$out/reply-class"
  docker run --rm --pull=never --network none --platform linux/arm64 \
    -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 -ec '
      out=build/reply-class/mixed
      sh "$out/build.sh"
      "$out/obj/Vtb" +upp_stress "+compare_trace=$out/traffic.log" > "$out/replay.log"
    '
)
cmp build/sim/v5-104-more-ram-prepared-wb-write-data-pin-mixed/mixed/traffic.log \
  "$area/source/build/reply-class/mixed/traffic.log"
```

The replay driver regenerates the [fixed](patches/wb-reply-class-fixed-fixture.patch)
and [native](patches/wb-reply-class-native-fixture.patch) modifications
to the frozen testbenches. Both enable and observe the two rails on the
physical stream, arbiter and board peer. The original observers record
either rail as completion, so their output remains directly comparable.
