## Passive readback RAM follow-up — 2026-11-11

Four spare words per timer now use one shared M10K; full values and warm-reset
zeroes are preserved with validity flags. Passive reads wait one RAM sample;
active count/control/reload/status and interrupt timing stay on their previous
path. Old-model randomized/vendor/collision tests and original routines pass.
See [RAM conversions](ram-conversions.md).

# UPP general timers

## Original NEM-4 evidence

The six 32-byte units at `0c120a00 + 20*n` now have programmable counters.
The previous timer0 boot-value whitelist, stored-only unit1 count and fixed
128-clock unit60 delay were staged software-model assumptions. They cannot
serve as an oracle for arbitrary original driver programming.

The private unmodified NEM-4 ROM has SHA-256
`26ca1dd937e299fd4ec3ad65a25d395743ae2149311c3d753cbeb5437673dbc5`.
Its kernel helpers at `50324948..50324a44` access:

| Offset | Original helper | Modeled meaning |
| --- | --- | --- |
| `+04` | `50324948/50324958` | Read/write control; zero stops, bit0 one-shot, bit1 periodic |
| `+08` | `50324a20/50324a38` | Write acknowledge/status; read status |
| `+0c` | `503249a8` | Unidentified configuration; storage only |
| `+10` | `503249e8/503249f4` | Read live count / write count, rearming a configured one-shot |
| `+18` | `503249c0/503249d0` | Read/write periodic reload |

Concrete original paths are retained in the ignored experiment's
`nem4-disassembly.txt`, `nem4-paths.txt` and `medint-path.txt`:

- Bootstrap `00003200` writes control2, reload/count18,200,000, ACK0 and IRQ0
  enable. Its ISR at `000030a8` clears reload/count, writes ACK1, stops the
  timer and explicitly masks IRQ0. Reload programming does not mask the ICU.
- Kernel `503226dc..50322758` writes control2/reload406,250, then live
  count406,250 and ACK0. The complete tick ISR `503225b0` writes ACK0.
- High-resolution initialization at `50322a64` uses timer1/control1,
  count`7fffffff`, ACK0. `50322b10` writes the requested count and updates its
  software queued flag. ISR `50322ac0` writes ACK1; stop `50322aa0` writes
  control0. Masking IRQ1 therefore cannot substitute for the producer ACK.
- Kernel delay `50323f4c` starts timer2/control1, writes configuration`+0c=0`
  and its count, then polls `+08` for nonzero.
- Medint `503872e4..50387304` sets timer3 reload390, clears its count and
  stops it. Import `50387e18` resolves to kernel reload helper `503249d0`.
  Arm `503865b0..503865d0` writes control2, count390 and ACK0. Its FIQ pump
  `503851d4` writes timer3 ACK0; the programmed periodic reload supplies the
  next interval. No fixed delay or implicit ACK rearm is needed.

NEM-4 time arithmetic `50322b74..50322b84` multiplies by
`5 * 5 * 65 * 16 = 26,000`; kernel reload406,250 at26 MHz yields64 Hz.
Together with the retained phone reference-clock evidence, this supports the
selected26 MHz general-timer enable. QD's separate104/3 MHz timer rate is not
copied. See [phone clocks](phone-clocks.md) for physical verification limits.

## Implemented contract and limits

Each of the six counters decrements independently on one shared clock enable.
The system uses divider3 at78 MHz or4 at104 MHz. Bus reads and writes remain
available on every system clock, without additional response latency. The read
path uses one-hot parallel selection; no counter arithmetic is shared serially.

Control0 stops and retains count. Nonzero control bits start a stopped timer;
a count write rearms a configured timer and replaces its deadline. Expiry
occurs at the enable taking count1 to0. One-shot stops at0; periodic reloads
from`+18`. A zero count wraps through32 bits. Pending survives stop, count
programming and ICU masking until the timer's own`+08` ACK. All six producer
bits are exported independently; UPP owns IRQ/FIQ routing and shared UEM IRQ1.
The legacy timer0-rearm output is tied low and has no ICU authority.

