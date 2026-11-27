# Use cancellation to qualify the MMC HPS owner

The [design patch](patches/mmc-hps-cancel-owner.patch) applies to retained `11c4a0c32983cc9aba89cae986684558583a33f2`, tree `8406276acdc60d658e189d09d31b0699217717ba`. It changes only `rtl/ngage_mmc_hps.v`.

## Ownership proof

- Configuration initializes IDLE, clears cancellation, and sets both generation registers to zero. IDLE is the only cancellation clear and the only state that can establish an owner. Its request branch requires `!changed`, so the generation stays fixed on the edge that captures it. An IDLE mount-release edge publishes no request.
- An init, guest-reset or mount edge in any non-IDLE state sets `cancelled`. A non-IDLE arm never clears it. Malformed words and an unexpected new ACK during TAIL can also set cancellation. Hence any uncancelled owner that persists from the previous edge has seen no intervening generation increment. This covers simultaneous events, ACK rise or fall, valid or invalid progress, TAIL restarts, CRC verification, and a transition back to IDLE. The proof depends on the enable for addition, so it also holds at 32-bit wrap.
- All current-owner consumers exclude IDLE. Malformed buffer tests, native buffer writes and footer capture require `owns_buffer`. Native ACK lists REQUEST, ACTIVE, TAIL and VERIFY explicitly. The remaining reads of the predicate are inside TAIL or VERIFY. In reserved encodings 5–7 those consumers are all inactive even if the generation registers are unequal and cancellation is clear. The default arm still sets fault and returns to IDLE. Thus an unused equality while IDLE and any unequal reserved-state counters cannot change an observed signal or update.
- The old advertised HPS request, descriptor, outgoing data and busy drain retain their existing state-based rules. The update removes the now-redundant epoch registers and comparison while leaving the original cancellation, assignment priorities and footer admission logic in place.

## Area and timing

The source change removes 64 register bits, a 32-bit incrementer, the capture enable for the 32-bit request epoch, and a wide equality from the current-owner qualifiers for reset, native ACK, buffer write, footer capture and drain. The retained backing entity maps to 793 FFs and 530 ALUTs at seeds 13, 43 and 31337. Its fitted estimate is 435.7, 429.9 and 440.2 ALMs, respectively. Earlier parked builds of the same HPS RTL have placement/retiming entries naming all 32 `request_generation` bit indices. Fitted area, packing and timing of this candidate are unmeasured.

Across the ten retained fits, 85 named generation endpoint rows occur in five cold slow top-1,000 exports. None appear in the other 35 per-corner exports. The worst named path is seed 2 at −1.476 ns, from `h_lba[3]~DUPLICATE` to `request_generation[26]`. On seed 31337 the worst named example is −1.209 ns from `h_blk_cnt[1]` to `request_generation[13]`. These observations support an area trial. The named paths were outside the retained worst setup group.

## Qualification

- The dual-instance Icarus miter matched all 15 public outputs and all shared registered state before and after clocks at 379,781 comparison points. It traversed 448 directed reset/mount/ACK/progress combinations across read REQUEST, ACTIVE, TAIL and VERIFY and write REQUEST, ACTIVE and TAIL, 49 seeded production-width counter wraps, 24 reserved-state recoveries, and 7,168 deterministic randomized edges.
- The retained 48-case direct test matched, including invalid ingress and metadata. The actual three-slot `hps_io` and native MMC card matched at 604,018 clocks, with 20 card reads, four card writes, two other-slot reads and two bulk reads. Its compiled candidate fingerprint matches the mixed replay.
- The physical SDRAM and HPS replay matched all 171,496 trace records in 1,201,547 clocks, including the native CMD24 persistence and PIO readback while LCD, PCM and both UPP DDR banks are active. Only the HPS adapter changed among 114 compiled source hashes.
- The frozen non-MMC digest controls matched all 105 fixed windows, repeats and wrong-output rejections and all four native PolyCount frames, with identical architectural, output and valid-write digests.

