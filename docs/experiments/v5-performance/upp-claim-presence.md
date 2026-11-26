# Compute UPP claim presence in parallel with priority

The [design patch](patches/upp-claim-presence.patch) changes only `rtl/ngage_upp_peripherals.v` on timer base `9f16d1a5b5bd5b255eb8f0b1a131399b7dcfb56e`, tree `0ccd13d8cd502bc14d3b89c6431ff0ebe4745612`. Candidate tree `dd90394f2bbd952eb8df84fc7df09efcc40b517d` uses the existing 104 MHz DDR build and disabled debugger, with the same CPU netlist, caches, clock constraints and reset distribution. The pinned Verible check passes.

## Routed evidence

The current reset source is the async-assert, clocked-release `reset_drain` introduced at `c8a851f`, with `maxfan=128`. The [route census](../../evidence/v5-104-upp-claim-presence-routes.json) binds the following conclusions to the fitted commits, report ranks, route LUTs and all four sampled corners.

- A-stage-only seed 31337 hot rank 1 is reset drain into request-stage `out_cyc`, timer claim, three selected-owner priority cells, the combined OR, live claim and the registered completion bit. Slack is −3.204 ns and the duplicate valid bit ranks second at −3.198 ns. Both valid paths traverse priority in the cold sample too. Of the hot top 1,000 paths, 632 reset launches fall below −1.5 ns, including 290 to the UPP peripheral subtree.
- That variant's seed 13 hot rank 1 is reset drain into CPU suspension, bridge liveness, LCD pixel take and memory offer, SDRAM line arbitration and the scalar arbiter's wide payload enable. Slack is −3.014 ns to bit 56. There are 135 reset-launched arbiter endpoints below −1.5 ns. The earlier block payload trial `b7cf9fc` already removed that grant-to-data enable and regressed median whole-core setup. This candidate leaves the wide payload architecture alone.
- Joint RAM seed 13 hot rank 1 is reset drain through SDRAM `owner_ready`, the DMA mux response and engine response logic into DMA completion at −3.080 ns. This path directly participates in suppressing replies and owner handoff during reset. The valid, drain and discard qualification on that path stays in place.
- In the retained seed 13 hot sample, 82 paths below −1.5 ns end in the peripheral subtree and launch from reset drain. Of those, 50 end at timers. Peripheral response-valid appears at ranks 61 and 62 from the held request address in that retained fit.

| Exact timer seed | Hot reset paths below −1.5 ns, worst | Hot registered-valid paths below −1.5 ns, worst | Cold registered-valid paths below −1.5 ns, worst |
| --- | --- | --- | --- |
| 13 | 2, −1.819 ns | 2, −1.513 ns | 2, −1.650 ns |
| 43 | 1, −1.517 ns | 1, −1.668 ns | 1, −1.594 ns |
| 31337 | 1, −1.530 ns | 2, −1.867 ns | 2, −1.805 ns |

No sampled timer reset launch ends in the UPP peripheral subtree in the slow corner exports. Timer seed 31337 hot rank 38 passes from `w_cls[3]` through bus liveness, a device claim, selected-owner priority and claim reduction into response valid. Cold rank 34 also traverses selected-owner priority. In the same fit, the fast hot export samples 210 reset-to-UPP endpoints and directly shows reset through that priority chain to response valid at ranks 14 and 15, with +2.848 and +2.849 ns slack. The fast cold export has seven reset-to-UPP samples with worst slack +3.959 ns. Seed 13 slow cold rank 25 goes through extra register storage lookup and ready. The new claim rail cuts the explicit priority family. The readiness path still qualifies valid, and seed 43's valid endpoints sit outside its top 100 detailed paths. These exports are samples of the fitted paths. This private candidate has no measured placement or timing yet.

## Equivalence and reset scope

A single vector contains the 16 existing claim tests, including all lane, direction, enable, and dynamic device qualifications. Its reduction answers whether there is an owner. The same vector still feeds the original priority order, with MMC first, SIMIF next, and then the existing sequence through UART/GPIO and LCD. This identifies which record supplies data and error. When the response record is empty, live claim and valid use presence directly. For a held response, claim still uses the captured owner and live request. A procedural positive test preserves the original treatment of unknown claims in four-state simulation. A pending-but-unready or uncommitted request cannot make a response, and an invalid claimed request still selects its normal error record. An unclaimed request stays unclaimed for the board fault path.

Reset and request withdrawal still clear valid on the original edge. Current request liveness still qualifies outward ready and captured-owner claim. The same live commit and local readiness own the effects, so MMIO writes, DMA reservations and MMC FIFO consumes retain their normal enable. The pending ROM, UPP DDR, MMC and SDRAM transport owners use their original reset and drain logic.

## Replay results

