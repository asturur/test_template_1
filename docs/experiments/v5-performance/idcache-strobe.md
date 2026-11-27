# Prepare instruction and data cache request strobes

The [combined Git patch](patches/idcache-strobe.patch) applies to the
retained production tree at `a58c77b`. The [D-cache delta](patches/idcache-strobe-delta.patch)
applies to the I-cache experiment at `561a5cb`. Both produce the
measured RTL and generator at `6c605ce`.

The [I-cache trial](icache-strobe.md) removed the named I-cache strobe
paths into the merger address. The D-cache strobe still appeared
on paths into the merger in every one of its ten fits. It was on the
worst path on seeds 13 and 2. On seed 13, SDRAM completion advanced
the D-cache beat, and the resulting strobe drove the Wishbone address
selection. The retained source also had a D-cache strobe path at
rank 3 on seed 43.

The data cache compares the current word and successor independently
against the last writeback word. ACK/ERR selects their validity and
termination results. Clean and fetch request validity each have a
hold and advance case. The data-side arbiter reduces the eligible
request mask when the bus can change owner, and uses the incumbent
request while it is held. The eligible mask still enforces posted-store
priority. The existing arbiter selects address, data, byte enables
and burst fields on the original request edge.

All 15 fixed workloads and 105 measured windows passed output and
repeat controls and matched cycles. The four native PolyCount frames
and ten directed cache profiles matched. The mixed board model matched
all 171,496 trace records and 1,201,547 clocks, including LCD, audio,
MMC persistence and SDRAM pin traffic.

All ten production fits use 104 MHz and DDR debugging off. They match
the I-cache-only fit seeds. Seeds 43, 13 and 31337 also match the retained
production fit seeds.

[Seed 43](https://github.com/asturur/test_template_1/actions/runs/45623038143) ·
[Seed 13](https://github.com/asturur/test_template_1/actions/runs/45623037946) ·
[Seed 31337](https://github.com/asturur/test_template_1/actions/runs/45623040151) ·
[Seed 1](https://github.com/asturur/test_template_1/actions/runs/45623036445) ·
[Seed 2](https://github.com/asturur/test_template_1/actions/runs/45623040010) ·
[Seed 3](https://github.com/asturur/test_template_1/actions/runs/45623039870) ·
[Seed 4](https://github.com/asturur/test_template_1/actions/runs/45623039732) ·
[Seed 5](https://github.com/asturur/test_template_1/actions/runs/45623038261) ·
[Seed 6](https://github.com/asturur/test_template_1/actions/runs/45623044481) ·
[Seed 7](https://github.com/asturur/test_template_1/actions/runs/45623039354)

## Fitted results

| Seed | Retained setup slack (ns) | I-cache only (ns) | I/D cache (ns) | Combined ALMs |
| ---: | ---: | ---: | ---: | ---: |
| 43 | −2.508 | −2.612 | −2.569 | 36,834 |
| 13 | −2.061 | −3.437 | −2.544 | 36,868 |
| 31337 | −2.471 | −2.942 | −2.432 | 36,913 |
| 1 | — | −2.435 | −2.512 | 36,940 |
| 2 | — | −3.542 | −2.494 | 36,890 |
| 3 | — | −2.731 | −3.031 | 36,947 |
| 4 | — | −2.822 | −3.749 | 36,933 |
| 5 | — | −3.208 | −2.410 | 36,909 |
| 6 | — | −2.632 | −2.564 | 36,903 |
| 7 | — | −2.781 | −2.855 | 36,912 |

Six of ten seeds improved over I-cache alone. Median setup moved from
−2.8015 to −2.554 ns, median core setup TNS from −6,794.090 to
−5,360.7045 ns, and median area from 36,086.5 to 36,910.5 ALMs.
Against retained production, the three matched fits moved the median
from −2.471 to −2.544 ns. Median TNS improved by 9.567 ns and area
increased by 422 ALMs. Each fit used 321 M10Ks.

The hot top-1,000 exports contain 101 named RAM ACK paths through the
D-cache request into the merger in the I-cache-only fits, versus 17
in the combined ones. Seed 13 fell from 34 to eight and its worst
named D-cache request path gained 1.710 ns. Its worst whole-core path
moved to the branch predictor valid-bit read. Seed 5 has the best
candidate setup at −2.410 ns. All ten still missed setup and passed hold,
recovery, removal and minimum pulse checks.

Park the combination. Public `606ff0d` restores the exact retained
production tree. The seed 5 bitstream is archived at
`build/fit/v5-104mhz-6c605ce-seed5/ngage1.rbf`. Board validation is pending.
[Verified per-seed timing evidence](../../evidence/v5-104-idcache-strobe-fits.json)

## Replay

Prepare the frozen [write-data workloads](prepared-wb-write-data.md).
The [replay helper patch](patches/idcache-strobe-replay.patch) adds the
directed comparison and the fixed and native workload runner.

```sh
catalog=docs/experiments/v5-performance
area=scratch/v5-fit-loop/idcache-strobe
git apply "$catalog/patches/idcache-strobe-replay.patch"
mkdir -p "$area/source"
git archive a58c77b | tar -x -C "$area/source"
git show a58c77b:rtl/arm9v2/arm925t_phone.v > "$area/reference.v"
git show 561a5cb:rtl/arm9v2/arm925t_phone.v > "$area/icache-reference.v"
git show a58c77b:rtl/ngage_cpu.sv > "$area/ngage_cpu.sv"
git apply --directory="$area/source" "$catalog/patches/idcache-strobe.patch"
cp scratch/v5-fit-loop/prepared-wb-write-data/architectural_trace.vh "$area/"
cp scratch/v5-fit-loop/prepared-wb-write-data/wb-write-trace.vh "$area/"
python3 -B "$area/source/tools/gen_arm9v2_phone.py" --stock build/arm9v2-assoc/stock-pinned.v --check
python3 -B "$area/check-dcache-strobe.py"
python3 -B "$area/replay.py" fixed --output candidate
python3 -B "$area/replay.py" native --output candidate
```

The directed expression comparison exercises 67,584 controller cases
and 4,096 arbiter cases across 16- and 32-byte line configurations.
It checks one- and four-word advances, all word limits, ACK/ERR and
posted-store eligibility. The integrated models check that all
producers drive CYC and STB together.

For the mixed pin model, copy the prepared write-data trial's frozen
replay into a separate output directory, replace its CPU netlist
and verify all other source hashes. Compare the cycle-stamped
`traffic.log` files.
