# Why ngage2 runs the Sega Rally fill in five clocks per pixel

**The 18-versus-5 steady-state gap originates at instruction delivery.**
The tagged core gets the branch target right. Each taken iteration still
inserts three clocks with no instruction request while the target moves
through the PC pipeline. At the two instruction line crossings, it waits
five clocks each for an already resident line. Stock ngage2 launches the
predicted target from F1, while the previous instruction is still in F2,
and gets one warm instruction reply per clock across the taken branch and
both line crossings.

The exact original 512-pixel fixture still scores 9,311 versus 2,596 at
0:0 and 9,311 versus 2,628 at 2:9. Both designs retire 2,567 instructions
and produce the same ordered 512 halfword writes. The added probes are
passive. The executable inputs, output and guard checks, all seven
windows and repeated scores match the [store experiment](cpu-sega-fill-store.md).

## Instruction delivery

Clocks below start at the MOV instruction reply for a steady iteration.
The loop spans two instruction lines even with the mainline's 32-byte
lines. The shifted index, store and ADD occupy the end of one line.
CMP and BLE occupy the start of the next.

| Instruction reply | Address | Tagged | Stock ngage2 |
| --- | --- | ---: | ---: |
| MOV shifted index | `1001c9f4` | 0 | 0 |
| STRH indexed store | `1001c9f8` | 1 | 1 |
| ADD increment | `1001c9fc` | 2 | 2 |
| CMP limit | `1001ca00` | 8 | 3 |
| BLE backedge | `1001ca04` | 9 | 4 |
| Next MOV | `1001c9f4` | 18 | 5 |

The five missing replies before CMP follow this measured state sequence.
After admitting the request, the I-cache goes through
`LOOKUP_CAPTURE → LOOKUP_WAIT → LOOKUP → READ_LINE` and acknowledges on
the following edge. The next MOV goes through that same sequence. Both
lines are resident. No I-TLB wait, page walk or external line transfer
occurs in these recurrences. The serialized resident read invalidates the
stream buffers, then seeds the line it returned. The streaming lookahead
is forward from `i_address + 16`. It fails to supply the next line in time
as execution reaches CMP, and can't supply the line behind the taken
branch. The two lines alternate through the warm but serialized path.

On the BLE reply edge, the tagged BTB computes `1001c9f4` correctly.
The `zap_pc_shelve` path inserts that address at the start of the
four-PC train and invalidates its three younger stages. The next three
edges have no instruction request. Then the MOV request starts its
five-clock cache wait. The steady branch prediction needs no decode or
ALU recovery. Across 511 complete fetch recurrences in each profile,
the tagged core shows exactly **2,555 CMP wait clocks, 1,533 clocks
with no request, and 2,555 MOV wait clocks**.

The donor's F1 BTB hit drives the next address immediately. On the edge
where F1 contains BLE, F2 acknowledges CMP and F1 launches the target
MOV. On the following edge F2 acknowledges BLE, with MOV in F1.
One edge later F2 acknowledges MOV. The instruction cache compares the
address in advance using its next/check interface and can acknowledge
the resident word in F2 while the next lookup proceeds. Its fetch queue
pushes on every edge of the steady recurrence. A representative advance
has seven queued words with simultaneous push and pop. The target MOV
reaches execution immediately after BLE.

## Execution and elapsed clocks

ngage2 forwards the shifted index into STRH, accepts ADD on the following
execute edge and writes the store the clock after ADD executes. All 512
stores see the donor's fast data acknowledgement in each scored trace.
CMP updates the flags in time for the next-cycle BLE. On our core the
earlier STRH-credit experiment moves the ADD and branch inside the
iteration, but the next MOV still arrives on the original schedule.
Store hold, the CMP-to-BLE lock and the empty operand-stage clocks
describe how the execution pipeline experiences the slower supply.
The 13 instruction-delivery clocks recur every iteration and overlap
those downstream counts.

| Contribution to the whole-window difference | 0:0 | 2:9 |
| --- | ---: | ---: |
| 510 regular executed intervals × (18 − 5) clocks | 6,630 | 6,630 |
| One exceptional MOV-to-MOV interval | 18 | 10 |
| Before first and after last executed MOV | 67 | 43 |
| Total | **6,715** | **6,683** |

The earlier 1,958-clock bound counted only empty operand-stage clocks
between BLE dequeue and the following MOV dequeue. These probes also
capture the mid-iteration line crossing and the instruction wait that
overlaps downstream work. A useful follow-on would measure whether the
current I-cache can deliver both resident lines continuously, including
a predicted backward target, before spending effort on the five
instructions' data path. At this measured boundary, removing only the
three predicted-target launch bubbles leaves the two five-clock line
waits in each recurrence.

The subsequent I-cache overlays cut the original fill to 4,805 clocks.
[Implementation and qualification](cpu-icache-stream.md)

[Source hashes and recurrence audit](evidence/cpu-sega-fill-fetch-20261118.json.gz) ·
[Per-edge fetch traces](evidence/cpu-sega-fill-fetch-20261118.traces.json.gz) ·
[Reproducer](../tests/cpu/sega_fill_store/README.md)
