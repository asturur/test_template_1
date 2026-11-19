# ARM9V2 phone replay

Use the installed `jotego/simulator:arm64` image, host ARM GNU binutils and
Python with Unicorn and Pillow. Run from the `ngage-v5` worktree. Set
`NGAGE_FIXTURES` to the mainline checkout's `tests/cpu` directory and
`NGAGE_FIRMWARE` to its `build/firmware` directory. These paths are read-only.
The JPEG runner and Docker phone harness read staged copies of the original
firmware from this worktree. Keep the copies under `build/`.

```sh
mkdir -p build/firmware/nem4-factory
cp "$NGAGE_FIRMWARE/nem4-factory/core.bin" "$NGAGE_FIRMWARE/nem4-factory/extension.bin" build/firmware/nem4-factory/

sh tests/cpu/arm9v2_board/run-contract.sh fresh-bus

python3 tests/cpu/ngage2_compare/run.py --cpu base --name fresh-base --trace --payload-dir "$NGAGE_FIXTURES/spmark_payload/local"
python3 tests/cpu/ngage2_compare/run.py --cpu arm9v2 --name fresh-phone --trace --payload-dir "$NGAGE_FIXTURES/spmark_payload/local"
python3 tests/cpu/ngage2_compare/run.py --cpu ngage2 --name fresh-donor --trace --payload-dir "$NGAGE_FIXTURES/spmark_payload/local"

python3 tests/cpu/arm9v2_board/games.py --name fresh-games --fixtures "$NGAGE_FIXTURES" \
  --leg base=fresh-base --leg arm9v2=fresh-phone --leg ngage2=fresh-donor

python3 tests/cpu/ngage2_compare/jpeg.py --cpu arm9v2 --name fresh-jpeg-phone --jpeg "$NGAGE_FIXTURES/spmark_payload/local/TEST.JPG"

python3 tests/phone/hardware_boot/run-logo.py --cpu arm9v2 --name fresh-cold \
  --cycles 400000000 --production-ddr --line-refill --sys-clk-hz 78000000 \
  --timer-clock 26mhz --nos-tick-hz 64 \
  --cdrive "$NGAGE_FIRMWARE/thc/cdrive-formatted-4mib.img"

cp "$NGAGE_FIRMWARE/thc/cdrive-formatted-4mib.img" build/firmware/arm9v2-cdrive.img
PHONE_SYS_CLK_HZ=78000000 PHONE_LINE_REFILL=1 PHONE_SHORT_READS=1 \
PHONE_CDRIVE=build/firmware/arm9v2-cdrive.img \
PHONE_SDRAM_MODEL="$NGAGE_FIXTURES/../phone/sdram/model/mt48lc16m16a2.v" \
  sh tests/phone/hardware_boot/run-real-sdram.sh
```

Use `--cpu base` and `--cpu ngage2` for the matching JPEG legs. Add
`--scalar-refills` to the `arm9v2` payload run for the resized scalar control.
Use `--cpu zap` for a cold mainline phone control. Boot checkpoints
require the same CPU, build, settings and firmware lineage on restore.

The games runner uses the exact compiled SPMark binaries after verifying
their recorded hashes. Game fixtures come from the checked mainline
Super Monkey Ball span and Sega Rally/Asphalt loop tests. Each guest checks
output, guards and immutable inputs after every window. The independent
reference also checks the ordered stores against the original executable
under Unicorn. Game spans time the same marker-to-marker interval on all
CPUs, including the small entry and exit shims.

Add `--sega-scan-only` and use a fresh name to test the full 36,608-pixel
native scan with original FbsCli calls. This compiles the same pinned CPUs
with the larger memory fixture needed for disjoint source and destination
buffers. Use `--workers 6` to run its independent repeat and wrong-output
checks in parallel when the simulator has enough CPU cores.

The standalone donor leg reads `/Users/andreabogazzi/develop/ngage2` inside
a read-only mount. Match the donor revision in the
[experiment record](../../../docs/arm9v2-cache32.md) before comparing with
published results.

## Replay the payloads with the phone's MMC and NOS clocks

`payload_clocks.py` uses the accepted, hash-checked v5 SPMark, game, Sega
scan and JPEG archives named in the runner. It maps the same linked
payloads and firmware helpers into the full phone's flash, preserving
their virtual addresses and the guest's timed code and output checks.
It runs a configurable D2 cache and 32-byte refills at a 78 MHz system
clock with modeled SDRAM and DDR backing. For each profile it checks two
repeats, both original-code retirement counts, and rejection of a guest
with a bad expected output. It observes MMC activity, NOS ticks and IRQ
occupancy during the workload.

```sh
python3 -B tests/cpu/arm9v2_board/payload_clocks.py --name fresh-payload-clocks
```

Use `--case matrix4` to select a single workload. The default uses 39 MHz
MMC with both NOS rates. Replaying the 78 MHz MMC profiles (`--config 1:64`
or `--config 1:128`) requires the experimental RTL from `893b109`.
Logs and raw windows are under `build/sim/payload-clocks/NAME/`.

For the physical SDRAM cache-writeback comparison, prepare the pin model
with `sh tests/phone/sdram/run-stream.sh writeback-model` and run both
legs at the same clocks. Omit `--case` to cover all 15 retained workloads.

```sh
python3 -B tests/cpu/arm9v2_board/payload_clocks.py --name writeback-scalar \
    --config 2:64 --flash-cache-bytes 32768 --stream-sdram \
    --sdram-model build/sim/writeback-model/mt48lc16m16a2.v
python3 -B tests/cpu/arm9v2_board/payload_clocks.py --name writeback-block16 \
    --config 2:64 --flash-cache-bytes 32768 --stream-sdram --block-writeback \
    --sdram-model build/sim/writeback-model/mt48lc16m16a2.v
```

The production path sends each dirty 32-byte victim as two 16-byte requests from
the captured victim buffer. The runner counts these separately from scalar
writes. The existing SDRAM scheduler drives eight single-location WRITE
commands per block. Explicit cache maintenance uses its existing path.

To compare true half-line dirty tracking, generate the two-way netlist
with `sv2v` on `PATH` and add it to the block-writeback run. Use `--dirty
packed` for the matched metadata control, which writes both halves.

```sh
python3 tools/gen_arm9v2_cache_experiment.py --iways 2 --dways 2 --dirty half \
    --stream-writeback --output build/arm9v2-writeback/half.v
python3 -B tests/cpu/arm9v2_board/payload_clocks.py --name writeback-half-dirty \
    --config 2:64 --flash-cache-bytes 32768 --stream-sdram --block-writeback \
    --arm9v2-netlist build/arm9v2-writeback/half.v \
    --sdram-model build/sim/writeback-model/mt48lc16m16a2.v
```
