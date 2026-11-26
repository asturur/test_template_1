# Register the GPIO and EUART response sources separately

The [design patch](patches/lane13-register-sources.patch) applies to `11c4a0c`, which has the same tree as retained
`e9552bd`. The two worst exported routes on retained seeds 43 and 13 terminate
at `local_results[13].data`. The old lane 13 data input selected between
`uart_data` and `keypad_dout` using the live EUART claim. Lane 13 now captures
`uart_data` directly. GPIO uses the existing lane 2 `keypad_dout` sample,
which already captures the identical word on the same edge. Lane 2's
registered data predicate includes GPIO ownership, and lane 13's predicate
includes only EUART ownership. Both feed the existing balanced return tree
with its original one masked word per leaf. Reusing the keypad sample
requires two new one-bit data predicates.

The original selected owner and error remain paired on every response,
including lane 13 requests rejected for invalid byte lanes. The data
predicates use the same sampling and hold condition as their data and error.
Ready, commit and valid still use the same edges. SIMIF still owns its
overlapping status accesses and samples the EUART contribution on that
edge. The immediate fabric uses the original data mux and owner. The keypad
overlay and EUART address decoding are the retained versions. Routed area
and timing remain open.

The lane-only production build is `5e91495`, a child of the exact
retained-tree forward restore `88796f65`. It uses the same-day retained
controls at 104 MHz with DDR debugging off.
[Seed 13](https://github.com/asturur/test_template_1/actions/runs/45800010061) ·
[Seed 43](https://github.com/asturur/test_template_1/actions/runs/45800009911) ·
[Seed 31337](https://github.com/asturur/test_template_1/actions/runs/45800009711)

## Qualification

The archived directed bench matched 614 responses and 4,070 trace records
with the keypad enabled and disabled. Standalone keypad, immediate board
keypad and EUART checks passed, and the registered responder elaborated as
Verilog-2001. The four ARM9v2 upstream-peer profiles matched with the retained
half-writeback and two-way XOR fixtures.

All 105 fixed workload windows and their negative-output checks matched.
The four native PolyCount frames matched at 14,391,395, 14,467,552,
14,346,201 and 14,303,223 clocks with identical outputs and traces. The
physical SDRAM replay matched 171,496 records and 1,201,547 clocks with
LCD, PCM, MMC persistence and both UPP DDR banks active. A hash comparison
of all 114 pin-model sources identified the UPP peripheral file as the
single changed source. [Qualification receipt](../../evidence/v5-104-lane13-register-sources.json)

The [combined replay with the MMC counter](lane13-mmc-combined.md)
also matches the retained directed tests, workloads and physical trace.

## Reproduction

Run from the repository root with the existing offline Jotego simulator
and local ARM GNU tools. Use the frozen input decks and retained receipts
from the prepared Wishbone write-data experiment. The two fixed/native
observers come from that replay. Restore `board.sh`, `mixed.py` and `replay.py`
with the [replay helper patch](patches/lane13-register-sources-replay.patch).

```sh
area=scratch/v5-fit-loop/lane13-register-sources
catalog=docs/experiments/v5-performance
out=build/sim/v5-104-lane13-register-sources
mkdir -p "$area/reference" "$area/source" "$out/units"
git archive 11c4a0c rtl tests/phone/keypad tests/phone/upp_euart \
  tests/cpu/arm9v2_board sim/programs/link.ld .rules.verible_format tools/format_phone_rtl.py \
  | tar -x -C "$area/reference"
(cd "$area/reference" && tar -c -f - .) | tar -x -C "$area/source"
git archive 11c4a0c tools tests/cpu/spmark_payload tests/phone/upp_ddr_ram/peer.v \
  | tar -x -C "$area/source"
git apply "$catalog/patches/lane13-register-sources-replay.patch"
git apply --directory="$area/source" "$catalog/patches/lane13-register-sources.patch"
git apply --directory="$area/source" --include="$area/source/tests/phone/upp_lane13/*" \
  "$catalog/patches/peripheral-lane13.patch"
cp scratch/v5-fit-loop/prepared-wb-write-data/{architectural_trace.vh,wb-write-trace.vh} "$area"
cp "$area/source/rtl/ngage_cpu.sv" "$area/ngage_cpu.sv"
```

The archived directed test remains byte-identical. Its original candidate
branch adds ports for the earlier EUART predecode trial. Generate a runner
that uses the retained port list for both legs.

```sh
sed 's/^            set --$/            set -- -DREFERENCE/' \
  "$area/source/tests/phone/upp_lane13/run.sh" > "$area/directed.sh"
mkdir -p "$area/source/build"
docker run --rm --pull=never --network none --platform linux/arm64 \
  -v "$PWD/$area:/bench:ro" -v "$PWD/$out:/results" \
  -v "$PWD/$out/units:/bench/source/build" -w /bench/source \
  --entrypoint sh jotego/simulator:arm64 -ec '
    UPP_LANE13_OUT=/results/directed sh ../directed.sh ../reference
    sh tests/phone/keypad/run.sh
    sh tests/phone/upp_euart/run.sh
    iverilog -g2001 -s ngage_upp_peripherals -Pngage_upp_peripherals.REGISTER_RESPONSES=1 \
      -y rtl -I rtl -o /results/units/registered-v2001 rtl/ngage_upp_peripherals.v'
sh "$area/board.sh"
for measure in fixed native; do
  python3 -B "$area/replay.py" "$measure" --output final-qualification
done
python3 -B "$area/mixed.py"
mixed="$out/mixed"
retained=build/sim/v5-104-more-ram-prepared-wb-write-data-pin-mixed/mixed
docker run --rm --pull=never --network none --platform linux/arm64 \
  -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 \
  -ec "sh '$mixed/build.sh'
'$mixed/obj/Vtb' +upp_stress '+compare_trace=$mixed/traffic.log' > '$mixed/replay.log'"
cmp "$retained/traffic.log" "$mixed/traffic.log"
```
