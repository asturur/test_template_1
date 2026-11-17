# Step 5F — post-indexed ARM store admission, 17 November 2026

**Retain the one-file admission change.** Original fill16_tail improves
**2,078→1,332 cycles (−746, −35.90%)** and fill8_tail **2,172→1,647
(−525, −24.17%)**, at both normal I:D profiles, 0:0 and 2:9. Matrix, transpose,
full-frame fill plus its pending-write drain, and the 71-cycle warm store stream
remain unchanged. This is an offline fixed-work result, not a phone score.

Control is retained 5D `258eed3abffac2017462d57005ef4da0e8443357`.
The [rejected 5E frontend change](cpu-target-delivery.md) is excluded. No donor
job or RTL import was used; larger-cache and whole-CPU work are deferred.

| Checked work | Profile | 5D | 5F |
| --- | --- | ---: | ---: |
| Original fill16_tail, 1,023 pixels | both | 2,078 | **1,332** |
| Original fill8_tail, 2,051 bytes | both | 2,172 | **1,647** |
| Original matrix ×16 | both | 45,736 | 45,736 |
| Original transpose ×32 | both | 3,591 | 3,591 |
| Full frame, 36,608 pixels, original window | 0:0 | 71,259 | 71,259 |
| Full frame, original median / body+first-empty | 2:9 | 201,302 / 201,407 | 201,302 / 201,407 |
| Warm 64 stores, first issue→last physical write inclusive | both | 71 | 71 |

All original bytes, mathematical/Unicorn outputs, guards, saved registers/SP,
seven windows, two repeats and wrong-output controls pass. Scored fill16_tail
windows are 2078/2086/2078/2086/2078 versus 1332/1341/1332/1341/1332; fill8_tail
2172/2171/2172/2171/2172 versus 1647/1645/1647/1645/1647, in both profiles.
Full-frame 2:9 windows remain 201302/201300/201302/201300/201302. Their first-empty
extensions remain 105–107 clocks, making every scored body+first-empty 201407.
This passive extension runs the normal check code concurrently; it is not a
parked CPU or full clean of dirty resident lines. The original guest still
cleans and checks its outputs. Full frame at 0:0 and both tails have zero
pending-write extension. Warm tails have zero external traffic.

[Source identities, all results, group schedules, checks and failed fixture attempts](evidence/cpu-store-postindex-20261117.json).

## Binding dependency and estimate before coding

The [collected donor report](ngage2-vs-5c-benchmark.md) suggested dependent
post-indexed stores. Exact 5D reproduces their eight retirement offsets:
**0,3,6,9,12,15,18,24**. However, this is not an absent base-forwarding path.
The first two stores already dequeue on consecutive clocks and compute correct
consecutive addresses. The younger issue packet can contain an old speculative
base; the existing shifter/ALU feedback resolves it before address capture.

What binds the stream is completion: the original classification only permits
unconditional pre-indexed word STR without writeback to use resident-store
credit. A post-indexed STR waits for its physical response, globally holding
younger packets despite their correct available bases. Same-line acceptance
therefore repeats every three clocks.

Before coding, measured main-loop counts were 504 word stores in fill16_tail
and 512 in fill8_tail. Of those, 441/448 are within the already selected line.
Two completion-wait clocks each gave direct bounds of 882/896 clocks and a
rough 750–900 wall-clock estimate. This was explicitly conditional on line
transitions and frontend phasing. The measured gains are smaller: 746/525.

## Two adjacent instructions and the group

Both tails first store to `80004004`, then `80004008`. PCs are `10002ae4/ae8`
for fill16 and `10002a3c/a40` for fill8. Offsets below use the first actual
operand dequeue as zero; both profiles have the same relative schedule.

| Event | 5D first / second | 5F first / second |
| --- | ---: | ---: |
| Actual operand dequeue | 0 / 1 | 0 / 1 |
| Correct address known and advancing at ALU | 2 / 3 | 2 / 3 |
| Store accepted | 5 / 8 | **5 / 6** |
| Actual cache RAM write | 7 / 10 | **7 / 8** |
| Architectural base write and retirement | 9 / 12 | **7 / 8** |

