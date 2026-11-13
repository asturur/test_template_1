# N-Gage2 timing investigation, 2026-11-12

## LCD implementation checkpoint

The new path is now staged in `scratch/ngage2-timing-20261112` and packaged as
[a separate LCD patch](evidence/ngage2-lcd-fast-2026-11-12.patch). It contains
two general workers plus a descriptor-selected word-only LCD reader and native
FIFO admission. There is **no feature switch**; a master build is the comparison.
Unsupported descriptor formats retain generic DMA handling. No SDRAM-controller,
CPU, panel serializer, clock or constraint changes; no burst prefetch yet.

DMA/LCD modules, the focused bench and integrated UPP hierarchy pass local
Icarus elaboration. Runtime tests, Verilator top, fit and board qualification
have NOT run: this session's Docker socket remains denied. The regression is
provided in `tests/lcd_fast/`; use the existing container and run
`make -C sim lcd-fast dma-count periph top` before promotion. The focused bench
covers bytes/all channels/cancellation/readback/full-FIFO/blocked workers, but
is not a replacement for real peripheral readiness and top-level arbitration.
Source review found no obvious ownership/cancellation issue. No area/FPS result
is claimed. Implementation and manual instructions are in the staged checkout's
`docs/LCD_DMA.md`; [provenance](evidence/ngage2-lcd-fast-2026-11-12.json).

The sibling checkout is unchanged. To apply this standalone patch there using
a normal terminal:

```sh
git -C /Users/andreabogazzi/develop/ngage2 apply /Users/andreabogazzi/develop/NGage_MiSTer/docs/evidence/ngage2-lcd-fast-2026-11-12.patch
```

### Where the picture is stored

| Stage | Location | Role |
| --- | --- | --- |
| Game/OS source framebuffer | External SDRAM | CPU renders here; LCD driver programs DMA source/count |
| LCD interface FIFO | Small FPGA RAM queue | Fixed destination10121208 (canonical0c121208), not a full frame |
| Emulated panel framebuffer | FPGA block RAM in `lcd_panel.fb` |176x208x16-bit screen memory; video scanout reads it |

On the phone the last memory lives inside the display controller/panel. The
core implements that separate memory in FPGA RAM, not the main SDRAM. Native
DMA still fills the same interface FIFO and panel memory; it bypasses the
shared-bus destination transaction, not panel packing or display memory.

The assessment sections below record earlier design reasoning; this checkpoint
supersedes their implementation-not-started state.

## Scope and stopping point

Target is the sibling `ngage2` core, not this checkout's ngage1 integration.
Source branch is `codex/mmc-payload-eof-fix`, pinned at
`542300b8dae1afb3e61c840d024364f29e0ca4a6`. Its untracked MMC experiments were
not copied or edited. The investigation checkout is
`scratch/ngage2-timing-20261112`, branch `codex/ngage2-timing-1000`.
It contains the reporting changes; the sibling checkout remains unchanged.
This session can write inside NGage_MiSTer, not the sibling checkout.

The reporting patch is ready for a real Quartus17 run. The local Docker socket
is inaccessible (`operation not permitted`); no simulation or fit was launched.
No current routed reports exist locally in ngage2. The connected GitHub lookup
for PR-triggered runs of 2904ebc returned none; this does not establish absence
of push/manual builds. No remote branches/CI or running boot were changed.

## Reporting change

[Portable patch](evidence/ngage2-timing-export-2026-11-12.patch) applies to the
pinned ngage2 tree. It changes `tools/report_timing.tcl`, the CI artifact/summary
steps, seed-report fetching, building docs and adds summary/regression helpers.

- Default count becomes 1,000, optional argument 1..10,000.
- Every available operating corner gets up to 1,000 **negative setup paths**,
  worst first, one worst path per endpoint (`-less_than_slack 0 -nworst 1`).
  This distributes the sample across sinks; it is not every failing path.
- `build/timing/corners.csv` maps numbered directories to actual corner names
  and exported counts. Each has full routes, machine-readable CSV, hold paths
  and Fmax. Passing corners retain a header-only setup CSV.
- Existing initial-corner `critical-paths.rpt` also gets the new count/filter;
  use the indexed per-corner files for analysis.
- All-corner setup/hold/recovery/removal and gated-video-clock uncertainty
  checks retain their failure exit. No SDC/clock/RTL settings change.
- CI publishes reports and block-pair summaries even on a timing failure.
  Seed fetching tolerates historical builds without the new report directory.

Checks: `python3 tests/timing/check.py` in the staged checkout passes eight
mock-STA orchestration cases: negative and passing corners, default/custom
limits, quoted CSV names, uncertainty rejection, empty corner rejection and
invalid counts. Shell syntax and diff whitespace checks pass. These checks do
not validate the Quartus17 runtime/API or prove physical timing.

