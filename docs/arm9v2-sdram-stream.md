# V5 streaming SDRAM controller

V5's production MiSTer top now uses the ngage2 SDRAM scheduler, adapted
to keep native 32-byte v5 cache refills. The checked original GLES
176×208 fill completes in **124,998 clocks at 78 MHz**. That is 58.2%
fewer clocks than the 299,252-clock v5 JTFRAME baseline and 16.6% fewer
than stock ngage2's 149,869. This measures the original fill function
through the CPU and the physical SDRAM model.

| CPU and SDRAM path | GLES fill clocks | Sega Rally scan clocks |
| --- | ---: | ---: |
| v5 with JTFRAME | 299,252 | 2,466,436 |
| Stock ngage2 | 149,869 | 4,456,598 |
| ngage2 with v5 D-cache capacity and section TLB index | 173,629 | 2,441,243 |
| v5 with unchanged ngage2 scheduler, two 16-byte requests | 135,528 | 2,419,482 |
| v5 production scheduler, one 32-byte request | 124,998 | 2,399,797 |

Each full-screen comparison uses the same original payload bytes,
NEM-4 helpers, framebuffer dimensions and guest output checks.
The 15 retained payloads pass twice on the production controller at
78 MHz with 32 KiB flash backing, 39 MHz MMC and the v5 TLB XOR.
Fourteen are faster than the JTFRAME control. JPEG takes exactly the
same number of clocks. Every deliberately corrupted expected result
fails, and the passed mailbox is checked after physical SDRAM drain.

## Production block writeback and the half-line comparison

The MiSTer build selects `NGAGE_BLOCK_WRITEBACK` in `files.qip`. The
ARM9V2 victim buffer sends one captured 16-byte half beside each write
request. The UPP, board and MiSTer expose it to the SDRAM arbiter, which
captures the payload at CPU admission. The stream adapter queues the
payload through pin admission and preserves it across a logical reset.
The scheduler emits eight single-location WRITEs per 16-byte request.
CPU cache refills are still 32 bytes and LCD DMA reads use 16 bytes.

The production 32-byte dirty-line build reproduced every timing and
memory-counter window from the original 16-byte writeback experiment.
The half-line replay held cache geometry, the folded section TLB index,
SDRAM model, clocks and writeback interface fixed. Only the dirty-half
mask determines which 16-byte blocks the candidate sends. The matched
control packs both flags and writes both halves. It reproduced every
production timing and memory-counter window.

| Payload | Posted 32-bit writes | Production 16-byte blocks | True half-line dirty tracking | Blocks (production → half-dirty) |
| --- | ---: | ---: | ---: | ---: |
| GLES full-frame fill | 124,998 | 112,705 | 112,702 | 4,064 → 4,063 |
| Sega Rally full-screen scan | 2,399,797 | 2,391,228 | 2,389,563 | 4,274 → 3,358 |

The other 13 median timings match production exactly. Half-line tracking
cuts Sega scan block writes by 21.43% and elapsed clocks by 0.07%.
Production keeps line-wide dirty tracking for this build. The half-line
option remains a simulation candidate. Top-level structural elaboration,
the block data and reset-drain contract, 18 LCD pin simulations and all
15 checked payloads pass.
Quartus fitting and on-board 3DMark are still open.

## Initial 16-byte dirty-line writeback experiment

The active v5 CPU marks dirty data per 32-byte line. The control sends a
dirty victim as eight 32-bit requests even though the CPU marks the
sequence with Wishbone CTI. The simulation candidate sends two 16-byte
requests directly from the victim buffer through the same one-entry
posting queue. Each block still issues eight single-location SDRAM WRITE
commands. Cache refills and explicit cache maintenance use their existing
paths. This first candidate used a simulation overlay.

Both legs replayed all 15 retained workloads at 78 MHz with the same
SDRAM pin model, 39 MHz MMC, 64 Hz NOS and 32 KiB flash backing. Times
are median CPU clocks. The block count comes from the first scored window.

