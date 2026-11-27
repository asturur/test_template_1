# Wait for the older W load before issuing to the same destination

The [original design patch](patches/conservative-w-load-order.patch) applies byte for byte to `ab75a622a80a5aedae347f63ae195f3da965815a`, tree `57cc1a796acc9b15a61522ccf2397230f38e9799`. The generated phone explicitly binds `WAW_WAIT_RETIRE=1` at `ngage2_zap_top.g_arm9.u_arm9_core`. Generic core callers retain the default of zero. A test-only bind attests the actual elaborated parameter and asserts equal hit/no-hit ordering waits on every live clock. The pinned generator reproduces both production files, and both optional hinted outputs reproduce the corresponding standalone guard and reference without the D beat transform.

## Target and residual paths

Seed 13 slow hot/cold rank 1 is `w[541]` through `complete_class[0]` and `ready_if_hit` to execute `a[241]`, at −2.006 ns and −1.994 ns. In each slow top-100 detailed sample four paths launch at `w[541]` through the classifier. Two end in A right payload and two in the memory check record.

The retained S same-destination hit guard has a direct release arm using a trusted successful W completion. Its predicate uses `wb_valid`, `request_done`, `retry` and `resp_err`. With the phone option enabled, this release predicate drops from the S hazard cone and `s_wait_w_hit` equals `s_wait_w_nohit`. The separate `load_trust` selects `i_data_short_trust` in production `TRUST_FF`, independently of `wb_valid`. It still controls A/S operand and self-dependency readiness. Both issue arms keep the same-destination lookup from raw `w[541]`, owner `w[527]` and W destination. The seed 43 slow rank-one destination route from `w[93]` remains structurally live. `wb_valid` still drives GPR and forwarding writes, and the retained completion class still controls W retirement, forwarding feedback and memory checks. The parked W-completion experiment registered the classifier. This trial changes just the same-destination ordering rule. Candidate routed setup and hold are unmeasured.

## Ordering and physical checks

The extracted guard miter covers all 128 binary inputs. Its default matches the retained guard. One case adds a wait in phone mode, and all 32 same-writer error cases retain their hold. The existing lock, M/skid, flush and exception paths remain the source of their respective ordering rules.

The directed ARM fixture matches all 64 retired PCs and alternating destination values in causal order. Across four burst/wait profiles it accepts the same younger packet on the next edge after each observed guard hold. It also checks precise external abort, destination preservation and a same-destination follower after return. The sampled fault edge has no active S same-writer guard. The extracted miter covers that conjunction independently.

| Directed profile | Retained clocks | Guard clocks | Guard holds |
| --- | ---: | ---: | ---: |
| Scalar, zero wait | 219 | 254 | 62 |
| Scalar, five waits | 499 | 503 | 55 |
| Burst, zero wait | 192 | 254 | 62 |
| Burst, five waits | 192 | 254 | 62 |

The four ordinary board profiles match cycle for cycle. All four physical traces match with active guard, including 171,496 normal, 171,497 timer/MMC/LCD, 172,060 CPU block-eviction and 171,518 MMC/HPS warm-Hold records. The compile manifests identify the exact generated netlist. The active D and WAW bind markers are also observed together when the changes stack.

## Measured workload cost

All 105 fixed windows, 15 repeats and four native frames match the checked guest outputs, architectural digests and ordered acknowledged writes. All 15 wrong-output controls are rejected. Twelve fixed medians tie.

| Fixed kernel | Retained median | Guard median | Relative cost | Holds over seven windows |
| --- | ---: | ---: | ---: | ---: |
| Triangle edges | 12,226 | 12,236 | +0.0818% | 112 |
| Asphalt table | 21,163 | 21,414 | +1.1860% | 1,792 |
| JPEG diffuse m10 8x8 | 35,324 | 35,524 | +0.5662% | 1,399 |

Four native PolyCount frames rise from 57,508,371 to 57,566,521 clocks, a cost of 58,150 (+0.1011%). The guard adds 59,866 holds at otherwise-ready admissions. Frame-by-frame deltas are +13,586, +14,930, +14,988 and +14,646 clocks. The cycle-stamped write hashes can change with this intended scheduling cost. Ordered address/control/data hashes and output bytes match. The 104 MHz workload replay uses the existing synthetic memory timing. The four pin modes separately check SDRAM, DMA, and peripheral behavior.

## Private physical 104 MHz lineages

| D-beat verdict | Compare against | Guard candidate |
| --- | --- | --- |
| PARK | Exact two-cut restore `0aeb6c621078bc7006fd455ac24604fd6fa6dbe0` | `0bd02b3ed9df7abc5fbcade1281889ff213b9639` |
| KEEP | Published D beat `0c64862ebd8c5c85830a931c7f68b6b429a32076` | `e35ecb3c788425ceb7de7f757ce2a3f61e31afaf` |