Status stores the last`+08` write and becomes1 on expiry. A new`+10` count
resets completion status to0, preserving an older pending IRQ until explicit
`+08` ACK. This is a transaction-level inference from the original timer2
sequence: control1, configuration`+0c=0`, newcount, pollstatus; it contains no
ACK. Executing the complete original delay twice reproduced the second call
returning early with192 counts remaining from its new256-count load. The
completion reset makes both calls wait for their own expiry. The instructions
establish the required new-deadline behavior but do not identify which
physical write resets a silicon latch; the model assigns it to the known
count-programming transaction, without inventing a function for`+0c`.

This also preserves the original boot's ACK1/poll. Other unidentified words
remain storage. Their physical function, including the role of`+0c`, needs
further evidence. Control high-bit meanings, zero-load duration and sub-clock ordering
remain unmeasured on a phone. The explicit digital policy makes count writes
and stop cancel an old deadline; a new expiry wins a simultaneous ACK. The
shared26 MHz phase is continuous rather than restarted by MMIO writes.

`periodic_active` reports an actually running timer0 in periodic mode with a
nonzero reload. Consequently it is also true during the real bootstrap's
periodic18.2M-count wait. Its staged UEM/MDI consumers must not treat it as proof
of a specific firmware phase. No firmware-state or programmed-value whitelist
remains in the timer.

## Verification

[`tests/phone/timers`](../tests/phone/timers/tb.sv) checks46 public-register cases
at divisors1/3/4: arbitrary loads, live count, stop, one-shot reprogram, six
parallel producers, programmed390-count repeat, ACK ownership, zero rollover,
same-edge expiry/ACK, distinct completion/IRQ ownership and access admission.
Totals are1,537/4,341/5,744 clocks.
[`timer_conformance`](../tests/phone/timer_conformance/tb.v) now uses19 direct
ICU/producer cases in178 clocks, replacing the old staged C++ oracle. It
covers masked overlaps, later unmask, explicit ACK, shared UEM ownership and
masked timer3 versus enabled timer4 FIQ priority.

[`timer_rates`](../tests/phone/timer_rates/tb.sv) programs the original406,250
count/reload through the public bus and observes two exact64 Hz periods at
78/104 MHz. ACK is accepted between counter enables. The separate NOS64 Hz
fixture remains an explicitly selected NOS hypothesis, not a new timer fact.

[`timer_original`](../tests/phone/timer_original/README.md) executes original
bootstrap/tick/high-resolution/repeated-delay/medint timer code on ZAP, with no
instruction substitutions. Its bounded state/callback and excluded scheduler,
flash-pump and CPU exception-entry scope are documented there. Passing these
fixtures does not verify a phone, a complete boot or an FPGA timing fit.

| System clock | Memory waits | Original fixture clocks | MMIO transactions |
| --- | --- | --- | --- |
| 78 MHz | 0 | 19,532 | 247 |
| 78 MHz | 3 | 26,023 | 206 |
| 104 MHz | 0 | 21,615 | 294 |
| 104 MHz | 3 | 28,207 | 243 |

All four execute seven phases, including two consecutive unchanged original
timer2 delay calls. Final timer SHA-256 is
`d7509e1efbcf3c60fb2ecfd6e6e81bdfb33a64ff04a021b566256c1d7aaff493`.
The [evidence manifest](evidence/general-timers-2026-11-11.json) records69
source hashes, exact input slices, pinned image, logs and the reproduced
pre-fix repeated-delay failure. The two original fixture executables remain;
reproducible intermediate build objects were removed to keep outputs small.

All outputs and source/input identities are retained under
`scratch/ngage2-integration/timer-flow-2026-11-11/`. No existing long-run or
billion-cycle checkpoint is resumed, overwritten or removed by these tests.

## Upper-word storage reduction — 2026-11-12

Control[31:2] and status[31:1] now share the existing timer/ICU M10K, with
one-clock sampling on these reads. Counter/reload and live mode/status/IRQ
behavior stay in registers; no frequency change. See
[timer readback RAM](timer-readback-ram.md) for expiry ordering, oracle coverage,
source-state accounting and production performance measurements. The earlier
fixture totals above describe the pre-conversion baseline.
