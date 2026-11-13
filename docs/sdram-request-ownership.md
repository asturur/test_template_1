# SDRAM request ownership and cache-line storage

Post-fit follow-up, 2026-11-13: [build 43327385834](fpga-build-43327385834.md)
now supplies whole-core and hierarchy resource observations. It fits, but fails
78 MHz setup at two diagnostic snapshot RAM inputs; reported SDRAM capture paths
have positive margin. The earlier NOT_RUN labels below describe this change's
pre-fit checkpoint. The new fit combines multiple source changes and a different
seed, so it does not isolate the 36-bit payload removal's cost.

2026-11-12. Follow-up to the native two-READ/two-WRITE controller work.
Implemented on the existing branch after baseline tests, using isolated
`scratch/sdram-ownership-20261112/before/` and `candidate/` snapshots.
No CPU/cache RTL, clocks, bank geometry, SDRAM command schedule or pin boundaries
changed. No commit, push, CI, deployment or hardware operation was performed.

## Accepted change: share the held write payload

The outer `ngage_sdram_arbiter` already retains the accepted scalar request.
The adapter now uses its held 32-bit data and four byte enables directly,
removing the adapter's duplicate **36 declared state bits**. Cold scrub selects
constant zero data/all byte lanes. Address, operation identity, beat counters
and controller timing records retain their existing ownership.

The adapter exports `owner_ready`. Production gates new CPU/DMA arbiter grants
with it. It permits ordinary queuing behind a line or scrub, but blocks a new
payload owner while a logically canceled physical operation drains. The outer
arbiter's payload registers retain their contents across logical reset. Physical
reset/init still resets the adapter/controller normally. There is no additional
payload queue, full-line buffer or production old/new mode.

This guard is necessary: deliberately bypassing it makes the new test fail with
`outer SDRAM write payload changed before drain`. The invariant is also checked
by a simulation-only assertion, which adds no production state.

The original native implementation had already removed the DMA/LCD mux's
62-bit duplicate packet. This change removes another 36 bits from the adapter.
These are source-level state counts; fitted ALM/register savings and routed
78/104 MHz setup/hold remain **NOT_RUN**.

## Measurements and validation

Baseline tests were written and run before changing the candidate. Both use the
existing `jotego/simulator:arm64` image, no pull/network, unchanged AW22/two-bank
geometry, identical traffic, original Micron timings, and the same clock rates.

| Native-controller probe | Before sharing | After sharing |
| --- | ---: | ---: |
| Row-hit line, first / whole | 8 / 23 clocks | 8 / 23 clocks |
| Row-conflict line, first / whole | 12 / 27 | 12 / 27 |
| Refresh probe line, first / whole | 16 / 31 | 16 / 31 |
| Row-hit masked word write | 12 | 12 |
| Mixed CPU/LCD workload | 4119 | 4119 |

All 310 latency samples plus the mixed-total record match exactly at **each**
of 78 and 104 MHz. The earlier native-controller gains (29→23 line clocks,
21→12 word-write clocks) are preserved and receive no new attribution here.

The directed delayed-controller test covers all 16 masks, source payload changes
after admission, controller grant waits 0/3/7, and logical reset before/after
launch. All pass for both baseline and candidate. After a canceled write, the
new response takes two extra clocks in this fixture: at wait 7, 33→35 clocks
before launch and 24→26 after launch. This is reset-recovery admission delay;
the normal request measurements are unchanged.

Candidate validation passes:

- Micron four-state functional/mask/bank/row/SWP/reset tests.
- Full and production DDIO profiles at 78/104 MHz and four clock delays;
  the deliberately wrong capture edge still fails with Z data.
- Short reads and legacy/native concurrent-bank schedules at both rates.
- Full 16 MiB cold scrub; actual DMA/LCD mux and arbiter retention; bit-exact
  legacy/fast LCD comparison for 18,304 words.
- Cache line stream/stall/fallback/dirty-writeback/error/reset and owner tests.
- Top-level structural lint with HPS/PLL stubs, CPU diagnostic SDRAM-path
  elaboration, formatter check, and maintained ownership runner.
- Two real-controller HDL CPU/board runs of 5,000,000 cycles, one per rate:
  327791/327792 bus transactions, 12 instruction faults at the previously
  documented peripheral addresses, **zero data faults**, final PC `00006178`.
  These are bounded startup regressions, not full boot or gameplay results.

[Structured evidence](evidence/sdram-request-ownership-2026-11-12.json) records
source/input hashes, comparisons, profiles, logs and limitations. CPU baseline
snapshots from the earlier experiment remain immutable; the next CPU experiment
must explicitly capture this additional memory change rather than altering B0.

## Why the cache has a refill buffer

Directly filling cache RAM is possible. The current buffer is an implementation
choice that assembles a 32-byte line, preserves the replacement entry during the
transfer, and feeds the existing complete-line installation path.

The actual incoming SDRAM path is:

```text
16-bit SDRAM beats
    → cache transfer's 32-byte refill_line
    → cache bank's registered commit_data stage
    → eight 32-bit cache RAM banks + tag/valid commit
```

The SDRAM adapter has a 16-bit beat register, not another full-line buffer.
The cache also has a separate dirty-victim snapshot for writeback. The incoming
refill register, dirty-victim snapshot and cache commit register have distinct
roles; this change does not claim to remove those cache-side stages.

For each accepted SDRAM line, the adapter counts 16 halfwords. Each `line_valid`
pulse supplies one piece; `line_last` marks the sixteenth. The transfer engine
records the last piece and reports `done`/`error`. Its simulation assertion checks
that the final-beat marker agrees with the expected length. The refill
coordinator enters `INSTALL` only after completion without a reported error.
The bank accepts the full 256 bits when `refill_ready` permits replacement;
its registered commit writes data and tag/valid together on the following edge.
The CPU is kept out of the incomplete replacement by the existing refill owner.

**Protocol completion is not a data-integrity check.** Production currently ties
`line_error` low because these backends expose no physical error signal. There
is no added checksum or ECC. It trusts the controller's timing and beat count;
the Micron-model regressions verify the modeled protocol, not board signal
integrity or installed-chip geometry. Scalar fallback honors bus errors.

A future direct-fill experiment would reserve a destination, write incoming
pieces through the cache RAM port, keep the incomplete new line unavailable,
and publish its valid tag only after successful completion. It must preserve
dirty writeback, error/reset/maintenance ownership and RAM port scheduling.
That changes the cache installation boundary and needs separate baseline,
correctness, area and routed-timing measurements. No direct-fill or cache-buffer
reuse change was attempted in this controller cleanup.

## Reproduce

`sh tests/phone/sdram/run-native.sh` includes the new ownership test. To run only
that test inside the installed simulator image:

```sh
sh tests/phone/sdram/run-ownership.sh
```

The unchanged pre-sharing native snapshot and all comparison logs are preserved
under `scratch/sdram-ownership-20261112/`. The shared latency harness uses
`SDRAM_SHARED_PAYLOAD` only to connect the candidate's new admission signal;
the saved pre-native adapter remains supported by the legacy comparison build.
No old implementation selector is added to production RTL.