| Payload | 32-bit requests | 16-byte blocks | Clock change | Blocks |
| --- | ---: | ---: | ---: | ---: |
| matrix4 | 17,835 | 17,835 | 0.00% | 0 |
| transpose4 | 2,772 | 2,772 | 0.00% | 0 |
| triangle_edges | 12,389 | 12,389 | 0.00% | 0 |
| fill16_frame | 124,998 | 112,705 | −9.83% | 4,064 |
| fill16_tail | 726 | 726 | 0.00% | 0 |
| fill8_tail | 747 | 747 | 0.00% | 0 |
| monkey-forward | 16,446 | 16,443 | −0.02% | 0 |
| monkey-reverse | 16,446 | 16,443 | −0.02% | 0 |
| sega-span | 15,936 | 15,936 | 0.00% | 0 |
| sega-fill | 2,622 | 2,622 | 0.00% | 0 |
| asphalt-table | 21,900 | 21,904 | +0.02% | 10 |
| asphalt-double | 12,486 | 12,469 | −0.14% | 10 |
| asphalt-single | 8,268 | 8,268 | 0.00% | 0 |
| sega-scan | 2,399,797 | 2,391,228 | −0.36% | 4,274 |
| diffuse_m10_8x8_jpeg | 35,903 | 35,903 | 0.00% | 0 |

All valid runs passed their guest output checks and matched their
repeats. Both legs rejected all 15 deliberately wrong guests. Expanding
the 16-byte blocks gave the same ordered write addresses for the traced
window of every workload. The full-frame fill replaced 16,256 scalar
writes with 4,064 block writes and saved 12,293 clocks, or 0.158 ms at
78 MHz. On-board 3DMark FPS remains unmeasured.

The [runner instructions](../tests/cpu/arm9v2_board/README.md#replay-the-payloads-with-the-phones-mmc-and-nos-clocks)
describe both legs. Results and traces are under `build/sim/payload-clocks/`
in `v5-block-writeback-control` and `v5-block-writeback-16`.

## Request and pin path

Standalone ngage2 arbitrates CPU and DMA Wishbone traffic in
`rtl/upp/wb_arb2.sv`. Its `upp_bus.sv` holds the posted write address,
data and byte enables while the custom open-page SDR SDRAM scheduler
in `rtl/mem/sdram.sv` drains the previous operation. The four banks
are interleaved at 4 KiB by address bits 13:12. The controller issues
commands through registered I/O, enforces refresh and write recovery,
and can start a new row-hit word write every three clocks.

V5 keeps its own CPU, DMA arbiter and NOR/refill interface. The stream
adapter owns one queued write and forwards it directly when the
scheduler can accept it. Reads and refills wait for earlier posted
writes. The CPU lock retains synchronous completion for atomic writes.
Logical reset suppresses canceled replies and drains accepted stores.
The scheduler borrows ngage2's pin stages and timing constraints.
A 32-byte refill issues two BL8 READ commands eight clocks apart.
The cold scrub uses 16-byte writes and covers the entire 16 MiB RAM
before CPU release. CPU, LCD and general DMA share the same mapping.

The original scheduler is pinned to ngage2 `ff6dcff`, and the imported
V5 copy is Verilog-2001. The MiSTer top elaborates with its production
CPU selection. Pin simulation uses a common Micron model and the
donor capture-edge arrangement, with 5.5 ns of modeled DQ return
delay. Physical I/O closure and the native SPMark Game FPS after the
change still require a board build and run.

## Verify in simulation

```sh
sh tests/phone/sdram/run-stream.sh fresh-stream-contract
python3 tests/cpu/arm9v2_board/payload_clocks.py --name fresh-stream-payloads \
  --config 2:64 --flash-cache-bytes 32768 --stream-sdram \
  --sdram-model build/sim/fresh-stream-contract/mt48lc16m16a2.v
```

[Clock counts and build-source hashes](evidence/arm9v2-sdram-stream-20261119.json) ·
[Previous write cadence measurements](arm9v2-sdram-handoff.md)