After a completed fit:

```sh
quartus_sta -t tools/report_timing.tcl 1000
python3 tools/summarize_timing.py build/timing/corner-*/failing-setup.csv
```

An export hitting 1,000 may be truncated. Its summed slacks are not whole-core
TNS. Repeated endpoints at different corners are not independent failures.

## Evidence toward 104 MHz

The latest documented release is trimmed source `91a6d08`, seed9: setup
**-1.453 ns**, hold **+0.243 ns**, **33,473 ALMs**. Eight seeds range from
-1.453 to -2.446 ns. This is historical evidence in ngage2's
`docs/PROGRESS-LOG.md`, final section; it predates the current DMA count fix.
Do not assign older 519-M10K/42-DSP totals to this revision without its report.

The Nov9 study (same log, “timing pass on master”) found 9–11 LUT levels with
65–78% routing delay. Simultaneous families included TLB physical address to
D-cache lock summary, decode D1 to D2 packet, W/S/A forwarding through the
address adder into cache RAM, cache load data through late bypass to M, and
D2 register reads. The bus/flash/peripheral cones also failed around -1 ns.
These are historical priorities, not classifications of unseen current paths.

Current source seams to correlate with the new reports:

| Family | ngage2 source |
| --- | --- |
| Selected lookup address and FCSE | `rtl/cpu/arm9v2/arm9v2_core.sv`, `lookup_address` around851 |
| Late operand forwarding/address sum | `rtl/cpu/arm9v2/arm9v2_execute.sv` around465 and635–646 |
| Cache lock summaries | `rtl/cpu/zap/zap_dcache_fsm.sv`, `lock_set_nxt` around275 and summary registers around495 |
| Load trust/hit qualification | `rtl/cpu/arm9v2/arm9v2_core.sv` around1084 |

MLAB RF, LOCK_SPLIT, registered load trust/hit candidates, one-hot FREE_SELECT
and registered TLB readiness already exist here. Integration CPU patches are
not automatically missing ports: ngage2 uses ARM9V2, integration uses owned-
operand ZAP. Quartus compiles `rtl/cpu/arm925t_gen.v`; source edits require
regeneration and `cpu-gen-check`.

Avoid repeating documented rejected CPU region, blind retiming, low packing,
S_AGU=1 and parallel-AGU trials without a new path-specific reason. Their
correctness did not translate into routed gains; parallel AGU added480 ALMs.

## DMA and LCD port assessment

ngage2 `upp_periph` defaults to three DMA engines; production `NGage.sv` does
not override it. Integration explicitly uses two general workers **plus an
independent LCD stream**. Its stalled-MMC/copy/LCD benchmark measured148,479
clocks with either two or three general workers; this relies on that stream.
It does not justify reducing ngage2 to two while LCD still takes a worker.

[Separate two-worker experiment patch](evidence/ngage2-two-workers-experiment-2026-11-12.patch)
adds only a production `.DMA_ENGINES(2)` override. It is **not applied, simulated
or recommended for promotion yet**. Generic test defaults remain three.

ngage2's `upp_lcdif.sv` models a serialized 8-bit panel bus, read phases,
packing, WR_LOW/HIGH timing and an ordered command/data FIFO. Integration's
`ngage_lcd_stream.v` ends at a transaction-level pixel queue. Copying it to the
panel directly would bypass modeled behavior.

Proposed port sequence, not implemented:

1. Give LCD DMA writes a native valid/ready/data input into the existing
   LCD-interface FIFO. Arbitrate with CPU command/data writes and retain exact
   FIFO ordering, fullness/readiness and panel byte timing. Keep memory reads
   on existing Wishbone initially. This removes write-side arbitration/decode
   work but does not yet free a general descriptor worker.
2. If worthwhile, add independent SDRAM-to-LCD descriptor ownership. Preserve
   shared memory arbitration, CPU/SWP exclusion, accepted-read drain on stop,
   reset/restart cancellation, residual/tail bytes, completion and IRQ timing.
3. Then compare two general workers against three under stalled MMC + LCD +
   copy. Preserve all eight channels and outstanding ownership. Measure CPU
   latency and transfer clocks as well as ALMs, setup, TNS and hold.

ngage2's own counter study reports upload4–5 ms /22–28 clocks per word against
about16 at the panel interface. CPU usually runs during uploads, so lower
upload latency does not establish a game-FPS improvement. Lower worker logic
may ease routing congestion; it cannot be assumed to close all CPU stages.

## Current direction: price the LCD port first

User clarification supersedes the baseline-fit-first sequence: decide whether
an LCD-specific port makes sense and price its implementation/resources.
A fresh baseline fit is not a prerequisite for this architectural assessment.

