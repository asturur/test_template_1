# Resident-store pipeline qualification — 16 November 2026

This Stop 3A work uses the original `codex/ngage2-integration` checkout at
`9c948da8da413a882e0fe8e559c380ea0cadabf4`. The Step 2 sources, runner and evidence
remain unchanged. The corrected candidate is a separate explicit overlay in
`tests/cpu/cache_resident_qualification/rtl/`. No production source imports it.
Production RTL, project settings, actual 78MHz PLL, CI, Git history, phone and
other simulations were left alone. The DDR3 experiment is independent.

## Interface contract traced from production

Sources: `rtl/arm/zap_dcache.sv`, `rtl/arm920/cache_adapter.sv`,
`rtl/arm/zap_cp15_cb.sv`, and the outer reset drain in `rtl/ngage_mister.v`.

| Boundary | Rising-edge contract and reachable combinations |
| --- | --- |
| Cache request | Accept only on req_valid && req_ready. Hold the complete packet while ready is low. Permissions, translation, alignment and SWP exclusion remain upstream. The production adapter permits one launched demand; the cache-port prototype separately exercises multiple certified store owners. |
| Return | No response-ready input. Each response_valid cycle returns exactly one accepted demand. Store response must coincide with its actual data and dirty write, except reset cancels the owner without reply. The adapter clears launched on response. Consecutive response cycles mean consecutive owners, not a held pulse. |
| Probe | Address-only tokens do not accept demands or issue bus traffic. Synchronous data belongs to a registered physical slot and line. Same-slot port collisions cannot feed a consumer. A noncolliding B read can run alongside an A write. |
| Fast read | Adapter fast_hit can acknowledge a permitted ordinary read without req_valid/req_ready. It checks rd, !wr, SWP, attributes, current address and fault/translation/maintenance state. Cache FSM IDLE alone cannot make it safe while private store owners exist. |
| Maintenance | CP15 clean/invalidate outputs remain asserted in their state until done. Adapter presents maint_valid when !launched && !active_maint and no pending lock; cache accepts on maint_valid && maint_ready. No invented pulse handshake is needed. CP15 clean+invalidate performs clean, then invalidate; the direct cache's combined flags are also tested. |
| Lock | CP15 holds lock_write until lock_done; adapter can also capture a one-cycle pulse and its six-bit payload while launched. apply_lock waits for !launched && !active_maint. Production sequences therefore reach the cache after the launched store response. The direct cache input has no ready: its pulses must be retained if offered while multiple test-only owners live. |
| Direct invalidate | Adapter ties invalidate_all low. Production invalidate uses maintenance. Exposed direct invalidation is tested separately, including pulses during live stores. Destructive invalidate may discard dirty data after older stores have committed; it is not a clean. |
| Reset | Reset immediately suppresses owned store/fast responses and data writes, then clears valid owners/certificates. Pre-reset physical commits remain counted; accepted but uncommitted stores are canceled without reply. Cache reset invalidates dirty contents, so restart loads use backing memory. The outer core reset remains asserted until accepted physical transport drains. A raw cache reset is not a new transaction-ID/drain protocol. |
| Return from reset | The faithful line peer drains its previously accepted tail while core reset is held. Restart is released only after peer idle; old beats cannot become a new line/response. Scalar tests retain existing adapter/bridge assumptions. No upstream reset bypass or admission widening is introduced. |

CP15 maintenance/lock are serialized against CPU demand. Direct pulse overlap
with live multi-owner stores is an exposed-interface stress case, separately
labeled from production reachability. The direct command latches retain one
pending invalidate and one pending lock payload; repeated different lock
commands while one is pending are outside the serialized caller contract.

## Reproduced failures and isolated corrections

**Failure 1:** a direct invalidate on the first physical commit edge cancels
bank writes, but Step 2's pipe_commit still returns a response. The independent
checker rejects a reply without a physical commit. The corrected overlay stops
younger admission immediately, captures pulsed invalidate/lock commands, and
applies their physical effects only after both owner stages and the serialized
controller have drained. Lock payload is retained. Maintenance retains its
existing ready/done protocol and waits for older owners. Reset cancels pending
controls as well as pipeline valids.

**Failure 2:** an already primed probe can advertise the old word immediately
after a younger store is accepted while the FSM stays IDLE. Ordinary readiness
is insufficient because adapter fast_hit bypasses it. The corrected cache
suppresses fast_lookup_valid for all live private store owners. Noncolliding
probe reads remain enabled, preserving A/B overlap; same-slot commit collisions
still invalidate/retry the synchronous token. DATA_PROBE=0 lookahead/stream
transients are canceled through the store drain too. No dirty forwarding rule,
geometry or RAM port is changed by these fixes.

