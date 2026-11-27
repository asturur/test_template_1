# ARM9V2 cache associativity experiment

Find out how much of v5’s 3D shortfall comes from conflict misses, how much time the CPU spends servicing a miss, and which geometry buys the most performance on MiSTer. Start with the existing `ngage-v5` worktree at `2a84b50`. Record the effective source and fixture hashes, including any existing local changes used. Preserve the other work in this checkout.

## The six configurations

Keep both L1 caches at 16 KiB each and 32 bytes per line. Change instruction and data ways together for the primary sweep. Each cache always holds 512 lines.

| Ways | Sets per cache | Bytes between addresses that select the same set |
| ---: | ---: | ---: |
| 2 | 256 | 8,192 |
| 4 | 128 | 4,096 |
| 8 | 64 | 2,048 |
| 16 | 32 | 1,024 |
| 32 | 16 | 512 |
| 64 | 8 | 256 |

Freeze the 78 MHz CPU and memory interfaces, 39 MHz MMC, 8 KiB flash backing cache, 64 Hz NOS, TLBs, memory waits, refill order and early-restart policy. Keep 104 MHz as the routed timing target. Use the existing v5 simulation entry points and the Quartus-selected generated CPU. Preserve the pinned upstream source and make regeneration reproducible for every geometry. Record the elaborated I/D geometry and verify CP15 readback and indexed maintenance agree with it.

## What to carry over

| Mechanism | Evidence and action |
| --- | --- |
| Dirty halves and writeback | Master keeps one dirty bit per 16-byte half of each 32-byte D-line, packed into the tag RAM. Data and dirty updates commit together. Eviction/clean writes 4 words if one half is dirty, 8 if both are dirty. Commit `37f3fac` packed the metadata and was tested for cycle equivalence. Measure the bandwidth effect of half-line writeback separately from the storage change. See master `rtl/arm920/cache_tags.sv`, `rtl/arm920/cache_maintenance.sv`, and `tests/cpu/cache_dirty_packed/`. |
| Faster repeated accesses | Master remembers a line's address, presence and validated way. This lets a later access select the data RAM directly. The two-entry implementation in `2aa4be3` gained 2.72% from resident reads and a further 8.29% from resident stores, or 11.23% combined over the prior control across six kernels. Current master has eight entries. Port as a separate D-side trial if ordinary hits spend cycles selecting a way. Count useful hint hits and cycles actually saved. See master `docs/cache-resident-way.md` and `rtl/arm920/cache_access.sv`. |
| Whole-cache cleaning | Master's maintenance controller visits all 512 slots and fetches line data only for dirty writeback. V5 already examines dirty flags in groups of 16 and selects a dirty line from the group. Preserve that advantage at every geometry. Count cycles scanning empty groups separately from cycles writing dirty data. A group-nonempty bitmap is an additional experiment if scanning accounts for meaningful time. |

## Implementation order

1. **Establish the original two-way control.** Record the benchmark and maintenance counters on the production build. Add independently selectable I/D way counts. Replace two-way-only hit/word/victim muxes, the one-bit way carried into the CPU and held across stalls, replacement state, CP15 index decoding and way/set arithmetic throughout the actual generated path. Review `rtl/arm9v2/upstream/rtl/cpu/zap/zap_cache_tag_ram.sv`, both cache FSMs, late load forwarding and `tools/gen_arm9v2_phone.py`. Verify the original two-way cycle counts, outputs and bus traffic after generalization.
2. **Keep a fair replacement policy.** Prefer invalid slots first. A binary-tree pseudo-LRU with accepted-hit/fill updates can reproduce the existing one-bit LRU at two ways and scale to 64. Verify its two-way equivalence including hit/fill overlap. Record any replacement-policy or pipeline-latency change and run the corresponding two-way control if it affects costs. Keep tag comparison and data selection balanced. Check the registered 104 MHz boundaries; count any added hit cycle in the result.
3. **Fix the maintenance indexing before the larger variants.** V5 packs groups of 16 dirty flags within a way and uses expressions such as `[SET_W-5:0]` and `SET_W-4`. At 32 ways there is only one 16-line group per way. At 64 ways each way has just eight sets. Use a flat 512-slot index with 32 groups of 16, or an equivalent geometry-safe banking scheme. A group may span two ways. Verify group/bit to way/set mappings and RAM read/modify/write forwarding at every size. No dropped upper ways, negative slices or padded ghost entries.
4. **Run 2 → 4 → 8 → 16 → 32 → 64.** First measure geometry alone using the existing whole-line dirty policy and geometry-safe walker. Then enable half-line dirty metadata on the same six builds and repeat, including the optimized two-way control. Keep the same fixtures, service model and scoring windows across both rows. Time the all-clean and sparse-clean cases even if the workload never issues maintenance. If the counters justify the resident-way hint or a dirty-group summary, change one feature at a time at two ways and the most informative higher-way point. Repeat across other ways if it changes their ranking. A flat or negative intermediate result still belongs in the six-point curve.

