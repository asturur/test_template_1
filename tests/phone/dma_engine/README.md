# Standalone DMA execution engine

Run from the repository root:

```sh
tests/phone/dma_engine/run.sh
```

The script uses Icarus in Verilog-2001 mode. Output defaults to
`build/sim/unit-dma-engine/`; `DMA_ENGINE_OUT` selects another output directory.
The same command runs inside the existing `jotego/simulator:arm64` image.

## Interface contract

`rtl/ngage_dma_engine.v` executes one captured descriptor. It does not decode
registers, translate aliases, assign channels or route interrupts.

| Signals | Meaning |
| --- | --- |
| `transfer_valid`, `transfer_ready` | Capture a descriptor on their common high clock edge. Ready remains low while active and during stop/reset. |
| `source_addr`, `destination_addr` | Physical byte addresses, naturally aligned to their respective widths. |
| `source_bytes`, `destination_bytes` | Three-bit literal byte counts: 1, 2 or 4. |
| `source_increment`, `destination_increment` | Advance by consumed bytes when high; reuse the original address for each unit when low. |
| `transfer_bytes` | Thirty-five-bit literal byte budget. The frontend converts its hardware count units according to the selected transfer mode. Zero bytes is invalid. |
| `source_ready`, `destination_ready` | Live eligibility for preparing each fixed-side access. Tie high for fixed memory without pacing. Incrementing sides ignore these inputs. |
| `stop` | Withdraw an unaccepted offer, or drain one accepted word before cancellation. A pulse during an owned word is remembered. |
| `busy` | A captured descriptor remains active. |
| `done`, `error`, `aborted` | Exclusive one-clock terminal outcomes. Done requires successful responses for all writes. A failed response wins over simultaneous stop. |
| `cmd_valid`, `cmd_ready`, `cmd_write`, `cmd_addr`, `cmd_data`, `cmd_be` | The aligned, byte-enabled word interface used by `ngage_dma_route`. A packet remains immutable while offered and owned. |
| `rsp_valid`, `rsp_error`, `rsp_data` | One terminal response per accepted word. A same-edge response is supported. There is no response backpressure. |

The engine preserves little-endian byte order across width conversion. Final
partial source and destination units use only their remaining byte lanes. It issues no
requests for unsupported widths, misalignment or a transfer whose incrementing
address range exceeds 32 bits. Invalid descriptors terminate with error on
capture. Active descriptors ignore subsequent field changes and starts.

The route must reserve actual peripheral capacity when accepting a word;
eligibility is sampled before the engine offers it. A waiting command must not
lock out CPU traffic. Stop does not undo an accepted write or guarantee an
atomic copy: successfully committed prefixes remain. Reset cancels responses,
so the downstream route must be reset/drained at the same boundary before
reuse. An idle stop produces no terminal outcome.

## Verification

The byte oracle derives source bytes from an independent memory image and
checks source/destination unit sequences, lane masks, payloads and every final
memory byte. It does not duplicate the engine's buffering or scheduling.
The deterministic matrix covers all nine width combinations, four
fixed/increment modes, every naturally aligned lane, and 1 through 9 source
units, with delayed and same-edge responses. Separate tests cover paced
endpoints, stalls, immutable descriptors, restart rejection, stop before and
after acceptance, error precedence, failed read/write prefixes, range/count
boundaries and coordinated reset/restart. A second matrix covers byte budgets
from 1 through 13 that end inside a 2- or 4-byte source unit, across all modes,
legal lanes and destination widths, with both response timing modes. Range
checks retain a carry above the whole byte budget; large fixed-endpoint
budgets remain representable without wrapping.

The old complete-source-unit matrix supplies `unit_count * source_bytes` as
its byte budget. This is a regression fixture convention, not a claim about
NEM-4 count registers. In particular, a memory-to-memory frontend can supply
a halfword-based count while using 32-bit accesses, and a paced transfer can
count peripheral bytes despite a wider memory side. Count conversion belongs
to the caller; the engine always transfers exactly `transfer_bytes` bytes.

Passing this test proves the standalone transfer contract. It does not establish
NEM-4 channel programming, peripheral aliases, IRQ routing, chip timing, firmware
behavior or FPGA fit.
