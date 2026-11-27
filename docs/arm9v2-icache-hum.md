# v5 I-cache hit under miss at 78 MHz

The three simulation legs use `57ba6ef` as the source control.
All keep the 16 KiB, two-way I and D caches, 32-byte lines, the XOR
section TLB, the original predictor, the same 78 MHz clock, and the
same SDRAM/flash transport and refill order.

- **A** is production. The prior control's netlist, board, CPU wrapper,
  SDRAM sources and bench inputs were verified against this checkout.
- **B** adds early restart with an explicit positive guarantee. The
  MiSTer line router asserts it only for eligible SDRAM or flash array
  reads at the accepted request. The CPU bridge latches it for that
  transaction. Missing capability or an unpromised response holds
  instructions until line completion. Rejected reads fall back to
  scalar transfers and give no promise. An error on a promised line
  fails the hardware simulation.
- **C** adds a checked resident hit to a different line during that
  same kind of refill. A second miss waits. Both overlays are offline.

## Directed proof

The short SDRAM call returns at clock 14 from its miss transition.
The original line receives its first word at clock 4 and finishes
at clock 20 in both B and C. The caller at `0x000004e8` has a
permitted section translation to the same physical address and
the I-cache shadow identifies its resident tag in way zero at
the redirect. Its set is different from the fill's. B cannot
advance the unused F2 record until refill completion. C advances
it with a no-request acknowledgement, checks the redirected
target through the normal synchronous lookup, and enqueues the
caller instruction at clock 16. It issues at clock 20 and retires
at clock 23. In B it issues at clock 27 and retires at clock 30.

| Target, zero-wait burst fixture | Redirect | Original refill complete | Issue B → C | Retire B → C |
| --- | ---: | ---: | ---: | ---: |
| Resident caller, different set | 14 | 20 | 27 → 20 | 30 → 23 |
| Resident other way of refill set, ARM | 12 | 20 | 27 → 18 | 30 → 21 |
| Reserved old victim, ARM | 12 | 20 | 33 → 33 | 36 → 36 |
| Second cold line, ARM | 12 | 20 | 33 → 33 | 36 → 36 |
| Resident other way of refill set, Thumb | 12 | 20 | 27 → 18 | 30 → 21 |
| Reserved old victim, Thumb | 12 | 20 | 33 → 33 | 36 → 36 |
| Second cold line, Thumb | 12 | 20 | 33 → 33 | 36 → 36 |

The same-set ARM and Thumb cases select way one while the refill
reserves way zero. The reserved victim and second cold target have
no precompletion acknowledgement with C. The blocked section test
redirects out of a cold line to an inaccessible section, then
checks the prefetch abort and guest resumption. All four profiles
pass in A, B, C and C with the guarantee deasserted. In the
deasserted case the contract and directed issue/retirement timings
match A. Rejected bursts tie across all legs. Existing tests also
cover each word offset in ARM and Thumb, modified code and
instruction maintenance, IRQ/FIQ, injected late external abort,
CP15 identity and physical geometry.

## RAM scheduling and timing

The existing I-cache RAM reads a set synchronously each time the
fetch stage advances. The next edge selects the requested word and
latches the hit/way along with the TLB result. C retains the checked
lookup address and the selected way's physical tag. A live demand
can use the buffered read during `FETCH_SINGLE` when its address
owns that probe, the registered TLB says permitted and cacheable,
the physical tag matches, and the set/way is outside the victim
reservation. Maintenance, an untrusted fill, or an unavailable
translation leaves the serial path in control.

The refill writes returned words into its existing buffer while
the tag/data RAM read port remains available. Replacement and
line commit still happen at the original `FILL_COMPLETE` cycle.
Hit under miss is disabled on that cycle. Existing registered
same-set RAM forwarding handles lookups after commit. Hits during
the fill leave replacement state unchanged. The path adds no
BRAM ports or refill slots. It adds a checked address register,
physical-tag register, comparisons and a selected-word mux. Check
the registered tag/TLB result to ACK/data, and the redirect-to-ACK
path, against the 104 MHz relationship before promotion.

## Workload opportunity and elapsed result

The observer shadows actual tag writes and invalidates and reads
the current section translation and permissions. It separates a
confirmed resident lookup from a missing way, the reserved victim,
or a translation that cannot be verified by the section observer.
It counts both a different-line demand in F2 and a redirect waiting
to reach F2. The ledger separates older issue/backend work or a
ready fetch-queue head from prospective exposed clocks. Direct
fetch enqueue remains speculative until retirement. The directed
cases join the target PC and ISA through actual retirement. The
bulk counters describe potential opportunities and physical
acceptances. The elapsed A/B gives the performance result.

B reproduces every frame and fixed-work window of the previous
early-restart run, including **14,696,883 clocks** for native
PolyCount. C saves **224,269 clocks (1.526%)** on top of B and
**455,647 clocks (3.052%)** against production. The native replay
submits 4,800 triangles per frame and preserves every frame's
retirements and issued work. Color, depth, object and indices
are byte-identical. Bench throughput rises from 25.08 (A) to 25.47
(B) and 25.87 (C) Ktriangles/s. C still takes 3,015.13 clocks per
triangle, 907.13 above the 2,108 goal.