## Correctness and measurements

- Force exactly W and then W+1 lines into one set using the stride in the table, with translation warmed independently. Verify the W-line warm hit case, a replacement on overflow, highest way/last set, invalid-slot preference, and no loss of other sets. Exercise instruction and data caches separately. Check replacement against the chosen policy.
- Use a backing-memory oracle for clean-only, invalidate-only and clean/invalidate by MVA, index and whole cache, as supported by v5. Verify indexed operations reach all 512 slots, same-address aliases, reset/invalidate during outstanding work, and the existing late-fault, SWP and refill contracts. Exercise empty, sparse and fully dirty caches, both halves, partial stores, dirty eviction, stalled acknowledgments, and same-slot updates on adjacent cycles. Check exact addresses, byte enables, order, and data. A clean half must leave newer backing bytes intact. Preserve donor store allocation, ordering and fault behavior. Keep the I-cache free of dirty metadata.
- Run all 15 retained fixed-work cases on each point: six SPMark/GLES kernels, Thumb JPEG, both Monkey Ball spans, Sega Rally textured/solid/full-screen FbsCli, and all three Asphalt loops. Use both `0:0` and `2:9` I:D waits, identical warmups, two independent repeats, output/guard and wrong-output controls. Entry points and fixtures are in `tests/cpu/arm9v2_board/README.md`. Run a representative cold and warm frame or replay on the board memory path as available. Keep retired guest work and memory outputs comparable.
- Report cycles per fixed unit, I/D demand accesses and misses per 1,000 instructions, refills, dirty evictions, writeback words, cycles spent on CP15 cleaning, and demand-stall clocks. For I misses measure request to first usable instruction and to complete refill. Distinguish overlapping counters. A check-only fully associative shadow cache or a replay of the same address trace can help isolate conflict misses from compulsory/capacity misses; count its results separately from production RTL. Record CPU TLB walks separately from cache cleaning.
- Give each point its change from two ways and from the preceding point, with individual workloads alongside the geometric mean. Read the results in light of the reported v5 5.22 fps and the donor's clock-scaled 6.66 fps, an estimate of roughly 3.2 million extra system clocks per frame. Synthetic percentages do not convert directly into official SPMark FPS. At the strongest point run I-only and D-only increases against two ways to locate the gain.

## Choosing the hardware candidate

Use **5% improvement** on the delayed six-kernel geometric mean or on a representative, correctly rendered 3D frame as a working threshold for “substantial”. Report smaller changes, regressions and maintenance-only wins. Prefer fewer ways when results are within the repeat spread. Prioritize running all six simulation points even if a larger geometry fails fitting.

Use branch-scoped commits for CI fits. First compare two ways and the best candidate with the same seed, flags and debug settings. Fit additional points near a meaningful knee or timing/resource limit. Report ALMs, LABs, M10Ks, setup and hold at the 78 MHz operating point and the 104 MHz timing check, with the limiting path. For viable candidates use matched physical SPMark04 Game, FillRate and PolyCount runs against two-way v5 with the same firmware, storage state and test order; collect Contacts and Disk Access separately. Record run IDs and distinguish board measurements from simulation. Coordinate board use with Andrea before replacing a running core.

Publish raw results under `docs/evidence/` and one scorecard in `docs/` with per-case numbers, both controls, correctness status, and the recommended next build. Under a hardware or fit limitation report which evidence is still missing. Preserve the known-good two-way configuration throughout.
