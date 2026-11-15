# Two local checked translation mappings

C is implemented and independently qualified in simulation. Matrix throughput
improves **8.51%**, transpose **3.68%**, triangle setup **4.40%**. The full suite
gains **2.7630% / 2.7626%** over resident-way reuse, with original-baseline
indices **149.1744 / 139.6171** for waits 0:0 / 2:9. These are fixed-work kernel
results, not official SPMark scores or board FPS. Fit, timing and boot are unverified.

## Why this change

After E1/E2, the actual matrix payload still spends 7,054 of 66,031 clocks
waiting for translation despite no external traffic in scored windows. It
alternates two 1KiB regions, repeatedly replacing the one checked local mapping.
The new slot preserves both under one shared permission context. Only
`rtl/arm920/tlb.sv` changes in the production CPU source closure.

## Implementation and cost

Keep the existing primary mapping/exact-fault record and add one secondary
mapping under its shared CPSR/SR/DACR/TTBR context. The secondary holds a 22-bit
virtual subpage, 22-bit physical subpage, two C/B bits, independent read/write
permissions, two 8-bit FSR fields and one valid bit: **65 additional state bits
per controller, 130 across I/D**. No new RAM, line copy, TLB bank, port or
outstanding request is added. Declared bits are not a fitted ALM estimate.

Both address comparisons run in parallel under the shared context, followed by
a two-way selection. AP/domain permission calculations remain at publication.
The synchronous architectural 64-entry table and its lookup/walk boundaries
remain. The PLL stays at 78MHz; 104MHz remains the routed-timing target.

Publication uses FIFO rather than hit-time LRU: an actual main-bank hit saves
the previous primary mapping as secondary before replacing the primary. Hits
do not swap wide records or update recency. An initial pair of cold walks needs
the first page rewarmed through the main bank before both mappings are local.
Every main-bank fill revokes both old local records before publishing its new
primary. This conservative rule prevents local mappings outliving a main-table
victim or overlapping-page replacement. All/MVA invalidate, lockdown writes and
MMU disable also revoke both; publication never mixes contexts.

Permission faults preserve reusable mapping permissions, including on the
secondary. Invalid descriptors and table-bus aborts remain exact full-VA and
access-direction primary results. Only their live owner can consume them;
idle ACKs and secondary permission faults cannot consume another pending exact
fault. Current request offsets supply PA/FAR low bits.

The CPU/cache remain blocking. Future P1 probes can use this comparison boundary,
but P2 must validate current context/direction and capture PA/C/B/fault with its
owner. Later replacements must not retarget accepted work. Stage credits,
precise exceptions and memory ordering remain separate F work.

## Verification and profile

The full six-payload benchmark passes both memory profiles, all 12 groups and
84 windows per repeat, two exact repeats and six wrong-output controls. Final
measurement including build/setup/checks takes 440.557s. Medians are matrix
60,850; transpose 7,510; triangle 37,360; full-frame 135,318 / 201,321; fill16
tail 4,328; fill8 tail 5,052. [Comparison table](spmark-payload-results.md).

Final-source acceptance also passes **96 CPU runs, seven related unit suites
and four negative controls**. The maintained `tlb_two_mapping` unit exercises
all four page classes, 256 hot checks, distinct PA/C/B/RW permissions, combined
SWP access, equal offsets, third-mapping FIFO replacement, current offsets,
context changes, idle ACKs and exact walk faults. It fills 64 main entries then
evicts a locally retained mapping with entry 65: the next access must walk and
observe the new PA. Preserved lockdown entries survive only in the main bank
across all-invalidate and are removed by MVA invalidate. Reset is tested too.

The new CPU program alternates two cached translated regions with distinct PAs
and AP2/AP3 permissions. Force-user reads and allowed writes remain correct;
all 32 denied writes report the exact protected FSR/FAR and leave data unchanged.
The retained negative controls reject the predecessor, stale mappings after
main-table eviction, incorrect secondary permissions and the owner bug below.

Qualified post-change profiles cover matrix, transpose and triangle at both
profiles, two identical repetitions, with every original counter unchanged.
Matrix translation waits fall **7,054→2,401**, and data holds **26.55%→21.17%**.
Transpose data holds are 44.85%, load dependencies 20.51%; matrix/triangle empty
queues are 33.84%/30.88%. These counters overlap and do not prove a branch cause.
They are not a new full six-case stall profile. The older RAS/forwarding/pipeline
plan and owned store-completion work remain open. [Profile](spmark-payload-profile.md).

## Rejected prototype corner

The first candidate passed 96 CPU runs and the initial directed unit, but an
expanded checked-tuple test caught a consumed primary walk fault appearing
valid through `o_checked_mmu` because the unrelated secondary remained occupied.
The final output qualifies the selected secondary rather than its occupancy.
The production checked-owner assertion remains. The added reproducer fails the
prototype; final-source units, CPU runs and the full benchmark were rerun.

## Reproduction and retained evidence

```sh
sh tests/cpu/tlb_two_mapping/sim.sh build/sim/UNIQUE
python3 tests/cpu/spmark_payload/run.py --name UNIQUE \
  --baseline build/sim/spmark-payload/resident-store-20261115/result.json
python3 tests/cpu/spmark_payload/profile.py \
  --base build/sim/spmark-payload/ACCEPTED --name UNIQUE \
  --case matrix4 --case transpose4 --case triangle_edges \
  --profile 0:0 --profile 2:9
```

[Qualification](evidence/cache-two-mapping-20261115.json),
[full benchmark](evidence/spmark-payload-two-mapping-20261115.json).
Accepted sources/binaries/logs: `build/sim/spmark-payload/two-mapping-final-20261115/`.
CPU outputs: `build/sim/two-mapping-final-cpu-20261115/`.
Unit fixtures/results: `build/sim/resident-two-mapping-final-units-20261115/`.
Controls: `build/sim/two-mapping-controls-final-20261115/`.
Before/after profiles: `build/sim/spmark-profile/two-mapping-before-retry-20261115/`
and `two-mapping-after-20261115/`.
Scripts/predecessor: `scratch/two-mapping-20261115/`.

The prototype in `build/sim/spmark-payload/two-mapping-20261115/` is not the
accepted final source. An initial profile launch failed on the sandbox's Docker
socket access; the retry used the existing offline simulator image. Other
threads' simulations and permanent checkpoints were untouched. No CI build,
MiSTer action or branch/worktree change was requested or performed in this step.