In the median native B frame the observer sees 276,147
different-line clocks. It classifies 102,633 as second misses,
14 as unavailable or unverified section translations, and
173,500 as resident. Of the resident clocks, 63,707 overlap
earlier work or a ready fetch-queue head. The remaining 109,793
include 42,392 with a resident redirect target waiting to reach F2.
C enqueues 184,849 different-line instruction packets during live
fills and has 19,167 exposed resident clocks. The candidate changes
the sequence of requests and overlap. The clock difference comes
from elapsed time, independently of the overlap counters.
Measured retirement-based frontend stalls fall from 1,764,337 to
1,562,791 in the native B/C median frame. Exposed I-memory service
clocks are still 1,423,106 in C. The previous ideal-hit comparison
put an independent floor at 11,281,363 clocks with the current
execution pipeline and real I-TLB.

All fixed-work cases have zero trusted refill clocks in their
five scored windows. The evidence records warm-up activity
separately. Matrix loses three clocks in the median and at most
twelve in an individual scored window. Several other small
window changes occur with resident instruction working sets and
different run entry timing. The full suite repeats identically
within each configuration, checks guest work, and rejects a
deliberately wrong expected output in each case.

| Workload | A clocks | B clocks | C clocks | Saved A → B | Saved B → C | Saved A → C |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| SPMark04 matrix | 16,814 | 16,814 | 16,817 | 0 | -3 | -3 |
| SPMark04 transpose | 2,772 | 2,769 | 2,769 | 3 | 0 | 3 |
| GLES triangle edges | 12,229 | 12,229 | 12,229 | 0 | 0 | 0 |
| GLES 16-bit frame fill | 112,705 | 112,705 | 112,705 | 0 | 0 | 0 |
| GLES 16-bit tail fill | 726 | 726 | 726 | 0 | 0 | 0 |
| GLES 8-bit tail fill | 747 | 747 | 747 | 0 | 0 | 0 |
| Monkey Ball forward | 15,934 | 15,931 | 15,931 | 3 | 0 | 3 |
| Monkey Ball reverse | 15,934 | 15,931 | 15,931 | 3 | 0 | 3 |
| Sega Rally textured span | 15,424 | 15,424 | 15,424 | 0 | 0 | 0 |
| Sega Rally solid fill | 2,622 | 2,622 | 2,622 | 0 | 0 | 0 |
| Asphalt table | 21,396 | 21,396 | 21,394 | 0 | 2 | 2 |
| Asphalt double lookup | 11,961 | 11,961 | 11,961 | 0 | 0 | 0 |
| Asphalt single lookup | 7,756 | 7,756 | 7,756 | 0 | 0 | 0 |
| Sega Rally full scan | 2,391,228 | 2,391,228 | 2,391,228 | 0 | 0 | 0 |
| Thumb JPEG 8×8 | 35,903 | 35,903 | 35,903 | 0 | 0 | 0 |
| Native PolyCount | 14,928,261 | 14,696,883 | 14,472,614 | 231,378 | 224,269 | 455,647 |

**Decision.** Keep C as a fit candidate after a standalone B fit.
The incremental native gain repeats across all four frames. B
and C have separate netlists and the same explicit line guarantee.
The carry-forward paths to check at 104 MHz are the resident
physical-tag/permission compare and read mux into fetch, and the
no-request redirect ACK into the fetch stall decision. Routed
timing, resource mapping and native board performance are still
unmeasured. Production stays at `57ba6ef`.

[Three-leg evidence, all timing windows and directed target traces](evidence/arm9v2-icache-hum-v5-20261120.json).

## Reproduce

Use unique run names when the recorded directories already exist.
The frozen A input and native draw are from the previous early-restart
experiment.

```sh
base=build/sim/icache-hum-v5-bound
pin=build/sim/unit-hardware-boot-real-sdram/mt48lc16m16a2-verilator.v
python3 tests/cpu/arm9v2_board/icache_hum_overlay.py "$base"
for leg in early hum; do
  python3 tests/cpu/arm9v2_board/payload_clocks.py --name "icache-hum-v5-$leg-bound" \
    --arm9v2-netlist "$base/$leg.v" --cpu-wrapper "$base/ngage_cpu.sv" --board-overlay "$base" \
    --config 2:64 --flash-cache-bytes 32768 --stream-sdram --block-writeback \
    --icache-hum-counts --sdram-model "$pin"
  python3 tests/cpu/polycount_v5/run.py --name "icache-hum-v5-$leg-bound" \
    --netlist "$base/$leg.v" --cpu-wrapper "$base/ngage_cpu.sv" --board-overlay "$base" \
    --capture build/sim/polycount-v5/native-qualified --pin-model "$pin" --icache-hum-counts --legs i16
done
for leg in production early hum untrusted; do
  test_mode=1
  no_guarantee=0
  cpu="$base/ngage_cpu.sv"
  case "$leg" in
    production) test_mode=control; cpu=rtl/ngage_cpu.sv; netlist=rtl/arm9v2/arm925t_phone.v ;;
    untrusted) no_guarantee=1; netlist="$base/hum.v" ;;
    *) netlist="$base/$leg.v" ;;
  esac
  ARM9V2_ICACHE_RESTART_TEST=1 ARM9V2_ICACHE_HUM_TEST=$test_mode \
    ARM9V2_NO_LINE_GUARANTEE=$no_guarantee ARM9V2_SECTION_INDEX=xor \
    ARM9V2_ICACHE_BYTES=16384 ARM9V2_NETLIST="$netlist" ARM9V2_CPU_WRAPPER="$cpu" \
    sh tests/cpu/arm9v2_board/run-contract.sh "icache-hum-v5-$leg-modes"
done
python3 tests/cpu/arm9v2_board/icache_hum_score.py --output "$base/scorecard.json"
```
