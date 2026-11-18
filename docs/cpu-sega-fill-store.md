# Sega Rally indexed halfword-store experiment

**Reject the store-credit extension for this loop.** The tagged control and
candidate both take **9,311 clocks** at 0:0 and 2:9, or 18.186 clocks per
pixel. The candidate acknowledges 480 resident stores two clocks earlier
and advances the independent ADD by two clocks on each of those pixels.
All 512 iterations start at the same edges as the control. The
960 clocks removed from store holds reappear as empty operand-stage
clocks. Keep the overlay as a reproducible experiment.

| Synthetic waits | Tagged control | Indexed STRH credit | Stock ngage2 | Elapsed clocks saved per pixel |
| --- | ---: | ---: | ---: | ---: |
| 0:0 | 9,311 | 9,311 | 2,596 | 0.000 |
| 2:9 | 9,311 | 9,311 | 2,628 | 0.000 |

Each window writes 512 halfwords and retires 2,567 instructions including
wrapper work. The exact five original words at `1001c9f4–1001ca04` execute
512 times in order. They shift the index, store a halfword, increment the
index, compare with the limit and branch. The fixture starts with index 3,
fills `80008000–800083ff` with `b67d`, and checks the entire output and
guards using the existing independent oracle and guest harness. All
profiles use two warmups, five scored windows, two agreeing repetitions
and a wrong-output control. For the first scored window at each profile
the observers verify every exact effective address, alternating lane
mask, accepted store and actual cache RAM mutation in order. The physical
write checks decode the two active data bytes in the 32-byte mainline or
16-byte donor line. The scope and combined source hashes match the retained
tagged-fetch receipt. [Previous source qualification](cpu-state-tagged-fetch.md)

## Matched resident iteration

Iteration 6 at 0:0. Clock zero is the advancing MOV in the mainline ALU
or the donor A-stage accept. The same schedule holds at 2:9. The two
mainline variants dequeue MOV and STRH on consecutive clocks before this
origin, and all three cores have the shifted index `10h` at clock zero.

| Boundary | Tagged control | Indexed STRH credit | Stock ngage2 |
| --- | ---: | ---: | ---: |
| STRH effective byte address `8000800a`, upper lanes `1100` | 1 | 1 | 1 |
| Store acceptance | 3 | 3 | 3 |
| CPU store acknowledgement | 5 | **3** | 3 |
| Physical cache RAM write | 5 | 5 | 3 |
| Independent ADD operand dequeue | 7 | **5** | — |
| Independent ADD executes | 10 | **8** | 2 |
| BLE operand dequeue / donor A accept | 10 | 8 | 4 |
| Next MOV operand dequeue / donor A accept | **15** | **15** | 5 |
| Next MOV executes | **18** | **18** | 5 |

The donor's A stage provides the measured execute/accept boundary. Its
ADD executes one clock before the store writes RAM. Its steady-state
loop advances one instruction per clock and starts a pixel every five
clocks. The mainline applies no operand-lock clock to the store index
on either variant. Its CMP-to-BLE dependency accounts for 512 clocks,
one per pixel. Each comparison has the same data address, byte lanes
and next value. During the control's store holds there is no valid ADD
yet at operand dequeue, issue, shifter or ALU. The hold delays the
shared pipeline, and releasing it earlier exposes a later gap in
delivery of the next loop iteration.

## Clock attribution and bounds

The control spends 1,635 first-scored clocks in a global data hold with
the original STRH selected. Of 512 stores, 480 enter the resident write
pipeline and the first store into each of 32 lines uses normal admission.
Existing indexed writes take two clocks from admission to cache RAM.
Predicting a saving of those two clocks for 480 stores gives a
960-clock opportunity, or 1.875 clocks per visited pixel, if the earlier
advance carries forward. The candidate gains those clocks locally and
saves zero elapsed clocks.

| Disjoint first-scored clocks | Tagged control | Indexed STRH credit |
| --- | ---: | ---: |
| Global data hold from the original STRH | 1,635 | 675 |
| Other global data hold | 17 | 17 |
| Operand-stage lock, outside data hold | 523 | 523 |
| Empty operand stage, outside holds and locks | 4,563 | 5,523 |
| Remaining clocks | 2,573 | 2,573 |
| Total | 9,311 | 9,311 |

No external memory service is active in either score. The shift/multiply
stall bin is zero. Of the 511 taken-loop transitions, 479 have a five-clock
BLE-to-next-MOV dequeue gap on the control and seven clocks on the candidate.
The other gaps stay at two clocks on 31 transitions and 12 on one. The two
variants have **1,958** and **2,916** empty clocks within these intervals,
respectively. All 511 corresponding donor A-stage gaps are one clock.
On mainline, 510 MOV-to-MOV execution intervals stay at 18 clocks and one
stays at 31 after the change.

The measured dominant boundary for this loop is the supply of the next
MOV at operand dequeue. Collapsing every measured backedge gap to one
clock and preserving all other sampled edges would give **7,353 clocks**
from the tagged control, or **6,395 clocks** starting from the overlay.
The latter already includes the store clocks that reappear after the
backedge. These are fixed-trace bounds for the measured target gaps, and
both exceed the whole-loop 2× budget of 4,655 clocks. The previously
measured steady-state 5-clock donor loop shows how much additional
pipeline latency remains beyond that single boundary.

[The subsequent fetch trace locates both resident-line waits and the predicted-target launch delay](cpu-sega-fill-fetch.md).

## Isolated RTL

The overlay only widens the existing predecode class for unconditional
ARM register-offset STRH with pre-index addressing, no writeback and no
PC operands. It keeps the ordinary register scoreboard for the index,
base and data. Issue explicitly excludes halfword stores from the two
existing late word-data bypasses, which deliver raw words around the
byte-lane formatter. The CPU eligibility predicate checks natural
halfword alignment and the exact two active lanes. Existing cache
logic still requires the translated normal, cacheable and bufferable
request, an indexed resident line, drained higher-priority ownership
and available credit. Nonresident, device and faulting requests use
the existing response path. The patch adds no state and reuses the
same physical write and ordering logic. The source audit finds changes
only in predecode, issue and the core eligibility gate.

This negative result stops at the requested loop. Other games and the
directed fault/ordering qualification were gated on an elapsed gain.
Routed cost and timing remain unmeasured for the overlay.

[Reproducer](../tests/cpu/sega_fill_store/README.md) ·
[Matched evidence](evidence/cpu-sega-fill-store-20261118.json.gz) ·
[Per-edge traces](evidence/cpu-sega-fill-store-20261118.traces.json.gz)
