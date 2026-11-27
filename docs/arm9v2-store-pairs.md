# v5 passed store-list timing and pairing bound

Experiment 5 profiles production `57ba6ef` with 78 MHz, 16 KiB I and D
caches, two ways, 32-byte lines, the XOR TLB and the production SDRAM
and DDR paths. The native torus and all 15 original fixed-work cases
match their existing elapsed counters and checked outputs. This is
instrumented production RTL with no experimental CPU path enabled.

## What the warm port can accept

All four directed profiles reproduce the same warm schedule. Elapsed
clocks are measured between retired NOP markers. Within each window
the accepted store words are consecutive, at one word per clock.

| Warm directed sequence | Accepted words | Elapsed clocks |
| --- | ---: | ---: |
| 16 pairs of ARM `STR` | 32 | 33 |
| 16 ARM two-word `STMIA` lists without writeback | 32 | 33 |
| 16 ARM two-word `STMIA!` lists | 32 | 33 |
| 16 ARM four-word `STMIA` lists without writeback | 64 | 65 |
| 16 ARM four-word `STMIA!` lists | 64 | 65 |
| 16 ARM two-word `PUSH` lists | 32 | 33 |
| 16 Thumb two-word `STMIA!` lists | 32 | 33 |
| 16 Thumb four-word `STMIA!` lists | 64 | 65 |
| 16 Thumb two-word `PUSH` lists | 32 | 33 |

The control already accepts the two words of a list on adjacent
clocks. Writeback rides with the list and adds no steady clock in these
windows. A pair crossing a 32-byte line takes two consecutive accepted
words and has two hits on separate lines. The two ordered device
writes take 31, 58, 63 or 157 marker-to-marker clocks, depending on
the contract responder. Neither device write qualifies as a hit.

The original CPU passes checks for distinct source values, readback,
base update, a falsely predicated list, uncached device order and
translation and permission faults. The 1 MiB section and 4 KiB small
page tests verify that the first word stays written when the second
aborts, while base writeback is restored. The burst/scalar responders
and both wait settings pass. These tests characterize the serial path.

## Eligibility in the original workloads

The observer requires a completed store beat with a writable resident
hit, permission, write-back caching, no unresolved data lock and no
alignment fault. Pairs are disjoint by list position and require two
adjacent aligned word addresses in the same line. The narrow form is
an ARM `STMIA` of exactly two ordinary registers with no base
writeback, PC, user-bank transfer, or base in the list. Banked source
registers in the current mode are outside that form. The broader
pair count includes additional address modes, writeback, stack and
Thumb forms, and disjoint pairs inside longer lists. It describes
the addresses and hit conditions, before adding those semantics to
the implementation.

| Measured workload | Production clocks | Narrow pairs | Broader pairs | Optimistic clocks with broader pairs |
| --- | ---: | ---: | ---: | ---: |
| Native PolyCount | 14,928,261 | 59,437 | 227,531 | 14,700,730 |
| SPMark matrix | 16,814 | 0 | 48 | 16,766 |
| SPMark transpose | 2,772 | 0 | 0 | 2,772 |
| GLES triangle edges | 12,229 | 0 | 64 | 12,165 |
| GLES 16-bit frame fill | 112,705 | 0 | 0 | 112,705 |
| GLES 16-bit tail fill | 726 | 0 | 0 | 726 |
| GLES 8-bit tail fill | 747 | 0 | 0 | 747 |
| Monkey Ball forward span | 15,934 | 0 | 0 | 15,934 |
| Monkey Ball reverse span | 15,934 | 0 | 0 | 15,934 |
| Sega Rally textured span | 15,424 | 0 | 0 | 15,424 |
| Sega Rally solid fill | 2,622 | 0 | 0 | 2,622 |
| Sega Rally full scan | 2,391,228 | 0 | 18,316 | 2,372,912 |
| Asphalt table | 21,396 | 0 | 0 | 21,396 |
| Asphalt double lookup | 11,961 | 0 | 0 | 11,961 |
| Asphalt single lookup | 7,756 | 0 | 0 | 7,756 |
| Thumb JPEG 8×8 | 35,903 | 0 | 722 | 35,181 |