**Recommendation: two general workers plus one lightweight LCD reader, using
existing memory arbitration and a native write handshake into upp_lcdif.**
A separate SDRAM-controller port is unnecessary for this first design. The LCD
reader participates in the existing DMA read scheduler; two generic requesters
plus one specialized requester still make three read-arbitration inputs.
The LCD's destination writes no longer enter the audio/shared-master selection,
CPU/DMA Wishbone arbiter, peripheral register bus or generic register storage.
The physical panel FIFO, serializer and timings remain.

### Resource budget, not synthesis results

The current per-worker arrays in `upp_dma.sv` declare exactly251 state bits:

| State | Bits per general worker |
| --- | ---: |
| State and channel |5 |
| Source and destination |64 |
| Remaining byte budget |35 |
| Conversion buffer and fill |68 |
| Increment/width/abort fields |7 |
| Prepared write flag, address, data, lanes and transfer size |72 |
| Total |251 |

These are source declarations, not251 guaranteed physical FFs: constant bits
and synthesis sharing can reduce them. Reducing three general workers to two
also simplifies some selectors/arithmetic; adding a specialized third requester
means the read scheduler itself still has three clients.

For eligible aligned32-bit SDRAM -> fixed LCD FIFO transfers, a specialized
reader needs source32, remaining-word count33 (count-minus-one can describe
2^32 words), held payload32, channel3, FSM/cancel/ownership flags about6:
approximately106 bits of active state. It needs no destination counter,
variable-width packing buffer or byte-shift network. Reuse the current
parameter-RAM loader and existing LCD queue; no additional M10K is necessary.

There is an easily missed cost: ordinary FIFO-register reads currently return
its last written word from generic peripheral storage. Native writes bypass
that storage. Preserve this behavior with a32-bit last-word shadow in lcdif,
updated by both CPU and native writes and covered by rmask on ordinary reads.
A small route/reservation allowance, and optionally another32-bit skid word,
gives a **working budget of140–180 added declared FF bits** for the specialized
reader plus bridge/readback. Against removing251, that is approximately
**70–110 fewer declared FF bits**, before shared-control changes/optimization.
This is a design estimate, not a measured resource saving or ALM conversion.
The generic shifts, increments, destination storage and write-request machinery
removed should also reduce logic; read arbitration does not disappear.

A FIFO-only bypass keeping all three general workers is cheaper to implement
but adds logic: one32-bit data selector, eligible-write routing/handshake and
about32–40 state bits if preserving last-word readback and a registered route.
It needs no new RAM, but still occupies a general worker for LCD.

### Eligibility and integration cost

Keep the specialized case narrow: peripheral-paced transfer, incrementing
aligned SDRAM source,32-bit source and destination widths, fixed canonical LCD
FIFO destination. Other descriptors continue through general workers. Do not
assume a fixed channel number. Preserve existing count semantics, accepted-read
error behavior, stop/restart and interrupt precedence. An unsupported third
simultaneous generic transfer can wait when only two general workers exist;
this is a concurrency change, not a guaranteed preservation of all3-worker
schedules. LCD itself no longer consumes either general slot.

The changes are local to the DMA loader/scheduler, `upp_periph` wiring/feedback
and `upp_lcdif` FIFO admission/readback; a separate reader module can hold the
new state. No CPU/generated CPU, SDRAM controller, board pins or clock edits
are needed. Reuse registered request ownership, avoiding a live32-bit address
comparator in the FIFO-ready/ACK path. Give selected CPU LCD accesses priority
before their pipelined readiness sample; arbitrating only at the final CPU
write strobe risks a native enqueue invalidating a previously sampled room bit.
Preserve ordering of control and data through the single existing FIFO.

### Expected benefit and limits

A36608-pixel RGB444 frame uses18304 DMA words. The current path issues18304
shared-bus reads AND18304 shared-bus peripheral writes. The proposed design
retains the reads and performs the writes locally: **50% fewer shared DMA bus
transactions for that eligible transfer**, not50% fewer occupied clocks.
SDRAM read traffic and arbitration against CPU/audio reads remain unchanged.

At104 MHz, the existing panel FSM takes16 clocks per3-byte/two-pixel word
(three5-clock byte cycles plus a word-load clock), about2.816ms per frame before
commands. Historical uploads3.97–4.93ms leave a theoretical roughly29–43%
upload-duration reduction if the native reader keeps that FIFO supplied.
This is a ceiling, not an expected measured speedup: the same shared SDRAM read
latency can still dominate. Source-side bursts/direct SDRAM admission would be
a distinct, more expensive step if the FIFO repeatedly empties.

Existing game counters show substantial overlap between upload and CPU work;
no numeric FPS gain follows from shortening uploads. This port makes sense as
a small DMA simplification and bus-contention reduction, especially when paired
with removing the generic worker. It does not alone shorten the historical
CPU-internal critical paths or establish104MHz closure. No implementation,
ALM measurement, simulation or frequency gain is claimed in this assessment.

