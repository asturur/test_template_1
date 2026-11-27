# v5 I-cache early restart at 78 MHz

Same-order early restart saves **231,378 median PolyCount clocks
(1.550%)** on production `57ba6ef`. Both 16 KiB caches retain two ways
and 32-byte lines. The XOR section TLB, production predictor, SDRAM
scheduler and DDR flash transport, 32 KiB flash cache and 78 MHz clock
match. The original 4,800-triangle draw, every frame's retired work,
color and depth, indices and object match byte for byte.

## Where the delay occurs

The I-cache requests eight 32-bit words in linear address order. The
MiSTer line bridge already hands them back in order as they arrive.
SDRAM's stream adapter receives a complete 32-bit word and emits its
two halves on adjacent CPU clocks. The CPU bridge registers the pair,
then acknowledges it. DDR flash provides a decoded 64-bit beat
containing two words. The bridge puts the words into its buffer and
returns at most one CPU word per clock. In the measured native
production frame, the bridge takes one clock from the completed board
word to its I-cache acknowledgement for SDRAM. The flash path averages
1.87 clocks for the requested word, including serialization of the
second word and intervening older beats.

The cache's existing refill buffer uses word-valid bits to
acknowledge an arriving instruction before line commit. The fetch
queue marks that packet pending and withholds it from decode until
the entire line completes. The existing no-late-error path can lift
that hold for a wrapped 16-byte line. v5 uses 32-byte lines and the
CPU wrapper ties its no-late-error input low.

The trial enables the same fetch-queue release for a 32-byte refill
whose bridge supplies a registered no-late-error guarantee. The
bridge samples this at line admission and qualifies it with the
existing ACK. The board's actual SDRAM and DDR line responders have
no late error signals. Rejected lines use the original scalar path.
In the directed responder the deliberate late-error line is marked
fallible and retains the original pending and abort path. An
unexpected error on a guaranteed line is a simulation failure. Both
legs use the same burst order, line addresses, memory transport and
memory clock.

## Directed arrival and issue traces

Clocks are relative to the I-cache miss transition. The 16-bit and
64-bit responders are directed transport fixtures. Main workloads
run the production SDRAM pin model and production flash path.

| Demand | Complete word at board | CPU word ACK | Fetch enqueue | Whole line complete | Production issue | Early issue |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| RAM ARM, word 0 | 4 | 5 | 6 | 20 | 24 | 10 |
| RAM ARM, word 7 | 18 | 19 | 20 | 20 | 24 | 24 |
| Flash ARM, word 0 | 3 | 4 | 5 | 12 | 16 | 9 |
| Flash Thumb high halfword, word 7 | 6 | 11 | 12 | 12 | 16 | 16 |

Issue is the S-to-A handshake of the demanded instruction. The
fixture also verifies that its PC and ARM/Thumb state retire. Both
ISAs cover all eight offsets on both transports. In the burst
profiles the issue advance is 14, 12, 10, 8, 6, 4, 2, 0 clocks in RAM
and 7 through 0 on the flash responder. Five added wait clocks shift
both legs by five. Rejected-burst profiles match exactly. The early
RAM offset-zero call also retires its body and redirects back to its
caller before the line completes. The caller issues seven clocks
after completion. Only one line can own the refill path. Older work
and a different-line target can consume the first instruction's
head start.

All four directed profiles pass in both legs. They check guest
register results, ARM/Thumb interworking, taken returns
during a fill, modified code after clean and invalidate, maintenance
from a just-filled line, prefetch permission and injected late
external abort, IRQ/FIQ, and the existing CP15 I/D capacity and
two-way I-cache checks. The bridge asserts one owned burst and
unchanged addresses and framing throughout that burst.

## Native delay accounting and limits

The median production frame completes 184,703 refills. SDRAM
accounts for 178,112 and flash for 6,591. Of the SDRAM fills,
146,477 demand word zero. Starting at the target word would
preserve their current order. Critical-word-first would change the
request protocol and only directly moves the first demanded word in
the other offsets.

Before line completion, 20,169 production fills and 22,625 early
fills see a redirect or epoch change. These are separated as canceled original fetch
contexts. A completed line can still be reused, and the early
variant can issue a useful instruction before its context changes.
Counts therefore identify context changes, with no claim that all
of those fills are wasted. The directed trace distinguishes an
already-retired instruction before redirect from killed work.

For the production fills whose original context stays live, the
pre-acknowledgement intervals total 361,425 clocks to the memory
offer, 1,692,972 from offer to board word, and 169,266 from board word
to CPU acknowledgement. These are raw intervals and can overlap
older CPU work. The later interval from demanded ACK to line
completion totals 2,139,567 clocks. It partitions into 1,796,895
with the referenced fetch blocked and no competing issue or backend
owner, 231,465 overlapped with issue or backend work, zero assigned
to I-TLB, and 111,207 other frontend clocks. The main replay
independently observes 608 exposed I-TLB clocks in its whole-frame
retirement-based partition.