The second speculative issue read is `80004004`; its resolved old base is
`80004008`, its address remains `80004008`, and its updated base is `8000400c`.
The current store never uses that updated base as its own address. No new
adder, base snapshot or bypass is needed. Physical masks, segments, ways and
stored words are checked separately from admission and architectural writes.
A fallback request's unqualified `result_way` is not treated as a certified
slot; the group audit uses an actual indexed owner of the same resident line.

| Eight original stores; offsets from first event of each kind | 5D | 5F |
| --- | --- | --- |
| Acceptance | 0,3,6,9,12,15,18,21 | **0,1,2,3,4,5,6,9** |
| Physical RAM writes | 0,3,6,9,12,15,18,24 | **0,1,2,3,4,5,6,12** |
| Retirement | 0,3,6,9,12,15,18,24 | **0,1,2,3,4,5,6,14** |

The eighth word crosses the cache-line boundary. Its slower path remains;
this experiment does not promise a one-clock stream across arbitrary lines.
Every main-loop accepted PC/address/word matches the original store sequence,
and the complete first-scored retirement-PC sequence matches for every workload/profile.

## One general change; zero added state

Only `zap_predecode_main.sv` changes. Extend the existing owned store class to
original **unconditional ARM immediate word STR, post-indexed, W=0**, with
non-PC base/data registers and distinct base/data. Add and subtract offsets
are allowed. Predicated stores, bytes/halves, register offsets, pre-indexed
writeback, force-user STRT, PC operands and equal base/data keep their existing
fallbacks. The original no-writeback pre-index class is preserved.

The same classification tag travels through the existing pipeline. It permits
resident admission only after existing alignment, TLB permission, normal
memory, older-exception, cache-owner and credit checks. Existing late/second
store-data ownership is reused, not bypassed. Cache misses, device accesses
and unavailable credits still wait. Architectural base writes remain in their
original writeback owner; fault/IRQ cancellation does not publish a speculative
base. Following loads/devices retain the pending-store drain rules.

Added state: **zero bits**. Address arithmetic, base/data feedback, completion
registers, physical write pipeline, ordering and cache size are unchanged.
The new path is a small opcode/register comparison into the existing registered
class bit; no new combinational cache-ACK→CPU-advance path is introduced.
Physical packing and routed timing are unmeasured. The PLL remains 78 MHz and
the registered design target 104 MHz; no timing-closure gate or fit was used.

## Exact cycle accounting and remaining cost

| Disjoint bucket change | fill16_tail | fill8_tail |
| --- | ---: | ---: |
| Write holds | −754 | −772 |
| Empty operand queue | +8 | +250 |
| Other/advance | 0 | −3 |
| Read/load/other locks | 0 | 0 |
| **Total** | **−746** | **−525** |

Resident credit counts become 7→448 and 0→448, with accepted store counts
unchanged at 513/515, including the original partial-width/tail operations.
The line-boundary and frontend costs prevent treating 882/896 as realized
savings. Full frame has **zero resident-pipeline/credit acceptances** in both
versions; its 18,305 accepted writes and original window/drain are unchanged.
Widening admission alone does not accelerate that write-miss workload.

Next current-CPU priority: trace the eighth-store line handoff and the extra
250 empty clocks exposed in fill8. Separate registered completion/probe
ownership from frontend replenishment, then estimate one further wall-cycle
opportunity. Reuse the 5E lesson that earlier speculative fetch is not itself
useful issue. No frontend change is combined here.

## Qualification and fixture corrections

12,288 real-predecode vectors cover condition, Thumb/ARM, immediate/register
offset, P/U/B/W/L, PC, same base/data and other registers. The existing 118
nested/circular-return, hold and clear checks also pass twice.

