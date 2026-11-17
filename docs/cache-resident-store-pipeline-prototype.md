# Isolated resident-store pipeline prototype — 16 November 2026

This is Stop 2: an offline, test-selectable source overlay on
`codex/ngage2-integration`, production revision
`9c948da8da413a882e0fe8e559c380ea0cadabf4`. Production RTL, project settings,
clocks, CI, Git history, phone and existing simulations were not changed.
The reusable candidate is `tests/cpu/cache_resident_pipeline/rtl/`;
`run.py` explicitly replaces only cache_access, cache_bank, cache_tags and the
simulation BRAM model. Exploration copies under `scratch/resident-store-pipeline/`
are disposable. No production file imports this candidate.

## Replay and source identity

Use unused output directories from the repository root:

```sh
python3 tests/cpu/cache_resident_pipeline/run.py build/sim/resident-pipeline-control-rerun --baseline
python3 tests/cpu/cache_resident_pipeline/run.py build/sim/resident-pipeline-default-rerun
python3 tests/cpu/cache_resident_pipeline/run.py build/sim/resident-pipeline-integrated-rerun --data-probe 1 --line-refill 1
```

Every invocation builds once and runs normal, repeat and deliberate wrong-byte
cases in `jotego/simulator:arm64`, with `--pull=never --network none`. Each output
has a manifest with actual compiled file SHA256s, included checker/adapter
hashes, exact parameters, revision and image identity, plus raw logs and
`result.json`. Source fingerprints must remain fixed through the test.
The five-stream generator, golden model and expected results come directly from
Step 1, unchanged; generated testbench changes select parameters, add directed
cases and print actual dirty metadata. All hierarchy-specific baseline taps
remain in `tests/cpu/cache_resident_stream/observe.vh`.

Default mode has LINE_REFILL=0, DATA_PROBE=0, READ_ONLY=0. The integrated D-cache
configuration has LINE_REFILL=1, DATA_PROBE=1, READ_ONLY=0; probe inputs are idle.
The fixture accepts line requests and explicitly rejects them to the existing
scalar refill fallback. Thus it tests parameter selection and the resident
pipeline with real scalar-warmed lines, not successful line transport or active
probe concurrency. Those qualifications remain outside this stop.

## Owner pipeline and drain

The production path is request admission → LOOKUP_CAPTURE → STORE_HIT →
STORE_COMMIT, then another admission. Its captured owner is unique, so simply
opening req_ready earlier corrupts ownership.

The overlay instead accepts an eligible certified ordinary write-back store
into a private owner register: MVA (word/half/segment), certified way, data and
byte mask. It uses the existing checked-line certificate; no new permission or
physical mapping rule is invented. Permission/translation remain upstream as
in production. Uncertified, nonordinary, zero-mask, uncached, write-through and
incompatible requests retain the serialized path. Cache geometry remains eight
segments ×64 ways ×32 bytes, with 32 independent byte enables and two dirty bits.

At acceptance E, synchronous tag port B reads the accepted segment. At E+1,
the registered owner supplies data and metadata intent to the existing bank
commit registers. At E+2, actual data port A and tag dirty byte write together;
pipe_commit supplies that owner's sampled response. The next independent owner
can occupy each stage concurrently. Payload registers have no reset mux; only
local valid bits reset. This two-stage, always-draining local capacity supports
a store every clock without CPU completion feedback or an ACK queue. The
interface has no response-ready input; every response cycle is a completion.

The fast path leaves the serialized controller idle. Ready is withheld from an
incompatible offer while either owner stage is occupied; maint_ready also waits
for both stages to drain. Once the last commit edge passes, the held ordinary
read or miss can enter the old path and receives its own response. The directed
test keeps req_valid high across each transition, checks the older six actual
commits/responses before accepting the following access, and verifies its read
value. An idle bubble is also exercised.

## Dirty collision rule

Tag RAM's mixed-port read value is not used when it collides with an overlapping
write. Metadata selection has this priority:

1. Pending metadata for the same physical slot: use its accumulated dirty bits
   OR its own half. This covers consecutive same-slot intents.
