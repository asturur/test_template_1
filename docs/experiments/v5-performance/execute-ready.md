# Execute operand readiness by W-load outcome

The [portable RTL, generator and test patch](patches/execute-ready.patch)
applies directly to the retained DDR candidate `b6d8981`. The isolated fit
candidate is `c492853ece51f106dc933c5cff8579eaffcd18ed`.

Seed 43 routed from `w_hit_candidate` through `s_wait` and
`o_ready_payload` into execute packet `a[234]` at −3.277 ns. The
corresponding named paths in the seed 13 and 31337 exports entered from
resident-packet finish and same-destination load ordering, respectively.
The patch resolves those inputs for both hit outcomes before one late
selection.

Each operand retains the youngest matching producer, with M winning
over W on either lane. Its wait is classified as unconditional or
released by a W hit. A and S retain their individual trust conditions.
The two candidate readiness decisions combine the early operands,
resident A finish and replacement, and the same-destination W guard.
A newly eligible register shift still requires its early Rs operand.
The admission calculation can check its instruction form in parallel.
Operand values, returned-data capture, producer forwarding grants,
shift preparation, and architectural flush and redirect priority keep
their original behavior. The version adds no clock edge to admission
or to forwarding.

## Reapply and verify

From the repository root, reproduce the isolated source and run the
stage differential in the installed offline simulator. This uses the
pinned stock netlist produced by the existing ARM9v2 generator setup.

```sh
area=scratch/recheck-execute-ready
mkdir -p "$area/source"
git archive b6d8981 | tar -x -C "$area/source"
git show b6d8981:rtl/arm9v2/arm925t_phone.v > "$area/reference.v"
git apply --directory="$area/source" docs/experiments/v5-performance/patches/execute-ready.patch
python3 "$area/source/tools/gen_arm9v2_phone.py" \
  --stock build/arm9v2-assoc/stock-pinned.v --check
docker run --rm --pull=never --network none --platform linux/arm64 \
  -v "$PWD/$area:/stage" -w /stage/source --entrypoint sh jotego/simulator:arm64 -ec \
  'sh tests/cpu/arm9v2_board/run-execute-ready.sh /stage/reference.v'
```

The direct test compares all execute outputs and packet/held state
with the old module over 20,000 cycles. It exercised 658 accepts that
depended on the hit, 943 blocked misses, 197 same-edge replacements,
5,459 prepared-shift cycles and 180 redirects. During the board and
workload replay, simulation assertions check both the old execute
wait/admission equations and the original same-destination W guard.
The four ARM9v2 board profiles include a data abort with a following
same-destination load, control-flow changes, SWP and variable response
delay. Each matched 293 ordered branch events, 22 ordered MMIO
records and the original clock count.

The [qualification receipt](execute-ready-replay.json) records the
exact source hashes, every benchmark window and four native frame
digests. All 15 fixed workloads match the retained DDR control and
reject deliberately wrong output. Native PolyCount matches all four
frames, their output SHA-256 and their total of 57,508,371 measured
clocks. The mixed SDRAM pin/phone-endpoint replay matches 1,201,547
clocks, the MMC write/readback, 18,304 LCD words, and PCM hash
`175ee178` with no underruns.

To rerun the fixed and native benches, first prepare the all-four decks
and archived DDR reference using the
[DDR replay recipe](ddr-burst-bounds.md). Extract the
[execute replay fixture](patches/execute-ready-replay.patch) and use
the candidate under the paths expected by that runner:

```sh
area=scratch/v5-fit-loop/execute-ready
mkdir -p "$area/source" "$area/replay"
git apply docs/experiments/v5-performance/patches/execute-ready-replay.patch
git archive b6d8981 | tar -x -C "$area/source"
git apply --directory="$area/source" docs/experiments/v5-performance/patches/execute-ready.patch
git show b6d8981:rtl/ngage_cpu.sv > "$area/ngage_cpu.sv"
python3 -B "$area/replay.py" fixed
python3 -B "$area/replay.py" native
```

## Routed results

At physical 104 MHz with the DDR debugger disabled, seed 43 improved
from −3.277 to −2.668 ns and seed 31337 from −2.978 to −2.666 ns.
Seed 13 moved from −2.742 to −2.954 ns. Median setup improved
0.310 ns. The hot export counts for named readiness paths into
execute packets went from 44, 111 and 7 to 13, 18 and zero.
The exported direct W-hit, short-hit and short-trust paths to those
packets fell to zero at all four corners.

All three fits missed setup and passed the other four-corner checks.
Keep the trial active as `c492853`. Seed 31337 produced the best
archived bitstream. [Matched fits and bitstream hash](../../evidence/v5-104-execute-ready-fits.json)
