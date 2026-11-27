# v5 control-flow delivery at 78 MHz

Production `57ba6ef` uses 16 KiB I and D caches with two ways and
32-byte lines, the XOR section TLB, and the production SDRAM and DDR
paths. The probe follows the branch and successor through execute and
writeback. It checks the successor's PC and ARM/Thumb state at
retirement, then reads the clock when S handed that packet to A.
An accepted wrong-path packet cannot satisfy this check.

## Directed results

The interval starts when the branch packet enters A. For `LDM` and
`POP` it starts at the packet that writes PC. For Thumb long `BL` it
starts at the suffix. The resolution column uses A finish for direct
branches, `BX`, and paired Thumb suffixes. It uses W for the other PC
writes. Negative values mean useful work issued before confirmation.

| Warm path on production | Branch issue to successor | Resolution to successor |
| --- | ---: | ---: |
| Conditional branch, correctly predicted taken or fall-through | 1 | 0 |
| ARM direct call, steady | 1 | 0 |
| Indirect `BX` with a steady target | 1 | 0 |
| ARM or Thumb `BX LR` | 1 | 0 |
| ARM `MOV PC,LR`, ARM `LDM PC`, Thumb `POP PC` | 1 | −2 |
| Thumb long `BL` suffix, correctly predicted | 1 | 0 |
| Conditional direction or indirect target mispredicted, I-side hit | 8 | 7 |
| ARM direct call with no BTB tag, I-side hit | 5 | 4 |

The four directed profiles use scalar or burst responses with zero or
five added wait clocks. The zero-wait burst profile measures 28 clocks for
a cold instruction line at the RAM `BX` target and 20 for the same
resident line after I-TLB invalidation. The exclusive active I-side
intervals are 22 refill clocks and 12 walk clocks respectively. This is
directed responder timing. The game and torus replays use the SDRAM pin
model. Both index variants pass ARM/Thumb interworking, guest
register/stack results, a forced IRQ on Thumb `BX LR` with precise
resumption, the existing FIQ and fault checks, and CP15 and I/D capacity
checks in all four profiles.

The first correctly predicted call immediately after fetch restarted
takes two clocks in the directed trace. The cached target is already at
the fetch queue head while the call is at D2. The ordinary target still
takes the empty D1 slot on the call's D2-to-S clock. It leaves a one-clock
issue gap. Once the queue has work in it the same call issues its
successor on the next clock. This is a demonstrated empty-queue latency,
with potential overlap from a preceding redirect or refill.

## Isolated predictor index A/B

The 256-entry branch target buffer (BTB) indexes on PC bits `[8:1]`.
Because ARM is word aligned, it uses only the even slots in that table.
The overlay indexes the same entries with `PC[8:1] ^ PC[16:9]`. It
applies the same index to lookup, update and the valid-bit checks for
predicted, sequential and redirected fetch. The tag keeps all high PC
bits and the source ISA, so the index change preserves address and mode
identity. Branch resolution, predictors' state transitions, return
stack, caches, memory and guest software are identical in the two legs.

The observer separates correct tagged predictions, wrong direction or
target with a tag, taken transfers without a usable tag, and sequential
fall-through without a tag. A missing tag on a direct branch can take
the decode redirect. A correctly predicted target can miss in the
instruction cache or TLB. For every interval the ledger prioritizes any
S-to-A acceptance, older/backend blockage, I-TLB activity, I-cache
activity, then other frontend clocks. A target-owned wait count requires
the last no-issue interval to have a single matching virtual line or page
owner. This is a conservative attribution. A frontend interval can
also reflect a preceding redirect or work that overlapped elsewhere.
The reported savings use elapsed benchmark clocks.

The 15 fixed-work cases use five scored windows after two warm-ups.
Each leg repeats the complete windows and rejects a deliberately
wrong expected output. The native medians use three warmed frames.
The observer itself exactly reproduces production's previous baseline.

| Workload | Production clocks | XOR clocks | Clocks saved | Taken BTB misses, production → XOR |
| --- | ---: | ---: | ---: | ---: |
| SPMark04 matrix | 16,814 | 16,844 | -30 | 67 → 129 |
| SPMark04 transpose | 2,772 | 2,772 | 0 | 0 → 0 |
| GLES triangle edges | 12,229 | 12,149 | 80 | 48 → 33 |
| GLES 16-bit frame fill | 112,705 | 112,652 | 53 | 1 → 0 |
| GLES 16-bit tail fill | 726 | 719 | 7 | 1 → 0 |
| GLES 8-bit tail fill | 747 | 747 | 0 | 0 → 0 |
| Monkey Ball forward | 15,934 | 15,934 | 0 | 0 → 0 |
| Monkey Ball reverse | 15,934 | 15,934 | 0 | 0 → 0 |
| Sega Rally textured span | 15,424 | 15,424 | 0 | 0 → 0 |
| Sega Rally solid fill | 2,622 | 2,622 | 0 | 0 → 0 |
| Asphalt table | 21,396 | 21,383 | 13 | 1 → 0 |
| Asphalt double lookup | 11,961 | 11,961 | 0 | 0 → 0 |
| Asphalt single lookup | 7,756 | 7,747 | 9 | 1 → 0 |
| Sega Rally full scan | 2,391,228 | 2,391,224 | 4 | 1 → 1 |
| Thumb JPEG 8×8 | 35,903 | 35,524 | 379 | 132 → 2 |
| Native PolyCount | 14,928,261 | 14,796,149 | 132,112 | 110,673 → 89,992 |

