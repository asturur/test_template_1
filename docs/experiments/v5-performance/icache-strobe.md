# Prepare the I-cache request strobe

The [exact Git patch](patches/icache-strobe.patch) applies to public
`d87216a`, which has the retained `e9552bd` source tree. The fitted
candidate is `561a5cb`.

The retained TimeQuest reports show the instruction-cache strobe on
22, 23 and 23 of the hot top-1,000 paths into the I/D Wishbone merger
address register, in seed 43, 13 and 31337 order. Seed 13 and seed
31337 include paths from SDRAM ready through refill ACK and this
strobe. The [earlier address trial](wb-id-address.md) absorbed the
arbitration mux after address capture and regressed whole-core setup.

Here, the cache controller computes two request-valid outcomes
independently of ACK/ERR. The hold outcome keeps the current beat.
The completion outcome offers the successor or drops the request at
the final beat. The I-cache arbiter uses the fact that each of its
three sources drives CYC and STB together. It combines the incumbent
request with eligibility to use any requesting source. Payload
arbitration retains its existing priority and captures address,
data and transaction fields on the original edge. ERR alone still
uses the incumbent for the strobe, as in the retained design.

All 15 fixed workloads matched over 105 windows, including their
checked outputs, repeats and deliberately wrong-output runs. All four
native PolyCount frames and ten directed cache profiles matched. The
mixed pin model matched all 171,496 events and 1,201,547 system clocks,
including SDRAM traffic, LCD, audio and MMC persistence.

The production fits use 104 MHz and DDR debugging off. All ten seed
numbers match the Wishbone address trial. Seeds 43, 13 and 31337 also
match the retained build.

[Seed 43](https://github.com/asturur/test_template_1/actions/runs/45608403636) ·
[Seed 13](https://github.com/asturur/test_template_1/actions/runs/45608404498) ·
[Seed 31337](https://github.com/asturur/test_template_1/actions/runs/45608404739) ·
[Seed 1](https://github.com/asturur/test_template_1/actions/runs/45608404918) ·
[Seed 2](https://github.com/asturur/test_template_1/actions/runs/45608405362) ·
[Seed 3](https://github.com/asturur/test_template_1/actions/runs/45608404309) ·
[Seed 4](https://github.com/asturur/test_template_1/actions/runs/45608405095) ·
[Seed 5](https://github.com/asturur/test_template_1/actions/runs/45608406140) ·
[Seed 6](https://github.com/asturur/test_template_1/actions/runs/45608405948) ·
[Seed 7](https://github.com/asturur/test_template_1/actions/runs/45608406349)

## Replay

Prepare the frozen inputs from [the prepared write-data experiment](prepared-wb-write-data.md)
and use the [replay helper patch](patches/icache-strobe-replay.patch).

```sh
catalog=docs/experiments/v5-performance
area=scratch/v5-fit-loop/icache-strobe
git apply "$catalog/patches/icache-strobe-replay.patch"
mkdir -p "$area/source"
git archive d87216a | tar -x -C "$area/source"
git show d87216a:rtl/arm9v2/arm925t_phone.v > "$area/reference.v"
git show d87216a:rtl/ngage_cpu.sv > "$area/ngage_cpu.sv"
git apply --directory="$area/source" "$catalog/patches/icache-strobe.patch"
cp scratch/v5-fit-loop/prepared-wb-write-data/architectural_trace.vh "$area/"
cp scratch/v5-fit-loop/prepared-wb-write-data/wb-write-trace.vh "$area/"
python3 -B "$area/source/tools/gen_arm9v2_phone.py" --stock build/arm9v2-assoc/stock-pinned.v --check
python3 -B "$area/check-strobe.py"
python3 -B "$area/replay.py" fixed --output candidate
python3 -B "$area/replay.py" native --output candidate
```

The directed check compares the generated logic over 221,184
cache-controller cases and 3,072 arbitration cases using 16-byte and
32-byte lines. The arbiter case input exercises producers that assert
CYC and STB together. The integrated Verilator runs assert that
invariant on every active edge.

Use the write-data trial's frozen pin-model replay for the physical
SDRAM comparison. In a separate output directory, substitute the
candidate CPU netlist, verify all other source hashes against that
replay, then compare the cycle-stamped `traffic.log` files.
