# Register the CPU's posted SDRAM write acknowledgment

The [exact Git patch](patches/cpu-posted-sdram-ack.patch) applies to the
retained production tree at `606ff0d`. The candidate is `654217d`.

In the retained hot top-1,000 setup exports, the SDRAM stream's
posted-write decision reached the Wishbone merger on 26, 34 and 54
paths for seeds 43, 13 and 31337. Its first paths ranked third,
second and first.

The SDRAM stream exposes a separate acknowledgment for reads and
locked writes. The existing acknowledgment still releases the
physical arbiter slot. The arbiter samples the CPU-owned posted
write completion into a register before returning it to the CPU.
The CPU route holds its outstanding token across that clock and can
still suppress a cancelled completion. This gives the posted path
a register boundary before CPU/cache request selection. DMA
completion and native-line delivery follow their original logic.

The directed route test covers scalar and block writes, DMA
admission during the registered reply, direct read and locked-write
responses, cancellation and reset. The 15 fixed workloads pass guest
checks, repeats, wrong-output checks and the ordered architectural
digest. The largest measured slowdowns are 0.091% for Sega scan and
0.031% for full-frame 16-bit fill.

The native replay takes 57,514,996 clocks over four frames, up 6,625
clocks (+0.0115%). Both reruns have the same frame output hash, ordered
guest retirement checksum, architectural data accesses and 278,165
acknowledged writes. The strict raw writeback checksum initially
failed on frame zero. The additional observer found eight extra
internal completions for the instruction at `0x10106768` and matching
guest retirements on that frame. Stalled write-offer clocks increased
from 530,081 to 577,011 over the four native frames.

The strict mixed replay reaches the PCM checksum assertion and fails.
The diagnostic replay compares individual samples with the strict
hash check omitted and keeps every other board assertion. It checks
both UPP DDR banks, LCD output, PCM cadence and underrun/overwrite
counters, and MMC write persistence and readback. Its completion
clock increases from 1,201,547 to 1,220,491 (+1.577%). Only sample
index 2 changes, from `f415/05f5` to `fff9/0003`; the other 127
samples and the 275,167-clock span match.

Three 104 MHz fits use DDR debugging off and match the retained
production seeds. [Seed 43](https://github.com/asturur/test_template_1/actions/runs/45674062799) ·
[Seed 13](https://github.com/asturur/test_template_1/actions/runs/45674066398) ·
[Seed 31337](https://github.com/asturur/test_template_1/actions/runs/45674071399)

## Fitted results

| Seed | Retained setup slack (ns) | Registered ACK setup slack (ns) | Candidate ALMs |
| ---: | ---: | ---: | ---: |
| 43 | −2.508 | −2.734 | 36,247 |
| 13 | −2.061 | −3.062 | 36,269 |
| 31337 | −2.471 | −2.823 | 36,209 |

Named paths through the posted-write decision into the Wishbone
merger fell from 26, 34 and 54 to zero in the matched hot top-1,000
reports. Whole-core median setup slack moved from −2.471 to −2.823 ns,
median core setup TNS from −5,143.651 to −7,366.732 ns, and median
area from 36,446 to 36,247 ALMs. All fits used 321 M10Ks. They missed
setup and passed hold, recovery, removal and minimum pulse checks.
Execute and the TLB-to-D-cache tag path set the remaining limits.

Park the trial. Public `e11a637` restores the exact retained source
tree. The best candidate fit was seed 43, archived at
`build/fit/v5-104mhz-654217d-seed43/ngage1.rbf`. Hardware status is unverified.
[Verified per-corner evidence](../../evidence/v5-104-cpu-posted-sdram-ack-fits.json)

## Replay

Prepare the frozen [write-data workloads](prepared-wb-write-data.md).
Apply the [replay helper patch](patches/cpu-posted-sdram-ack-replay.patch)
and run the following from the repository root.

```sh
catalog=docs/experiments/v5-performance
area=scratch/v5-fit-loop/cpu-posted-sdram-ack
git apply "$catalog/patches/cpu-posted-sdram-ack-replay.patch"
mkdir -p "$area/source"
git archive 606ff0d | tar -x -C "$area/source"
git apply --directory="$area/source" "$catalog/patches/cpu-posted-sdram-ack.patch"
cp "$area/source/rtl/ngage_cpu.sv" "$area/"
cp scratch/v5-fit-loop/prepared-wb-write-data/wb-write-trace.vh "$area/"
iverilog -g2012 -s reply_tb -o "$area/reply_tb" \
  "$area/reply_tb.v" "$area/source/rtl/ngage_sdram_arbiter.v" "$area/source/rtl/ngage_upp.v"
vvp "$area/reply_tb"
python3 -B "$area/replay.py" fixed --output candidate
python3 -B "$area/replay.py" native --control --output control-native
python3 -B "$area/replay.py" native --output verified-native
python3 -B "$area/mixed.py"
python3 -B "$area/pcm-replay.py"
```

Compare the four `guest` rows in the two native receipts. The native
runner also requires the reference frame output hash and the ordered
memory access digest.

Run each mixed leg with its own `build.sh`, then execute the resulting
`obj/Vtb` with `+upp_stress`. The two PCM characterization builds
output the index and values of all samples.