The trees are `c2522f9f74efcd3047bb300f84acc62c1821fe6c` and `ea6fc925cf1ec76fa832b124588b3ed556ec7fc9`. The stacked core exactly matches the standalone guard. Both D-cache modules match D-only, and the shared wrapper's two binds match the two standalones. Three production seed manifests per branch verify 104 MHz DDR-debug-off, 133 selected sources and a generated-CPU-only compiled-source delta from each reference.

[Qualification receipt](../../evidence/v5-104-waw-retire-two-cut.json) · [Route census](../../evidence/v5-104-waw-retire-two-cut-routes.json) · [Fit preflight](../../evidence/v5-104-waw-retire-two-cut-preflight.json) · [Exact patch on prepared D-beat](patches/waw-retire-on-d-beat.patch) · [Stacked qualification](../../evidence/v5-104-waw-retire-on-d-beat.json)

## Reproduction

Run at the repository root with the cached Jotego ARM64 image, the pinned `build/arm9v2-assoc/stock-pinned.v` and the private object chain. The frozen workloads are `build/sim/{payload-clocks,polycount}/v5-104-all-four-ram-candidate` using the `scratch/refill-issue-739d3bd/leg` compile deck. Reuse exact comparison sources and receipts from `build/sim/v5-104-refill-payload-combined` or `build/sim/v5-104-d-completion-merger`, and the physical guest overlays from `build/sim/v5-104-sdram-block-payload`. The D-beat experiment supplies the stacked binder and preflight reference.

Use the original design patch and the [two-cut replay patch](patches/waw-retire-two-cut-replay.patch).

```sh
set -eu
area=scratch/v5-fit-loop/waw-retire-two-cut
prior=scratch/v5-fit-loop/refill-payload-after-a-only/dispatch-20261126
base=ab75a622a80a5aedae347f63ae195f3da965815a
patches=docs/experiments/v5-performance/patches
git apply "$patches/waw-retire-two-cut-replay.patch"
cp "$patches/conservative-w-load-order.patch" "$area/waw-retire-two-cut.patch"
cp "$patches/waw-retire-two-cut-replay.patch" "$area"
mkdir -p "$area/objects" "$area/reference" "$area/source"
printf '%s:%s\n' "$PWD/$prior/objects" "$(cat "$prior/alternate-objects.txt")" > "$area/alternate-objects.txt"
(
    export GIT_INDEX_FILE="$PWD/$area/design.index"
    export GIT_OBJECT_DIRECTORY="$PWD/$area/objects"
    export GIT_ALTERNATE_OBJECT_DIRECTORIES="$(cat "$area/alternate-objects.txt")"
    git read-tree "$base"
    git apply --cached "$area/waw-retire-two-cut.patch"
    git write-tree > "$area/design-tree.sha"
    test "$(cat "$area/design-tree.sha")" = c2522f9f74efcd3047bb300f84acc62c1821fe6c
    for leg in reference source; do
        tree="$base"
        if [ "$leg" = source ]; then tree="$(cat "$area/design-tree.sha")"; fi
        git archive "$tree" Template.sv rtl tools files.qip .rules.verible_format tests sim/programs/link.ld \
            | tar -x -C "$area/$leg"
    done
)
cp "$area/source/rtl/ngage_cpu.sv" "$area/ngage_cpu.sv"
python3 -B "$area/routes.py"
python3 -B "$area/prepare-fit.py"
sh "$area/prepare-stack-replay.sh"
sh "$area/check-generator.sh"
python3 -B "$area/guard-proof.py"
proof=build/sim/v5-104-waw-retire-two-cut/guard-proof
docker run --rm --pull=never --network none --platform linux/arm64 \
    -v "$PWD/$proof:/proof" -w /proof --entrypoint sh jotego/simulator:arm64 \
    -ec 'iverilog -g2012 -s tb -o check tb.v && vvp check' > "$proof/run.log"
for measure in fixed native; do
    python3 -B "$area/replay.py" "$measure" --retained --output retained
done
for entry in waw-retire-two-cut waw-retire-d-beat; do
    variant="scratch/v5-fit-loop/$entry"
    out="build/sim/v5-104-$entry"
    mkdir -p "$out"
    docker image inspect -f '{{.Id}} {{.Os}}/{{.Architecture}}' jotego/simulator:arm64 > "$out/image.id"
    sh "$variant/board.sh"
    sh "$variant/directed.sh"
    for measure in fixed native; do
        python3 -B "$variant/replay.py" "$measure" --output candidate
    done
    sh "$variant/pins.sh"
    sh "$variant/hold.sh"
done
python3 -B "$area/record-qualification.py" standalone
python3 -B "$area/record-qualification.py" stacked
```