The unchanged 64-store body is retained inside the existing memory/late-data
safety guest. Eighteen additional untimed cases check distinct data and varied
post increments/decrements, old-base addressing, equal base/data fallback,
true/false predication, pre-indexed writeback dependency, cold-load store data,
device exactly-once and base update, translation/permission/alignment aborts,
and an older failed load squashing the post store and base update. Guest checks
verify base preservation, FAR and FSR. A cold source can require serialized
completion; eligibility does not promise credit while cache service is occupied.

Actual IRQ injection occurs with **two outstanding stores**. Both profiles
accept and retire exactly 14 stores before the handler snapshot, preserving
base `80001d78`; readback verifies that prefix and the untouched zero suffix.
Physical RAM slot/byte ordering is checked independently, including 485 indexed
mutations across the composed guest. The original stream retains 448 ordered
acceptances, mutations, completions and retirements, 16 independent dirty
backing words and **71 clocks in all five scored warm samples**, twice per
profile. Existing load, late/second owner, banked source, device, IRQ/abort and
held-packet checks also pass. Both deliberately wrong post-store and ordinary
stream physical-byte expectations fail on the immutable passing executable.

Failed fixture attempts are retained explicitly. The initial legacy benchmark
observer assumed word-only masks and rejected a valid original halfword store.
The added IRQ test initially assumed its second store already had credit;
after a translation-context change the first store instead serialized. The
corrected trigger waits for the actual pending count of two. Added cold/fault
tests also required restoring the original stream's warm-up immediately before
its body. Finally, the legacy physical checker sampled stale `result_way` on
a fallback accept; its corrected expected slot comes from an independent scan
of valid tag RAM, retaining physical way/mask/data and backing-byte checks.
An assembly newline and an over-specified cold-load credit expectation were
also corrected. **Prototype RTL did not change during these fixture fixes.**

An extra JPEG build hit PCH disk exhaustion before simulation, after the
required runs above had passed. Docker subsequently returned cached-image I/O
errors. No new JPEG or additional eight-diagnostic result is claimed. Only
this chat's rebuildable compiler intermediates were removed; frozen inputs,
logs and completed executables remain. No Docker restart/prune, other-run
cleanup or image download was performed. The installed offline image and
single compiler job were used throughout.

## Provenance and replay

Control bundle `a70e107c983794856fb6091433866f9809263d0f307e356991c2e7a3d60f7f68`.
Accepted candidate `0db2f3095ddf7e92003ebaa52ca5673266a49cbe96de6c47571240e8b0a812c0`.
Normal patch 0078 records the one-file change; pristine upstream replay passes.
All 60 compiled production CPU RTL files match the measured candidate. Other
working files, strategy work, runs, assets
and checkpoints are preserved. No branch/worktree, donor job, CI, fit,
deployment or hardware input. Stop after this bounded result.

Helpers: `tests/cpu/cpu_store_postindex/`; use unique run names:

```sh
python3 tests/cpu/cpu_store_postindex/bench.py --control --name CONTROL \
  --case fill16_tail --case fill8_tail --case fill16_frame --case matrix4 --case transpose4 --jobs 1
python3 tests/cpu/cpu_store_postindex/bench.py --name CANDIDATE \
  --case fill16_tail --case fill8_tail --case fill16_frame --case matrix4 --case transpose4 --jobs 1
python3 tests/cpu/cpu_store_postindex/classify.py CLASSIFY
python3 tests/cpu/cpu_store_postindex/run.py MEMORY --safety --arg +i_wait=2 --arg +d_wait=9
python3 tests/cpu/cpu_store_postindex/run.py ZERO --safety --reuse build/sim/cpu-store-postindex/MEMORY
python3 tests/cpu/cpu_store_postindex/negative.py build/sim/cpu-store-postindex/ZERO
```

Final benchmarks: `build/sim/spmark-payload/postindex-{control-02,candidate-01}/`.
Qualification: `build/sim/cpu-store-postindex/{classify-01,memory-07,memory-zero-01}/`.
`analyze.py --production` audits these runs and writes the durable evidence.
`storage.py` compacts only completed5F outputs. All software needed for replay
is maintained outside disposable scratch space.
