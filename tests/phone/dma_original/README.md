# Original NEM-4 DMA programming fixture

Run from the repository root, supplying the private original ROM:

```sh
sh tests/phone/dma_original/run.sh /path/to/ngage-rom-0x50000000.dmp
```

The runner verifies SHA-256
`26ca1dd937e299fd4ec3ad65a25d395743ae2149311c3d753cbeb5437673dbc5`,
extracts the original `50320000..503d0000` instruction window without modifying
instructions, and calls the original functions on ZAP:

| Case | Setup / start | Original descriptor for 16 bytes |
| --- | --- | --- |
| SDRAM to SDRAM | `5032130c` / `503213c4` | 32/32-bit widths, raw count 7, control 1 |
| SDRAM to type-5 FIFO | `50321444` / `50321568` | 32/8-bit widths, raw count 15, control 2 |
| Type-5 FIFO to SDRAM | `503215e8` / `5032170c` | 8/32-bit widths, raw count 15, control 2 |
| On-chip RAM to SDRAM | `5032130c` / `503213c4` | 16/32-bit widths, raw count 7, control 1 |

Both zero and three memory-wait runs verify all 4 KiB of SDRAM and on-chip
memory after every case, including source data and unwritten trails. The
transmit FIFO reserves and compares exactly sixteen ordered bytes; the receive
FIFO provides exactly sixteen distinct ordered bytes. The fixture also checks
original start bookkeeping at `80000e4c + channel*4`, the original type-5 selector
clear/set writes, channel completion and absence of model errors. After each
verified transfer the CPU executes original stop routine `503212c0`, including
its stop write, idle poll and channel disable/acknowledgment. Exactly the current
channel owns the pending IRQ at each transfer check; no IRQ remains at the next
original start or the final pass.

The following are explicit fixture boundaries:

- The CPU's original virtual `5812xxxx` register accesses are translated to
  physical `0c12xxxx` at the candidate DMA frontend, without enabling the MMU.
- Original request selector writes at `58120068/64` are captured and checked,
  and also fed to the frontend when PRODUCTION_PROFILE=1.
- Exact address `10120624` is intercepted by a test-only byte FIFO **before**
  `ngage_dma_route`. This isolates the native programming/admission/pacing contract; the separate
  mmc_mister fixture covers the actual production endpoint.
- SDRAM and on-chip RAM use bounded testbench arrays and delayed responses.
  The original MMIO helpers and start bookkeeping execute without replacement.
- IRQs are checked in the candidate frontend. The CPU polls the original run
  register and executes the original stop/acknowledgment routine; the original
  ISR/DFC path, P4 transition and board ICU assignments are outside this test.

Generated private instructions, manifest, build and run logs stay under
`scratch/ngage2-integration/p2/original/`. No long-running phone simulation or
checkpoint is opened or changed.

Observed locally on 2026-11-11: all four cases passed with zero memory waits
in 11,130 cycles and three memory waits in 16,814 cycles, including the original
stop/acknowledgment after every case. This establishes compatibility between
those original programming routines and the candidate frontend's byte-budget
interpretation, within the fixture boundaries above.

## Production admission profile

`DMA_PRODUCTION_PROFILE=1 PHONE_TEST_OUT=build/sim/unit-native-mmc-dma-control2
sh tests/phone/dma_original/run.sh ROM` selects the real production request
policy with2workers and feeds original selector writes into it. Native TX and
RX both use control2. The old production filter failed RX with channel2 error04;
the corrected filter passes all4cases at11130/16814clocks (wait0/3). The default
generic profile retains the same results. FIFO readiness uses the bounded
fixture reservation, and original kernel instructions remain unchanged.