`first_failure.v` and the archived Step 2 overlay reproduce failure 1. The
qualification fixture's `+probe_only` case with `--old` reproduces failure 2.
Each failed run preserves its generated testbench, manifest and raw edge log.
The targeted negative controls use uncorrected candidate sources; the five
stream tests also retain their deliberately corrupted expected-byte control.

## Replay

From `/Users/andreabogazzi/develop/NGage_MiSTer`, choose unused output paths:

```sh
# Expected failures, before correction:
python3 tests/cpu/cache_resident_qualification/run.py build/sim/qual-invalidate-bad --old --fixture first_failure
python3 tests/cpu/cache_resident_qualification/run.py build/sim/qual-fast-bad --old --arg +probe_only
# Corrected complete boundary suite and reused actual-adapter/bank regressions:
python3 tests/cpu/cache_resident_qualification/run.py build/sim/qual-full
python3 tests/cpu/cache_resident_qualification/run.py build/sim/qual-probe --fixture cache_probe
python3 tests/cpu/cache_resident_qualification/run.py build/sim/qual-admit --fixture cache_admit_probe
python3 tests/cpu/cache_resident_qualification/run.py build/sim/qual-lock --fixture adapter_lock
python3 tests/cpu/cache_resident_qualification/run.py build/sim/qual-refill --fixture cache_refill
python3 tests/cpu/cache_resident_qualification/run.py build/sim/qual-maint --fixture cache_maintenance
# Same current runner for the fresh baseline and both candidate configurations:
python3 tests/cpu/cache_resident_qualification/stream.py build/sim/qual-control --baseline
python3 tests/cpu/cache_resident_qualification/stream.py build/sim/qual-stream
python3 tests/cpu/cache_resident_qualification/stream.py build/sim/qual-stream-integrated --data-probe 1 --line-refill 1
```

All use the existing `jotego/simulator:arm64` image with `--pull=never --network
none`. Every output's source.json lists the files actually compiled, included
helpers, image identity, SHA256s and parameters/fixture selection. Source hashes
are checked again after execution. The stream runner preserves independent
Step 1 byte/slot/dirty checks, deterministic repeats and wrong-byte rejection.
The qualification line peer sends four 64-bit beats with two empty cycles
between beats, can reject to scalar fallback, and drains accepted old beats
during reset. Candidate RAM reads are poisoned on mixed-port collision.

## Qualification limits and physical follow-up

The estimate changes from Step 2's 94 additional FFs to about **102 FFs**:
two pending-control valid bits plus six pending lock-base bits. No new memory
block, DSP or line copy is introduced. Estimate **70–210 additional ALMs** versus
production, previously 60–180, assuming register/mux mapping and the unchanged
RAM organization. All are pre-fit estimates, not area reports.

New combinational qualifications include pending-control suppression of local
admission, and pipe_busy into fast_lookup_valid. The latter can continue through
adapter fast_hit, req_valid and the data-probe offer to existing probe-owner
control. Thus it touches the reset/drain-to-probe cone indirectly: this work
must not claim that cone was removed or that 9.615ns is met. Existing owner
payload captures remain unreset; only small local valid/control registers have
reset. The physical fit must inspect this new fan-in, certificate/way selection
and dirty forwarding, plus original probe-owner endpoints. There is no
full-core timing or workload speed claim here.

## Verified matrix and fit decision

**READY for a matched full-core fit**, using the corrected isolated overlay
against production `9c948da8`, debugger enabled, seed **42**, actual **78MHz**
and analysis target **104MHz**. No fit has been submitted. No exercised lifecycle
or stale-read failure remains open. This decision authorizes no CPU adapter
widening or production adoption; routed timing/packing and full-core integration
remain the fit’s purpose.

