# Timer-write and D-cache live-trust fit candidates

Timer-write preparation and D-cache live trust compose in either patch order from retained `11c4a0c`. The original measured hashes match all seven edited files. Only the timer patch’s three RTL files and two compatibility testbench edits are new in either candidate commit.

| Candidate | Commit | Parent |
| --- | --- | --- |
| Forward restore | `d211fe8d25abf13968f36c208eee3729efb1ddd7` | `f6ae7f67642cabfb62aac9ead7ab955f14594bbb` |
| Timer only | `9f16d1a5b5bd5b255eb8f0b1a131399b7dcfb56e` | `d211fe8d25abf13968f36c208eee3729efb1ddd7` |
| Timer with live trust | `ebbc3a455ed27fc5215cb7dbe839c0c196f72577` | `f6ae7f67642cabfb62aac9ead7ab955f14594bbb` |

The forward restore has tree `8406276acdc60d658e189d09d31b0699217717ba`, which matches both `11c4a0c` and `e9552bd`. The candidate objects and indexes are private. Their parents and selected inputs are recorded in `dispatch-20261126/prepare.json`.

Both candidates use the production physical 104 MHz PLL and DDR debugger off. At seeds 13, 43, and 31337, preflight reconstructs the effective QSF and verifies all 133 selected-source hashes against controls 45771268571, 45771267820, and 45771266151. The timer-only build changes three selected sources. The combined build also selects the changed generated CPU netlist. The QSF byte hash reproduces the runner’s rewrite of the Quartus version line. The private candidates await routed fits.

## Combined replay

- All 8,192 directed timer decode vectors matched across 6,025 replies and 41,235 clocks. Timer unit, request-stage, register RAM, peripheral response, and timer/ICU conformance checks passed. The four original NEM-4 instruction profiles matched at dividers 3 and 4 with zero and three waits.
- The four ARM9v2 board contract traces matched. All 105 fixed windows matched cycle counts and the architectural and Wishbone trace digests. All 15 repeats and negative-output checks matched. Native PolyCount matched at 14,391,395, 14,467,552, 14,346,201, and 14,303,223 clocks with identical guest output.
- The exact physical replay matched 171,496 events over 1,201,547 clocks. The timer/MMC/LCD overlap replay matched 171,497 events over 1,201,528 clocks. Verilator selected the same four measured changed RTL hashes in fixed, native, and both physical pin replays.

[Qualification receipt](../../evidence/v5-104-timer-live-trust-combined.json)

## Reproduction

Run from the repository root using the [combined replay patch](patches/timer-live-trust-combined-replay.patch). The route preflight expects the prior live-trust dispatch object directory and its alternates. The replay uses the existing prepared Wishbone write-data decks and the original timer instruction data previously staged from the pinned ROM. Both inputs are described in `docs/experiments/v5-performance/timer-write-prepare.md`.

```sh
area=scratch/v5-fit-loop/timer-live-trust-combined
catalog=docs/experiments/v5-performance
combined_helpers="$catalog/patches/timer-live-trust-combined-replay.patch"
for leg in reference source; do
  mkdir -p "$area/$leg/build"
  git archive 11c4a0c rtl tools .rules.verible_format tests/cpu/arm9v2_board \
    tests/cpu/spmark_payload tests/phone/upp_ddr_ram/peer.v tests/phone/timers \
    tests/phone/timer_rates tests/phone/timer_conformance tests/phone/timer_original \
    tests/phone/upp_request_stage tests/phone/register_ram tests/phone/peripheral_response \
    sim/programs/link.ld | tar -x -C "$area/$leg"
done
git apply "$combined_helpers"
cp "$combined_helpers" "$area/timer-live-trust-combined-replay.patch"
for patch in timer-write-prepare dcache-live-trust; do
  git apply --directory="$area/source" "$catalog/patches/$patch.patch"
done
cp "$area/source/rtl/ngage_cpu.sv" "$area/ngage_cpu.sv"
python3 -B "$catalog/verify.py" timer-write-prepare dcache-live-trust
python3 -B "$area/source/tools/gen_arm9v2_phone.py" --stock build/arm9v2-assoc/stock-pinned.v --check
python3 -B "$area/prepare-fit.py"
sh "$area/qualify.sh" "$pinned_timer_instruction_deck"
```

For access to the staged commits, set `GIT_OBJECT_DIRECTORY` to `$PWD/$area/dispatch-20261126/objects` and `GIT_ALTERNATE_OBJECT_DIRECTORIES` to the contents of `$area/dispatch-20261126/alternate-objects.txt`. The replay receipt is `qualification.json` and the full workload rows are under `build/sim/v5-104-timer-live-trust-combined/qualification`.
