# Register D-cache line admission

The [design patch](patches/d-line-admission.patch) changes only `rtl/ngage_cpu.sv` on timer commit `9f16d1a5b5bd5b255eb8f0b1a131399b7dcfb56e`, tree `0ccd13d8cd502bc14d3b89c6431ff0ebe4745612`. The candidate tree is `27b2fe1957188d905a4a61e0e1a3be92367ce34c`. The ARM9v2 wrapper statically selects the D-line stage when native lines are enabled. The refill module's new parameter defaults to the original direct behavior for standalone callers. Both 16 KiB caches, the CPU netlist, 104 MHz clock, scheduler, DDR debug setting and timing constraints retain their timer values. The pinned Verible format check passes.

The new stage captures a valid bit and the aligned address on the first eligible D-line clock. Pending valid and address directly drive the D term in `line_req` and `line_addr`. Its late grant no longer rechecks donor CYC, classifier, address or lock. Instruction lines retain their live grant term. Scalar WB CYC is withheld on the D capture edge and throughout the pending and accepted line. The request can go directly to the existing board RAM preview on its next clock. Backpressure keeps the register valid and the address stable until board acceptance. Relative to the acceptance edge, existing rejection, scalar fallback, error handling, and first and following word ACKs use the original refill logic.

## Held owner before board grant

The production induction uses the emitted CPU's three arbitration levels:

1. In `ngage2_zap_dcache_fsm`, a native candidate requires `FETCH_SINGLE`, `saved_fill_region`, zero `adr_ctr_ff` and no `take`. The pending address uses `phy_addr` captured in IDLE. In the FETCH_SINGLE case aliases, interrupted CPU issue, abort/flush and CP15 activity do not change the transaction. The counter advances only on `take = o_wb_stb_ff && (i_wb_ack | i_wb_err)`. Without that response the first beat keeps STB and CYC, and the fixed address, byte lanes and burst CTI.
2. In `ngage2_zap_dcache`, high `o_wb_line_candidate_nxt` requires `state_nxt == SELECT_CCH`. After the selection edge, while STB is high and ACK and ERR are low, `state_nxt` holds. The CYC and STB next expressions use `state_ff & wb_cyc` and `state_ff & wb_stb` for this leg. Any newly eligible posted store, TLB walk or cache maintenance cannot change owners before that reply.
3. At the shared `ngage2_zap_wb_merger`, `state_ff == 1` owns the D beat and produces `wb_code == 0`. D retains arbitration while `i_d_wb_stb` stays asserted unless `(i_wb_ack | i_wb_err) && o_wb_cti == CTI_EOB` also permits switching. Hence Instruction CYC cannot take the port during this D burst's unacknowledged first beat. The final wrapper exports `bus_req = wb_cyc & wb_stb` from the same registered packet.

The capture edge already suppresses the scalar request, so it clears the registered scalar offer bit. Every pending clock consequently has neither a scalar request nor a matching scalar response. The simulation assertion enforces IDLE refill state, live donor CYC, D owner, original classifier and exact aligned address for every non-reset pending edge. The same reset reaches the donor and refill wrapper and immediately masks the board request.

The W-stage SWP lock is independent of the held CCH/merger arbitration. A lock already live at initial eligibility excludes native capture. A younger SWP appearing after the D capture is held behind that owned refill, as it would be after the original earlier LINE grant. Pending and active states mask its external lock until the refill retires. The directed fixture tests both orderings and checks that scalar lock and cancellation retain their original behavior.

## Routed evidence on the timer source

The D capture structurally splits live donor validity and address from the D term in the later board RAM/ROM decode and SDRAM early preview. Instruction eligibility and shared scalar release still have their existing live paths. The timer reports give no demonstrated hot D-only admission path along that prospective boundary.

| Seed and hot rank | Observed route |
| --- | --- |
| 13 rank 34, −1.716 ns | D TLB physical address bit 29 into existing merger `o_wb_line_candidate`. This endpoint precedes the new stage. |
| 13 rank 18, −1.830 ns | `w_cls[3]` through `line_req~1`, then `bus_live`, `bus_access`, `fast_cancel`, `mem_req` and `response_dma` into the uncached scalar DMA reservation. A line-control LUT participates on the scalar path. |
| 43 rank 1, −2.403 ns | Retimed `cpu_ack~1_OTERM10890` through refill return ACK and cache next-packet logic to merger `o_wb_adr[6]`. |
| 31337 rank 3, −2.214 ns | Native `received[4]` through return ACK and cache next-packet logic to merger `o_wb_adr[17]`. |
| 31337 rank 40, −1.867 ns | Native LCD `cursor[7]` into scheduler `cmd_addr[17]`. |

Across the four corner exports per seed, the sampled `o_wb_line_candidate` launches end in scalar-conditioned DMA/UPP/ICU logic. The 104 MHz DDR-debug-off timer manifests each pin 133 production files. The staged patch replaces only the wrapper bytes among those files. Candidate routed timing and area remain open.

## Qualification

