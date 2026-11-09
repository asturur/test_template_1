# DDR-backed ROM instruction buffer

The optional `ROM_CACHE=1` path in `ngage_ddr_adapter` uses JTFRAME's LARGE
ROM request cache: configurable 1/2/4 KiB with 64/128/256-bit lines, 32-bit
client and synchronous BRAM tags (`TAG_RAM=1`). Template currently enables
64-bit lines and 1 KiB, retained after the nine-way benchmark. It is an implementation
buffer for raw backing bytes, independent of the ARM's architectural I-cache.
It does not model the flash device's specified access/burst timing yet.

`ngage_mister` captures the CPU instruction-fetch qualifier when the code-flash
request is accepted, then holds it for the later DDR request. The shared DDR
arbiter's CPU acceptance qualifies that sideband at the cache boundary; loader
and save traffic cannot inherit it. Only instruction reads in immutable backing
`0x30000000..0x313effff` look up or fill the cache. ROM data/file/literal reads,
C:, PMM, status and programming responses take their existing paths. NOR command
and address-dependent descrambling logic remains above the raw-byte cache.

On a miss, the DDR backend requests one, two or four 64-bit beats for a
64/128/256-bit line. It assembles the complete response before feeding the
LARGE cache in 16-bit words, low first. `dst` marks the first word and `din_ok`
the last. Template forwards the backend's DDRAM_BURSTCNT. Bypass reads and
writes always use one beat; uncached reads extract the addressed 32-bit lane. A hit
returns after synchronous tag/data lookup and address-pipeline settling.

Every accepted DDR write to immutable ROM backing clears all cache valid bits.
This covers loader erase, either firmware slot and repeated reloads without
requiring a separate loader-valid event. Writable flash remains uncached. The
outer cache accepts one request at a time, so a write cannot race an earlier
fill. Reset discards lookup/fill state; the backend drains any already accepted
DDR read, including every remaining beat of a wider burst, before accepting
another and suppresses its stale response. A cancelled
fill cannot mark a line valid after reset. Source addresses/data are latched.

Imported implementation: local JTFRAME
`modules/jtframe/hdl/sdram/jtframe_romrq_lcache.v`, SPDX GPL-3.0-or-later. Local
copy is `rtl/jtframe/ngage_jtframe_romrq_lcache.v`; the module is renamed and its
two generic RAM instances use `ngage_bram` to request explicit Cyclone V M10Ks.
The imported fill counter, line assembly and word selection were extended for
128/256-bit lines using the sysfl 128-bit cache as a reference. Wider lines
require a 32-bit client; the original 64-bit/1 KiB mode remains supported. Provenance/hash of the original
copy is retained in `scratch/jtframe-ddr-cache/provenance.json`.
Data is 8192 bits, tags 1920 bits and valid storage 128 bits, plus fill/control.
Primitive packing and final timing require a future Quartus fit; no resource
or 104 MHz closure claim follows from simulation.

Run inside the existing simulator image:

```
sh tests/phone/ddr_rom_cache/run.sh
```

The test uses the production adapter/backend/cache/BRAM models and covers both
word lanes, resident reuse, direct-map eviction, data-read bypass without
instruction eviction, full/masked reload writes, mutable-region exclusion,
reset during lookup/issue/wait/select/fill and a new request arriving before a
cancelled DDR response drains. Legacy transport, flash reset and save-manager
regressions remain applicable. Post-fit validation remains separate.

Independent boot measurement uses `run-logo.py --rom-cache --early-boot-trace`
with verified service-loader backing and 78 MHz phone timebase parameter. It
never restores or changes the long uncached run. Its manifest/source identity
records the cache option. The long run continues with its frozen executable;
resume it with `--use-saved-build`, not newly edited HDL.

Integrated reset/reload and boot tests now pass; measured warm delay iteration
is1515clocks with the buffer alone,1317 after the uncached CPU-side bypass fix.
See [uncached fetch](uncached-fetch.md) for exact counter attribution.


## Nine-way boot benchmark

