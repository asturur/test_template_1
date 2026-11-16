## Production integration — 2026-11-16

The user authorized adoption of the qualified full-product candidate. Production
`rtl/arm/zap_shifter_multiply.sv` now infers a registered signed33x33-bit product
with `multstyle = "dsp"`, retaining the existing five-state busy schedule,
separate accumulator and ordered low/high result ownership. Only comments and
whitespace differ from the previously qualified candidate after its module is
renamed to the production name. No PLL or pipeline-latency change.

A permanent regression lives in `tests/cpu/multiply_mapping/` and is included in
`tests/cpu/run.sh`:2,048 independent arithmetic vectors,4,096 ordered results,
random stalls, failed conditions and16 held writeback cancellations. Its frozen
pre-change reference is test-only, never in the QIP. Production checks pass92 architecture runs and44 IRQ/FIQ boundary runs. All12
original-payload workload/profile groups pass with two identical repeats and
wrong-output controls. Every raw counter matches production POP/BX exactly
(excluding its derived ratio field); both profile indices are100.0 relative
to that baseline. Private outputs and source hashes are recorded in
`evidence/dsp-full-product-production-20261116.json`.

This is production source adoption for a physical experiment. Quartus resource
mapping, net ALM savings, routed timing and native board qualification remain
unmeasured. The loaded MiSTer RBF remains b707ebd, without this change. The
actual PLL remains78MHz and the design objective104MHz. No build/deployment
has been requested in this adoption step. Earlier isolated observations below
are retained as historical evidence.

# DSP use and ALM reduction audit

Read-only source and b3131b5/run43821270521/seed43 Fitter audit. No mapping or
arithmetic RTL is changed and no new build is started. Actual PLL remains78MHz;
104MHz is the implementation objective. Phone stays user-controlled.

| Fitted consumer | DSP blocks |
| --- | ---: |
| MiSTer HDMI scaler |23|
| Framework audio filter |8|
| Phone LCD display |5|
| CPU integer multiplication |4|
| YC output |2|
| **Total / capacity** |**42 /112**|

There are70unused physical DSP blocks. Synthesis already has DSP Block Balancing
Auto and Auto DSP Block Replacement On. The CPU's four17x17 partial products
are already hard DSP multipliers with their input/output registers packed. Their
reported DSP adder-chain/accumulator features are unused. This is not evidence
those features can simply be enabled without changing their configured mode.

The CPU multiplier entity is attributed106.1ALMs and88dedicated logic registers;
the ordinary ALU355.8ALMs and268registers. Fitter entity figures use hierarchical
inclusive/self accounting; do not add a parent and its children. The multiplier
is already mostly offloaded. An attribute on its fourexisting products does not
identify a large remaining soft multiplier or establish a reduction. Its remaining
106ALMs also include control/muxes/flags, so they are not all removable arithmetic.
The23+8framework blocks are already doing multiply-heavy video/audio work.

## What generic directives can accomplish

