# V5 fitted area experiments with M10K storage

The reference is the production 104 MHz UPP-DDR build at `61d51fe`, with both 16 KiB CPU caches and DDR debugging off. The experiment uses the same three fitter seeds for each revision. The area measure is whole-design fitted ALMs. Per-instance figures explain local changes and are estimates because Quartus packs logic across instance boundaries.

## What changed and what was checked

1. **Return-address stack.** `0965372` moves eight 32-bit return addresses behind the existing registered top. Calls forward the link, while pops and misprediction repair select the synchronous RAM read. The predictor comparison exercised 129,126 edges in each of two configurations, including every pointer and depth. All 15 fixed workloads and their request traces matched, as did the four native PolyCount frames at 57,514,786 clocks. [Predictor test](../tests/cpu/arm9v2_ras/)
2. **MMC stream tags.** `341a454` adds three read copies of the 12 sequential-slot tags. The four associative metadata tags stay local. The card keeps its four lookup stages. A pending tag write supplies data on collisions. All slots and 24 forced-unknown RAM collisions passed. Under three host delay profiles, the card matched the reference cycle for cycle through contention, writes, remounts and reads across EOF. The original Sega Rally CMD18 replay returned the same 32 KiB in 830,761 transfer clocks. [MMC regression](../tests/phone/mmc_card/run-stream-tags.sh)
3. **Posted-store queue.** `5700837` adds two parity banks that prepare the current and following 68-bit packets, and a saved pushed packet covers a simultaneous read/write of the same slot. The production-depth queue matched the reference for 251,347 clocks per directed/random test. Whole-CPU tests exercised byte, halfword and word stores, dependent refills, and a write-buffer drain.

4. **Instruction fetch queue.** `d127eb3` applies the fetch payload implementation from `dc1903f` on top of the return-stack and MMC changes. Forward revert `7b1b425` restored the exact `341a454` tree first. The fetch module matched the earlier version byte for byte and passed its original 8,504-cycle test, all 15 workloads and request traces, four native PolyCount frames with matching digest, four CPU contracts and the 1,201,547-clock mixed replay. [Fetch regression](../tests/cpu/arm9v2_board/run-fetch-ram.sh)

5. **All four together.** `739d3bd` adds the posted-store queue to the fetch, return-stack and MMC build at `d127eb3`. Compiled-source checks verified the fetch and predictor modules and MMC source match that parent, while the store queue matches its separately qualified implementation. The complete combination matched the parent on the 15 fixed workloads and request traces, four native PolyCount frames and digest at 57,514,786 clocks, four ordinary CPU contract configurations, ordered posted writes, and the 1,201,547-clock mixed replay. All four directed storage tests passed.

The mixed ARM9V2/SDRAM-pin replay covers LCD DMA, PCM output and persisted MMC traffic. It is independent of the CPU-only workload timings. Hardware performance on a MiSTer requires a board run.

## Matched production fits

Entries give whole-core fitted ALMs followed by the worst setup slack in ns across all four timing corners. The median column reports ALMs. The return-stack and MMC rows are successive additions. The store-only and fetch-only additions have the same return-stack-plus-MMC parent. The final row includes both queues.