2. The metadata written on the tag read's launch edge, saved in one recent
   slot/dirty record. This covers A/B/A interleaving of different ways in the
   same segment and collision reads after a bubble.
3. The synchronous packed-tag RAM result.

The newest pending record wins over the recent record. Each current store then
ORs its own half into this selected value. The bank has a separate indexed MVA
input so a younger lookup address cannot change an older commit's half/segment.
The serialized same-slot assertion is replaced by an assertion requiring a
forwarding owner for overlapping same-slot mutation, and the tag assertion
permits the bypass while retaining resident-valid checking. The independent
scoreboard checks the physical tag after every actual RAM commit.

Recent valid is refreshed only by an allowed metadata write and otherwise
cleared on the next clock; reset, invalidate, lock, scan clean/invalidate and
fill suppress it. It is not a persistent dirty cache. Maintenance/fill cannot
start until accepted stores drain. Asynchronous revoke during an occupied
pipeline is explicitly asserted unsupported in this prototype; full reset,
probe and maintenance overlap qualification belongs to the next stop.

The overlay BRAM model deliberately returns all ones on a mixed-port collision,
including poisoned tag bits and dirty bits. The checker observes actual RAM
storage independently of that read output. Passing opposite-half and A/B/A
cases therefore does not depend on the benign production simulation collision
value. This poison affects simulation behavior only; RAM ports and storage
geometry are unchanged.

## Results and edge convention

See the measured table appended below and the compact evidence JSON. Offers,
acceptances, responses and physical RAM write ports use Step 1's pre-NBA rising
edge convention. Stored bytes and tag dirty bits are checked at +1ns. Warming,
readback and clean are outside measured intervals. Every stream requires 256
ordered accepts/responses/physical writes, exactly 255 one-clock acceptance and
commit gaps, independent byte/slot ownership, clean counts 8/16/4/4/4, zero on
second clean, and zero external transfers through drain. Normal/repeat event
records and directed dirty traces must match. The wrong-byte run must fail
specifically at the independent commit checker.

The default first-owner trace is:

| Edge | Accept | Registered owner supplies bank intent | Actual RAM+dirty write and sampled response |
| ---: | --- | --- | --- |
| 63 | store 0, 0x100 | — | — |
| 64 | store 1, 0x104 | store 0 | — |
| 65 | store 2, 0x108 | store 1 | store 0 |
| 66 | store 3, 0x10c | store 2 | store 1 |
| 67 | store 4, 0x110 | store 3 | store 2 |

Fill latency is two clocks versus baseline three. Steady rate is
`255/(last−first)`, one per clock versus baseline 0.25. This is direct cache-port
throughput, not CPU IPC or a workload speedup.

## Pre-fit resource and timing estimate

The added state is approximately 94 FFs: 74 owner payload bits, two pipeline
valids, six registered indexed-way bits and a 12-bit recent-dirty forwarding
record. Existing 256-bit bank payload registers are reused. Estimate roughly
60–180 additional ALMs, zero added M10Ks/MLABs/DSPs, assuming muxes map to logic
and the existing RAM organization is preserved. These are pre-fit engineering
estimates, not synthesis or packing results.

Likely limiting cones are the eight-certificate tag match/way select into the
ingress owner, and synchronous tag output / pending 64-way selected-bit test /
recent-slot comparison → two-bit dirty bypass → registered metadata. A rough
5–10ns local-path planning range is plausible with routing; its upper end
already exceeds 9.615ns, so there is no 104MHz closure claim. A fit must check
these paths and the whole core, against the review's ~8ns local data-delay
planning screen and actual clock effects.

No new pipeline response feeds the probe address/way selection or CPU
completion-next logic; ingress payload capture uses local owner registers.
The existing probe circuit is retained and idle in these tests, so this result
neither reproduces nor fixes the fitted reset-drain→completion-next→probe-owner
path. Full reset/probe ownership timing and the matched integrated fitter gate
remain mandatory before any production adoption.

## Failed approaches retained

