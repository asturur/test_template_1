# Wait for the older W load before issuing a same-destination load

The [design patch](patches/conservative-w-load-order.patch) starts at `11c4a0c`, the exact retained `e9552bd` tree.
`WAW_WAIT_RETIRE` defaults to the legacy behavior in the ARM9 core.
The generated phone instance enables it. Both execute W-load order inputs
then use the original no-hit wait. The same-destination guard has no
combinational release from completion, ACK, retry or error. Forwarding,
load-hit selection, exception handling, requests, cache sizes and clocks
follow the retained implementation. Routed timing and area remain open.

## Ordering proof

The retained hit arm checks the same writer in W and drops its wait
only for a successful trusted completion. The conservative mode waits
on W valid, write destination and the held younger load. The generated
guard was compared against retained logic over all 128 Boolean input
vectors. The default mode matched every vector. Exactly one vector
changes in the phone mode. Both modes wait in all 32 vectors with
a same-destination writer and an error. Both release when no older
same-destination W writer is present.

The existing retirement logic makes W advance to M or clear its valid
bit when the old writer completes. A same-destination M, skid or
cache lock still holds the younger load through its own guard.
A fault redirects and clears the pipeline through the existing flush.
The directed test checks both the held issue edge and the next edge,
then checks all 64 retired PCs and alternating result values in order.
It observes an older external abort, no younger execution on that
edge, an unchanged destination in the handler, and one successful
same-destination follower after return. The sampled fault edge has no
valid S-stage WAW guard. The extracted guard test covers that conjunction
independently.

| Directed profile | Retained chain clocks | Candidate chain clocks | Candidate observed holds |
| --- | ---: | ---: | ---: |
| Scalar, zero wait | 219 | 254 | 62 |
| Scalar, five waits | 499 | 503 | 55 |
| Burst, zero wait | 192 | 254 | 62 |
| Burst, five waits | 192 | 254 | 62 |

Every counted hold in the directed chain accepted the same younger PC
on the next edge. The chain clock totals also include other scheduling
effects. The four normal ARM9v2 contract profiles match cycle for cycle.

## Workload cost

All 105 fixed windows retain the ordered architectural, data and
acknowledged Wishbone write digests and pass the guest checks. All 15
wrong-output controls are rejected. The 12 unchanged medians have no
observed held admissions. Three workloads have measurable cost.

| Fixed workload | Retained median | Candidate median | Delta | Held admissions across seven windows |
| --- | ---: | ---: | ---: | ---: |
| Triangle edges | 12,226 | 12,236 | +0.082% | 112 |
| Asphalt table | 21,163 | 21,414 | +1.186% | 1,792 |
| JPEG diffuse m10 8x8 | 35,324 | 35,524 | +0.566% | 1,399 |

Four native PolyCount frames take 57,566,521 clocks against 57,508,371
retained, a cost of 58,150 clocks (+0.1011%). The candidate holds 59,866
otherwise-ready same-destination admissions. The output, ordered guest
and acknowledged write digests match. Cycle-stamped write traces change
with the longer runs. The 104 MHz mixed SDRAM, LCD, PCM and MMC replay
matches all 171,496 records and 1,201,547 clocks. The generated CPU
netlist is the only changed source across the 114 pin-model source hashes.
[Qualification receipt](../../evidence/v5-104-conservative-w-load-order.json)

## Reproduction

Run from the repository root with the pinned stock netlist, retained
Wishbone write-data decks, ARM GNU tools and offline Jotego simulator.
Restore the helper files with the [replay patch](patches/conservative-w-load-order-replay.patch).

```sh
area=scratch/v5-fit-loop/conservative-w-load-order
catalog=docs/experiments/v5-performance/patches
out=build/sim/v5-104-conservative-w-load-order
mkdir -p "$out"
for leg in reference source; do
  mkdir -p "$area/$leg"
  git archive 11c4a0c rtl tools tests/cpu/arm9v2_board tests/cpu/spmark_payload \
    tests/phone/upp_ddr_ram/peer.v sim/programs/link.ld | tar -x -C "$area/$leg"
done
git apply "$catalog/conservative-w-load-order-replay.patch"
git apply --directory="$area/source" "$catalog/conservative-w-load-order.patch"
for leg in reference source; do
  python3 -B "$area/$leg/tools/gen_arm9v2_phone.py" \
    --stock build/arm9v2-assoc/stock-pinned.v --check
done
cp scratch/v5-fit-loop/prepared-wb-write-data/{architectural_trace.vh,wb-write-trace.vh} "$area"
cp "$area/source/rtl/ngage_cpu.sv" "$area/ngage_cpu.sv"
docker image inspect --format '{{.Id}} {{.Os}}/{{.Architecture}}' jotego/simulator:arm64 > "$out/image.id"
python3 -B "$area/guard-proof.py"
proof="$out/guard-proof"
docker run --rm --pull=never --network none --platform linux/arm64 \
  -v "$PWD/$proof:/proof" -w /proof --entrypoint sh jotego/simulator:arm64 \
  -ec 'iverilog -g2012 -s tb -o check tb.v && vvp check' > "$proof/run.log"
sh "$area/directed.sh"
sh "$area/board.sh"
for measure in fixed native; do
  python3 -B "$area/replay.py" "$measure" --retained --output retained
  python3 -B "$area/replay.py" "$measure" --output candidate
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
