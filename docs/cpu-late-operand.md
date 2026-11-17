# Step 5L — registered late arithmetic operand pickup

**Retain the isolated experiment for broader qualification and eventual timing;
do not promote it yet.** Both original span patterns improve by 1,533 measured
clocks over promoted 5J/5K. Production stays at
`ccba54f60a2c6f4741e74428b3306a19717ea58d`; its separate fit/release belongs to
another chat. No production RTL, cache geometry, PLL, branch, hardware, donor
source or Quartus job was changed by this experiment.

| Identical checked work, both profiles | Promoted 5J/5K | Step 5L |
| --- | ---: | ---: |
| Original forward span, 512 pixels | 36,528 | **34,995** |
| Original reverse span, 512 pixels | 36,453 | **34,920** |
| Guarded original transpose | 3,441 | 3,441 |
| Independent loads, one resident line | 343 | 343 |
| Independent loads, eight resident lines | 499 | 499 |
| Dependent 32-load/add checksum | 271 | **239** |
| Original native Thumb JPEG block | 84,353 | 84,353 |

Forward changes **71.34375→68.349609375 clocks/pixel (−4.1968%)**;
reverse **71.197265625→68.203125 (−4.2054%)**. These are actual bounded
CPU/cache simulations, including final cache mutation and retirement, not FPS.
The earlier 1,536-clock scenario was not substituted for measurement.

## Boundary and eligibility

The original implementation is a reproducible overlay generator in
[setup.py](../tests/cpu/cpu_late_operand/setup.py). Only `zap_issue_main.sv`
and `zap_core.sv` differ from the promoted control. No donor code was read or
copied for implementation. The initial boundary is deliberately narrower than
a generic execute-stage forwarding network: accept in Issue before the older
load completes, then fill the missing raw operand as the existing shifter
register captures the execute operands. The ALU still reads a register.

An unconditional ADD or CMP, with constant LSL #0, can carry exactly one
unresolved source from the eligible P1 word load that is starting this edge.
Both Rn and unshifted Rm are supported; two matching sources are excluded.
PC destinations, memory consumers, switches, exceptions, background locks,
SWP, narrow/unaligned/writeback loads and nonqualified load producers retain
the existing path. Rotated immediates, shifts and predicated consumers are
conservatively excluded. A register writer or load targeting that physical
source in Issue, Shifter or ALU blocks acceptance even when its predicate
has not resolved. The other source, shift length and other scoreboard checks
remain in force. Eligibility contains no benchmark address or instruction PC.

Two new registered bits identify which source needs pickup. The existing
physical register selector identifies Rd. No PC tag or value buffer is added:
P1 transfers the same packet to P2 on the acceptance edge, and P2 cannot leave
until its registered completion is consumed. These facts supply temporal
producer ownership; the consumer cannot move independently of that owner.
The simulation assertion checks the load's Rd and registered completion on
the pickup edge, including the distinct owned-fault case.

## Registered schedule and useful progress

One source-base load's first measured occurrence gives this schedule. Offsets
are from that load's dequeue; the full journals use absolute window clocks.

| Observed edge | Promoted control | Candidate |
| --- | ---: | ---: |
| Load dequeue | 0 | 0 |
| Registered ALU effective address | 3 | 3 |
| P1 load start / early consumer acceptance | 4 / — | 4 / **4** |
| Raw ACK; pipeline still held | 5 | 5 |
| Registered completion / operand pickup | 6 / — | 6 / **6** |
| Consumer normal dequeue | 6 | already accepted |
| Registered ALU result | 9 | **8** |
| Consumer retirement | 12 | **11** |
| Following useful dequeue | 7 | **6** |

Thus acceptance moves two clocks but execute, retirement and following useful
issue move **one**. The held ACK edge remains; no combinational ACK→ALU or
ACK→issue release was introduced. At absolute clocks 26/30/32/34/37 the
candidate dequeues the producer, accepts the consumer, picks up its result,
exposes the registered ALU result and retires it. The next useful dequeue is
32. Control is 26/32/35/38 with next dequeue 33.

Full-window event audits cover every targeted occurrence in both patterns:

| Site role | Early acceptances | Load→consumer dequeue, control→candidate | Load→retirement |
| --- | ---: | --- | --- |
| Destination-bias ADD | 510/512 | 510×6→4; 2×7 unchanged | 510×12→11; 2×13 unchanged |
| Source-base ADD | 512/512 | 512×6→4 | 512×12→11 |
| Loop-bound CMP | 512/512 | 512×6→4 | 512×12→11 |

Both missed destination-bias cases (iterations 0 and 1) retain the late-arriving consumer path;
the narrowed P1 opportunity has passed before the operand queue is valid.
Both are visible explicitly in the bounded edge journal. All
1,534 accepted operations have matching pickups, registered execution and
retirement. Their following useful issues advance one clock locally.

Exclusive full-window accounting changes load-lock clocks **12,794→11,260
(−1,534)** and empty delivery **19→20 (+1)**. Read stalls, write stalls,
shift/multiply locks and advancing work are unchanged. Net elapsed saving is
**1,533**. Forward last RAM mutation/store retirement/end are
**34,975 / 34,977 / 34,995**; reverse **34,900 / 34,902 / 34,920**.
All 512 writes complete before the end, and pending store credits are empty.