The early leg's live contexts have 154,061 demanded packets leave
the fetch queue before commit. Its equivalent tail has 152,845
blocked original fetch clocks, 778,123 overlapped clocks and
1,153,296 clocks with the gate open and no acceptance or older
blockage. These phase counts describe where work moved. The
end-to-end improvement is 231,378 clocks. Total exposed I-memory
service in the independent frame partition only falls from
1,432,956 to 1,423,984 clocks. The observed offer-to-word latency
and the one-line service constraint remain the larger targets.
One route is to allow a resident hit to a different I-cache line
while the original fill drains. Starting the next needed line
earlier would also address the wait before data arrives. Neither
requires changing cache capacity.

| Native warmed median | Clocks | Clocks/triangle | Ktriangles/s at 78 MHz |
| --- | ---: | ---: | ---: |
| Production | 14,928,261 | 3,110.05 | 25.08 |
| Same-order early restart | 14,696,883 | 3,061.85 | 25.47 |
| Ideal I hits at identical geometry | 11,281,363 | 2,350.28 | 33.19 |

The ideal leg supplies known immutable instruction words at the
cache's hit boundary, keeps the real I-TLB and frontend, and has
zero I refills in the scored windows. It removes 3,646,898 elapsed
clocks. Real early restart recovers 6.34% of that diagnostic gap.
Even the ideal leg is 242.28 clocks per triangle above the
2,108-clock objective.

## Fixed-work scorecard

The control reproduces all previous windows. Both variants repeat
their seven windows and deliberately reject a wrong expected output.
The medians use five scored windows after two warm-ups.

| Workload | Production clocks | Early restart clocks | Saved |
| --- | ---: | ---: | ---: |
| SPMark04 matrix | 16,814 | 16,814 | 0 |
| SPMark04 transpose | 2,772 | 2,769 | 3 |
| GLES triangle edges | 12,229 | 12,229 | 0 |
| GLES 16-bit frame fill | 112,705 | 112,705 | 0 |
| GLES 16-bit tail fill | 726 | 726 | 0 |
| GLES 8-bit tail fill | 747 | 747 | 0 |
| Monkey Ball forward | 15,934 | 15,931 | 3 |
| Monkey Ball reverse | 15,934 | 15,931 | 3 |
| Sega Rally textured span | 15,424 | 15,424 | 0 |
| Sega Rally solid fill | 2,622 | 2,622 | 0 |
| Sega Rally full scan | 2,391,228 | 2,391,228 | 0 |
| Asphalt table | 21,396 | 21,396 | 0 |
| Asphalt double lookup | 11,961 | 11,961 | 0 |
| Asphalt single lookup | 7,756 | 7,756 | 0 |
| Thumb JPEG 8×8 | 35,903 | 35,903 | 0 |

**Decision.** Queue a standalone fit for the repeatable native
gain and small hardware delta. Bind the trusted-line signal
explicitly to the production backends before promotion. Check
the registered line grant and ACK into the cache release bit,
and the release-to-fetch-queue path, under the 104 MHz constraint.
This overlay adds a grant bit and reuses the existing buffered
word and queue path. FPGA timing and native hardware performance
are unmeasured. The patch remains offline.

[Verified workload windows, output digest and directed traces](evidence/arm9v2-icache-restart-v5-20261120.json).

## Reproduce

Use a fresh run name if a result directory already exists.

```sh
base=build/sim/icache-restart-v5
pin=build/sim/unit-hardware-boot-real-sdram/mt48lc16m16a2-verilator.v
mkdir -p "$base"
git show 57ba6ef:rtl/arm9v2/arm925t_phone.v > "$base/control.v"
git show 57ba6ef:rtl/ngage_cpu.sv > "$base/ngage_cpu_control.sv"
python3 tests/cpu/arm9v2_board/icache_restart_overlay.py \
  "$base/control.v" "$base/ngage_cpu_control.sv" "$base"
for leg in control early; do
  early=0
  set -- i16 ideal-i16
  if [ "$leg" = early ]; then
    early=1
    set -- i16
  fi
  ARM9V2_ICACHE_RESTART_TEST=1 ARM9V2_ICACHE_RESTART_EARLY=$early \
    ARM9V2_SECTION_INDEX=xor ARM9V2_ICACHE_BYTES=16384 \
    ARM9V2_NETLIST="$base/$leg.v" ARM9V2_CPU_WRAPPER="$base/ngage_cpu_$leg.sv" \
    sh tests/cpu/arm9v2_board/run-contract.sh "icache-restart-v5-$leg-offsets"
  python3 tests/cpu/arm9v2_board/payload_clocks.py --name "icache-restart-v5-$leg" \
    --arm9v2-netlist "$base/$leg.v" --cpu-wrapper "$base/ngage_cpu_$leg.sv" \
    --config 2:64 --flash-cache-bytes 32768 --stream-sdram --block-writeback \
    --icache-restart-counts --sdram-model "$pin"
  python3 tests/cpu/polycount_v5/run.py --name "icache-restart-v5-$leg" \
    --netlist "$base/$leg.v" --cpu-wrapper "$base/ngage_cpu_$leg.sv" \
    --capture build/sim/polycount-v5/native-qualified --pin-model "$pin" \
    --icache-restart-counts --legs "$@"
done
python3 tests/cpu/arm9v2_board/icache_restart_score.py --output "$base/scorecard.json"
```
