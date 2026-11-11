# IRQ, timer and keypad flow corrections

The hardware report concerned integration build `8ff8b11`, before the
`6b7be5a` DMA/LCD/MMC checkpoint. A read-only donor comparison reproduced
incomplete IRQ status, masked FIQ selection and boot-specific timer behaviour
in both revisions. These corrections use original NEM-4 instructions to qualify
the applicable behaviour; QD firmware addresses and timer frequency are not
treated as NEM-4 specifications.

## Interrupt controller and routing

Raw IRQ status now exposes every routed source in all three banks. Current
IRQ and FIQ each select the lowest **enabled** pending source, numbered1..32
within the bank. A pending masked source remains visible in raw status but
cannot win current selection. Both paths use the existing balanced selector;
no CPU bus stage or interrupt latency was added.

Stock kernel helpers `50324698/503246a4` read raw IRQ status at
`58120110 + bank offset`; `503246b0..50324708` tests selected source bits.
The old DMA-only readback was therefore a firmware-visible inconsistency.
Original name tables `50322fe8` and `503236c0` identify FiqTimer0..5 and
IrqTimer0..5. The six timer levels now feed both independently enabled planes.
IRQ1 also retains the UEM producer. DMA6..13, MMC21/23/24, shared NOS/keypad25
and the existing SIMIF route remain distinct from timer acknowledgement.

Timer reload programming no longer masks IRQ0. The original boot ISR stops
the timer and explicitly masks its source. ICU masking no longer clears timer1;
its original ISR acknowledges `0c120a28`. The legacy UEM/DMA clear output
remains a separately documented staged-model shortcut, rather than authority
over the corrected timer producers.

## Programmable timers and keypad pins

[General timers](general-timers.md) records the six parallel counters, original
boot/tick/high-resolution/medint routines and exact26 MHz/64 Hz evidence.
Completion status is separate from pending IRQ after reprogramming. Repeated
original synchronous delays exposed stale completion; new count programming
now discards it while preserving pending IRQ until explicit ACK. Assigning the
completion reset to `+10` is a transaction-level inference from the original
programming sequence. The physical role of `+0c` remains unidentified.

[Live controls](live-controls.md#2026-11-11-nem-4-configuration-and-pin-edge-interrupt-flow)
records NEM-4 GPIO data, direction, per-pin enable and edge semantics. A press
on a floating or interrupt-disabled contact no longer invents a keypad IRQ.
Driver scan/configuration writes and shared W1C acknowledgements retain the
original public key numbering and independent NOS state. GENIO direction
writes now reach the keypad even when GPIO loopback owns the transaction.

The UEM-routed GENIO1 level is an explicit stable signal from the loopback
module. Pin-edge detection no longer depends on whichever address the CPU is
reading. GPIO30 retains its separate data/direction path. Unproved port-D
interrupt generation and the separate GPIO23Low callback are not invented.

## Performance and verification boundary

Timers use one shared enable and six parallel decrementers. Read selection is
parallel; keypad edges are registered independently of CPU transactions. The
existing registered peripheral response boundary and fast LCD path are retained.
The selected hardware PLL remains78 MHz. Divisor3 at78 MHz and4 at104 MHz
preserve the original26 MHz timer rate; this does not certify104 MHz FPGA fit.

Local checks pass:

- IRQ and FIQ: all96 sources and1,584 priority pairs in each plane, raw
  readback, independent masks and masked lower-priority overlaps.
- Timers:46 public-register cases at divisors1/3/4;19 coupled ICU ownership
  cases; exact64 Hz periods at78/104 MHz; seven original-instruction phases
  at both rates with zero/three memory waits, including repeated delays.
- Keypad: host, board and protocol fixtures; unmodified original GPIO/scan/ACK
  routines at78/104 MHz with zero/three waits. The new pin-configuration test
  rejects the prior logical-press model.
- Combined board: shared NOS/keypad acknowledgements, GPIO loopback, registered
  responses, exhaustive regional ownership, retained-address inventory and clock
  selection. The104 MHz timer-profile ARM board fixture passes IRQ/FIQ, key
  injection, local DMA, queued LCD, fault reporting and diagnostic checks.

Several old fixtures assumed the previous boot script, zero-wait sparse
registers or a removed RAM hierarchy. Those assumptions were corrected; failing
old-model comparisons were not silently accepted. The registered-response
ownership tests force the named periodic boundary signal, rather than private
timer implementation registers.

Source/test hashes and logs are recorded in
[flow evidence](evidence/irq-timer-keypad-flow-2026-11-11.json),
[timer evidence](evidence/general-timers-2026-11-11.json), and the isolated
scratch directories named there. No old simulation/checkpoint was resumed or
modified. New timer semantics require a fresh boot lineage.

## Bad pointer remains a separate diagnosis

[Startup investigation](symbian-startup.md) and
[pointer evidence](evidence/bad-pointer-2026-11-11.json) resolve the recorded
fault to `RArrayBase::Count()` and validate a simulation-only caller/register/
memory-history observer using original instructions. The recorded value can
arise from `e59ff028 + 1c`; that induced fixture is not the hardware caller.
Actual caller provenance, complete UI wake and the selected production DDR
chain remain unverified. No synthesized tracing state or CPU execution change
is included in this correction.