## Holds, faults, retry and architectural state

A waited P2 load asserts the existing global data hold. It holds the consumer
in Issue, its late bits, source selectors and all downstream packets. A missing
response cannot release that hold. A successful registered response selects
`completion_data` before the existing shifter register, so later stages use
stable operands. There is no speculative load completion or extra MMIO access.

Reset and existing ALU/writeback clears clear the two late bits and the operand
queue. A fault completion can contain unusable/stale data; it is **not** a
successful operand pickup. The unchanged ALU fault/sleep path preserves flags
and suppresses younger results until writeback redirects. The unchanged retry
path restarts the load and clears its younger operation; a replay must obtain
its own producer ownership again. Register and CPSR writes still follow their
ordinary in-order paths. Consumer conditions are checked by the original ALU;
initial eligible consumers are AL. CMP flags feed subsequent conditional work
through the original flag network.

The actual CPU safety guest passes twice at **0:0, 2:9 and 0:97**. It checks
ADD writing its own loaded source, a second writer, true/false predicated
writers, CMP feeding conditional moves including signed-overflow conditions,
IRQ during a load, exact abort FAR/FSR, destination sentinels and excluded
fault-path/flushed MMIO reads. The faulting load's dependent ADDS is confirmed
**early accepted but never validly executed**; the saved SPSR flags are checked
and the younger destination remains unchanged. A cold successful load holds
its accepted consumer **48 / 59 / 145 clocks**, respectively.

A separately compiled testbench uses exactly the same frozen CPU RTL:

- Withhold the cold external line response: **128 clocks held, one acceptance,
  zero dependent executions**, with stable consumer owner and no completion.
- Inject a one-shot retry at the CPU response boundary: **one retry, two early
  acceptances, exactly one valid execution and retirement**, then the complete
  guest output checks pass. This tests CPU replay, not cache retry generation.

The first safety run found an overly strict test assertion that demanded a
usable result for a fault completion. It was corrected to recognize the owned
fault path; no CPU fault behavior was changed. Two initial directed-test
forms (two matching sources, then a rotated immediate) were outside eligibility;
the final single-source ADDS #1 is confirmed to exercise the early path.

## Reproducibility and remaining qualification

Saved 5K measurements are reused with **all 60 frozen RTL/header hashes checked
against promoted master**, not merely a commit label. Candidate changes are
exactly the two overlay files; compiler input journals identify 51 read inputs.
Manifests retain exact source, executable, toolchain image, harness, original
program and oracle hashes. Both full workload repetitions, both wait profiles,
five equal scored windows per case, zero scored external transfers and all
12 corrupted-output controls pass. Original span instructions, 10,240 retired
operations, full output/guards/source/stack checks, ordered stores, actual RAM
mutations and byte enables are retained. Dynamic retirement PC streams match
the saved control. The extra killed next-iteration dequeue is not scored as
retired work. Eight actual-CPU ARM/Thumb/MMU/FCSE/prefetch/return diagnostics pass.
The independent/multiline and transpose checks pass unchanged. The separate
original Thumb JPEG uses matching CPU hashes, original oracle, repeated windows
and corrupted-output rejection, with 84,353 clocks at both profiles.

Structural cost is **two state bits, two 32-bit operand-selection muxes and
eligibility/younger-writer comparisons**. No RAM, port, cache entry, adder, DSP
or additional outstanding load is introduced. A rough source-level planning
allowance is tens of ALMs (approximately 40–80); this is not synthesis evidence.
The new result path is registered completion→operand mux→existing shifter
conflict resolution→shifter register, then a separate ALU stage. The control
path extends registered P1 qualifications through physical-register comparisons
and scoreboard acceptance. Completion fanout and this control cone need timing
review. There is no new cache-result/translation/ACK combinational feedback to
ALU or issue. **78 MHz PLL and 104 MHz design target are unchanged; meeting
104 MHz is unverified.** No timing or area claim is inferred from simulation.

The subsequent six-kernel campaign is complete on the **exact same 60-input
5L overlay**. Both profiles, five scored windows, two equal repetitions,
original hashes/oracles/retirements and all six wrong-output controls pass.
Canonical matrix45,073→45,073; transpose3,560→3,560; triangle23,568→23,520;
frame71,259/201,302 unchanged; halfword1,332 and byte1,647 unchanged.
These canonical wrappers are separate from the guarded transpose3,441 above.
No broad regression; retain 5L for the isolated admission experiment and later
timing assessment. [Separate broad receipt](evidence/cpu-late-operand-six-20261117.json)
preserves attribution before 5M. A fit of 5L remains future work. No new Quartus, release/CI,
phone access or donor experiment was performed. Only this experiment's completed
compiler trees and derived private binaries are cleaned after qualification;
compact logs, manifests, checks, synthetic assembly and evidence remain.

[Replay commands](../tests/cpu/cpu_late_operand/README.md) ·
[Machine receipt](evidence/cpu-late-operand-20261117.json) ·
[Full span journals](evidence/cpu-late-operand-20261117.events.json.gz).