The XOR index improves seven fixed-work cases, ties seven, and slows
the matrix by 30 clocks. Matrix picks up 62 taken BTB misses. Thumb
JPEG removes 130. Native PolyCount saves **132,112 clocks (0.885%)**
with the same 4,800 triangles, 7,322,287 retired instructions in the
median frame, and byte-identical color, depth, indices and object
output. Elapsed clocks per triangle fall from 3,110.05 to 3,082.53,
leaving 974.53 clocks per triangle to the 2,108 target at 78 MHz.

There are 34,944 wrong tagged predictions and 110,673 taken BTB misses
in the production median frame. The overlay has 39,713 and 89,992
respectively. Taken conditional misses fall from 52,459 to 31,944.
ARM `BX LR` misses rise from 27,640 to 32,665. The elapsed change
includes different speculative fetch and refill schedules. One tag
miss corresponds to no fixed clock penalty.

Of 347,280 correct tagged predictions in the native production
median, 304,759 issue the successor on the next clock. Exactly 5,613
have an intervening gap made entirely of frontend clocks, including
4,155 direct calls and 1,447 ARM `BX LR` returns. Saving one clock
on every one would be 0.038% of the frame. The measured empty-D1 case
is one of the mechanisms behind this bound. No fixed-work case had
an entirely frontend gap on a correct tagged prediction in its
selected median window. A decoder bypass for that gap has no measured
elapsed saving. The control's I-side interval counters record
1,229,028 refill-active and 600 walk-active clocks inside branch
delivery gaps. Conservative line/page matching attributes 444,804 and
244 of those clocks to the target. These are parts of the observed
intervals.

Keep the XOR result offline. The speedup is measurable across several
workloads, with a matrix regression and only 27.52 clocks per
triangle recovered in PolyCount. FPGA timing and board performance are
unmeasured. The production branch and bitstream were left in place.

[Per-workload timing windows, exclusive gap accounting and directed evidence](evidence/arm9v2-control-flow-v5-20261119.json).

## Reproduce

Use distinct run names if the listed directories already exist. The
runner checks guest outputs and rejects bad expected outputs. The
reference is the production store-list profile on the same source and
memory setup.

```sh
mkdir -p build/sim/control-flow-v5
git show 57ba6ef:rtl/arm9v2/arm925t_phone.v > build/sim/control-flow-v5/control.v
python3 tests/cpu/arm9v2_board/control_flow_overlay.py \
  build/sim/control-flow-v5/control.v build/sim/control-flow-v5/xor-btb-overlay.v
for variant in refined xor-btb; do
  case "$variant" in
    refined) netlist=control ;;
    xor-btb) netlist=xor-btb-overlay ;;
  esac
  source="build/sim/control-flow-v5/$netlist.v"
  ARM9V2_CONTROL_FLOW_TEST=1 ARM9V2_SECTION_INDEX=xor ARM9V2_ICACHE_BYTES=16384 \
    ARM9V2_NETLIST="$source" sh tests/cpu/arm9v2_board/run-contract.sh "control-flow-v5-$variant-irq"
  python3 tests/cpu/arm9v2_board/payload_clocks.py --name "control-flow-v5-$variant" \
    --arm9v2-netlist "$source" --config 2:64 --flash-cache-bytes 32768 \
    --stream-sdram --block-writeback --control-flow-counts \
    --sdram-model build/sim/unit-hardware-boot-real-sdram/mt48lc16m16a2-verilator.v
  python3 tests/cpu/polycount_v5/run.py --name "control-flow-v5-$variant" \
    --netlist "$source" --legs i16 --control-flow-counts \
    --capture build/sim/polycount-v5/native-qualified \
    --pin-model build/sim/unit-hardware-boot-real-sdram/mt48lc16m16a2-verilator.v
done
python3 tests/cpu/arm9v2_board/control_flow_score.py --control control-flow-v5-refined \
  --candidate control-flow-v5-xor-btb --reference store-list-v5 \
  --output build/sim/control-flow-v5/scorecard.json
```
