# Use the D-cache hit acknowledgment for trusted W-load ordering

The [design patch](patches/dcache-trusted-hit-ack.patch) applies to retained `11c4a0c32983cc9aba89cae986684558583a33f2`. It also applies to the tuner pilot tree, which changes SDC and timing reporting. The seed 13 tuner pilot’s worst hot setup path starts at D-cache `state_ff[UNC_DONE]` and runs through `o_ack~0`, `s_wait_w_hit~0/1`, `ready_if_hit`, and the ready payload to execute `a[224]`. The measured path has −2.297 ns slack and 11.281 ns data delay. The candidate’s routed timing and area are unmeasured.

## Equivalence

The D-cache FSM, D-cache wrapper, and core carry an additional hit-only ACK. The FSM keeps its existing hit predicate, including hit-under-miss, and adds `UNC_DONE` when forming its original full fast ACK. `o_err_fast` still reports only an uncached error. The normal `request_done`, data, retry, exception, and store paths use the original completion signals.

The one-hot state and live trust register are sampled from the same next state. Reset sets IDLE and trust. The only states that enable trust are next IDLE or one of the three next hit-under-miss states. Therefore, trust excludes `UNC_DONE` after reset. The previous `dcache-live-trust` fixture established one-hot next state across all branch predicates. The extracted cone check verifies that this candidate leaves that FSM logic byte-identical.

In the registered completion path, `request` is already masked by `late_done`. Thus success with live trust is a successful late response, or a request with the hit-only fast ACK. Late error and retry suppress the former. On the latter, the only fast error source is the excluded `UNC_DONE` state. Alignment suppresses the fast hit predicate, so a slow alignment error retains normal precise-abort ordering.

The same wait term also requires `wb_valid`, which depends on the full completion signals through the writeback class and data-abort logic. This candidate evaluates the writeback class locally with success already known. A non-retried, error-free completion permits the same immediate memory response and fast PC hit. A W state of 10 still aborts, block-update errors still use the original path, and CP, wait-for-lock, non-data exceptions, and writeback restore preserve their existing priority. The original writeback expression stays in use for architectural writeback. Assertions compare both the success predicate and the combination of success and W validity on every trusted clock.

The core uses the new input only with explicit `TRUSTED_HIT_ACK` opt-in from the phone top and with `REG_DONE`, `TRUST_FF`, and `COMPLETE_FLAT` active. Alternate parameter combinations use the existing wait expression. The handoff uses the existing storage and completion edges.

## Measured replay

- The extracted reference and candidate cones matched in all 3,170,304 cases. The sweep included normal and error uncached ACKs, alignment and posting gates, hit-under-miss, all late-response outcomes, and all W completion classifications under known success.
- Four ARM9v2 board profiles matched at both wait settings and burst modes. A second guest passed all four profiles, checked the CP15 alignment fault status and preserved destination, and checked a successful younger load to the same destination after an uncached external abort.
- All 105 fixed windows matched the retained clocks, architectural digests, and write traffic. All repeat runs matched, and all 15 wrong-output fixtures failed as intended. The four native frames matched at 14,391,395, 14,467,552, 14,346,201, and 14,303,223 clocks with identical guest output, architectural digests, and write traffic.
- The mixed physical SDRAM and UPP DDR replay matched all 171,496 trace records and 1,201,547 clocks with LCD, PCM, MMC, and both UPP DDR banks active. The CPU netlist was the sole difference across the 114 source hashes.

[Qualification receipt](../../evidence/v5-104-dcache-trusted-hit-ack.json)

## Reproduction

Use the retained payload and native decks staged by the prepared Wishbone write-data experiment, its exact fixed/native JSON receipts, and its physical mixed pin-model source and traffic trace. See `docs/experiments/v5-performance/prepared-wb-write-data.md` for staging. The existing offline simulator image and pinned CPU donor are required.

Run from the repository root. Set `patches` to the archive containing the design and replay patches.

```sh
area=scratch/v5-fit-loop/dcache-trusted-hit-ack
out=build/sim/v5-104-dcache-trusted-hit-ack
patches=docs/experiments/v5-performance/patches
mkdir -p "$area/reference" "$area/source"
for leg in reference source; do
  git archive 11c4a0c rtl tools tests/cpu/arm9v2_board tests/cpu/spmark_payload \
    tests/phone/upp_ddr_ram/peer.v sim/programs/link.ld | tar -x -C "$area/$leg"
done
git apply "$patches/dcache-trusted-hit-ack-replay.patch"
git apply --directory="$area/source" "$patches/dcache-trusted-hit-ack.patch"
cp "$area/source/rtl/ngage_cpu.sv" "$area/ngage_cpu.sv"
for leg in reference source; do
  python3 -B "$area/$leg/tools/gen_arm9v2_phone.py" \
    --stock build/arm9v2-assoc/stock-pinned.v --check
done
python3 -B "$area/prepare-proof.py"
docker run --rm --pull=never --network none --platform linux/arm64 \
  -v "$PWD/$out/proof:/proof" -w /proof --entrypoint sh jotego/simulator:arm64 \
  -ec 'iverilog -g2012 -s tb -o miter tb.sv && vvp miter'
sh "$area/board.sh"
sh "$area/board-phase.sh"
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
cp "$patches/dcache-trusted-hit-ack.patch" "$area/dcache-trusted-hit-ack.patch"
python3 -B "$area/collect-receipt.py"
```
