# Prepare D-cache completion beats beside the count

This private trial uses the 104 MHz DDR-debug-off two-cut baseline `ab75a622a80a5aedae347f63ae195f3da965815a` and tree `57cc1a796acc9b15a61522ccf2397230f38e9799`. It clocks six flags beside the existing D-cache beat count. Those flags describe held and following availability for scalar dirty writeback, native block writeback and read fill. Dirty writeback and read fill each select their prequalified held or next address with the original D ACK/ERR. CYC, STB, data, byte enables, CTI, line eligibility, reset and I/D ownership use the existing edge. The retained capture path remains the default for generic D-cache callers. The 32-byte D-cache instance inside the donor explicitly enables this option. Bound test observers verify the active parameter in the actual compiled hierarchy.

## Exact route family and earlier attempts

| Seed and corner | Slack | Rank and family |
| --- | ---: | --- |
| 13 slow hot | −1.978 ns | Rank 2, stream `WRITE_LOCKED` through D-cache take to merger address bit 9 |
| 13 slow cold | −1.984 ns | Rank 2, stream `seen` through the same D path |
| 43 slow hot | −2.509 ns | Rank 2, scheduler readiness through common ACK to I-cache request and merger address bit 15 |
| 43 slow cold | −2.463 ns | Rank 2, stream `seen` through the same I path |

The seed 13 routed copies start at stream ACK, pass D-cache FSM `take~1` and `o_wb_cyc_nxt~2`, pass the D-cache `o_wb_stb_nxt~3` copies and enter the merger's shared address-selection cells. At RTL `take` requires the held local strobe and its owner qualified ACK or ERR. In `CLEAN_SINGLE` the original expression selects the next count then compares with the scalar/half/native-block bound. In `FETCH_SINGLE` the original hold/advance validity uses the full line count. The resulting D-cache CYC/STB controls the parent D-cache owner's eligible request map and can reach the outer I/D selection through both request presence and incumbent retirement. The old uncached strobe has a separate direct withdrawal arm. Fitted cells reveal the shared structural cone and do not identify which guest transaction was in flight on a worst-case static timing path.

Across each slow top-100 detailed sample, seed 13 has 6 hot and 9 cold D-side strobe paths from the stream ACK to merger address, with 3 and 5 below −1.5 ns. Seed 43 has 23 hot and 25 cold common-I paths below −1.5 ns. Both seed 13 and 31337 have zero such I-side paths across all four detailed corners. The older split reply patch targets the I-side dependency, did cut it on its previous baseline and increased area by 685 median ALMs there. Its port is parked. The earlier I/D strobe trial precompared current and next counts using combinational logic. The prepared flags in this trial cross the existing local counter register. The earlier I/D address experiment moved the final owner mux after capture. This trial keeps the merger's address output register.

## Same-edge proof and remaining paths

On each clock, the flag logic sees exactly the value that becomes `adr_ctr_ff`, including the terminal-clean zero, reset zero, first victim word and modulo counter wrap. It also sees exactly the high-half bit that becomes `victim_halves[1]`, taking it from the cache offer in IDLE and from the saved victim elsewhere. The two CLEAN bound pairs consider both +1 and +4 increments. The current live block geometry selects between the already clocked pairs, so even changes in `i_block_enable` retain the original classification. The FETCH pair uses the full-line +1 count. Current hold and successor addresses remain computed from the original address and saved metadata. The early availability bits qualify each address with zero in the invalid case.

An initially considered shortcut using the held CTI has a boundary exception. After terminal FETCH, the count can be 8. In `UNLOCK_REG`, the original first-clean CTI computes the block region from that older offset. At the last 0x0a line, this can classify address +32 in 0x0b while the first high-half eviction is again in 0x0a. The numerical flags follow the new count and live block target directly and preserve the original separate CTI logic. Generic widths keep the original functional default. The optional hinted-LDM generator emits its original bytes.

