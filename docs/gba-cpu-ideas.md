# GBA_MiSTer CPU comparison — 2026-11-17

Source-only review of MiSTer-devel/GBA_MiSTer `rtl/gba_cpu.vhd`, pinned to
`93790a023395bbd90e5eaf4dfb2cb5910afd55f5`, retrieved with `gh`. Compared with
the current N-Gage 5L implementation and existing resource audits. No GBA
synthesis, timing report or matched benchmark was obtained; no production RTL,
running simulation, hardware or pending matched-fit inputs were changed.

## Decision

Keep the present pipeline and finish the banked-TLB measurement. This GBA CPU
offers clear examples of explicit operation sequencing and registered arithmetic
boundaries, but no demonstrated improvement over our current DSP mapping,
register-file storage, branch prediction or memory overlap. Its simpler execution
ownership relies on serializing instructions. It does not supply the ARM920
translation, cache or abort interfaces we need.

Do not interpret its reported emulated cycles as FPGA clocks per instruction.
`new_cycles_out`, wait-state tables and prefetch counters model guest timing;
the execution state machines consume separate `clk100` edges. The clock signal's
name also does not establish routed 104 MHz closure.

## Source comparison

All GBA line references below refer to the pinned
[source](https://github.com/MiSTer-devel/GBA_MiSTer/blob/93790a023395bbd90e5eaf4dfb2cb5910afd55f5/rtl/gba_cpu.vhd).

| Area | Observed GBA implementation | Implication for N-Gage |
| --- | --- | --- |
| Instruction overlap | Fetch buffer and separate decode operate alongside execution. `FETCH_OP` accepts an instruction, then `CALC` waits for completion (lines 744–867, 1064–1208). | Useful front-end overlap, but one execution owner. No one-per-clock execution pipeline to transplant. |
| Memory | Fetch/data share one bus. Data issue waits for the fetch buffer to be ready; execution waits for `gb_bus_done`, then optionally writes the base register (643–646, 2617–2789). | Clear ownership, but no parallel independent load/store execution. Bus ports have no abort input (9–77); ARM920 precise faults cannot be inferred from this design. |
| Branches | Resolve target, raise `branchnext`, redirect through `jump`; flush decode and discard an outstanding wrong-path fetch (744–765, 825–830, 2129–2148, 2588–2615). | Simple explicit recovery is useful reference material. No direction/target predictor appears in this CPU. Our existing prediction and recovery are more relevant to throughput. |
| Multiply | Registered operands, signed/unsigned full product, a four-edge `MULCALCMUL` residence, then optional low/high accumulation and separate result writes (2383–2499). | Already have a registered full product fitted to three DSP blocks. GBA source gives no evidence of a better DSP count or hard accumulator mapping. Its modeled operand-dependent cycle charge does not shorten the four-edge product-state residence. |
| Register file | Active 18-word array plus explicit banked registers; reset/save-state access and bank copying (110–146, 674–715, 902–1040). | No inferred BRAM RF advantage shown. Our two-writer/five-read MLAB implementation already addresses this cost; its stronger port contract cannot be replaced by this serial organization without redesign. |
| Shifts | One shared shift service for arithmetic/address work; separately registered LSL/LSR/ASR/ROR/RRX results followed by result selection (2172–2232, 2648–2667, 3056–3171). | Explicit timing boundaries are useful. Multiple parallel shift results are not evidence of ALM savings. Our CPU already instantiates one shared barrel-shift module. |
| Complex instructions | Dedicated block-transfer sequencer with register-list traversal, address increment, per-word completion and base update (2791–2999). | A readable reference for local control. Our predecode already sequences LDM/STM/SWP/long multiply; replacing it requires preserving user-bank, abort and exception-return behavior. |

## Physical-clock schedule example

Derived from the clocked processes, not measured in simulation. Assume an
ordinary immediate ADD, no PC destination, no exception return, `gb_on=1`,
continuous `do_step`, and the following instruction decoded in time:

| Edge | GBA action |
| --- | --- |
| E0 | Accept decoded instruction; assert registered `execute_start`; enter `CALC`. |
| E1 | `ALUSTART` captures operands; select `ALUCALC`. |
| E2 | `ALUCALC` registers arithmetic result. |
| E3 | `ALUSETFLAGS` produces writeback control/result and `calc_done`. |
| E4 | Main process writes destination and returns to `FETCH_OP`. |
| E5 | Earliest next instruction acceptance. |

Fetch and decode can run during these edges. They do not turn this schedule
into one instruction started each clock. Shifted operations add more states.
Our qualified favorable stream already starts 224 instructions in 224 clocks;
its remaining dependent-load and cache costs need different solutions.

## Small later experiment suggested by the comparison

After the current area measurement, **screen the existing barrel shifter's
fitted cost before considering a rewrite**. This is an original area hypothesis,
not an optimization demonstrated by GBA. Our `zap_shifter_shift.sv` expresses
left, logical-right, arithmetic-right and rotate operations separately. A shared
right-shift network, bit reversal for left shifts, and explicit fill/carry rules
may reduce duplicated logic. Quartus may already share enough to make this
unproductive; inspect the synthesized/fitted leaf first.

Keep the existing interface, zero additional pipeline stages, and current
throughput for the first candidate. Adding input/output reversal muxes may
worsen delay, so fewer operators in source is insufficient evidence. Do not
claim an ALM saving or promise an implementation before that screen.

If warranted: independent arithmetic oracle across all 256 shift amounts,
both carries, every shift type and randomized/boundary operands; explicitly
cover 0/31/32/33/255, RRX, rotate multiples of 32 and ARM/Thumb immediate
normalization. Then run shifted-address and flag-dependent CPU cases plus the
existing original workloads. Require identical fixed-work cycles and outputs,
and a matched fit showing net ALM benefit without a material timing regression.
The physical PLL stays 78 MHz; report both 78 and 104 MHz timing.

Do not redirect the current TLB work or MMC write diagnosis for this idea.
The TLB has a measured roughly 4,096-ALM direct target; the shifter saving is
currently unknown. MMC area changes remain deferred while hardware writes are
unresolved.

Related evidence: [TLB area](tlb-area.md), [RF audit](register-file-area-audit.md),
[DSP mapping](dsp-mapping-audit.md), [load overlap](cpu-load-release.md),
[ngage2 comparison](ngage2-transfer-options.md),
[block-transfer history](block-transfer-sequencing.md).
