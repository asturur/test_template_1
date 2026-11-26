# Prepare timer count writes and stops at the UPP request boundary

The [design patch](patches/timer-write-prepare.patch) starts at `11c4a0c`, the exact retained `e9552bd` tree. The
internal UPP request stage captures six count-write selects and six stop
selects with the existing held CPU or local-DMA packet. A select requires
a write, all four byte lanes, a word in the timer aperture, the matching
unit and the count or zero-control register operation. The UPP word-aligns
the address before handing it to the timers, so the select follows the
same low-address aliases. Standalone timers still check raw alignment.
The new ports default to the live decode outside the internal UPP path.
Two positional timer test instances tie off the new inputs.

The selects take effect only on the original local commit, which already
checks packet liveness, reset, initialization and response ownership.
An admitted count write takes the explicit count-update branch. The
count, stop and expiry qualification therefore bypasses the late timer
claim and write-access decode. Control, reload, status writes and MMIO
reply selection retain their ordinary decode. A count write clears the
completion status and preserves an older interrupt. Stop preserves count.
A coincident new expiry still wins over an acknowledgement.

## Timing target

The retained seed 13 hot witness starts at `reset_drain~SynDup_58`, passes
two request-stage CYC cells, timer claim, timer write access and two count
control cells, and ends at the timer 4 count synchronous clear. It has
−1.931 ns setup and 10.833 ns data delay. The prototype keeps the required
live commit path and cuts its late timer-local decode leg. Seed 13 has
50 exported count endpoints below −1.5 ns in the hot model, all with
reset-drain launches. Seed 6 has 12 hot count endpoints below −1.5 ns
from other launches. The other retained hot exports and all retained
cold exports contain zero count endpoints below that threshold. Twelve
packet bits are added. Fitted area and changed route slack remain open.

## Qualification

The directed differential uses the production request stage and
registered peripheral responder. It covers 8,192 held-decode vectors
across all words, directions, byte masks and low-address aliases,
including the two unit numbers outside the aperture. Both legs return
6,025 responses and match 8,397 trace records. The timer 4 sequence
checks writes and stops coincident with expiry, acknowledge and reload
priority, passive status clearing, old interrupt retention, disabled
loads, zero wrap, pending-response hold, cancellation and warm reset.

The timer units, rate checks, request-stage checks, passive timer/ICU RAM
oracle, timer/ICU conformance and peripheral response tests pass. Four
original NEM-4 timer instruction runs match at dividers 3 and 4 with zero or
three peer waits. Both ROM slice hashes were checked against the pinned deck.
All four ARM9v2 contract profiles, 105 fixed windows and four native
PolyCount frames match, including output and architectural and write
digests. The exact physical SDRAM mixed workload matches 171,496 records
over 1,201,547 clocks.

A second physical replay inserts a timer 4 one-shot after the MMC write
and LCD DMA start. The guest observes expiry while the MMC host and LCD
DMA still report busy, then checks its timer acknowledgement. That replay
matches 171,497 records over 1,201,528 clocks. All three full replay
builds identify the three expected patched RTL files with the same
source hashes. [Qualification receipt](../../evidence/v5-104-timer-write-prepare.json)

The [combined replay with D-cache live trust](timer-live-trust-combined.md)
also matches both physical traces, the directed tests and the workloads.

## Reproduction

Use the existing offline Jotego image, prepared Wishbone write-data decks
and ARM GNU tools. Restore the helper files with
the [replay helper patch](patches/timer-write-prepare-replay.patch) and run from the repository root.

```sh
area=scratch/v5-fit-loop/timer-write-prepare
catalog=docs/experiments/v5-performance
out=build/sim/v5-104-timer-write-prepare
mkdir -p "$out"
for leg in reference source; do
  mkdir -p "$area/$leg/build" "$out/units/$leg"
  git archive 11c4a0c rtl tools .rules.verible_format tests/cpu/arm9v2_board \
    tests/cpu/spmark_payload tests/phone/upp_ddr_ram/peer.v \
    tests/phone/timers tests/phone/timer_rates tests/phone/timer_conformance \
    tests/phone/timer_original tests/phone/upp_request_stage tests/phone/register_ram \
    tests/phone/peripheral_response sim/programs/link.ld | tar -x -C "$area/$leg"
done
git apply "$catalog/patches/timer-write-prepare-replay.patch"
git apply --directory="$area/source" "$catalog/patches/timer-write-prepare.patch"
cp scratch/v5-fit-loop/prepared-wb-write-data/{architectural_trace.vh,wb-write-trace.vh} "$area"
cp "$area/source/rtl/ngage_cpu.sv" "$area/ngage_cpu.sv"
docker image inspect --format '{{.Id}} {{.Os}}/{{.Architecture}}' jotego/simulator:arm64 > "$out/image.id"
for leg in reference source; do
  docker run --rm --pull=never --network none --platform linux/arm64 \
    -v "$PWD/$area/$leg:/bench:ro" -v "$PWD/$out/units/$leg:/bench/build" -w /bench \
    --entrypoint sh jotego/simulator:arm64 -ec '
      for suite in timers timer_rates upp_request_stage register_ram peripheral_response; do
        sh tests/phone/"$suite"/run.sh
      done' > "$out/units/$leg.log" 2>&1
  sed -n '/^PASS /p' "$out/units/$leg.log" > "$out/units/$leg.pass"
done
cmp "$out/units/reference.pass" "$out/units/source.pass"
docker run --rm --pull=never --network none --platform linux/arm64 \
  -v "$PWD/$area/source:/bench:ro" -v "$PWD/$out/units/source:/bench/build" -w /bench \
  --entrypoint sh jotego/simulator:arm64 tests/phone/timer_conformance/run.sh > "$out/units/conformance.log" 2>&1
python3 -B "$area/prepare-directed.py"
docker run --rm --pull=never --network none --platform linux/arm64 \
  -v "$PWD/$area:/bench:ro" -v "$PWD/$out/directed:/results" -w /results \
  --entrypoint sh jotego/simulator:arm64 -ec '
    for leg in reference source; do
      base=/bench/$leg/rtl
      set --
      if [ "$leg" = reference ]; then set -- -DREFERENCE; fi
      iverilog -g2012 -s tb "$@" -y "$base" -I "$base" -o "$leg" \
        "$base/ngage_upp.v" "$base/ngage_upp_euart.v" tb.sv
      vvp "$leg" > "$leg.log"
      grep -E "^(TRACE|PASS) " "$leg.log" > "$leg.trace"
    done
    cmp reference.trace source.trace'
sh "$area/original.sh" "$pinned_timer_instruction_deck"
sh "$area/board.sh"
for measure in fixed native; do
  python3 -B "$area/replay.py" "$measure" --output qualification
done
python3 -B "$area/mixed.py"
mixed="$out/mixed"
retained=build/sim/v5-104-more-ram-prepared-wb-write-data-pin-mixed/mixed
docker run --rm --pull=never --network none --platform linux/arm64 \
  -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 \
  -ec "sh '$mixed/build.sh'
'$mixed/obj/Vtb' +upp_stress '+compare_trace=$mixed/traffic.log' > '$mixed/replay.log'"
cmp "$retained/traffic.log" "$mixed/traffic.log"
sh "$area/coexistence.sh"
python3 -B "$area/record.py"
```

Set `pinned_timer_instruction_deck` to the directory that contains the
inputs produced by `tests/phone/timer_original/prepare.py` for the pinned
ROM. This qualification used the archived output under
`scratch/retired-v5-worktree.5eDUI7tZ/scratch/ngage2-integration/timer-flow-2026-11-11/original`.
