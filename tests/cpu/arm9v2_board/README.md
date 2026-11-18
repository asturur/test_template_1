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
