# Original NEM-4 timer instructions

Run `sh tests/phone/timer_original/run.sh /path/to/original/nem4-rom.dmp`.
The extractor rejects any ROM other than SHA-256
`26ca1dd937e299fd4ec3ad65a25d395743ae2149311c3d753cbeb5437673dbc5`.
Private ROM words and generated outputs stay under the ignored
`scratch/ngage2-integration/timer-flow-2026-11-11/original/` directory.
The existing `jotego/simulator:arm64` image is used, without network access.

The ZAP CPU executes unchanged original instructions for:

- bootstrap initialization at `00003200`, including its CPSR operation;
- timer0 initialization helpers and the complete tick ISR at `503225b0`;
- the high-resolution timer's original initialization helper sequence,
  complete start/reprogram routine at `50322b10` and ISR at `50322ac0`;
- stop and live count read helpers;
- the complete synchronous timer2 delay at `50323f4c`, twice consecutively;
- medint's original reload/count import thunks and acknowledge helper.

There are no instruction substitutions. The fixture supplies bounded kernel
RAM, a registered tick callback, tick count ten (past its first-tick queue
insertion), and the high-resolution ISR's already-queued DFC state. The outer
scheduler/object registration, original flash pump and CPU IRQ/FIQ entry are
outside this fixture. Handlers are called directly; connected IRQ/FIQ delivery
is covered separately by board tests. No firmware patch or real-phone timing
verification is implied.

The two builds select 26 MHz timer enables at system clocks 78 and 104 MHz
(divisors three and four). Each runs with zero and three memory wait clocks.