- The source-extracted four-state miter passed 1,185,794 comparisons. It tested every binary claim vector, every mask of unknown claims with no known claim and with a known claim, and varied commit, ready and reset.
- The actual UPP bridge, request stage and peripheral device replay matched two keypad configurations and 311 responses each. Each includes 48 GPIO, 237 UART, 11 simultaneous SIMIF/UART and four NOS ownership samples. It verifies all byte masks and error/reply edges, UART backpressure, canceled requests, warm reset while a response is valid, reset before capture, and cold initialization. Separate matched probes cover unclaimed addresses and invalid timer lanes.
- Integrated flash checks match in both legs for warm and cold reset, old response collision, accepted C and PMM writes, erase and DDR drain. The legacy test stubs were adapted to the current wrapper interface in the scratch fixtures. The UPP DDR and LCD DMA replays also match, including pending writes during warm drain, cold clear and fast LCD cancel after four pixels without a success IRQ.
- Both regular mixed physical traces match exactly. Normal is 171,496 records at 1,201,547 clocks. Timer/MMC/LCD overlap is 171,497 records at 1,201,528 clocks. The separate warm CPU Hold test during a live HPS MMC transfer matches 171,518 records at 1,203,504 clocks. Its PCM hash is the timer's observed warm-hold hash `015ec64f`, while the regular deck continues to require `175ee178`. The HPS warm hold sees five backing reads, one persisted write and all original guest/card output checks.
- The unchanged physical SDRAM transport regression completes a full 16 MiB cold scrub and validates posted write ownership through warm reset, canceled read replies, locked and DMA transactions, and refresh at 104 MHz. The maximum sampled refresh interval is 758 clocks against the fixture limit of 812.
- All 105 fixed windows, all 15 repeated cases and all 15 wrong-output controls, and four native frames match the exact timer outputs, cycles and architectural and bus digests. The native frame counts are 14,391,395, 14,467,552, 14,346,201 and 14,303,223 clocks. The exact modified source fingerprint is present in fixed, native, regular mixed and warm-hold compilations.

[Qualification receipt](../../evidence/v5-104-upp-claim-presence.json)

## Reproduction

Use the cached Jotego ARM64 simulator, the frozen fixed/native inputs under `build/sim/{payload-clocks,polycount}/v5-104-all-four-ram-candidate`, the compile deck `scratch/refill-issue-739d3bd/leg`, the prepared Wishbone reference receipts and the exact timer replays under `build/sim/v5-104-timer-write-prepare`. The timer mixed deck provides the cached physical memory model and expected traffic. The modified bench for warm Hold uses the same guest images and a matched trial/reference build. The archived `peripheral-lane13.patch` supplies the common held UPP overlap test, with only its experimental interface predecode removed from the copied test.

Run from the repository root with the design patch and [replay patch](patches/upp-claim-presence-replay.patch). The private timer object chain supplies the exact base. The route script reads the original timer, A-only, joint RAM and retained runs under `build/timing-audit-*/output_files`.

```sh
set -eu
area=scratch/v5-fit-loop/upp-claim-presence
timer=scratch/v5-fit-loop/timer-live-trust-combined/dispatch-20261126
base=9f16d1a5b5bd5b255eb8f0b1a131399b7dcfb56e
patches=docs/experiments/v5-performance/patches
git apply "$patches/upp-claim-presence-replay.patch"
cp "$patches/upp-claim-presence.patch" "$patches/upp-claim-presence-replay.patch" "$area"
mkdir -p "$area/objects" "$area/reference" "$area/source"
printf '%s:%s\n' "$PWD/$timer/objects" "$(cat "$timer/alternate-objects.txt")" > "$area/alternate-objects.txt"
(
    export GIT_INDEX_FILE="$PWD/$area/design.index"
    export GIT_OBJECT_DIRECTORY="$PWD/$area/objects"
    export GIT_ALTERNATE_OBJECT_DIRECTORIES="$(cat "$area/alternate-objects.txt")"
    test "$(git rev-parse "$base^{tree}")" = 0ccd13d8cd502bc14d3b89c6431ff0ebe4745612
    git read-tree "$base"
    git apply --cached "$area/upp-claim-presence.patch"
    git write-tree > "$area/design-tree.sha"
    test "$(cat "$area/design-tree.sha")" = dd90394f2bbd952eb8df84fc7df09efcc40b517d
    for leg in reference source; do
        tree="$base"
        if [ "$leg" = source ]; then tree="$(cat "$area/design-tree.sha")"; fi
        git archive "$tree" rtl tools files.qip .rules.verible_format tests sim/programs/link.ld \
            | tar -x -C "$area/$leg"
    done
)
cp "$area/source/rtl/ngage_cpu.sv" "$area/ngage_cpu.sv"
sh "$area/claim-miter.sh"
sh "$area/directed.sh"
sh "$area/flash-reset.sh"
sh "$area/sdram-drain.sh"
sh "$area/mixed.sh"
for kind in fixed native; do
    python3 -B "$area/replay.py" "$kind" --output qualification
done
python3 -B "$area/routes.py"
python3 -B "$area/record.py"
```
