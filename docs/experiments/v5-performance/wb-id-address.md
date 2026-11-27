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

Ten 104 MHz production fits use DDR debugging off. The retained build
has seed-matched controls for 43, 13 and 31337. Seeds 1–7 measure the
routing spread of this candidate and form the expanded seed set for
the next experiment.

[Seed 43](https://github.com/asturur/test_template_1/actions/runs/45591013483) ·
[Seed 13](https://github.com/asturur/test_template_1/actions/runs/45591019039) ·
[Seed 31337](https://github.com/asturur/test_template_1/actions/runs/45591018440) ·
[Seed 1](https://github.com/asturur/test_template_1/actions/runs/45592688278) ·
[Seed 2](https://github.com/asturur/test_template_1/actions/runs/45592689985) ·
[Seed 3](https://github.com/asturur/test_template_1/actions/runs/45592688767) ·
[Seed 4](https://github.com/asturur/test_template_1/actions/runs/45592684806) ·
[Seed 5](https://github.com/asturur/test_template_1/actions/runs/45592687936) ·
[Seed 6](https://github.com/asturur/test_template_1/actions/runs/45592688580) ·
[Seed 7](https://github.com/asturur/test_template_1/actions/runs/45592688146)

## Fitted results

| Seed | Retained worst setup (ns) | Candidate worst setup (ns) | Candidate ALMs |
| ---: | ---: | ---: | ---: |
| 43 | −2.508 | −2.522 | 37,044 |
| 13 | −2.061 | −3.138 | 37,035 |
| 31337 | −2.471 | −3.057 | 37,015 |
| 1 | — | −2.797 | 37,059 |
| 2 | — | −3.025 | 36,898 |
| 3 | — | −2.497 | 37,041 |
| 4 | — | −2.513 | 37,095 |
| 5 | — | −3.029 | 37,107 |
| 6 | — | −2.841 | 36,953 |
| 7 | — | −2.762 | 37,012 |

Across matched seeds, median worst setup moved from −2.471 to −3.057 ns,
median setup TNS moved from −5,143.651 to −5,630.477 ns, and median area
rose by 589 ALMs to 37,035. M10K use was 321 in every fit. Across all ten
candidate seeds, worst setup ranged from −3.138 to −2.497 ns, with a median
of −2.819 ns. All ten failed setup and passed hold, recovery, removal
and minimum pulse width.

The named instruction-cache strobe paths into the address registers
fell from 22, 23 and 23 to zero in the matched 100 °C top-1,000 lists.
The new address or owner launch into the board appeared 10, 1 and
113 times, with the worst listed slacks at −2.446, −1.716 and −2.312 ns.
Execute, DMA and cache paths limited the global fit on other seeds.

Park the candidate. Public `d87216a` restores the exact retained tree.
The best experimental bitstream is seed 3 at
`build/fit/v5-104mhz-f628271-seed3/ngage1.rbf`. It has no board validation.
[Verified per-corner results and artifact hash](../../evidence/v5-104-wb-id-address-fits.json)

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