Native eligibility is from the median frame. The fixed-work clock
medians use five scored windows after two warm-ups. Pair counts use
the first scored window. The optimistic column subtracts one elapsed
clock per observed disjoint pair. It assumes each removed issue slot
shortens elapsed time, with free second-operand delivery, cache
forwarding and fallback. The model is a bound for the counted pairs.
All observed elapsed timings tie their corresponding production
controls. The native replay matches 4,800 triangles, original color
and depth, indices, saved object and retired work. The 15 payloads
match inputs and retirements and pass repeat and wrong-output controls.

The native median contains 431,290 scalar stores and 560,551 words
from 140,308 store lists. Of 265,302 disjoint list pairs, 34,498 cross
a line and 227,531 pass the resident-pair checks. The two words are
already accepted on consecutive clocks for 227,413 of those pairs.
The broad count includes 158,453 pairs in longer lists and 141,166
stack pairs. The narrow form has a 59,437-clock optimistic saving
(0.40% of native elapsed time). The broader bound is 1.52%. The
full Sega scan's pairs are all Thumb stack lists. JPEG pairs are
Thumb writeback forms. Reaching either game case requires wider
coverage than the narrow ARM form.

## Why pairing needs a wider change

The line RAM already takes a full line and per-byte enables on one
edge. The store interface feeding it carries one 32-bit operand.
The controller replicates that operand across the line and enables
bytes in one word. The short-hit store/load forwarding selects one
word address and value, and the eviction forwarding record keeps one
32-bit value replicated across its mask. Enabling a second word with
the existing data path would write copies of the first operand.
[Store bus](../rtl/arm9v2/arm925t_phone.v#L1161) · [Line data and mask](../rtl/arm9v2/arm925t_phone.v#L10264) · [Victim merge and short forwarding](../rtl/arm9v2/arm925t_phone.v#L11400)

Saving the issue slot requires the decoder to track both sources and
deliver them in the same packet. Saving the memory slot requires
carrying both values and masks through cache acceptance, forwarding
both to ahead-of-write reads and dirty victims, and leaving the
existing ordered serial path available for an ineligible pair. On a
fallback that faults on word two, word one must remain visible while
the base update is suppressed. This affects the issue, execute,
writeback and cache interfaces. A wider mask by itself is insufficient.

**Decision: revise the design before implementation.** Keep the
profile and optimistic model. The narrow ARM form has a modest bound
and no eligible pairs in the fixed-work set. The broader counts
justify evaluating a two-value cache interface with longer lists and
stack forms as explicit targets. This experiment did not install or
time a paired-store RTL candidate.
[Raw windows, eligibility, and directed timing](evidence/arm9v2-store-pairs-v5-20261119.json)

## Reproduce

```sh
mkdir -p build/sim/store-list-v5
git show 57ba6ef:rtl/arm9v2/arm925t_phone.v > build/sim/store-list-v5/control.v
ARM9V2_STORE_LIST_TEST=1 ARM9V2_ICACHE_BYTES=16384 ARM9V2_SECTION_INDEX=xor \
  ARM9V2_NETLIST=build/sim/store-list-v5/control.v \
  sh tests/cpu/arm9v2_board/run-contract.sh fresh-store-list-v5
python3 tests/cpu/arm9v2_board/store_list_timing.py \
  build/sim/arm9v2/contract-fresh-store-list-v5 --output build/sim/store-list-v5/directed.json
python3 tests/cpu/polycount_v5/run.py --name fresh-store-list-v5 --store-list-counts \
  --netlist build/sim/store-list-v5/control.v --legs i16 \
  --capture build/sim/polycount-v5/native-qualified \
  --pin-model build/sim/unit-hardware-boot-real-sdram/mt48lc16m16a2-verilator.v
python3 tests/cpu/arm9v2_board/payload_clocks.py --name fresh-store-list-v5 \
  --arm9v2-netlist build/sim/store-list-v5/control.v --config 2:64 \
  --flash-cache-bytes 32768 --stream-sdram --block-writeback --store-list-counts \
  --sdram-model build/sim/unit-hardware-boot-real-sdram/mt48lc16m16a2-verilator.v
```
