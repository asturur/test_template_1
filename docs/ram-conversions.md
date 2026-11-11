# RAM conversions for fit margin (2026-11-11)

## What changed

The synthesis target remains78 MHz, with RTL structured toward104 MHz. No PLL,
clock constraint, cache capacity, CPU feature, DMA worker or guest channel was
changed. No other-chat simulation or saved checkpoint was touched.

| Storage | Previous logic state | Replacement | Visible timing |
| --- | --- | --- | --- |
| Eight immutable queued DMA descriptors |111 payload bits/channel,888 FF bits in total | Four8x32 simple-dual M10Ks;17 padding bits/row are constant. The fast-classification bits remain live for scheduling. | One synchronous fetch clock before engine launch; no extra transfer-beat stage. |
| Six timers' four spare words each |24x32 =768 FF bits | Rows0..23 of shared32x32 M10K plus24 reset-valid flags | These passive reads wait one RAM sample; writes, live counters and IRQ/ACK do not. |
| ICU configuration words |Six32-bit words,192 FF bits | Rows24..29 of the same M10K plus6 reset-valid flags | Only cfg0/cfg1 reads wait one RAM sample. Mask/current/IRQ/FIQ remain immediate. |

Intended cost: **five additional M10Ks**,497->502/553 if the prior allocation is
otherwise unchanged. Source-level state arithmetic removes1,848 FF bits and
adds42 small validity/read/dispatch state bits in the two-worker production
profile: approximately**1,806 fewer FF state bits**, plus the associated wide
selection/reset logic. This is not a measured ALM saving or successful fit;
physical synthesis/packing can change unrelated blocks.

### Shared timer/ICU bank

Production UPP owns the shared bank; private controller banks are disabled at
elaboration. Thirty words use960 bits of one10,240-bit M10K. UPP accepts one
MMIO request at a time, so sharing needs no arbitration and adds no latency
beyond the existing synchronous sample. Standalone controller fixtures retain
the private-bank option. Live counters and interrupt state remain independent.

The production shared-bank oracle passes the same12,788 transactions with
4,659 sample clocks. Board IRQ routing and production ARM LCD normal/held/reset
fixtures pass; the frame remains130,685 clocks. Intel/poison checks also pass, with unrelated large RAMs modeled behaviorally.
Production elaboration confirms exactly one passive bank and no private banks.

### Why this differs from deleting registers

Guest software still gets every32-bit value it wrote. Warm reset clears small
valid flags instead of clearing RAM words: invalid words read zero, even when
old physical RAM contents remain. Active timer count/reload/status and ICU IRQ
masks stay in registers because they change or must be queried concurrently.
The ICU's32-bit diagnostic global OR/AND latch also stays live; moving that
read/modify/write state is not necessary for this passive-storage conversion.

DMA captures the complete descriptor on the original start-write edge. Later
programming-latch writes cannot change queued work. The queue RAM is not a
late reread of mutable programming registers. A selected channel/engine waits
one fetch clock before dispatch; pending remains asserted throughout. Stop,
restart or reset invalidates the old sampled descriptor before consumption,
including a same-row RAM read/write collision. No background RAM reset sweep,
new execution worker or reduced queue capacity is introduced.

The existing raw DMA programming RAM and768 bits of live src/dst/count mirrors
remain. Those mirrors allow parallel construction of an exact start snapshot;
a further conversion would need its own ordering contract. This change targets
the queued copy, not all possible state in the controller.

## Validation

- DMA one/two/three-worker suites pass with ordinary simulation and Intel
  primitives. Intel and explicitly X-poisoned collisions also pass the new
  stop/restart-on-descriptor-fetch-edge fixture; no work is duplicated or
  published from stale collision data. All397 raw readbacks still pass.
- Independent old timer/ICU models compare12,788 accepted transactions across
  all passive words, random full-width values, bad widths, warm resets,
  canceled requests and live periodic timers/interrupts. PASS for ordinary RAM,
  Intel primitives and poisoned collisions;4,659 total inserted read clocks
  in this mixed workload. Live timer/IRQ behavior is compared every clock.
- Existing46 timer cases at dividers1/3/4,19 ICU ownership cases, all96 IRQ/FIQ
  sources/1,584 priority pairs per plane and78/104 MHz timebase checks pass.
- Original NEM-4 timer routines pass seven phases at dividers3/4 and waits0/3;
  cycle/MMIO counts match previous results. Original DMA helpers remain
 11,130/16,814 clocks and original ISR11,067/16,449, with no instruction patch.
- Production ARM LCD normal/CPU-Hold tests pass at152,454/152,534 clocks.
  Full-frame interval is unchanged at**130,685 clocks**,18,304 words.
  Stop/restart, queued tail, transport reset and CPU-Hold logical reset pass.
  The small complete-fixture timing movement is handshake alignment, not a
  claim that every workload became faster.
- MMC bus30 cases stay132,221 clocks. The98-phase DMA suite passes all native
  lengths, channels, immutable selectors, blocked peers, stop/restart/reset,
  mask/ACK and error cases in667,186 clocks. A matched old-queue run with the
  same current fixture takes667,085: **+101 clocks (about0.015%)** overall.
- Formatter and selected production top elaboration pass. Quartus source graph
  and actual allocation/area/timing must still be checked before claiming fit.

### Accepted-offer test correction

The new dispatch clock exposed a test assumption in MMC cancellation: waiting
for combinational mreq did not prove the router accepted the request. A probe
showed route state IDLE before stop, so canceling that offer correctly removed
it. The ownership tests now wait for the accepting edge and assert RAM state
before testing drain/reset. This strengthens the advertised ownership boundary;
it does not relax accepted-transaction protection. The matched performance
comparison uses that same strengthened fixture in both runs.

## Locations and next result

Maintained tests: `tests/phone/register_ram/`, `tests/phone/dma_channels/`,
`tests/phone/mmc_production/` and original-instruction fixtures. Generated
outputs are under `build/sim/unit-register-ram*`, `unit-dma-channels*`,
`unit-mmc-production`, `unit-mmc-queue-before` and `unit-dma-handover`.
Scratch baselines/scripts are in
`scratch/ngage2-integration/ram-conversions-2026-11-11/`.

No long firmware boot was started. Hardware fit and timing remain unverified;
launch the next normal78 MHz build, retain its full map/fitter reports and
compare actual required LABs, placed/required ALMs, RAMs and setup/hold. Do not
monitor CI. See [evidence](evidence/ram-conversions-2026-11-11.json).
