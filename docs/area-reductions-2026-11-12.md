# Further area reductions — 2026-11-12

This pass follows the [timer upper-readback conversion](timer-readback-ram.md).
Actual PLL/constraints stay78 MHz, with104 MHz as the RTL design objective.
Keep diagnostics, semi-real NOS, all eight DMA channels, two production workers
and the fast LCD path. No FPGA build was launched or monitored; the other chat's
frozen simulation and permanent checkpoints were not accessed or changed.

## Changes

| Reduction | Declared state reduction | Additional intended M10Ks |
| --- | ---: | ---: |
| DMA source/destination/count mirrors |764 bits net|0|
| Boot-controller words in shared scratch RAM |374 bits net|0|
| Bounded DMA/NOS/CBUS/MDI/SDRAM state |185 bits at production parameters|0|
| **This pass** |**1,323 bits**|**0**|
| Previous timer upper words |353 bits net|0|
| **Combined source-state estimate** |**1,676 bits**|**0**|

These are declared register-bit differences, **not promised physical FF or ALM
savings**. Quartus may already prune some bits; muxes, validity, CDC-free launch
control and LAB packing also matter. Measure a routed fit before accepting an
ALM/timing conclusion. Source graph and structural elaboration are not fitting.

### DMA live and queued values share four existing banks

The first three queued-descriptor M10Ks grow from8x32 to16x32. Rows0..7 hold
live source, destination and raw count; rows8..15 retain the immutable start
snapshot. The fourth payload bank is still8x32. The existing raw MMIO readback
bank remains unchanged, including arbitrary upper/mode words.

A start request selects the three live rows in parallel, waits one sampling
clock, then commits its immutable descriptor. Four handshake bits replace768
mirror FFs. Existing per-word validity masks retained physical values to zero
after warm reset. Mode/width/request inputs remain live, sampled on that same
accepted edge. Starts/restarts preserve all32 raw count bits and the35-bit
byte budget. Ordinary programming writes and stops remain immediate.

Live/queued rows use separate addresses, avoiding dependence on mixed-port
read-during-write behavior. A pending restart suppresses old descriptor dispatch
for that channel while sampling. Withdrawal leaves the old queued work intact;
no cancellation takes effect before commit. The shared read port pauses new
queue fetch while sampling a start, but does not pause an executing transfer.
An already sampled descriptor for another channel may dispatch normally.
No new per-beat state or readiness stage was added.

DMA bus ownership/round-robin indices are now sized to `ENGINES`, including
one-worker configurations. Integer loop variables remain elaboration/control
variables rather than being blindly replaced.

### Boot-controller latches share scratch RAM

The existing64x32 byte-enable scratch M10K had45 used rows. Eleven boot words
now occupy rows45..55. Remove352 FF payload bits; reduce sampled read address
from32 bits to6; add4 byte flags for the special readable-zero reset word:
net374 declared bits. Writes remain immediate; fixed boot reads gain one RAM
sampling clock, while executable scratch keeps its current latency.

Fault claims/missing-byte checks remain parallel constant-address reductions.
The RAM row encoder is a balanced reduction of one-hot constant rows; no
priority-encoded validity mux was reintroduced onto the fault path. Preserve
unaligned word aliases and the differing read-lane contract: fixed words mask
by selected bytes, executable scratch exposes its valid stored bytes.

`0x08000040` remains readable as zero after warm reset, including after an
old full-word write. Separate4-bit payload validity hides retained RAM data
while its permission validity resets to all-readable. A subsequent partial
write exposes only the newly stored bytes. Other words retain per-byte
unwritten-read faults. No reset payload sweep is required.

### Bound state to configured ranges

Use at least one bit for divisor1/single-worker cases:

- NOS slow/fast dividers use `clog2(divisor)`:21/12 bits for the production
  timebase, saving31 declared bits. Do not alter the timebase values.
- UEM RTC second divider, alarm countdown and alarm divider use27/7/16 bits
  with the existing default parameters, saving46 bits. Countdown width includes
  its initial rounded-up alarm count. No RTC/alarm phase or event priority change.
