# Benchmark-only ngage2 versus exact5C

The `ngage-v5` experiment also uses this driver. The 32-byte comparison runs
`--cpu base`, `--cpu arm9v2`, and `--cpu ngage2`. Use `--scalar-refills` to
isolate the resized v5 CPU's scalar path or reproduce the standalone scalar
control from the stock-geometry experiment.
See [ARM9V2 phone replay](../arm9v2_board/README.md) for that configuration.

Read `docs/ngage2-vs-5c-benchmark.md` for qualified results and limitations.
Run from the repository with existing original local payload/ROM inputs,
Unicorn, ARM GNU binutils and installed offline `jotego/simulator:arm64`.
Never modify/import donor RTL or use this fixture as production wiring.

Use new output names; outputs are exclusively under build/. The5C CPU closure
is read from78d53d4 without Git checkout/index changes. Donor QIP-selected
netlist and its existing primitive models are compiled in place through a
read-only mount; dependency hashes and its revision are recorded and checked.

```sh
python3 tests/cpu/ngage2_compare/run.py --cpu 5c --name NEW-control --trace --jobs 2
python3 tests/cpu/ngage2_compare/run.py --cpu ngage2 --name NEW-donor --trace --jobs 2
python3 tests/cpu/ngage2_compare/qualify.py --base build/sim/spmark-payload/NEW-donor --name NEW-observer
python3 tests/cpu/ngage2_compare/run.py --cpu 5c --name NEW-drain-control --case fill16_frame --profile 2:9 --jobs 2
python3 tests/cpu/ngage2_compare/run.py --cpu ngage2 --name NEW-drain-donor --case fill16_frame --profile 2:9 --jobs 2
python3 tests/cpu/ngage2_compare/jpeg.py --cpu 5c --name NEW-jpeg-control
python3 tests/cpu/ngage2_compare/jpeg.py --cpu ngage2 --name NEW-jpeg-donor
python3 tests/cpu/ngage2_compare/collect.py \
 --control build/sim/spmark-payload/NEW-control \
 --donor build/sim/spmark-payload/NEW-donor \
 --qualification build/sim/ngage2-observer/NEW-observer \
 --drain-control build/sim/spmark-payload/NEW-drain-control \
 --drain-donor build/sim/spmark-payload/NEW-drain-donor \
 --jpeg-control build/sim/jpeg-payload/NEW-jpeg-control \
 --jpeg-donor build/sim/jpeg-payload/NEW-jpeg-donor \
 --output build/sim/NEW-comparison.json
```

`--case matrix4 --case transpose4` starts the requested pair; default runs all
six. Default is two warmups/five scored windows/two complete repeats plus
wrong-output controls. `--trace` records one scored window's real retirement,
physical transfers, donor completed data accesses and paired register writes.
`observe.py` adds only passive counters, MMU/cache assertions and first-empty
write-buffer observation; it never stalls either CPU or changes guest bytes.
The standard timing window is preserved even if writes remain pending.

Memory is intentionally the accepted fixture's asymmetric synthetic contract:
scalar32 per-word waits for all scalar reads/writes (including donor burst
writes); read-line transport16bits/clock with one startup wait. Donor read
bursts aggregate pairs into32bits, first ACKwait+3, later words2clocks. This
is not physical SDRAM and not a uniform16-bit bus. Keep this contract identical
for both CPUs. Cache geometry, line lengths, critical-word delivery and TLB
organization remain native and are explained in the report.

`collect.py` rejects changed guests/oracles, failed runs, wrong source hashes,
PC-sequence differences, changed original counters in drain runs, incorrect
actual donor paired multiply writes, and an unqualified donor executable.
JPEG explicitly validates the donor's905 extra Thumb BL suffix retirements
against original bytes and the full independent PC histogram, rather than
mistaking raw halfword completions for extra work or generic CPI.

Source/template/harness hashes are in each run. Preserve failed fixture and
unmatched-contract runs as evidence; do not combine them with final results.
Firmware, extracted modules, raw pixels and generated build products stay local.
