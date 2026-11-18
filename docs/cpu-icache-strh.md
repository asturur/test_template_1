# Indexed STRH credit on the faster instruction frontend

The existing indexed halfword-store extension cuts the original Sega
Rally fill from **4,805 to 4,200 clocks** at both 0:0 and 2:9 on the
refined instruction frontend. The result is **605 clocks faster**, or
12.59% and 1.182 clocks per visited pixel. Both versions retire 2,567
instructions and make the same 512 ordered halfword writes.

The control is the exact archived combination of state-tagged fetch,
resident instruction-line retention and idle-lookahead steering, with
the banked main TLB and third D-side local mapping. The candidate applies
the existing unconditional aligned ARM register-offset STRH extension
to that source. Only predecode, issue and the core credit gate differ.
The independent one-file I-cache overlay remains its own variant.

| Original Sega Rally fill | 0:0 clocks | 2:9 clocks |
| --- | ---: | ---: |
| State-tagged baseline | 9,311 | 9,311 |
| One-file I-cache line retention | 5,473 | 5,473 |
| Refined frontend, matched control | 4,805 | 4,805 |
| Refined frontend with indexed STRH credit | **4,200** | **4,200** |
| Stock ngage2 | 2,596 | 2,628 |

## Where the clocks go

Both waits show the same schedule. Credit is issued on 480 resident
stores. Store hold drops from 1,635 to 675 clocks, while the 17 data
holds elsewhere in the wrapper remain equal. Operand-stage lock also
remains equal. The 3,845-clock arithmetic scenario assumes all 960
removed hold clocks carry through to the end of the window. Execution
exposes 356 new empty operand clocks, with one clock saved in the
remaining occupancy bin. The actual elapsed score is therefore
355 clocks above that arithmetic scenario.

| Whole first-window occupancy | Control | Candidate | Change |
| --- | ---: | ---: | ---: |
| Global data hold | 1,652 | 692 | −960 |
| Operand lock outside hold | 523 | 523 | 0 |
| Empty operand outside hold and lock | 54 | 410 | +356 |
| Other advancing clocks | 2,576 | 2,575 | −1 |
| Total | 4,805 | 4,200 | −605 |

Useful dequeue is the operand pop for the MOV that actually reaches
the ALU, matched separately for each of the 512 original iterations.
Of the 477 ordinary nine-clock dequeue intervals in the control,
322 become eight clocks and 155 become seven. The 31 store line
crossings take 13 clocks each, up from 12. The first and last useful
dequeues are clocks 34 and 4,747 in the control, and 34 and 4,144 in
the candidate. This measures 603 clocks saved in the useful loop
issue span. The remaining two clocks are outside those boundaries.

The frontend delivers all five original instruction replies in eight
clocks on 511 measured recurrences after the credit change. Three
clocks still have no instruction request at the taken branch. FIFO-full
edges fall from 579 to zero, and empty gaps specifically between BLE
dequeue and the next MOV rise from 15 to 370 clocks. The store credit
turns the early ADD into an earlier next pixel here, while exposing
some of the branch delivery delay that was covered by backpressure.

The per-edge audit checks both waits, the original retired-PC sequence,
the 512 ordered accepted addresses and lane masks, and the 512 physical
RAM writes. The existing guard and wrong-output checks pass across two
repeats, two warmups and five scored windows.

## Fault and ordering checks

A directed ARM guest runs twice per design at 0:0, 2:9 and 0:97. It checks
both halfword lanes against distinct neighboring bytes and writes the upper
halfword from an immediately preceding LDR whose own upper and lower halves
differ. The candidate earns credit on the four resident cases, including
an older store immediately before a faulting STRH. The subsequent load
and the final sentinels verify that all accepted earlier writes are visible.
The uncached halfword store takes the serialized path, generates exactly one
external write with mask `c`, then reads back the merged word.

The section translation abort, section permission abort and alignment
abort report the same PC, FAR and FSR on both cores. All three faulting
stores avoid cache acceptance and credit. The younger forbidden stores
never offer a write. The first guest expected byte-address FAR for an
upper-halfword translation fault, and both designs instead reported
`90000000` for the attempted access at `90000002`. The matched test
asserts the existing word-aligned FAR for translation and permission
faults, and the exact `80001011` FAR for the alignment fault. This is a
shared pre-existing behavior. The CPU/MMU sweep adds 22 ordinary
diagnostics and ten FIQ, SWP, translated I-cache prefetch and pending
write ordering cases, all passing.

## Broader result and decision

**Retain the store extension as an isolated candidate on the faster
frontend.** It provides an elapsed gain on two original Sega loops.
All 42 matched workload/profile comparisons pass the architectural
effect and output checks. The favorable ARM stream still starts 224
useful operations in 224 clocks.

| Original workload | Waits | Earlier tagged | Refined frontend | Refined frontend with STRH credit |
| --- | --- | ---: | ---: | ---: |
| Sega fill | both | 9,311 | 4,805 | **4,200** |
| Sega textured span | both | 32,908 | 32,902 | **31,942** |
| Full Sega scan | 0:0 | 5,375,298 | 5,176,864 | 5,176,864 |
| Full Sega scan | 2:9 | 5,506,714 | 5,308,282 | 5,308,282 |
| Matrix | both | 41,667 | 42,248 | 42,248 |
| Original Thumb JPEG 8×8 | both | 80,379 | 78,647 | 78,647 |

All four Monkey Ball rows per wait improve by two clocks. The remaining
medians match the refined frontend. The six SPMark/GLES geometric
throughput ratio versus the earlier tagged source is 1.0489× at both
waits. The already measured matrix cost is 1.4% versus tagged, while
the one-file I-cache-only variant scores 41,587. The matched STRH
comparison shows no elapsed regression and no new fault or ordering
failure. The word-aligned FAR behavior is common to both source sets.
Physical timing remains unmeasured.

[Full scorecard, matched source hashes and qualification](evidence/cpu-icache-strh-20261118.json.gz) ·
[First-scored edge traces](evidence/cpu-icache-strh-20261118.traces.json.gz) ·
[Reproducer](../tests/cpu/sega_fill_store/README.md)
