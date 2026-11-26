# Read the captured MMC footer during CRC verification

The [design patch](patches/mmc-footer-crc-direct.patch) applies to retained commit `11c4a0c32983cc9aba89cae986684558583a33f2` (tree `8406276acdc60d658e189d09d31b0699217717ba`). It removes the two 120-bit CRC shift banks from `rtl/ngage_mmc_hps.v` and uses the existing four-bit CRC counter to select one byte from each captured record.

The backing adapter owns incoming words only in REQUEST, ACTIVE and TAIL. TAIL enters VERIFY once the expected words arrive. At the first VERIFY edge, the old shift banks expose bytes 15, and their successive shifts expose bytes 14 through 1. The counter starts at 15 and decrements on those same edges, so the indexed reads present exactly the same sequence. Byte zero holds the stored CRC and stop bit. At counter zero the existing metadata check looks at both accumulated CRCs and all the same footer fields. The change keeps the original ACK duration, CRC accumulator enables, reset, admission and cancellation priorities.

The design removes 240 sequential bits and adds two byte selectors with a common index. Synthesis may use two levels of muxing ahead of CRC, and the two selectors may reuse counter decoding. The area and timing trade-off requires a fit. The [matched audit](fitter-alm-accounting.md) describes why this module is of interest and what the existing fits can establish.

## Qualification

- The existing 48-case direct Icarus test, including invalid footer cases, matched both legs. A Verilog-2001 extension flipped a data bit in each of the 30 protected bytes in turn, strobed the unselected shared slot during VERIFY and interrupted active VERIFY with guest reset, initial reset or remount. It checked the fresh footer afterward. The 82-case replay matched all 1,186 per-edge CRC and ownership records.
- The existing three-slot bench with retained `hps_io` and the native MMC card matched at 604,018 clocks, with 20 card reads, four card writes, two other-slot reads and two bulk reads. Verilator recorded the same candidate source fingerprint for this bench and the physical SDRAM replay.
- Physical SDRAM replay instantiated the candidate HPS adapter and matched all 171,496 traffic records and 1,201,547 clocks. Native MMC card coverage includes CMD24 TX2 DMA, 512-byte persistence, and PIO readback while PCM, LCD and both UPP DDR banks are active. Only the adapter's hash differed among 114 staged source files.
- The frozen guest replay matched all 105 fixed windows, including repeat runs and negative-output checks. It matched all four native PolyCount frames at 14,391,395, 14,467,552, 14,346,201 and 14,303,223 clocks, including guest output and architectural and valid-write digests. Those decks disable MMC and serve as guest digest controls. The direct, native card and physical SDRAM fixtures exercise the changed adapter.

[Machine-readable receipt](../../evidence/v5-104-mmc-footer-crc-direct.json)

The [combined timer and footer replay](mmc-footer-timer-combined.md)
also matches the actual card and HPS test, both physical traces, and
the workload digests.

The production triplet uses the combined candidate `3e3dc32` with
timer-only `9f16d1a` as the matched control. Both run at physical
104 MHz with DDR debugging off.
[Seed 13](https://github.com/asturur/test_template_1/actions/runs/45830589134) ·
[Seed 43](https://github.com/asturur/test_template_1/actions/runs/45830594892) ·
[Seed 31337](https://github.com/asturur/test_template_1/actions/runs/45830599809)

## Reproduction

Run from the repository root with the frozen fixed/native decks, the prepared Wishbone observers and receipts, the physical SDRAM replay input and the cached Jotego image. The [fixture patch](patches/mmc-footer-crc-direct-replay.patch) installs the scripts into the scratch directory.

```sh
area=scratch/v5-fit-loop/mmc-footer-crc-direct
catalog=docs/experiments/v5-performance/patches
out=build/sim/v5-104-mmc-footer-crc-direct
mkdir -p "$area/reference" "$area/source" "$out/units"
for leg in reference source; do
  git archive 11c4a0c rtl tools sys .rules.verible_format tests/phone/mmc_hps \
    tests/phone/upp_ddr_ram/peer.v tests/cpu/arm9v2_board tests/cpu/spmark_payload \
    sim/programs/link.ld | tar -x -C "$area/$leg"
done
git apply "$catalog/mmc-footer-crc-direct-replay.patch"
git apply --directory="$area/source" "$catalog/mmc-footer-crc-direct.patch"
cp scratch/v5-fit-loop/prepared-wb-write-data/architectural_trace.vh "$area"
cp scratch/v5-fit-loop/prepared-wb-write-data/wb-write-trace.vh "$area"
cp "$area/source/rtl/ngage_cpu.sv" "$area/ngage_cpu.sv"
docker image inspect -f '{{.Id}} {{.Os}}/{{.Architecture}}' jotego/simulator:arm64 > "$out/image.id"

for leg in reference source; do
  docker run --rm --pull=never --network none --platform linux/arm64 \
    -v "$PWD/$area/$leg:/bench:ro" -v "$PWD/$out/units:/results" -w /bench \
    -e "MMC_HPS_OUT=/results/$leg" --entrypoint sh jotego/simulator:arm64 \
    -ec 'iverilog -g2001 -s ngage_mmc_hps -o /results/elaborate rtl/ngage_mmc_hps.v
         sh tests/phone/mmc_hps/run.sh' > "$out/units/$leg.log"
  grep '^PASS ' "$out/units/$leg.log" > "$out/units/$leg.pass"
done
cmp "$out/units/reference.pass" "$out/units/source.pass"

python3 -B "$area/prepare-verify.py"
docker run --rm --pull=never --network none --platform linux/arm64 \
  -v "$PWD/$area:/bench:ro" -v "$PWD/$out/verify:/results" -w /results \
  --entrypoint sh jotego/simulator:arm64 -ec '
  for leg in reference source; do
    iverilog -g2001 -s tb -o "$leg" "/bench/$leg/rtl/ngage_mmc_hps.v" tb.v
    vvp "$leg" > "$leg.log"
    grep -E "^(CRC_EDGE|PASS) " "$leg.log" > "$leg.trace"
    grep -q "^PASS MMC HPS direct " "$leg.trace"
  done
  cmp reference.trace source.trace'

for kind in fixed native; do
  python3 -B "$area/replay.py" "$kind" --output qualification
done

python3 -B "$area/mixed.py"
mixed="$out/mixed"
retained=build/sim/v5-104-more-ram-prepared-wb-write-data-pin-mixed/mixed
docker run --rm --pull=never --network none --platform linux/arm64 \
  -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 \
  -ec "sh '$mixed/build.sh'
'$mixed/obj/Vtb' +upp_stress '+compare_trace=$mixed/traffic.log' > '$mixed/replay.log'"
cmp "$retained/traffic.log" "$mixed/traffic.log"
python3 -B "$area/record-qualification.py"
```