Each combination of 64/128/256-bit lines and 1/2/4 KiB capacity runs independently
from reset for 50,000,000 cycles with the uncached CPU lookup shortcut enabled.
The source files, service-loader-derived firmware bytes, C: snapshot, erased
PMM and 78 MHz phone timebase are identical. The harness uses 100 MHz host
steps, three clocks to the first modeled DDR response and consecutive later
beats. These are simulated cycle comparisons, not measured board DDR latency,
post-fit resource usage or timing closure.

The runner accepts `--rom-cache --rom-cache-bits BITS --rom-cache-bytes BYTES`.
Production adapter/cache tests cover all nine configurations, including reset
after the first beat of a wider response. The benchmark orchestrator, result
collector and logs are in `scratch/ddr-cache-matrix/`; per-case runs and paired
50M checkpoints are in `build/sim/runs/rom-matrix-{bits}-{bytes}-50m/`.
The separate original 12B run uses its frozen executable and is not resumed,
rebuilt or modified by these cases. All nine endpoints completed and were checked.

| Line bits | Cache KiB | Delay entry cycle | Clocks/iteration | Outer index at 50M | DDR commands | 64-bit beats |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 64 | 1 | 147,802 | 1,317 | 37,852 | 1,208 | 1,208 |
| 64 | 2 | 147,186 | 1,317 | 37,853 | 1,155 | 1,155 |
| 64 | 4 | 146,990 | 1,317 | 37,853 | 1,141 | 1,141 |
| 128 | 1 | 145,252 | 1,317 | 37,854 | 841 | 1,315 |
| 128 | 2 | 144,669 | 1,317 | 37,855 | 804 | 1,241 |
| 128 | 4 | 144,498 | 1,317 | 37,855 | 795 | 1,223 |
| 256 | 1 | 144,523 | 1,317 | 37,855 | 645 | 1,479 |
| 256 | 2 | 143,798 | 1,317 | 37,855 | 618 | 1,371 |
| 256 | 4 | 143,566 | 1,317 | 37,856 | 610 | 1,339 |

Each run retired about 3 million instructions and covered 37.85% of the first
100000-iteration delay. All have zero data faults and the same 12 known early
fetch faults; LCD initialization has not yet reached pixel output at these
endpoints. Source/input hashes match across the nine manifests, apart from
configuration-dependent identities/binaries. Both CPU and host checkpoint files
are retained for every 50M endpoint. All nine unit configurations, legacy DDR
transport and top elaboration passed before the boot matrix.

Every measured warm iteration has 79 retirements, 99 fetch completions, zero
DDR reads and 1317 clocks. Increasing capacity or line width cannot improve
this resident loop. Relative to 64-bit/1KiB, 256-bit/4KiB enters the delay 4236
clocks earlier (54.3 microseconds at 78MHz); 64-bit/4KiB saves only 812 clocks.
The approximately 131.7M-clock loop body remains unchanged. Its full completion
and a subsequent logo are projections here, not observed by these 50M cases.
Wider lines reduce DDR command count but increase total returned beats in this
startup workload. Actual DDR latency could change the cold-start tradeoff.

Recommendation: retain 64-bit/1KiB as the default. This workload does not justify
extra capacity or wider refill machinery. The next useful latency investigation
is the resident instruction-hit path: the existing measured sequential chain
still costs 4 clocks to issue the next request, 7 to service it, and 2 to deliver
completion. Preserve registered ownership, reset/reload and fault alignment when
considering reductions. Do not infer real flash timing or a hardware speedup
from this modeled-memory benchmark. No hardware build was launched.

Full counters: `scratch/ddr-cache-matrix/results.json`; compact table:
`scratch/ddr-cache-matrix/results.md`. The orchestrator's already-running copy
encountered a duplicate-name bookkeeping exception after launching all cases;
the independent runner processes continued. `collect.py` verified all nine
final JSONs, matching source/input lineage, counter deltas and paired
checkpoints. The on-disk orchestrator is corrected; no simulation rerun was
needed for this collection-only failure.


The subsequent resident-hit change is described in [uncached fetch](uncached-fetch.md).
It starts BRAM lookup on acceptance and uses the imported cache's opt-in
`HELD_ADDRESS` contract; the wrapper keeps one outstanding held request and
registers completion. Reset/reload and streaming-client defaults are preserved.
The nine-way matrix above predates this change; its1317-clock iterations are
the baseline, not the shortened path's new result.
