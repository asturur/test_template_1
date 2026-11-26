# Combine the MMC counter and lane 13 response changes

The stack applies the [MMC counter](patches/mmc-count-prepare.patch)
and [lane 13](patches/lane13-register-sources.patch)
patches to the retained `11c4a0c` tree. Each patch changes one RTL
file. The private MMC candidate `9a02faff` has exactly the tree
produced by the first patch. Both files in the combined candidate are
byte-identical to those used by the replay.

| Candidate | Parent | Git tree |
| --- | --- | --- |
| `1e2c7344ec15f504a38ad16da7da215394dd879b` | Standalone MMC `9a02faff` | `54f7a84b0825a6bdc194403740286f1969fbdd66` |
| `5e91495cbe00967237eec556262b043a9de09245` | Forward restore `88796f65` | `3d21ee389dd2e9ca1a14c086df1208ba78ad11c3` |

The forward restore has parent `9a02faff` and tree
`8406276acdc60d658e189d09d31b0699217717ba`, the exact retained tree.
The lane-only candidate changes the same UPP file as the independently
qualified [lane 13 replay](lane13-register-sources.md).
The archive verifier reproduces the combined RTL hashes from the two
design patches.

Preflight matched the effective QSF for seeds 13, 43 and 31337 at
physical 104 MHz with DDR debugging disabled. Across the 132 selected
sources in each run, the hashes differ only where the two candidate
trees differ from retained RTL.

## Combined replay

The lane 13 directed bench matched 614 responses and 4,070 trace
records with both keypad settings. The MMC command, clock and data
benches matched their retained logs. The 4 KiB TX/RX run used 258,366
clocks, covering 1,278 byte groups crossed by the counter, and the
internal observer agreed with the original arithmetic.

The physical 104 MHz replay matched 171,496 records over 1,201,547
clocks with LCD, PCM, MMC persistence and UPP DDR active. The pin
model's manifest identifies the MMC host and UPP peripherals as the
only changed source files. The fixed and native simulators explicitly
compiled both patched files from the combined source staging area.
All 105 fixed workload windows matched, including the repeated runs
and wrong-output checks. Four native PolyCount frames matched at
14,391,395, 14,467,552, 14,346,201 and 14,303,223 clocks, with
matching guest output, architectural digests and valid-write traces.
[Qualification receipt](../../evidence/v5-104-lane13-mmc-combined.json)

## Reproduction

Run from the repository root with the existing offline Jotego image,
prepared Wishbone write-data decks, and the archived MMC and lane 13
fixtures. Restore this package's runner files with
the [replay helper patch](patches/lane13-mmc-combined-replay.patch). The tree in the stack receipt
is reproducible from the two design patches even after the private
Git objects are archived.

```sh
area=scratch/v5-fit-loop/lane13-mmc-combined
catalog=docs/experiments/v5-performance/patches
out=build/sim/v5-104-lane13-mmc-combined
mkdir -p "$area/reference/build" "$area/source/build" "$out/mmc/reference" "$out/mmc/source"
git apply "$catalog/lane13-mmc-combined-replay.patch"
for leg in reference source; do
  git archive 11c4a0c rtl tools tests/cpu/arm9v2_board tests/cpu/spmark_payload \
    tests/phone/upp_ddr_ram/peer.v tests/phone/mmc_host | tar -x -C "$area/$leg"
done
git apply --directory="$area/source" "$catalog/mmc-count-prepare.patch"
git apply --directory="$area/source" "$catalog/lane13-register-sources.patch"
git apply --directory="$area/source" --include="$area/source/tests/phone/upp_lane13/*" \
  "$catalog/peripheral-lane13.patch"
cp scratch/v5-fit-loop/prepared-wb-write-data/{architectural_trace.vh,wb-write-trace.vh} "$area"
cp "$area/source/rtl/ngage_cpu.sv" "$area/ngage_cpu.sv"
cp scratch/v5-fit-loop/mmc-count-prepare/count-observer.vh "$area"
sed 's/^            set --$/            set -- -DREFERENCE/' \
  "$area/source/tests/phone/upp_lane13/run.sh" > "$area/directed.sh"
python3 -B "$area/prepare-host-tests.py"
```

To reconstruct the private commit lineage, run
`python3 -B "$area/prepare.py"` while the MMC parent is available
through the checkout or previous private object stores. The script
records new commit hashes if the author or commit timestamps differ.
Run `python3 -B "$area/preflight.py"` to check production inputs with
the retained fit manifests.

```sh
docker run --rm --pull=never --network none --platform linux/arm64 \
  -v "$PWD/$area:/bench:ro" -v "$PWD/$out:/results" -w /bench/source \
  --entrypoint sh jotego/simulator:arm64 \
  -ec 'UPP_LANE13_OUT=/results/directed sh ../directed.sh ../reference'
for leg in reference source; do
  docker run --rm --pull=never --network none --platform linux/arm64 \
    -v "$PWD/$area/$leg:/bench:ro" -v "$PWD/$out/mmc/$leg:/bench/build" -w /bench \
    --entrypoint sh jotego/simulator:arm64 -ec '
      sh tests/phone/mmc_host/run.sh
      out=build/sim/unit-mmc-host
      iverilog -g2001 -s tb -Ptb.DIV=3 -o "$out/long" rtl/ngage_mmc_host.v "$out/long_tb.v"
      vvp "$out/long" > "$out/long.log"
      grep -E "^(PASS|COUNT) " "$out/long.log"' > "$out/mmc/$leg.log" 2>&1
  sed -n '/^PASS /p' "$out/mmc/$leg.log" > "$out/mmc/$leg.pass"
done
cmp "$out/mmc/reference.pass" "$out/mmc/source.pass"
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
docker image inspect --format '{{.Id}} {{.Os}}/{{.Architecture}}' \
  jotego/simulator:arm64 > "$out/image.id"
python3 -B "$area/record-qualification.py"
```
