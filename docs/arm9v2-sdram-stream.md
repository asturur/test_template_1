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

## Registered scalar reply at 104 MHz

The stream captures the scalar read word and reply together. The arbiter
keeps the CPU or DMA owner through that reply clock. A waiting line can
take the command slot on the reply edge, and its first halfword still
follows the early line path. Posted writes and locked write completion
keep their original timing. Reset suppresses a captured reply and the
pin transaction drains before admitting another owner.

Both pin tests passed, with maximum refresh intervals of 563 clocks at
78 MHz and 758 at 104 MHz. Their checks cover a canceled pin read,
reset after reply capture, and simultaneous scalar retirement and line
admission. At 104 MHz the 15 fixed payloads pass with at most 0.038%
more clocks. The native PolyCount replay preserves the guest output and
retired work for all four frames. Its warm median changes from
14,345,830 to 14,346,201 clocks.

The 16-byte LCD path matches the original aligned and refill-only cases.
Its largest change is 1.47% more clocks with periodic scalar contention.
The scalar-only LCD control takes 11.66–12.87% more clocks. The separate
mixed pin replay with scalar LCD changes by 0.038% and checks an exact
MMC sector write/readback, 18,304 LCD words and playback without underflow.

### Slow bus ownership after capture

The CPU address decode selects the direct RAM or slow UPP route when a
packet enters the bus. The existing UPP bridge and shared request stage
capture the slow owner and packet on that edge. For an owned CPU packet,
the bridge keeps it live from its active state, the requester's CYC and
DMA exclusion. For local DMA, the held DMA owner keeps the packet live.
The shared stage drops the packet on cancellation or retirement. This
keeps the live address decode off the slow request's commit and memory
ownership path, which can otherwise feed the next RAM refill offer.

A matched test compares adjacent RAM and slow packets under continuous
CYC, late replies after cancellation, errors, and local DMA reservation
and lock handoffs. Both designs deliver 162 replies and 32 errors on the
same cycles. The 18 LCD pin cases and the mixed 104 MHz MMC, PCM and LCD
replay have identical timing records and outputs. All 15 fixed payloads
and all four native PolyCount frames also match cycle for cycle.

### SDRAM packet fields and admission

DMA can offer a legal RAM word while a local endpoint is stalled. A live
MMC command still waits for local-ready before acceptance. The SDRAM
stream forms write data and byte enables from the accepted scalar or
queued write. The lane comes from that write's address, independently of
any competing read or refill.

While the scheduler command slot is empty, it samples the candidate
fields. Admission sets the valid bit on that same edge. The slot holds
the packet until the scheduler takes it, including while an older pin
transaction or refresh is active. A candidate sampled without admission
has no effect on SDRAM. This removes late admission from the wide packet
register enable without adding a request clock.

The pin tests at 78 and 104 MHz each accept and issue 1,048,650 commands,
including the full cold scrub, with the same burst and refresh records as
before. A side-by-side 104 MHz test against `ff8becc` matches handshakes,
accepted addresses and write masks, and returned data cycle for cycle.
All 18 LCD pin cases and the mixed 104 MHz MMC, PCM and LCD replay match
their prior results, including the 512-byte persisted sector and
readback. The four ARM contracts, 15 fixed payloads and all four native
PolyCount frames also match their previous cycle counts and outputs.

### Owned completion at the CPU Wishbone boundary

The 104 MHz seed 42 and 43 paths from `6c569de` ran from board reset or
scalar acceptance through the reply, cache request logic, and the next
Wishbone packet's address. The refill adapter captures scalar writes,
slow reads, and errors with their returned data. It suppresses external
CYC while the donor consumes the captured reply, keeping the previous
address from issuing twice. The donor's CYC and reset still qualify the
reply, and SWP keeps its reservation across both beats.

An owned SDRAM read can use the stream's existing reply register directly.
The independent pulse travels with the registered CPU owner and the
route's outstanding transaction. The combined board ACK, including posted
acceptance, reaches the donor through the completion register. For native line
reads, lookahead registers each word's availability on its original clock.
A simulation assertion compares line availability and errors against the
previous reply logic on every active clock.

At 104 MHz, buffering every scalar reply increased transpose by 8.065%.
The owned SDRAM read path restores 2,976 clocks. Nine of the 15 fixed
payload medians match `6c569de`, four improve, the full-frame dirty
writeback takes 0.031% more clocks, and Sega scan takes 0.086% more. Four
native PolyCount frames take 57,522,526 clocks, up 0.0135%, with identical
retired work and output. The
forced scalar-only CPU contract takes 19.138% and 9.855% more clocks at
its zero- and five-clock wait settings. The line-enabled variants take
1.440% and 1.345% more. These tests include rejected lines, page walks,
and abort recovery. The mixed scalar-LCD and MMC-polling pin replay takes
7.266% more clocks. Its 512-byte persisted write and readback match, and
audio playback completes without an underrun.

The 78 and 104 MHz pin tests match the original SDRAM command ordering,
pin beats, and refresh intervals. The focused Wishbone tests check two
same-address MMIO writes, held I/D arbitration, reply cancellation and
reset, SWP, rejected lines, and consecutive, gapped, and fallible bursts.

## Verify in simulation

```sh
sh tests/phone/sdram/run-stream.sh fresh-stream-contract
sh tests/cpu/arm9v2_board/run-wb-completion.sh fresh-wb-completion
python3 tests/cpu/arm9v2_board/payload_clocks.py --name fresh-stream-payloads \
  --config 2:64 --flash-cache-bytes 32768 --stream-sdram \
  --sdram-model build/sim/fresh-stream-contract/mt48lc16m16a2.v
```

[Clock counts and build-source hashes](evidence/arm9v2-sdram-stream-20261119.json) ·
[Previous write cadence measurements](arm9v2-sdram-handoff.md)