[Qualification receipt](../../evidence/v5-104-mmc-hps-cancel-owner.json)

The [qualification on the timer and footer branches](mmc-hps-owner-timer-combined.md)
also matches the real three-slot HPS bench, both physical SDRAM traces,
and all guest workload digest checks.

The production candidate `efc761a` is a child of the exact timer-tree
restore `409fb87`. The matched control is timer-only `9f16d1a` at
physical 104 MHz with DDR debugging off.
[Seed 13](https://github.com/asturur/test_template_1/actions/runs/45837478177) ·
[Seed 43](https://github.com/asturur/test_template_1/actions/runs/45837483204) ·
[Seed 31337](https://github.com/asturur/test_template_1/actions/runs/45837488068)

## Routed results

| Seed | Timer setup | Owner setup | Timer / owner ALMs needed | Timer / owner occupied ALMs | Timer / owner HPS occupied ALMs |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 13 | −2.214 ns | −2.615 ns | 37,039 / 36,906 | 38,645 / 38,617 | 579.6 / 481.3 |
| 43 | −2.403 ns | −2.766 ns | 37,014 / 37,019 | 38,576 / 38,570 | 581.3 / 489.4 |
| 31337 | −2.452 ns | −2.079 ns | 36,908 / 36,918 | 38,603 / 38,680 | 599.3 / 493.8 |
| Median | −2.403 ns | −2.615 ns | 37,014 / 36,918 | 38,603 / 38,617 | 581.3 / 489.4 |

Park `efc761a` as a timing base. Seed 31337 gains 0.373 ns against
its timer control and comes within 0.018 ns of the retained best fit.
The other two seeds lose setup. Core TNS worsens on all three seeds,
with the median moving from −3791.887 to −3874.340 ns. The backing
adapter occupies 91.9–105.5 fewer ALMs across all three seeds and
its fitted ALUT count falls to 546 each time. Whole-design median
occupation grows by 14 ALMs. Every build uses 321 M10Ks, passes
hold, recovery, removal, pulse width and SDRAM pin packing, and
fails setup. The best experimental RBF is
`build/fit/v5-104mhz-efc761a-seed31337/ngage1.rbf`.
Forward restore `2d69c26` returns to the exact timer tree.
[Matched timing and area evidence](../../evidence/v5-104-mmc-hps-cancel-owner-fits.json)

## Reproduction

Run from the repository root with the archived design and fixture patches, prepared Wishbone write-data digest controls, pinned mixed pin-model replay and existing offline simulator image. The archived footer CRC replay documents the same frozen decks. Set `patches` to the directory containing both patches.

```sh
area=scratch/v5-fit-loop/mmc-hps-cancel-owner
out=build/sim/v5-104-mmc-hps-cancel-owner
mkdir -p "$out/units"
for leg in reference source; do
  mkdir -p "$area/$leg"
  git archive 11c4a0c rtl tools sys .rules.verible_format tests/phone/mmc_hps \
    tests/phone/upp_ddr_ram/peer.v tests/cpu/arm9v2_board tests/cpu/spmark_payload \
    sim/programs/link.ld | tar -x -C "$area/$leg"
done
git apply "$patches/mmc-hps-cancel-owner-replay.patch"
git apply --directory="$area/source" "$patches/mmc-hps-cancel-owner.patch"
cp "$patches/mmc-hps-cancel-owner.patch" "$patches/mmc-hps-cancel-owner-replay.patch" "$area"
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

python3 -B "$area/prepare-owner-miter.py"
docker run --rm --pull=never --network none --platform linux/arm64 \
  -v "$PWD/$out/owner-miter:/work" -w /work --entrypoint sh jotego/simulator:arm64 \
  -ec 'iverilog -g2001 -s tb -o miter tb.v retained.v trial.v
       vvp miter > miter.log
       grep "^PASS owner miter " miter.log'

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