Default attempt 01 reached consecutive writes then correctly tripped the old
fresh-read tag assertion on a poisoned collision. Default 02 and integrated 01
passed streaming but their directed driver tested combinational ready in the
same delta as changing the offer; a +1ns settle before checking ready repaired
the test. Integrated 02 timed out because the original fixture held line_ready
low. The final runner acknowledges line requests and rejects to scalar fallback.
These are preserved raw traces, not qualified final runs.

Stop after this isolated result. CPU adapter changes, full lifecycle/probe/
maintenance qualification, Quartus, workload claims and hardware deployment
are separate work.

## Verified measured handoff

**PASS** for the isolated throughput and correctness gates in both candidate
configurations. All rows have 256 accepted stores, 256 sampled responses and
256 actual physical RAM writes. Baseline gaps are four clocks; both candidate
acceptance and commit histograms are exactly `{1: 255}` in every row.

| Stream | Baseline accepts / commits | Default candidate accepts / commits | Integrated candidate accepts / commits | Clean words |
| --- | --- | --- | --- | ---: |
| successive_words_both_halves | 63–1083 / 66–1086 | 63–318 / 65–320 | 67–322 / 69–324 | 8 |
| alternating_two_lines | 4244–5264 / 4247–5267 | 3478–3733 / 3480–3735 | 3482–3737 / 3484–3739 | 16 |
| same_word_partial_bytes | 8435–9455 / 8438–9458 | 6903–7158 / 6905–7160 | 6907–7162 / 6909–7164 | 4 |
| lower_half_only | 12612–13632 / 12615–13635 | 10314–10569 / 10316–10571 | 10318–10573 / 10320–10575 | 4 |
| upper_half_only | 16789–17809 / 16792–17812 | 13725–13980 / 13727–13982 | 13729–13984 / 13731–13986 | 4 |

Default and integrated fill latency is two rising edges; baseline is three.
Steady acceptance and RAM-commit rates are 1.0/clock for candidates and
0.25/clock for baseline. All measured external reads/writes and all second-clean
writes are zero. The integrated warm-up adds four clocks to absolute edges
because it enters line request/rejection before scalar refill; burst intervals
and correctness are identical. There is no change to responder speed.

Final raw output and source/hash manifests:

- baseline: `build/sim/resident-pipeline-control-20261116-01/` (`source.json`, `normal.log`, `repeat.log`, `negative.log`, `result.json`).
- default: `build/sim/resident-pipeline-20261116-04/` (`source.json`, `normal.log`, `repeat.log`, `negative.log`, `result.json`).
- integrated: `build/sim/resident-pipeline-integrated-20261116-03/` (`source.json`, `normal.log`, `repeat.log`, `negative.log`, `result.json`).

Durable combined evidence: `docs/evidence/cache-resident-store-pipeline-prototype-20261116.json`.
Every normal event and directed trace repeats exactly. Each wrong-byte run
rejects store 0 at its physical commit for the intended checker byte mismatch.

Actual directed dirty metadata from the default run (first transition):

```text
DIRECTED_DIRTY edge=17138 id=0 slot=0 actual=01
DIRECTED_DIRTY edge=17139 id=1 slot=0 actual=11
DIRECTED_DIRTY edge=17140 id=2 slot=8 actual=01
DIRECTED_DIRTY edge=17141 id=3 slot=0 actual=11
DIRECTED_DIRTY edge=17143 id=4 slot=8 actual=11
DIRECTED_DIRTY edge=17144 id=5 slot=0 actual=11
```

The first two entries are consecutive full-word writes to lower and upper
halves of initially clean physical slot 0. Slot 8 is a different way in the
same segment. Later entries alternate those ways and include an idle bubble.
The post-edge checker compares these actual tag bytes with independent dirty
expectations, and checks physical data bytes after every write.

```text
DIRECTED drain_read waited=2 owner=0 commit=0
DIRECTED opposite_halves/interleaved_ways/bubble transition=0 accepts=6 commits=6 responses=6 clean_words=16 PASS
DIRECTED drain_read waited=2 owner=0 commit=0
DIRECTED opposite_halves/interleaved_ways/bubble transition=1 accepts=6 commits=6 responses=6 clean_words=16 PASS
```