Required RTL gates: ngage2 DMA-count, peripheral/audio and top benches; new
1/2/3-worker concurrency cases; full-FIFO and simultaneous CPU/native writes;
stop/restart/accepted-read/last-word races; every width and MMC direction;
unchanged IRQ and exact panel-byte sequences for12/16-bpp, commands and reads.
Use the existing `jotego/simulator:arm64` image when simulation is available.
Keep fit/simulation outputs under this investigation's scratch/build paths.

[Machine-readable checkpoint](evidence/ngage2-timing-investigation-2026-11-12.json).

## SDRAM comparison with ngage1 integration

Source-only comparison on2026-11-12; no new timing/throughput simulation or fit.
Actual source is authoritative over older explanatory documents.

| Aspect | ngage2 | ngage1 integration |
| --- | --- | --- |
| Physical controller | Custom Sorgelig-derived `rtl/mem/sdram.sv` | Modified JTFRAME `rtl/sdram/jtframe_sdram64*.v` |
| Operating clock |104MHz |78MHz production;104MHz design objective |
| Logical interface |32-bit word or128-bit block, streaming32-bit read results |32-bit scalar adapter and256-bit logical refill streaming16-bit results |
| Physical read burst | BL8; word reads terminate after two halfwords | BL8; scalar reads terminate after two halfwords;32-byte refill uses two BL8s |
| Physical writes | Two consecutive single-location writes per word; eight per16-byte block | Adapter issues two distinct masked16-bit operations per32-bit write, with explicit gaps; no equivalent native128-bit write interface |
| Page policy | Four tracked open rows, bank bits at byte13:12 | Per-bank open-row tracking; phone uses two8MiB physical banks, bank select at bit23 |
| Scheduling | One operation in flight, no overlapping/reordered accesses | JTFRAME has per-bank scheduling machinery, but current phone adapter serializes requests |
| Timing parameters | ns values rounded up for CLK_HZ, explicit row ages/tRAS/tRC | HF-mode state schedules plus top-level clock-scaled refresh trigger |
| Refresh | Deadline-based one-refresh service, all rows closed | Debt scheduler credited9 refreshes per~65.4us; services debt with arbitration |
| Read capture | Rising-edge DQ capture with extra command-output stage and CAPTURE_CLKS schedule | ALTDDIO_IN falling-edge capture/resynchronization |
| LCD route | General DMA word reads through shared Wishbone and upp_bus | Dedicated LCD reader bypasses peripheral bridge but shares CPU/DMA SDRAM arbiter and scalar adapter |

Both forward an inverted system clock to SDRAM. Their command-output pipeline
and capture schedule differ: do not copy one input edge without its associated
latency/IO timing design. ngage2's documented running board builds do not imply
all-module timing qualification; ngage1's model-tested78/104MHz path does not
establish a faster controller.

ngage2's documented controller-only104MHz row-hit schedule: first32-bit word
at5 clocks, next scalar request at6; four-word line results at5/7/9/11, next
request at12; scalar write next request at3, block write at9. Closed banks add
3 clocks; conflicts add at least6 plus row-age waits. Those numbers exclude DMA,
CPU contention and Wishbone routing, and are not directly comparable with a
cache-miss benchmark or the measured22–28 clocks per LCD word.

**Recommendation: keep ngage2's controller.** Integration supplies a useful
route/ownership design, not evidence of a superior physical controller. There
is no reason to pay for a controller replacement to add the native LCD sink.
The next source-side opportunity is using ngage2's already implemented16-byte
reads: general DMA currently emits classic single-word accesses, so it does
not exploit that four-word mode. upp_bus already recognizes CPU CTI bursts and
turns them into line requests; an LCD reader could use bounded bursts through
an adapted DMA path, or arbitrate directly at the existing controller request
boundary. Neither requires rewriting pin-level SDRAM scheduling.

A four-word row-hit read occupies12 controller clocks rather than four6-clock
scalar slots (24), excluding wrappers/refresh/contention. This is a capacity
comparison, not a measured2x LCD speedup; the panel still consumes about16
clocks per word. Bounded line prefetch can reduce read-command/arbitration
frequency and help keep the LCD FIFO supplied.

The earlier140–180-bit estimate was for a one-word reader. Optional burst
staging adds128 payload bits for a full block plus credit/beat/owner controls;
alternatively reserve four slots in the existing LCD FIFO and consume streamed
words there, avoiding a duplicate payload bank. The latter needs rigorous CPU
command ordering, queue-credit reservation and accepted-burst drain on stop.
No extra SDRAM array, mirrored memory or second physical data bus is required.
Do not include burst-prefetch state for free in the earlier one-word budget.
