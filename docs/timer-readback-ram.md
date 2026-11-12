# Timer upper-word RAM conversion — 2026-11-12

## Implementation

Keep six counters, reload values, two control mode bits, one status bit,
run state and pending IRQ state in live registers. Move the remaining30 control
and31 status bits per timer into the existing shared timer/ICU M10K. Arbitrary
software-written upper bits still read back exactly; this does not remove
register behavior or reduce timer/channel counts.

Production `ngage_upp_peripherals` expands its existing bank from32x32 to64x32:
rows0..23 remain timer spare words,24..29 ICU configuration,32..43 timer
control/status shadows. Explicit address concatenation avoids a row-address
adder. One64x32 simple dual-port store still fits in one M10K. Standalone timer
fixtures implement the equivalent private bank; production disables that bank.

Source state removes366 register bits and adds12 validity bits plus one sampled
address bit: approximately353 net FF bits. This is **not a measured ALM saving**.
The RAM data mux, validity logic, routing and packing also matter. Actual
M10K count and78/104 MHz timing need a routed Quartus report. No PLL, SDC,
diagnostics, NOS, LCD architecture or DMA ownership changed.

## Ordering and cost

Control/status reads now require one synchronous RAM sample, just like existing
spare/configuration reads. Count/reload reads and all writes retain their
admission timing; counter updates and IRQ production do not wait for RAM.
Responses merge the sampled upper word with current live low bits.

Count programming and timer expiry invalidate status upper bits. Expiry wins
over a coincident status write, while stop/count writes cancel the old expiry,
matching the frozen pre-conversion model. All six clears occur independently
on an edge, without competing for the RAM write port. Current validity also
masks an already sampled word, preventing stale upper bits if a held read
straddles expiry. Warm reset invalidates words rather than clearing RAM.

## Verification

The existing frozen FF reference remains unchanged. The expanded oracle covers
all control/status upper bits, bad-width accesses, warm resets, cancellation,
random accesses to all eight timer slots, reads held across expiry, and exact
expiry collisions with status ACK, count rewrite and stop. Standalone and
actual production shared-bank behavioral tests pass12,848 transactions with
4,286 RAM sample clocks, while live counters and IRQ/FIQ behavior agree.

Six-timer tests pass46 cases each at divisors1/3/4; ICU ownership passes19 cases;
78/104 MHz rate tests and board IRQ routing pass. Production ARM board,
LCD/DMA ownership/cancellation/reset and MMC bus/DMA tests pass. Top-level
structural elaboration and the173-file/9-QIP Quartus source check pass.

| Production measurement | Before | After |
| --- | ---: | ---: |
| LCD18,304-word frame interval |128,964|128,964|
| LCD normal complete fixture |149,748|149,748|
| LCD held complete fixture |149,826|149,826|
| MMC captured bus fixture |132,221|132,221|
| MMC production DMA fixture |669,329|669,329|

The original ARM timer fixture now explicitly honors `ready`; its previous
fixture ACK ignored this signal. The ROM instructions remain unchanged.
All seven original-code phases pass at both divisors with0/3 memory waits:

| Timer fixture profile | Before clocks | After clocks | After MMIO accesses |
| --- | ---: | ---: | ---: |
|78 MHz,0 waits|19,532|19,532|242|
|78 MHz,3 waits|26,023|26,023|206|
|104 MHz,0 waits|21,615|21,697|290|
|104 MHz,3 waits|28,207|28,207|243|

The104 MHz zero-wait case costs82 clocks (0.38%); other totals are unchanged.
Polling iteration counts change with the read sampling interval, so identical
total deadline-dominated fixture time does not imply every MMIO read is free.
These are bounded model measurements, not full-boot or real-phone results.

Intel and poison RAM tests pass for both standalone and shared banks. First
three combinations use the12,836-transaction version (upper words and held
expiry reads); shared poison also includes the final exact-write-collision cases
and passes12,848. Both behavioral profiles pass the final suite. See the
[evidence manifest](evidence/timer-readback-ram-2026-11-12.json) for exact
source hashes, profile counts and log results.

Local logs and pre-edit RTL snapshots:
`scratch/ngage2-integration/timer-upper-ram-20261112/`.
The other chat's frozen simulation and checkpoints were not accessed or changed.
No CI build was launched or monitored.

## Remaining candidates

The RF MLAB conversion is already implemented and physically fitted. Next is
DMA programming mirrors (768 raw src/dst/count bits), which requires preserving
the exact start-edge immutable snapshot under immediate reprogram/stop/reset.
Queue/worker RAM compaction follows; reducing RAM count alone does not establish
an ALM improvement. Keep eight DMA channels, two workers, fast LCD and diagnostics
until Symbian boots. Cache/TLB geometry remains a separate architectural task.
