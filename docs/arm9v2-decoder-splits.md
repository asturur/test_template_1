# v5 ARM9V2 decoder splits

Source audit of production `ngage-v5` at `78af1df`. A decoder operation
is a packet passed from D2 to S. The decoder initializes every packet
with `first=last=1`. Only `K_BLOCK` can hold D2 and emit another packet
from the same instruction. On each step it removes the next register,
advances the address offset by four, and marks the final packet.
[Production decode](../rtl/arm9v2/arm925t_phone.v#L2372) · [Register-list sequencer](../rtl/arm9v2/arm925t_phone.v#L2864)

| Instruction form | Decoder operations | Examples with two operations |
| --- | --- | --- |
| ARM `LDM` and `STM`, all four address modes | One per register | `LDMIA r0,{r2,r3}`, `STMDB sp!,{r4,lr}` |
| Thumb `LDMIA` and `STMIA` | One per register | `LDMIA r0!,{r2,r3}`, `STMIA r0!,{r2,r3}` |
| Thumb `PUSH` and `POP` | One per register, including optional `lr` or `pc` | `PUSH {r4,lr}`, `POP {r4,pc}` |
| Thumb long `BL` | One operation for each encoded halfword | The prefix writes the intermediate link value. The suffix branches and writes the return address. |

ARM `PUSH` and `POP` aliases encode `STMDB` and `LDMIA` for register
lists. The register-list rule applies to ordinary admitted transfers.
An empty list decodes as undefined. Base writeback rides with the final
transfer where enabled. Register banks, PC loads and CPSR restoration
follow the existing special cases. Thumb `BL` uses separate instruction
records with different PCs. The suffix can execute using the link
register without the immediately preceding prefix. Keeping that
behavior and the interrupt boundary is part of any call optimization.
[Thumb expansion and prefix handling](../rtl/arm9v2/upstream/rtl/cpu/arm9v2/arm9v2_decode.sv#L331) · [Thumb BL boundary evidence](ngage2-vs-5c-benchmark.md#L231)

Single loads and stores with address writeback already share a packet
with the base update. Register-count shifts and `MLA`/`SMLAL`/`UMLAL`
can wait in execute. `SMULL` has both result destinations in one packet.
`SWP` and `SWPB` use one packet and two locked memory phases. These are
separate optimization points downstream of decode.

An independent cross-check joined the archived `78af1df` native
PolyCount writeback trace to the original instruction encodings by PC.
At every observed PC, the nonfinal writebacks matched the extra
register-list packets. The inventory above comes from the decoder
control paths and applies across workloads. Production `57ba6ef`
keeps the same decoder as `78af1df`. The directed loop timings are
useful independently of how often a title executes the instruction.
For calls and returns, the later branch-to-target experiment measures
issue after both warmed predictions and redirects.
[Control-flow issue timing](arm9v2-control-flow.md).

## Next experiment

Try pairing two adjacent `STM` words in one issued packet, starting
with an aligned, writable, resident D-cache line and ordinary source
registers. The cache RAM has byte enables for the full line. Its
current store path sends one word's data and enables for each
update. A paired path would carry both source values into the same
line update. Keep the serial path for misses, line crossings, device
accesses and exceptional forms. Extend to stack writeback and then to
adjacent pairs in longer lists after the two-word path is verified.
[D-cache write enables](../rtl/arm9v2/arm925t_phone.v#L10287)

Use directed ARM and Thumb block-transfer loops to measure decoder
issue slots and elapsed clocks separately. Check the stored bytes,
registers, base updates and abort ordering. An earlier `LDM` pairing
experiment removed issue packets, but fallback and dependency costs
consumed most of the throughput gain. Paired stores avoid tracking two
pending load results and give a distinct test of the mechanism.
[Earlier load-pair experiment](spmark-polycount-v5.md#issuing-two-ldm-registers-together)

The subsequent production profile measured warm store throughput and
the bound for narrow and extended store pairing.
[Store-list experiment](arm9v2-store-pairs.md)

## Experiment 1. Skip a failed ARM register list

The simulation overlay evaluates a conditional ARM `LDM` or `STM` in
D2 when execute's registered NZCV is usable. It leaves the list alone
when S might write flags, A will write flags, or a CP15 flags refresh
is pending. Existing fences and flushes still apply. A known-false
first packet becomes the final packet. It keeps the original predicate,
PC and interrupt handling. Execute still verifies the condition. Fetch
faults, Thumb and taken transfers follow their usual paths. There is
no forwarding from the ALU flag result back to D2.

| Native PolyCount at 78 MHz | `78af1df` | Predicate overlay | Saved |
| --- | ---: | ---: | ---: |
| Median frame clocks | 15,019,070 | 14,946,484 | 72,586 |
| Issued register-list packets | 1,449,307 | 1,383,815 | 65,492 |
| Extra completed packets of failed lists | 289,237 | 223,745 | 65,492 |
| Retired instructions | 7,322,287 | 7,322,287 | 0 |

Elapsed clocks fell by 0.483% and simulated throughput rose from 24.93
to 25.05 Ktriangles/s. Each frame submits 4,800 triangles. Final object,
index, color and depth bytes match the original guest. Cache geometry,
memory RTL, firmware and clocks match `78af1df`. The direct-accumulate
overlay is absent from both runs. An independent ARM replay sampled
NZCV again. It counted 35,255 failed lists, matching the RTL and
correcting the earlier independent total of 37,122. Both independent
counts agree on the 289,237 extra packets.

The conservative guard eliminated 22.6% of the extra packets. Two
`POPLE` sites at GLES offsets `0x6db8` and `0x6e8c` account for 65,296
of the 65,492 removed packets. `POPHI` at `0x11c18` follows a `CMP`
immediately and retains all 65,322 of its extra packets.

All 15 fixed-work cases pass identical windows, guest output checks,
and wrong-output rejection in both legs. This includes the six SPMark
kernels, Thumb JPEG, Super Monkey Ball forward and reverse, Sega Rally
span, fill and scan, and the three Asphalt cases. Fourteen cases had
zero failed lists. Triangle edges had 16 failed lists and 128 extra
packets per window in both legs. The prototype removed no packets
from the fixed-work cases and had no measured regressions there.

The directed contract passes in all four profiles with zero or five
memory wait cycles and burst responses allowed or rejected. It crosses
all 16 NZCV values with every legal ARM predicate for loads and stores.
It also covers the undefined NV encoding, immediate successful and
failed flag writers, held lists, different list lengths and address
modes, System and Supervisor modes, PC loads and base writeback, a
prefetch abort, and an IRQ on a known-false list followed by precise
retry. The monitor rejects memory requests or register writes by failed
lists. The contract completes the same 235 failed lists and reduces
extra packets from 253 to 2.

**Recommendation: revise.** Keep this as a checked simulation result.
Prototype cancellation of the unissued tail after the first packet
resolves its predicate in execute. Use the hot `CMP`/`POPHI` case to
check coverage, and preserve the existing decode timing path. Measure
clocks again after measuring packet removal. Routed timing is unmeasured.
[Native, fixed-work and directed results](evidence/arm9v2-predicate-block-v5-20261119.json)

### Opcode measurement queue

Run paired fixed-work loops at the same 16 KiB I and D geometry. Use
dependent chains to measure latency in clocks per result and independent
instructions to measure throughput in clocks per operation. Warm the I
and D caches first. Measure misses, walks, writebacks and bus waits in
separate runs, with fixed inputs and verified registers, flags and memory.

| Opcode group | Dependent latency | Independent throughput and controls |
| --- | --- | --- |
| Passed `LDM`/`STM`, `PUSH`/`POP` | Load-to-first/last-register consumer and base-update consumer | Two-word and longer lists, same-line versus crossing, cache-hit versus refill. Count packets as well as elapsed clocks. |
| `MUL`, `MLA`, `SMULL`, `UMULL`, `SMLAL`, `UMLAL` | Low/high result and flags consumers, accumulator feedback | Interleave distinct destinations. Compare the checked early `SMULL` and direct-accumulate replays before duplicating them. |
| Scalar `LDR` and variants | Immediate ALU, branch, store or address consumer | Independent loads on resident lines, then repeat at forced miss and walk. Keep byte/halfword and sign extension visible. |
| ARM and Thumb shifts, scaled loads/stores | Shift count produced just before use, then base or index produced just before the address | Independent shifts and scaled addresses, with ready register shift enabled as in production. |
| Branch and return | Dependent flags/target and redirect-to-target latency | Trained direct branches, indirects, and ARM/Thumb call/return loops. Measure correct hits separately from redirects and I misses. |
| Remaining slower forms | `SWP`/`SWPB` result, PSR or CP15 flag consumers, and Thumb `BL` halfword sequence | Separate locked or serial operations from ordinary ARM/Thumb ALU and memory forms. Record code alignment and architectural boundaries. |

The existing [shift and multiply replays](spmark-polycount-v5.md#production-register-shift-and-incremental-smull)
provide checked workload-level comparisons. Use the [direct accumulate A/B](spmark-polycount-v5.md#direct-accumulate-on-production-smull)
for the same production control. The [earlier `LDM` pairing run](spmark-polycount-v5.md#issuing-two-ldm-registers-together)
uses an older CPU control and supplies coverage and fallback guidance.

### Reproduce the predicate experiment

```sh
mkdir -p build/sim/predicate-block-v5
git show 78af1df:rtl/arm9v2/arm925t_phone.v > build/sim/predicate-block-v5/control.v
python3 tests/cpu/arm9v2_board/predicate_block.py \
  build/sim/predicate-block-v5/control.v build/sim/predicate-block-v5/candidate.v
python3 tests/cpu/polycount_v5/run.py --name fresh-predicate-polycount \
  --netlist build/sim/predicate-block-v5/control.v \
  --capture build/sim/polycount-v5/native-qualified \
  --pin-model build/sim/unit-hardware-boot-real-sdram/mt48lc16m16a2-verilator.v \
  --legs i16 predicate-block
for leg in control candidate; do
  python3 tests/cpu/arm9v2_board/payload_clocks.py --name "fresh-predicate-$leg" \
    --arm9v2-netlist "build/sim/predicate-block-v5/$leg.v" --config 2:64 \
    --flash-cache-bytes 32768 --stream-sdram --block-writeback --predicate-block-counts \
    --sdram-model build/sim/unit-hardware-boot-real-sdram/mt48lc16m16a2-verilator.v
  ARM9V2_BLOCK_PREDICATE_TEST=1 ARM9V2_SECTION_INDEX=xor ARM9V2_ICACHE_BYTES=16384 \
    ARM9V2_NETLIST="build/sim/predicate-block-v5/$leg.v" \
    sh tests/cpu/arm9v2_board/run-contract.sh "fresh-predicate-$leg"
done
```