Quartus supports Verilog-2001 `(* multstyle = "dsp" *)` on the directly assigned
product signal, multiply expression or enclosing module. It is a preference,
not a guarantee, and covers HDL multiplication operators. It does not send
arbitrary ADD/SUB, flags, compares, shifts, cache tags or ARM software functions
to DSP hardware. The existing report already demonstrates automatic recognition.
The legacy guide confirms this syntax predates our Quartus17 toolchain:
[Quartus legacy handbook](https://cdrdv2-public.intel.com/653795/quartusii_handbook_archive_130.pdf),
[current Standard multiplier-style reference](https://docs.altera.com/r/docs/683283/18.1/design-compilation-user-guide-quartus-prime-standard-edition/multiplier-style-for-inferred-multipliers?contentId=nFUh~4aq5kIoZRSnKWi6bQ).

Cyclone V DSPs include a64bit accumulator/adder and supported multiply-adder
configurations. Mode restrictions and clock/reset/enable controls matter:
[device accumulator reference](https://docs.altera.com/r/docs/683375/current/cyclone-v-device-handbook-volume-1-device-interfaces-and-integration/accumulator-and-chainout-adder).
That makes CPU partial-product recombination/accumulation a concrete experiment,
not a claim a synthesis annotation alone moves today's separated64bit sums.

## Ordered experiments and acceptance

1. Establish identical-source map/fit reference after the pending timing change.
   Keep seed, debug setting, clocks and source manifest fixed. Retain overall
   and per-entity ALMs, FFs, M10Ks, DSP allocation, registered DSP ports, setup/
   hold/recovery/removal and SDRAM I/O packing. Attribute-only builds must show
   an actual mapping/ALM improvement before claiming any benefit.
2. First functional mapping candidate: CPU multiplier S1/S2 recombination and
   accumulator. Explore inference-friendly registered full-product/MAC or a
   documented Quartus17 DSP arithmetic primitive. Preserve current busy/result
   schedule initially, both low/high owners, signed/unsigned arithmetic,
   accumulate carry/wrap, paired long-multiply flags, reset, stall and kill.
   Keep conditional/failed instructions and producer/consumer ordering exact.
   The existing four hard products alone are not the opportunity; the ALM-side
   sums/control boundary is. A distinct later experiment may shorten the schedule.
3. Measure any residual video/audio multiply-add expressions individually.
   Most are already DSP-backed. Consider constant products only where a fitted
   comparison shows useful ALM reduction and unchanged pixel/audio timing.
   Do not convert cheap shifts/wiring to extra arithmetic just to fill DSPs.
4. Audit the main32bit ALU/adders only after bounded MAC work. ADD/SUB carry/
   overflow, comparison, address generation and branch targets are tightly
   coupled and already feed important combinational paths. DSP mapping that
   requires another CPU cycle or harms104MHz is not an area win we can accept.
   Arbitrary bitwise/control/memory functions do not become DSP candidates.

Tests for each candidate: independent64bit signed/unsigned integer oracle,
MUL/MLA/UMULL/SMULL/UMLAL/SMLAL edge values and flags; dependent/back-to-back
factors and accumulators; failed conditions, held completion, reset/flush/IRQ/
FIQ, exact low/high ownership. Use the existing donor-import multiply workloads
and actual CPU architecture/interrupt suites. Then repeat all sixoriginal
SPMark groups and fourJPEG cases with output checks and counter comparisons.
The original matrix kernel has meaningful multiply occupancy; the measured JPEG
bitmap converter has zero, so a MUL change cannot be sold as its next speedup.
Finally require fitted net ALM savings and acceptable physical timing before
adoption; report any addedDSPs, unchanged/changed CPU latency and actual gain.

Full use of112blocks is not an acceptance metric on its own. Use available DSPs
where they free ALMs or improve measured throughput within the latency/timing
contract. Current106ALM multiplier attribution bounds the scale of the obvious
local opportunity; no thousands-of-ALMs saving has been demonstrated.
[Exact fitted inventory](evidence/dsp-mapping-audit-20261116.json).

## Instruction mix and isolated full-product experiment

The benchmark names describe software routines, not extra ARM instructions.
An original-code instruction-hook audit, with independent output checks, visits
1,024 SMULL instructions in `matrix4`, and 48 SMULL plus 16 MLA instructions in
`triangle_edges`. `transpose4` and the fill routines contain no multiplication.
These are visited-instruction counts, not a cycle profile or conditional
retirement count. The JPEG bitmap converter's measured multiply occupancy is
also zero. [Instruction evidence](evidence/dsp-instruction-mix-20261116.json).

A private candidate replaces the four explicit 17-bit partial products and
wide recombination sums with registered signed 33-bit factors and one inferred
full product, annotated for DSP inference. The extra sign bit supports both
unsigned and signed ARM operands. It preserves the existing state machine,
low/high result ownership and busy schedule, and leaves accumulation as a
separate stage. Its purpose is to expose recombination to the fitter; it makes
no claim that the remaining accumulator is already inside a DSP.

The isolated old/new comparison passes 2,048 independent integer-oracle vectors,
4,096 ordered low/high results, signed/unsigned accumulation, paired zero flags,
random data holds, failed conditions and 16 held writeback cancellations.
This does not replace full CPU qualification, a fitted resource comparison or
hardware testing. The initial payload-run adapter failed compilation because
it omitted the renamed module's end label; its results are rejected. The
corrected adapter passes all six original workloads in both memory profiles,
with two exact repeats and wrong-output controls. All raw rows, including
warm-up/scored windows and whole-run counters, exactly match production
POP/BX; only the baseline report's derived throughput-ratio field is excluded.
No speedup is expected or measured; the busy schedule is preserved. The
broader CPU qualification passes 92 architecture runs and 44 IRQ/FIQ boundary
runs. Fitted ALM/DSP allocation and routed timing remain unmeasured. Production RTL is unchanged, and this
candidate is excluded from the already-running POP/BX build.

[Candidate patch](evidence/dsp-full-product-candidate-20261116.patch),
[experiment identities](evidence/dsp-full-product-experiment-20261116.json).
Private sources and test vectors remain under
`scratch/dsp-full-product-20261116/`; outputs under
`build/sim/dsp-full-product-20261116/`.
