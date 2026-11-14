# Native MMC identification: long-response completion ordering

## Hardware failure and donor comparison

Original ngage1 build2d9605f detects the unchanged SPMark04 image but reports
“memorycard corrupted”. The host file position remains after the metadata
footer; no payload-sector request was qualified. A fresh-Hold observation-only
trace preserves original firmware behavior and checksum validation:

```
CMD0: success
CMD1 arg80008000: OCR00ff8000, then80ff8000 (ready)
CMD2: raw host status100, native result8000, no CID copied
```

The sequence retries. Raw status/event tracing resolves the discrepancy:
CMD2 starts with status8/busy and a wait mask0a. Source23/CmdIdle is serviced
with status100/response available, but its callback updates only native event2.
The resumed R2 state machine consumes event2 without event8 and returns8000 at
503f466c. This is before FAT, application discovery or SPMark execution.

The donor checkout0fe531f uses the same host behavior (last host change6b1055b),
four-word R2 FIFO, level IRQs and lowest-source ICU priority. Its working QD
path does not establish that this ordering works with the original NEM-4 driver
and our CPU latency. No donor, global ICU priority or firmware change is made.
The failure is independently reproduced with the actual original NEM-4 code
on ZAP, production host/ICU and delayed IRQ service.

## Small host correction

Original EPBUS503f49b0..503f4af8 consumes three R2 words through response-ready,
then waits command-idle and consumes the fourth. Keep C_TAIL busy until those
first three words are read. Saturate its existing tail counter while waiting.
R1/R3/data transfers are unchanged; R2 CRC error or missing response releases
busy normally. Reset/new command retains existing abort behavior.

The implementation adds no registers or RAM in source; only tail-state
qualification changes. Fitted area/timing still require a new build. PLL stays
78MHz;104MHz remains the design objective. This is a register-level ordering
model supported by the original driver, not measured physical UPP pin timing.

## Verification

| Check | Result |
| --- | --- |
| Original EPBUS R2 FSM/event/status code on ZAP, old host | Native8000 reproduced with no CID copied |
| Same unchanged driver, corrected host, bus wait0/3 | Exact128-bit CID and native completion;11463/16661clocks |
| Independent host accepted-length/response tests | 33probes,126430clocks; includes R2 CRC error and timeout release |
| Independent host data peers | 28cases each, DIV4/FIFO16:82004; DIV12/FIFO8:244751clocks |
| Production ZAP/board/card/HPS/DMA fixture | Full512-byte DMA/PIO and prior odd/padding/ICU/WP checks;197627clocks/4HPSreads |
| Same fixture with CPU Hold during metadata |198041clocks/5HPSreads |
| Language/format | Strict Verilog-2001 host lint and pinned Verible pass |

The old pinned host runner's final formatter step names a missing pre-worktree-
consolidation path; its behavioral tests passed. Formatting and lint were run
separately with the installed pinned tool. No tool download was needed.

The previously preserved but unrun full-sector authored test had swapped DMA
source-width/count values. Corrected that fixture to width8/count511; production
DMA was not changed to accommodate it. The new native regression explicitly
mocks kernel scheduling/interrupt export boundaries and starts at registered
R2-wait state. It is not a full native enumeration or filesystem-mount test.

## Diagnostic hygiene and remaining gate

An initial RDebug-service probe was invalid in kernel context (ABT503aec54,
reason10000000); discard boot-trace/probe-follow captures from that attempt.
Corrected hooks use the existing privileged59000000 byte-output endpoint,
preserve GPRs/flags/stack and replay original instructions;320 randomized ABI
and exact-output cases pass. Captures and selected small sources are in
`scratch/mmc-native-20261114/`; no ROM/image bytes are checked in.

A new FPGA build and original-firmware boot must verify CMD2/CID, CMD9/CSD,
then actual sector reads and a native mount of the same SPMark04 card. There
are no benchmark scores yet. Keep formatting and background saves off. Remove
all observation hooks by reloading the original/new RBF before final acceptance.
