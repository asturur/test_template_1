# Early ordinary Thumb word loads on 5L

**Retain the isolated Thumb candidate for timing evaluation.** The four
original JPEG cases use 2.83–3.03% fewer warm clocks. The original Sega Rally
screen scan uses 2.12–2.15% fewer clocks while executing both native FbsCli
routines. All other cases match exact 5L, including the six SPMark/GLES
kernels and the ARM stream at **224 useful starts in 224 clocks**.
The Thumb overlay remains separate from the published translation fit.
Physical area and routed timing for Thumb are unmeasured.

## Source and correctness

The control is exact unbanked `0c380ab9bae92916d297b72d6a303d251f1d49d9`.
Only `zap_predecode_main`, `zap_core` and `zap_issue_main` differ. An
eligible Thumb load must be the original last micro-op, match the
pre-sequencer decoded instruction, and normalize to unconditional
preindexed positive word LDR without writeback. The source and immediate
fields restrict the case to the two Thumb forms with low destination
registers. The actual address must be word-aligned at ALU/P1. Literal PC
loads, register-offset loads, byte/halfword loads, macro-op expansion and
unaligned early starts are excluded. The existing ARM-only adjacent-load
gate checks both latched instruction states. The ARM late-store paths
retain their Thumb exclusions and their original four-byte adjacency rule.

The existing registered P1 owner, transfer to P2, completion and
forwarding checks apply. The experiment extends the eligible load class,
without adding a retirement stage. The directed guest exercises both
halfword positions for both load forms, ADD overflow/sign, ADD zero/carry
and CMP flags. It verifies a cold offered load under 0:0, 2:9 and 0:97
with stable address until ACK. In the candidate those runs see 42, 53
and 139 actual offers for the same cold load. The exact failing P1 word
load at `90000004` returns section translation FSR `05`. Its younger
dependent ADDS was accepted in all three candidate profiles and never
retired. The guest checks the saved Thumb state and flags, resumes through
the abort handler with its destination sentinel intact, and exits back
to ARM via BX. The monitor positively verifies each excluded instruction
reaches the ALU as a load without the early class. Two identical trials
pass for both source sets in all three profiles.

All 22 ordinary CPU diagnostic runs and ten FIQ, SWP, translated-prefetch
and ordering runs match the prior exact-5L results. The first directed
trace decoder used the bench's eight-byte ARM PC subtraction on Thumb
events and failed its label audit. The corrected observer applies the
four-byte Thumb bias and checks exact producer and consumer PCs.

## Original work and trace evidence

Each case has both synthetic wait profiles, two warmups, five scored
windows, two matching repeats and a wrong-output control. The new
instrumentation reproduces every archived counter in 20 fresh exact-5L
rows (JPEG, five bounded game loops and ARM stream). The remaining controls
reuse their checked 5L rows. Source, peer and span monitor hashes match
within the comparison after removing the new passive monitor. Workload,
wrapper, payload, oracle, original retirement fingerprints and store
fingerprints match for all 42 comparisons.

The study identified 1,147 dynamically adjacent Thumb load → ADD/CMP
pairs in its original converter trace. The tested gate accepts only
the hazards whose producer is already the safe P1 owner and whose
consumer has exactly one matching late source with no intervening
writer. Across the four first scored 0:0 JPEG journals the 215, 214,
215 and 407 accepted operands all have successful pickups and useful
retirements. Aligning the original retiring sequence by ordinal shows
that the **producer-to-consumer ALU interval drops by two clocks and the
retirement interval drops by one** for every one of those measured pairs.
For example, the first checked JPEG pair at `505a9e5e → 505a9e60`
goes from seven to five clocks at the ALU and from five to four at retirement.
The earlier private lookup and P1 offer cover thousands of loads,
including ones with no eligible ADD/CMP consumer. The full Sega scan
starts 109,873 Thumb loads early per score and has zero late ADD/CMP
pickups. At 0:0, it spends 109,873 fewer clocks in data hold while retaining
the same I/D search and external transfer counts. The scan uses the same validated synthetic post-`Begin`
bitmap state and original 36,608-pixel path as experiment 1.

## Published banked-plus-third-slot smoke

The published build has its own routed area and timing comparison.
[Banked control and third-slot fit](tlb-banked-third-fit.md)

The exact published `1928aeef68cbd65699014854326c38101f5249a7`
reproduces the unbanked third-slot medians for all four JPEG cases, both
Monkey Ball patterns in both layouts, and the ARM stream, at both waits.
The two repeats, original retirement and store fingerprints and
wrong-output controls match. The ARM stream remains 224 starts in 224
clocks. Strict Verilog-2001 and the actual bank/controller unit pass
with 1,600 observed delayed-fill edges. Suppressing third-slot revocation
only at `INSTALL_WAIT` makes the fixture fail on the stale grant
immediately after entry-65 replacement.

[Exact build and test commands](../tests/cpu/thumb_early_load/README.md) · [All windows, decoded dependency timings and qualification receipts](evidence/cpu-thumb-load-20261118.json.gz)

