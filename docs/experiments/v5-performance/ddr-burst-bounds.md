# DDR burst bounds by final address window

The [portable RTL and test patch](patches/ddr-burst-bounds.patch) applies to
the all-four production control `739d3bd`. The separate fit commit
`b6d8981` starts from the same production source on public parent `8949813`.

Legal requests carry 1–64 aligned eight-byte beats. A request outside
`0xfffffe00–0xffffffff` fits, including 64 beats at the last aligned
address before that window. Inside the window, the six-bit starting beat
offset plus the requested count must be at most 64. Seven bits suffice
for the addition after the common count check. End exactly at 4 GiB
remains legal. With the production sector adapter's constant count of
64, the local check reduces to an offset of zero. The request, command
and completion edges remain the same for reads, scalar writes, streamed
writes and fills.

## Reapply and verify

Use a disposable copy of `739d3bd` and apply the linked patch. From that
source directory, run the symbolic proof on the host and the HDL
admission and transport tests in the existing offline Jotego image.

```sh
z3 tests/phone/ddr_stream/bounds.smt2
docker run --rm --pull=never --network none --platform linux/arm64 \
    -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 -ec '
    sh tests/phone/ddr_stream/run-bounds.sh
    sh tests/phone/ddr_stream/run.sh
    sh tests/phone/ddr_stream/run-equivalence.sh
    sh tests/phone/ddr_stream/run-fabric.sh
    sh tests/phone/ddr_bulk/run.sh
    sh tests/phone/upp_ddr_transport/run.sh
    sh tests/phone/mmc_hps/run.sh
'
sh tests/phone/upp_ddr_top/run.sh
```

Z3 returned `unsat` for old and new admission disagreeing on any address,
count, or mode. The HDL test checked 98,304 admissions per fill setting
against the original 33-bit expression, plus live final-sector reads
and last-address writes. The transport regressions covered physical DDR
request sequences in the model, masks, ownership, scrubbing, reset
drain and actual MMC HPS bridge logic. The actual Template transport was
also checked with a modeled HPS and PLL.

The 104 MHz fixed-work comparison ran 15 payloads, two good trials and a
wrong-output control each. All guest windows and ordered digests matched
the all-four control. Four native PolyCount frames matched each frame's
clocks, ordered digests and output SHA-256. The LCD/PCM/MMC replay uses a
delayed raw-DDR peer at the phone endpoint and the pin SDRAM model; it
matched 1,201,547 clocks, 18,304 LCD words, PCM hash `175ee178`, no
underruns and correct 512-byte CMD24 persistence. The DDR stream is
exercised directly by the sector and transport fixtures.
[Checked simulation results](ddr-burst-bounds-replay.json)

To repeat the ordered workload comparison, use the local all-four decks,
frozen board and observer references described in the
[simulation fixture recipes](fixtures.md#thumb-and-d-admission-together).
Apply the [workload replay fixture](patches/ddr-burst-bounds-replay.patch)
from the repository root as well as the RTL patch in the disposable source
directory. Then run the two deck replays:

```sh
area=scratch/v5-fit-loop/ddr-bound-window
mkdir -p "$area/source" "$area/replay"
git archive 739d3bd | tar -x -C "$area/source"
git apply --directory="$area/source" docs/experiments/v5-performance/patches/ddr-burst-bounds.patch
git show 739d3bd:rtl/ngage_cpu.sv > "$area/ngage_cpu.sv"
python3 -B "$area/replay.py" fixed
python3 -B "$area/replay.py" native
```

The three builds use the same production constraints and source graph as
the all-four control, with only the DDR stream source changed. The
[seed 43](https://github.com/asturur/test_template_1/actions/runs/45291134648),
[seed 13](https://github.com/asturur/test_template_1/actions/runs/45291139958)
and [seed 31337](https://github.com/asturur/test_template_1/actions/runs/45291143845)
dispatches pin `b6d8981` at 104 MHz with the debugger off.
