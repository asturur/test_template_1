# v5 scalar load-to-use timing

Experiment 2 uses the synthesis-selected CPU at `78af1df`. The original
replays use 78 MHz, 16 KiB I and D caches, two ways, 32-byte lines, and
the production streaming SDRAM and 32 KiB flash cache. The directed
guest uses the production CPU/cache/MMU with the contract's synthetic
scalar and burst responders. Its traces report CPU clocks.

## Warm schedule

The trace starts at the cycle in which the load calculates its address
in A. D2 hands an instruction to S, and S hands it to A. The register
operand of an ordinary ADD can arrive late in A. A shifted operand
must be present in S for the shifter.

| Event | Cycle relative to the load in A |
| --- | ---: |
| Load accepted by D2 | −2 |
| Load accepted by S | −1 |
| Load computes and presents the address in A | 0 |
| M sees the cache tag, TLB/permission precheck and formatted word | +1 |
| W has the owned, trusted hit and exposes it on the bypass | +2 |
| Dependent ordinary ADD or dependent load address uses the result in A | +2 |
| Dependent shifted ADD consumes the value in S | +2 |
| Dependent shifted ADD finishes in A | +3 |

The measured ordinary ADD and pointer chase enter S at +1. They use the
bypass in A as soon as W owns the hit. The M values sampled at +1 are
inputs to the registered data, permission and ownership path. A
design to consume them in +1 would cross that boundary and would need
a new address/format/permission path and miss replay qualification.
[CPU bypass](../rtl/arm9v2/arm925t_phone.v#L1406) · [D-cache short-response registers](../rtl/arm9v2/arm925t_phone.v#L11487)

All five formats `LDR`, `LDRB`, `LDRH`, `LDRSB`, and `LDRSH` reach an
immediate unshifted ADD at +2 in ARM and Thumb. The trace checks
the formatted bytes, including `0xffffff81` and `0xffff80ff` for the
signed cases. The guest checks the ADD results, a failed conditional
load with an immediate consumer, a passed conditional load, and a fault
that leaves the destination unchanged when the abort handler resumes
at the consumer. All four memory profiles pass, including the existing
prefetch-abort, IRQ and FIQ controls.

| Sequence | Steady clocks per load or load/ADD pair |
| --- | ---: |
| Independent loads | 1 per load |
| Load-to-load address chain | 2 per load |
| Load/ADD pairs with load destination rotated | 3 per pair |
| Load/ADD pairs with the same load destination | 4 per pair |

The fourth clock in the repeated destination sequence is a decode
write-after-write interlock. The next LDR targets the register whose
previous load is still in M. Rotation removes this clock without
moving the immediate ADD's +2 use. The first dependency clock is spent
between address generation and the checked hit. In the same contract,
the cold load's consumer waits 9 to 15 clocks and the uncached device
load's consumer waits 38 to 202 clocks, depending on the responder.
Those are fixture waits. A cold load can leave W before its data is
ready, so elapsed consumer time is measured separately from W completion.

## Original code replays and decision

The instrumented PolyCount replay reproduces 15,019,070 clocks in the
median frame with 4,800 triangles and the same object, index, color,
and depth bytes. The load-site probe counts a finishing A consumer in
the same cycle as the matching trusted W result.

| GLES load and consumer | Loads | Trusted W hits | Consumer finishes on the hit cycle |
| --- | ---: | ---: | ---: |
| `+0x6c54` word → `+0x6c58` ADD | 14,400 | 14,400 | 14,400 |
| `+0x6c5c` vertex halfword → `+0x6c64` AND | 14,400 | 14,046 | 0 |
| `+0x6c60` stack word → `+0x6c64` AND | 14,400 | 14,363 | 14,014 |
| `+0x6c6c` stack word → `+0x6c70` ORR | 14,400 | 14,400 | 14,400 |

The AND also reads the older halfword. The halfword row measures a
two-instruction distance. In the recorded held example, the AND is
still waiting in D2 when its newer stack word hits. This exposes an
earlier dependency at the two-load sequence.

The six SPMark kernels, Thumb JPEG, Monkey Ball forward and reverse,
Sega Rally span, fill and scan, and three Asphalt payloads reproduce
every timing window across all 15 cases and the output checks, including
wrong-output rejection. The benchmark runs use the production control
without either of the parked overlays. Sample matched clocks are
16,814 for matrix, 12,254 for triangle edges, 35,903 for JPEG, 16,443
for Monkey Ball forward, 2,391,228 for Sega scan and 21,396 for the
Asphalt table case.

**Decision: drop a redundant W-hit bypass.** The current consumers
use the result as soon as the registered cache path makes it available.
The measured opportunities are before that boundary or in surrounding
dependencies, including repeated destinations and unavailable older
data. This audit does not time an M-stage retiming or a new scoreboard.
[Stage trace and matched workload evidence](evidence/arm9v2-load-use-v5-20261119.json)

## Repeated load destination experiment

Experiment 4 starts from `57ba6ef`, the production direct-accumulate
commit. The same cache geometry, clocks, original inputs and memory
RTL are used for both legs. A counter inspects the actual D2 producer
hazard mask. It marks an older scalar load only when its tag matches
the younger scalar load destination and the younger load does not read
that tag. References to the destination as an address source remain
true dependencies. A blocked issue slot, a separate source hazard, and
a separate destination lock or other decode hazard are counted apart.

In the median native control the repeated-destination hazard is present
for 21,488 clocks. Of these, 622 also have no issue slot available.
The remaining 20,866 clocks have the repeated destination as their sole
issue blocker. This includes 20,580 with the producer in M and 286 with
it in W. M has a valid tag and permission precheck in 20,554 of those
20,580 clocks. These are counts of issue slots in the control schedule.
Elapsed savings are measured independently.

The offline overlay removes only the M-stage interlock between two
scalar loads without base writeback or a PC destination. The younger
load must not read the older destination. It can move from D2
to S early. S waits for older matching records and cache locks. It can
advance alongside the older W record when that record has a trusted,
acknowledged hit. This keeps the existing value bypass and memory
request order. The S guard also covers a result that returns later on
a miss or uncached access.

Across all four directed profiles, rotating load destinations still
costs three clocks per load/ADD pair. Reusing the same destination
falls from four to three. The dependent ADD and pointer chase keep
their two-clock hit latency. In the zero-extra-wait burst trace, the
younger load enters S while the older load is in M. S holds it for
15 clocks on the cold case and 30 on the device case. Tests check
distinct old/new values, a failed condition, an IRQ/FIQ, and a fault
where the abort handler sees the old destination and returns to the
younger load. Both legs pass the same directed checks.

| Workload | Control sole WAW slots | Overlay sole WAW slots | Control clocks | Overlay clocks |
| --- | ---: | ---: | ---: | ---: |
| Native PolyCount | 20,866 | 12 | 14,928,261 | 14,913,976 |
| SPMark matrix | 0 | 0 | 16,814 | 16,814 |
| SPMark transpose | 0 | 0 | 2,772 | 2,772 |
| GLES triangle edges | 16 | 0 | 12,229 | 12,213 |
| GLES 16-bit frame fill | 0 | 0 | 112,705 | 112,705 |
| GLES 16-bit tail fill | 0 | 0 | 726 | 726 |
| GLES 8-bit tail fill | 0 | 0 | 747 | 747 |
| Monkey Ball forward span | 0 | 0 | 15,934 | 15,934 |
| Monkey Ball reverse span | 0 | 0 | 15,934 | 15,934 |
| Sega Rally textured span | 0 | 0 | 15,424 | 15,424 |
| Sega Rally solid fill | 0 | 0 | 2,622 | 2,622 |
| Sega Rally full scan | 0 | 0 | 2,391,228 | 2,391,228 |
| Asphalt table | 1,280 | 1,024 | 21,396 | 21,136 |
| Asphalt double lookup | 0 | 0 | 11,961 | 11,961 |
| Asphalt single lookup | 0 | 0 | 7,756 | 7,756 |
| Thumb JPEG 8×8 | 200 | 0 | 35,903 | 35,703 |

Cycle results use the existing warmed medians. The slot counters for
fixed-work windows use the first scored window. Native values use the
median frame. PolyCount saves 14,285 clocks (0.096%), Asphalt table
saves 260, JPEG saves 200, and triangle edges saves 16. The other
twelve fixed-work medians tie. Triangle-edge window 5 is 14 clocks
slower, with one additional scalar read and eleven additional scalar
wait clocks. Its median still improves. Asphalt keeps 1,024 stalls
in S and A, stages outside the M-only change.

The native replay matches all 4,800 triangles, original color and depth
bytes, indices, object state and retired instructions. All 15 payloads
pass matched guest checks twice, including deliberately wrong-output
rejection. **Keep this candidate offline.** The local Asphalt and JPEG
gains justify retaining the experiment. The native speedup is small,
one fixed-work window loses clocks, and the new W-to-S guard has no
routed timing evidence.
[Per-window measurements and stage evidence](evidence/arm9v2-repeated-load-v5-20261119.json)

## Reproduce

```sh
mkdir -p build/sim/load-use-v5
git show 78af1df:rtl/arm9v2/arm925t_phone.v > build/sim/load-use-v5/control.v
ARM9V2_LOAD_USE_TEST=1 ARM9V2_ICACHE_BYTES=16384 ARM9V2_SECTION_INDEX=xor \
  ARM9V2_NETLIST=build/sim/load-use-v5/control.v \
  sh tests/cpu/arm9v2_board/run-contract.sh fresh-load-use-v5
python3 tests/cpu/arm9v2_board/load_use_trace.py \
  build/sim/arm9v2/contract-fresh-load-use-v5 --output build/sim/load-use-v5/contract-trace.json
python3 tests/cpu/polycount_v5/run.py --name fresh-load-use-v5 --trace-load-sites \
  --netlist build/sim/load-use-v5/control.v --legs i16 \
  --capture build/sim/polycount-v5/native-qualified \
  --pin-model build/sim/unit-hardware-boot-real-sdram/mt48lc16m16a2-verilator.v
python3 tests/cpu/arm9v2_board/payload_clocks.py --name fresh-load-use-v5 \
  --arm9v2-netlist build/sim/load-use-v5/control.v --config 2:64 \
  --flash-cache-bytes 32768 --stream-sdram --block-writeback \
  --sdram-model build/sim/unit-hardware-boot-real-sdram/mt48lc16m16a2-verilator.v
```

Reproduce the repeated-destination A/B on the direct-accumulate commit.

```sh
mkdir -p build/sim/load-waw-v5
git show 57ba6ef:rtl/arm9v2/arm925t_phone.v > build/sim/load-waw-v5/control.v
python3 tests/cpu/arm9v2_board/load_waw.py \
  build/sim/load-waw-v5/control.v build/sim/load-waw-v5/candidate.v
python3 tests/cpu/polycount_v5/run.py --name fresh-load-waw-polycount --load-waw-counts \
  --netlist build/sim/load-waw-v5/control.v --legs i16 load-waw \
  --capture build/sim/polycount-v5/native-qualified \
  --pin-model build/sim/unit-hardware-boot-real-sdram/mt48lc16m16a2-verilator.v
for leg in control candidate; do
  netlist="build/sim/load-waw-v5/$leg.v"
  python3 tests/cpu/arm9v2_board/payload_clocks.py --name "fresh-load-waw-$leg" \
    --arm9v2-netlist "$netlist" --config 2:64 --flash-cache-bytes 32768 \
    --sdram-model build/sim/unit-hardware-boot-real-sdram/mt48lc16m16a2-verilator.v \
    --stream-sdram --block-writeback --load-waw-counts
  ARM9V2_LOAD_USE_TEST=1 ARM9V2_LOAD_WAW_TEST=1 ARM9V2_ICACHE_BYTES=16384 \
    ARM9V2_SECTION_INDEX=xor ARM9V2_NETLIST="$netlist" \
    sh tests/cpu/arm9v2_board/run-contract.sh "fresh-load-waw-$leg"
done
```
