# LCD read stream

`ngage_lcd_stream.v` is a transaction-level speed shortcut for the general DMA
frontend's captured LCD descriptor. It reads aligned words from physical
`0a000000..0afffffc`, preserving the exact little-endian 32-bit bus word. The
normal LCD queue/display owns packing, pixel position and physical completion;
the frontend owns registers, IRQs and the final queue-empty fence. This module
models no LCD pin timing.

The descriptor accepts a literal 33-bit positive word count. Source plus byte
extent uses 36 bits, including the carry from a maximum 35-bit extent, and must
end at or before `0b000000`. Inputs can change after descriptor acceptance.
`mem_addr` is the low 25-bit byte address, not a word index. `mem_accept` captures
a level request, which stays asserted with immutable address through its owned
ACK. Unowned ACKs are ignored; acceptance and ACK on the same edge are legal.
One registered skid word releases RAM ownership during arbitrary pixel stalls.

A pixel handshake with `pixel_error=1` rejects the offered word and terminates
with error. Stop suppresses pixel handshake immediately, withdraws an unaccepted
RAM offer, or drains and discards an accepted RAM read before reporting aborted.
An accepted pixel prefix stays accepted. Reset must also reset/drain the connected
RAM arbiter because this native interface has no transaction identifiers.

Run in the installed offline image from the repository root:

```sh
docker run --rm --pull=never --network none --platform linux/arm64 \
  -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 \
  -c 'tests/phone/lcd_stream/run.sh'
```

The same Verilog-2001 fixture runs directly against a latency-controlled memory
and through the real `ngage_sdram_arbiter.v`. An independent address/data oracle
checks full 18,304-word frames, descriptor mutation, FIFO stalls, range/count
rejection including `2^32` and maximum 33-bit counts, canceled prefixes, stop on
final ACK/pixel offer, sink rejection, coordinated owned reset and stale ACKs.
One hundred additional descriptors vary source, extent, latency and stalls.

With continuously ready pixels, direct latency-one/three memory takes
36,609/73,217 clocks for 18,304 words (approximately two/four per word). The
actual native arbiter adds its grant clock: 54,913/91,521 (three/five per word).
These synthetic measurements do not measure physical SDRAM or phone boot speed.

## Matched legacy comparison

Run `tests/phone/lcd_stream/run-comparison.sh` in the same image to compare the
actual legacy `ngage_lcd_dma.v` and new stream. Each has an independent instance
of the same real SDRAM arbiter and identical physical memory model, no CPU
traffic and an always-ready sink. Legacy channel 1 is programmed with source
`0a000020`, destination `10121208`, count `18303` and start `2`.

The timed interval starts on the first client read-request edge and ends on the
last accepted pixel / terminal edge. Four legacy register writes precede the
origin and are excluded. Each word is checked against an independent source
oracle, then the full 18,304-word streams are compared bit for bit.

| Physical RAM response delay | Legacy clocks | Stream clocks | Clocks/word |
| --- | ---: | ---: | ---: |
| 0 (combinational ACK while arbiter owns request) | 36,608 | 36,608 | 2 |
| 1 | 54,912 | 54,912 | 3 |
| 3 | 91,520 | 91,520 | 5 |

Both final-pixel and terminal intervals match exactly. All six streams have
checksum `069c7940`. These elapsed intervals are one clock shorter than the
previous metrics because the previous origin included the descriptor-accept
edge; the per-word rates are unchanged. The new shortcut preserves the legacy
rate on the matched backend. It adds normal FIFO delivery and separate frontend
ownership; this test does not measure queue-drain latency or physical LCD timing.