| Configuration | Seed 43 | Seed 13 | Seed 31337 | Median ALMs | M10Ks |
| --- | ---: | ---: | ---: | ---: | ---: |
| DDR-backed reference | [38,017 / −2.809](https://github.com/asturur/test_template_1/actions/runs/45072531740) | [37,927 / −3.282](https://github.com/asturur/test_template_1/actions/runs/45072535827) | [37,931 / −2.919](https://github.com/asturur/test_template_1/actions/runs/45072539647) | 37,931 | 310 |
| Return stack | [37,936 / −2.630](https://github.com/asturur/test_template_1/actions/runs/45194460210) | [37,849 / −3.156](https://github.com/asturur/test_template_1/actions/runs/45194467446) | [37,840 / −2.907](https://github.com/asturur/test_template_1/actions/runs/45194474075) | 37,849 | 311 |
| Return stack + MMC | [36,978 / −2.853](https://github.com/asturur/test_template_1/actions/runs/45195347941) | [36,150 / −3.350](https://github.com/asturur/test_template_1/actions/runs/45195353698) | [36,961 / −3.868](https://github.com/asturur/test_template_1/actions/runs/45195360053) | 36,961 | 314 |
| Add posted-store queue | [37,397 / −2.889](https://github.com/asturur/test_template_1/actions/runs/45196614138) | [37,475 / −2.706](https://github.com/asturur/test_template_1/actions/runs/45196621785) | [37,451 / −2.591](https://github.com/asturur/test_template_1/actions/runs/45196629287) | 37,451 | 318 |
| Add fetch queue | [37,494 / −2.973](https://github.com/asturur/test_template_1/actions/runs/45204899334) | [37,475 / −2.694](https://github.com/asturur/test_template_1/actions/runs/45204906790) | [37,481 / −3.298](https://github.com/asturur/test_template_1/actions/runs/45204914742) | 37,481 | 317 |
| All four | [37,366 / −2.851](https://github.com/asturur/test_template_1/actions/runs/45206755388) | [37,286 / −2.803](https://github.com/asturur/test_template_1/actions/runs/45206762467) | [37,364 / −2.852](https://github.com/asturur/test_template_1/actions/runs/45206768879) | 37,364 | 321 |

The return stack reduced ALMs and improved setup on all three matched seeds. The return stack plus MMC had the lowest median area at 36,961 ALMs, 970 below the DDR-backed reference. Its median setup was −3.350 ns. Each queue lowered its own fitted ALM count and raised whole-core ALMs on all three seeds when added separately to that configuration.

Adding the posted-store queue to the fetch build saved 117–189 ALMs per matched seed. The all-four median was 37,364 ALMs, 567 fewer than the DDR-backed reference and 403 more than return stack plus MMC. It used 321 of 553 M10Ks, leaving 232 free. Its median setup improved to −2.851 ns from −2.919 ns for the DDR-backed reference and −2.973 ns for the fetch build. Seed 13 improved against the DDR reference and was 0.109 ns slower than the fetch build at the same seed.

All 18 fits passed hold, recovery, removal and minimum pulse width across the four corners. All missed setup at 104 MHz. Seed 13 had the best all-four fit at −2.803 ns and 37,286 ALMs. Its archived image is `build/fit/v5-104mhz-739d3bd-seed13/ngage1.rbf`, SHA-256 `688ab8a44a8342b3973558fe12dcb08af2c75d3822d4d5251474f64085821061`. The best setup in the series was the earlier posted-store image at seed 31337, −2.591 ns, archived at `build/fit/v5-104mhz-5700837-seed31337/ngage1.rbf`. [Per-corner and per-instance evidence](evidence/v5-alm-storage-fits-20261123.json)
## Register banks selected for 104 MHz experiments

Use the all-four build at `739d3bd` as the timing reference for further RAM experiments. At the same seeds, its setup margin improved over the return-stack-plus-MMC build by 0.002, 0.547 and 1.016 ns. The difference between their median slacks is 0.499 ns. The seed spread makes a fixed improvement from the RTL alone uncertain.

* **CPU line-refill buffer.** The eight 32-bit words reside in a wrapper with 292 direct fitted registers and zero M10Ks on seed 13. Try odd/even 4×32 banks with the next word pre-read and a bypass for a word consumed as soon as it arrives. A wide beat writes both banks. Two narrow beats assemble a single word. Seed 43 shows a −1.693 ns path from the consumer index into response data. The −2.803 ns seed-13 limit starts at retimed acknowledgement logic and continues through the I-cache command selection to the Wishbone merger address. Moving the data has no demonstrated effect on that path. Check first-word latency, sustained one-word-per-clock consumption, stalls, errors and scalar fallback against the existing RTL. [Refill buffer](../rtl/ngage_cpu.sv#L227)
* **ICU probe register bank.** Five 32-bit words accept byte writes and must read zero after warm reset. In the seed-13 worst-corner report, 33 of the first 1,000 setup paths end at these registers. The worst reaches −1.445 ns. These endpoints are absent from the other two seeds' first 1,000. A trial needs to supply the RAM read address early enough to keep the existing response cycle and preserve the probe-enable and reset rules. [Probe registers](../rtl/ngage_icu_extra.v#L28)

* **MMC host byte FIFO.** All 128 bits of the 16-byte host FIFO survive in registers. Three seed-13 paths end in its data array, the worst at −1.404 ns. Four interleaved byte banks with head prefetch could support the existing four-byte bus access. Check wrap, simultaneous bus/card access and the number of clocks to transfer a sector. [Host FIFO](../rtl/ngage_mmc_host.v#L222)
* **Small-page TLB replacement bits.** Each two-way small-page TLB uses one victim bit for each of 256 sets. The lookup can potentially share the existing walk address stage. Verify reset value, same-set collisions and consecutive walks to the same page. No victim-bit endpoint appeared in the three worst-corner top-1,000 reports, so this is primarily an area candidate. [Replacement state](../rtl/arm9v2/arm925t_phone.v#L14973)

Keep the refill trial limited to data storage. The earlier `d4edf9b` trial changed both refill acknowledgement and scalar completion timing, which makes it unsuitable as a control for the buffer alone. Compare each candidate separately at 104 MHz using seeds 43, 13 and 31337. Compare the per-seed worst setup and total negative setup slack, then inspect which path families improved or replaced them. Check hold and benchmark cycles before choosing a new reference. The matched fits below give the measured results.

## Independent changes for a later combined fit

All candidates use the exact all-four production RTL as their parent for comparison. The forward reverts preserve every candidate commit. Apply the selected experiment commits in the table to reproduce a combination. The three seed columns give fitted ALMs and worst setup slack in ns. The last columns report median ALMs, total M10Ks and median core setup TNS in ns.

| Trial and commit | Seed 43 | Seed 13 | Seed 31337 | Median ALMs | M10Ks | Median TNS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| All-four control `739d3bd` | [37,366 / -2.851](https://github.com/asturur/test_template_1/actions/runs/45206755388) | [37,286 / -2.803](https://github.com/asturur/test_template_1/actions/runs/45206762467) | [37,364 / -2.852](https://github.com/asturur/test_template_1/actions/runs/45206768879) | 37,364 | 321 | -5,849.1 |
| CPU refill buffer `13a471b` | [36,176 / -2.895](https://github.com/asturur/test_template_1/actions/runs/45230489919) | [36,148 / -3.081](https://github.com/asturur/test_template_1/actions/runs/45230488647) | [36,166 / -2.779](https://github.com/asturur/test_template_1/actions/runs/45230489549) | 36,166 | 323 | -6,621.0 |
| ICU probe bank `fa1b2f1` | [36,151 / -2.863](https://github.com/asturur/test_template_1/actions/runs/45231285727) | [36,304 / -3.278](https://github.com/asturur/test_template_1/actions/runs/45231286010) | [36,311 / -2.932](https://github.com/asturur/test_template_1/actions/runs/45231285784) | 36,304 | 321 | -7,837.6 |
| MMC host FIFO `d790e96` | [37,052 / -2.980](https://github.com/asturur/test_template_1/actions/runs/45231987887) | [37,140 / -2.713](https://github.com/asturur/test_template_1/actions/runs/45231987701) | [37,079 / -2.993](https://github.com/asturur/test_template_1/actions/runs/45231987009) | 37,079 | 325 | -5,838.2 |
| TLB victim bits `723e2b7` | [35,641 / -3.088](https://github.com/asturur/test_template_1/actions/runs/45232753533) | [35,645 / -3.089](https://github.com/asturur/test_template_1/actions/runs/45232752956) | [35,680 / -2.999](https://github.com/asturur/test_template_1/actions/runs/45232753430) | 35,645 | 323 | -8,282.5 |

All four RAM experiments reproduced the 15 fixed workloads and their request traces, four native PolyCount frames and the mixed replay. All seeds produced RBFs and passed hold, recovery, removal and minimum pulse checks. Every seed missed 104 MHz setup. The whole-design ALM deltas include changes in fitting and packing outside each edited module. An actual combined fit is needed to measure their joint effect. [Run manifests and simulation checks](evidence/v5-104-bram-mix-qualification.json) · [Per-corner timing, routing and instance counts](evidence/v5-104-bram-mix-fits.json)

For a timing-led combination, the CPU refill buffer offers the best area trade in this round. It saved 1,138–1,198 ALMs per matched seed for two M10Ks and a 0.044 ns lower median setup slack. The ICU probe bank saved 982–1,215 ALMs by reusing existing RAM rows, with no new M10Ks. Its setup slack worsened on all three seeds. The TLB victim table gave the largest area saving (1,641–1,725 ALMs for two M10Ks) and the largest median setup regression (0.237 ns). Keep all three as independent options. The MMC FIFO gave the best single new setup result at −2.713 ns on seed 13, an improvement of 0.090 ns at that seed, while the other two seeds regressed. Its four new M10Ks saved just 146–314 ALMs. None of these substitutions improved median worst setup over the all-four control.

The best-setup RBF for each variant is archived under `build/fit/v5-104mhz-<commit>-seed<seed>/ngage1.rbf`. Copies are available for refill `13a471b` seed 31337, ICU `fa1b2f1` seed 43, MMC `d790e96` seed 13 and TLB `723e2b7` seed 31337. Hardware validation is pending. The RTL at the end of the series (`903efe1`) matches the original all-four control.

## Parallel work and the cost of another pipeline stage

The throughput control is `739d3bd` at 104 MHz, with both 16 KiB caches, a 32 KiB flash cache, the production streaming SDRAM model, MMC divided by three and 64 Hz guest ticks. The store-list observer reproduced all 15 fixed-work windows and request summaries, and every frame, retirement count and output digest in the four-frame PolyCount control. A pair counts when two disjoint adjacent words in one ARM or Thumb store list reach the same writable resident cache line.

| Work on the unmodified CPU | Eligible store pairs | Most cycles recoverable per window |
| --- | ---: | ---: |
| Four native PolyCount frame intervals | 911,218 in 57,508,371 clocks | 1.58% overall |
| Thumb JPEG block | 722 | 2.04% of the median window |
| Sega Rally full scan | 18,316 | 0.76% |
| GLES triangle edges | 64 | 0.52% |
| SPMark matrix | 48 | 0.28% |
| Other 11 fixed workloads | 0 | 0% |

The ceiling assumes one elapsed clock saved for every counted pair. A real design needs the next source register ahead of issue, two different values at the line write port, forwarding for both, and precise serial fallback for a fault or cross-line access. The other eleven workloads get no offsetting benefit from store-list pairing. At the same clock and fixed guest work, compare the baseline, parallel work alone, the extra pipeline stage alone, and both together. Count executed guest instructions as well as cycles, and check the mixed LCD/audio/MMC replay separately. [Counts for each scored window and native frame](evidence/v5-104-parallel-store-census.json)

### One extra clock on data-line admission

In a separate simulation A/B the alternate samples the D-cache line address in a register and waits one clock before offering it. The instruction and scalar paths use the original admission. A directed always-ready test checked the critical word and the following seven ACKs keep their spacing after grant. Both legs of the full replay ran the same binary with a simulation switch and matched all output checks. This isolates cycle cost; the alternate has no routed timing measurement. [Simulation-only patch](evidence/v5-104-d-refill-admission-sim.patch) · [Per-window and per-frame results](evidence/v5-104-d-refill-admission.json)

Across the four PolyCount frame intervals the extra stage cost 30,030 clocks out of 57,508,371 (+0.0522%). Sega Rally scan cost 5,101 clocks at its warm median (+0.213%). Recovering that time with paired stores would require about 28% of its 18,316 eligible pairs to save a full elapsed clock. The full-frame 16-bit fill cost 176 clocks, Asphalt table cost 20 and Asphalt double lookup cost three. Those three had zero eligible store-list pairs. Nine other medians tied, and two moved down by nine and six clocks as memory scheduling changed. Keep this stage as an option if a fit demonstrates slack in the data admission path. A regression of about 0.05–0.2% is an acceptable trade for improved timing. Record the cost on every workload and proceed to evaluate the fit. Recovering cycles on these three workloads is additional upside.

A second counter checked whether the eight-word refill buffer had two aligned words ready on the same ACK. Four PolyCount frames produced 66,320 instruction pairs and 3,064 data pairs, all from wide responses. Over 5.8 million narrow word ACKs had zero eligible pairs. Even an ideal dual-word consumer could remove at most 69,384 delivery edges under that schedule, about 0.121% of frame time if every removed edge advanced retirement. We observed no first ACK of a pair in the CPU's exposed-wait category. That check cannot establish what the second edge would have saved.

### Preparing the next sequential instruction-line request

In the checked four frames, 532,812 of 691,932 eligible narrow instruction fills were true sequential fetches starting at word zero. A hint formed in the final two words of a line matched 359,405 later checked misses. Requiring the memory port to stay idle until demand gives a hindsight ceiling of 1.50% of frame clocks. Starting on the first free slot would have encountered later data requests on 72,206 matches. The native fixture had no live LCD traffic. None of the 15 fixed workloads had a narrow SDRAM instruction fill in its timed windows.

A smaller experiment would register the next-line descriptor locally and send it only after the normal cache, translation and permission checks confirm the miss. This preserves demand arbitration for D-cache, locked and LCD requests. On frame zero, additionally requiring the same 1 KiB permission subpage gives this preparation-only design a modeled ceiling of 77,353 clocks (0.54%). It has no measured IPC or setup result. [Sequentiality, bus availability and service bounds](evidence/v5-104-sequential-instruction-hints.json)

The physical timing question depends on *which edge* takes that extra clock. Seed 43 has a −1.936 ns path through the line-request classification and eager SDRAM grant to the physical SDRAM address. Registering the data-side offer could help its data requests there. In contrast, the seed-13 −2.803 ns path starts at refill acknowledgement, passes through I-cache beat acceptance, and ends at the Wishbone address. Registering request admission leaves that return path in place. A separate timing candidate would register the accepted native line response and prepare the next word while the current one retires. That trial would need its own first-word and elapsed-cycle measurements, especially on the instruction side. The measured D-only cost applies to admission alone. [Refill and scalar acknowledgement](../rtl/ngage_cpu.sv#L245) · [SDRAM eager grant](../rtl/ngage_mister.v#L630)

### Reusing a checked Thumb halfword

The working prototype keeps a valid bit, a 30-bit word address and the upper 16-bit instruction from a checked I-cache fetch. When a predicted-taken conditional branch in the lower half instead falls through, the frontend can put the saved halfword at the fetch queue head. It restricts reuse to supported instructions and discards the entry on redirects, retries, exceptions, fills and context or maintenance barriers. The registered correction still determines ownership.

| 104 MHz replay | All-four control | D admission stage only | Thumb recovery only | Both |
| --- | ---: | ---: | ---: | ---: |
| Sega Rally scan, median cycles | 2,395,767 | 2,400,868 | 2,377,506 | 2,382,348 |
| Native PolyCount, clocks inside four frames | 57,508,371 | 57,538,401 | 57,508,371 | 57,538,401 |

Sega used the saved instruction 18,305 times in each scored window. The combined build finished 13,419 clocks ahead of the control (0.560%) and 18,520 ahead of the D-stage build. Thumb recovery alone changed no window in the other 14 payloads or the four PolyCount frames. All four legs matched ordered guest retirements and data access digests, and the separate control-flow contracts matched 21 ordered MMIO transactions in each mode. The matched FPGA fits below measure the cost of putting this choice on the redirect path. [Four-way results and digest checks](evidence/v5-104-thumb-recovery-stage-comparison.json)

### Registering the native data-cache return

Two implementations register a response word together with valid, error, terminal and trust information for native D-cache fills. I-cache, scalar and MMIO replies keep their existing path. The first reads a fully buffered word into the output register. It cost 0.057% over four native frames, 0.216% in Sega scan, and 2.834% in the full-frame 16-bit fill. The buffered version remains available for a comparison against simpler register input logic.

The second captures a newly completed narrow word or the appropriate half of an arriving wide beat directly into that same output register when it is due next. It can also load a previously buffered word. This keeps a real register between data arrival and the D-side consumer, preserves first-word latency and replaces a retired word on the same clock. All 15 workloads and their SDRAM request traces, four native frames, four CPU contract modes and the mixed replay matched the all-four control cycle for cycle. This is the response variant used in the matched fits below. A common final mux still serves immediate I-cache and scalar replies. [Matched response-head measurements](evidence/v5-104-native-d-line-return.json)

The local replay patches are independently applicable on the all-four RTL. The two D-return implementations are alternatives. The same-edge head and the refill-buffer RAM conversion edit neighboring storage logic, so their eventual combination needs an integrated merge and a fresh collision/first-word test. [Thumb recovery](evidence/v5-104-thumb-fallthrough.patch) · [Thumb tests](evidence/v5-104-thumb-fallthrough-tests.patch) · [Buffered D return](evidence/v5-104-d-return-buffered.patch) · [Same-edge D return](evidence/v5-104-d-return-same-edge.patch) · [D-return tests](evidence/v5-104-d-return-tests.patch)

## Routed D-cache return and Thumb recovery

Both trials are independently applicable to the all-four 104 MHz CPU. Three matched seeds used production clocks, the existing 16 KiB I/D caches and DDR debugging off. Each row lists worst setup slack across four corners. TNS is the reported core setup total negative slack. All three configurations used 321 M10Ks.

| Trial | Seed 43 | Seed 13 | Seed 31337 | Median setup | Median TNS | Median ALMs |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| All-four baseline `739d3bd` | [-2.851](https://github.com/asturur/test_template_1/actions/runs/45206755388) | [-2.803](https://github.com/asturur/test_template_1/actions/runs/45206762467) | [-2.852](https://github.com/asturur/test_template_1/actions/runs/45206768879) | -2.851 ns | -5,849.1 ns | 37,364 |
| Same-edge D return `25e1208` | [-3.187](https://github.com/asturur/test_template_1/actions/runs/45241891082) | [-3.456](https://github.com/asturur/test_template_1/actions/runs/45241891134) | [-3.242](https://github.com/asturur/test_template_1/actions/runs/45241890928) | -3.242 ns | -8,720.0 ns | 36,401 |
| Thumb recovery `27bd8bf` | [-3.083](https://github.com/asturur/test_template_1/actions/runs/45242151063) | [-3.205](https://github.com/asturur/test_template_1/actions/runs/45242151078) | [-2.870](https://github.com/asturur/test_template_1/actions/runs/45242150714) | -3.083 ns | -6,676.2 ns | 37,126 |

**D return.** On seed 13, the control had 63 of its 1,000 worst 100 °C paths originating at refill ACK and passing through data-cache beat selection. The trial had zero from the named ACK or new head signals through that selection in this export. The critical data-cache trust endpoint was still −2.632 ns, compared with −2.618 ns originally. Its limiting source changed to the Wishbone strobe. Whole-core worst setup also moved to a path from the SDRAM scheduler into the Wishbone address at −3.456 ns. The D-return design saved 885–990 ALMs across the seeds and preserved benchmark cycles. Park it as an area alternative for a future combined fit.

**Thumb recovery.** At the same clock the implementation saved 18,261 cycles in the Sega Rally scan and tied the other 14 fixed-work cases and four PolyCount frames. Named recovery logic is on the hot-corner worst path for seeds 43 and 31337, and on path five for seed 13. All three end at the branch predictor register `read_valid_bit`. The seed-13 report shows writeback feeding the recovery choice before BTB indexing and valid-bit selection. The best Thumb seed, 31337, gave up 0.018 ns against the matching control. Preserve this version for its IPC gain. The next separated experiment is to prepare the two possible predictor lookups in parallel and select their results late, or carry a prequalified recovery decision with the branch. Verify explicit kill, reset, maintenance and exception priority, then repeat the cycle and matched-seed checks.

The all-four build remains the timing reference. Keep the candidate commits for recombination. Both new triplets produced bitstreams and passed hold, recovery, removal and minimum pulse width across the reported corners. All six missed setup. The best D-return image is `build/fit/v5-104mhz-25e1208-seed43/ngage1.rbf`. The best Thumb image is `build/fit/v5-104mhz-27bd8bf-seed31337/ngage1.rbf`. Hardware behavior is unverified. The numerical evidence includes all four corners and the named paths present in the 1,000-path hot-corner export. Paths below that cutoff and logic renamed by synthesis are outside the named-path counts. [Fitted results and path counts](evidence/v5-104-d-return-thumb-fits.json)

## Parallel predictor validity for Thumb recovery

Commit `f7d5746` computes the normal and recovered branch-target-buffer validity lookups independently. It captures the next aligned word address when saving the Thumb halfword, reads the current validity and same-edge write forwarding for both addresses, and selects between the sampled bits after the lookup edge. The production trial consists of the exact Thumb recovery replay `e86bd00` plus the isolated parallel-lookup commit. The forward revert `a041985` restored the all-four production tree.

The 30,006-clock differential test covered normal and recovered lookups, same-edge collisions, folded tag aliases, held lookups, clears and resets. The 15 fixed workloads and SDRAM request traces, four native PolyCount frames, four CPU contracts, and mixed LCD/PCM/MMC replay matched the earlier Thumb design. The Sega Rally scan took 2,377,506 clocks, retaining its 0.762% saving against the all-four build.

| 104 MHz physical fit | Seed 43 | Seed 13 | Seed 31337 | Median setup | Median core TNS | Median ALMs |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| All-four control | −2.851 ns | −2.803 ns | −2.852 ns | −2.851 ns | −5,849 ns | 37,364 |
| Original Thumb recovery | −3.083 ns | −3.205 ns | −2.870 ns | −3.083 ns | −6,676 ns | 37,126 |
| Parallel predictor validity | [−2.927 ns](https://github.com/asturur/test_template_1/actions/runs/45253654162) | [−3.130 ns](https://github.com/asturur/test_template_1/actions/runs/45253653661) | [−3.147 ns](https://github.com/asturur/test_template_1/actions/runs/45253653778) | −3.130 ns | −9,715 ns | 36,977 |

**Local outcome.** In the hot-corner top 1,000, the ordinary predictor-valid endpoint improved from −3.083 to −1.806 ns on seed 43 and from −2.870 to −2.191 ns on seed 31337. On seed 13 it had been −3.109 ns and dropped below the reporting cutoff. No named path launching from either new validity/selection register appeared among the worst 1,000 in these reports. Absence gives no exact slack. On seed 31337 the hot-corner worst path still traversed the Thumb recovery choice, now to the fetch PC, at −3.091 ns. At −40 °C that seed's limiting path instead ended at the TLB hit check at −3.147 ns.

**Whole-core decision.** Parallel lookup improved matched setup by 0.156 ns and 0.075 ns on seeds 43 and 13, then lost 0.277 ns on seed 31337. Median setup and total negative slack both worsened against the original Thumb implementation. All three used 321 M10Ks, produced bitstreams, passed hold/recovery/removal/minimum pulse checks, and missed 104 MHz setup. Park the new design as a mix-and-match option. Retain the all-four timing baseline and the original Thumb implementation as the stronger standalone speed variant. If revisiting the Thumb logic, measure whether the saved halfword can enter the queue while the ordinary redirect address launches independently, with explicit duplicate cancellation. That changes the delivery schedule and needs a fresh Sega scan benchmark.

The best parallel-lookup bitstream is `build/fit/v5-104mhz-f7d5746-seed43/ngage1.rbf`. Its board behavior is unverified. [Functional checks, per-corner timing, path counts and RBF hash](evidence/v5-104-thumb-parallel-valid.json)

## Independent Thumb redirect and duplicate cancellation

Commit `e6c352c` lets the ordinary redirect launch the actual target immediately while a saved, already checked Thumb halfword enters the decode queue on the same edge. A tag follows the redundant fetch through both stages and suppresses its prediction, retry and delivery. The next real instruction keeps its normal fault and retry behavior. The patch applies to the original Thumb experiment `27bd8bf`. The catalog also verifies the complete stack from the all-four control `739d3bd`. Production RTL returned to that control at `03158d3`. [Patch and replay instructions](experiments/v5-performance/README.md) · [Benchmarks and directed checks](experiments/v5-performance/thumb-ordinary-redirect-replay.json)

| Implementation | Sega Rally scan clocks | Seed 43 setup | Seed 13 setup | Seed 31337 setup | Median setup | Median core TNS | Median ALMs |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| All-four timing control | 2,395,767 | −2.851 ns | −2.803 ns | −2.852 ns | −2.851 ns | −5,849 ns | 37,364 |
| Original saved Thumb halfword | 2,377,506 | −3.083 ns | −3.205 ns | −2.870 ns | −3.083 ns | −6,676 ns | 37,126 |
| Parallel predictor lookup | 2,377,506 | −2.927 ns | −3.130 ns | −3.147 ns | −3.130 ns | −9,715 ns | 36,977 |
| Independent redirect | 2,395,766 | [−2.900 ns](https://github.com/asturur/test_template_1/actions/runs/45282574954) | [−2.974 ns](https://github.com/asturur/test_template_1/actions/runs/45282574801) | [−3.143 ns](https://github.com/asturur/test_template_1/actions/runs/45282574309) | −2.974 ns | −7,916 ns | 36,659 |

**Speed and area.** The other 14 fixed workloads and four native PolyCount frames matched all-four and original Thumb cycle for cycle. The four frames totalled 57,508,371 clocks. Ordered retirements, guest-visible data, the four CPU contracts and the mixed LCD/PCM/MMC replay passed. Refetching the target cost 18,260 clocks on the Sega scan against original Thumb. The new implementation saved 705 median ALMs versus all-four at the same 321 M10Ks, while giving up 0.123 ns of median setup. Keep the patch for an area-constrained combination. Keep original Thumb for Sega speed and all-four for timing.

**Where the critical path moved.** Across the three 100 °C exports, zero of the worst 1,000 paths per seed ran through the named halfword reuse decision to the fetch PC or the predictor. The previous parallel variant had 11, 3 and 16 such paths to the fetch PC alone. The new queue-head paths still appear, with worst slack of −2.201, −2.268 and −2.578 ns. The worst setup on seeds 43 and 13 ran from decode write-through data into the execute operand register. Seed 31337 instead ran from CPU writeback through arbitration to DDR sector-transfer cancellation. All three missed 104 MHz setup and passed the reported hold, recovery, removal and minimum pulse checks at all four corners. The best bitstream, seed 43, is archived at `build/fit/v5-104mhz-e6c352c-seed43/ngage1.rbf`. Hardware behavior remains unverified. [Per-corner and routed evidence](evidence/v5-104-thumb-independent-redirect-fits.json)

**Next timing experiment.** Simplify the DDR burst bounds check on the all-four control. The named validity check and its address adder appeared in all twelve hot-corner exports in this comparison. On the new seed 31337, the worst path traversed 15 carry cells before reaching request validation. A burst is aligned and limited to 64 eight-byte beats. Only a start within the final 512 bytes of the 32-bit address space can overrun it. Detect that region in parallel with a small check of remaining beats, keeping a burst that ends exactly at the boundary legal. This preserves the existing request edge. Prove the predicates equivalent across all addresses and counts, then compare the same three seeds and workloads. The two decode-to-execute limits give this isolated change a clear test of how much it can improve whole-core timing.

## DDR burst bounds

Commit `b6d8981` replaces the 33-bit end-address addition with a final-512-byte region decode and a seven-bit beat check. The production sector adapter's fixed 64-beat count reduces the local calculation to checking whether the starting offset is zero. Z3 proved admission equivalence across all addresses, counts and modes, and RTL tests checked 98,304 descriptors per fill setting and live boundary transfers. All 15 workloads and all four native PolyCount frames match the all-four control cycle for cycle, with the same output and ordered-event digests. The mixed LCD, PCM and MMC replay matched 1,201,547 clocks. [Exact patch, replay receipt and test commands](experiments/v5-performance/ddr-burst-bounds.md)

| 104 MHz production setup | All-four `739d3bd` | DDR bounds `b6d8981` |
| --- | ---: | ---: |
| Seed 43 | −2.851 ns | [−3.277 ns](https://github.com/asturur/test_template_1/actions/runs/45291134648) |
| Seed 13 | −2.803 ns | [−2.742 ns](https://github.com/asturur/test_template_1/actions/runs/45291139958) |
| Seed 31337 | −2.852 ns | [−2.978 ns](https://github.com/asturur/test_template_1/actions/runs/45291143845) |
| Median setup | −2.851 ns | −2.978 ns |
| Median core setup TNS | −5,849.103 ns | −7,256.958 ns |
| Median ALMs | 37,364 | 37,334 |
| M10Ks on every seed | 321 | 321 |

The worst reported sector result endpoint (`done`, `error` or `cancelled`) improved on all six matched slow corners. The hot and cold gains were +0.090 and +0.227 ns on seed 43, +0.248 and +0.700 ns on seed 13, and +0.250 and +0.338 ns on seed 31337. In the three hot top-1,000 exports, the maximum local carry cells on those result paths fell from 10, 19 and 8 to zero in each. These counts describe the exported paths. All three builds missed setup and passed hold, recovery, removal and minimum pulse checks at all four corners. The best DDR bitstream is seed 13 at `build/fit/v5-104mhz-b6d8981-seed13/ngage1.rbf`. Its SHA-256 is `97ed5eacf5cd18dcf3e9f196abc8f55fa8f987ebfb6a776f67d589654fe2b097`. Board behavior remains unverified. [Matched fit manifests, path counts and bitstream hash](evidence/v5-104-ddr-burst-bounds-fits.json)

Keep `b6d8981` active for the next combination because it removes the targeted carry chain with no measured cycle cost. Keep `739d3bd` as the matched timing control. Seed 13 gained 0.061 ns for the whole core, with the worst path from the D-side TLB's `o_fsr[1]` to the D-cache FSM's `o_lock_any`. Seed 31337 was limited by Wishbone `o_wb_cyc` to SDRAM scheduler `cmd_addr[12]`.

The next timing target is execute operand packet readiness. Paths through the routed `o_ready_payload` cell to an execute `a` register appeared 44, 111 and 7 times in the hot top 1,000 for seeds 43, 13 and 31337. Their worst slack was −3.277, −2.094 and −2.072 ns, respectively. Try registering independent readiness conditions ahead of operand delivery while keeping same-cycle load forwarding, packet holds and flush behavior.

## Execute operand readiness

Commit `c492853` computes complete execute admission decisions for the two W-load outcomes and selects with the live hit. The 20,000-cycle execute differential compared all stage outputs and held state. It covered same-cycle load release and A-packet replacement, register-shift preparation, priority, stalls and redirects. Four board profiles, all 15 fixed workloads, four native PolyCount frames and the mixed LCD, PCM and MMC replay matched the DDR control. The four measured frame windows totalled 57,508,371 clocks. [Exact patch, differential and replay receipt](experiments/v5-performance/execute-ready.md)

| 104 MHz production fit | DDR bounds `b6d8981` | Execute readiness `c492853` | Setup change |
| --- | ---: | ---: | ---: |
| Seed 43 setup | −3.277 ns | [−2.668 ns](https://github.com/asturur/test_template_1/actions/runs/45301331404) | +0.609 ns |
| Seed 13 setup | −2.742 ns | [−2.954 ns](https://github.com/asturur/test_template_1/actions/runs/45301335032) | −0.212 ns |
| Seed 31337 setup | −2.978 ns | [−2.666 ns](https://github.com/asturur/test_template_1/actions/runs/45301339080) | +0.312 ns |
| Median setup | −2.978 ns | −2.668 ns | +0.310 ns |
| Median core setup TNS | −7,256.958 ns | −5,760.244 ns | |
| Median ALMs | 37,334 | 37,297 | |
| M10Ks on every seed | 321 | 321 | |

Of the 1,000 detailed hot setup paths per seed, paths that cross named readiness logic and end at an execute packet register fell from 44, 111 and 7 to 13, 18 and zero. The worst remaining listed paths were −2.300 and −1.949 ns on seeds 43 and 13. In the exported paths at all four corners, none launched from a named W hit, short hit or short trust register and ended at an execute packet register. A path outside the export has no measured slack in this comparison. [Matched path and source evidence](evidence/v5-104-execute-ready-fits.json)

The largest remaining setup delay on seed 43 went from the D-cache data RAM read through forwarded shift amount and barrel shifter into the execute packet. Seed 13's worst path ran from the UPP bridge response through I-cache beat acceptance to the Wishbone merger's next native-line flag. Seed 31337 reached −2.666 ns on a path from CP15 `o_sr[0]` to the D-side TLB fault status `o_fsr[3]`. All three fits missed setup and passed hold, recovery, removal and minimum pulse checks at all four corners. Keep `c492853` active. The best bitstream, seed 31337, is archived at `build/fit/v5-104mhz-c492853-seed31337/ngage1.rbf`. Its SHA-256 is `892fd9e84eafcca5818a6173fc413a2b01b5ac0c01a9d4e55c88bfec6b91ca5a`. It has no board validation. [Per-corner fits and bitstream hash](evidence/v5-104-execute-ready-fits.json)

The next standalone timing experiment is to precompute CP15 S/R-dependent access permissions on the same edge that updates CP15 state. Let those bits settle in parallel with descriptor and domain checks. Keep fault codes, fault ordering and cache-hit latency precise. Seed 31337 is the direct timing target. Repeat the other seeds to detect shifts into the other limiting paths.
