# Select the Wishbone address after cache capture

The [design patch](patches/wb-id-address.patch) applies to public `e7beaf2`,
which has the exact retained `e9552bd` tree. The trial is `f628271`.

On the retained 104 MHz fits, the merger address register is the worst
setup endpoint at −40 °C on all three seeds. At 100 °C, its first path
ranks second, second and first. The first paths include MMU/cache busy
and SDRAM ACK feeding the instruction-cache strobe, followed by the
merger's I/D owner decision and the address mux.

The instruction and data cache already capture their chosen address on
the same edge as the merger. The trial connects those two registers
and selects between them with the registered bus owner. Both reset to
the original outward address of zero. The merger still captures CYC,
STB, WE, SEL, CTI, BTE and native-line eligibility on the original edge.
ACK, ERR, arbitration and the prepared write-data path retain their
existing logic. This removes the outer owner mux from the address
register input. The new output mux can affect paths into downstream
address decoders, so compare both sides of the boundary after fitting.

The prior [payload-bank trial](historical/wishbone-payload-banks.patch)
exposed five source addresses and captured write-data banks as well.
This trial uses the two existing cache outputs and keeps each cache's
internal owner selection.

## Simulation

- The merger comparison matched every output on 50,000 edges. It
  observed 18,677 valid requests, 25,038 asserted error replies and
  13,670 owner switches.
- All 15 fixed workloads matched the retained counters, results and
  architectural and write digests over 105 windows. Repeat runs and
  wrong-output controls passed. All four native PolyCount frames
  matched, including every checked cycle count and the result hash.
- Ten directed cache profiles matched, including scalar and native
  eviction, rejected stores, tag maintenance, and reset while a write
  was stalled. The 104 MHz pin model matched all 171,496 trace records
  over 1,201,547 clocks, including PCM, LCD, MMC persistence and SDRAM.

Three 104 MHz production fits use DDR debugging off.
[Seed 43](https://github.com/asturur/test_template_1/actions/runs/45591013483) ·
[Seed 13](https://github.com/asturur/test_template_1/actions/runs/45591019039) ·
[Seed 31337](https://github.com/asturur/test_template_1/actions/runs/45591018440)

## Replay

Prepare the frozen inputs from [the write-data experiment](prepared-wb-write-data.md),
then apply the [measurement helper patch](patches/wb-id-address-replay.patch).

```sh
catalog=docs/experiments/v5-performance
area=scratch/v5-fit-loop/wb-id-address
git apply "$catalog/patches/wb-id-address-replay.patch"
mkdir -p "$area/source"
git archive e7beaf2 | tar -x -C "$area/source"
git show e7beaf2:rtl/arm9v2/arm925t_phone.v > "$area/reference.v"
git show e7beaf2:rtl/ngage_cpu.sv > "$area/ngage_cpu.sv"
git apply --directory="$area/source" "$catalog/patches/wb-id-address.patch"
cp scratch/v5-fit-loop/prepared-wb-write-data/architectural_trace.vh "$area/"
cp scratch/v5-fit-loop/prepared-wb-write-data/wb-write-trace.vh "$area/"
python3 -B "$area/source/tools/gen_arm9v2_phone.py" --stock build/arm9v2-assoc/stock-pinned.v --check
python3 -B "$area/check-merger.py"
python3 -B "$area/replay.py" fixed --output candidate
python3 -B "$area/replay.py" native --output candidate
```

Use the write-data trial's frozen board replay for the physical SDRAM
comparison. In a separate output directory, substitute the candidate
CPU netlist, verify all other source hashes against that replay and
compare the cycle-stamped `traffic.log` files.