- MDI announcement elapsed counter uses5 bits for20 ticks, saving27 bits.
- SDRAM refresh counter uses13 bits at the selected5100-clock period,
  saving19 bits. Refresh rate, scheduling, scrub and phone-reset discard stay
  unchanged.
- Two production DMA worker indices use one bit each, saving62 declared bits.

## Verification and measured cost

DMA tests cover1/2/3 workers, all8 channels, arbitrary397 raw readback checks,
queued snapshots, paced/blocked peers, ownership, error/IRQ ACK, stop/restart,
lock and reset. Added tests withdraw a sampled start, change its channel, and
perform gapless source/destination/count writes immediately before start and
rewrites immediately afterward. Exact snapshot contents and memory results
are checked. Intel and poison RAM models pass all six worker/model profiles,
including these cases, the descriptor-fetch fence and same-row collision checks.

The direct test bus drivers now honor `ready` for start acceptance. The
production transport fixture uses the dedicated DMA register ready output.
The original DMA instruction fixture previously ignored DMA `ready`; it now
honors it, with the original guest instructions unchanged. Removed-mirror
internal assertions inspect the correctly sampled RAM values at accepted start.
The one-cycle restart pre-sample is issued before the final response so the
existing terminal-cancellation test still targets its intended commit edge.

| Measurement | Before this pass | After |
| --- | ---: | ---: |
| LCD18,304-word frame interval, including launch |128,964|128,965|
| Full LCD/DMA CPU fixture, normal |149,748|149,765|
| Full LCD/DMA CPU fixture, held |149,826|149,844|
| MMC captured bus fixture |132,221|132,221|
| MMC production DMA98-case suite |669,329|669,385|

The single frame's extra clock is launch sampling (about0.0008%). The complete
LCD and MMC suites contain multiple starts/restarts; they do not add56 clocks
per MMC transfer or any cycle to each byte/beat. Both transport/reset/queued-tail
and CPU Hold/reset tests pass. Concurrency tests with1/2/3 workers pass stalled,
MMC and LCD modes;3-worker LCD-only interval146,433 and MMC256-byte mode1,544
clocks are model measurements, not measured hardware throughput.

Original NEM-4 setup/start instructions pass four cases with no substitutions:
11,130/16,814 clocks at0/3 waits. Original ISR fixture passes three ISR calls,
two callbacks and one rearm with ACK-before-restart:11,067/16,449 clocks.
This verifies bounded driver/ISR behavior, not Symbian boot.

Boot tests and the12,000-cycle independent expected-value conformance pass
behavioral, Intel and poison RAM, including byte masks, holes, unaligned aliases,
uncommitted requests and reset. Added directed checks cover retained data in
the special readable-zero row and partial writes after reset.

NOS IRQ/wrap/compare,20-tick MDI, CBUS RTC/alarm/ADC and the two existing C++
alarm/phase reference profiles pass. Timer rates pass78/104 MHz. Actual SDRAM
controller/Micron tests pass baseline/short78/short104/delayed-pin modes,
concurrent banks and full16 MiB scrub:8,388,608 halfwords and6,784 scheduled
refresh pulses. Production ARM board passes after all changes, and top-level
structural elaboration/source graph173 files/9 QIPs pass. Formatting and diff
whitespace checks pass. [Evidence](evidence/area-reductions-2026-11-12.json).

## Remaining area work

The low-risk passive-state candidates identified for this pass are implemented.
Further queue/worker serial packing might save M10Ks, but introduces staging
logic and launch latency; it does not establish an ALM win. Our four DMA banks
now also store live parameters, so that experiment must include both uses.

Cache/TLB associativity, whole-CPU replacement and dirty-cache optimizations
remain separate architectural work with greater correctness/performance risk.
Do not undertake them solely to remove more declared bits before observing
actual fit results. Diagnostic rendering is the next removal candidate, subject
to a working replacement: [read-only JTAG exploration](jtag-diagnostics-plan.md).
Keep the screen until that replacement is demonstrated on hardware.

Reproducers, pre-edit source snapshots, private original-code slices and logs
are in `scratch/ngage2-integration/{dma-live-ram,boot-shared-ram,bounded-state}-20261112/`.
No long boot was launched, resumed, inspected or modified.