## A/B scorecard

| Workload | Waits | 5L → Thumb clocks | Δ elapsed | Early starts low/high | Useful late pickups |
| --- | --- | ---: | ---: | ---: | ---: |
| matrix4 | 0:0 | 45,073 → 45,073 | +0.00% | 0/0 | 0 |
| matrix4 | 2:9 | 45,073 → 45,073 | +0.00% | 0/0 | 0 |
| transpose4 | 0:0 | 3,560 → 3,560 | +0.00% | 0/0 | 0 |
| transpose4 | 2:9 | 3,560 → 3,560 | +0.00% | 0/0 | 0 |
| triangle_edges | 0:0 | 23,520 → 23,520 | +0.00% | 0/0 | 0 |
| triangle_edges | 2:9 | 23,520 → 23,520 | +0.00% | 0/0 | 0 |
| fill16_frame | 0:0 | 71,259 → 71,259 | +0.00% | 0/0 | 0 |
| fill16_frame | 2:9 | 201,302 → 201,302 | +0.00% | 0/0 | 0 |
| fill16_tail | 0:0 | 1,332 → 1,332 | +0.00% | 0/0 | 0 |
| fill16_tail | 2:9 | 1,332 → 1,332 | +0.00% | 0/0 | 0 |
| fill8_tail | 0:0 | 1,647 → 1,647 | +0.00% | 0/0 | 0 |
| fill8_tail | 2:9 | 1,647 → 1,647 | +0.00% | 0/0 | 0 |
| diffuse_m10_8x8_jpeg | 0:0 | 84,353 → 81,946 | -2.85% | 1,131/1,922 | 215 |
| diffuse_m10_8x8_jpeg | 2:9 | 84,353 → 81,946 | -2.85% | 1,131/1,922 | 215 |
| diffuse_m10_8x8_random | 0:0 | 84,367 → 81,961 | -2.85% | 1,131/1,922 | 214 |
| diffuse_m10_8x8_random | 2:9 | 84,367 → 81,961 | -2.85% | 1,131/1,922 | 214 |
| diffuse_m8_8x8_random | 0:0 | 83,370 → 80,842 | -3.03% | 1,131/1,922 | 215 |
| diffuse_m8_8x8_random | 2:9 | 83,370 → 80,842 | -3.03% | 1,131/1,922 | 215 |
| diffuse_m10_16x8_jpeg | 0:0 | 166,289 → 161,578 | -2.83% | 2,283/3,778 | 407 |
| diffuse_m10_16x8_jpeg | 2:9 | 166,289 → 161,578 | -2.83% | 2,283/3,778 | 407 |
| monkey-forward | 0:0 | 34,995 → 34,995 | +0.00% | 0/0 | 0 |
| monkey-forward | 2:9 | 34,995 → 34,995 | +0.00% | 0/0 | 0 |
| monkey-reverse | 0:0 | 34,920 → 34,920 | +0.00% | 0/0 | 0 |
| monkey-reverse | 2:9 | 34,920 → 34,920 | +0.00% | 0/0 | 0 |
| monkey-forward-small | 0:0 | 34,995 → 34,995 | +0.00% | 0/0 | 0 |
| monkey-forward-small | 2:9 | 34,995 → 34,995 | +0.00% | 0/0 | 0 |
| monkey-reverse-small | 0:0 | 34,920 → 34,920 | +0.00% | 0/0 | 0 |
| monkey-reverse-small | 2:9 | 34,920 → 34,920 | +0.00% | 0/0 | 0 |
| sega-span | 0:0 | 36,996 → 36,996 | +0.00% | 0/0 | 0 |
| sega-span | 2:9 | 36,996 → 36,996 | +0.00% | 0/0 | 0 |
| sega-fill | 0:0 | 9,311 → 9,311 | +0.00% | 0/0 | 0 |
| sega-fill | 2:9 | 9,311 → 9,311 | +0.00% | 0/0 | 0 |
| sega-scan | 0:0 | 8,344,171 → 8,164,770 | -2.15% | 0/109,873 | 0 |
| sega-scan | 2:9 | 8,475,588 → 8,296,188 | -2.12% | 0/109,873 | 0 |
| asphalt-table | 0:0 | 41,753 → 41,753 | +0.00% | 0/0 | 0 |
| asphalt-table | 2:9 | 41,753 → 41,753 | +0.00% | 0/0 | 0 |
| asphalt-double | 0:0 | 19,811 → 19,811 | +0.00% | 0/0 | 0 |
| asphalt-double | 2:9 | 19,811 → 19,811 | +0.00% | 0/0 | 0 |
| asphalt-single | 0:0 | 12,731 → 12,731 | +0.00% | 0/0 | 0 |
| asphalt-single | 2:9 | 12,731 → 12,731 | +0.00% | 0/0 | 0 |
| arm-stream | 0:0 | 343 → 343 | +0.00% | 0/0 | 0 |
| arm-stream | 2:9 | 343 → 343 | +0.00% | 0/0 | 0 |
