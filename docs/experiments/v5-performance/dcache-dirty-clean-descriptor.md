# Preselect the D-cache dirty-clear descriptor

The [design patch](patches/dcache-dirty-clean-descriptor.patch) applies to the exact retained timer base `9f16d1a5b5bd5b255eb8f0b1a131399b7dcfb56e`, tree `0ccd13d8cd502bc14d3b89c6431ff0ebe4745612`. It changes the ARM9 generator and its emitted D-cache-only half-tag RAM. The pinned generator check passed in both legs.

## Timing witness

At physical 104 MHz, timer seed 13 hot rank 1 starts at merger `o_wb_cyc`. It passes through `bus_req~0`, refill `cpu_ack~3`, and `tag_ram_clean~0`, then through `g_metadata[0].g_dirty.update_group[2]~2`, `Mux116~0`, and the final dirty byte-lane enables. It ends at `ram_block1a64~porta_bytena_reg2` with −2.168 ns slack and 11.003 ns data delay. Rank 2 ends at another dirty byte-lane register at −2.162 ns.

The 1,000-path exports contain 56, 55, 32, and 15 paths from that merger CYC to dirty RAMs across the four seed 13 corners. The same endpoint and launch filter yields zero on timer seeds 43 and 31337. The new condition removes completion from descriptor selection. The same completion still drives effective lane write enable, read enable, and forwarding capture. In RTL the ACK can reach the final enable without travelling through the selected group address or its initialization-bit lookup. The actual routed improvement and any change to store-side timing require a fit.

## Sequential equivalence

The pending dirty-store packet is captured on the ordinary tag write edge. Reset clears `pend_en`. The IDLE branch is the only legal state that can raise `tag_ram_wr_en`. Its three departures, global clean, global invalidate and line maintenance, all clear `tag_ram_wr_en` before entering any other state. The other legal states keep its default zero. Since the pending enable samples it on the same edge as the next state, an active pending store implies IDLE after reset. In particular, maintenance clean-send and line-done cannot see a pending store.

When the dirty write enable is true, there are two possible owners. With a pending store, the original and new selectors use the same registered address, way and dirty fields. With a clean or invalidation commit, both use the held `rd_flat_ff` set and way with a zero dirty mask. The no-write cycle may now carry the held descriptor. Any forwarded dirty update or collision sampled on that cycle is disabled. During a hold the captured group, update and collision registers all keep their old values. Thus the address can differ only while the RAM write and all comparisons that expose that captured address are inactive.

Dirty-group scan, lookahead and read enables retain their existing clocks and conditions. The I-cache tag RAM is a different module. The patch uses the existing storage, states and cycle boundaries. For this production path the Wishbone merger sends both ACK and ERR to the selected owner's completion input. A real final ERR therefore retires the maintenance writeback on the same tag edge as a final ACK. The modified fixture models that existing behavior and suppresses the rejected backing write.

## Qualification

- The source-extracted write-lane miter checked 163,840 cases at the production geometry. It compared the active descriptor and all 32 way/byte lane enables and data, across held sets/ways, dirty half masks, uninitialized-bank clearing, clean, line clear, and no-write cycles.
- Four exact ARM9v2 board traces matched. All eight added CP15 profiles also matched, with scalar and native refill modes, peer waits of zero and five, a repeated clean of the same line, and separate final ACK and final ERR runs. Each final beat spent two or seven cycles stalled, then completed exactly once. The same guest also checks clean-all, the empty post-clean scan, low/high/both dirty halves, line and index invalidation, and cache associativity.
- All 105 fixed windows matched the timer controls with 15 repeats and 15 expected wrong-output failures. The four native frames matched at 14,391,395, 14,467,552, 14,346,201, and 14,303,223 clocks with identical architectural, guest-output and valid-write digests.
- The normal pin replay matched all 171,496 records at 1,201,547 clocks. Timer/MMC/LCD overlap matched all 171,497 records at 1,201,528 clocks. The same candidate CPU fingerprint was compiled for board, fixed, native and both pin-model replays, and the CPU was the sole source difference from the timer pin deck.

[Qualification receipt](../../evidence/v5-104-dcache-dirty-clean-descriptor.json)

## Qualification on the compact-lock variant

The [standalone descriptor](patches/dcache-dirty-descriptor-on-timer.patch) and the [descriptor on compact lock](patches/dcache-dirty-descriptor-on-compact.patch) both pass the same board, CP15, fixed, native and physical pin replays. Each exact candidate also passes the dirty-lane miter and the 1,281-cycle critical refill abort and reset fixture. The generated combined CPU contains the four tested compact-lock modules and the tested dirty half-tag RAM byte-for-byte. Production preflight selects 133 inputs, with only the emitted CPU changed from each control. DDR debugging is off at physical 104 MHz.