| Test / event | Stages / outcomes | Result |
| --- | --- | --- |
| Reset with primed probe | Empty; one accepted owner; adjacent owners/bank intent; physical commit; first post-drain. Precommits/cancellations reconciled; no stale restart effects. | PASS |
| Direct invalidate / lock pulses with primed probe | Each event × all five stages. Older stores drain; one command application; payload preserved; sustained younger offer cannot starve command. | PASS |
| Clean / invalidate / clean+invalidate with primed probe | Each operation × all five stages; handshake waits for older commits; clean backing bytes correct; certificate reacquired. | PASS |
| Disable/re-enable with primed probe | All five stages; captured stores finish, directory revoked, subsequent read reacquires a certificate. | PASS |
| Active probes then actual load | Same word; opposite half; same segment/different way; noncolliding line. One and two adjacent stores each: 8 sampled fast consumers plus ordinary readbacks. | PASS |
| Successful line transfer | 32 bytes, four 64-bit beats, two empty cycles between beats; all eight returned words checked. | PASS |
| Rejected line | Explicit acceptance/rejection followed by scalar refill and correct returned bytes. | PASS |
| Reset with accepted line outstanding | Old peer tail drains while core held reset; release after quiet; no old beat/write/reply on restart; fresh read correct. | PASS |
| Dirty replacement | Distinct MVA 0x10100 / saved PA 0x5000; partial masks 5/A dirty both halves; force 64-way reuse; all 8 full-word writeback beats checked for PA/data/mask. | PASS |
| Existing admit-probe regression | 256 shortened reads, three injected owner mismatches, segments/words/masks/fault/SWP/maintenance/reset. | PASS |
| Existing real-adapter probe regression | 402 requests, 164 fast reads, 8 parallel A/B clocks, 122 blocked collisions. | PASS |
| Real-adapter lock pulse | Pulse captured while launched store live; one lock_done; following read sees new bytes. Extended probe fixture: 407 requests, 9 parallel A/B clocks. | PASS |
| Existing refill / maintenance regressions | Dirty-victim bus-error retry; indexed clean/error retention/invalidate. | PASS |
| Five-stream default + integrated gates | Each: five ×256 accepts/actual RAM writes/replies; all 255 adjacent gaps exactly 1; latency 2; clean counts 8/16/4/4/4; second cleans/external traffic 0. Deterministic repeat and wrong-byte rejection. | PASS |
| Fresh control, same current stream runner | Five ×256 stores, acceptance/commit gaps 4, latency 3. Current runner SHA matches both candidate manifests, differs from archived Stop 2 control runner. | PASS |

The full suite has **35 event/stage cases**, **8 sampled fast consumers**,
and **4 transfer/replacement cases**; its complete deterministic edge/event
stream repeats exactly. The five streams retain Step 2’s absolute edge results
and independently checked dirty-half sequence. Detailed per-stream counts,
first/last edges and interval histograms are in the machine-readable evidence.

## First failing and corrected edges

Raw pre-NBA rising-edge records (absolute origins differ between fixtures):

**invalidate failing**

```text
EDGE e=66 event=1 stage=2 req=1 ready=1 owner=0 intent=0 commit=0 reply=0 inv=0 lock=0 reset=0 fast=0
EDGE e=67 event=1 stage=2 req=1 ready=1 owner=1 intent=1 commit=0 reply=0 inv=0 lock=0 reset=0 fast=0
EDGE e=68 event=1 stage=2 req=0 ready=0 owner=1 intent=0 commit=0 reply=1 inv=1 lock=0 reset=0 fast=0
[675000] %Fatal: test.v:121: Assertion failed in test: reply without physical commit
```

**invalidate corrected**

```text
EDGE e=1074 event=1 stage=2 req=1 ready=1 owner=0 intent=0 commit=0 reply=0 inv=0 lock=0 reset=0 fast=1 apply_inv=0 apply_lock=0
EDGE e=1075 event=1 stage=2 req=1 ready=1 owner=1 intent=1 commit=0 reply=0 inv=0 lock=0 reset=0 fast=0 apply_inv=0 apply_lock=0
EDGE e=1076 event=1 stage=2 req=0 ready=0 owner=1 intent=1 commit=1 reply=1 inv=1 lock=0 reset=0 fast=0 apply_inv=0 apply_lock=0
EDGE e=1077 event=1 stage=2 req=0 ready=0 owner=0 intent=0 commit=1 reply=1 inv=0 lock=0 reset=0 fast=0 apply_inv=0 apply_lock=0
EDGE e=1078 event=1 stage=2 req=0 ready=0 owner=0 intent=0 commit=0 reply=0 inv=0 lock=0 reset=0 fast=0 apply_inv=1 apply_lock=0
EDGE e=1079 event=1 stage=2 req=0 ready=1 owner=0 intent=0 commit=0 reply=0 inv=0 lock=0 reset=0 fast=0 apply_inv=0 apply_lock=0
EDGE e=1080 event=1 stage=2 req=0 ready=1 owner=0 intent=0 commit=0 reply=0 inv=0 lock=0 reset=0 fast=0 apply_inv=0 apply_lock=0
```

**fast failing**

```text
EDGE e=113 event=8 stage=0 req=1 ready=1 owner=0 intent=0 commit=0 reply=0 inv=0 lock=0 reset=0 fast=1 apply_inv=0 apply_lock=0
STALE_FAST e=113 target=00000100 word=51000100 commits=0 accepts=1
[1131000] %Fatal: test.v:231: Assertion failed in test.probes: fast ACK before older store drain
```

