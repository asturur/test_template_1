# Sol 6.2 High — investigate ALM savings on ngage-v5

Find the largest credible reductions in **whole-design fitted ALMs** that preserve game speed and working phone features. Also give Andrea a priced list of features he could deliberately give up. The decision we need is which change to try first, and whether removing any functionality buys enough to justify the loss.

## Establish the baseline

Use the existing `ngage-v5` checkout at `/Users/andreabogazzi/develop/NGage_MiSTer`. Read `docs/status.md` first. Use production RTL commit `61d51fe`, physical 104 MHz, DDR debugger off. The three completed fits already provide the controls. Preserve the retained RBF and other people's local changes. Use `gh` for GitHub.

| Seed | Run ID | Fitted ALMs | Worst-corner setup |
| --- | --- | ---: | ---: |
| 43 | 45072531740 | 38,017 | −2.809 ns |
| 13 | 45072535827 | 37,927 | −3.282 ns |
| 31337 | 45072539647 | 37,931 | −2.919 ns |

All three use 310 of 553 M10Ks. The 243 free blocks give us room to replace suitable register or LUT storage with RAM. Preserve the 16 KiB I-cache and 16 KiB D-cache, both DDR-backed UPP banks, LCD framebuffer, auxiliary RAM, and clock rates.

## Find where the ALMs go

1. Start with the compiled production source manifest and the Quartus map and fit reports. Rank direct ALMs by instance. Also show the inclusive cost when a whole subsystem is a removal candidate. Account for shared logic and avoid adding parent and child totals. Exclude diagnostic logic the production build already eliminates.
2. Look across CPU, caches, MMC, DMA and board peripherals. Look for expensive wide muxes, replicated control, register arrays with RAM-compatible ports, and duplicate implementations that are simultaneously live. For the strongest candidates, explain what drives the cost, which access or latency contracts matter, and how the change could reduce it. Distinguish measured savings, an upper bound and an estimate.
3. Use the existing three-M10K fetch queue from `dc1903f` as the first candidate on the current DDR-backed tree. The earlier fit reduced whole-design ALM usage from 90–91% to 86% while preserving measured cycles. The current tree also shows a fetch-area increase after fitting with identical CPU source. Reuse the existing queue design for a clean comparison and verify its area and cycle results on the current baseline. See [the original fits](v5-timing-seed44.md#independent-alternatives-on-the-round-three-baseline).

## Candidates after the fetch queue

* **Return-address stack.** The eight 32-bit entries feed an existing registered top-of-stack. Try one M10K for the backing stack, forward a new call's link, and read the pop or repair address on the existing clock edge. Verify consecutive returns, pointer wrap, misprediction repair and the first return after a stall. The predictor's branch-target payload already uses two M10Ks. [Stack RTL](../rtl/arm9v2/arm925t_phone.v#L5224)
* **MMC streaming tags.** Twelve 23-bit tags identify sequential card-cache slots, for 276 source bits. The older proposal at commit `5a65948` uses three RAM copies for current, next and prefetch lookups. Keep the four parallel metadata tags and validity flags in logic. Check tag forwarding, replacement, image remount and write invalidation, then compare block-read/write service times and persisted data. [Card cache](../rtl/ngage_mmc_card.v#L287)
* **CPU posted-write queue.** Four 68-bit entries hold address, data and byte enables. The entire unit uses 95.4 fitted ALMs on seed 43, so its savings potential is modest. A RAM implementation needs a ready head and successor to sustain consecutive acknowledgements. Compare queue ordering, simultaneous push/take, wrap, byte masks and drain cycles. [Store queue](../rtl/arm9v2/arm925t_phone.v#L13139)

Treat bit counts as source-storage sizes. Report the fitted ALM change after adding RAM ports, forwarding and control.

## Price the trade-offs

Produce two short ranked tables. One should cover ways to retain behavior, with expected ALMs saved, M10Ks spent, throughput and routing risks, and the cheapest test that could disprove each idea. The other should cover actual feature cuts. For each cut, name the exact user-visible loss, games, firmware or workflows that rely on it, what still has to be retained, and the likely **net** saving. A feature absent from our benchmark traces still needs a dependency check. If the evidence favors keeping every feature, say so.

## Qualify the leading experiment

Reproduce a current baseline before comparing. Use the existing SPMark payload benchmark workflow. Run the **entire 15-workload matrix**, including the SPMark04 cases, Thumb JPEG, Super Monkey Ball, Sega Rally and Asphalt, plus the four native PolyCount frames. Compare each workload's fixed-work cycles, retired work and output digest. Use identical warm-ups and repeats. Report the worst individual regression as well as the overall result.

Add the functional tests that exercise the changed unit. For fetch or storage, cover stalls, collisions, redirects and faults. For shared memory or peripherals, run the mixed LCD/MMC/PCM replay and check sample values, underruns, LCD data and persisted MMC readback. A CPU kernel cannot establish that a peripheral is safe to cut. For an area-only RTL rewrite, expect identical output and explain every repeatable cycle change.

Compare the fetch queue against the existing production controls using seeds 43, 13 and 31337. Sol implements and benchmarks, Luna monitors the fits, and Astra reviews the results. Report fitted ALMs and M10Ks, average and peak routing utilization, worst setup slack across corners, total negative setup slack, hold, and the limiting path for each seed. Record commit, run IDs and benchmark deltas.

If the queue reproduces a substantial whole-core area saving comparable to the earlier fit, passes the functional checks and preserves benchmark performance, recommend keeping it as the development baseline even if worst setup initially regresses. Preserve the current hardware-test RBF. Identify whether the new worst paths cross the queue and which path should be shortened next. Rank the remaining area ideas separately. Any permanent loss of functionality needs Andrea's explicit choice.