- [Standalone receipt](../../evidence/v5-104-dcache-dirty-descriptor-on-timer.json)
- [Compact-lock combination receipt](../../evidence/v5-104-dcache-dirty-descriptor-on-compact.json)
- [Exact candidates and all three seeds' preflight checks](../../evidence/v5-104-dcache-dirty-compact-preflight.json)
- [Combined replay fixture](patches/dcache-dirty-compact-combined-replay.patch)

## 104 MHz fit

The compact lock fits were parked. The standalone descriptor `dbad302`
was dispatched on the exact timer restore `da03b02`. Its matched control
is timer-only `9f16d1a`. The design uses the production 104 MHz clock
with DDR debugging off. [Seed 13](https://github.com/asturur/test_template_1/actions/runs/45850041608) · [Seed 43](https://github.com/asturur/test_template_1/actions/runs/45850046593) · [Seed 31337](https://github.com/asturur/test_template_1/actions/runs/45850051512)

## Routed decision

Park `dbad302`. All three fits pass the native hold, recovery, removal,
minimum pulse and SDRAM pin checks, and all three miss 104 MHz setup.

| Seed | Worst setup, timer → descriptor | Core TNS delta | Occupied ALM delta | Estimated ALMs needed delta |
| ---: | ---: | ---: | ---: | ---: |
| 13 | −2.214 → −3.104 ns | −3,626.369 ns | +259 | −762 |
| 43 | −2.403 → −2.583 ns | −1,947.139 ns | +302 | −740 |
| 31337 | −2.452 → −2.648 ns | −2,290.485 ns | +211 | −658 |

The former merger CYC launch to any dirty RAM destination leaves the
four corner samples. On timer seed 13 there had been 65 hot and 64 cold
matches to that wider endpoint filter. Core median setup falls by 0.245 ns
and median TNS worsens by 2,290.485 ns. Actual median occupancy rises by
259 paired ALMs, while the median paired estimate falls by 740. All builds
retain 321 M10Ks. The new limiting paths end in the execute packet, the
Wishbone merger address, and the D-cache lock-valid register.
[Matched fits and path census](../../evidence/v5-104-dcache-dirty-descriptor-fits.json)

## Reproduction

Run from the repository root using the prior private timer objects, pinned donor, prepared Wishbone workloads, and already-qualified timer pin and overlap decks. The ARM GNU tools and cached Jotego ARM64 image supply the directed tests. Set `patches` to the archive containing the design and fixture patches.

```sh
area=scratch/v5-fit-loop/dcache-dirty-clean-descriptor
patches=docs/experiments/v5-performance/patches
timer=scratch/v5-fit-loop/timer-live-trust-combined/dispatch-20261126
out=build/sim/v5-104-dcache-dirty-clean-descriptor
for leg in reference source; do
  mkdir -p "$area/$leg"
  env GIT_OBJECT_DIRECTORY="$PWD/$timer/objects" \
    GIT_ALTERNATE_OBJECT_DIRECTORIES="$(cat "$timer/alternate-objects.txt")" \
    git archive 9f16d1a5b5bd5b255eb8f0b1a131399b7dcfb56e rtl tools \
      tests/cpu/arm9v2_board tests/cpu/spmark_payload tests/phone/upp_ddr_ram/peer.v \
      tests/phone/timers sim/programs/link.ld | tar -x -C "$area/$leg"
done
git apply "$patches/dcache-dirty-clean-descriptor-replay.patch"
git apply --directory="$area/source" "$patches/dcache-dirty-clean-descriptor.patch"
cp "$patches/dcache-dirty-clean-descriptor.patch" "$patches/dcache-dirty-clean-descriptor-replay.patch" "$area"
cp "$area/source/rtl/ngage_cpu.sv" "$area/ngage_cpu.sv"
for leg in reference source; do
  python3 -B "$area/$leg/tools/gen_arm9v2_phone.py" \
    --stock build/arm9v2-assoc/stock-pinned.v --check
done
python3 -B "$area/prepare-metadata-proof.py"
docker run --rm --pull=never --network none --platform linux/arm64 \
  -v "$PWD/$out/proof:/proof" -w /proof --entrypoint sh jotego/simulator:arm64 \
  -ec 'iverilog -g2001 -s tb -o miter tb.v retained.v trial.v
       vvp miter > miter.log
       grep "^PASS dirty metadata lane comparisons=" miter.log'
sh "$area/board.sh"
sh "$area/cp15-phase.sh"
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
