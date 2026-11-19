# Scalar SDRAM handoff at 78 MHz

The later [streaming SDRAM controller](arm9v2-sdram-stream.md) implements
posted scalar service in the production v5 path.

The pin trace shows 11 idle command slots between the second halfword
of one v5 write and the first halfword of the next. On ngage2 there is
one idle slot on the same workload. Each controller already writes the two
halfwords of one word on consecutive clocks.

This compares the same serialized first scored GLES fill and Sega Rally
streams captured from v5 `8546db1`. The donor uses its original
`ff6dcff` CPU-independent memory path. The common Micron model checks
every read and each final written word. Pin READ/WRITE command counts,
request order and transaction widths are identical. Same-row samples
are adjacent writes in the same 1 KiB region with no intervening
activate, precharge or refresh. The elapsed figures include these
maintenance commands and a final read to drain writes.

| Path | First-to-first pin WRITE per word, same row | GLES fixed stream | Sega fixed stream |
| --- | ---: | ---: | ---: |
| V5 | 13 clocks | 284,450 | 360,587 |
| V5 with donor bank map | 13 clocks | 282,462 | 353,932 |
| V5 with immediate response on controller ready | 12 clocks | 268,494 | 343,844 |
| V5 with earlier scalar launch and immediate response | 11 clocks | 252,476 | 327,110 |
| ngage2 | 3 clocks | 134,704 | 215,532 |

On the GLES trace the median request-to-first-pin-write time is 5 clocks
on stock v5. The second write reaches the pins one clock later. V5
acknowledges 5 clocks after that second command. ngage2 can acknowledge
before either pin command because its UPP holds the accepted write
and its masks. The controller still enforces write recovery. Staging
the next operation while that write drains lets ngage2 start the next
word immediately when it can accept it.


### Where the 13 clocks go

A directed run of twelve adjacent 32-bit writes in one open row
records the request, internal controller states and pin commands.
Clock zero is when the request becomes visible to the old v5 SDRAM
adapter, downstream of the CPU/DMA arbiter.

| Clock | Event |
| ---: | --- |
| 0 | The host presents the word. |
| 1 | The adapter latches its address and enters `ISSUE`. |
| 2–3 | JTFRAME latches the bank request and registers the write enable. |
| 4 | The bank request obtains the shared command slot. |
| 5–6 | The two 16-bit `WRITE` commands reach the pins. |
| 8–9 | Write recovery completes in the bank and JTFRAME registers `rdy`. |
| 10–11 | The adapter enters `RESP`, then asserts the upstream ACK. |
| 12–13 | The request drops, the adapter returns to idle, and the test source presents the next word. |

The final two clocks include request release and source pacing in the
serialized replay. They are not SDRAM timing. The important dependency
is the round trip: each word waits for physical completion and for
`rdy` to cross the adapter before the next request starts the same
launch pipeline. The donor holds the next accepted payload while the
current word drains. Its open-row command path can start that pending
word as soon as the controller allows it. The two physical WRITE slots
and one intervening idle slot produce the observed three-clock cadence.

The test overlay removes the adapter's extra response state. It also
presents an arriving scalar request in the idle cycle while capturing
its address and direction. The outer arbiter still holds its payload. Read capture, write command spacing, controller timing,
bank map and 32-byte line service are unchanged. Both changes can be
tested separately in the pin fixture. The faster overlay recovers
31,974 clocks, about 21% of the original fixed GLES memory-path gap.

The full CPU and physical memory-path replay verifies the same
original-code outputs with the faster overlay and two identical runs.

| Checked CPU replay | V5 | Earlier scalar launch and immediate response |
| --- | ---: | ---: |
| Original GLES full-screen fill | 299,252 | 267,360 |
| Sega Rally full-screen scan | 2,466,436 | 2,457,047 |

The pin fixture's single frame readback takes 221,942 vs 185,666 clocks
with the faster handoff. This is sequential memory service. Native LCD
DMA can contend with the CPU and has additional transfer phases.
The existing controller test passes at 78 MHz with 113 checked short
reads and 226 halfwords on both paths, plus 32-byte fills, masked writes,
DMA and CPU lock behavior. The ownership fixture also passes all 16
masks and a logical reset during an outstanding store at controller
grant delays of 0, 3 and 7 clocks. These are simulation-only overlays.

The next experiment should queue the next ordered scalar write in the
controller-facing path while the current write drains. Track queue
occupation and physical completion alongside CPU acknowledgements.
Keep row policy and 32-byte bursts fixed for that comparison. A read,
refill, DMA observer or locked operation must see preceding writes in
order. Keep the controller's SDRAM recovery and refresh constraints.
Check the pin stream, actual CPU and DMA path, and final physical data
before deciding whether a controller replacement is worthwhile. The
native contribution remains unmeasured.

[Machine-readable phase timings](evidence/arm9v2-sdram-handoff-20261119.json)

## Replay

```sh
FRAME_GAP_HANDOFF=1 FRAME_GAP_TRACES=build/sim/payload-clocks/frame-gap-v5-pin-profile \
  sh tests/phone/sdram/run-frame-gap-banks.sh fresh-handoff
python3 tests/cpu/arm9v2_board/payload_clocks.py --name fresh-handoff-phone \
  --config 2:64 --flash-cache-bytes 32768 --handoff admit \
  --sdram-model build/sim/fresh-handoff/mt48lc16m16a2.v \
  --case fill16_frame --case sega-scan
```