**fast corrected**

```text
EDGE e=27495 event=8 stage=0 req=1 ready=1 owner=0 intent=0 commit=0 reply=0 inv=0 lock=0 reset=0 fast=1 apply_inv=0 apply_lock=0
EDGE e=27496 event=8 stage=0 req=0 ready=0 owner=1 intent=1 commit=0 reply=0 inv=0 lock=0 reset=0 fast=0 apply_inv=0 apply_lock=0
EDGE e=27497 event=8 stage=0 req=0 ready=0 owner=0 intent=0 commit=1 reply=1 inv=0 lock=0 reset=0 fast=0 apply_inv=0 apply_lock=0
EDGE e=27498 event=8 stage=0 req=0 ready=1 owner=0 intent=0 commit=0 reply=0 inv=0 lock=0 reset=0 fast=0 apply_inv=0 apply_lock=0
EDGE e=27499 event=8 stage=0 req=0 ready=1 owner=0 intent=0 commit=0 reply=0 inv=0 lock=0 reset=0 fast=1 apply_inv=0 apply_lock=0
EDGE e=27500 event=8 stage=0 req=0 ready=1 owner=0 intent=0 commit=0 reply=0 inv=0 lock=0 reset=0 fast=1 apply_inv=0 apply_lock=0
EDGE e=27501 event=8 stage=0 req=0 ready=1 owner=0 intent=0 commit=0 reply=0 inv=0 lock=0 reset=0 fast=1 apply_inv=0 apply_lock=0
EDGE e=27502 event=8 stage=0 req=0 ready=1 owner=0 intent=0 commit=0 reply=0 inv=0 lock=0 reset=0 fast=1 apply_inv=0 apply_lock=0
EDGE e=27503 event=8 stage=0 req=0 ready=1 owner=0 intent=0 commit=0 reply=0 inv=0 lock=0 reset=0 fast=1 apply_inv=0 apply_lock=0
EDGE e=27618 event=8 stage=0 req=1 ready=1 owner=0 intent=0 commit=0 reply=0 inv=0 lock=0 reset=0 fast=1 apply_inv=0 apply_lock=0
EDGE e=27619 event=8 stage=0 req=1 ready=1 owner=1 intent=1 commit=0 reply=0 inv=0 lock=0 reset=0 fast=0 apply_inv=0 apply_lock=0
EDGE e=27620 event=8 stage=0 req=0 ready=0 owner=1 intent=1 commit=1 reply=1 inv=0 lock=0 reset=0 fast=0 apply_inv=0 apply_lock=0
```

On corrected invalidation, the two older RAM writes and replies complete
before apply_inv becomes 1; the younger request stays blocked. On corrected
probe traffic, fast stays 0 while either owner lives and becomes usable only
after the physical commit. Noncolliding read-B activity is retained.

## Evidence and retained failed attempts

- full: `build/sim/resident-qual-full-20261116-05/`.
- admit: `build/sim/resident-qual-admit-20261116-01/`.
- probe: `build/sim/resident-qual-probe-20261116-01/`.
- adapter_lock: `build/sim/resident-qual-adapter-lock-20261116-01/`.
- refill: `build/sim/resident-qual-refill-20261116-01/`.
- maintenance: `build/sim/resident-qual-maintenance-20261116-01/`.
- baseline: `build/sim/resident-qual-stream-control-20261116-01/`.
- stream_default: `build/sim/resident-qual-stream-default-20261116-01/`.
- stream_integrated: `build/sim/resident-qual-stream-integrated-20261116-01/`.

Compact evidence: `docs/evidence/cache-resident-store-pipeline-qualification-20261116.json`.
It records final RTL hashes, per-run source manifests/log hashes, stream
measurements, the 35-case matrix and failing/corrected traces. Only
cache_access.sv differs from Step 2; bank/tags and collision poison are identical.
The Step 2 source and historical results remain replayable.

The old-candidate expected failures are under
`build/sim/resident-qual-first-failure-20261116-01/` and
`build/sim/resident-qual-stale-fast-20261116-01/`. Intermediate full-suite
attempts 01–03 stopped on a testbench fast-consumer counter check despite
all eight cases logging correct data. Generated C++ had constant-folded that
check to an unconditional stop. Moving counter ownership and its assertion
entirely to edge monitors corrected the fixture; final runs count eight
actual sampled acknowledgements. No RTL workaround was made for that check.
Full 04 passes without lifecycle probe priming; full **05** is the final
primed-probe sweep plus exact repeat. The first lifecycle-only run also
passed, and remains a smaller corrected trace.

No Quartus/CI action, clock change, production change or phone access occurred.
Stop here before fit submission.