The observed ACK still drives `take`, the new local result mux and the existing D owner and I/D handoff. Other scalar or uncached request/response conditions, posted FIFO, tag-maintenance and TLB remain on the existing logic. `take` also feeds `adr_ctr_nxt` and can now reach the D of the new flags through the short next-count comparisons. The new register and smaller local strobe path exchange those destinations. Setup and hold after routing remain unmeasured.

## Qualification and identification

The arithmetic model checks 61,440 outcomes over all count values, four line sizes, both dirty-half geometries, both reply choices and four address boundaries. The asserted paired CCH fixture exercises accepted ACK, accepted ERR and an ERR with no strobe during scalar and block clean, fill and handoff. The board phases check eight ordinary and precision profiles. The 10 extra write-bus profiles cover scalar and native dirty eviction, stalled retirement and last-beat handoffs. Each reset profile waits for a stalled D-cache victim packet. The board peer reinitializes test RAM and per-boot checks before the restarted guest. The physical warm-Hold test covers the separate persistent backing-store case.

Each workload leg checks 105 fixed windows, 15 repeats, 15 expected wrong-output rejections and four native frames against its exact comparator. The four physical modes check 171,496 normal records, 171,497 timer/MMC/LCD records, 172,060 block-eviction records and 171,518 warm-Hold records. The actual source digests and bind activity are stored in the per-leg qualification receipts. The physical block fixture observes the new path in active native writeback as well as in read fill.

| W outcome | Private commit | Tree | Comparison |
| --- | --- | --- | --- |
| PARK | `0c64862ebd8c5c85830a931c7f68b6b429a32076` | `6dd7930e0036b06f2513d0e8ade7c994e55d2048` | Exact two-cut tree after restore `5a30e26583f81c4cd2415672f9f8bbfb6ed767d6` |
| KEEP | `4a53b1f1e9786ad413712ddd80fb74feeb85d387` | `904182b9d49bd676c09def999abafa45a188f057` | W completion `e2249e46c0bd47ab85539cff9416a51214c1ea05` |

The combined generator shares a call-site diff hunk with W, so the staging helper composes the exact two transform definitions and calls. The combined output's W core is byte-identical to W-only. Its D FSM, D cache and binding wrapper are byte-identical to D-only. Three production seeds per branch pass the exact 133-input preflight at 104 DDR debug off. The CPU netlist is the only compiled-source difference from either selected reference.

[Design patch](patches/d-completion-merger.patch) · [Replay patch](patches/d-completion-merger-replay.patch) · [Qualification receipt](../../evidence/v5-104-d-completion-merger.json) · [Route census](../../evidence/v5-104-d-completion-merger-routes.json)

[Fit manifests](../../evidence/v5-104-d-beat-preflight.json) · [Exact patch on W](patches/d-beat-on-w.patch) · [Combined receipt](../../evidence/v5-104-d-beat-on-w.json)

## 104 MHz fit

