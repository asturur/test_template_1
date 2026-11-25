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
