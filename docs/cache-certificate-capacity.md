# Cache metadata reuse capacity

The two-entry directory repeatedly forgets resident lines in the original JPEG
converter. Every forgotten line repeats synchronous tag read and comparison even
though the main cache still holds it. Eight records reduce that work without
changing the 16KiB data cache, allocating extra line data, or weakening current
translation and permission checks.

The directory retains only full modified-virtual line tag, present/absent and
selected way. Admission captures the selected owner before RAM use. Stores still
commit data and current dirty metadata together; no dirty bits or permission
results are copied into these records. Existing refill, maintenance, lock, cache
disable and reset revocations clear every record. The independent port-B probe
selects from the same eight certified records and keeps its collision interlock.
A simple rotating replacement successor updates after learned or reused entries;
there is no associative data cache replacement policy change.

Two records used71 declared metadata bits. Four use142 and eight283: the adopted
eight-record change adds212 bits, no line-data RAM, no queue or pipeline stage.
Tag comparisons and selectors are wider, so fitted area and routed timing remain
required. Actual PLL stays78MHz;104MHz remains the design objective. The prior
CPU image uses93% ALMs, so reject an unsuitable fit rather than assuming this
small RTL size has a negligible physical cost.

| Original JPEG converter | Corrected CPU,2 records |4 records|8 records|
| --- | ---:| ---:| ---:|
|8x8 image, mode10|104900|100622|98072|
|8x8 random, mode10|104916|100638|98088|
|8x8 random, mode8|103771|99285|96623|
|16x8 image, mode10|206956|198750|193536|
| Original four-case index|113.2493|118.1046|121.2488|

Eight records improve this suite7.0636% over corrected0070+0071. Full original
six-kernel indices become233.2707/196.1981 at synthetic I:D0:0/2:9 (+1.2195%).
These are fixed-work simulation indices, not SPMark points or whole-phone speed.
The JPEG8x8 profile falls36994→28970 data-wait clocks; do not add
occupancy buckets into a predicted speedup.

A supplemental original176x16 image-derived strip uses disjoint source/output
buffers and1warmup/1checked sample with2exact repeats per profile. Corrected CPU
4511115/4515352 clocks becomes4231624/4235861. Previous CPU4679397/4683631 is
retained for comparison. Original-code Unicorn output matches every checked
object, error buffer, source byte, output pixel and guard. This separate workload
does not replace the original four-case index. Initial7-window runs were stopped
because speculative decode advisories flooded logs, not because output failed.
A2-window parser mismatch then failed before result acceptance; the corrected
supplement validates its exact window set and every category/counter. Advisory
counts and hashes are retained, with fatal/output failures unfiltered.

Qualification: full12six-kernel and8JPEG groups, two exact repeats, mathematical/
original-code outputs, six wrong-output and eight wrong-object/pixel controls;
eight unprofiled JPEG runs match every raw profiled counter.92CPU architecture,
44IRQ/FIQ boundaries,128per-beat block-transfer aborts and8protected-page/LDRT/
STRT controls pass. Direct resident94, probe336, absence44 and admission256
transactions preserve masks, high tags, physical writeback, permission/class,
capacity, maintenance, reset and mixed-port collisions. Real CPU C: erase/refill,
reset-drain and competing DDR snapshots pass with unchanged counts.

The new independent twelve-line fixture checks every loaded/revisited/mutated
value, reverse reads, wrap and revocation: old two-entry directory gets0short
revisits; eight gets8. A deliberately truncated selector fails specifically with
`certificate slot data`, rather than a timing-count assertion.146requests pass
in the adopted implementation. Other simulations/checkpoints are untouched.

```sh
sh tests/cpu/cache_certificate/run.sh build/sim/UNIQUE
# Prior two-entry cache can be checked with CERT_REUSE=0 and CACHE_ACCESS_RTL.
```

Production adoption is simulation-qualified; native JPEG and fit/timing remain
pending.00fbbea boots stock firmware cardless and saves C:, but its JPEG-only
native test still waits. No deadline, result or firmware substitution was made.
[Machine evidence](evidence/cache-certificate-capacity-20261116.json).