The W candidate was parked. The D-cache-only preparation `0c64862` builds
above exact restore `5a30e26` of the `ab75a62` combined tree, at physical
104 MHz with DDR debug off. [Seed 13](https://github.com/asturur/test_template_1/actions/runs/45893161445) · [Seed 43](https://github.com/asturur/test_template_1/actions/runs/45893165422) · [Seed 31337](https://github.com/asturur/test_template_1/actions/runs/45893169984)

## Routed decision

Park `0c64862`. The published `8da70c9` restores the exact `ab75a62` tree.
No workflow ran on the restore. [Restore receipt](../../evidence/v5-104-pause-restore.json)
Hold, recovery, removal, minimum pulse width and SDRAM
pin register packing pass on all three seeds. All fail 104 MHz setup.

| Seed | Worst setup, base → prepared beat | Core TNS, base → prepared beat | Occupied ALMs, base → prepared beat | Estimated ALMs needed, base → prepared beat |
| ---: | ---: | ---: | ---: | ---: |
| 13 | −2.006 → −3.139 ns | −2,674.880 → −7,773.317 ns | 38,867 → 38,849 | 37,215 → 36,291 |
| 43 | −2.636 → −2.995 ns | −5,121.630 → −7,429.893 ns | 38,725 → 38,866 | 37,134 → 36,307 |
| 31337 | −2.902 → −2.723 ns | −6,815.895 → −8,579.607 ns | 38,716 → 38,961 | 37,189 → 36,350 |

The sampled hot SDRAM ACK to D-cache to merger-address family drops
from 19/0/3 to zero on seeds 13/43/31337. The new beat flags do not appear
in the hot top-1,000 endpoints. Seed 31337 setup improves by 0.179 ns,
while the best control seed regresses by 1.133 ns. Median setup falls
0.359 ns and median TNS worsens by 2,651.687 ns. The paired median TNS
delta is −2,308.263 ns. Estimated ALMs needed fall by 839 at the paired
median while physical occupancy rises by 141. All builds keep 321 M10Ks.
The revised limiting paths end in D-cache lock validity, Wishbone merger
address and DMA error. [Matched fit reports](../../evidence/v5-104-d-completion-merger-fits.json)

## Reproduction

Use the private retained object chain, pinned donor `build/arm9v2-assoc/stock-pinned.v` and the cached Jotego ARM64 image. The frozen workload decks are in `build/sim/{payload-clocks,polycount}/v5-104-all-four-ram-candidate`, with the original compile deck under `scratch/refill-issue-739d3bd/leg`. The standalone comparison and pin inputs come from `build/sim/v5-104-refill-payload-combined`. The stack uses the sealed W completion receipts in `build/sim/v5-104-w-completion-prepare` and the private W dispatch object chain. Guest overlays live under `build/sim/v5-104-sdram-block-payload`.

Run from the repository root. The replay patch supplies the fixture scripts and staged-source digest. Place both patches into the trial area before rebuilding an empty stage.

```sh
set -eu
area=scratch/v5-fit-loop/d-completion-merger
prior=scratch/v5-fit-loop/refill-payload-after-a-only/dispatch-20261126
base=ab75a622a80a5aedae347f63ae195f3da965815a
patches=docs/experiments/v5-performance/patches
git apply "$patches/d-completion-merger-replay.patch"
cp "$patches/d-completion-merger.patch" "$patches/d-completion-merger-replay.patch" "$area"
mkdir -p "$area/objects" "$area/reference" "$area/source"
printf '%s:%s\n' "$PWD/$prior/objects" "$(cat "$prior/alternate-objects.txt")" > "$area/alternate-objects.txt"
(
    export GIT_INDEX_FILE="$PWD/$area/design.index"
    export GIT_OBJECT_DIRECTORY="$PWD/$area/objects"
    export GIT_ALTERNATE_OBJECT_DIRECTORIES="$(cat "$area/alternate-objects.txt")"
    git read-tree "$base"
    git apply --cached "$area/d-completion-merger.patch"
    git write-tree > "$area/design-tree.sha"
    test "$(cat "$area/design-tree.sha")" = 6dd7930e0036b06f2513d0e8ade7c994e55d2048
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

for entry in d-completion-merger d-completion-w-prepare; do
    variant="scratch/v5-fit-loop/$entry"
    out="build/sim/v5-104-$entry"
    mkdir -p "$out"
    docker image inspect -f '{{.Id}} {{.Os}}/{{.Architecture}}' jotego/simulator:arm64 > "$out/image.id"
    sh "$variant/check-generator.sh"
    python3 -B "$area/check-beat-arithmetic.py" > "$out/arithmetic.log"
    sh "$area/beat-errors.sh" "$entry"
    sh "$variant/board.sh"
    sh "$variant/board-phase.sh"
    sh "$variant/board-write.sh"
    python3 -B "$variant/replay.py" fixed --output qualification
    python3 -B "$variant/replay.py" native --output qualification
    sh "$variant/pins.sh"
    sh "$variant/hold.sh"
done
python3 -B "$area/record.py" standalone
python3 -B "$area/record.py" stacked
```