- The Icarus differential passed 3,625 checks for registered scalar and 3,615 for same-edge scalar. Each exercised 105 native lines, 53 line errors, 57 staged D offers, 52 withheld-ready clocks, pending reset, the original narrow/wide assembly, rejection and scalar fallback. The original default and disabled-line selections passed their replay checks.
- All four CPU-board profiles matched line counts, fault cases, SWP, cache cleaning and scalar wait clocks. Total execution added 524 clocks in each profile; individual cycle values are preserved in the logs.
- All 105 fixed windows, 15 repeat cases and 15 deliberate wrong-output checks passed. All four native outputs and all 109 architectural summaries match. Acknowledged Wishbone write counts by class match, while the write observer's clock-inclusive digests can change with this experiment.
- Native PolyCount adds 30,030 clocks over 57,508,371 across four frames, or +0.052218%. Sega scan's warm median adds 5,101 clocks (+0.213%). Full-frame 16-bit fill adds 176, Asphalt table 20 and Asphalt double 3. Matrix adds −9 and triangles −6. Nine warm medians tie. All window and frame differences are in the receipt.
- The normal and timer/MMC/LCD physical regressions match 171,496 and 171,497 records byte for byte, with the exact candidate wrapper as the sole difference among 114 compiled model sources. Those two historical mixed decks wire off the CPU native line port. Their checked MMC, PCM, SWP, LCD and scalar SDRAM behavior is independent of contact on the new native D stage.

The separate 36-phase native D/LCD sweep connects the exact refill module to a retained RAM-preview/held-address ingress followed by the production LCD/CPU line mux, SDRAM stream, scheduler, DDIO and cached physical Micron model at 104 MHz. A synthetic legal first D beat competes with one 16-byte LCD line. Each pair starts from a refreshed closed bank and samples a different relative LCD offset away from or near refresh. The bench checks distinct data sequences for all eight D words and eight LCD halfwords per phase. Twenty-four cases include a runtime auto-refresh.

| Change to D first and final ACK | Number of phases |
| --- | ---: |
| 0 clocks | 21 |
| +1 clock | 12 |
| +15, +16, +27 clocks | 1 each |

The three larger cases occur when LCD appears one clock after D and sees the staged D offer for the first time. The retained mux preference lets LCD win that arbitration, moving its grant 25, 25 or 28 clocks earlier. The +27 D case also crosses refresh. These are bounds observed in the sampled isolated traffic patterns. The measured 36 pairs use the same pin model and clocks in both legs.

[Qualification receipt](../../evidence/v5-104-d-line-admission-production.json)

## Reproduction

Run from the repository root with the private timer object chain, design patch and [replay patch](patches/d-line-admission-replay.patch). The cached `jotego/simulator:arm64` image has digest `sha256:df6f55924d5fab96083d01332e45cd734f22277c4dd3b34f55a09cd8dbc3eb8d`. The frozen workload inputs are under `build/sim/{payload-clocks,polycount}/v5-104-all-four-ram-candidate` and the compile deck is under `scratch/refill-issue-739d3bd/leg`. The timer qualification directory `build/sim/v5-104-timer-write-prepare` supplies architectural receipts, the authored physical guest, Micron and DDIO models, and prior pin traces. The route collector reads original timer controls 45824513460, 45824520116 and 45824525843.

```sh
set -eu
area=scratch/v5-fit-loop/d-line-admission
timer=scratch/v5-fit-loop/timer-live-trust-combined/dispatch-20261126
out=build/sim/v5-104-d-line-admission
base=9f16d1a5b5bd5b255eb8f0b1a131399b7dcfb56e
patches=docs/experiments/v5-performance/patches
git apply "$patches/d-line-admission-replay.patch"
cp "$patches/d-line-admission.patch" "$patches/d-line-admission-replay.patch" "$area"
mkdir -p "$area/objects" "$area/reference" "$area/source" "$out"
printf '%s:%s\n' "$PWD/$timer/objects" "$(cat "$timer/alternate-objects.txt")" > "$area/alternate-objects.txt"
(
  export GIT_INDEX_FILE="$PWD/$area/design.index"
  export GIT_OBJECT_DIRECTORY="$PWD/$area/objects"
  export GIT_ALTERNATE_OBJECT_DIRECTORIES="$(cat "$area/alternate-objects.txt")"
  test "$(git rev-parse "$base^{tree}")" = 0ccd13d8cd502bc14d3b89c6431ff0ebe4745612
  git read-tree "$base"
  git apply --cached "$area/d-line-admission.patch"
  git write-tree > "$area/design-tree.sha"
  test "$(cat "$area/design-tree.sha")" = 27b2fe1957188d905a4a61e0e1a3be92367ce34c
  for leg in reference source; do
    tree="$base"
    if [ "$leg" = source ]; then tree="$(cat "$area/design-tree.sha")"; fi
    git archive "$tree" rtl tools .rules.verible_format tests/cpu/arm9v2_board \
      tests/cpu/spmark_payload tests/phone/upp_ddr_ram/peer.v tests/phone/direct_sdram \
      tests/phone/upp_bus_bridge sim/programs/link.ld | tar -x -C "$area/$leg"
  done
)
cp "$area/source/rtl/ngage_cpu.sv" "$area/ngage_cpu.sv"
docker image inspect -f '{{.Id}} {{.Os}}/{{.Architecture}}' jotego/simulator:arm64 > "$out/image.id"
sh "$area/directed.sh"
sh "$area/board.sh"
sh "$area/lcd-phase.sh"
for kind in fixed native; do
  python3 -B "$area/replay.py" "$kind" --output qualification
done
python3 -B "$area/mixed.py"
mixed="$out/mixed"
docker run --rm --pull=never --network none --platform linux/arm64 \
  -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 \
  -ec "sh '$mixed/build.sh'
       '$mixed/obj/Vtb' +upp_stress '+compare_trace=$mixed/traffic.log' > '$mixed/replay.log'"
sh "$area/coexistence.sh"
python3 -B "$area/record.py"
```
